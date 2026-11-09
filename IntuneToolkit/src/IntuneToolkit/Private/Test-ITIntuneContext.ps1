function Test-ITIntuneContext {
    <#
    .SYNOPSIS
        Internal: $true when the current script was started by the Intune Management Extension.

    .DESCRIPTION
        Intune runs platform scripts, remediations and Win32 app installs through the Intune
        Management Extension (IME). Detected when:
          - the script path is under the IME folder or the IMECache (Win32 app content), or
          - one of the parent processes (up to 6 levels) is AgentExecutor.exe,
            IntuneManagementExtension.exe or Microsoft.Management.Services.IntuneWindowsAgent.exe.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ScriptPath
    )

    if ($ScriptPath -and $ScriptPath -match '\\Microsoft Intune Management Extension\\|\\IMECache\\') { return $true }

    # Read-only: keep -WhatIf of the caller away from the CimCmdlets auto-import ("Set Alias" noise)
    $WhatIfPreference = $false
    $imeProcesses = 'AgentExecutor.exe', 'IntuneManagementExtension.exe', 'Microsoft.Management.Services.IntuneWindowsAgent.exe'
    try {
        $processId = $PID
        for ($level = 0; $level -lt 6; $level++) {
            $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $processId" -ErrorAction Stop -Verbose:$false
            if (-not $proc) { break }
            if ($level -gt 0 -and $imeProcesses -contains $proc.Name) { return $true }
            if (-not $proc.ParentProcessId -or $proc.ParentProcessId -eq $processId) { break }
            $processId = $proc.ParentProcessId
        }
    }
    catch {
        Write-Verbose -Message "Intune detection: parent processes not readable ($($_.Exception.Message))."
    }
    $false
}
