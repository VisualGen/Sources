#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Compliance, configuration profiles, settings catalog, assignment filters. Graph is mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        param([string[]]$Scopes = @('DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementManagedDevices.Read.All'))
        $script:fakeScopes = $Scopes
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = $script:fakeScopes }
        }
    }

    $script:policies = @(
        [pscustomobject]@{ id = 'c1'; displayName = 'Win - Baseline'; '@odata.type' = '#microsoft.graph.windows10CompliancePolicy' }
        [pscustomobject]@{ id = 'c2'; displayName = 'iOS - Baseline'; '@odata.type' = '#microsoft.graph.iosCompliancePolicy' }
    )
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITCompliancePolicy' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceCompliancePolicies' } {
            $script:policies | ForEach-Object { $_.PSObject.Copy() }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
            [pscustomobject]@{ id = 'as1'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g1' } }
        }
    }

    It 'lists policies from v1.0 with Platform, ObjectType and PolicyType' {
        $result = @(Get-ITCompliancePolicy)
        $result.Count | Should -Be 2
        $result[0].Platform | Should -Be 'Windows'
        $result[0].ObjectType | Should -Be 'windows10CompliancePolicy'
        $result[0].PolicyType | Should -Be 'Compliance'
        $result[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.CompliancePolicy'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $ApiVersion -eq 'v1.0' -and $All }
    }

    It 'filters by platform and name' {
        (Get-ITCompliancePolicy -Platform iOS).id | Should -Be 'c2'
        (Get-ITCompliancePolicy -Name 'Win*').id | Should -Be 'c1'
    }

    It 'adds assignments with the correct intent' {
        $p = Get-ITCompliancePolicy -Name 'Win*' -IncludeAssignment
        $p.Assignments[0].Intent | Should -Be 'Exclude'
        $p.Assignments[0].GroupId | Should -Be 'g1'
    }

    It 'needs DeviceManagementConfiguration.Read.All' {
        Set-FakeConnection -Scopes 'User.Read'
        { Get-ITCompliancePolicy } | Should -Throw '*DeviceManagementConfiguration.Read.All*'
    }
}

Describe 'Get-ITDeviceComplianceStatus' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/deviceStatuses' } {
            [pscustomobject]@{ id = 'c1_dev1_u1'; deviceDisplayName = 'PC1'; userPrincipalName = 'a@contoso.com'; status = 'compliant'; lastReportedDateTime = '2026-11-01T00:00:00Z' }
            [pscustomobject]@{ id = 'c1_dev2_u2'; deviceDisplayName = 'PC2'; userPrincipalName = 'b@contoso.com'; status = 'noncompliant'; lastReportedDateTime = '2026-11-01T00:00:00Z' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/deviceCompliancePolicyStates' } {
            [pscustomobject]@{ id = 'c1'; displayName = 'Win - Baseline'; state = 'noncompliant' }
        }
    }

    It 'by policy: one row per device, device ID taken from the status ID' {
        $rows = @(Get-ITDeviceComplianceStatus -PolicyId 'c1')
        $rows.Count | Should -Be 2
        $rows[1].DeviceId | Should -Be 'dev2'
        $rows[1].Status | Should -Be 'noncompliant'
    }

    It 'filters by -Status' {
        (Get-ITDeviceComplianceStatus -PolicyId 'c1' -Status noncompliant).DeviceName | Should -Be 'PC2'
    }

    It 'pipeline: a compliance policy reads deviceStatuses, a managed device reads its policy states' {
        $policy = [pscustomobject]@{ id = 'c1'; displayName = 'Win - Baseline'; PolicyType = 'Compliance' }
        @($policy | Get-ITDeviceComplianceStatus).Count | Should -Be 2
        @($policy | Get-ITDeviceComplianceStatus)[0].PolicyName | Should -Be 'Win - Baseline'

        $device = [pscustomobject]@{ id = 'dev9'; deviceName = 'PC9' }
        $row = $device | Get-ITDeviceComplianceStatus
        $row.DeviceName | Should -Be 'PC9'
        $row.PolicyName | Should -Be 'Win - Baseline'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -eq 'deviceManagement/managedDevices/dev9/deviceCompliancePolicyStates' }
    }
}

