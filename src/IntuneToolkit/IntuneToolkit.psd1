@{
    # --- Identity ---------------------------------------------------------
    RootModule           = 'IntuneToolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '744b6229-6827-4f69-8659-8024430b8e08'
    Author               = 'antoniodv'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2026 antoniodv. All rights reserved.'
    Description          = 'PowerShell 5.1 toolkit for Microsoft Intune management through Microsoft Graph.'

    # --- Runtime ----------------------------------------------------------
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')
    DotNetFrameworkVersion = '4.7.2'

    # Microsoft.Graph.Authentication 2.0.0+ is loaded by IntuneToolkit.psm1, not listed in RequiredModules:
    # the module must still load when it is missing, so Test-ITPrerequisite can say what to install.

    # --- Default table views --------------------------------------------
    FormatsToProcess     = @('Formats\IntuneToolkit.Format.ps1xml')

    # --- Exports (kept explicit for fast import; updated by build\build.ps1) --
    FunctionsToExport    = @(
        'Add-ITAppAssignment'
        'Add-ITGroupMember'
        'Add-ITGroupOwner'
        'Add-ITPolicyAssignment'
        'Compare-ITPolicy'
        'Connect-ITGraph'
        'Disconnect-ITGraph'
        'Export-ITPolicy'
        'Export-ITReport'
        'Export-ITScript'
        'Get-ITApp'
        'Get-ITAppAssignment'
        'Get-ITAppInstallStatus'
        'Get-ITAssignmentFilter'
        'Get-ITAutopilotDevice'
        'Get-ITAutopilotImportStatus'
        'Get-ITAutopilotProfile'
        'Get-ITAutopilotSyncStatus'
        'Get-ITCompliancePolicy'
        'Get-ITConfiguration'
        'Get-ITConfigurationProfile'
        'Get-ITConnectorStatus'
        'Get-ITContext'
        'Get-ITDeviceBitLockerKey'
        'Get-ITDeviceCategory'
        'Get-ITDeviceComplianceStatus'
        'Get-ITDeviceLapsPassword'
        'Get-ITDriverUpdateProfile'
        'Get-ITEnrollmentRestriction'
        'Get-ITEnrollmentStatusPage'
        'Get-ITFeatureUpdateProfile'
        'Get-ITGroup'
        'Get-ITGroupAssignment'
        'Get-ITGroupMember'
        'Get-ITGroupMembership'
        'Get-ITGroupOwner'
        'Get-ITManagedDevice'
        'Get-ITNonCompliantDevice'
        'Get-ITPolicyAssignment'
        'Get-ITRemediation'
        'Get-ITRemediationResult'
        'Get-ITRoleAssignment'
        'Get-ITRoleDefinition'
        'Get-ITScopeTag'
        'Get-ITScript'
        'Get-ITScriptRunState'
        'Get-ITSettingsCatalogPolicy'
        'Get-ITStaleDevice'
        'Get-ITTenantCertificateStatus'
        'Get-ITUpdateRing'
        'Import-ITAutopilotDevice'
        'Import-ITPolicy'
        'Invoke-ITAutopilotSync'
        'Invoke-ITBitLockerKeyRotation'
        'Invoke-ITDefenderScan'
        'Invoke-ITDeviceRestart'
        'Invoke-ITDeviceRetire'
        'Invoke-ITDeviceSync'
        'Invoke-ITDeviceWipe'
        'Invoke-ITRemediationOnDemand'
        'New-ITGroup'
        'New-ITRemediation'
        'New-ITScript'
        'New-ITWin32App'
        'Remove-ITAppAssignment'
        'Remove-ITAutopilotDevice'
        'Remove-ITGroup'
        'Remove-ITGroupMember'
        'Remove-ITGroupOwner'
        'Remove-ITManagedDevice'
        'Remove-ITPolicyAssignment'
        'Rename-ITGroup'
        'Resume-ITUpdateRing'
        'Set-ITAutopilotDevice'
        'Set-ITConfiguration'
        'Set-ITGroup'
        'Set-ITManagedDeviceCategory'
        'Set-ITManagedDevicePrimaryUser'
        'Start-ITLog'
        'Stop-ITLog'
        'Suspend-ITUpdateRing'
        'Test-ITGraphConnection'
        'Test-ITPrerequisite'
        'Write-ITLog'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    # --- Gallery metadata -------------------------------------------------
    PrivateData          = @{
        PSData = @{
            Tags         = @('Intune', 'MicrosoftGraph', 'Graph', 'Endpoint', 'MEM', 'MDM', 'Autopilot', 'Windows')
            ProjectUri   = ''
            LicenseUri   = ''
            Prerelease   = ''
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}
