function Remove-ITAutopilotDevice {
    <#
    .SYNOPSIS
        Deregisters devices from Windows Autopilot.

    .DESCRIPTION
        Deletes the Autopilot registration (hardware hash). Typical uses: a device is sold,
        returned to the vendor or moves to another tenant. If the device is still enrolled in
        Intune, delete or retire the Intune device first; otherwise Graph may reject the request.
        Asks for confirmation by default.

    .PARAMETER Id
        Autopilot device identity ID(s). Accepts pipeline input from Get-ITAutopilotDevice.

    .PARAMETER SerialNumber
        Serial number, used only for messages and the result object (bound from the pipeline).

    .EXAMPLE
        Get-ITAutopilotDevice -SerialNumber 'PF3A1234' | Remove-ITAutopilotDevice

    .EXAMPLE
        Import-Csv .\ReturnedToVendor.csv | ForEach-Object { Get-ITAutopilotDevice -SerialNumber $_.Serial } |
            Remove-ITAutopilotDevice -WhatIf

        Shows which returned devices would be deregistered.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementServiceConfig.ReadWrite.All
        Graph endpoint   : DELETE /deviceManagement/windowsAutopilotDeviceIdentities/{id}
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-enrollment-windowsautopilotdeviceidentity-delete
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SerialNumber
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.ReadWrite.All'
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($SerialNumber -and $Id.Count -eq 1) { $label = 'Serial {0} ({1})' -f $SerialNumber, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, 'Deregister from Windows Autopilot')) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $SerialNumber -Action '' -ActionName 'DeleteAutopilot' `
                    -Method DELETE -BasePath 'deviceManagement/windowsAutopilotDeviceIdentities'
            }
        }
    }
}
