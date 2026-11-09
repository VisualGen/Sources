#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Device functions. Graph is never called: Invoke-ITGraphRequest is mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    $script:allScopes = @(
        'DeviceManagementManagedDevices.ReadWrite.All'
        'DeviceManagementManagedDevices.PrivilegedOperations.All'
        'BitLockerKey.Read.All'
        'DeviceLocalCredential.Read.All'
        'User.Read.All'
    )

    function Set-FakeConnection {
        param([string[]]$Scopes = $script:allScopes)
        $script:fakeScopes = $Scopes
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't'; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = $script:fakeScopes }
        }
    }

    # Decoded URI helper for parameter filters
    function Get-Decoded([string]$Uri) { [uri]::UnescapeDataString($Uri) }

    function New-Device([string]$Id = 'dev-1', [string]$Name = 'PC-001') {
        [pscustomobject]@{ id = $Id; deviceName = $Name; azureADDeviceId = "aad-$Id"; operatingSystem = 'Windows'; lastSyncDateTime = (Get-Date).AddDays(-5).ToString('o') }
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITManagedDevice' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest { New-Device }
    }

    It 'uses an eq filter for an exact name and reads all pages' {
        Get-ITManagedDevice -Name 'PC-001' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            (Get-Decoded $Uri) -eq "deviceManagement/managedDevices?`$filter=deviceName eq 'PC-001'" -and $All
        }
    }

    It 'uses startswith for a prefix wildcard' {
        Get-ITManagedDevice -Name 'NL-LT-*' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            (Get-Decoded $Uri) -like "*startswith(deviceName,'NL-LT-')*"
        }
    }

    It 'filters other wildcards locally' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest { New-Device -Id 1 -Name 'HQ-LAPTOP-1'; New-Device -Id 2 -Name 'HQ-DESK-1' }
        $r = @(Get-ITManagedDevice -Name '*LAPTOP*')
        $r.Count | Should -Be 1
        $r[0].deviceName | Should -Be 'HQ-LAPTOP-1'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -notlike '*filter*' }
    }

    It 'escapes single quotes in names' {
        Get-ITManagedDevice -Name "O'Brien-PC" | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { (Get-Decoded $Uri) -like "*deviceName eq 'O''Brien-PC'*" }
    }

    It 'combines filters with and' {
        Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant -OwnerType company | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            (Get-Decoded $Uri) -like "*(operatingSystem eq 'Windows') and (complianceState eq 'noncompliant') and (managedDeviceOwnerType eq 'company')*"
        }
    }

    It 'formats LastSyncBefore as UTC' {
        Get-ITManagedDevice -LastSyncBefore ([datetime]::new(2026, 1, 15, 0, 0, 0, [DateTimeKind]::Utc)) | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { (Get-Decoded $Uri) -like '*lastSyncDateTime le 2026-01-15T00:00:00Z*' }
    }

    It 'appends a raw -Filter' {
        Get-ITManagedDevice -OperatingSystem Windows -Filter "manufacturer eq 'Dell Inc.'" | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { (Get-Decoded $Uri) -like "*and (manufacturer eq 'Dell Inc.')*" }
    }

    It 'uses $top and no paging with -Top' {
        Get-ITManagedDevice -Top 10 | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*$top=10*' -and -not $All }
    }

    It 'passes -Property as $select' {
        Get-ITManagedDevice -Property id, deviceName | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { (Get-Decoded $Uri) -like '*$select=id,deviceName*' }
    }

    It 'tags results as IntuneToolkit.ManagedDevice' {
        (Get-ITManagedDevice -Name 'PC-001').PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.ManagedDevice'
    }

    It 'gets devices by Id and continues after an error' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/bad*' } { throw 'not found' }
        $r = @(Get-ITManagedDevice -Id 'good', 'bad', 'good2' -ErrorAction SilentlyContinue -ErrorVariable err)
        $r.Count | Should -Be 2
        $err.Count | Should -BeGreaterThan 0
    }

    It 'throws when not connected' {
        Mock -ModuleName IntuneToolkit Get-MgContext { $null }
        { Get-ITManagedDevice } | Should -Throw -ErrorId 'IntuneToolkit.NotConnected*'
    }
}

