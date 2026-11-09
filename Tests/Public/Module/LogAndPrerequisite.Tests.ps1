#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Start-ITLog / Stop-ITLog (script logging) and Test-ITPrerequisite (machine check). No Graph calls.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force -WarningAction SilentlyContinue

    # Parses a log in CMTrace format; throws when any text in the file is not a valid CMTrace entry
    function Read-CMTraceLog([string]$Path) {
        $raw = [IO.File]::ReadAllText($Path)
        $pattern = '<!\[LOG\[(?<Message>.*?)\]LOG\]!><time="(?<Time>\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d+)" date="(?<Date>\d{2}-\d{2}-\d{4})" component="(?<Component>[^"]*)" context="(?<Context>[^"]*)" type="(?<Type>[123])" thread="(?<Thread>\d+)" file="(?<File>[^"]*)">\r?\n'
        $found = [regex]::Matches($raw, $pattern, 'Singleline')
        $rest = [regex]::Replace($raw, $pattern, '', 'Singleline').Trim([char]0xFEFF, [char]13, [char]10, ' ')
        if ($rest) { throw "Not CMTrace format: $($rest.Substring(0, [math]::Min(120, $rest.Length)))" }
        foreach ($m in $found) {
            [pscustomobject]@{ Message = $m.Groups['Message'].Value; Component = $m.Groups['Component'].Value; Type = [int]$m.Groups['Type'].Value
                File = $m.Groups['File'].Value; Thread = [int]$m.Groups['Thread'].Value; Time = $m.Groups['Time'].Value; Date = $m.Groups['Date'].Value }
        }
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Start-ITLog / Stop-ITLog' {
    BeforeEach {
        $script:savedTmp = $env:TMP
        $script:savedTemp = $env:TEMP
        $script:savedProgramData = $env:ProgramData
        $env:TMP = Join-Path $TestDrive 'tmp'
        $env:TEMP = $env:TMP
        $env:ProgramData = Join-Path $TestDrive 'ProgramData'
        Mock -ModuleName IntuneToolkit Test-ITIntuneContext { $false }
    }

    AfterEach {
        Stop-ITLog
        $env:TMP = $script:savedTmp
        $env:TEMP = $script:savedTemp
        $env:ProgramData = $script:savedProgramData
    }

    It 'logs to the temp folder by default and routes the IntuneToolkit log to the file' {
        $s = Start-ITLog -Name 'Demo' -NoTranscript -PassThru
        $s.Location | Should -Be 'Temp'
        $s.LogPath | Should -BeLike (Join-Path $env:TMP 'IntuneToolkit\Demo_*.log')
        (Get-ITConfiguration).LogPath | Should -Be $s.LogPath
        $null = Get-ITContext                       # any IntuneToolkit command logs on its own
        Stop-ITLog -Status 'Success'
        $entries = @(Read-CMTraceLog $s.LogPath)
        $entries[0].Message | Should -Match 'Log started: Demo'
        ($entries | Where-Object Component -eq 'Get-ITContext').Message | Should -Match 'Not connected'
        $entries[-2].Message | Should -Match 'Status: Success \| Duration'
        $entries[-1].Message | Should -Match 'Log closed: Demo'
        $entries[0].Thread | Should -Be $PID
    }

    It 'uses the Intune Management Extension log folder when Intune runs the script' {
        Mock -ModuleName IntuneToolkit Test-ITIntuneContext { $true }
        $s = Start-ITLog -Name 'Remediation' -NoTranscript -PassThru
        $s.Location | Should -Be 'Intune'
        $s.IntuneDetected | Should -BeTrue
        $s.Folder | Should -Be (Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs')
        Test-Path $s.LogPath | Should -BeTrue
    }

    It 'falls back to the temp folder when the Intune folder cannot be written' {
        # TestDrive is shared by the whole Describe: use a fresh ProgramData where a FILE named 'Microsoft' blocks the folder
        $env:ProgramData = Join-Path $TestDrive 'ProgramData-blocked'
        $null = New-Item -ItemType Directory -Path $env:ProgramData -Force
        $null = New-Item -ItemType File -Path (Join-Path $env:ProgramData 'Microsoft')
        $s = Start-ITLog -Name 'Remediation' -Intune -NoTranscript -PassThru -WarningVariable warn -WarningAction SilentlyContinue
        $s.Location | Should -Be 'Temp'
        "$warn" | Should -Match 'Cannot write'
    }

    It 'accepts a custom folder or a full .log file path' {
        $s = Start-ITLog -Path (Join-Path $TestDrive 'logs') -Name 'Custom' -NoTranscript -PassThru
        $s.Location | Should -Be 'Custom'
        $s.LogPath | Should -BeLike (Join-Path $TestDrive 'logs\Custom_*.log')
        Stop-ITLog
        $s = Start-ITLog -Path (Join-Path $TestDrive 'logs\fixed-name.log') -NoTranscript -PassThru
        $s.LogPath | Should -Be (Join-Path $TestDrive 'logs\fixed-name.log')
        $s.Name | Should -Be 'fixed-name'
    }

    It 'writes a transcript next to the log and closes it' {
        $s = Start-ITLog -Path (Join-Path $TestDrive 'tr') -Name 'WithTranscript' -PassThru
        $s.TranscriptPath | Should -BeLike '*WithTranscript_*.transcript.log'
        Write-Host 'visible line from the script'
        Stop-ITLog
        Get-Content -Path $s.TranscriptPath -Raw | Should -Match 'visible line from the script'
        { Add-Content -Path $s.TranscriptPath -Value 'unlocked' -ErrorAction Stop } | Should -Not -Throw   # file closed
    }

    It 'records the errors of the script in the summary' {
        $s = Start-ITLog -Name 'Errors' -NoTranscript -PassThru
        Write-Error 'something failed in the script' -ErrorAction SilentlyContinue
        $closed = Stop-ITLog -PassThru
        $closed.ErrorCount | Should -Be 1
        $err = Read-CMTraceLog $s.LogPath | Where-Object Message -like 'Error recorded:*'
        $err.Message | Should -BeLike 'Error recorded: something failed in the script*'   # + (line N)
        $err.Type | Should -Be 3
    }

    It 'restores the previous log setting and ignores a second Stop-ITLog' {
        $before = Join-Path $TestDrive 'before.log'
        Set-ITConfiguration -LogPath $before
        $null = Start-ITLog -Name 'Restore' -NoTranscript
        Stop-ITLog
        (Get-ITConfiguration).LogPath | Should -Be $before
        { Stop-ITLog } | Should -Not -Throw
        Set-ITConfiguration -LogPath ''
    }

    It 'closes a running log before starting a new one' {
        $first = Start-ITLog -Name 'First' -NoTranscript -PassThru
        $second = Start-ITLog -Name 'Second' -NoTranscript -PassThru -WarningAction SilentlyContinue
        (Read-CMTraceLog $first.LogPath)[-1].Message | Should -Be '===== Log closed: First ====='
        (Get-ITConfiguration).LogPath | Should -Be $second.LogPath
    }

    It 'deletes logs of the same name older than -RetentionDays' {
        $folder = Join-Path $TestDrive 'retention'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $old = New-Item -ItemType File -Path (Join-Path $folder 'Job_20200101-000000.log')
        $old.LastWriteTime = (Get-Date).AddDays(-40)
        $recent = New-Item -ItemType File -Path (Join-Path $folder 'Job_20260101-000000.log')
        $other = New-Item -ItemType File -Path (Join-Path $folder 'Other_20200101-000000.log')
        $other.LastWriteTime = (Get-Date).AddDays(-40)
        $null = Start-ITLog -Path $folder -Name 'Job' -RetentionDays 30 -NoTranscript
        Test-Path $old.FullName | Should -BeFalse
        Test-Path $recent.FullName | Should -BeTrue
        Test-Path $other.FullName | Should -BeTrue
    }
}

Describe 'Write-ITLog' {
    BeforeEach {
        Mock -ModuleName IntuneToolkit Test-ITIntuneContext { $false }
        $script:log = Start-ITLog -Path (Join-Path $TestDrive 'events') -Name 'Events' -NoTranscript -PassThru
    }

    AfterEach {
        Stop-ITLog
    }

    It 'writes Info, Warning and Error entries with the script as source' {
        Write-ITLog 'step one'
        Write-ITLog -Message 'low disk' -Level Warning -WarningAction SilentlyContinue
        $errorsBefore = $global:Error.Count
        Write-ITLog -Message 'policy missing' -Level Error 2>$null
        $global:Error.Count | Should -Be $errorsBefore          # no PowerShell error: the script continues
        $entries = @(Read-CMTraceLog $script:log.LogPath | Where-Object { $_.Component -eq 'LogAndPrerequisite.Tests.ps1' -and $_.Message -in 'step one', 'low disk', 'policy missing' })
        $entries.Message | Should -Be @('step one', 'low disk', 'policy missing')
        $entries.Type | Should -Be @(1, 2, 3)                    # CMTrace: 1 Info, 2 Warning (yellow), 3 Error (red)
        $entries[0].File | Should -Match '^LogAndPrerequisite\.Tests\.ps1:\d+$'
    }

    It 'logs a caught error with exception type, line and call stack' {
        try { throw [System.IO.FileNotFoundException]::new('config.json not found') }
        catch { Write-ITLog -ErrorRecord $_ -Message 'Loading config' 2>$null }
        $e = Read-CMTraceLog $script:log.LogPath | Where-Object { $_.Type -eq 3 -and $_.Message -like 'Loading config*' }
        $lines = $e.Message -split "`r?`n"                       # one entry; details on extra lines (CMTrace detail pane)
        $lines[0] | Should -Be 'Loading config: config.json not found'
        $lines[1] | Should -Match 'Exception: System\.IO\.FileNotFoundException \| at LogAndPrerequisite\.Tests\.ps1:\d+'
        $lines.Count | Should -BeGreaterThan 2                   # call stack
    }

    It 'counts the script errors and warnings in the Stop-ITLog summary' {
        Write-ITLog -Level Error -Message 'e1' 2>$null
        Write-ITLog -Level Error -Message 'e2' 2>$null
        Write-ITLog -Level Warning -Message 'w1' -WarningAction SilentlyContinue
        $null = Get-ITContext                                     # module entries are not counted
        Stop-ITLog
        (Read-CMTraceLog $script:log.LogPath | Where-Object Component -eq 'Stop-ITLog').Message | Should -Contain ((Read-CMTraceLog $script:log.LogPath | Where-Object Message -like '*errors logged: 2 | warnings logged: 1*').Message)
    }

    It 'accepts pipeline input and keeps multi-line messages on one line' {
        "first`r`nsecond" | Write-ITLog
        (Read-CMTraceLog $script:log.LogPath)[-1].Message | Should -Be 'first | second'
    }

    It 'keeps the CMTrace structure for quotes, brackets and the end marker in messages' {
        Write-ITLog 'Policy "Win - Edge" [v2] ]LOG]!> done'
        $e = (Read-CMTraceLog $script:log.LogPath)[-1]
        $e.Message | Should -Be 'Policy "Win - Edge" [v2] ] LOG]!> done'
        $e.Date | Should -Be (Get-Date -Format 'MM-dd-yyyy')
        $bias = -[int][TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
        $e.Time | Should -Match ('[+-]{0}$' -f [math]::Abs($bias))
    }

    It 'only shows the entry when no log file is set' {
        Stop-ITLog
        { Write-ITLog -Message 'no file' -Level Error 2>$null } | Should -Not -Throw
        (Get-ITConfiguration).LogPath | Should -BeNullOrEmpty
    }
}

Describe 'Test-ITIntuneContext' {
    It 'recognises scripts started from the Intune Management Extension folders' {
        InModuleScope IntuneToolkit {
            Test-ITIntuneContext -ScriptPath 'C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts\abc.ps1' | Should -BeTrue
            Test-ITIntuneContext -ScriptPath 'C:\WINDOWS\IMECache\abc_1\install.ps1' | Should -BeTrue
        }
    }

    It 'is false for a normal script started from a console' {
        InModuleScope IntuneToolkit {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'powershell.exe'; ParentProcessId = 0 } }
            Test-ITIntuneContext -ScriptPath 'C:\Scripts\report.ps1' | Should -BeFalse
        }
    }

    It 'is true when a parent process is the Intune agent' {
        InModuleScope IntuneToolkit {
            Mock Get-CimInstance -ParameterFilter { $Filter -eq "ProcessId = $PID" } { [pscustomobject]@{ Name = 'powershell.exe'; ParentProcessId = 4242 } }
            Mock Get-CimInstance -ParameterFilter { $Filter -eq 'ProcessId = 4242' } { [pscustomobject]@{ Name = 'AgentExecutor.exe'; ParentProcessId = 1 } }
            Test-ITIntuneContext -ScriptPath 'C:\Temp\x.ps1' | Should -BeTrue
        }
    }
}

