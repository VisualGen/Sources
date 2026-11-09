#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function New-FakeContext {
        param([string[]]$Scopes = @(), [string]$AuthType = 'Delegated')
        [pscustomobject]@{
            TenantId = '11111111-1111-1111-1111-111111111111'
            Account  = 'admin@contoso.com'
            AppName  = 'Microsoft Graph Command Line Tools'
            ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
            AuthType = $AuthType
            Scopes   = $Scopes
        }
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Test-ITGraphConnection' {
    It 'returns $false when not connected' {
        Mock -ModuleName IntuneToolkit Get-MgContext { $null }
        Test-ITGraphConnection | Should -BeFalse
    }

    It 'returns $true when connected and no scope is required' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext }
        Test-ITGraphConnection | Should -BeTrue
    }

    It 'returns $false when a required scope is missing' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -Scopes 'User.Read' }
        Test-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All' | Should -BeFalse
    }

    It 'accepts a ReadWrite scope for a Read requirement' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -Scopes 'DeviceManagementManagedDevices.ReadWrite.All' }
        Test-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All' | Should -BeTrue
    }

    It 'skips the scope check for app-only sessions without roles' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -AuthType 'AppOnly' }
        Test-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All' | Should -BeTrue
    }

    It 'lists missing scopes with -Detailed' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -Scopes 'DeviceManagementApps.Read.All' }
        $r = Test-ITGraphConnection -RequiredScope 'DeviceManagementApps.Read.All', 'Group.Read.All' -Detailed
        $r.Connected | Should -BeTrue
        $r.MissingScopes | Should -Be @('Group.Read.All')
    }
}

Describe 'Assert-ITGraphConnection' {
    It 'throws NotConnected when there is no session' {
        Mock -ModuleName IntuneToolkit Get-MgContext { $null }
        { InModuleScope IntuneToolkit { Assert-ITGraphConnection } } | Should -Throw -ErrorId 'IntuneToolkit.NotConnected*'
    }

    It 'throws MissingScope with the missing permission' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -Scopes 'User.Read' }
        { InModuleScope IntuneToolkit { Assert-ITGraphConnection -RequiredScope 'DeviceManagementApps.Read.All' } } |
            Should -Throw -ExpectedMessage '*DeviceManagementApps.Read.All*'
    }

    It 'does not throw when all scopes are present' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -Scopes 'DeviceManagementApps.Read.All' }
        { InModuleScope IntuneToolkit { Assert-ITGraphConnection -RequiredScope 'DeviceManagementApps.Read.All' } } | Should -Not -Throw
    }
}

Describe 'Connect-ITGraph' {
    BeforeEach {
        Mock -ModuleName IntuneToolkit Connect-MgGraph { }
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext -Scopes 'DeviceManagementManagedDevices.Read.All' }
        # Never touch the real (persisted) Graph WAM option from a test
        Mock -ModuleName IntuneToolkit Set-ITWamLogin -ParameterFilter { $Disable } { $false }
        Mock -ModuleName IntuneToolkit Set-ITWamLogin -ParameterFilter { -not $Disable } { }
        InModuleScope IntuneToolkit { $script:ITConfig.DefaultApiVersion = 'v1.0' }
    }

    It 'does not change the WAM setting for a normal sign-in' {
        Connect-ITGraph
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 0 -Exactly
    }

    It 'retries through the browser when WAM has no window handle, then restores the setting' {
        $script:attempt = 0
        Mock -ModuleName IntuneToolkit Connect-MgGraph {
            $script:attempt++
            if ($script:attempt -eq 1) { throw 'InteractiveBrowserCredential authentication failed: A window handle must be configured. See https://aka.ms/msal-net-wam#parent-window-handles' }
        }
        { Connect-ITGraph -WarningAction SilentlyContinue } | Should -Not -Throw
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 2 -Exactly
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 1 -Exactly -ParameterFilter { $Disable }
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 1 -Exactly -ParameterFilter { -not $Disable -and $Restore -eq $false }
    }

    It 'skips WAM with -UseBrowser and restores the setting' {
        Connect-ITGraph -UseBrowser
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 1 -Exactly
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 1 -Exactly -ParameterFilter { $Disable }
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 1 -Exactly -ParameterFilter { -not $Disable }
    }

    It 'restores the setting also when the browser sign-in fails' {
        Mock -ModuleName IntuneToolkit Connect-MgGraph { throw 'User canceled authentication.' }
        { Connect-ITGraph -UseBrowser } | Should -Throw '*canceled*'
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 1 -Exactly -ParameterFilter { -not $Disable }
    }

    It 'does not retry other sign-in errors or device code sign-in' {
        Mock -ModuleName IntuneToolkit Connect-MgGraph { throw 'AADSTS50076: multi-factor authentication required' }
        { Connect-ITGraph } | Should -Throw '*AADSTS50076*'
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 1 -Exactly
        Mock -ModuleName IntuneToolkit Connect-MgGraph { throw 'A window handle must be configured' }
        { Connect-ITGraph -UseDeviceCode } | Should -Throw '*window handle*'
        Should -Invoke -ModuleName IntuneToolkit Set-ITWamLogin -Times 0 -Exactly
    }

    It 'connects interactively with read-only default scopes' {
        Connect-ITGraph
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 1 -ParameterFilter {
            $Scopes -contains 'DeviceManagementManagedDevices.Read.All' -and
            -not ($Scopes -match 'ReadWrite') -and $NoWelcome
        }
    }

    It 'passes device code and tenant' {
        Connect-ITGraph -UseDeviceCode -TenantId 'contoso.onmicrosoft.com'
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 1 -ParameterFilter {
            $UseDeviceCode -and $TenantId -eq 'contoso.onmicrosoft.com'
        }
    }

    It 'connects app-only with a certificate' {
        Connect-ITGraph -TenantId 't' -ClientId 'c' -CertificateThumbprint ('A' * 40)
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 1 -ParameterFilter {
            $ClientId -eq 'c' -and $CertificateThumbprint -eq ('A' * 40) -and -not $Scopes
        }
    }

    It 'connects with a managed identity' {
        Connect-ITGraph -Identity
        Should -Invoke -ModuleName IntuneToolkit Connect-MgGraph -Times 1 -ParameterFilter { $Identity }
    }

    It 'sets the default API version with -ApiVersion' {
        Connect-ITGraph -ApiVersion beta
        (Get-ITConfiguration).DefaultApiVersion | Should -Be 'beta'
    }

    It 'returns the context with -PassThru' {
        $ctx = Connect-ITGraph -PassThru
        $ctx.PSObject.TypeNames | Should -Contain 'IntuneToolkit.Context'
        $ctx.Account | Should -Be 'admin@contoso.com'
        $ctx.ConnectMethod | Should -Be 'Interactive'
    }

    It 'rejects an invalid certificate thumbprint' {
        { Connect-ITGraph -TenantId 't' -ClientId 'c' -CertificateThumbprint 'nothex' } | Should -Throw
    }
}

