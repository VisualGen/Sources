#Requires -Version 5.1
<#
.SYNOPSIS
    Example: Entra ID groups - find, create, rename, members, nested groups, owners, clean-up.

.DESCRIPTION
    Read-only blocks run as-is. Blocks that change data use -WhatIf; remove it when you are sure.
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

$scopes = @(
    'Group.ReadWrite.All', 'User.Read.All', 'Device.Read.All', 'DeviceManagementManagedDevices.Read.All'
    'DeviceManagementConfiguration.Read.All', 'DeviceManagementApps.Read.All'                     # Get-ITGroupAssignment
)
Connect-ITGraph -Scopes $scopes

# --- Find ------------------------------------------------------------------------------
Get-ITGroup -Name 'SG-Intune-*'                                         # prefix, evaluated by Graph
Get-ITGroup -Search 'pilot'                                             # word search in name and description
Get-ITGroup -MembershipType Dynamic | Select-Object displayName, membershipRule, membershipRuleProcessingState

# --- Members and nested groups ---------------------------------------------------------
$parent = 'SG-Intune-All-Pilots'
Get-ITGroupMember -Id $parent                                           # direct members
Get-ITGroupMember -Id $parent -Recurse | Format-Table Depth, MemberType, displayName, Path
Get-ITGroupMember -Id $parent -Transitive -MemberType Device | Measure-Object

# Why does this device get a policy? Its groups, including through nesting
Get-ITManagedDevice -Top 1 | Get-ITGroupMembership -Transitive | Select-Object MemberName, displayName, Direct

# --- Create, nest, add members (preview) --------------------------------------------------
New-ITGroup -DisplayName 'SG-Intune-Pilot-Users' -Description 'Pilot ring - users' -MemberId 'jane@contoso.com' -WhatIf
$rule = '(device.deviceOSType -eq "Windows") and (device.deviceOwnership -eq "Company")'
New-ITGroup -DisplayName 'SG-Intune-Win-Corporate' -MembershipRule $rule -WhatIf               # dynamic device group

Add-ITGroupMember -GroupId $parent -MemberId 'SG-Intune-Pilot-Users' -WhatIf                         # nested group
Get-ITManagedDevice -Name 'NL-LT-*' | Add-ITGroupMember -GroupId 'SG-Intune-Pilot-Devices' -WhatIf   # Intune devices
Remove-ITGroupMember -GroupId 'SG-Intune-Pilot-Users' -MemberId 'john@contoso.com' -WhatIf

# --- Rename, owners, rule ---------------------------------------------------------------
Rename-ITGroup -Id 'Pilot users' -NewName 'SG-Intune-Pilot-Users' -WhatIf
Get-ITGroupOwner -Id 'SG-Intune-Pilot-Users'
Add-ITGroupOwner -GroupId 'SG-Intune-Pilot-Users' -MemberId 'servicedesk.lead@contoso.com' -WhatIf
Set-ITGroup -Id 'SG-Intune-Win-Corporate' -MembershipRuleProcessingState Paused -WhatIf

# --- What does Intune assign to a group? ---------------------------------------------------
Get-ITGroupAssignment -Id 'SG-Intune-Pilot-Devices'                    # direct and through parent groups
Get-ITGroupAssignment -Id 'SG-Intune-Pilot-Devices' -IncludeAllTargets | Group-Object PolicyType | Select-Object Name, Count

# --- Clean-up (monthly) -----------------------------------------------------------------
$empty = Get-ITGroup -Name 'SG-Intune-*' -IncludeMemberCount | Where-Object { $_.MemberCount -eq 0 -and $_.MembershipType -eq 'Assigned' }
$empty | Select-Object displayName, createdDateTime
$unused = $empty | Where-Object { -not @(Get-ITGroupAssignment -Id $_.id -DirectOnly).Count }   # not used in Intune
$unused | Remove-ITGroup -WhatIf

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
