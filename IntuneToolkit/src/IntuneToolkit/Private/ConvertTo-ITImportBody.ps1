function ConvertTo-ITImportBody {
    <#
    .SYNOPSIS
        Internal: turns an exported Intune object into a POST body for creating it again.

    .DESCRIPTION
        Removes read-only / server-generated properties (generic and per PolicyType),
        rebuilds the settings catalog 'settings' and compliance 'scheduledActionsForRule'
        without IDs, and optionally drops roleScopeTagIds (other tenant: tags do not exist).
        Returns an ordered hashtable.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyType,

        [Parameter(Mandatory)]
        [object]$Object,

        [string]$NewName,

        [switch]$RemoveScopeTag
    )

    $readOnly = @(
        'id', 'createdDateTime', 'lastModifiedDateTime', 'version', 'settingCount', 'creationSource',
        'isAssigned', 'priorityMetaData', 'supportsScopeTags', 'assignments', 'deviceStatuses', 'userStatuses',
        'deviceStatusOverview', 'userStatusOverview', 'deviceSettingStateSummaries', 'deviceRunStates',
        'runSummary', 'groupAssignments', 'PolicyType', 'ObjectType', 'Platform', 'Assignments', 'SettingList'
    )
    $perType = @{
        SettingsCatalog = @('displayName', 'settings', 'templateReference', 'isDefault')
        Compliance      = @('scheduledActionsForRule')
        Remediation     = @('isGlobalScript', 'highestAvailableVersion', 'deviceHealthScriptType', 'detectionScriptParameters', 'remediationScriptParameters')
        FeatureUpdate   = @('endOfSupportDate', 'deployableContentDisplayName')
        DriverUpdate    = @('newUpdates', 'deviceReporting', 'inventorySyncStatus', 'driverInventories')
    }
    $skip = $readOnly
    if ($perType.ContainsKey($PolicyType)) { $skip += $perType[$PolicyType] }
    if ($RemoveScopeTag) { $skip += 'roleScopeTagIds' }

    $body = [ordered]@{}
    foreach ($prop in $Object.PSObject.Properties) {
        if ($skip -contains $prop.Name) { continue }
        if ($prop.Name -like '*@odata.*' -and $prop.Name -ne '@odata.type') { continue }
        $body[$prop.Name] = $prop.Value
    }

    switch ($PolicyType) {
        'SettingsCatalog' {
            $settings = @()
            if ($Object.PSObject.Properties['settings']) {
                $settings = @($Object.settings | Where-Object { $_ } | ForEach-Object {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = $_.settingInstance }
                    })
            }
            $body['settings'] = $settings
            if ($Object.PSObject.Properties['templateReference'] -and $Object.templateReference -and
                $Object.templateReference.PSObject.Properties['templateId'] -and $Object.templateReference.templateId) {
                $body['templateReference'] = @{ templateId = $Object.templateReference.templateId }
            }
            break
        }
        'Compliance' {
            $rules = @()
            if ($Object.PSObject.Properties['scheduledActionsForRule']) {
                $rules = @($Object.scheduledActionsForRule | Where-Object { $_ } | ForEach-Object {
                        $rule = $_
                        $configs = @()
                        if ($rule.PSObject.Properties['scheduledActionConfigurations']) {
                            $configs = @($rule.scheduledActionConfigurations | Where-Object { $_ } | ForEach-Object {
                                    $c = [ordered]@{}
                                    foreach ($n in 'actionType', 'gracePeriodHours', 'notificationTemplateId', 'notificationMessageCCList') {
                                        if ($_.PSObject.Properties[$n]) { $c[$n] = $_.$n }
                                    }
                                    $c
                                })
                        }
                        $ruleName = 'PasswordRequired'
                        if ($rule.PSObject.Properties['ruleName'] -and $rule.ruleName) { $ruleName = $rule.ruleName }
                        @{ ruleName = $ruleName; scheduledActionConfigurations = $configs }
                    })
            }
            # Graph requires at least the 'block' action when a compliance policy is created
            if (-not $rules.Count) {
                $rules = @(@{ ruleName = 'PasswordRequired'; scheduledActionConfigurations = @(@{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = ''; notificationMessageCCList = @() }) })
            }
            $body['scheduledActionsForRule'] = $rules
            break
        }
    }

    if ($NewName) {
        if ($PolicyType -eq 'SettingsCatalog') { $body['name'] = $NewName } else { $body['displayName'] = $NewName }
    }
    $body
}