Describe 'Disconnect-ITGraph' {
    It 'does nothing when not connected' {
        Mock -ModuleName IntuneToolkit Get-MgContext { $null }
        Mock -ModuleName IntuneToolkit Disconnect-MgGraph { }
        Disconnect-ITGraph
        Should -Invoke -ModuleName IntuneToolkit Disconnect-MgGraph -Times 0 -Exactly
    }

    It 'disconnects an active session' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext }
        Mock -ModuleName IntuneToolkit Disconnect-MgGraph { }
        Disconnect-ITGraph
        Should -Invoke -ModuleName IntuneToolkit Disconnect-MgGraph -Times 1 -Exactly
    }

    It '-Force disconnects even when no session is visible and ignores errors' {
        Mock -ModuleName IntuneToolkit Get-MgContext { $null }
        Mock -ModuleName IntuneToolkit Disconnect-MgGraph { throw 'No application to sign out from.' }
        { Disconnect-ITGraph -Force -ErrorAction Stop -WarningAction Stop } | Should -Not -Throw
        Should -Invoke -ModuleName IntuneToolkit Disconnect-MgGraph -Times 1 -Exactly
        InModuleScope IntuneToolkit { $script:ITSession } | Should -BeNullOrEmpty
    }

    It '-Force does not ask for confirmation but still honours -WhatIf' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext }
        Mock -ModuleName IntuneToolkit Disconnect-MgGraph { }
        $ConfirmPreference = 'Low'                          # would normally prompt
        Disconnect-ITGraph -Force -WarningAction SilentlyContinue
        Should -Invoke -ModuleName IntuneToolkit Disconnect-MgGraph -Times 1 -Exactly
        Disconnect-ITGraph -Force -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Disconnect-MgGraph -Times 1 -Exactly
    }

    It '-Force warns when a session is still visible afterwards' {
        Mock -ModuleName IntuneToolkit Get-MgContext { New-FakeContext }
        Mock -ModuleName IntuneToolkit Disconnect-MgGraph { }
        Disconnect-ITGraph -Force -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'still visible'
    }
}

Describe 'Set-ITWamLogin' {
    It 'turns WAM off and returns the previous value, then restores it' {
        InModuleScope IntuneToolkit {
            Mock Get-MgGraphOption { [pscustomobject]@{ DisableLoginByWAM = $false } }
            Mock Set-MgGraphOption { }
            Set-ITWamLogin -Disable | Should -BeFalse
            Should -Invoke Set-MgGraphOption -Times 1 -Exactly -ParameterFilter { $DisableLoginByWAM -eq $true }
            Set-ITWamLogin -Restore $false
            Should -Invoke Set-MgGraphOption -Times 1 -Exactly -ParameterFilter { $DisableLoginByWAM -eq $false }
        }
    }

    It 'also works when the caller runs with -WhatIf' {
        InModuleScope IntuneToolkit {
            Mock Get-MgGraphOption { [pscustomobject]@{ DisableLoginByWAM = $true } }
            Mock Set-MgGraphOption { }
            $WhatIfPreference = $true
            Set-ITWamLogin -Disable | Should -BeTrue
            Should -Invoke Set-MgGraphOption -Times 1 -Exactly
        }
    }
}

Describe 'Get/Set-ITConfiguration' {
    It 'changes and returns settings' {
        $cfg = Set-ITConfiguration -DefaultApiVersion beta -MaxRetry 2 -PassThru
        $cfg.DefaultApiVersion | Should -Be 'beta'
        $cfg.MaxRetry | Should -Be 2
    }

    It 'does not change settings with -WhatIf' {
        Set-ITConfiguration -PageSize 50
        Set-ITConfiguration -PageSize 999 -WhatIf
        (Get-ITConfiguration).PageSize | Should -Be 50
    }

    It 'rejects invalid values' {
        { Set-ITConfiguration -DefaultApiVersion 'v2' } | Should -Throw
    }
}
