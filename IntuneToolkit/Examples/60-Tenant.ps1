#Requires -Version 5.1
<#
.SYNOPSIS
    Example: tenant administration - RBAC review, Apple tokens, connectors, scope tags.

.DESCRIPTION
    Read-only.
#>

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

Connect-ITGraph    # default read-only scopes include RBAC, service config, apps and groups

# --- Access review -------------------------------------------------------------------
Get-ITRoleDefinition -CustomOnly | Select-Object displayName, @{ n = 'Actions'; e = { @($_.AllowedActions).Count } }
$columns = @(
    'RoleName', 'displayName'
    @{ n = 'Admins'; e = { $_.MemberNames -join '; ' } }
    @{ n = 'Scope'; e = { $_.ScopeMemberNames -join '; ' } }
    @{ n = 'Tags'; e = { $_.ScopeTagNames -join '; ' } }
)
Get-ITRoleAssignment -ResolveName | Select-Object -Property $columns

Get-ITScopeTag -IncludeAssignment

# --- Expiry and health ----------------------------------------------------------------
Get-ITTenantCertificateStatus                     # APNs, ADE/DEP, VPP
Get-ITTenantCertificateStatus | Where-Object Status -ne 'OK'
Get-ITConnectorStatus                             # Intune Connector for AD, NDES, Exchange, MTD, partners

Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
