#Requires -Version 5.1
<#
.SYNOPSIS
    Scheduled monthly report: inventory, configuration backup, unassigned policies/apps, Apple tokens, connectors, RBAC.

.DESCRIPTION
    Designed for Task Scheduler or Azure Automation. Read-only: nothing in the tenant is changed.
    Unattended: app registration with a certificate and these application permissions (admin consent):
        DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All,
        DeviceManagementApps.Read.All, DeviceManagementServiceConfig.Read.All,
        DeviceManagementRBAC.Read.All, Group.Read.All
    Without -ClientId it signs in interactively (for testing).
    Reports: <ReportPath>\Monthly\<yyyy-MM-dd>\ - CSV + HTML per report, Summary.html and a JSON
    configuration backup in Backup\ (restore with Import-ITPolicy, drift with Compare-ITPolicy).

.PARAMETER TenantId
    Tenant ID or domain (required with -ClientId).

.PARAMETER ClientId
    App registration (client) ID for certificate sign-in.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate in Cert:\CurrentUser\My or Cert:\LocalMachine\My.

.PARAMETER ReportPath
    Root folder for the reports. Default: C:\IntuneReports

.EXAMPLE
    .\Monthly.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
#>
[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$CertificateThumbprint,
    [string]$ReportPath = 'C:\IntuneReports'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$ctx = Start-ITScheduledReport -Name 'Monthly' -ReportPath $ReportPath -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint

try {
    Save-ITScheduledReport $ctx -Name 'Inventory' -Title 'Device inventory' -Data @(Get-ITManagedDevice) `
        -Property deviceName, userPrincipalName, operatingSystem, osVersion, manufacturer, model, serialNumber, complianceState, managedDeviceOwnerType, enrolledDateTime, lastSyncDateTime

    $backup = @(Export-ITPolicy -Path (Join-Path $ctx.OutDir 'Backup'))
    $ctx.Summary.Add([pscustomobject]@{ Report = 'Configuration backup (JSON)'; Rows = $backup.Count; File = 'Backup\' })

    $unassigned = @(
        Get-ITCompliancePolicy -IncludeAssignment
        Get-ITConfigurationProfile -IncludeAssignment
        Get-ITSettingsCatalogPolicy -IncludeAssignment
        Get-ITScript -IncludeAssignment
    ) | Where-Object { -not @($_.Assignments).Count }
    Save-ITScheduledReport $ctx -Name 'UnassignedPolicies' -Title 'Unassigned policies and scripts' -Data @($unassigned) -Property PolicyType, displayName, lastModifiedDateTime, id
    Save-ITScheduledReport $ctx -Name 'UnassignedApps' -Title 'Unassigned apps' -Data @(Get-ITApp -Unassigned) -Property displayName, ObjectType, createdDateTime, id

    Save-ITScheduledReport $ctx -Name 'AppleTokens' -Title 'Apple tokens and certificates' -Data @(Get-ITTenantCertificateStatus)
    Save-ITScheduledReport $ctx -Name 'Connectors' -Title 'Connector health' -Data @(Get-ITConnectorStatus)
    Save-ITScheduledReport $ctx -Name 'FeatureUpdates' -Title 'Feature update profiles' -Data @(Get-ITFeatureUpdateProfile) -Property displayName, featureUpdateVersion, DaysToEndOfSupport
    Save-ITScheduledReport $ctx -Name 'RoleAssignments' -Title 'Intune role assignments' -Data @(Get-ITRoleAssignment -ResolveName) `
        -Property RoleName, displayName, MemberNames, ScopeType, ScopeMemberNames, ScopeTagNames
}
finally {
    Stop-ITScheduledReport $ctx
}
