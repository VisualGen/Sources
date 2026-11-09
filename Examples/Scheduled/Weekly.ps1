#Requires -Version 5.1
<#
.SYNOPSIS
    Scheduled weekly report: stale devices (30/60/90 days), encryption, OS versions, remediation and script failures.

.DESCRIPTION
    Designed for Task Scheduler or Azure Automation. Read-only: nothing in the tenant is changed.
    Unattended: app registration with a certificate and these application permissions (admin consent):
        DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All
    Without -ClientId it signs in interactively (for testing).
    Reports: <ReportPath>\Weekly\<yyyy-MM-dd>\ - one CSV and one HTML per report, plus Summary.html.

.PARAMETER TenantId
    Tenant ID or domain (required with -ClientId).

.PARAMETER ClientId
    App registration (client) ID for certificate sign-in.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate in Cert:\CurrentUser\My or Cert:\LocalMachine\My.

.PARAMETER ReportPath
    Root folder for the reports. Default: C:\IntuneReports

.EXAMPLE
    .\Weekly.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
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
$ctx = Start-ITScheduledReport -Name 'Weekly' -ReportPath $ReportPath -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint

try {
    foreach ($age in 30, 60, 90) {
        Save-ITScheduledReport $ctx -Name "Stale$age" -Title "Stale devices ($age days)" -Data @(Get-ITStaleDevice -Days $age) `
            -Property deviceName, userPrincipalName, operatingSystem, lastSyncDateTime, DaysSinceLastSync
    }

    $devices = @(Get-ITManagedDevice -ApiVersion beta)
    $notEncrypted = @($devices | Where-Object { $_.PSObject.Properties['isEncrypted'] -and -not $_.isEncrypted })
    Save-ITScheduledReport $ctx -Name 'NotEncrypted' -Title 'Devices not encrypted' -Data $notEncrypted `
        -Property deviceName, userPrincipalName, operatingSystem, osVersion, lastSyncDateTime

    $osVersions = @($devices | Group-Object operatingSystem, osVersion | Sort-Object Count -Descending |
            Select-Object @{ n = 'OsVersion'; e = { $_.Name } }, Count)
    Save-ITScheduledReport $ctx -Name 'OsVersions' -Title 'OS version distribution' -Data $osVersions

    Save-ITScheduledReport $ctx -Name 'RemediationFailures' -Title 'Remediation failures' `
        -Data @(Get-ITRemediation -ExcludeBuiltIn | Get-ITRemediationResult -Status RemediationFailed)

    Save-ITScheduledReport $ctx -Name 'ScriptFailures' -Title 'Platform script failures' -Data @(Get-ITScript | Get-ITScriptRunState -FailedOnly)
}
finally {
    Stop-ITScheduledReport $ctx
}
