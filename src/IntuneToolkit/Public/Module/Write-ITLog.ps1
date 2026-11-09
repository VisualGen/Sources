function Write-ITLog {
    <#
    .SYNOPSIS
        Writes an Info, Warning or Error entry to the IntuneToolkit log (the file started by Start-ITLog).

    .DESCRIPTION
        The IntuneToolkit commands already log on their own. Use Write-ITLog in your script for your
        own events, for example a step that starts, a value you checked, or an error you caught.

        Entries are written in the CMTrace format, so the log opens in CMTrace.exe, OneTrace or
        Support Center like the Intune Management Extension logs: Component = your script or the
        IntuneToolkit command, Type = Info / Warning (yellow) / Error (red), Thread = process ID,
        Source = script file and line.

        On screen:
          Info     shown with -Verbose only
          Warning  shown as a warning
          Error    shown in red (error output, as Intune expects from a failing script), without
                   creating a PowerShell error, so the script continues and $Error is not changed
        Errors and warnings written by your script are counted in the Stop-ITLog summary.

        -ErrorRecord takes the error of a 'catch' block ($_) and logs its message, exception type,
        script line and call stack (level Error unless -Level is given).

        Without Start-ITLog (and without Set-ITConfiguration -LogPath) nothing is written to a
        file; the entry is only shown on screen.

    .PARAMETER Message
        The text to log. Accepts pipeline input.

    .PARAMETER Level
        Info (default), Warning or Error. Default with -ErrorRecord: Error.

    .PARAMETER ErrorRecord
        An error from a catch block ($_) or from $Error.

    .EXAMPLE
        Write-ITLog 'Step 1: reading stale devices'
        Write-ITLog -Message 'No devices found - nothing to do' -Level Warning

    .EXAMPLE
        try {
            Get-ITManagedDevice -Id $deviceId -ErrorAction Stop | Invoke-ITDeviceSync
        }
        catch {
            Write-ITLog -ErrorRecord $_ -Message "Sync failed for $deviceId"
        }

        Logs the caught error with its message, script line and call stack; the script continues.

    .EXAMPLE
        Write-ITLog -Level Error -Message 'Compliance policy "Win - Baseline" is missing'

        An error event without an exception.

    .NOTES
        No Graph connection or permission needed. Lines are written as UTF-8.

    .LINK
        Start-ITLog
    #>
    [CmdletBinding(DefaultParameterSetName = 'Message')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ParameterSetName = 'Message')]
        [Parameter(Position = 0, ParameterSetName = 'ErrorRecord')]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory, ParameterSetName = 'ErrorRecord')]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    process {
        $entryLevel = $Level
        if (-not $entryLevel) {
            $entryLevel = 'Info'
            if ($ErrorRecord) { $entryLevel = 'Error' }
        }

        # Who wrote the entry: the calling command, or the script name for script code
        $caller = 'IntuneToolkit'
        $fromScript = $true
        $stack = @(Get-PSCallStack)
        if ($stack.Count -gt 1) {
            $frame = $stack[1]
            # Module code (also its script blocks) lives under the module folder; everything else is the user's script
            $moduleBase = $MyInvocation.MyCommand.Module.ModuleBase
            $fromScript = -not ($frame.ScriptName -and $moduleBase -and $frame.ScriptName.StartsWith($moduleBase, [StringComparison]::OrdinalIgnoreCase))
            if ($frame.Command -and $frame.Command -ne '<ScriptBlock>') { $caller = $frame.Command }
            elseif ($frame.ScriptName) { $caller = Split-Path -Leaf $frame.ScriptName }
            else { $caller = 'Script' }
        }

        # --- Text ------------------------------------------------------------------------------
        $text = $Message
        $details = @()
        if ($ErrorRecord) {
            $errorText = [string]$ErrorRecord.Exception.Message
            if (-not $errorText) { $errorText = [string]$ErrorRecord }
            if ($text) { $text = '{0}: {1}' -f $text, $errorText } else { $text = $errorText }

            $info = $ErrorRecord.InvocationInfo
            $where = @()
            $where += 'Exception: ' + $ErrorRecord.Exception.GetType().FullName
            if ($info -and $info.ScriptName) { $where += ('at {0}:{1}' -f (Split-Path -Leaf $info.ScriptName), $info.ScriptLineNumber) }
            elseif ($info -and $info.ScriptLineNumber) { $where += ('line {0}' -f $info.ScriptLineNumber) }
            if ($ErrorRecord.FullyQualifiedErrorId) { $where += 'Id: ' + $ErrorRecord.FullyQualifiedErrorId }
            $details += ($where -join ' | ')
            if ($ErrorRecord.ScriptStackTrace) {
                $details += @(($ErrorRecord.ScriptStackTrace -split "`r?`n") | Where-Object { $_ } | Select-Object -First 8 | ForEach-Object { '    ' + $_ })
            }
        }
        if ($null -eq $text) { $text = '' }
        $text = $text -replace "`r?`n", ' | '

        $now = Get-Date
        $line = '{0} [{1}] {2}: {3}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $entryLevel.ToUpper(), $caller, $text   # screen (-Verbose)

        # --- CMTrace entry (CMTrace.exe, OneTrace, Support Center, IME log viewers) -----------------
        #   <![LOG[text]LOG]!><time="HH:mm:ss.fff+bias" date="MM-dd-yyyy" component="..." context="..."
        #     type="1|2|3" thread="<PID>" file="script.ps1:line">
        #   type 1 = Info, 2 = Warning (yellow), 3 = Error (red); bias = minutes to add to get UTC.
        #   Error details go on extra lines inside the same entry (CMTrace shows them in the detail pane).
        $body = $text
        if ($details.Count) { $body = $text + [Environment]::NewLine + ($details -join [Environment]::NewLine) }
        $body = $body.Replace(']LOG]!>', '] LOG]!>')
        $bias = -[int][TimeZoneInfo]::Local.GetUtcOffset($now).TotalMinutes
        $type = @{ Info = 1; Warning = 2; Error = 3 }[$entryLevel]
        $source = ''
        if ($stack.Count -gt 1 -and $stack[1].ScriptName) { $source = '{0}:{1}' -f (Split-Path -Leaf $stack[1].ScriptName), $stack[1].ScriptLineNumber }
        $context = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $cmTrace = '<![LOG[{0}]LOG]!><time="{1}{2:+0;-0;+0}" date="{3}" component="{4}" context="{5}" type="{6}" thread="{7}" file="{8}">'
        $values = @($body, $now.ToString('HH:mm:ss.fff'), $bias, $now.ToString('MM-dd-yyyy'), ($caller -replace '"', "'"), $context, $type, $PID, $source)
        $lines = $cmTrace -f $values

        # --- Screen -------------------------------------------------------------------------------
        switch ($entryLevel) {
            'Warning' { Write-Warning -Message $text; break }
            'Error' {
                if ($fromScript) {
                    # Red error output without an ErrorRecord: the script continues, $Error unchanged
                    try { $Host.UI.WriteErrorLine(('ERROR: {0}' -f $text)) } catch { Write-Verbose -Message $line }
                }
                else {
                    Write-Verbose -Message $line
                }
                break
            }
            default { Write-Verbose -Message $line }
        }

        # --- Count script events for the Stop-ITLog summary -----------------------------------------
        if ($fromScript -and $script:ITLogSession -and $entryLevel -ne 'Info') {
            $counter = 'LoggedWarnings'
            if ($entryLevel -eq 'Error') { $counter = 'LoggedErrors' }
            $script:ITLogSession.$counter = $script:ITLogSession.$counter + 1
        }

        # --- File ------------------------------------------------------------------------------
        $path = $script:ITConfig.LogPath
        if ($path) {
            try {
                Add-Content -Path $path -Value $lines -Encoding UTF8 -ErrorAction Stop
            }
            catch {
                Write-Verbose -Message "Write-ITLog: cannot write to '$path': $($_.Exception.Message)"
            }
        }
    }
}
