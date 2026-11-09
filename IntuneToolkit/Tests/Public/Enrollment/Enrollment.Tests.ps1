#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Enrollment configurations' {
    BeforeEach {
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't'; Account = 'a'; AuthType = 'Delegated'; Scopes = @('DeviceManagementServiceConfig.Read.All') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceEnrollmentConfigurations' } {
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration'; id = 'x_DefaultPlatformRestrictions'; displayName = 'All users and all devices'; priority = 0 }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentLimitConfiguration'; id = 'x_DefaultLimit'; displayName = 'All users and all devices'; priority = 0; limit = 15 }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'; id = 'x_DefaultWindows10EnrollmentCompletionPageConfiguration'; displayName = 'All users and all devices'; priority = 0 }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'; id = 'esp-2'; displayName = 'ESP Kiosk'; priority = 2 }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'; id = 'esp-1'; displayName = 'ESP Standard'; priority = 1 }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration'; id = 'pr-1'; displayName = 'Block personal Android'; priority = 1; platformType = 'android' }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentLimitConfiguration'; id = 'lim-1'; displayName = 'Limit 3'; priority = 1; limit = 3 }
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentWindowsHelloForBusinessConfiguration'; id = 'x_DefaultWindowsHelloForBusiness'; displayName = 'WHfB'; priority = 0 }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
            [pscustomobject]@{ id = 'a1'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' } }
        }
    }

    It 'Get-ITEnrollmentRestriction returns platform restrictions and limits, defaults last' {
        $r = @(Get-ITEnrollmentRestriction)
        $r.id | Should -Be @('pr-1', 'lim-1', 'x_DefaultPlatformRestrictions', 'x_DefaultLimit')
        $r[0].ConfigurationType | Should -Be 'PlatformRestriction'
        $r[2].IsDefault | Should -BeTrue
        $r[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.EnrollmentConfiguration'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $ApiVersion -eq 'beta' -and $All }
    }

    It 'Get-ITEnrollmentRestriction -Type DeviceLimit' {
        (Get-ITEnrollmentRestriction -Type DeviceLimit).limit | Should -Be @(3, 15)
    }

    It 'Get-ITEnrollmentRestriction -Type Platform -Name' {
        (Get-ITEnrollmentRestriction -Type Platform -Name '*Android*').id | Should -Be 'pr-1'
    }

    It 'Get-ITEnrollmentStatusPage returns ESP profiles by priority, default last' {
        (Get-ITEnrollmentStatusPage).id | Should -Be @('esp-1', 'esp-2', 'x_DefaultWindows10EnrollmentCompletionPageConfiguration')
    }

    It 'adds assignments with -IncludeAssignment' {
        $r = Get-ITEnrollmentStatusPage -Name 'ESP Standard' -IncludeAssignment
        $r.Assignments[0].Intent | Should -Be 'AllUsers'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/deviceEnrollmentConfigurations/esp-1/assignments'
        }
    }

    It 'does not read assignments by default' {
        Get-ITEnrollmentRestriction | Out-Null
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*/assignments' }
    }
}

Describe 'Get-ITAssignment (private)' {
    BeforeEach {
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ id = '1'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1'; deviceAndAppManagementAssignmentFilterId = 'f1'; deviceAndAppManagementAssignmentFilterType = 'include' } }
            [pscustomobject]@{ id = '2'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g2' } }
            [pscustomobject]@{ id = '3'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'; deviceAndAppManagementAssignmentFilterType = 'none' } }
            [pscustomobject]@{ id = '4'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.somethingNewTarget' } }
        }
    }

    It 'translates target types to intents and keeps filters' {
        $r = @(InModuleScope IntuneToolkit { Get-ITAssignment -Path 'x/1' })
        $r.Intent | Should -Be @('Include', 'Exclude', 'AllDevices', 'somethingNewTarget')
        $r[0].FilterId | Should -Be 'f1'
        $r[0].FilterType | Should -Be 'include'
        $r[2].FilterType | Should -BeNullOrEmpty
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -eq 'x/1/assignments' -and $All }
    }
}
