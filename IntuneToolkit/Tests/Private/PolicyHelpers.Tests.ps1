#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Shared internal helpers for policies, assignments, reports and Win32 packages.

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITPlatform' {
    It 'maps <Type> to <Expected>' -ForEach @(
        @{ Type = '#microsoft.graph.windows10CompliancePolicy'; Expected = 'Windows' }
        @{ Type = '#microsoft.graph.iosCompliancePolicy'; Expected = 'iOS' }
        @{ Type = '#microsoft.graph.macOSCompliancePolicy'; Expected = 'macOS' }
        @{ Type = '#microsoft.graph.androidDeviceOwnerCompliancePolicy'; Expected = 'Android' }
        @{ Type = '#microsoft.graph.win32LobApp'; Expected = 'Windows' }
        @{ Type = '#microsoft.graph.windows81CompliancePolicy'; Expected = 'Windows8' }
        @{ Type = '#microsoft.graph.somethingElse'; Expected = 'Any' }
    ) {
        InModuleScope IntuneToolkit -Parameters @{ T = $Type; E = $Expected } {
            Get-ITPlatform -InputObject ([pscustomobject]@{ '@odata.type' = $T }) | Should -Be $E
        }
    }

    It 'prefers the settings catalog platforms property' {
        InModuleScope IntuneToolkit {
            Get-ITPlatform -InputObject ([pscustomobject]@{ platforms = 'macOS'; '@odata.type' = '#microsoft.graph.deviceManagementConfigurationPolicy' }) | Should -Be 'macOS'
        }
    }
}

Describe 'ConvertTo-ITSettingList' {
    It 'flattens choice, simple and nested group settings' {
        InModuleScope IntuneToolkit {
            $instance = [pscustomobject]@{
                settingDefinitionId = 'root_choice'
                choiceSettingValue  = [pscustomobject]@{
                    value    = 'root_choice_1'
                    children = @(
                        [pscustomobject]@{ settingDefinitionId = 'child_simple'; simpleSettingValue = [pscustomobject]@{ value = 42 } }
                        [pscustomobject]@{
                            settingDefinitionId         = 'child_group'
                            groupSettingCollectionValue = @([pscustomobject]@{ children = @(
                                        [pscustomobject]@{ settingDefinitionId = 'grand_list'; simpleSettingCollectionValue = @([pscustomobject]@{ value = 'a' }, [pscustomobject]@{ value = 'b' }) }
                                    )
                                })
                        }
                    )
                }
            }
            $rows = @(ConvertTo-ITSettingList -SettingInstance $instance)
            ($rows | Where-Object SettingDefinitionId -eq 'root_choice').Value | Should -Be 'root_choice_1'
            ($rows | Where-Object SettingDefinitionId -eq 'child_simple').Value | Should -Be 42
            ($rows | Where-Object SettingDefinitionId -eq 'grand_list').Value | Should -Be 'a; b'
            $rows.SettingDefinitionId | Should -Not -Contain 'child_group'
        }
    }
}

Describe 'ConvertTo-ITFlatHashtable' {
    It 'flattens nested objects and arrays, ignores keys and sorts plain arrays' {
        InModuleScope IntuneToolkit {
            $obj = [pscustomobject]@{ id = 'x'; displayName = 'P'; nested = [pscustomobject]@{ a = 1; b = $true }; tags = @('2', '1'); list = @([pscustomobject]@{ n = 'v' }) }
            $flat = ConvertTo-ITFlatHashtable -InputObject $obj -Ignore 'id' -Result @{}
            $flat.ContainsKey('id') | Should -BeFalse
            $flat['nested.a'] | Should -Be '1'
            $flat['nested.b'] | Should -Be 'true'
            $flat['tags'] | Should -Be '1,2'
            $flat['list[0].n'] | Should -Be 'v'
        }
    }

    It 'normalises ISO date strings and DateTime to the same text' {
        InModuleScope IntuneToolkit {
            $a = ConvertTo-ITFlatHashtable -InputObject ([pscustomobject]@{ d = '2026-11-01T10:00:00Z' }) -Result @{}
            $b = ConvertTo-ITFlatHashtable -InputObject ([pscustomobject]@{ d = [datetime]::SpecifyKind([datetime]'2026-11-01 10:00:00', 'Utc') }) -Result @{}
            $a['d'] | Should -Be $b['d']
        }
    }

    It 'keys settings catalog settings by definition ID, not by position' {
        InModuleScope IntuneToolkit {
            $s1 = [pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'def_a'; simpleSettingValue = [pscustomobject]@{ value = 'A' } } }
            $s2 = [pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'def_b'; simpleSettingValue = [pscustomobject]@{ value = 'B' } } }
            $x = ConvertTo-ITFlatHashtable -InputObject ([pscustomobject]@{ settings = @($s1, $s2) }) -Result @{}
            $y = ConvertTo-ITFlatHashtable -InputObject ([pscustomobject]@{ settings = @($s2, $s1) }) -Result @{}
            $x['setting:def_a'] | Should -Be 'A'
            ($x.Keys | Sort-Object) -join ',' | Should -Be (($y.Keys | Sort-Object) -join ',')
        }
    }
}

