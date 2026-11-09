#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Get/Add/Remove-ITPolicyAssignment and the app assignment commands. Graph is mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        param([string[]]$Scopes = @('DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementApps.ReadWrite.All', 'Group.Read.All'))
        $script:fakeScopes = $Scopes
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'; Scopes = $script:fakeScopes }
        }
    }

    # Existing: include g1, exclude g2
    $script:existing = @(
        [pscustomobject]@{ id = 'a1'; source = 'direct'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } }
        [pscustomobject]@{ id = 'a2'; source = 'direct'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g2' } }
    )
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITPolicyAssignment' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } { $script:existing }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like 'groups/*' } { [pscustomobject]@{ displayName = 'SG-' + ($Uri -replace '^groups/([^?]+).*$', '$1') } }
    }

    It 'returns flat rows for the policy type collection' {
        $rows = @(Get-ITPolicyAssignment -PolicyType SettingsCatalog -Id 's1')
        $rows.Count | Should -Be 2
        $rows.Intent | Should -Be @('Include', 'Exclude')
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/configurationPolicies/s1/assignments' }
    }

    It 'binds PolicyType and id from pipeline objects and resolves group names once' {
        $objects = @(
            [pscustomobject]@{ PolicyType = 'Compliance'; id = 'c1'; displayName = 'Win - Baseline' }
            [pscustomobject]@{ PolicyType = 'Script'; id = 'x1'; displayName = 'Set-TimeZone' }
        )
        $rows = @($objects | Get-ITPolicyAssignment -ResolveName)
        $rows.Count | Should -Be 4
        $rows[0].ObjectName | Should -Be 'Win - Baseline'
        $rows[0].GroupName | Should -Be 'SG-g1'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 2 -Exactly -ParameterFilter { $Uri -like 'groups/*' }
    }
}

Describe 'Add-ITPolicyAssignment' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } { $script:existing }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assign' } { }
    }

    It 'keeps the existing assignments and adds the new group' {
        $r = Add-ITPolicyAssignment -PolicyType Compliance -Id 'c1' -GroupId 'g3'
        $r.Status | Should -Be 'Changed'
        $r.AssignmentCount | Should -Be 3
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'deviceManagement/deviceCompliancePolicies/c1/assign' -and
            @($Body.assignments).Count -eq 3 -and $Body.assignments[2].target.groupId -eq 'g3'
        }
    }

    It 'reports Unchanged and posts nothing when the target already exists' {
        (Add-ITPolicyAssignment -PolicyType Compliance -Id 'c1' -GroupId 'g1').Status | Should -Be 'Unchanged'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Uri -like '*/assign' }
    }

    It 'adds an exclusion, all devices with a filter' {
        $null = Add-ITPolicyAssignment -PolicyType DeviceConfiguration -Id 'p1' -GroupId 'g9' -Exclude
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Body -and $Body.assignments[2].target['@odata.type'] -eq '#microsoft.graph.exclusionGroupAssignmentTarget' }

        $null = Add-ITPolicyAssignment -PolicyType DeviceConfiguration -Id 'p1' -AllDevices -FilterId 'f1'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Body -and $Body.assignments[2].target['@odata.type'] -eq '#microsoft.graph.allDevicesAssignmentTarget' -and
            $Body.assignments[2].target['deviceAndAppManagementAssignmentFilterId'] -eq 'f1'
        }
    }

    It 'gives remediations a daily schedule and uses deviceHealthScriptAssignments' {
        $null = Add-ITPolicyAssignment -PolicyType Remediation -Id 'r1' -GroupId 'g3'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Body -and $Body.deviceHealthScriptAssignments[2].runSchedule['@odata.type'] -eq '#microsoft.graph.deviceHealthScriptDailySchedule' -and
            $Body.deviceHealthScriptAssignments[2].runRemediationScript
        }
    }

    It 'pipes from Get-IT* objects and supports -WhatIf' {
        [pscustomobject]@{ PolicyType = 'SettingsCatalog'; id = 's1'; displayName = 'Win - Edge' } | Add-ITPolicyAssignment -GroupId 'g3' -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0
    }

    It 'needs the write scope' {
        Set-FakeConnection -Scopes 'DeviceManagementConfiguration.Read.All'
        { Add-ITPolicyAssignment -PolicyType Compliance -Id 'c1' -GroupId 'g3' } | Should -Throw '*ReadWrite*'
    }
}

Describe 'Remove-ITPolicyAssignment' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } { $script:existing }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assign' } { }
    }

    It 'removes the group and keeps the rest' {
        $r = Remove-ITPolicyAssignment -PolicyType Compliance -Id 'c1' -GroupId 'g2' -Confirm:$false
        $r.Status | Should -Be 'Changed'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -like '*/assign' -and @($Body.assignments).Count -eq 1 -and $Body.assignments[0].target.groupId -eq 'g1'
        }
    }

    It '-Include only removes the include of that group' {
        (Remove-ITPolicyAssignment -PolicyType Compliance -Id 'c1' -GroupId 'g2' -Include -Confirm:$false).Status | Should -Be 'Unchanged'
    }

    It '-All posts an empty set' {
        $null = Remove-ITPolicyAssignment -PolicyType Compliance -Id 'c1' -All -Confirm:$false
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*/assign' -and @($Body.assignments).Count -eq 0 }
    }

    It 'asks for confirmation by default (ConfirmImpact High)' {
        (Get-Command Remove-ITPolicyAssignment).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] } |
            ForEach-Object { $_.ConfirmImpact } | Should -Be 'High'
    }
}

Describe 'App assignments' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
            [pscustomobject]@{ id = 'a1'; intent = 'available'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' } }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assign' } { }
    }

    It 'Get-ITAppAssignment returns the install intent' {
        $row = [pscustomobject]@{ id = 'app1'; displayName = 'Company Portal' } | Get-ITAppAssignment
        $row.InstallIntent | Should -Be 'available'
        $row.Intent | Should -Be 'AllUsers'
        $row.ObjectName | Should -Be 'Company Portal'
    }

    It 'Add-ITAppAssignment posts mobileAppAssignments with intent and Win32 settings' {
        $app = [pscustomobject]@{ id = 'app1'; displayName = '7-Zip'; ObjectType = 'win32LobApp' }
        $null = $app | Add-ITAppAssignment -Intent required -GroupId 'g1' -Notification hideAll -DeliveryOptimizationPriority foreground
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq 'deviceAppManagement/mobileApps/app1/assign' -and
            $Body.mobileAppAssignments[1].intent -eq 'required' -and
            $Body.mobileAppAssignments[1].settings.notifications -eq 'hideAll' -and
            $Body.mobileAppAssignments[1].settings['@odata.type'] -eq '#microsoft.graph.win32LobAppAssignmentSettings'
        }
    }

    It 'Add-ITAppAssignment needs an intent unless it is an exclusion' {
        $null = Add-ITAppAssignment -Id 'app1' -GroupId 'g1' -ErrorVariable err -ErrorAction SilentlyContinue
        $err[0] | Should -BeLike '*-Intent is required*'
        (Add-ITAppAssignment -Id 'app1' -GroupId 'g1' -Exclude).Status | Should -Be 'Changed'
    }

    It 'Remove-ITAppAssignment -AllUsers removes the all users target' {
        $null = Remove-ITAppAssignment -Id 'app1' -AllUsers -Confirm:$false
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*/assign' -and @($Body.mobileAppAssignments).Count -eq 0 }
    }
}
