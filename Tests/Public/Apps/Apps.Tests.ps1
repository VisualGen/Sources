#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Get-ITApp, Get-ITAppInstallStatus, New-ITWin32App. Graph and blob storage are mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = @('DeviceManagementApps.ReadWrite.All') }
        }
    }

    function New-TestPackage {
        param([string]$Path, [switch]$Msi, [int]$Size = 200)
        $stage = Join-Path $TestDrive ('stage' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -ItemType Directory -Path (Join-Path $stage 'IntuneWinPackage\Metadata') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $stage 'IntuneWinPackage\Contents') -Force
        $msiXml = ''
        if ($Msi) { $msiXml = '<MsiInfo><MsiProductCode>{AAAA}</MsiProductCode><MsiProductVersion>1.0</MsiProductVersion><MsiPublisher>Contoso</MsiPublisher><MsiExecutionContext>System</MsiExecutionContext></MsiInfo>' }
        $setup = 'install.cmd'
        if ($Msi) { $setup = 'tool.msi' }
        ('<ApplicationInfo><Name>Tool</Name><UnencryptedContentSize>{0}</UnencryptedContentSize><FileName>IntunePackage.intunewin</FileName><SetupFile>{1}</SetupFile>' +
            '<EncryptionInfo><EncryptionKey>K</EncryptionKey><MacKey>M</MacKey><InitializationVector>IV</InitializationVector><Mac>MAC</Mac><ProfileIdentifier>ProfileVersion1</ProfileIdentifier>' +
            '<FileDigest>D</FileDigest><FileDigestAlgorithm>SHA256</FileDigestAlgorithm></EncryptionInfo>{2}</ApplicationInfo>') -f $Size, $setup, $msiXml |
            Set-Content -Path (Join-Path $stage 'IntuneWinPackage\Metadata\Detection.xml') -Encoding UTF8
        [System.IO.File]::WriteAllBytes((Join-Path $stage 'IntuneWinPackage\Contents\IntunePackage.intunewin'), (New-Object byte[] $Size))
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $Path)
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITApp' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ id = 'a1'; displayName = '7-Zip'; '@odata.type' = '#microsoft.graph.win32LobApp'; isAssigned = $true }
            [pscustomobject]@{ id = 'a2'; displayName = 'Old tool'; '@odata.type' = '#microsoft.graph.win32LobApp'; isAssigned = $false }
            [pscustomobject]@{ id = 'a3'; displayName = 'Outlook'; '@odata.type' = '#microsoft.graph.managedIOSStoreApp'; isAssigned = $false; appAvailability = 'global' }
        }
    }

    It 'hides unassigned built-in managed apps unless -IncludeBuiltIn' {
        (Get-ITApp).id | Should -Be @('a1', 'a2')
        (Get-ITApp -IncludeBuiltIn).id | Should -Contain 'a3'
    }

    It 'filters assigned / unassigned / ObjectType' {
        (Get-ITApp -Assigned).id | Should -Be 'a1'
        (Get-ITApp -Unassigned).id | Should -Be 'a2'
        @(Get-ITApp -ObjectType 'win32*').Count | Should -Be 2
        (Get-ITApp)[0].PolicyType | Should -Be 'App'
    }
}

