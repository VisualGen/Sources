function Get-ITPolicyTypeInfo {
    <#
    .SYNOPSIS
        Internal: central registry of the Intune object types handled by the generic policy functions.

    .DESCRIPTION
        One entry per PolicyType with:
          Path          - Graph collection path
          ApiVersion    - API version used for export/import/assign (beta: the full object model)
          ReadScope     - delegated scope to read
          WriteScope    - delegated scope to create/assign
          AssignKey     - property name of the array in the POST {id}/assign body
          TypeName      - IntuneToolkit type name for the returned objects
          NameProperty  - 'displayName' or 'name' (settings catalog)
          ExportExpand  - $expand used when exporting a single object (or $null)
          ODataType     - when set, only objects of this @odata.type belong to the PolicyType
        Without -PolicyType all entries are returned (ordered).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Compliance', 'DeviceConfiguration', 'SettingsCatalog', 'Script', 'Remediation',
            'UpdateRing', 'FeatureUpdate', 'DriverUpdate', 'App')]
        [string]$PolicyType
    )

    $registry = [ordered]@{
        Compliance          = @{ Path = 'deviceManagement/deviceCompliancePolicies'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'assignments'; TypeName = 'CompliancePolicy'; NameProperty = 'displayName'
            ExportExpand = 'scheduledActionsForRule($expand=scheduledActionConfigurations)'; ODataType = $null
        }
        DeviceConfiguration = @{ Path = 'deviceManagement/deviceConfigurations'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'assignments'; TypeName = 'ConfigurationProfile'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = $null
        }
        SettingsCatalog     = @{ Path = 'deviceManagement/configurationPolicies'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'assignments'; TypeName = 'SettingsCatalogPolicy'; NameProperty = 'name'
            ExportExpand = $null; ODataType = $null
        }
        Script              = @{ Path = 'deviceManagement/deviceManagementScripts'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'deviceManagementScriptAssignments'; TypeName = 'Script'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = $null
        }
        Remediation         = @{ Path = 'deviceManagement/deviceHealthScripts'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'deviceHealthScriptAssignments'; TypeName = 'Remediation'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = $null
        }
        UpdateRing          = @{ Path = 'deviceManagement/deviceConfigurations'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'assignments'; TypeName = 'UpdateRing'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = '#microsoft.graph.windowsUpdateForBusinessConfiguration'
        }
        FeatureUpdate       = @{ Path = 'deviceManagement/windowsFeatureUpdateProfiles'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'assignments'; TypeName = 'FeatureUpdateProfile'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = $null
        }
        DriverUpdate        = @{ Path = 'deviceManagement/windowsDriverUpdateProfiles'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementConfiguration.Read.All'; WriteScope = 'DeviceManagementConfiguration.ReadWrite.All'
            AssignKey = 'assignments'; TypeName = 'DriverUpdateProfile'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = $null
        }
        App                 = @{ Path = 'deviceAppManagement/mobileApps'; ApiVersion = 'beta'
            ReadScope = 'DeviceManagementApps.Read.All'; WriteScope = 'DeviceManagementApps.ReadWrite.All'
            AssignKey = 'mobileAppAssignments'; TypeName = 'App'; NameProperty = 'displayName'
            ExportExpand = $null; ODataType = $null
        }
    }

    if ($PolicyType) {
        $info = $registry[$PolicyType]
        $info['PolicyType'] = $PolicyType
        return $info
    }
    foreach ($key in $registry.Keys) {
        $entry = $registry[$key]
        $entry['PolicyType'] = $key
        $entry
    }
}