Describe 'Get-ITStaleDevice' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ id = '1'; deviceName = 'OLD'; lastSyncDateTime = (Get-Date).AddDays(-200).ToUniversalTime().ToString('o') }
            [pscustomobject]@{ id = '2'; deviceName = 'OLDER'; lastSyncDateTime = (Get-Date).AddDays(-400).ToUniversalTime().ToString('o') }
            [pscustomobject]@{ id = '3'; deviceName = 'NEVER'; lastSyncDateTime = '0001-01-01T00:00:00Z' }
        }
    }

    It 'filters on last sync older than -Days' {
        Get-ITStaleDevice -Days 90 -OperatingSystem Windows | Out-Null
        $expected = (Get-Date).AddDays(-90).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            (Get-Decoded $Uri) -like "*lastSyncDateTime le $expected*" -and (Get-Decoded $Uri) -like "*operatingSystem eq 'Windows'*"
        }
    }

    It 'adds DaysSinceLastSync and sorts never-synced first, then oldest' {
        $r = @(Get-ITStaleDevice -Days 90)
        $r.deviceName | Should -Be @('NEVER', 'OLDER', 'OLD')
        $r[0].DaysSinceLastSync | Should -BeNullOrEmpty
        $r[1].DaysSinceLastSync | Should -BeIn 399, 400
    }
}

