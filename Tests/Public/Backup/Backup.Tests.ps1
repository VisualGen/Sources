#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Export-ITPolicy / Import-ITPolicy / Compare-ITPolicy. Graph is mocked; files go to TestDrive.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        param([string]$TenantId = 't1')
        $script:fakeTenant = $TenantId
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = $script:fakeTenant; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = @('DeviceManagementConfiguration.ReadWrite.All') }
        }
    }

    function New-Policy {
        param([string]$Value = 'https://contoso.com')
        [pscustomobject]@{ id = 's1'; name = 'Win - Edge'; platforms = 'windows10'; technologies = 'mdm'; roleScopeTagIds = @('0', '7')
            lastModifiedDateTime = '2026-11-01T10:00:00Z'; settingCount = 1; '@odata.context' = 'x' }
    }
    function New-Setting {
        param([string]$Value = 'https://contoso.com')
        [pscustomobject]@{ id = '0'; settingInstance = [pscustomobject]@{ settingDefinitionId = 'edge_home'; simpleSettingValue = [pscustomobject]@{ value = $Value } } }
    }

    function Set-PolicyMocks {
        param([string]$Value = 'https://contoso.com')
        $script:settingValue = $Value
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies' -and -not $Method } { New-Policy }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies/s1' } { New-Policy }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies/s1/settings' } { New-Setting -Value $script:settingValue }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
            [pscustomobject]@{ id = 'a1'; source = 'direct'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } }
        }
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Export-ITPolicy' {
    BeforeEach {
        Set-FakeConnection
        Set-PolicyMocks
        $script:backup = Join-Path $TestDrive ('b' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    }

    It 'writes one JSON per object in a folder per policy type, with metadata, settings and assignments' {
        $r = Export-ITPolicy -Path $script:backup -PolicyType SettingsCatalog
        $r.Path | Should -BeLike '*\SettingsCatalog\Win - Edge__s1.json'
        $doc = Get-Content $r.Path -Raw | ConvertFrom-Json
        $doc.IntuneToolkit.PolicyType | Should -Be 'SettingsCatalog'
        $doc.IntuneToolkit.TenantId | Should -Be 't1'
        $doc.IntuneToolkit.SourceId | Should -Be 's1'
        $doc.Object.settings[0].settingInstance.settingDefinitionId | Should -Be 'edge_home'
        $doc.Object.PSObject.Properties.Name | Should -Not -Contain '@odata.context'
        $doc.Assignments[0].target.groupId | Should -Be 'g1'
    }

    It 'exports piped objects by Id' {
        $r = [pscustomobject]@{ PolicyType = 'SettingsCatalog'; id = 's1' } | Export-ITPolicy -Path $script:backup
        $r.Id | Should -Be 's1'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies' }
    }
}

Describe 'Import-ITPolicy' {
    BeforeAll {
        Set-FakeConnection
        Set-PolicyMocks
        $script:exportDir = Join-Path $TestDrive 'import-src'
        $script:file = (Export-ITPolicy -Path $script:exportDir -PolicyType SettingsCatalog).Path
    }

    BeforeEach {
        Set-FakeConnection
        Set-PolicyMocks
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies' -and $Method -eq 'POST' } { [pscustomobject]@{ id = 'new1' } }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assign' } { }
    }

    It 'skips an object whose name already exists' {
        (Import-ITPolicy -Path $script:file).Status | Should -Be 'Exists'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'creates a copy with a prefix, without IDs; keeps scope tags in the same tenant' {
        $r = Import-ITPolicy -Path $script:file -NamePrefix 'Restored - '
        $r.Status | Should -Be 'Created'
        $r.NewId | Should -Be 'new1'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body['name'] -eq 'Restored - Win - Edge' -and -not $Body.Contains('id') -and
            -not $Body.Contains('settingCount') -and @($Body['roleScopeTagIds']).Count -eq 2 -and
            $Body['settings'][0].settingInstance.settingDefinitionId -eq 'edge_home'
        }
    }

    It 'other tenant: removes scope tags and does not apply assignments' {
        Set-FakeConnection -TenantId 't2'
        $r = Import-ITPolicy -Path $script:exportDir -NamePrefix 'X ' -IncludeAssignment
        $r.Status | Should -Be 'Created'
        $r.Message | Should -BeLike '*another tenant*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'deviceManagement/configurationPolicies' -and -not $Body.Contains('roleScopeTagIds') }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Uri -like '*/assign' }
    }

    It 'same tenant with -IncludeAssignment applies the exported assignments' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies/new1/assignments' } { }
        $r = Import-ITPolicy -Path $script:file -NamePrefix 'Y ' -IncludeAssignment
        $r.Message | Should -Be '1 assignment(s) applied.'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies/new1/assign' }
    }

    It '-WhatIf creates nothing' {
        (Import-ITPolicy -Path $script:file -NamePrefix 'Z ' -WhatIf).Status | Should -Be 'WhatIf'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'rejects files that are not IntuneToolkit exports' {
        $bad = Join-Path $TestDrive 'bad.json'
        '{"foo":1}' | Set-Content $bad
        $r = Import-ITPolicy -Path $bad -ErrorAction SilentlyContinue
        $r.Status | Should -Be 'Failed'
        $r.Message | Should -BeLike '*Not an IntuneToolkit export*'
    }
}

Describe 'Compare-ITPolicy' {
    BeforeAll {
        Set-FakeConnection
        Set-PolicyMocks
        $script:cmpFile = (Export-ITPolicy -Path (Join-Path $TestDrive 'cmp') -PolicyType SettingsCatalog).Path
    }

    BeforeEach { Set-FakeConnection }

    It 'returns nothing when backup and tenant are the same' {
        Set-PolicyMocks
        @(Compare-ITPolicy -Path $script:cmpFile).Count | Should -Be 0
    }

    It 'reports a changed setting by definition ID' {
        Set-PolicyMocks -Value 'https://evil.example'
        $d = @(Compare-ITPolicy -Path $script:cmpFile)
        $d.Count | Should -Be 1
        $d[0].Property | Should -Be 'setting:edge_home'
        $d[0].Change | Should -Be 'Changed'
        $d[0].BackupValue | Should -Be 'https://contoso.com'
        $d[0].TenantValue | Should -Be 'https://evil.example'
    }

    It 'reports a changed assignment' {
        Set-PolicyMocks
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
            [pscustomobject]@{ id = 'a9'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
        }
        $d = @(Compare-ITPolicy -Path $script:cmpFile)
        ($d | Where-Object Change -eq 'OnlyInTenant').Property | Should -BeLike 'assignments.allDevicesAssignmentTarget*'
        ($d | Where-Object Change -eq 'OnlyInBackup').Property | Should -Be 'assignments.groupAssignmentTarget:g1'
    }

    It 'reports MissingInTenant when the object was deleted' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies/s1' } { throw 'Graph request failed: GET x -> HTTP 404 [ResourceNotFound]: gone' }
        (Compare-ITPolicy -Path $script:cmpFile).Change | Should -Be 'MissingInTenant'
    }

    It '-ExcludeAssignment ignores assignment drift' {
        Set-PolicyMocks
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } { }
        @(Compare-ITPolicy -Path $script:cmpFile -ExcludeAssignment).Count | Should -Be 0
    }
}
