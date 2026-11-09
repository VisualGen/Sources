function Remove-ITManagedDevice {
    <#
    .SYNOPSIS
        Deletes one or more device records from Intune.

    .DESCRIPTION
        Deletes the managed device object. Nothing is sent to the device itself; if the device
        is still active it will show up again at its next check-in (retire or wipe it first).
        Typical use: clean up records of devices that no longer exist. Asks for confirmation by default.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .EXAMPLE
        Get-ITStaleDevice -Days 365 | Remove-ITManagedDevice -WhatIf

        Lists which records a yearly clean-up would delete.

    .EXAMPLE
        Get-ITStaleDevice -Days 365 | Remove-ITManagedDevice -Confirm:$false |
            Export-Csv .\Deleted.csv -NoTypeInformation -Encoding UTF8

        Deletes the records and keeps a CSV log of the result.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.ReadWrite.All
        Graph endpoint   : DELETE /deviceManagement/managedDevices/{id}
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-delete
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
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.ReadWrite.All'
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $label = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, 'Delete Intune device record')) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action '' -ActionName 'Delete' -Method DELETE
            }
        }
    }
}