Describe 'Get-ITNonCompliantDevice' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/managedDevices?*' } {
            [pscustomobject]@{ id = 'd1'; deviceName = 'PC1'; complianceState = 'noncompliant' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/deviceCompliancePolicyStates' } {
            [pscustomobject]@{ id = 'c1'; displayName = 'Win - Baseline'; state = 'nonCompliant' }
            [pscustomobject]@{ id = 'c3'; displayName = 'Win - BitLocker'; state = 'compliant' }
        }
    }

    It 'filters non-compliant devices on the server' {
        @(Get-ITNonCompliantDevice).Count | Should -Be 1
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { [uri]::UnescapeDataString($Uri) -like "*complianceState eq 'noncompliant'*" }
    }

    It 'adds the failing policy names with -IncludePolicy' {
        (Get-ITNonCompliantDevice -IncludePolicy).FailedPolicies | Should -Be @('Win - Baseline')
    }

    It 'also queries inGracePeriod with -IncludeGracePeriod' {
        $null = Get-ITNonCompliantDevice -IncludeGracePeriod
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { [uri]::UnescapeDataString($Uri) -like "*complianceState eq 'inGracePeriod'*" }
    }
}

Describe 'Get-ITConfigurationProfile' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ id = 'p1'; displayName = 'Win - Custom'; '@odata.type' = '#microsoft.graph.windows10CustomConfiguration' }
            [pscustomobject]@{ id = 'p2'; displayName = 'iOS - Wifi'; '@odata.type' = '#microsoft.graph.iosWiFiConfiguration' }
        }
    }

    It 'filters by ObjectType wildcard and platform' {
        (Get-ITConfigurationProfile -ObjectType '*Custom*').id | Should -Be 'p1'
        (Get-ITConfigurationProfile -Platform iOS).id | Should -Be 'p2'
        (Get-ITConfigurationProfile)[0].PolicyType | Should -Be 'DeviceConfiguration'
    }
}

Describe 'Get-ITSettingsCatalogPolicy' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies' } {
            [pscustomobject]@{ id = 's1'; name = 'Win - Edge'; platforms = 'windows10'; settingCount = 1 }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/settings' } {
            [pscustomobject]@{ id = '0'; settingInstance = [pscustomobject]@{ settingDefinitionId = 'edge_home'; simpleSettingValue = [pscustomobject]@{ value = 'https://contoso.com' } } }
        }
    }

    It 'uses beta, copies name to displayName and adds SettingList with -IncludeSetting' {
        $p = Get-ITSettingsCatalogPolicy -IncludeSetting
        $p.displayName | Should -Be 'Win - Edge'
        $p.Platform | Should -Be 'Windows'
        $p.SettingList[0].SettingDefinitionId | Should -Be 'edge_home'
        $p.SettingList[0].Value | Should -Be 'https://contoso.com'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $ApiVersion -eq 'beta' -and $Uri -like '*/settings' -and $All }
    }

    It 'does not read settings without -IncludeSetting' {
        $null = Get-ITSettingsCatalogPolicy
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Uri -like '*/settings' }
    }
}

Describe 'Get-ITAssignmentFilter' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ id = 'f1'; displayName = 'Windows 11'; platform = 'windows10AndLater'; rule = '(device.osVersion -startsWith "10.0.22")' }
            [pscustomobject]@{ id = 'f2'; displayName = 'Corporate iOS'; platform = 'iOS'; rule = '(device.deviceOwnership -eq "Corporate")' }
        }
    }

    It 'filters by name and platform' {
        (Get-ITAssignmentFilter -Name 'Windows*').id | Should -Be 'f1'
        (Get-ITAssignmentFilter -Platform iOS).id | Should -Be 'f2'
        (Get-ITAssignmentFilter)[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.AssignmentFilter'
    }
}
