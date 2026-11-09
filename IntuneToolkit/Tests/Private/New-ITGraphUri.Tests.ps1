#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'New-ITGraphUri' {
    It 'returns the path when no options are given' {
        InModuleScope IntuneToolkit { New-ITGraphUri -Path 'deviceManagement/managedDevices' } |
            Should -Be 'deviceManagement/managedDevices'
    }

    It 'URL-encodes a single filter' {
        InModuleScope IntuneToolkit { New-ITGraphUri -Path 'x' -Filter "deviceName eq 'PC 1'" } |
            Should -Be 'x?$filter=deviceName%20eq%20%27PC%201%27'
    }

    It 'joins several filters with and, each in parentheses' {
        $uri = InModuleScope IntuneToolkit { New-ITGraphUri -Path 'x' -Filter "a eq '1'", "b eq '2'" }
        [uri]::UnescapeDataString($uri) | Should -Be "x?`$filter=(a eq '1') and (b eq '2')"
    }

    It 'ignores empty filter entries' {
        InModuleScope IntuneToolkit { New-ITGraphUri -Path 'x' -Filter @('', $null) } | Should -Be 'x'
    }

    It 'adds select, expand, orderby and top' {
        $uri = InModuleScope IntuneToolkit { New-ITGraphUri -Path 'x' -Select id, deviceName -Expand users -OrderBy 'deviceName desc' -Top 5 }
        [uri]::UnescapeDataString($uri) | Should -Be 'x?$select=id,deviceName&$expand=users&$orderby=deviceName desc&$top=5'
    }
}

Describe 'ConvertTo-ITODataString' {
    It 'doubles single quotes' {
        InModuleScope IntuneToolkit { ConvertTo-ITODataString "O'Brien" } | Should -Be "O''Brien"
    }
}
