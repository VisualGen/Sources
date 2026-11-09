#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITScopeTag' {
    BeforeEach {
        $script:fakeScopes = @('DeviceManagementRBAC.Read.All')
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't'; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = $script:fakeScopes }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/roleScopeTags' } {
            [pscustomobject]@{ id = '0'; displayName = 'Default'; description = 'Built-in'; isBuiltIn = $true }
            [pscustomobject]@{ id = '1'; displayName = 'NL-Amsterdam'; description = ''; isBuiltIn = $false }
            [pscustomobject]@{ id = '2'; displayName = 'DE-Berlin'; description = ''; isBuiltIn = $false }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/roleScopeTags/1' } {
            [pscustomobject]@{ id = '1'; displayName = 'NL-Amsterdam'; description = ''; isBuiltIn = $false }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'deviceManagement/roleScopeTags/*/assignments' } {
            [pscustomobject]@{ id = 'a1'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-1' } }
            [pscustomobject]@{ id = 'a2'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-2' } }
        }
    }

    It 'lists all scope tags from the beta endpoint with paging' {
        $r = @(Get-ITScopeTag)
        $r.displayName | Should -Be @('Default', 'NL-Amsterdam', 'DE-Berlin')
        $r[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.ScopeTag'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $ApiVersion -eq 'beta' -and $All }
    }

    It 'filters by name with wildcards' {
        (Get-ITScopeTag -Name 'NL-*').id | Should -Be '1'
    }

    It 'gets a tag by Id' {
        (Get-ITScopeTag -Id '1').displayName | Should -Be 'NL-Amsterdam'
    }

    It 'adds the auto-assignment group IDs with -IncludeAssignment' {
        $r = Get-ITScopeTag -Name 'NL-*' -IncludeAssignment
        $r.AssignedGroupIds | Should -Be @('grp-1', 'grp-2')
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'deviceManagement/roleScopeTags/1/assignments' }
    }

    It 'does not read assignments without -IncludeAssignment' {
        Get-ITScopeTag | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*/assignments' }
    }

    It 'requires DeviceManagementRBAC.Read.All' {
        $script:fakeScopes = @('DeviceManagementManagedDevices.Read.All')
        { Get-ITScopeTag } | Should -Throw -ExpectedMessage '*DeviceManagementRBAC.Read.All*'
    }
}
