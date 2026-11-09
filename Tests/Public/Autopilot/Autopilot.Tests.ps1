#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Autopilot functions. Graph is never called: Invoke-ITGraphRequest is mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        param([string[]]$Scopes = @('DeviceManagementServiceConfig.ReadWrite.All'))
        $script:fakeScopes = $Scopes
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't'; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = $script:fakeScopes }
        }
    }
    function Get-Decoded([string]$Uri) { [uri]::UnescapeDataString($Uri) }

    $script:hash = [Convert]::ToBase64String([byte[]](1..64))
    $script:apDevices = @(
        [pscustomobject]@{ id = 'ap-1'; serialNumber = 'PF3A0001'; model = 'Surface Laptop 5'; groupTag = 'Sales'; enrollmentState = 'enrolled'; managedDeviceId = 'md-1' }
        [pscustomobject]@{ id = 'ap-2'; serialNumber = 'PF3A0002'; model = 'Latitude 7440'; groupTag = ''; enrollmentState = 'notContacted'; managedDeviceId = '00000000-0000-0000-0000-000000000000' }
        [pscustomobject]@{ id = 'ap-3'; serialNumber = 'XY990003'; model = 'Surface Pro 9'; groupTag = $null; enrollmentState = 'notContacted'; managedDeviceId = '00000000-0000-0000-0000-000000000000' }
    )
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITAutopilotDevice' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest { $script:apDevices }
    }

    It 'lists all devices from v1.0 with paging' {
        @(Get-ITAutopilotDevice).Count | Should -Be 3
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq 'deviceManagement/windowsAutopilotDeviceIdentities' -and $All -and $ApiVersion -eq 'v1.0'
        }
    }

    It 'uses a server-side contains filter for -SerialNumber' {
        Get-ITAutopilotDevice -SerialNumber 'PF3A' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { (Get-Decoded $Uri) -like "*contains(serialNumber,'PF3A')*" }
    }

    It 'filters group tag locally; empty string finds devices without a tag' {
        (Get-ITAutopilotDevice -GroupTag 'Sal*').id | Should -Be 'ap-1'
        (Get-ITAutopilotDevice -GroupTag '').id | Should -Be @('ap-2', 'ap-3')
    }

    It 'filters model and enrollment state locally' {
        (Get-ITAutopilotDevice -Model 'Surface*').id | Should -Be @('ap-1', 'ap-3')
        (Get-ITAutopilotDevice -EnrollmentState notContacted).id | Should -Be @('ap-2', 'ap-3')
    }

    It 'tags results as IntuneToolkit.AutopilotDevice' {
        (Get-ITAutopilotDevice)[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.AutopilotDevice'
    }

    It 'needs only the Read scope' {
        Set-FakeConnection -Scopes 'DeviceManagementServiceConfig.Read.All'
        { Get-ITAutopilotDevice } | Should -Not -Throw
    }
}

