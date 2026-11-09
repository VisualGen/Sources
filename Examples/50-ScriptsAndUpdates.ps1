#Requires -Version 5.1
<#
.SYNOPSIS
    Example: platform scripts, remediations, Windows update rings and profiles.

.DESCRIPTION
    Read-only blocks run as-is. Blocks that change data use -WhatIf; remove it when you are sure.
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

Connect-ITGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementManagedDevices.Read.All', 'DeviceManagementManagedDevices.PrivilegedOperations.All'

# --- Platform scripts ------------------------------------------------------------------------
Get-ITScript | Format-Table
Get-ITScript | Get-ITScriptRunState -FailedOnly | Select-Object ScriptName, DeviceName, ErrorCode, ResultMessage
Get-ITScript | Export-ITScript -Path (Join-Path $env:TEMP 'IntuneScripts') -Force          # source files for review / git

# New-ITScript -Path .\Set-TimeZone.ps1 -WhatIf

# --- Remediations ---------------------------------------------------------------------
Get-ITRemediation -ExcludeBuiltIn | Format-Table
Get-ITRemediation -ExcludeBuiltIn | Get-ITRemediationResult -Status RemediationFailed |
    Select-Object RemediationName, DeviceName, PostRemediationDetectionOutput

# Run one remediation on one device now (preview)
$fix = Get-ITRemediation -ExcludeBuiltIn | Select-Object -First 1
if ($fix) { Get-ITManagedDevice -Top 1 | Invoke-ITRemediationOnDemand -RemediationId $fix.id -WhatIf }

# New-ITRemediation -DisplayName 'Fix - Clear Teams cache' -DetectionScriptPath .\detect.ps1 -RemediationScriptPath .\remediate.ps1 -WhatIf

# --- Windows updates ------------------------------------------------------------------
Get-ITUpdateRing | Select-Object displayName, qualityUpdatesDeferralPeriodInDays, featureUpdatesDeferralPeriodInDays, qualityUpdatesPaused
Get-ITFeatureUpdateProfile | Select-Object displayName, featureUpdateVersion, DaysToEndOfSupport
Get-ITDriverUpdateProfile -IncludeInventory | Select-Object -ExpandProperty Drivers |
    Where-Object approvalStatus -eq 'needsReview' | Select-Object name, version, manufacturer, applicableDeviceCount

# Bad patch: pause quality updates on the pilot ring (preview), resume later
Get-ITUpdateRing -Name '*Pilot*' | Suspend-ITUpdateRing -WhatIf
Get-ITUpdateRing | Where-Object qualityUpdatesPaused | Resume-ITUpdateRing -WhatIf

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
