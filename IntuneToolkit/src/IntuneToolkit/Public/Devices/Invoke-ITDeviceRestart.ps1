function Invoke-ITDeviceRestart {
    <#
    .SYNOPSIS
        Restarts one or more managed devices.

    .DESCRIPTION
        Sends the 'rebootNow' remote action. The user is NOT asked; unsaved work can be lost.
        Asks for confirmation by default (use -Confirm:$false in scripts).

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .EXAMPLE
        Get-ITManagedDevice -Name 'MEETINGROOM-01' | Invoke-ITDeviceRestart

    .EXAMPLE
        Get-ITManagedDevice -Name 'KIOSK-*' | Invoke-ITDeviceRestart -Confirm:$false

        Restarts all kiosk devices without prompting (scheduled maintenance).

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/rebootNow
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-rebootnow
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
            if ($PSCmdlet.ShouldProcess($label, 'Restart device now')) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'rebootNow' -ActionName 'Restart'
            }
        }
    }
}
