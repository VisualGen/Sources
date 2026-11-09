#Requires -Version 5.1
<#
.SYNOPSIS
    Build script for IntuneToolkit (Windows PowerShell 5.1).

.DESCRIPTION
    Tasks (run in the order given):
      Encoding  - make sure every .ps1/.psm1/.psd1 under src/templates/Tests/Examples is UTF-8 *with BOM*
      Manifest  - regenerate FunctionsToExport in the manifest from the files in Public\
      Analyze   - PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1 (fails on Error/Warning)
      Test      - Pester 5 tests in Tests\
      Bump      - raise ModuleVersion (-Version Major|Minor|Patch), set -Prerelease,
                  and move the CHANGELOG [Unreleased] section under the new version
      Package   - copy the module to out\IntuneToolkit\<version>\ and create out\IntuneToolkit-<version>.zip

    Default: Encoding, Manifest, Analyze, Test

.EXAMPLE
    .\build\build.ps1

    Daily check: encoding, export list, analyzer, tests.

.EXAMPLE
    .\build\build.ps1 -Task Bump, Package -Version Minor -Prerelease preview1

    Weekly preview: 0.1.0 -> 0.2.0-preview1, changelog updated, zip created.

.EXAMPLE
    .\build\build.ps1 -Task Encoding, Manifest, Analyze, Test, Bump, Package -Version Minor

    Monthly stable release.
#>
[CmdletBinding()]
param(
    [ValidateSet('Encoding', 'Manifest', 'Analyze', 'Test', 'Bump', 'Package')]
    [string[]]$Task = @('Encoding', 'Manifest', 'Analyze', 'Test'),

    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$Version = 'Patch',

    [ValidatePattern('^[a-zA-Z0-9]*$')]
    [string]$Prerelease = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root         = Split-Path -Parent $PSScriptRoot
$moduleName   = 'IntuneToolkit'
$moduleDir    = Join-Path (Join-Path $root 'src') $moduleName
$manifestPath = Join-Path $moduleDir "$moduleName.psd1"
$changelog    = Join-Path $root 'CHANGELOG.md'
$outDir       = Join-Path $root 'out'
$utf8Bom      = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

function Get-ManifestText { [System.IO.File]::ReadAllText($manifestPath) }
function Set-ManifestText([string]$Text) { [System.IO.File]::WriteAllText($manifestPath, $Text, $utf8Bom) }

function Invoke-EncodingTask {
    Write-Step 'Encoding: ensure UTF-8 with BOM'
    $folders = 'src', 'templates', 'Tests', 'Examples', 'build' | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ }
    $files = Get-ChildItem -Path $folders -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File
    $fixed = 0
    foreach ($file in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        if (-not $hasBom) {
            $text = [System.IO.File]::ReadAllText($file.FullName, (New-Object System.Text.UTF8Encoding $false))
            [System.IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
            $fixed++
        }
    }
    Write-Host "    $($files.Count) files checked, $fixed converted."
}

function Invoke-ManifestTask {
    Write-Step 'Manifest: update FunctionsToExport'
    $names = Get-ChildItem -Path (Join-Path $moduleDir 'Public') -Filter '*.ps1' -Recurse |
        Select-Object -ExpandProperty BaseName | Sort-Object
    $list = ($names | ForEach-Object { "        '$_'" }) -join "`r`n"
    $text = Get-ManifestText
    $new = [regex]::Replace($text, '(?s)FunctionsToExport\s*=\s*@\(.*?\r?\n\s*\)', "FunctionsToExport    = @(`r`n$list`r`n    )")
    if ($new -ne $text) { Set-ManifestText $new }
    Write-Host "    $($names.Count) public functions exported."
}

function Invoke-AnalyzeTask {
    Write-Step 'Analyze: PSScriptAnalyzer'
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { throw 'PSScriptAnalyzer missing: Install-Module PSScriptAnalyzer -Scope CurrentUser' }
    Import-Module PSScriptAnalyzer
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $results = @(
        Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Settings $settings
        Invoke-ScriptAnalyzer -Path (Join-Path $root 'Examples') -Recurse -Settings $settings
    )
    if ($results.Count) { $results | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 250 | Write-Host }
    $blocking = @($results | Where-Object { $_.Severity -in 'Error', 'Warning', 'ParseError' })
    if ($blocking.Count) { throw "PSScriptAnalyzer: $($blocking.Count) error/warning finding(s)." }
    Write-Host "    No blocking findings ($($results.Count) informational)."
}

function Invoke-TestTask {
    Write-Step 'Test: Pester 5+'
    $pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester) { throw 'Pester 5 missing: Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -SkipPublisherCheck -Force' }
    Import-Module $pester.Path -Force

    # Colour rule: red = a real problem only. Pester prints "Running tests from ..." and discovery
    # lines in Magenta (looks red in many consoles) - show them in DarkYellow (console 'orange').
    # Pester has no public theme setting, so adjust its internal table if it exists.
    & (Get-Module Pester) {
        $theme = Get-Variable -Name ReportTheme -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($theme -is [hashtable]) {
            $theme['Container'] = 'DarkYellow'
            $theme['Discovery'] = 'DarkYellow'
        }
    }

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $root 'Tests'
    $config.Run.Exit = $false
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path (Join-Path $root 'TestResults') 'pester.xml'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $config.TestResult.OutputPath.Value)
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { throw "Pester: $($result.FailedCount) test(s) failed." }
}

