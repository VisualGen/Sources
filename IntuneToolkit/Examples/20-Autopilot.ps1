#Requires -Version 5.1
<#
.SYNOPSIS
    Example: Windows Autopilot and enrollment with IntuneToolkit.

.DESCRIPTION
    Read-only blocks run as-is. Blocks that change data use -WhatIf; remove it when you are sure.
    Hardware hash CSV: created on the device with
        Install-Script Get-WindowsAutopilotInfo; Get-WindowsAutopilotInfo -OutputFile C:\Temp\AutopilotHWID.csv
    or delivered by the OEM / reseller.
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

Connect-ITGraph -Scopes 'DeviceManagementServiceConfig.ReadWrite.All', 'DeviceManagementManagedDevices.Read.All'

# --- Overview ---------------------------------------------------------------------
Get-ITAutopilotDevice                                        # all registered devices
Get-ITAutopilotDevice -SerialNumber 'PF3A'                   # partial serial (server side)
Get-ITAutopilotDevice -GroupTag ''                           # devices without group tag
Get-ITAutopilotSyncStatus

# --- Import new devices (onboarding) -----------------------------------------------
$csv = 'C:\Temp\AutopilotHWID.csv'
if (Test-Path $csv) {
    Import-ITAutopilotDevice -Path $csv -GroupTag 'Standard' -WhatIf
    # Real run: waits, cleans up the import records and syncs Autopilot
    # Import-ITAutopilotDevice -Path $csv -GroupTag 'Standard' -Wait -Sync
}

# --- Group tags ---------------------------------------------------------------------
Get-ITAutopilotDevice -GroupTag '' | Set-ITAutopilotDevice -GroupTag 'Standard' -WhatIf
Get-ITAutopilotDevice -SerialNumber 'PF3A1234' | Set-ITAutopilotDevice -UserPrincipalName 'jane@contoso.com' -AddressableUserName 'Jane' -WhatIf

# --- Find the Intune device of an Autopilot device -------------------------------------
# (the Autopilot 'id' is not the Intune device id - use managedDeviceId)
$ap = Get-ITAutopilotDevice -EnrollmentState enrolled | Select-Object -First 1
if ($ap) { Get-ITManagedDevice -Id $ap.managedDeviceId }

# --- Monthly: registered but never deployed ----------------------------------------------
Get-ITAutopilotDevice -EnrollmentState notContacted |
    Select-Object serialNumber, model, groupTag, purchaseOrderIdentifier |
    Export-Csv -Path (Join-Path $env:TEMP 'Autopilot_NotDeployed.csv') -NoTypeInformation -Encoding UTF8

# --- Devices returned to the vendor: deregister (preview) ---------------------------------
Get-ITAutopilotDevice -SerialNumber 'RETURNED01' | Remove-ITAutopilotDevice -WhatIf

# --- Profiles, restrictions, ESP ------------------------------------------------------------
Get-ITAutopilotProfile -IncludeAssignment |
    Select-Object displayName, JoinType, @{ n = 'Assignments'; e = { ($_.Assignments | ForEach-Object { "$($_.Intent):$($_.GroupId)" }) -join '; ' } }

Get-ITEnrollmentRestriction                                   # evaluation order, defaults last
Get-ITEnrollmentRestriction -Type DeviceLimit | Select-Object displayName, priority, limit
Get-ITEnrollmentStatusPage | Select-Object displayName, priority, installProgressTimeoutInMinutes, @{ n = 'BlockingApps'; e = { @($_.selectedMobileAppIds).Count } }

Invoke-ITAutopilotSync -WhatIf

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
