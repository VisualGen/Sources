#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Module-wide quality gates: manifest, exports, naming conventions, help, encoding.

BeforeDiscovery {
    $root      = Split-Path -Parent $PSScriptRoot
    $moduleDir = Join-Path (Join-Path $root 'src') 'IntuneToolkit'
    $publicFiles = @(Get-ChildItem -Path (Join-Path $moduleDir 'Public') -Filter '*.ps1' -Recurse)
    $publicCases = @($publicFiles | ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } })
    $scriptCases = @(Get-ChildItem -Path $moduleDir -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $root         = Split-Path -Parent $PSScriptRoot
    $moduleDir    = Join-Path (Join-Path $root 'src') 'IntuneToolkit'
    $manifestPath = Join-Path $moduleDir 'IntuneToolkit.psd1'
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module $manifestPath -Force
    $approvedVerbs = (Get-Verb).Verb
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Module manifest' {
    It 'is a valid manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'targets Windows PowerShell 5.1 Desktop' {
        $data = Import-PowerShellDataFile -Path $manifestPath
        $data.PowerShellVersion | Should -Be '5.1'
        $data.CompatiblePSEditions | Should -Contain 'Desktop'
    }

    It 'has author and description metadata' {
        $data = Import-PowerShellDataFile -Path $manifestPath
        $data.Author | Should -Not -BeNullOrEmpty
        $data.Description | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions in Public\' {
        $data = Import-PowerShellDataFile -Path $manifestPath
        $expected = @(Get-ChildItem -Path (Join-Path $moduleDir 'Public') -Filter '*.ps1' -Recurse).BaseName | Sort-Object
        @($data.FunctionsToExport | Sort-Object) | Should -Be $expected
        @((Get-Command -Module IntuneToolkit).Name | Sort-Object) | Should -Be $expected
    }

    It 'does not export private functions' {
        Get-Command -Module IntuneToolkit -Name 'Invoke-ITGraphRequest' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Public function <Name>' -ForEach $publicCases {
    BeforeAll {
        $command = Get-Command -Name $Name -Module IntuneToolkit
        $help    = Get-Help -Name $Name -Full
        $verb, $noun = $Name -split '-', 2
    }

    It 'file contains exactly one function with the same name' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
        $functions.Count | Should -Be 1
        $functions[0].Name | Should -Be $Name
    }

    It 'uses an approved verb' {
        $approvedVerbs | Should -Contain $verb
    }

    It 'uses the IT noun prefix' {
        $noun | Should -MatchExactly '^IT[A-Z][A-Za-z0-9]+$'
    }

    It 'is an advanced function (CmdletBinding)' {
        $command.CmdletBinding | Should -BeTrue
    }

    It 'has a synopsis' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match "^\s*$Name"   # auto-generated help repeats the syntax
    }

    It 'has a description' {
        ($help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
    }

    It 'has at least one example' {
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        $params = $command.Parameters.Keys | Where-Object { $common -notcontains $_ }
        foreach ($p in $params) {
            $doc = $help.Parameters.Parameter | Where-Object { $_.Name -eq $p }
            ($doc.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty -Because "parameter -$p must be documented"
        }
    }

    It 'supports -WhatIf when the verb changes state' {
        $readOnly = 'Get', 'Test', 'Export', 'Compare', 'Find', 'Search', 'Measure', 'Resolve', 'Show', 'Format', 'ConvertTo', 'ConvertFrom', 'Connect', 'Wait', 'Watch', 'Write'   # Write-*: like Write-Verbose/Write-Error, logging must work under -WhatIf
        if ($readOnly -notcontains $verb) {
            $command.Parameters.Keys | Should -Contain 'WhatIf'
        }
    }

    It 'does not use Write-Host' {
        (Get-Content -Path $Path -Raw) | Should -Not -Match '\bWrite-Host\b'
    }
}

Describe 'File encoding <Name>' -ForEach $scriptCases {
    It 'is UTF-8 with BOM (required by Windows PowerShell 5.1)' {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
    }
}
