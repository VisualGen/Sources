function Add-ITPolicyAssignment {
    <#
    .SYNOPSIS
        Assigns a policy, profile, script, remediation or update profile to a group, all devices or all users.

    .DESCRIPTION
        Adds ONE target and keeps the existing assignments (Graph's /assign replaces the full set,
        so the current set is read and posted back with the new target). A target that already
        exists is reported as 'Unchanged'. Exclusions: -Exclude. Assignment filters: -FilterId.
        Remediations get a daily schedule (01:00 local time) unless -RemediationSchedule is given.
        For apps use Add-ITAppAssignment (install intent is required).

    .PARAMETER PolicyType
        Type of the object. Binds from the PolicyType property of Get-IT* objects.

    .PARAMETER Id
        Object ID. Binds from the id property.

    .PARAMETER GroupId
        Entra group object ID to include (or exclude with -Exclude).

    .PARAMETER Exclude
        Exclude the group instead of including it.

    .PARAMETER AllDevices
        Assign to all devices.

    .PARAMETER AllUsers
        Assign to all licensed users.

    .PARAMETER FilterId
        Assignment filter ID (Get-ITAssignmentFilter). Not allowed on exclusions.

    .PARAMETER FilterType
        'include' (default): only devices matching the filter; 'exclude': all except matching devices.

    .PARAMETER RemediationSchedule
        Graph runSchedule object for remediations, e.g.
        @{ '@odata.type' = '#microsoft.graph.deviceHealthScriptHourlySchedule'; interval = 4 }

    .EXAMPLE
        Get-ITCompliancePolicy -Name 'Win - Baseline' | Add-ITPolicyAssignment -GroupId 'b1c2...' -WhatIf

    .EXAMPLE
        Get-ITSettingsCatalogPolicy -Name 'Win - Edge' | Add-ITPolicyAssignment -AllDevices -FilterId $filter.id

        All devices, limited by an assignment filter.

    .EXAMPLE
        Add-ITPolicyAssignment -PolicyType DeviceConfiguration -Id $profileId -GroupId $kioskGroup -Exclude

    .OUTPUTS
        IntuneToolkit.AssignmentChange

    .NOTES
        Graph permission : DeviceManagementConfiguration.ReadWrite.All
        Graph endpoint   : GET /{collection}/{id}/assignments, POST /{collection}/{id}/assign
        API version      : beta

    .LINK
        Remove-ITPolicyAssignment
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Group')]
    [OutputType('IntuneToolkit.AssignmentChange')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateSet('Compliance', 'DeviceConfiguration', 'SettingsCatalog', 'Script', 'Remediation',
            'UpdateRing', 'FeatureUpdate', 'DriverUpdate')]
        [string]$PolicyType,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Group')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupId,

        [Parameter(ParameterSetName = 'Group')]
        [switch]$Exclude,

        [Parameter(Mandatory, ParameterSetName = 'AllDevices')]
        [switch]$AllDevices,

        [Parameter(Mandatory, ParameterSetName = 'AllUsers')]
        [switch]$AllUsers,

        [ValidateNotNullOrEmpty()]
        [string]$FilterId,

        [ValidateSet('include', 'exclude')]
        [string]$FilterType = 'include',

        [hashtable]$RemediationSchedule
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'
    }

    process {
        $info = Get-ITPolicyTypeInfo -PolicyType $PolicyType
        if ($AllDevices) { $intent = 'AllDevices' }
        elseif ($AllUsers) { $intent = 'AllUsers' }
        elseif ($Exclude) { $intent = 'Exclude' }
        else { $intent = 'Include' }

        $objectName = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $objectName = $_.displayName }

        $extra = $null
        if ($PolicyType -eq 'Remediation' -and $intent -ne 'Exclude') {
            $schedule = $RemediationSchedule
            if (-not $schedule) {
                $schedule = @{ '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'; interval = 1; time = '01:00:00'; useUtc = $false }
            }
            $extra = @{ runRemediationScript = $true; runSchedule = $schedule }
        }

        $label = $intent
        if ($GroupId) { $label = '{0} group {1}' -f $intent, $GroupId }
        $what = '{0} {1}' -f $PolicyType, $(if ($objectName) { "'$objectName' ($Id)" } else { $Id })
        if ($PSCmdlet.ShouldProcess($what, "Add assignment: $label")) {
            Invoke-ITAssignmentChange -TypeInfo $info -Id $Id -ObjectName $objectName -Mode Add -Intent $intent -GroupId $GroupId `
                -FilterId $FilterId -FilterType $FilterType -Extra $extra
        }
    }
}
