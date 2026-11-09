function Test-ITPrerequisite {
    <#
    .SYNOPSIS
        Checks that this machine has everything IntuneToolkit needs: the Microsoft Graph module and runtime.

    .DESCRIPTION
        Run it after Import-Module IntuneToolkit. The module also loads when the Graph module is
        missing, so this command can tell you what to install. Checks:

          PowerShell             Windows PowerShell 5.1 (Desktop edition)
          Framework              Microsoft .NET Framework 4.7.2 or later
          TLS 1.2                enabled for this session (needed for Microsoft Graph and sign-in)
          Graph module installed Microsoft.Graph.Authentication 2.0.0 or later
          Graph module loaded    loaded in this session, and the newest installed version
          Graph module versions  other Microsoft.Graph.* modules on the same version (mixed versions
                                 cause "Assembly with same name is already loaded")
          Module install tools   PowerShellGet and the NuGet provider (only when something must be installed)

        Each check returns Status OK, Warning, Missing, Outdated or Failed, and a Fix command.
        Nothing is installed or changed.

    .PARAMETER Quiet
        Return only $true (nothing Missing, Outdated or Failed) or $false.

    .EXAMPLE
        Import-Module .\src\IntuneToolkit\IntuneToolkit.psd1
        Test-ITPrerequisite

        Shows every check with its status and, where needed, the command to fix it.

    .EXAMPLE
        if (-not (Test-ITPrerequisite -Quiet)) {
            Test-ITPrerequisite | Where-Object Status -ne 'OK' | Format-List Check, Found, Fix
            exit 1
        }

        Stops a script early when the machine is not ready (e.g. in an Intune remediation).

    .OUTPUTS
        IntuneToolkit.PrerequisiteCheck, or [bool] with -Quiet

    .NOTES
        No Graph connection or permission needed.
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.PrerequisiteCheck', [bool])]
    param(
        [switch]$Quiet
    )

    $graphName = $script:ITGraphModule.Name
    $minimum = $script:ITGraphModule.MinimumVersion
    $results = New-Object -TypeName System.Collections.Generic.List[object]
    $add = {
        param([string]$Check, [string]$Status, [string]$Required, [string]$Found, [string]$Fix)
        $results.Add([pscustomobject]@{
                PSTypeName = 'IntuneToolkit.PrerequisiteCheck'
                Check      = $Check
                Status     = $Status
                Required   = $Required
                Found      = $Found
                Fix        = $Fix
            })
    }

    # --- PowerShell ----------------------------------------------------------------------------
    $edition = 'Desktop'
    if ($PSVersionTable.ContainsKey('PSEdition')) { $edition = [string]$PSVersionTable.PSEdition }
    $psFound = '{0} {1}' -f $edition, $PSVersionTable.PSVersion
    if ($edition -eq 'Desktop' -and $PSVersionTable.PSVersion -ge [version]'5.1') {
        & $add 'PowerShell' 'OK' 'Windows PowerShell 5.1' $psFound ''
    }
    else {
        & $add 'PowerShell' 'Warning' 'Windows PowerShell 5.1' $psFound 'IntuneToolkit is built and tested for Windows PowerShell 5.1: run it with powershell.exe'
    }

    # --- .NET Framework ------------------------------------------------------------------------
    $release = $null
    try {
        $ndp = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name 'Release' -ErrorAction Stop
        $release = [int]$ndp.Release
    }
    catch {
        $release = $null
    }
    if ($null -eq $release) {
        & $add '.NET Framework' 'Missing' '4.7.2 or later' 'not found' 'Install .NET Framework 4.8: https://dotnet.microsoft.com/download/dotnet-framework'
    }
    else {
        $netVersion = '4.x'
        foreach ($pair in @(@(533320, '4.8.1'), @(528040, '4.8'), @(461808, '4.7.2'), @(461308, '4.7.1'), @(460798, '4.7'), @(394802, '4.6.2'))) {
            if ($release -ge $pair[0]) { $netVersion = $pair[1]; break }
        }
        $netFound = '{0} (release {1})' -f $netVersion, $release
        if ($release -ge 461808) { & $add '.NET Framework' 'OK' '4.7.2 or later' $netFound '' }
        else { & $add '.NET Framework' 'Outdated' '4.7.2 or later' $netFound 'Install .NET Framework 4.8: https://dotnet.microsoft.com/download/dotnet-framework' }
    }

    # --- TLS 1.2 -------------------------------------------------------------------------------
    $protocols = [Net.ServicePointManager]::SecurityProtocol
    $tlsOk = ($protocols -band [Net.SecurityProtocolType]::Tls12) -or ([int]$protocols -eq 0)   # 0 = SystemDefault (OS decides, TLS 1.2+)
    if ($tlsOk) { & $add 'TLS 1.2' 'OK' 'enabled' ([string]$protocols) '' }
    else {
        & $add 'TLS 1.2' 'Failed' 'enabled' ([string]$protocols) '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12'
    }

    # --- Graph module installed ----------------------------------------------------------------
    $installed = @(Get-Module -ListAvailable -Name $graphName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
    $newest = $null
    $needInstall = $false
    if (-not $installed.Count) {
        $needInstall = $true
        & $add 'Graph module installed' 'Missing' "$graphName $minimum+" 'not installed' "Install-Module $graphName -Scope CurrentUser"
    }
    else {
        $newest = $installed[0].Version
        $versions = @($installed | ForEach-Object { [string]$_.Version } | Select-Object -Unique)
        $found = $versions -join ', '
        if ($newest -ge $minimum) {
            & $add 'Graph module installed' 'OK' "$graphName $minimum+" $found ''
        }
        else {
            $needInstall = $true
            & $add 'Graph module installed' 'Outdated' "$graphName $minimum+" $found "Install-Module $graphName -MinimumVersion $minimum -Scope CurrentUser"
        }
    }

    # --- Graph module loaded -------------------------------------------------------------------
    $loaded = @(Get-Module -Name $graphName)
    if (-not $loaded.Count) {
        $fix = "Import-Module $graphName -MinimumVersion $minimum"
        if ($needInstall) { $fix = 'Install the module first (see above), then start a new PowerShell session' }
        & $add 'Graph module loaded' 'Failed' "$minimum+ in this session" 'not loaded' $fix
    }
    else {
        $loadedVersion = ($loaded | Sort-Object -Property Version -Descending | Select-Object -First 1).Version
        if ($loadedVersion -lt $minimum) {
            & $add 'Graph module loaded' 'Outdated' "$minimum+ in this session" ([string]$loadedVersion) 'Start a new PowerShell session (an older version was loaded first)'
        }
        elseif ($newest -and $loadedVersion -lt $newest) {
            & $add 'Graph module loaded' 'Warning' "$minimum+ in this session" ('{0} (newest installed: {1})' -f $loadedVersion, $newest) 'Start a new PowerShell session to use the newest version'
        }
        else {
            & $add 'Graph module loaded' 'OK' "$minimum+ in this session" ([string]$loadedVersion) ''
        }
    }

    # --- Other Microsoft.Graph.* modules on the same version ---------------------------------------
    if ($newest) {
        $others = @(Get-Module -ListAvailable -Name 'Microsoft.Graph.*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne $graphName } | Group-Object -Property Name | ForEach-Object {
                    $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
                })
        $mismatch = @($others | Where-Object { $_.Version -ne $newest })
        if (-not $others.Count) {
            & $add 'Graph module versions' 'OK' "same as $graphName" 'no other Microsoft.Graph modules (not needed)' ''
        }
        elseif (-not $mismatch.Count) {
            & $add 'Graph module versions' 'OK' "same as $graphName" ('{0} module(s) on {1}' -f $others.Count, $newest) ''
        }
        else {
            $list = @($mismatch | Select-Object -First 5 | ForEach-Object { '{0} {1}' -f $_.Name, $_.Version }) -join ', '
            if ($mismatch.Count -gt 5) { $list += (', +{0} more' -f ($mismatch.Count - 5)) }
            & $add 'Graph module versions' 'Warning' ("same as $graphName ($newest)") $list 'Update-Module Microsoft.Graph* (all to the same version), then start a new PowerShell session'
        }
    }

    # --- Install tools (only relevant when something must be installed) --------------------------
    if ($needInstall) {
        $psGet = @(Get-Module -ListAvailable -Name 'PowerShellGet' -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
        $nuget = Get-ITNuGetProviderVersion
        if ($psGet.Count -and $nuget) {
            & $add 'Module install tools' 'OK' 'PowerShellGet + NuGet provider' ('PowerShellGet {0}, NuGet {1}' -f $psGet[0].Version, $nuget) ''
        }
        else {
            & $add 'Module install tools' 'Missing' 'PowerShellGet + NuGet provider' ('PowerShellGet: {0}, NuGet: {1}' -f [bool]$psGet.Count, [bool]$nuget) 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force'
        }
    }

    $blocking = @($results | Where-Object { @('Missing', 'Outdated', 'Failed') -contains $_.Status })
    if ($Quiet) { return ($blocking.Count -eq 0) }
    $results.ToArray()
}
