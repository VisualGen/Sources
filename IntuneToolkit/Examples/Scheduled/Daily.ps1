#Requires -Version 5.1
<#
.SYNOPSIS
    Scheduled daily report: non-compliant devices, failed app installs (24 h), devices without check-in > 7 days, Autopilot import errors.

.DESCRIPTION
    Designed for Task Scheduler or Azure Automation. Read-only: nothing in the tenant is changed.
    Unattended: app registration with a certificate and these application permissions (admin consent):
        DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All,
        DeviceManagementApps.Read.All, DeviceManagementServiceConfig.Read.All
    Without -ClientId it signs in interactively (for testing).
    Reports: <ReportPath>\Daily\<yyyy-MM-dd>\ - one CSV and one HTML per report, plus Summary.html.

.PARAMETER TenantId
    Tenant ID or domain (required with -ClientId).

.PARAMETER ClientId
    App registration (client) ID for certificate sign-in.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate in Cert:\CurrentUser\My or Cert:\LocalMachine\My.

.PARAMETER ReportPath
    Root folder for the reports. Default: C:\IntuneReports

.EXAMPLE
    .\Daily.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567

.EXAMPLE
    # Task Scheduler action (daily 06:00)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\IntuneToolkit\Examples\Scheduled\Daily.ps1" -TenantId ... -ClientId ... -CertificateThumbprint ...
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
$ctx = Start-ITScheduledReport -Name 'Daily' -ReportPath $ReportPath -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint

try {
    Save-ITScheduledReport $ctx -Name 'NonCompliant' -Title 'Non-compliant devices' -Data @(Get-ITNonCompliantDevice -IncludePolicy) `
        -Property deviceName, userPrincipalName, operatingSystem, osVersion, lastSyncDateTime, FailedPolicies

    $since = (Get-Date).AddDays(-1)
    $failed = @(Get-ITApp -Assigned | Where-Object { @('win32LobApp', 'winGetApp', 'windowsMobileMSI') -contains $_.ObjectType } |
            Get-ITAppInstallStatus -FailedOnly -Since $since)
    Save-ITScheduledReport $ctx -Name 'FailedAppInstalls' -Title 'Failed app installs (24 h)' -Data $failed

    Save-ITScheduledReport $ctx -Name 'NoCheckin7d' -Title 'Devices without check-in for 7 days' -Data @(Get-ITStaleDevice -Days 7) `
        -Property deviceName, userPrincipalName, operatingSystem, lastSyncDateTime, DaysSinceLastSync

    Save-ITScheduledReport $ctx -Name 'AutopilotImportErrors' -Title 'Autopilot import errors' -Data @(Get-ITAutopilotImportStatus -ErrorOnly) `
        -Property serialNumber, groupTag, Status, ErrorCode, ErrorName
}
finally {
    Stop-ITScheduledReport $ctx
}
