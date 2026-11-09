#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostic (read-only): captures the raw error Graph/Intune returns for an unknown device ID.

.DESCRIPTION
    Saves exception type, Exception.Message and ErrorDetails.Message to
    TestResults\graph-error-sample.txt so Get-ITGraphErrorInfo can be tuned to the real format.
#>
[CmdletBinding()]
param([string]$TenantId)

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out  = Join-Path $root 'TestResults\graph-error-sample.txt'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $out)

$connect = @{ Scopes = 'DeviceManagementManagedDevices.Read.All'; NoWelcome = $true; ContextScope = 'Process' }
if ($TenantId) { $connect['TenantId'] = $TenantId }
Connect-MgGraph @connect

$lines = New-Object System.Collections.Generic.List[string]
try {
    Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop `
        -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/00000000-0000-0000-0000-000000000000' | Out-Null
    $lines.Add('No error returned?!')
}
catch {
    $e = $_
    $lines.Add("ExceptionType   : $($e.Exception.GetType().FullName)")
    $lines.Add("HasResponse     : $([bool]$e.Exception.PSObject.Properties['Response'])")
    if ($e.Exception.PSObject.Properties['Response'] -and $e.Exception.Response) {
        $lines.Add("StatusCode      : $([int]$e.Exception.Response.StatusCode)")
    }
    $lines.Add('--- Exception.Message ---')
    $lines.Add($e.Exception.Message)
    $lines.Add('--- ErrorDetails.Message ---')
    if ($e.ErrorDetails) { $lines.Add($e.ErrorDetails.Message) } else { $lines.Add('<none>') }
}
Disconnect-MgGraph | Out-Null

$lines | Set-Content -Path $out -Encoding UTF8
Write-Host "Saved: $out" -ForegroundColor Green