Describe 'Import-ITAutopilotDevice' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Start-Sleep { }
        Mock -ModuleName IntuneToolkit Write-Progress { }
        Mock -ModuleName IntuneToolkit Invoke-ITAutopilotSync { }
        $script:importCounter = 0
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'POST' } {
            $script:importCounter++
            [pscustomobject]@{ id = "imp-$($script:importCounter)"; state = [pscustomobject]@{ deviceImportStatus = 'pending' } }
        }
        # GET calls do not pass -Method (default), so $Method is empty in the filter
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { -not $Method -and $Uri -like '*/imp-1' } {
            [pscustomobject]@{ id = 'imp-1'; state = [pscustomobject]@{ deviceImportStatus = 'complete'; deviceErrorCode = 0; deviceErrorName = '' } }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { -not $Method -and $Uri -like '*/imp-2' } {
            [pscustomobject]@{ id = 'imp-2'; state = [pscustomobject]@{ deviceImportStatus = 'error'; deviceErrorCode = 806; deviceErrorName = 'ZtdDeviceAlreadyAssigned' } }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'DELETE' } { }

        $script:csv = Join-Path $TestDrive 'hashes.csv'
        @(
            [pscustomobject]@{ 'Device Serial Number' = 'SER001'; 'Windows Product ID' = ''; 'Hardware Hash' = $script:hash; 'Group Tag' = 'Sales' }
            [pscustomobject]@{ 'Device Serial Number' = 'SER002'; 'Windows Product ID' = ''; 'Hardware Hash' = $script:hash; 'Group Tag' = '' }
        ) | Export-Csv -Path $script:csv -NoTypeInformation
    }

    It 'submits every CSV row with the Get-WindowsAutopilotInfo column names' {
        $r = @(Import-ITAutopilotDevice -Path $script:csv)
        $r.Status | Should -Be @('Submitted', 'Submitted')
        $r.ImportId | Should -Be @('imp-1', 'imp-2')
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'deviceManagement/importedWindowsAutopilotDeviceIdentities' -and
            $Body.serialNumber -eq 'SER001' -and $Body.groupTag -eq 'Sales' -and $Body.hardwareIdentifier -eq $script:hash -and
            $Body.'@odata.type' -eq '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
        }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { -not $Method }
    }

    It '-GroupTag overrides the CSV column' {
        Import-ITAutopilotDevice -Path $script:csv -GroupTag 'Kiosk' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Body.groupTag -eq 'Kiosk' }
    }

    It '-Wait reports complete and error, removes completed import records and syncs with -Sync' {
        $r = @(Import-ITAutopilotDevice -Path $script:csv -Wait -Sync)
        $r[0].Status | Should -Be 'Complete'
        $r[1].Status | Should -Be 'Error'
        $r[1].ErrorCode | Should -Be 806
        $r[1].ErrorName | Should -Be 'ZtdDeviceAlreadyAssigned'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like '*/imp-1' }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like '*/imp-2' }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITAutopilotSync -Times 1 -Exactly
    }

    It 'marks devices still pending after the timeout' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { -not $Method } {
            [pscustomobject]@{ state = [pscustomobject]@{ deviceImportStatus = 'pending' } }
        }
        # Every Get-Date call moves the clock 10 minutes forward, so the 1-minute deadline passes after one poll
        $script:clock = 0
        Mock -ModuleName IntuneToolkit Get-Date { $script:clock++; ([datetime]'2030-01-01').AddMinutes($script:clock * 10) }
        $r = @(Import-ITAutopilotDevice -Path $script:csv -Wait -TimeoutMinutes 1)
        $r.Status | Should -Be @('Timeout', 'Timeout')
    }

    It 'accepts pipeline objects from Import-Csv' {
        $r = @(Import-Csv -Path $script:csv | Import-ITAutopilotDevice)
        $r.SerialNumber | Should -Be @('SER001', 'SER002')
    }

    It 'skips rows with an invalid hash and continues' {
        $bad = Join-Path $TestDrive 'bad.csv'
        @(
            [pscustomobject]@{ 'Device Serial Number' = 'BAD001'; 'Hardware Hash' = 'not base64 !!' }
            [pscustomobject]@{ 'Device Serial Number' = 'OK0002'; 'Hardware Hash' = $script:hash }
        ) | Export-Csv -Path $bad -NoTypeInformation
        $r = @(Import-ITAutopilotDevice -Path $bad -ErrorAction SilentlyContinue -ErrorVariable err)
        $r.Status | Should -Be @('Invalid', 'Submitted')
        $err.Count | Should -BeGreaterThan 0
    }

    It 'does nothing with -WhatIf' {
        Import-ITAutopilotDevice -Path $script:csv -WhatIf | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly
    }

    It 'requires the ReadWrite scope' {
        Set-FakeConnection -Scopes 'DeviceManagementServiceConfig.Read.All'
        { Import-ITAutopilotDevice -Path $script:csv } | Should -Throw -ExpectedMessage '*DeviceManagementServiceConfig.ReadWrite.All*'
    }
}

