function Get-ITPolicyAssignment {
    <#
    .SYNOPSIS
        Gets the assignments of a policy, profile, script, remediation, update profile or app.

    .DESCRIPTION
        Works for every PolicyType: Compliance, DeviceConfiguration, SettingsCatalog, Script,
        Remediation, UpdateRing, FeatureUpdate, DriverUpdate, App. Objects returned by the
        Get-IT* list functions carry PolicyType and id, so they can be piped in directly.
        Returns one row per assignment: Intent (Include/Exclude/AllDevices/AllUsers),
        InstallIntent (apps), GroupId, FilterId, FilterType. -ResolveName adds GroupName and
        FilterName (cached lookups; needs Group.Read.All).

    .PARAMETER PolicyType
        Type of the object. Binds from the PolicyType property of Get-IT* objects.

    .PARAMETER Id
        Object ID. Binds from the id property.

    .PARAMETER ResolveName
        Add GroupName and FilterName.

    .EXAMPLE
        Get-ITCompliancePolicy | Get-ITPolicyAssignment -ResolveName

    .EXAMPLE
        Get-ITPolicyAssignment -PolicyType SettingsCatalog -Id '1b2c...' | Format-Table

    .EXAMPLE
        Get-ITSettingsCatalogPolicy | Get-ITPolicyAssignment -ResolveName |
            Where-Object GroupName -eq 'SG-Pilot-Devices'

        Everything assigned to one group (pipe the other Get-IT* commands too).

    .OUTPUTS
        IntuneToolkit.PolicyAssignment

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All (apps: DeviceManagementApps.Read.All)
                           + Group.Read.All for -ResolveName
        Graph endpoint   : GET /{collection}/{id}/assignments
        API version      : beta

    .LINK
        Add-ITPolicyAssignment
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.PolicyAssignment')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateSet('Compliance', 'DeviceConfiguration', 'SettingsCatalog', 'Script', 'Remediation',
            'UpdateRing', 'FeatureUpdate', 'DriverUpdate', 'App')]
        [string]$PolicyType,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [switch]$ResolveName
    )

    begin {
        $groupCache  = @{}
        $filterCache = @{}
        $asserted    = @{}
    }

    process {
        $info = Get-ITPolicyTypeInfo -PolicyType $PolicyType
        if (-not $asserted[$info.ReadScope]) {
            Assert-ITGraphConnection -RequiredScope $info.ReadScope
            $asserted[$info.ReadScope] = $true
        }

        $objectName = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $objectName = $_.displayName }

        try {
            $rows = @(Get-ITAssignment -Path ('{0}/{1}' -f $info.Path, $Id) -ApiVersion 'beta')
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }

        foreach ($row in $rows) {
            $out = [ordered]@{
                PSTypeName    = 'IntuneToolkit.PolicyAssignment'
                PolicyType    = $PolicyType
                ObjectId      = $Id
                ObjectName    = $objectName
                Intent        = $row.Intent
                InstallIntent = $row.InstallIntent
                GroupId       = $row.GroupId
                FilterId      = $row.FilterId
                FilterType    = $row.FilterType
                AssignmentId  = $row.AssignmentId
            }
            if ($ResolveName) {
                $groupName = $null
                if ($row.GroupId) {
                    if (-not $groupCache.ContainsKey($row.GroupId)) {
                        try {
                            $group = Invoke-ITGraphRequest -Uri ('groups/{0}?$select=displayName' -f $row.GroupId) -ApiVersion 'v1.0'
                            $groupCache[$row.GroupId] = $group.displayName
                        }
                        catch {
                            Write-Warning -Message ('Group {0}: {1}' -f $row.GroupId, $_.Exception.Message)
                            $groupCache[$row.GroupId] = $null
                        }
                    }
                    $groupName = $groupCache[$row.GroupId]
                }
                $filterName = $null
                if ($row.FilterId) {
                    if (-not $filterCache.ContainsKey($row.FilterId)) {
                        try {
                            $filter = Invoke-ITGraphRequest -Uri ('deviceManagement/assignmentFilters/{0}' -f $row.FilterId) -ApiVersion 'beta'
                            $filterCache[$row.FilterId] = $filter.displayName
                        }
                        catch {
                            Write-Warning -Message ('Filter {0}: {1}' -f $row.FilterId, $_.Exception.Message)
                            $filterCache[$row.FilterId] = $null
                        }
                    }
                    $filterName = $filterCache[$row.FilterId]
                }
                $out['GroupName']  = $groupName
                $out['FilterName'] = $filterName
            }
            [pscustomobject]$out
        }
    }
}