function Invoke-BumpTask {
    Write-Step "Bump: $Version$(if ($Prerelease) { " ($Prerelease)" })"
    $text = Get-ManifestText
    $current = [version]([regex]::Match($text, "ModuleVersion\s*=\s*'([^']+)'").Groups[1].Value)
    switch ($Version) {
        'Major' { $next = New-Object version ($current.Major + 1), 0, 0 }
        'Minor' { $next = New-Object version $current.Major, ($current.Minor + 1), 0 }
        'Patch' { $next = New-Object version $current.Major, $current.Minor, ($current.Build + 1) }
    }
    $text = [regex]::Replace($text, "ModuleVersion(\s*)=\s*'[^']+'", "ModuleVersion`${1}= '$next'")
    $text = [regex]::Replace($text, "Prerelease(\s*)=\s*'[^']*'", "Prerelease`${1}= '$Prerelease'")
    Set-ManifestText $text

    $label = "$next"
    if ($Prerelease) { $label = "$next-$Prerelease" }
    if (Test-Path $changelog) {
        $log = [System.IO.File]::ReadAllText($changelog)
        $date = Get-Date -Format 'yyyy-MM-dd'
        $log = $log -replace '(?m)^## \[Unreleased\]\s*$', "## [Unreleased]`r`n`r`n## [$label] - $date"
        [System.IO.File]::WriteAllText($changelog, $log, (New-Object System.Text.UTF8Encoding $false))
    }
    Write-Host "    $current -> $label"
}

function Invoke-PackageTask {
    Write-Step 'Package'
    $data = Import-PowerShellDataFile -Path $manifestPath
    $ver  = $data.ModuleVersion
    $pre  = $data.PrivateData.PSData.Prerelease
    $label = $ver
    if ($pre) { $label = "$ver-$pre" }

    $target = Join-Path (Join-Path $outDir $moduleName) $ver
    if (Test-Path $target) { Remove-Item -Path $target -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $target -Force
    Copy-Item -Path (Join-Path $moduleDir '*') -Destination $target -Recurse
    foreach ($doc in 'README.md', 'CHANGELOG.md') {
        if (Test-Path (Join-Path $root $doc)) { Copy-Item (Join-Path $root $doc) $target }
    }

    $zip = Join-Path $outDir "$moduleName-$label.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $outDir $moduleName) -DestinationPath $zip
    Write-Host "    $target"
    Write-Host "    $zip"
}

foreach ($t in $Task) {
    & "Invoke-$($t)Task"
}
Write-Host 'Build completed.' -ForegroundColor Green
