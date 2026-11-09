#Requires -Version 5.1
<#
.SYNOPSIS
    Example: daily device operations with IntuneToolkit.

.DESCRIPTION
    Read-only blocks run as-is. Blocks that change devices use -WhatIf so you can see
    what WOULD happen; remove -WhatIf only when you are sure.
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

# Read + device actions + BitLocker/LAPS (delegated, interactive)
Connect-ITGraph -Scopes @(
    'DeviceManagementManagedDevices.ReadWrite.All'
    'DeviceManagementManagedDevices.PrivilegedOperations.All'
    'BitLockerKey.Read.All'
    'DeviceLocalCredential.Read.All'
    'User.Read.All'
)

# --- Find devices ---------------------------------------------------------------
Get-ITManagedDevice -Name 'PC-001'                                   # exact name
Get-ITManagedDevice -Name 'NL-LT-*'                                  # prefix (server side)
Get-ITManagedDevice -UserPrincipalName 'jane@contoso.com'            # all devices of a user
Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant
Get-ITManagedDevice -Top 5 | Format-List *                           # see all properties

# --- Daily: non-compliant Windows devices -> sync them ------------------------------
$nonCompliant = Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant
$nonCompliant | Invoke-ITDeviceSync -WhatIf

# --- Weekly: stale devices report ------------------------------------------------
$reportPath = Join-Path $env:TEMP ('StaleDevices_{0:yyyyMMdd}.csv' -f (Get-Date))
Get-ITStaleDevice -Days 30 |
    Select-Object deviceName, operatingSystem, userPrincipalName, lastSyncDateTime, DaysSinceLastSync, id |
    Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
Write-Output "Report: $reportPath"

# --- Monthly: clean up records older than one year (preview only) ------------------
Get-ITStaleDevice -Days 365 | Remove-ITManagedDevice -WhatIf

# --- Help desk ---------------------------------------------------------------------
Get-ITDeviceBitLockerKey -DeviceName 'LT-0815'                       # recovery key (audited)
Get-ITManagedDevice -Name 'LT-0815' | Invoke-ITBitLockerKeyRotation -WhatIf   # rotate after use

$laps = Get-ITDeviceLapsPassword -DeviceName 'LT-0815'               # password stays SecureString
$laps | Format-Table DeviceName, AccountName, BackupDateTime

Get-ITManagedDevice -Name 'LT-0815' | Invoke-ITDefenderScan -FullScan -WhatIf
Get-ITManagedDevice -Name 'LT-0815' | Set-ITManagedDevicePrimaryUser -UserPrincipalName 'new.owner@contoso.com' -WhatIf

# --- Categories ----------------------------------------------------------------------
Get-ITDeviceCategory
Get-ITManagedDevice -Name 'KIOSK-*' | Set-ITManagedDeviceCategory -CategoryName 'Kiosk' -WhatIf

# --- Bulk action with a result log -----------------------------------------------------
$results = Get-ITManagedDevice -Name 'KIOSK-*' | Invoke-ITDeviceRestart -WhatIf
$results | Where-Object Status -eq 'Failed'

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
