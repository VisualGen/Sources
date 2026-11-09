function Remove-ITAppAssignment {
    <#
    .SYNOPSIS
        Removes an assignment (group, all devices, all users or everything) from an Intune app.

    .DESCRIPTION
        Removes the matching target(s) and keeps the other assignments. With -GroupId both an
        include and an exclude of that group are removed. -All removes every assignment.
        Removing a 'required' assignment does NOT uninstall the app from devices; assign
        'uninstall' for that.

    .PARAMETER Id
        App ID. Binds from the id of Get-ITApp objects.

    .PARAMETER GroupId
        Entra group object ID whose assignment is removed.

    .PARAMETER AllDevices
        Remove the 'All devices' assignment.

    .PARAMETER AllUsers
        Remove the 'All users' assignment.

    .PARAMETER All
        Remove every assignment.

    .EXAMPLE
        Get-ITApp -Name '7-Zip' | Remove-ITAppAssignment -GroupId $pilotGroup -WhatIf

    .EXAMPLE
        Get-ITApp -Name 'Old VPN client' | Remove-ITAppAssignment -All

    .OUTPUTS
        IntuneToolkit.AssignmentChange

    .NOTES
        Graph permission : DeviceManagementApps.ReadWrite.All
        Graph endpoint   : GET /deviceAppManagement/mobileApps/{id}/assignments, POST /deviceAppManagement/mobileApps/{id}/assign
        API version      : beta

    .LINK
        Add-ITAppAssignment
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Group')]
    [OutputType('IntuneToolkit.AssignmentChange')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Group')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupId,

        [Parameter(Mandatory, ParameterSetName = 'AllDevices')]
        [switch]$AllDevices,

        [Parameter(Mandatory, ParameterSetName = 'AllUsers')]
        [switch]$AllUsers,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType App
        Assert-ITGraphConnection -RequiredScope $info.WriteScope
    }

    process {
        $objectName = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $objectName = $_.displayName }

        if ($AllDevices) { $intent = 'AllDevices' }
        elseif ($AllUsers) { $intent = 'AllUsers' }
        else { $intent = 'Any' }
        $label = $intent
        if ($GroupId) { $label = 'group {0}' -f $GroupId }
        if ($All) { $label = 'ALL assignments' }

        $what = 'App {0}' -f $(if ($objectName) { "'$objectName' ($Id)" } else { $Id })
        if ($PSCmdlet.ShouldProcess($what, "Remove assignment: $label")) {
            $params = @{ TypeInfo = $info; Id = $Id; ObjectName = $objectName; Mode = 'Remove'; GroupId = $GroupId; RemoveAll = $All }
            if (-not $All) { $params['Intent'] = $intent }
            Invoke-ITAssignmentChange @params
        }
    }
}
