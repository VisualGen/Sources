function Stop-ITLog {
    <#
    .SYNOPSIS
        Closes the log started by Start-ITLog. Call it once at the end of the script.

    .DESCRIPTION
        Writes a closing summary to the IntuneToolkit log (duration, optional status, the number of
        errors and warnings the script wrote with Write-ITLog, and the PowerShell errors recorded
        while the script ran), stops the transcript and restores the previous log
        setting. Put it in a 'finally' block so the log is also closed when the script fails.

        Calling Stop-ITLog when no log is running does nothing.

    .PARAMETER Status
        Optional result text for the summary, e.g. 'Success' or 'Failed: no connection'.

    .PARAMETER PassThru
        Return the closed log session (paths, start and end time, duration, error count).

    .EXAMPLE
        Start-ITLog
        try {
            Connect-ITGraph
            Get-ITNonCompliantDevice | Export-ITReport -Path "$env:TEMP\noncompliant.html"
            $result = 'Success'
        }
        catch {
            $result = "Failed: $($_.Exception.Message)"
            throw
        }
        finally {
            Stop-ITLog -Status $result
        }

    .OUTPUTS
        IntuneToolkit.LogSession (with -PassThru)

    .LINK
        Start-ITLog
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneToolkit.LogSession')]
    param(
        [string]$Status,

        [switch]$PassThru
    )

    $session = $script:ITLogSession
    if (-not $session) {
        Write-Verbose -Message 'Stop-ITLog: no log is running.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($session.LogPath, 'Close log')) { return }

    $end = Get-Date
    $duration = $end - $session.StartTime

    # Errors recorded since Start-ITLog (the session $global:Error keeps the newest first; PowerShell keeps at most 256)
    $newErrors = [math]::Max(0, $global:Error.Count - $session.ErrorCountStart)
    $shown = @($global:Error | Select-Object -First ([math]::Min($newErrors, 10)))
    for ($i = $shown.Count - 1; $i -ge 0; $i--) {
        $text = [string]$shown[$i]
        if ($shown[$i] -is [System.Management.Automation.ErrorRecord] -and $shown[$i].InvocationInfo -and $shown[$i].InvocationInfo.ScriptLineNumber) {
            $text = '{0} (line {1})' -f $text, $shown[$i].InvocationInfo.ScriptLineNumber
        }
        Write-ITLog -Level Error -Message ('Error recorded: {0}' -f $text)
    }

    $summary = 'Duration {0:hh\:mm\:ss} | errors logged: {1} | warnings logged: {2} | PowerShell errors recorded: {3}' -f $duration, $session.LoggedErrors, $session.LoggedWarnings, $newErrors
    if ($Status) { $summary = 'Status: {0} | {1}' -f $Status, $summary }
    Write-ITLog -Message $summary
    Write-ITLog -Message ('===== Log closed: {0} =====' -f $session.Name)

    if ($session.TranscriptPath) {
        try { $null = Stop-Transcript -ErrorAction Stop }
        catch { Write-Verbose -Message "Stop-ITLog: transcript already stopped ($($_.Exception.Message))." }
    }

    $script:ITConfig.LogPath = $session.PreviousLogPath
    $script:ITLogSession = $null

    if ($PassThru) {
        $session | Add-Member -NotePropertyName 'EndTime' -NotePropertyValue $end -Force
        $session | Add-Member -NotePropertyName 'Duration' -NotePropertyValue $duration -Force
        $session | Add-Member -NotePropertyName 'ErrorCount' -NotePropertyValue $newErrors -Force          # PowerShell errors ($Error)
        $session | Add-Member -NotePropertyName 'Status' -NotePropertyValue $Status -Force
        $session
    }
}
