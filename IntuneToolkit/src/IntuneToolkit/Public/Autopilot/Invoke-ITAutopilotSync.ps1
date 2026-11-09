function Invoke-ITAutopilotSync {
    <#
    .SYNOPSIS
        Starts a Windows Autopilot sync (same as 'Sync' in Intune > Windows Autopilot devices).

    .DESCRIPTION
        Asks Intune to sync registrations with the Autopilot deployment service, so imported
        devices and changed group tags show up sooner. Intune allows one manual sync every
        10 minutes; a request within that window is reported as a warning, not an error.
        Returns the sync status afterwards. -Wait polls until the sync has finished.

    .PARAMETER Wait
        Wait until the sync status is 'completed' or 'failed'.

    .PARAMETER TimeoutMinutes
        Maximum wait time with -Wait. Default 10.

    .EXAMPLE
        Invoke-ITAutopilotSync

    .EXAMPLE
        Invoke-ITAutopilotSync -Wait

        Starts a sync and waits for it to finish.

    .OUTPUTS
        IntuneToolkit.AutopilotSyncStatus

    .NOTES
        Graph permission : DeviceManagementServiceConfig.ReadWrite.All
        Graph endpoint   : POST /deviceManagement/windowsAutopilotSettings/sync
        API version      : beta (windowsAutopilotSettings is not in v1.0)

    .LINK
        https://learn.microsoft.com/graph/api/intune-enrollment-windowsautopilotsettings-sync
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('IntuneToolkit.AutopilotSyncStatus')]
    param(
        [switch]$Wait,

        [ValidateRange(1, 60)]
        [int]$TimeoutMinutes = 10
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.ReadWrite.All'

    if (-not $PSCmdlet.ShouldProcess('Windows Autopilot', 'Sync with the deployment service')) { return }

    $before = Get-ITAutopilotSyncStatus
    $started = $false
    try {
        $null = Invoke-ITGraphRequest -Uri 'deviceManagement/windowsAutopilotSettings/sync' -Method POST -ApiVersion 'beta' -NoRetry
        $started = $true
        Write-ITLog -Message 'Autopilot sync started.'
    }
    catch {
        if ($_.Exception.Message -match 'HTTP 429') {
            Write-ITLog -Level Warning -Message "A manual Autopilot sync was requested less than 10 minutes ago (last request: $($before.LastManualSyncTriggerDateTime)). Try again later."
        }
        else {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    if ($Wait -and $started) {
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            Start-Sleep -Seconds 15
            $status = Get-ITAutopilotSyncStatus
            $done = ($status.SyncStatus -in 'completed', 'failed') -and ([string]$status.LastSyncDateTime -ne [string]$before.LastSyncDateTime)
        } until ($done -or (Get-Date) -ge $deadline)
        if (-not $done) { Write-ITLog -Level Warning -Message "Autopilot sync still running after $TimeoutMinutes minute(s)." }
        return $status
    }

    Get-ITAutopilotSyncStatus
}
