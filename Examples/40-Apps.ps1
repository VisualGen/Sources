#Requires -Version 5.1
<#
.SYNOPSIS
    Example: apps, app assignments, install status, Win32 upload.

.DESCRIPTION
    Read-only blocks run as-is. Blocks that change data use -WhatIf; remove it when you are sure.
    A .intunewin is created with IntuneWinAppUtil.exe (Microsoft Win32 Content Prep Tool):
        IntuneWinAppUtil.exe -c .\Source -s setup.msi -o .\Output
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

Connect-ITGraph -Scopes 'DeviceManagementApps.ReadWrite.All', 'DeviceManagementManagedDevices.Read.All', 'Group.Read.All'

# --- Inventory ------------------------------------------------------------------------------
Get-ITApp | Group-Object ObjectType | Sort-Object Count -Descending | Select-Object Name, Count
Get-ITApp -Unassigned | Select-Object displayName, ObjectType, createdDateTime         # monthly clean-up
Get-ITApp -ObjectType win32LobApp | Get-ITAppAssignment -ResolveName |
    Select-Object ObjectName, InstallIntent, Intent, GroupName

# --- Install status (reports API) ---------------------------------------------------------
Get-ITApp -ObjectType win32LobApp -Assigned |
    Get-ITAppInstallStatus -FailedOnly -Since (Get-Date).AddDays(-1) |
    Select-Object AppName, DeviceName, UserPrincipalName, InstallState, ErrorCode

Get-ITManagedDevice -Top 1 | Get-ITAppInstallStatus                                    # all apps on one device

# --- Assign (preview) ---------------------------------------------------------------------
$pilotGroupId = '00000000-0000-0000-0000-000000000000'
Get-ITApp -Name '7-Zip*' | Add-ITAppAssignment -Intent required -GroupId $pilotGroupId -Notification hideAll -WhatIf
Get-ITApp -Name 'Company Portal' | Add-ITAppAssignment -Intent available -AllUsers -WhatIf
Get-ITApp -Name 'Old VPN client' | Remove-ITAppAssignment -All -WhatIf

# --- Upload a Win32 app -----------------------------------------------------------------
$package = 'C:\Packages\Output\7z2408-x64.intunewin'
if (Test-Path $package) {
    # MSI: install / uninstall / detection come from the MSI information
    New-ITWin32App -Path $package -Publisher 'Igor Pavlov' -AppVersion '24.08' -WhatIf
}

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
