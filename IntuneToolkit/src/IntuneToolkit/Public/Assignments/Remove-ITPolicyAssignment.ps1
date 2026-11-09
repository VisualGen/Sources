function Remove-ITPolicyAssignment {
    <#
    .SYNOPSIS
        Removes an assignment (group, all devices, all users or everything) from a policy, profile, script or update profile.

    .DESCRIPTION
        Removes the matching target(s) and keeps the other assignments. With -GroupId both the
        include and the exclude of that group are removed unless -Exclude/-Include narrows it.
        -All removes every assignment (the object stays, it is just no longer deployed).
        For apps use Remove-ITAppAssignment.

    .PARAMETER PolicyType
        Type of the object. Binds from the PolicyType property of Get-IT* objects.

    .PARAMETER Id
        Object ID. Binds from the id property.

    .PARAMETER GroupId
        Entra group object ID whose assignment is removed.

    .PARAMETER Include
        Only remove the include assignment of the group.

    .PARAMETER Exclude
        Only remove the exclude assignment of the group.

    .PARAMETER AllDevices
        Remove the 'All devices' assignment.

    .PARAMETER AllUsers
        Remove the 'All users' assignment.

    .PARAMETER All
        Remove every assignment.

    .EXAMPLE
        Get-ITCompliancePolicy -Name 'Win - Old baseline' | Remove-ITPolicyAssignment -All -WhatIf

    .EXAMPLE
        Remove-ITPolicyAssignment -PolicyType SettingsCatalog -Id $id -GroupId 'b1c2...'

    .OUTPUTS
        IntuneToolkit.AssignmentChange

    .NOTES
        Graph permission : DeviceManagementConfiguration.ReadWrite.All
        Graph endpoint   : GET /{collection}/{id}/assignments, POST /{collection}/{id}/assign
        API version      : beta

    .LINK
        Add-ITPolicyAssignment
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Group')]
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
        [switch]$Include,

        [Parameter(ParameterSetName = 'Group')]
        [switch]$Exclude,

        [Parameter(Mandatory, ParameterSetName = 'AllDevices')]
        [switch]$AllDevices,

        [Parameter(Mandatory, ParameterSetName = 'AllUsers')]
        [switch]$AllUsers,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'
    }

    process {
        $info = Get-ITPolicyTypeInfo -PolicyType $PolicyType
        $objectName = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $objectName = $_.displayName }

        $intent = 'Any'
        if ($AllDevices) { $intent = 'AllDevices' }
        elseif ($AllUsers) { $intent = 'AllUsers' }
        elseif ($Include -and -not $Exclude) { $intent = 'Include' }
        elseif ($Exclude -and -not $Include) { $intent = 'Exclude' }

        $label = $intent
        if ($GroupId) { $label = '{0} group {1}' -f $intent, $GroupId }
        if ($All) { $label = 'ALL assignments' }
        $what = '{0} {1}' -f $PolicyType, $(if ($objectName) { "'$objectName' ($Id)" } else { $Id })
        if ($PSCmdlet.ShouldProcess($what, "Remove assignment: $label")) {
            $params = @{ TypeInfo = $info; Id = $Id; ObjectName = $objectName; Mode = 'Remove'; GroupId = $GroupId; RemoveAll = $All }
            if (-not $All) { $params['Intent'] = $intent }
            Invoke-ITAssignmentChange @params
        }
    }
}
