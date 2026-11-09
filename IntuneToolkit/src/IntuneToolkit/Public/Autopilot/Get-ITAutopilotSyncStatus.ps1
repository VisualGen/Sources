function Get-ITAutopilotSyncStatus {
    <#
    .SYNOPSIS
        Shows when Windows Autopilot last synced with the Autopilot deployment service.

    .DESCRIPTION
        Returns the Autopilot settings: last sync, last manual sync request and the sync status
        (unknown, inProgress, completed, failed).

    .EXAMPLE
        Get-ITAutopilotSyncStatus

    .OUTPUTS
        IntuneToolkit.AutopilotSyncStatus

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All
        Graph endpoint   : GET /deviceManagement/windowsAutopilotSettings
        API version      : beta (windowsAutopilotSettings is not in v1.0)

    .LINK
        Invoke-ITAutopilotSync
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.AutopilotSyncStatus')]
    param()

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'

    $settings = Invoke-ITGraphRequest -Uri 'deviceManagement/windowsAutopilotSettings' -ApiVersion 'beta'

    $get = { param($name) if ($settings.PSObject.Properties[$name]) { $settings.$name } else { $null } }
    [pscustomobject]@{
        PSTypeName                    = 'IntuneToolkit.AutopilotSyncStatus'
        SyncStatus                    = & $get 'syncStatus'
        LastSyncDateTime              = & $get 'lastSyncDateTime'
        LastManualSyncTriggerDateTime = & $get 'lastManualSyncTriggerDateTime'
    }
}