Describe 'Get-ITAppInstallStatus' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/reports/*' } {
            [pscustomobject]@{ TotalRowCount = 2
                Schema = @([pscustomobject]@{ Column = 'DeviceName' }, [pscustomobject]@{ Column = 'InstallState' }, [pscustomobject]@{ Column = 'LastModifiedDateTime' })
                Values = @(@('PC1', 'installed', (Get-Date).ToString('o')), @('PC2', 'failed', (Get-Date).AddDays(-3).ToString('o')))
            }
        }
    }

    It 'uses retrieveDeviceAppInstallationStatusReport with an ApplicationId filter for apps' {
        $rows = @([pscustomobject]@{ id = 'a1'; displayName = '7-Zip' } | Get-ITAppInstallStatus)
        $rows.Count | Should -Be 2
        $rows[0].AppName | Should -Be '7-Zip'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/reports/retrieveDeviceAppInstallationStatusReport' -and $Method -eq 'POST' -and $Body.filter -eq "(ApplicationId eq 'a1')"
        }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*getDeviceInstallStatusReport' }
    }

    It 'falls back to getDeviceInstallStatusReport only where the new report does not exist' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*retrieveDeviceAppInstallationStatusReport' } {
            throw "Graph request failed: POST -> HTTP 400 [BadRequest]: Resource not found for the segment 'retrieveDeviceAppInstallationStatusReport'."
        }
        @(Get-ITAppInstallStatus -AppId 'a1').Count | Should -Be 2
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*getDeviceInstallStatusReport' }
    }

    It 'does not hide other report errors behind the fallback' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*retrieveDeviceAppInstallationStatusReport' } {
            throw 'Graph request failed: POST -> HTTP 403 [Forbidden]: no access'
        }
        { Get-ITAppInstallStatus -AppId 'a1' -ErrorAction Stop } | Should -Throw '*403*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*getDeviceInstallStatusReport' }
    }

    It 'uses the device report for managed devices' {
        $null = [pscustomobject]@{ id = 'd1'; deviceName = 'PC1' } | Get-ITAppInstallStatus
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*retrieveDeviceAppInstallationStatusReport' -and $Body.filter -eq "(DeviceId eq 'd1')" }
    }

    It '-FailedOnly and -Since filter locally' {
        (Get-ITAppInstallStatus -AppId 'a1' -FailedOnly).DeviceName | Should -Be 'PC2'
        (Get-ITAppInstallStatus -AppId 'a1' -Since (Get-Date).AddDays(-1)).DeviceName | Should -Be 'PC1'
    }
}

Describe 'New-ITWin32App' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Start-Sleep { }
        Mock -ModuleName IntuneToolkit Send-ITBlobRequest { }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceAppManagement/mobileApps' -and $Method -eq 'POST' } { [pscustomobject]@{ id = 'app1' } }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/contentVersions' } { [pscustomobject]@{ id = '1' } }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/files' -and $Method -eq 'POST' } { [pscustomobject]@{ id = 'f1' } }
        $script:fileStates = New-Object System.Collections.Queue
        foreach ($s in 'azureStorageUriRequestPending', 'azureStorageUriRequestSuccess', 'commitFilePending', 'commitFileSuccess') { $script:fileStates.Enqueue($s) }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/files/f1' -and -not $Method } {
            [pscustomobject]@{ id = 'f1'; uploadState = $script:fileStates.Dequeue(); azureStorageUri = 'https://blob.example/x?sv=1&sig=SECRET' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/commit' } { }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'PATCH' } { }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceAppManagement/mobileApps/app1' -and -not $Method } {
            [pscustomobject]@{ id = 'app1'; displayName = 'Tool'; '@odata.type' = '#microsoft.graph.win32LobApp' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'DELETE' } { }
    }

    It 'MSI package: creates the app with msiexec commands and product code detection, uploads, commits' {
        $pkg = Join-Path $TestDrive 'msi.intunewin'
        New-TestPackage -Path $pkg -Msi
        $app = New-ITWin32App -Path $pkg -AppVersion '1.0'
        $app.id | Should -Be 'app1'

        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq 'deviceAppManagement/mobileApps' -and $Method -eq 'POST' -and
            $Body.installCommandLine -eq 'msiexec /i "tool.msi" /qn' -and $Body.uninstallCommandLine -eq 'msiexec /x "{AAAA}" /qn' -and
            $Body.publisher -eq 'Contoso' -and $Body.rules[0]['@odata.type'] -eq '#microsoft.graph.win32LobAppProductCodeRule' -and
            $Body.msiInformation.productCode -eq '{AAAA}' -and $Body.displayVersion -eq '1.0'
        }
        Should -Invoke -ModuleName IntuneToolkit Send-ITBlobRequest -Times 1 -ParameterFilter { $Uri -like '*comp=block&blockid=*' }
        Should -Invoke -ModuleName IntuneToolkit Send-ITBlobRequest -Times 1 -ParameterFilter { $Uri -like '*comp=blocklist' -and $Body -like '*<Latest>*' }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*/commit' -and $Body.fileEncryptionInfo.fileDigestAlgorithm -eq 'SHA256' }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' -and $Body.committedContentVersion -eq '1' }
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'non-MSI package needs commands, publisher and a detection rule' {
        $pkg = Join-Path $TestDrive 'exe.intunewin'
        New-TestPackage -Path $pkg
        { New-ITWin32App -Path $pkg -InstallCommandLine 'i' -UninstallCommandLine 'u' } | Should -Throw '*Publisher*'
        { New-ITWin32App -Path $pkg -Publisher 'C' } | Should -Throw '*InstallCommandLine*'
        { New-ITWin32App -Path $pkg -Publisher 'C' -InstallCommandLine 'i' -UninstallCommandLine 'u' } | Should -Throw '*detection rule*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'adds a PowerShell detection script rule' {
        $pkg = Join-Path $TestDrive 'exe2.intunewin'
        New-TestPackage -Path $pkg
        $detect = Join-Path $TestDrive 'detect.ps1'
        'if (Test-Path C:\x) { "ok"; exit 0 }' | Set-Content $detect
        $null = New-ITWin32App -Path $pkg -Publisher 'C' -InstallCommandLine 'i' -UninstallCommandLine 'u' -DetectionScriptPath $detect
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'deviceAppManagement/mobileApps' -and $Body.rules[0]['@odata.type'] -eq '#microsoft.graph.win32LobAppPowerShellScriptRule' -and $Body.rules[0].scriptContent
        }
    }

    It 'deletes the incomplete app when the commit fails' {
        $script:fileStates.Clear()
        foreach ($s in 'azureStorageUriRequestSuccess', 'commitFileFailed') { $script:fileStates.Enqueue($s) }
        $pkg = Join-Path $TestDrive 'fail.intunewin'
        New-TestPackage -Path $pkg -Msi
        { New-ITWin32App -Path $pkg -WarningAction SilentlyContinue } | Should -Throw '*commitFileFailed*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'deviceAppManagement/mobileApps/app1' }
    }

    It '-WhatIf creates nothing and removes the extracted temp file' {
        $pkg = Join-Path $TestDrive 'whatif.intunewin'
        New-TestPackage -Path $pkg -Msi
        $before = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'IntuneToolkit_*.bin').Count
        New-ITWin32App -Path $pkg -WhatIf
        @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'IntuneToolkit_*.bin').Count | Should -Be $before
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0
    }
}
