function Get-ITGroupMember {
    <#
    .SYNOPSIS
        Lists the members of an Entra ID group, optionally including nested groups.

    .DESCRIPTION
        Without switches: the direct members (users, devices, groups, service principals, contacts).

        -Recurse walks the nested groups and shows where each member comes from: Depth (1 = direct
        member), ParentGroupName (the group it is a direct member of) and Path
        ('All Pilots > Pilot Devices'). A user or device reached through two paths is listed twice;
        a nested group that appears in several places (or in a circle) is expanded only once.

        -Transitive asks Graph for the flat list of every member at any level (each member once,
        no path). Faster on large trees.

    .PARAMETER Id
        Group object ID or exact display name. Accepts pipeline input by property name (id / GroupId).

    .PARAMETER Recurse
        Include the members of nested groups, with Depth / ParentGroupName / Path.

    .PARAMETER Transitive
        Flat list of all members at any nesting level (Graph transitiveMembers).

    .PARAMETER MemberType
        Return only these member types: User, Device, Group, ServicePrincipal, Contact.
        Nested groups are still followed with -Recurse.

    .PARAMETER MaxDepth
        Maximum nesting depth for -Recurse. Default 10.

    .EXAMPLE
        Get-ITGroupMember -Id 'SG-Intune-Pilot-Users'

        Direct members of one group.

    .EXAMPLE
        Get-ITGroupMember -Id 'SG-Intune-All-Pilots' -Recurse | Format-Table Depth, MemberType, displayName, Path

        The nesting tree of a group.

    .EXAMPLE
        Get-ITGroup -Name 'SG-Intune-*' | Get-ITGroupMember -Transitive -MemberType Device | Select-Object GroupName, displayName, deviceId

        Every device in a set of groups, including devices in nested groups.

    .OUTPUTS
        IntuneToolkit.GroupMember

    .NOTES
        Graph permission : Group.Read.All (+ User.Read.All / Device.Read.All for member details)
        Graph endpoint   : GET /groups/{id}/members, GET /groups/{id}/transitiveMembers
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-list-members
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.GroupMember')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$Recurse,

        [switch]$Transitive,

        [ValidateSet('User', 'Device', 'Group', 'ServicePrincipal', 'Contact')]
        [string[]]$MemberType,

        [ValidateRange(1, 50)]
        [int]$MaxDepth = 10
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.Read.All'
        if ($Recurse -and $Transitive) { throw 'Use -Recurse or -Transitive, not both.' }
        $select = 'id', 'displayName', 'userPrincipalName', 'mail', 'accountEnabled', 'deviceId', 'operatingSystem', 'appId'
        $typeFilter = $MemberType
        $depthLimit = $MaxDepth
        $walkNested = [bool]$Recurse

        $emit = {
            param($m, $top, [string]$ParentId, [string]$ParentName, $Depth, [string]$Path)
            $type = Get-ITDirectoryObjectType -InputObject $m
            $row = [ordered]@{
                GroupId         = $top.id
                GroupName       = $top.displayName
                MemberType      = $type
                id              = $m.id
                displayName     = $null
                userPrincipalName = $null
                mail            = $null
                accountEnabled  = $null
                deviceId        = $null
                operatingSystem = $null
                Depth           = $Depth
                ParentGroupId   = $ParentId
                ParentGroupName = $ParentName
                Path            = $Path
            }
            foreach ($p in 'displayName', 'userPrincipalName', 'mail', 'accountEnabled', 'deviceId', 'operatingSystem') {
                if ($m.PSObject.Properties[$p]) { $row[$p] = $m.$p }
            }
            $out = [pscustomobject]$row
            if (-not $typeFilter -or $typeFilter -contains $type) { $out | ConvertTo-ITObject -TypeName 'GroupMember' }
        }

        $walk = {
            param($top, [string]$GroupIdNow, [string]$GroupNameNow, [int]$Depth, [string]$Path, [hashtable]$Visited)
            $uri = New-ITGraphUri -Path ('groups/{0}/members' -f $GroupIdNow) -Select $select
            foreach ($m in @(Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -All)) {
                & $emit $m $top $GroupIdNow $GroupNameNow $Depth $Path
                if ($walkNested -and (Get-ITDirectoryObjectType -InputObject $m) -eq 'Group') {
                    if ($Visited.ContainsKey([string]$m.id)) {
                        Write-Verbose ("'{0}' is already expanded below '{1}' (repeated or circular nesting)." -f $m.displayName, $top.displayName)
                        continue
                    }
                    if ($Depth -ge $depthLimit) {
                        Write-Warning ("'{0}': nesting deeper than {1} levels below '{2}' is not shown (-MaxDepth)." -f $top.displayName, $depthLimit, $m.displayName)
                        continue
                    }
                    $Visited[[string]$m.id] = $true
                    & $walk $top ([string]$m.id) ([string]$m.displayName) ($Depth + 1) ($Path + ' > ' + $m.displayName) $Visited
                }
            }
        }
    }

    process {
        foreach ($identity in $Id) {
            try {
                $top = Resolve-ITGroup -Identity $identity
                if ($Transitive) {
                    $uri = New-ITGraphUri -Path ('groups/{0}/transitiveMembers' -f $top.id) -Select $select
                    foreach ($m in @(Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -All)) {
                        & $emit $m $top $null $null $null $null
                    }
                }
                else {
                    & $walk $top ([string]$top.id) ([string]$top.displayName) 1 ([string]$top.displayName) @{ ([string]$top.id) = $true }
                }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
