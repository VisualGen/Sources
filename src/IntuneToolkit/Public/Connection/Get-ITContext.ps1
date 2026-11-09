function Get-ITContext {
    <#
    .SYNOPSIS
        Shows the current IntuneToolkit / Microsoft Graph session.

    .DESCRIPTION
        Combines Get-MgContext with IntuneToolkit settings: tenant, signed-in account or app,
        authentication type, granted scopes, default API version and module version.
        Returns nothing when not connected.

    .EXAMPLE
        Get-ITContext

    .EXAMPLE
        (Get-ITContext).Scopes

        Lists the permissions of the current session.

    .OUTPUTS
        IntuneToolkit.Context

    .NOTES
        Graph permission: none.

    .LINK
        Connect-ITGraph
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.Context')]
    param()

    $mg = Get-ITMgContext
    if (-not $mg) {
        Write-ITLog -Message 'Not connected. Run Connect-ITGraph.'
        return
    }

    $connectedAt = $null
    $method      = $null
    if ($script:ITSession) {
        $connectedAt = $script:ITSession.ConnectedAt
        $method      = $script:ITSession.Method
    }

    [pscustomobject]@{
        PSTypeName    = 'IntuneToolkit.Context'
        TenantId      = $mg.TenantId
        Account       = $mg.Account
        AppName       = $mg.AppName
        ClientId      = $mg.ClientId
        AuthType      = [string]$mg.AuthType
        ConnectMethod = $method
        ConnectedAt   = $connectedAt
        Scopes        = @($mg.Scopes | Where-Object { $_ })
        ApiVersion    = $script:ITConfig.DefaultApiVersion
        ModuleVersion = $MyInvocation.MyCommand.Module.Version
    }
}
