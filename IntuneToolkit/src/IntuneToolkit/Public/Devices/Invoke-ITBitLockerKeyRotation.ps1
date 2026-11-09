function Invoke-ITBitLockerKeyRotation {
    <#
    .SYNOPSIS
        Rotates the BitLocker recovery key(s) of one or more Windows devices.

    .DESCRIPTION
        Sends the 'rotateBitLockerKeys' remote action. The device creates a new recovery
        password and escrows it to Entra ID. Use it after a recovery key has been handed out.
        Requires Windows 10 1909+ and the BitLocker 'client-driven recovery password rotation' setting.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .EXAMPLE
        Get-ITManagedDevice -Name 'LT-0815' | Invoke-ITBitLockerKeyRotation

        Rotates the key after it was given to a user over the phone.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/rotateBitLockerKeys
        API version      : beta (not available in v1.0)

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-rotatebitlockerkeys
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
            if ($PSCmdlet.ShouldProcess($label, 'Rotate BitLocker recovery key')) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'rotateBitLockerKeys' -ActionName 'BitLockerKeyRotation' -ApiVersion 'beta'
            }
        }
    }
}
