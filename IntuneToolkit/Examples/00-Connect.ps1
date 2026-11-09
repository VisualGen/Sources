#Requires -Version 5.1
<#
.SYNOPSIS
    Example: the different ways to connect IntuneToolkit to Microsoft Graph.

.DESCRIPTION
    Run the block that matches your scenario. Nothing in this file changes tenant data.
#>

# --- 0. Load the module (from the repository) ---------------------------------
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\IntuneToolkit\IntuneToolkit.psd1'
Import-Module $modulePath -Force

# --- Check the machine (works even when the Graph module is missing) ---------
if (-not (Test-ITPrerequisite -Quiet)) {
    Test-ITPrerequisite | Where-Object Status -ne 'OK' | Format-Table Check, Status, Found, Fix -AutoSize -Wrap
    throw 'Fix the prerequisites above first.'
}

# --- Log everything this script does (one line, closed at the end) ----------
Start-ITLog                     # log to %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script

# --- 1. Interactive sign-in, read-only Intune scopes (default) ---------------
try {
    Connect-ITGraph
    Write-ITLog ('Connected to tenant {0}' -f (Get-ITContext).TenantId)            # your own Info event
}
catch {
    Write-ITLog -ErrorRecord $_ -Message 'Sign-in failed'                          # Error event with line and call stack
    Stop-ITLog -Status 'Failed: sign-in'
    return
}

# --- 2. Interactive with write / device-action permissions ------------------
# Connect-ITGraph -Scopes 'DeviceManagementManagedDevices.ReadWrite.All', 'DeviceManagementManagedDevices.PrivilegedOperations.All'

# --- 3. Device code (e.g. from a server without a browser) ------------------
# Connect-ITGraph -UseDeviceCode -TenantId 'contoso.onmicrosoft.com'

# --- 4. Unattended: app registration + certificate (scheduled tasks) -------
# $tenantId   = 'contoso.onmicrosoft.com'
# $appId      = '00000000-0000-0000-0000-000000000000'
# $thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'
# Connect-ITGraph -TenantId $tenantId -ClientId $appId -CertificateThumbprint $thumbprint -ContextScope Process

# --- 5. Azure Automation / Azure VM with managed identity -------------------
# Connect-ITGraph -Identity

# --- Check permissions before doing work -------------------------------------
$needed = 'DeviceManagementManagedDevices.Read.All'
if (-not (Test-ITGraphConnection -RequiredScope $needed)) {
    Write-ITLog -Level Warning -Message "Missing permission $needed - reconnect with: Connect-ITGraph -Scopes $needed"
}

# --- Module settings ----------------------------------------------------------
Set-ITConfiguration -DefaultApiVersion beta     # the log path is managed by Start-ITLog
Get-ITConfiguration

# --- Finish -------------------------------------------------------------------
Disconnect-ITGraph
Stop-ITLog                      # closes the log and the transcript