Describe 'Device actions' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest { }
    }

    It '<Command> calls <HttpMethod> .../<GraphAction> on <Api>' -ForEach @(
        @{ Command = 'Invoke-ITDeviceSync';           GraphAction = 'syncDevice';          HttpMethod = 'POST';   Api = 'v1.0' }
        @{ Command = 'Invoke-ITDeviceRestart';        GraphAction = 'rebootNow';           HttpMethod = 'POST';   Api = 'v1.0' }
        @{ Command = 'Invoke-ITDeviceRetire';         GraphAction = 'retire';              HttpMethod = 'POST';   Api = 'v1.0' }
        @{ Command = 'Invoke-ITDeviceWipe';           GraphAction = 'wipe';                HttpMethod = 'POST';   Api = 'v1.0' }
        @{ Command = 'Invoke-ITDefenderScan';         GraphAction = 'windowsDefenderScan'; HttpMethod = 'POST';   Api = 'v1.0' }
        @{ Command = 'Invoke-ITBitLockerKeyRotation'; GraphAction = 'rotateBitLockerKeys'; HttpMethod = 'POST';   Api = 'beta' }
        @{ Command = 'Remove-ITManagedDevice';        GraphAction = '';                    HttpMethod = 'DELETE'; Api = 'v1.0' }
    ) {
        $result = & $Command -Id 'dev-1' -Confirm:$false
        $expectedUri = 'deviceManagement/managedDevices/dev-1'
        if ($GraphAction) { $expectedUri = "$expectedUri/$GraphAction" }

        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq $expectedUri -and $Method -eq $HttpMethod -and $ApiVersion -eq $Api
        }
        $result.Status | Should -Be 'Sent'
        $result.DeviceId | Should -Be 'dev-1'
        $result.PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.DeviceActionResult'
    }

    It '<Command> does nothing with -WhatIf' -ForEach @(
        @{ Command = 'Invoke-ITDeviceSync' }, @{ Command = 'Invoke-ITDeviceWipe' }, @{ Command = 'Remove-ITManagedDevice' }
    ) {
        & $Command -Id 'dev-1' -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly
    }

    It 'accepts pipeline input from Get-ITManagedDevice objects' {
        $r = @((New-Device -Id 'a' -Name 'PC-A'), (New-Device -Id 'b' -Name 'PC-B') | Invoke-ITDeviceSync)
        $r.DeviceId | Should -Be @('a', 'b')
        $r.DeviceName | Should -Be @('PC-A', 'PC-B')
    }

    It 'returns Failed and writes an error when Graph fails, then continues' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/bad/*' } { throw 'Graph request failed: HTTP 404' }
        $r = @(Invoke-ITDeviceSync -Id 'bad', 'good' -ErrorAction SilentlyContinue -ErrorVariable err)
        $r.Status | Should -Be @('Failed', 'Sent')
        $r[0].Message | Should -BeLike '*404*'
        $err.Count | Should -BeGreaterThan 0
    }

    It 'wipe sends the options in the body' {
        Invoke-ITDeviceWipe -Id 'dev-1' -KeepUserData -KeepEnrollmentData -MacOsUnlockCode '123456' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Body.keepUserData -eq $true -and $Body.keepEnrollmentData -eq $true -and $Body.persistEsimDataPlan -eq $false -and
            $Body.macOsUnlockCode -eq '123456' -and -not $Body.ContainsKey('useProtectedWipe') -and $ApiVersion -eq 'v1.0'
        }
    }

    It 'protected wipe uses beta' {
        Invoke-ITDeviceWipe -Id 'dev-1' -ProtectedWipe -Confirm:$false | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Body.useProtectedWipe -and $ApiVersion -eq 'beta' }
    }

    It 'rejects an invalid macOS unlock code' {
        { Invoke-ITDeviceWipe -Id 'dev-1' -MacOsUnlockCode '12' -Confirm:$false } | Should -Throw
    }

    It 'Defender scan is quick by default and full with -FullScan' {
        Invoke-ITDefenderScan -Id 'dev-1' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Body.quickScan -eq $true }
        Invoke-ITDefenderScan -Id 'dev-2' -FullScan | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*dev-2*' -and $Body.quickScan -eq $false }
    }

    It 'requires the PrivilegedOperations permission' {
        Set-FakeConnection -Scopes 'DeviceManagementManagedDevices.ReadWrite.All'
        { Invoke-ITDeviceWipe -Id 'dev-1' -Confirm:$false } | Should -Throw -ExpectedMessage '*PrivilegedOperations*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly
    }
}

Describe 'Get-ITDeviceBitLockerKey' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/managedDevices*' } {
            New-Device -Id 'dev-1' -Name 'LT-0815'
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'informationProtection/bitlocker/recoveryKeys?*' } {
            [pscustomobject]@{ id = 'key-1'; deviceId = 'aad-dev-1'; volumeType = 'operatingSystemVolume'; createdDateTime = '2026-01-01T00:00:00Z' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'informationProtection/bitlocker/recoveryKeys/key-1*' } {
            [pscustomobject]@{ id = 'key-1'; key = '111111-222222-333333-444444-555555-666666-777777-888888' }
        }
    }

    It 'finds the device by name and returns the key' {
        $r = Get-ITDeviceBitLockerKey -DeviceName 'LT-0815'
        $r.DeviceName | Should -Be 'LT-0815'
        $r.DeviceId | Should -Be 'aad-dev-1'
        $r.Key | Should -BeLike '111111-*'
        $r.PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.BitLockerKey'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            (Get-Decoded $Uri) -like "*deviceId eq 'aad-dev-1'*" -and $Headers['ocp-client-name'] -eq 'IntuneToolkit'
        }
    }

    It 'accepts pipeline input (azureADDeviceId + deviceName)' {
        $r = New-Device -Id 'dev-1' -Name 'LT-0815' | Get-ITDeviceBitLockerKey
        $r.DeviceName | Should -Be 'LT-0815'
        $r.Key | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like 'deviceManagement/*' }
    }

    It 'filters by -KeyId' {
        @(Get-ITDeviceBitLockerKey -DeviceName 'LT-0815' -KeyId 'other*' -WarningAction SilentlyContinue).Count | Should -Be 0
    }

    It 'writes an error when the device is not found' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/managedDevices*' } { }
        Get-ITDeviceBitLockerKey -DeviceName 'NOPE' -ErrorAction SilentlyContinue -ErrorVariable err
        $err[0].Exception.Message | Should -BeLike "*NOPE*"
    }
}

Describe 'Get-ITDeviceLapsPassword' {
    BeforeEach {
        Set-FakeConnection
        $script:b64new = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('N3w-P@ss!'))
        $script:b64old = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('0ld-P@ss!'))
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'directory/deviceLocalCredentials?*' } {
            [pscustomobject]@{ id = 'aad-1'; deviceName = 'LT-0815' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'directory/deviceLocalCredentials/aad-1*' } {
            [pscustomobject]@{
                id = 'aad-1'; deviceName = 'LT-0815'; refreshDateTime = '2026-12-01T00:00:00Z'
                credentials = @(
                    [pscustomobject]@{ accountName = 'LapsAdmin'; accountSid = 'S-1-5-21-1'; backupDateTime = '2026-10-01T00:00:00Z'; passwordBase64 = $script:b64old }
                    [pscustomobject]@{ accountName = 'LapsAdmin'; accountSid = 'S-1-5-21-1'; backupDateTime = '2026-11-01T00:00:00Z'; passwordBase64 = $script:b64new }
                )
            }
        }
    }

    It 'returns only the newest credential as SecureString by default' {
        $r = @(Get-ITDeviceLapsPassword -DeviceName 'LT-0815')
        $r.Count | Should -Be 1
        $r[0].Password | Should -BeOfType [System.Security.SecureString]
        $plain = (New-Object System.Management.Automation.PSCredential ('x', $r[0].Password)).GetNetworkCredential().Password
        $plain | Should -Be 'N3w-P@ss!'
        $r[0].AccountName | Should -Be 'LapsAdmin'
    }

    It 'returns plain text with -AsPlainText and history with -IncludeHistory' {
        $r = @(Get-ITDeviceLapsPassword -DeviceName 'LT-0815' -AsPlainText -IncludeHistory)
        $r.Password | Should -Be @('N3w-P@ss!', '0ld-P@ss!')
    }

    It 'sends the client headers' {
        Get-ITDeviceLapsPassword -DeviceName 'LT-0815' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 2 -Exactly -ParameterFilter { $Headers['ocp-client-name'] -eq 'IntuneToolkit' }
    }

    It 'accepts azureADDeviceId from the pipeline' {
        $r = [pscustomobject]@{ azureADDeviceId = 'aad-1'; deviceName = 'LT-0815' } | Get-ITDeviceLapsPassword -AsPlainText
        $r.Password | Should -Be 'N3w-P@ss!'
    }
}

Describe 'Device category and primary user' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceCategories' } {
            [pscustomobject]@{ id = 'cat-1'; displayName = 'Kiosk'; description = '' }
            [pscustomobject]@{ id = 'cat-2'; displayName = 'Finance'; description = '' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'users/*' } {
            [pscustomobject]@{ id = '11111111-2222-3333-4444-555555555555'; userPrincipalName = 'new@contoso.com' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/managedDevices/*' } { }
    }

    It 'Get-ITDeviceCategory filters by name' {
        (Get-ITDeviceCategory -Name 'Fin*').id | Should -Be 'cat-2'
    }

    It 'Set-ITManagedDeviceCategory resolves the name and PUTs the $ref on beta' {
        $r = Set-ITManagedDeviceCategory -Id 'dev-1' -CategoryName 'Kiosk' -PassThru
        $r.Status | Should -Be 'Sent'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq 'deviceManagement/managedDevices/dev-1/deviceCategory/$ref' -and $Method -eq 'PUT' -and $ApiVersion -eq 'beta' -and
            $Body['@odata.id'] -eq 'https://graph.microsoft.com/beta/deviceManagement/deviceCategories/cat-1'
        }
    }

    It 'Set-ITManagedDeviceCategory throws for an unknown category and lists the existing ones' {
        { Set-ITManagedDeviceCategory -Id 'dev-1' -CategoryName 'Nope' } | Should -Throw -ExpectedMessage '*Kiosk, Finance*'
    }

    It 'Set-ITManagedDevicePrimaryUser resolves the UPN and POSTs users/$ref on beta' {
        Set-ITManagedDevicePrimaryUser -Id 'dev-1' -UserPrincipalName 'new@contoso.com' | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like 'users/new%40contoso.com*' }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq 'deviceManagement/managedDevices/dev-1/users/$ref' -and $Method -eq 'POST' -and $ApiVersion -eq 'beta' -and
            $Body['@odata.id'] -eq 'https://graph.microsoft.com/beta/users/11111111-2222-3333-4444-555555555555'
        }
    }

    It 'Set-ITManagedDevicePrimaryUser with -WhatIf changes nothing' {
        Set-ITManagedDevicePrimaryUser -Id 'dev-1' -UserId '11111111-2222-3333-4444-555555555555' -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like 'deviceManagement/*' }
    }
}