Describe 'Test-ITPrerequisite' {
    BeforeEach {
        $script:authVersion = '2.41.2'
        $script:loaded = $true
        $script:otherVersion = '2.41.2'
        $script:netRelease = 533320
        Mock -ModuleName IntuneToolkit Get-ItemProperty { [pscustomobject]@{ Release = $script:netRelease } }
        Mock -ModuleName IntuneToolkit Get-ITNuGetProviderVersion { [version]'2.8.5.208' }
        Mock -ModuleName IntuneToolkit Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication' } {
            if ($script:authVersion) { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication'; Version = [version]$script:authVersion } }
        }
        Mock -ModuleName IntuneToolkit Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.Graph.*' } {
            if ($script:authVersion) { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication'; Version = [version]$script:authVersion } }
            [pscustomobject]@{ Name = 'Microsoft.Graph.Users'; Version = [version]$script:otherVersion }
        }
        Mock -ModuleName IntuneToolkit Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShellGet' } {
            [pscustomobject]@{ Name = 'PowerShellGet'; Version = [version]'2.2.5' }
        }
        Mock -ModuleName IntuneToolkit Get-Module -ParameterFilter { -not $ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication' } {
            if ($script:loaded) { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication'; Version = [version]$script:authVersion } }
        }
    }

    It 'reports OK for a ready machine' {
        $r = @(Test-ITPrerequisite)
        $r[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.PrerequisiteCheck'
        $r | Where-Object Status -ne 'OK' | Should -BeNullOrEmpty
        ($r | Where-Object Check -eq '.NET Framework').Found | Should -Match '4\.8\.1'
        Test-ITPrerequisite -Quiet | Should -BeTrue
        @($r | Where-Object Check -eq 'Module install tools').Count | Should -Be 0
    }

    It 'reports a missing Graph module with the install command' {
        $script:authVersion = $null
        $script:loaded = $false
        $r = @(Test-ITPrerequisite)
        $inst = $r | Where-Object Check -eq 'Graph module installed'
        $inst.Status | Should -Be 'Missing'
        $inst.Fix | Should -Be 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
        ($r | Where-Object Check -eq 'Graph module loaded').Status | Should -Be 'Failed'
        ($r | Where-Object Check -eq 'Module install tools').Status | Should -Be 'OK'
        Test-ITPrerequisite -Quiet | Should -BeFalse
    }

    It 'reports an outdated Graph module' {
        $script:authVersion = '1.28.0'
        $r = @(Test-ITPrerequisite)
        ($r | Where-Object Check -eq 'Graph module installed').Status | Should -Be 'Outdated'
        ($r | Where-Object Check -eq 'Graph module loaded').Status | Should -Be 'Outdated'
    }

    It 'warns about mixed Microsoft.Graph module versions without blocking' {
        $script:otherVersion = '2.30.0'
        $w = Test-ITPrerequisite | Where-Object Check -eq 'Graph module versions'
        $w.Status | Should -Be 'Warning'
        $w.Found | Should -Match 'Microsoft.Graph.Users 2.30.0'
        Test-ITPrerequisite -Quiet | Should -BeTrue
    }

    It 'reports an old .NET Framework' {
        $script:netRelease = 460798
        $n = Test-ITPrerequisite | Where-Object Check -eq '.NET Framework'
        $n.Status | Should -Be 'Outdated'
        $n.Found | Should -Match '^4\.7 '
    }
}
