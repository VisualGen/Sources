function Set-ITWamLogin {
    <#
    .SYNOPSIS
        Internal: turns sign-in through the Windows account broker (WAM) off or back on.

    .DESCRIPTION
        Microsoft.Graph.Authentication saves this option for the Windows user (it lasts across
        sessions), so Connect-ITGraph changes it only for one sign-in and restores it right after.

        -Disable returns the previous value ($true/$false), or $null when the installed Graph module
        has no such option (older versions, which do not use WAM). -Restore sets the given value.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable,

        [Parameter(Mandatory, ParameterSetName = 'Restore')]
        [bool]$Restore
    )

    $command = Get-Command -Name 'Set-MgGraphOption' -ErrorAction SilentlyContinue
    if (-not $command -or -not $command.Parameters.ContainsKey('DisableLoginByWAM')) { return $null }

    # Changes only how the next sign-in window is shown; must also work when the caller uses -WhatIf
    $WhatIfPreference = $false
    if ($Disable) {
        $previous = $false
        $options = Get-MgGraphOption
        if ($options -and $options.PSObject.Properties['DisableLoginByWAM']) { $previous = [bool]$options.DisableLoginByWAM }
        if ($PSCmdlet.ShouldProcess('Microsoft Graph sign-in', 'Use the web browser instead of WAM')) {
            Set-MgGraphOption -DisableLoginByWAM $true | Out-Null
        }
        return $previous
    }

    if ($PSCmdlet.ShouldProcess('Microsoft Graph sign-in', "Restore DisableLoginByWAM = $Restore")) {
        Set-MgGraphOption -DisableLoginByWAM $Restore | Out-Null
    }
}
