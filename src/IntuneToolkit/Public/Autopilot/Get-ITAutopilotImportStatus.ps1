function Get-ITAutopilotImportStatus {
    <#
    .SYNOPSIS
        Gets pending and failed Autopilot hardware-hash imports.

    .DESCRIPTION
        Returns the import records (importedWindowsAutopilotDeviceIdentities) that are still
        in the tenant: devices being processed and imports that failed (e.g. 806
        ZtdDeviceAlreadyAssigned, 808 ZtdDeviceAssignedToOtherTenant). Successful imports are
        cleaned up by Import-ITAutopilotDevice -Wait. -ErrorOnly is used by the daily report.

    .PARAMETER ErrorOnly
        Only failed imports.

    .EXAMPLE
        Get-ITAutopilotImportStatus

    .EXAMPLE
        Get-ITAutopilotImportStatus -ErrorOnly | Select-Object serialNumber, Status, ErrorCode, ErrorName

    .OUTPUTS
        IntuneToolkit.AutopilotImportStatus

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All
        Graph endpoint   : GET /deviceManagement/importedWindowsAutopilotDeviceIdentities
        API version      : v1.0

    .LINK
        Import-ITAutopilotDevice
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.AutopilotImportStatus')]
    param(
        [switch]$ErrorOnly
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'
    $items = Invoke-ITGraphRequest -Uri 'deviceManagement/importedWindowsAutopilotDeviceIdentities' -ApiVersion 'v1.0' -All

    foreach ($item in @($items | Where-Object { $_ })) {
        $state = $null
        if ($item.PSObject.Properties['state']) { $state = $item.state }
        $status = $null; $code = $null; $errName = $null
        if ($state) {
            if ($state.PSObject.Properties['deviceImportStatus']) { $status = [string]$state.deviceImportStatus }
            if ($state.PSObject.Properties['deviceErrorCode']) { $code = $state.deviceErrorCode }
            if ($state.PSObject.Properties['deviceErrorName']) { $errName = $state.deviceErrorName }
        }
        if ($ErrorOnly -and $status -ne 'error') { continue }
        Add-Member -InputObject $item -NotePropertyName 'Status' -NotePropertyValue $status -Force
        Add-Member -InputObject $item -NotePropertyName 'ErrorCode' -NotePropertyValue $code -Force
        Add-Member -InputObject $item -NotePropertyName 'ErrorName' -NotePropertyValue $errName -Force
        $item | ConvertTo-ITObject -TypeName 'AutopilotImportStatus'
    }
}
