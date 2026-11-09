function Disconnect-ITGraph {
    <#
    .SYNOPSIS
        Disconnects the current Microsoft Graph session.

    .DESCRIPTION
        Calls Disconnect-MgGraph and clears the IntuneToolkit session. Safe to call when not connected.

        -Force disconnects in every case: it calls Disconnect-MgGraph even when no session is
        visible (for example a session left behind by a failed sign-in, or by another module in
        the same PowerShell window), ignores errors and does not ask for confirmation. Disconnect-
        MgGraph also removes the cached sign-in of the account, so the next Connect-ITGraph asks
        you to sign in again (use it to switch to another account or tenant).

    .PARAMETER Force
        Disconnect even when no session is visible, ignore errors, no confirmation.

    .EXAMPLE
        Disconnect-ITGraph

    .EXAMPLE
        Disconnect-ITGraph -Force
        Connect-ITGraph -TenantId 'fabrikam.onmicrosoft.com'

        Ends any leftover session and signs in to another tenant.

    .OUTPUTS
        None.

    .NOTES
        Graph permission: none.

    .LINK
        Connect-ITGraph
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force
    )

    if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'None' }

    $context = Get-ITMgContext
    if (-not $context -and -not $Force) {
        Write-ITLog -Message 'No active Graph session.'
        $script:ITSession = $null
        return
    }

    $target = 'Microsoft Graph session'
    if ($context) {
        $who = $context.Account
        if (-not $who) { $who = $context.AppName }
        $target = 'Microsoft Graph session ({0}, tenant {1})' -f $who, $context.TenantId
    }

    if ($PSCmdlet.ShouldProcess($target, 'Disconnect')) {
        if (Get-Command -Name 'Disconnect-MgGraph' -ErrorAction SilentlyContinue) {
            try {
                Disconnect-MgGraph -ErrorAction Stop | Out-Null
            }
            catch {
                # -Force: nothing to sign out from, or a broken session - the goal is "disconnected"
                if ($Force) { Write-ITLog -Message "Disconnect-MgGraph (ignored with -Force): $($_.Exception.Message)" }
                else { Write-ITLog -Level Warning -Message "Disconnect-MgGraph: $($_.Exception.Message)" }
            }
        }
        $script:ITSession = $null

        if ($Force -and (Get-ITMgContext)) {
            Write-ITLog -Level Warning -Message 'A Graph session is still visible after Disconnect-MgGraph. Close this PowerShell window to end it.'
        }
        else {
            Write-ITLog -Message 'Disconnected from Microsoft Graph.'
        }
    }
}
