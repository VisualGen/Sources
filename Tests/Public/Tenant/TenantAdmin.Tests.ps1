#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Reports, Autopilot import status, RBAC, Apple tokens, connectors. Graph is mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'
                Scopes = @('DeviceManagementServiceConfig.Read.All', 'DeviceManagementRBAC.Read.All', 'DeviceManagementApps.Read.All', 'Group.Read.All') }
        }
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Export-ITReport' {
    BeforeAll {
        $script:data = @(
            [pscustomobject]@{ Name = 'PC1'; Policies = @('A', 'B'); Note = '<script>x</script>' }
            [pscustomobject]@{ Name = 'PC2'; Policies = @(); Note = 'ok' }
        )
    }

    It 'writes CSV and joins arrays' {
        $f = $script:data | Export-ITReport -Path (Join-Path $TestDrive 'r\out.csv')
        $rows = Import-Csv $f.FullName
        $rows.Count | Should -Be 2
        $rows[0].Policies | Should -Be 'A; B'
    }

    It 'writes HTML with encoded values, row count and the selected columns' {
        $f = $script:data | Export-ITReport -Path (Join-Path $TestDrive 'out.html') -Title 'Devices & more' -Property Name, Note
        $html = Get-Content $f.FullName -Raw
        $html | Should -Match '<title>Devices &amp; more</title>'
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Not -Match '<script>'
        $html | Should -Match '2 row\(s\)'
        $html | Should -Not -Match '<th>Policies</th>'
    }

    It 'still writes a report for empty input' {
        $f = @() | Export-ITReport -Path (Join-Path $TestDrive 'empty.html')
        Get-Content $f.FullName -Raw | Should -Match 'No rows'
    }
}

Describe 'Get-ITAutopilotImportStatus' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ id = 'i1'; serialNumber = 'S1'; state = [pscustomobject]@{ deviceImportStatus = 'pending' } }
            [pscustomobject]@{ id = 'i2'; serialNumber = 'S2'; state = [pscustomobject]@{ deviceImportStatus = 'error'; deviceErrorCode = 806; deviceErrorName = 'ZtdDeviceAlreadyAssigned' } }
        }
    }

    It 'flattens the state and filters errors' {
        @(Get-ITAutopilotImportStatus).Count | Should -Be 2
        $e = Get-ITAutopilotImportStatus -ErrorOnly
        $e.serialNumber | Should -Be 'S2'
        $e.ErrorCode | Should -Be 806
    }
}

Describe 'Get-ITRoleDefinition / Get-ITRoleAssignment' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/roleDefinitions' } {
            [pscustomobject]@{ id = 'rd1'; displayName = 'Help Desk Operator'; isBuiltIn = $true
                rolePermissions = @([pscustomobject]@{ resourceActions = @([pscustomobject]@{ allowedResourceActions = @('Microsoft.Intune_ManagedDevices_Read', 'Microsoft.Intune_RemoteTasks_RebootNow') }) }) }
            [pscustomobject]@{ id = 'rd2'; displayName = 'Custom - Apps'; isBuiltIn = $false; rolePermissions = @() }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/roleDefinitions/rd1/roleAssignments' } { [pscustomobject]@{ id = 'ra1' } }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/roleDefinitions/rd2/roleAssignments' } { }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/roleAssignments/ra1' } {
            [pscustomobject]@{ id = 'ra1'; displayName = 'HD EU'; members = @('g-admins'); scopeMembers = @('g-devices'); scopeType = 'resourceScope'; roleScopeTagIds = @('5') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'groups/*' } { [pscustomobject]@{ displayName = 'Group ' + ($Uri -replace '^groups/([^?]+).*$', '$1') } }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/roleScopeTags' } { [pscustomobject]@{ id = '5'; displayName = 'EU' } }
    }

    It 'flattens permissions and filters custom roles' {
        (Get-ITRoleDefinition -Name 'Help*').AllowedActions | Should -Contain 'Microsoft.Intune_RemoteTasks_RebootNow'
        (Get-ITRoleDefinition -CustomOnly).id | Should -Be 'rd2'
    }

    It 'returns assignments with role name and resolved names' {
        $a = Get-ITRoleAssignment -ResolveName
        $a.RoleName | Should -Be 'Help Desk Operator'
        $a.Members | Should -Be 'g-admins'
        $a.MemberNames | Should -Be 'Group g-admins'
        $a.ScopeMemberNames | Should -Be 'Group g-devices'
        $a.ScopeTagNames | Should -Be 'EU'
    }
}