Describe 'Set-ITAutopilotDevice and Remove-ITAutopilotDevice' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest { }
    }

    It 'sends only the specified properties to updateDeviceProperties' {
        $r = $script:apDevices[0] | Set-ITAutopilotDevice -GroupTag 'Kiosk' -PassThru
        $r.Status | Should -Be 'Sent'
        $r.DeviceName | Should -Be 'PF3A0001'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/windowsAutopilotDeviceIdentities/ap-1/updateDeviceProperties' -and $Method -eq 'POST' -and
            $Body.groupTag -eq 'Kiosk' -and $Body.Count -eq 1
        }
    }

    It 'can clear the group tag with an empty string' {
        Set-ITAutopilotDevice -Id 'ap-1' -GroupTag '' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Body.ContainsKey('groupTag') -and $Body.groupTag -eq '' }
    }

    It 'throws when no property is given' {
        { Set-ITAutopilotDevice -Id 'ap-1' } | Should -Throw -ExpectedMessage '*at least one*'
    }

    It 'Remove-ITAutopilotDevice deletes the identity' {
        $r = $script:apDevices[1] | Remove-ITAutopilotDevice -Confirm:$false
        $r.Action | Should -Be 'DeleteAutopilot'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/windowsAutopilotDeviceIdentities/ap-2' -and $Method -eq 'DELETE'
        }
    }

    It 'Remove-ITAutopilotDevice -WhatIf deletes nothing' {
        Remove-ITAutopilotDevice -Id 'ap-2' -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly
    }
}

Describe 'Autopilot sync' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Start-Sleep { }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/windowsAutopilotSettings' } {
            [pscustomobject]@{ syncStatus = 'completed'; lastSyncDateTime = '2026-11-08T10:00:00Z'; lastManualSyncTriggerDateTime = '2026-11-08T09:55:00Z' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/sync' } { }
    }

    It 'Get-ITAutopilotSyncStatus returns the settings' {
        $s = Get-ITAutopilotSyncStatus
        $s.SyncStatus | Should -Be 'completed'
        $s.PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.AutopilotSyncStatus'
    }

    It 'Get-ITAutopilotSyncStatus uses beta (windowsAutopilotSettings is not in v1.0)' {
        $null = Get-ITAutopilotSyncStatus
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/windowsAutopilotSettings' -and $ApiVersion -eq 'beta'
        }
    }

    It 'Invoke-ITAutopilotSync posts sync without retries' {
        Invoke-ITAutopilotSync | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/windowsAutopilotSettings/sync' -and $Method -eq 'POST' -and $NoRetry -and $ApiVersion -eq 'beta'
        }
    }

    It 'turns HTTP 429 (sync less than 10 minutes ago) into a warning' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/sync' } { throw 'Graph request failed: POST x -> HTTP 429 [TooManyRequests]: wait' }
        { Invoke-ITAutopilotSync -WarningVariable warn -WarningAction SilentlyContinue } | Should -Not -Throw
        $null = Invoke-ITAutopilotSync -WarningVariable warn -WarningAction SilentlyContinue
        $warn[0] | Should -BeLike '*10 minutes*'
    }

    It 'throws other errors' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/sync' } { throw 'Graph request failed: POST x -> HTTP 403 [Forbidden]: no' }
        { Invoke-ITAutopilotSync } | Should -Throw -ExpectedMessage '*403*'
    }

    It 'does nothing with -WhatIf' {
        Invoke-ITAutopilotSync -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly
    }
}

Describe 'Get-ITAutopilotProfile' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/windowsAutopilotDeploymentProfiles' } {
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile'; id = 'p-1'; displayName = 'Standard User-Driven'; language = 'os-default' }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile'; id = 'p-2'; displayName = 'Hybrid Kiosk'; language = 'en-US' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
            [pscustomobject]@{ id = 'as-1'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-in' } }
            [pscustomobject]@{ id = 'as-2'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'grp-out' } }
        }
    }

    It 'returns profiles from beta with JoinType' {
        $r = @(Get-ITAutopilotProfile)
        $r.JoinType | Should -Be @('EntraJoined', 'HybridJoined')
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $ApiVersion -eq 'beta' -and $All }
    }

    It 'filters by name' {
        (Get-ITAutopilotProfile -Name '*Kiosk*').id | Should -Be 'p-2'
    }

    It 'adds include and exclude assignments with -IncludeAssignment' {
        $r = Get-ITAutopilotProfile -Name 'Standard*' -IncludeAssignment
        $r.Assignments.Intent | Should -Be @('Include', 'Exclude')
        $r.Assignments.GroupId | Should -Be @('grp-in', 'grp-out')
    }
}
