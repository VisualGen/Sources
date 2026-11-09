#Requires -Version 5.1
<#
.SYNOPSIS
    Example: compliance, configuration, settings catalog, assignments, backup / restore / drift.

.DESCRIPTION
    Read-only blocks run as-is. Blocks that change data use -WhatIf; remove it when you are sure.
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

Connect-ITGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementManagedDevices.Read.All', 'Group.Read.All'

# --- Compliance ----------------------------------------------------------------------
Get-ITCompliancePolicy -IncludeAssignment | Select-Object displayName, Platform, @{ n = 'Assignments'; e = { @($_.Assignments).Count } }
Get-ITNonCompliantDevice -IncludePolicy | Select-Object deviceName, userPrincipalName, @{ n = 'Failed'; e = { $_.FailedPolicies -join '; ' } }
Get-ITCompliancePolicy -Platform Windows | Select-Object -First 1 | Get-ITDeviceComplianceStatus -Status noncompliant

# --- Configuration ----------------------------------------------------------------------
Get-ITConfigurationProfile -Platform Windows | Format-Table
Get-ITSettingsCatalogPolicy -Name 'Win - *' -IncludeSetting | Select-Object -First 1 -ExpandProperty SettingList

# Everything that is not assigned (monthly clean-up)
$unassigned = @(
    Get-ITCompliancePolicy -IncludeAssignment
    Get-ITConfigurationProfile -IncludeAssignment
    Get-ITSettingsCatalogPolicy -IncludeAssignment
) | Where-Object { -not @($_.Assignments).Count }
$unassigned | Select-Object PolicyType, displayName, lastModifiedDateTime

# --- Who gets what? (one group) ------------------------------------------------------------
$groupName = 'SG-Intune-Pilot'
@(Get-ITCompliancePolicy; Get-ITConfigurationProfile; Get-ITSettingsCatalogPolicy) |
    Get-ITPolicyAssignment -ResolveName | Where-Object GroupName -eq $groupName |
    Select-Object PolicyType, ObjectName, Intent, FilterName

# --- Assign / unassign (preview) -----------------------------------------------------------
$pilotGroupId = '00000000-0000-0000-0000-000000000000'
$filter = Get-ITAssignmentFilter -Name 'Windows 11*' | Select-Object -First 1
Get-ITSettingsCatalogPolicy -Name 'Win - Edge' | Add-ITPolicyAssignment -GroupId $pilotGroupId -WhatIf
if ($filter) { Get-ITCompliancePolicy -Name 'Win - Baseline' | Add-ITPolicyAssignment -AllDevices -FilterId $filter.id -WhatIf }
Get-ITConfigurationProfile -Name 'Old Wi-Fi' | Remove-ITPolicyAssignment -All -WhatIf

# --- Backup, drift, restore --------------------------------------------------------------
$backup = Join-Path $env:TEMP "IntuneBackup\$(Get-Date -Format yyyy-MM-dd)"
Export-ITPolicy -Path $backup                                   # all supported types
Compare-ITPolicy -Path $backup                                  # should be empty right after the export
Import-ITPolicy -Path (Join-Path $backup 'SettingsCatalog') -NamePrefix 'Restored - ' -WhatIf

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
