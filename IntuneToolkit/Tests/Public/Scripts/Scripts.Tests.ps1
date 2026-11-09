#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Platform scripts, remediations, update profiles. Graph is mocked.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'
                Scopes = @('DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementManagedDevices.PrivilegedOperations.All') }
        }
    }
    $script:b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('Write-Output "hello"'))
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITScript / New-ITScript / Export-ITScript' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceManagementScripts' -and -not $Method } {
            [pscustomobject]@{ id = 'x1'; displayName = 'Set-TimeZone'; fileName = 'Set-TimeZone.ps1' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceManagementScripts/x1' } {
            [pscustomobject]@{ id = 'x1'; displayName = 'Set-TimeZone'; fileName = 'Set-TimeZone.ps1'; scriptContent = $script:b64 }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'POST' } { [pscustomobject]@{ id = 'x1' } }
    }

    It 'decodes the script with -IncludeContent' {
        (Get-ITScript -IncludeContent).ScriptText | Should -Be 'Write-Output "hello"'
        (Get-ITScript)[0].PolicyType | Should -Be 'Script'
    }

    It 'New-ITScript uploads the file as Base64 with run settings' {
        $file = Join-Path $TestDrive 'Set-TimeZone.ps1'
        'Write-Output "hello"' | Set-Content $file -Encoding ASCII -NoNewline
        $null = New-ITScript -Path $file -RunAsAccount user -RunAs32Bit
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.displayName -eq 'Set-TimeZone' -and $Body.scriptContent -eq $script:b64 -and
            $Body.runAsAccount -eq 'user' -and $Body.runAs32Bit -eq $true -and $Body.fileName -eq 'Set-TimeZone.ps1'
        }
    }

    It 'Export-ITScript writes the .ps1 and refuses to overwrite without -Force' {
        $dir = Join-Path $TestDrive 'scripts'
        $f = [pscustomobject]@{ id = 'x1'; PolicyType = 'Script' } | Export-ITScript -Path $dir
        Get-Content $f.FullName -Raw | Should -Be 'Write-Output "hello"'
        $null = [pscustomobject]@{ id = 'x1'; PolicyType = 'Script' } | Export-ITScript -Path $dir -ErrorVariable err -ErrorAction SilentlyContinue
        $err[0] | Should -BeLike '*-Force*'
    }
}

Describe 'Get-ITScriptRunState' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            [pscustomobject]@{ runState = 'success'; resultMessage = 'ok'; managedDevice = [pscustomobject]@{ id = 'd1'; deviceName = 'PC1' } }
            [pscustomobject]@{ runState = 'fail'; errorCode = -1; resultMessage = 'boom'; managedDevice = [pscustomobject]@{ id = 'd2'; deviceName = 'PC2' } }
        }
    }

    It 'returns device rows and filters failures' {
        @(Get-ITScriptRunState -Id 'x1').Count | Should -Be 2
        (Get-ITScriptRunState -Id 'x1' -FailedOnly).DeviceName | Should -Be 'PC2'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { [uri]::UnescapeDataString($Uri) -like '*deviceRunStates?$expand=managedDevice(*' }
    }
}