Describe 'Get-ITTenantCertificateStatus' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*applePushNotificationCertificate' } {
            [pscustomobject]@{ id = 'apns'; appleIdentifier = 'mdm@contoso.com'; topicIdentifier = 'com.apple.mgmt'; expirationDateTime = (Get-Date).AddDays(200).ToString('o') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*depOnboardingSettings' } {
            [pscustomobject]@{ id = 'dep1'; tokenName = 'ABM'; appleIdentifier = 'abm@contoso.com'; tokenExpirationDateTime = (Get-Date).AddDays(10).ToString('o') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*vppTokens' } {
            [pscustomobject]@{ id = 'vpp1'; organizationName = 'Contoso'; appleId = 'vpp@contoso.com'; expirationDateTime = (Get-Date).AddDays(-2).ToString('o'); state = 'expired' }
        }
    }

    It 'returns OK, Warning and Expired' {
        $rows = @(Get-ITTenantCertificateStatus)
        ($rows | Where-Object Type -eq 'APNs').Status | Should -Be 'OK'
        ($rows | Where-Object Type -eq 'DEP').Status | Should -Be 'Warning'
        ($rows | Where-Object Type -eq 'VPP').Status | Should -Be 'Expired'
    }

    It 'skips types that are not configured (404)' {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*applePushNotificationCertificate' } { throw 'Graph request failed: GET x -> HTTP 404 [ResourceNotFound]: none' }
        { Get-ITTenantCertificateStatus -ErrorAction Stop } | Should -Not -Throw
        @(Get-ITTenantCertificateStatus).Type | Should -Not -Contain 'APNs'
    }
}

Describe 'Get-ITConnectorStatus' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*domainJoinConnectors' } {
            [pscustomobject]@{ id = 'c1'; displayName = 'SRV-ODJ01'; state = 'active'; lastConnectionDateTime = (Get-Date).AddHours(-1).ToString('o') }
            [pscustomobject]@{ id = 'c2'; displayName = 'SRV-ODJ02'; state = 'active'; lastConnectionDateTime = (Get-Date).AddDays(-3).ToString('o') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*ndesConnectors' } {
            [pscustomobject]@{ id = 'n1'; displayName = 'SRV-PKI'; state = 'inactive'; lastConnectionDateTime = (Get-Date).ToString('o') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*mobileThreatDefenseConnectors' -or $Uri -like '*deviceManagementPartners' } {
            throw 'Graph request failed: GET x -> HTTP 403 [Forbidden]: not licensed'
        }
        # Seen in a real tenant without an on-premises Exchange connector
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*exchangeConnectors' } {
            throw 'Graph request failed: GET x -> HTTP 501 [NotSupported]: An error has occurred'
        }
    }

    It 'rates connectors OK / Warning / Error and skips unavailable types' {
        { Get-ITConnectorStatus -ErrorAction Stop } | Should -Not -Throw
        $rows = @(Get-ITConnectorStatus)
        ($rows | Where-Object Name -eq 'SRV-ODJ01').Status | Should -Be 'OK'
        ($rows | Where-Object Name -eq 'SRV-ODJ02').Status | Should -Be 'Warning'
        ($rows | Where-Object Name -eq 'SRV-PKI').Status | Should -Be 'Error'
        $rows.Count | Should -Be 3
    }
}