Describe 'ConvertTo-ITImportBody' {
    It 'removes read-only properties and keeps @odata.type' {
        InModuleScope IntuneToolkit {
            $obj = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'; id = '1'; createdDateTime = 'x'; version = 3
                displayName = 'Old'; omaSettings = @(); roleScopeTagIds = @('0', '5'); 'assignments@odata.context' = 'y' }
            $body = ConvertTo-ITImportBody -PolicyType DeviceConfiguration -Object $obj -NewName 'New'
            $body.Keys | Should -Not -Contain 'id'
            $body.Keys | Should -Not -Contain 'createdDateTime'
            $body.Keys | Should -Not -Contain 'version'
            $body.Keys | Should -Not -Contain 'assignments@odata.context'
            $body['@odata.type'] | Should -Be '#microsoft.graph.windows10CustomConfiguration'
            $body['displayName'] | Should -Be 'New'
            $body['roleScopeTagIds'] | Should -Be @('0', '5')
        }
    }

    It 'drops scope tags with -RemoveScopeTag' {
        InModuleScope IntuneToolkit {
            $body = ConvertTo-ITImportBody -PolicyType DeviceConfiguration -Object ([pscustomobject]@{ displayName = 'A'; roleScopeTagIds = @('5') }) -RemoveScopeTag
            $body.Keys | Should -Not -Contain 'roleScopeTagIds'
        }
    }

    It 'rebuilds settings catalog settings and template reference without IDs' {
        InModuleScope IntuneToolkit {
            $obj = [pscustomobject]@{ id = 'p1'; name = 'SC'; displayName = 'SC'; platforms = 'windows10'; technologies = 'mdm'; settingCount = 1
                templateReference = [pscustomobject]@{ templateId = ''; templateFamily = 'none' }
                settings = @([pscustomobject]@{ id = '0'; settingInstance = [pscustomobject]@{ settingDefinitionId = 'd'; simpleSettingValue = [pscustomobject]@{ value = 1 } } })
            }
            $body = ConvertTo-ITImportBody -PolicyType SettingsCatalog -Object $obj -NewName 'SC copy'
            $body['name'] | Should -Be 'SC copy'
            $body.Keys | Should -Not -Contain 'displayName'
            $body.Keys | Should -Not -Contain 'templateReference'
            @($body['settings']).Count | Should -Be 1
            $body['settings'][0].Keys | Should -Not -Contain 'id'
            $body['settings'][0]['@odata.type'] | Should -Be '#microsoft.graph.deviceManagementConfigurationSetting'
        }
    }

    It 'adds the mandatory block action to a compliance policy without scheduled actions' {
        InModuleScope IntuneToolkit {
            $body = ConvertTo-ITImportBody -PolicyType Compliance -Object ([pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; displayName = 'C' })
            $body['scheduledActionsForRule'][0].scheduledActionConfigurations[0].actionType | Should -Be 'block'
        }
    }

    It 'keeps compliance scheduled actions without their IDs' {
        InModuleScope IntuneToolkit {
            $obj = [pscustomobject]@{ displayName = 'C'; scheduledActionsForRule = @([pscustomobject]@{ id = 'r'; ruleName = 'PasswordRequired'
                        scheduledActionConfigurations = @([pscustomobject]@{ id = 'a'; actionType = 'notification'; gracePeriodHours = 24; notificationTemplateId = 't'; notificationMessageCCList = @() }) })
            }
            $body = ConvertTo-ITImportBody -PolicyType Compliance -Object $obj
            $config = $body['scheduledActionsForRule'][0].scheduledActionConfigurations[0]
            $config.Keys | Should -Not -Contain 'id'
            $config['gracePeriodHours'] | Should -Be 24
        }
    }
}

Describe 'New-ITAssignmentTarget' {
    It 'builds <Intent> targets' -ForEach @(
        @{ Intent = 'Include'; Type = '#microsoft.graph.groupAssignmentTarget' }
        @{ Intent = 'Exclude'; Type = '#microsoft.graph.exclusionGroupAssignmentTarget' }
        @{ Intent = 'AllDevices'; Type = '#microsoft.graph.allDevicesAssignmentTarget' }
        @{ Intent = 'AllUsers'; Type = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
    ) {
        InModuleScope IntuneToolkit -Parameters @{ I = $Intent; T = $Type } {
            $target = New-ITAssignmentTarget -Intent $I -GroupId 'g1'
            $target['@odata.type'] | Should -Be $T
        }
    }

    It 'adds a filter and refuses a filter on an exclusion' {
        InModuleScope IntuneToolkit {
            $t = New-ITAssignmentTarget -Intent AllDevices -FilterId 'f1' -FilterType exclude
            $t['deviceAndAppManagementAssignmentFilterId'] | Should -Be 'f1'
            $t['deviceAndAppManagementAssignmentFilterType'] | Should -Be 'exclude'
            { New-ITAssignmentTarget -Intent Exclude -GroupId 'g' -FilterId 'f' } | Should -Throw '*exclusion*'
            { New-ITAssignmentTarget -Intent Include } | Should -Throw '*GroupId*'
        }
    }
}

Describe 'Send-ITAssignmentSet' {
    It 'posts existing (cleaned) plus new assignments under the type-specific key' {
        InModuleScope IntuneToolkit {
            Mock Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assignments' } {
                [pscustomobject]@{ id = 'a1'; source = 'direct'; sourceId = 's'; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'old' } }
            }
            Mock Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*/assign' } { }
            $info = Get-ITPolicyTypeInfo -PolicyType Script
            $count = Send-ITAssignmentSet -TypeInfo $info -Id 's1' -Add @{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
            $count | Should -Be 2
            Should -Invoke Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'deviceManagement/deviceManagementScripts/s1/assign' -and $Method -eq 'POST' -and
                @($Body['deviceManagementScriptAssignments']).Count -eq 2 -and
                -not $Body['deviceManagementScriptAssignments'][0].Contains('id') -and
                -not $Body['deviceManagementScriptAssignments'][0].Contains('source')
            }
        }
    }
}