Describe 'Remediations' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceHealthScripts' -and -not $Method } {
            [pscustomobject]@{ id = 'r1'; displayName = 'Fix - Teams'; isGlobalScript = $false }
            [pscustomobject]@{ id = 'r2'; displayName = 'Microsoft - Restart stale'; isGlobalScript = $true }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceHealthScripts/r1' } {
            [pscustomobject]@{ id = 'r1'; displayName = 'Fix - Teams'; detectionScriptContent = $script:b64; remediationScriptContent = $script:b64 }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*deviceRunStates*' } {
            [pscustomobject]@{ detectionState = 'success'; remediationState = 'skipped'; managedDevice = [pscustomobject]@{ id = 'd1'; deviceName = 'PC1' } }
            [pscustomobject]@{ detectionState = 'fail'; remediationState = 'success'; managedDevice = [pscustomobject]@{ id = 'd2'; deviceName = 'PC2' } }
            [pscustomobject]@{ detectionState = 'fail'; remediationState = 'remediationFailed'; managedDevice = [pscustomobject]@{ id = 'd3'; deviceName = 'PC3' } }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'POST' } { [pscustomobject]@{ id = 'r1' } }
    }

    It 'Get-ITRemediation marks and hides built-in scripts, decodes content' {
        (Get-ITRemediation -ExcludeBuiltIn).id | Should -Be 'r1'
        (Get-ITRemediation | Where-Object id -eq 'r2').IsBuiltIn | Should -BeTrue
        (Get-ITRemediation -Name 'Fix*' -IncludeContent).DetectionScriptText | Should -Be 'Write-Output "hello"'
    }

    It 'Get-ITRemediationResult summarises the states' {
        (Get-ITRemediationResult -Id 'r1').Result | Should -Be @('NoIssue', 'Fixed', 'RemediationFailed')
        (Get-ITRemediationResult -Id 'r1' -Status RemediationFailed).DeviceName | Should -Be 'PC3'
    }

    It 'New-ITRemediation sends both scripts' {
        $d = Join-Path $TestDrive 'detect.ps1'; 'exit 1' | Set-Content $d
        $r = Join-Path $TestDrive 'fix.ps1'; 'exit 0' | Set-Content $r
        $null = New-ITRemediation -DisplayName 'Fix - X' -DetectionScriptPath $d -RemediationScriptPath $r -Publisher 'IT'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.publisher -eq 'IT' -and $Body.detectionScriptContent -and $Body.remediationScriptContent
        }
    }

    It 'Invoke-ITRemediationOnDemand posts the script policy ID per device' {
        $r = [pscustomobject]@{ id = 'd1'; deviceName = 'PC1' } | Invoke-ITRemediationOnDemand -RemediationId 'r1'
        $r.Status | Should -Be 'Sent'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq 'deviceManagement/managedDevices/d1/initiateOnDemandProactiveRemediation' -and $Body.scriptPolicyId -eq 'r1' -and $ApiVersion -eq 'beta'
        }
    }
}

Describe 'Update rings and profiles' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceConfigurations' } {
            [pscustomobject]@{ id = 'u1'; displayName = 'Ring 1 - Pilot'; '@odata.type' = '#microsoft.graph.windowsUpdateForBusinessConfiguration'; qualityUpdatesPaused = $false }
            [pscustomobject]@{ id = 'p1'; displayName = 'Wifi'; '@odata.type' = '#microsoft.graph.windows10WiFiConfiguration' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceConfigurations/u1' -and -not $Method } {
            [pscustomobject]@{ id = 'u1'; displayName = 'Ring 1 - Pilot'; '@odata.type' = '#microsoft.graph.windowsUpdateForBusinessConfiguration' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/deviceConfigurations/p1' -and -not $Method } {
            [pscustomobject]@{ id = 'p1'; displayName = 'Wifi'; '@odata.type' = '#microsoft.graph.windows10WiFiConfiguration' }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'PATCH' } { }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -eq 'deviceManagement/windowsFeatureUpdateProfiles' } {
            [pscustomobject]@{ id = 'f1'; displayName = 'Win11 24H2'; endOfSupportDate = (Get-Date).AddDays(10).ToString('o') }
        }
    }

    It 'Get-ITUpdateRing only returns update rings' {
        (Get-ITUpdateRing).id | Should -Be 'u1'
        (Get-ITUpdateRing)[0].PolicyType | Should -Be 'UpdateRing'
    }

    It 'Suspend-ITUpdateRing patches the pause flags with @odata.type' {
        $null = Get-ITUpdateRing | Suspend-ITUpdateRing -UpdateType Both -Confirm:$false
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body['@odata.type'] -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' -and
            $Body.qualityUpdatesPaused -eq $true -and $Body.featureUpdatesPaused -eq $true
        }
    }

    It 'Resume-ITUpdateRing clears only the quality pause by default; -WhatIf sends nothing' {
        $null = Resume-ITUpdateRing -Id 'u1' -Confirm:$false
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' -and $Body.qualityUpdatesPaused -eq $false -and -not $Body.ContainsKey('featureUpdatesPaused') }
        $null = Suspend-ITUpdateRing -Id 'u1' -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'refuses a profile that is not an update ring' {
        $null = Suspend-ITUpdateRing -Id 'p1' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err[0] | Should -BeLike '*not a Windows update ring*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'Get-ITFeatureUpdateProfile adds DaysToEndOfSupport' {
        (Get-ITFeatureUpdateProfile).DaysToEndOfSupport | Should -BeIn 9, 10
    }
}
