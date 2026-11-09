function Get-ITGroupAssignment {
    <#
    .SYNOPSIS
        Lists the Intune policies, profiles, scripts, update profiles and apps assigned to a group.

    .DESCRIPTION
        The reverse of Get-ITPolicyAssignment: "what does this group get?". Every supported
        Intune object type is read once (with its assignments) and the rows that target the
        group are returned, both inclusions and exclusions.

        Assignments to the groups this group is nested in also reach its members, so by default
        those are included as well: ViaGroupName shows the group the assignment actually
        targets and Via is 'Direct' or 'Parent group'. Use -DirectOnly to skip them.
        -IncludeAllTargets adds the assignments to 'All devices' / 'All users', which reach
        every member too.

        Piping several groups reads the Intune objects only once.

    .PARAMETER Id
        Group object ID or exact display name. Accepts pipeline input by property name (id / GroupId).

    .PARAMETER PolicyType
        Object types to check. Default: all (Compliance, DeviceConfiguration, SettingsCatalog,
        Script, Remediation, UpdateRing, FeatureUpdate, DriverUpdate, App).

    .PARAMETER DirectOnly
        Only assignments that target the group itself, not the groups it is nested in.

    .PARAMETER IncludeAllTargets
        Also list assignments to All devices / All users.

    .EXAMPLE
        Get-ITGroupAssignment -Id 'SG-Intune-Pilot-Devices'

        Everything the pilot device group gets, including through parent groups.

    .EXAMPLE
        Get-ITGroupAssignment -Id 'SG-Intune-Old-Pilot' -DirectOnly | Measure-Object

        Check before Remove-ITGroup: is the group still used in Intune?

    .EXAMPLE
        Get-ITGroup -Name 'SG-Intune-*' | Get-ITGroupAssignment -PolicyType App -DirectOnly |
            Select-Object GroupName, ObjectName, InstallIntent, Intent

        App assignments of all Intune groups.

    .OUTPUTS
        IntuneToolkit.GroupAssignment

    .NOTES
        Graph permission : Group.Read.All, DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All (apps)
        Graph endpoint   : GET <object list>?$expand=assignments, GET /groups/{id}/transitiveMemberOf
        API version      : beta (Intune objects), v1.0 (groups)

    .LINK
        https://learn.microsoft.com/graph/api/resources/intune-graph-overview
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.GroupAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateSet('Compliance', 'DeviceConfiguration', 'SettingsCatalog', 'Script', 'Remediation',
            'UpdateRing', 'FeatureUpdate', 'DriverUpdate', 'App')]
        [string[]]$PolicyType,

        [switch]$DirectOnly,

        [switch]$IncludeAllTargets
    )

    begin {
        $types = @($PolicyType)
        if (-not $PolicyType) { $types = @(Get-ITPolicyTypeInfo | ForEach-Object { $_.PolicyType }) }
        $infos = @($types | ForEach-Object { Get-ITPolicyTypeInfo -PolicyType $_ })

        $scopes = @('Group.Read.All') + @($infos | ForEach-Object { $_.ReadScope }) | Select-Object -Unique
        Assert-ITGraphConnection -RequiredScope $scopes

        # Loaded on first use, then reused for every group in the pipeline
        $rows = $null
        $filterNames = $null

        $load = {
            $list = New-Object -TypeName System.Collections.Generic.List[object]
            foreach ($info in $infos) {
                # One request per type: the assignments come with the objects ($expand).
                # If Graph rejects the expand, or silently leaves it out, read them per object.
                $expanded = $true
                $objects = @()
                try {
                    $objects = @(Get-ITIntuneObject -TypeInfo $info -Expand 'assignments' -ErrorAction Stop)
                    if (@($objects | Where-Object { -not $_.PSObject.Properties['assignments'] }).Count) { $expanded = $false }
                }
                catch {
                    Write-ITLog -Level Warning -Message ("{0}: `$expand=assignments failed ({1})." -f $info.PolicyType, $_.Exception.Message)
                    $expanded = $false
                }
                if (-not $expanded) {
                    Write-ITLog -Message ('{0}: reading assignments per object.' -f $info.PolicyType)
                    $objects = @(Get-ITIntuneObject -TypeInfo $info -IncludeAssignment)
                }

                foreach ($o in $objects) {
                    # -IncludeAssignment gives converted assignments; $expand gives raw Graph objects
                    # (PowerShell property names are case-insensitive: 'Assignments' = 'assignments')
                    if ($expanded) { $assignments = @(Get-ITAssignment -InputObject @($o.assignments)) }
                    else { $assignments = @($o.Assignments) }
                    foreach ($a in $assignments) {
                        $list.Add([pscustomobject]@{ Object = $o; Assignment = $a })
                    }
                }
            }
            , $list.ToArray()
        }
    }

    process {
        foreach ($identity in $Id) {
            try {
                $group = Resolve-ITGroup -Identity $identity

                # Groups whose assignments reach this group's members
                $targets = @{ ([string]$group.id) = $group.displayName }
                if (-not $DirectOnly) {
                    $parentUri = New-ITGraphUri -Path ('groups/{0}/transitiveMemberOf/microsoft.graph.group' -f $group.id) -Select 'id', 'displayName'
                    foreach ($p in @(Invoke-ITGraphRequest -Uri $parentUri -ApiVersion 'v1.0' -All)) { $targets[[string]$p.id] = $p.displayName }
                }

                if ($null -eq $rows) { $rows = & $load }

                foreach ($row in $rows) {
                    $a = $row.Assignment
                    $via = $null
                    if ($a.GroupId -and $targets.ContainsKey([string]$a.GroupId)) {
                        $via = 'Parent group'
                        if ([string]$a.GroupId -eq [string]$group.id) { $via = 'Direct' }
                    }
                    elseif ($IncludeAllTargets -and @('AllDevices', 'AllUsers') -contains $a.Intent) {
                        $via = $a.Intent
                    }
                    if (-not $via) { continue }

                    if ($a.FilterId -and $null -eq $filterNames) {
                        $filterNames = @{}
                        try {
                            foreach ($f in @(Invoke-ITGraphRequest -Uri 'deviceManagement/assignmentFilters' -ApiVersion 'beta' -All)) { $filterNames[[string]$f.id] = $f.displayName }
                        }
                        catch {
                            Write-ITLog -Level Warning -Message "Assignment filter names not available: $($_.Exception.Message)"
                        }
                    }
                    $filterName = $null
                    if ($a.FilterId -and $filterNames.ContainsKey([string]$a.FilterId)) { $filterName = $filterNames[[string]$a.FilterId] }

                    $viaName = $null
                    if ($a.GroupId -and $targets.ContainsKey([string]$a.GroupId)) { $viaName = $targets[[string]$a.GroupId] }

                    $o = $row.Object
                    [pscustomobject]@{
                        PSTypeName    = 'IntuneToolkit.GroupAssignment'
                        GroupId       = $group.id
                        GroupName     = $group.displayName
                        Via           = $via
                        ViaGroupId    = $a.GroupId
                        ViaGroupName  = $viaName
                        PolicyType    = $o.PolicyType
                        ObjectType    = $o.ObjectType
                        ObjectId      = $o.id
                        ObjectName    = $o.displayName
                        Platform      = $o.Platform
                        Intent        = $a.Intent
                        InstallIntent = $a.InstallIntent
                        FilterId      = $a.FilterId
                        FilterType    = $a.FilterType
                        FilterName    = $filterName
                    }
                }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
