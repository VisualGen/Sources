function Invoke-ITDeviceRetire {
    <#
    .SYNOPSIS
        Retires one or more managed devices (removes company data and management).

    .DESCRIPTION
        Sends the 'retire' remote action: company apps, data, profiles and settings delivered
        by Intune are removed, personal data stays. The device leaves Intune management.
        Asks for confirmation by default.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .EXAMPLE
        Get-ITManagedDevice -Name 'IPHONE-JDOE' | Invoke-ITDeviceRetire

    .EXAMPLE
        Get-ITStaleDevice -Days 180 -OwnerType personal | Invoke-ITDeviceRetire -WhatIf

        Shows which personal devices without check-in for 180 days would be retired.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/retire
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-retire
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.PrivilegedOperations.All'
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $label = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, 'Retire device (remove company data and management)')) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'retire' -ActionName 'Retire'
            }
        }
    }
}
