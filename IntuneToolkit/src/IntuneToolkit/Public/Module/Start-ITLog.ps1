function Start-ITLog {
    <#
    .SYNOPSIS
        Starts logging for a script that uses IntuneToolkit. Call it once at the top of the script.

    .DESCRIPTION
        After Start-ITLog every IntuneToolkit command logs on its own - you do not add log calls to
        your code. Two files are written to the log folder:

          <Name>_<yyyyMMdd-HHmmss>.log             IntuneToolkit log in CMTrace format (open it with
                                                    CMTrace.exe or OneTrace): every Graph request, retry,
                                                    action, warning and error of the IT commands, and
                                                    your own events (Write-ITLog).
          <Name>_<yyyyMMdd-HHmmss>.transcript.log  Transcript: everything else the script prints
                                                    (output, host messages, warnings, errors).

        Two files because Windows locks a transcript file while it is open. Use -NoTranscript for
        the IntuneToolkit log only. Close both with Stop-ITLog at the end of the script (in a
        'finally' block, so the log is also closed when the script fails).

        Log folder, in this order:
          1. -Path (a folder, or a file name ending in .log)
          2. the Intune Management Extension log folder
             (%ProgramData%\Microsoft\IntuneManagementExtension\Logs) when the script is run by
             Intune (platform script, remediation, Win32 app) or with -Intune. These logs are
             included when you collect diagnostics from the device in Intune.
          3. %TEMP%\IntuneToolkit (C:\Windows\Temp\IntuneToolkit when running as SYSTEM).
        If the folder cannot be written, %TEMP%\IntuneToolkit is used and a warning is shown.

        Log files of the same name older than -RetentionDays are deleted.

    .PARAMETER Name
        Base name of the log files. Default: the name of the calling script, or 'IntuneToolkit'.

    .PARAMETER Path
        Custom log folder, or full path of the log file (ending in .log).

    .PARAMETER Intune
        Use the Intune Management Extension log folder even if Intune is not detected.

    .PARAMETER RetentionDays
        Delete older log files with the same name. Default 30; 0 keeps everything.

    .PARAMETER NoTranscript
        Write only the IntuneToolkit log, no transcript.

    .PARAMETER PassThru
        Return the log session (paths, Intune detected, start time).

    .EXAMPLE
        Start-ITLog
        try {
            Connect-ITGraph
            Get-ITStaleDevice -Days 60 | Export-ITReport -Path "$env:TEMP\stale.csv"
        }
        finally {
            Stop-ITLog
        }

        The pattern for every script: log in %TEMP%\IntuneToolkit, or in the Intune log folder
        when Intune runs the script.

    .EXAMPLE
        Start-ITLog -Name 'Monthly-Cleanup' -Path 'D:\Logs\Intune' -RetentionDays 90

        Custom folder and name; keeps 90 days of logs.

    .OUTPUTS
        IntuneToolkit.LogSession (with -PassThru)

    .NOTES
        The transcript header contains the command line that started PowerShell. Do not pass
        secrets on the command line; use certificates (Connect-ITGraph -CertificateThumbprint).

    .LINK
        Stop-ITLog
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneToolkit.LogSession')]
    param(
        [ValidatePattern('^[^\\/:*?"<>|]+$')]
        [string]$Name,

        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Intune,

        [ValidateRange(0, 3650)]
        [int]$RetentionDays = 30,

        [switch]$NoTranscript,

        [switch]$PassThru
    )

    if ($script:ITLogSession) {
        Write-Warning -Message "A log is already running ($($script:ITLogSession.LogPath)); it is closed first."
        Stop-ITLog
    }

    # --- Who is calling? ------------------------------------------------------------------
    $callerScript = $null
    $stack = @(Get-PSCallStack)
    if ($stack.Count -gt 1 -and $stack[1].ScriptName) { $callerScript = $stack[1].ScriptName }
    $baseName = $Name
    if (-not $baseName -and $callerScript) { $baseName = [IO.Path]::GetFileNameWithoutExtension($callerScript) }
    if (-not $baseName) { $baseName = 'IntuneToolkit' }

    $isIntune = [bool]$Intune -or (Test-ITIntuneContext -ScriptPath $callerScript)
    $tempFolder = Join-Path ([IO.Path]::GetTempPath()) 'IntuneToolkit'
    $imeFolder = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'

    # --- Folder and file name -------------------------------------------------------------
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $fileName = '{0}_{1}.log' -f $baseName, $stamp
    $folder = $tempFolder
    $source = 'Temp'
    if ($Path) {
        $source = 'Custom'
        if ($Path -match '\.log$') {
            $folder = Split-Path -Parent $Path
            if (-not $folder) { $folder = (Get-Location).ProviderPath }
            $fileName = Split-Path -Leaf $Path
            $baseName = [IO.Path]::GetFileNameWithoutExtension($fileName)
        }
        else {
            $folder = $Path
        }
    }
    elseif ($isIntune) {
        $folder = $imeFolder
        $source = 'Intune'
    }

    $logPath = Join-Path $folder $fileName
    if (-not $PSCmdlet.ShouldProcess($logPath, 'Start log')) { return }
    try {
        $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop
        [IO.File]::AppendAllText($logPath, '', (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))
    }
    catch {
        Write-Warning -Message "Cannot write to '$folder' ($($_.Exception.Message)); logging to '$tempFolder' instead."
        $folder = $tempFolder
        $source = 'Temp'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $logPath = Join-Path $folder $fileName
    }

    # --- Retention --------------------------------------------------------------------------
    if ($RetentionDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $old = @(Get-ChildItem -Path $folder -Filter ('{0}_*.log' -f $baseName) -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff -and $_.FullName -ne $logPath })
        foreach ($file in $old) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
        if ($old.Count) { Write-Verbose -Message "Removed $($old.Count) log file(s) older than $RetentionDays day(s)." }
    }

    # --- Transcript (everything the script prints) -------------------------------------------
    $transcriptPath = $null
    if (-not $NoTranscript) {
        $transcriptPath = [IO.Path]::ChangeExtension($logPath, '.transcript.log')
        try {
            $null = Start-Transcript -Path $transcriptPath -Append -ErrorAction Stop
        }
        catch {
            Write-Warning -Message "Transcript not started: $($_.Exception.Message)"
            $transcriptPath = $null
        }
    }

    # --- Route the IntuneToolkit log to the file ---------------------------------------------
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $module = $MyInvocation.MyCommand.Module
    $script:ITLogSession = [pscustomobject]@{
        PSTypeName      = 'IntuneToolkit.LogSession'
        Name            = $baseName
        LogPath         = $logPath
        TranscriptPath  = $transcriptPath
        Folder          = $folder
        Location        = $source
        IntuneDetected  = $isIntune
        Script          = $callerScript
        StartTime       = Get-Date
        PreviousLogPath = $script:ITConfig.LogPath
        LoggedErrors    = 0          # Write-ITLog -Level Error from the script
        LoggedWarnings  = 0
        ErrorCountStart = $global:Error.Count   # inside a module $Error is the module's own, empty list
    }
    $script:ITConfig.LogPath = $logPath

    $moduleVersion = ''
    if ($module) { $moduleVersion = [string]$module.Version }
    Write-ITLog -Message ('===== Log started: {0} =====' -f $baseName)
    Write-ITLog -Message ('Script: {0}' -f $(if ($callerScript) { $callerScript } else { '(interactive)' }))
    Write-ITLog -Message ('Computer: {0} | User: {1} | SYSTEM: {2} | Intune: {3}' -f $env:COMPUTERNAME, $identity.Name, $identity.IsSystem, $isIntune)
    Write-ITLog -Message ('PowerShell {0} | IntuneToolkit {1} | Log folder: {2} ({3})' -f $PSVersionTable.PSVersion, $moduleVersion, $folder, $source)
    if ($transcriptPath) { Write-ITLog -Message "Transcript: $transcriptPath" }

    if ($PassThru) { $script:ITLogSession }
}