Describe 'Invoke-ITReport' {
    It 'turns Schema/Values into objects and pages with skip/top' {
        InModuleScope IntuneToolkit {
            $script:calls = 0
            Mock Invoke-ITGraphRequest {
                $script:calls++
                if ($Body.skip -eq 0) {
                    [pscustomobject]@{ TotalRowCount = 3; Schema = @([pscustomobject]@{ Column = 'DeviceName' }, [pscustomobject]@{ Column = 'InstallState' }); Values = @(@('PC1', 'installed'), @('PC2', 'failed')) }
                }
                else {
                    [pscustomobject]@{ TotalRowCount = 3; Schema = @([pscustomobject]@{ Column = 'DeviceName' }, [pscustomobject]@{ Column = 'InstallState' }); Values = @(, @('PC3', 'installed')) }
                }
            }
            $rows = @(Invoke-ITReport -ReportName 'getDeviceInstallStatusReport' -Filter "(ApplicationId eq 'a')" -PageSize 2)
            $rows.Count | Should -Be 3
            $rows[1].InstallState | Should -Be 'failed'
            $script:calls | Should -Be 2
        }
    }

    It 'accepts a byte-array (octet-stream) response' {
        InModuleScope IntuneToolkit {
            $json = '{"TotalRowCount":1,"Schema":[{"Column":"A"}],"Values":[["x"]]}'
            Mock Invoke-ITGraphRequest { , ([System.Text.Encoding]::UTF8.GetBytes($json)) }
            (Invoke-ITReport -ReportName 'r').A | Should -Be 'x'
        }
    }
}

Describe 'Read-ITIntuneWinPackage' {
    It 'reads Detection.xml and extracts the encrypted content' {
        $pkg = Join-Path $TestDrive 'app.intunewin'
        $stage = Join-Path $TestDrive 'stage'
        $null = New-Item -ItemType Directory -Path (Join-Path $stage 'IntuneWinPackage\Metadata') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $stage 'IntuneWinPackage\Contents') -Force
        @'
<ApplicationInfo ToolVersion="1.8.6">
  <Name>Contoso Tool</Name><UnencryptedContentSize>1000</UnencryptedContentSize><FileName>IntunePackage.intunewin</FileName><SetupFile>setup.msi</SetupFile>
  <EncryptionInfo><EncryptionKey>K</EncryptionKey><MacKey>M</MacKey><InitializationVector>IV</InitializationVector><Mac>MAC</Mac>
    <ProfileIdentifier>ProfileVersion1</ProfileIdentifier><FileDigest>D</FileDigest><FileDigestAlgorithm>SHA256</FileDigestAlgorithm></EncryptionInfo>
  <MsiInfo><MsiProductCode>{11111111-2222-3333-4444-555555555555}</MsiProductCode><MsiProductVersion>1.2.3</MsiProductVersion><MsiPublisher>Contoso</MsiPublisher><MsiExecutionContext>System</MsiExecutionContext></MsiInfo>
</ApplicationInfo>
'@ | Set-Content -Path (Join-Path $stage 'IntuneWinPackage\Metadata\Detection.xml') -Encoding UTF8
        [System.IO.File]::WriteAllBytes((Join-Path $stage 'IntuneWinPackage\Contents\IntunePackage.intunewin'), [byte[]](1..200))
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $pkg)

        InModuleScope IntuneToolkit -Parameters @{ P = $pkg } {
            $info = Read-ITIntuneWinPackage -Path $P
            try {
                $info.Name | Should -Be 'Contoso Tool'
                $info.SetupFile | Should -Be 'setup.msi'
                $info.EncryptedSize | Should -Be 200
                $info.Msi.ProductCode | Should -Be '{11111111-2222-3333-4444-555555555555}'
                $info.EncryptionInfo.fileDigestAlgorithm | Should -Be 'SHA256'
                Test-Path $info.EncryptedFilePath | Should -BeTrue
            }
            finally {
                Remove-Item $info.EncryptedFilePath -Force
            }
        }
    }
}
