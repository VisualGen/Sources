function Send-ITGraphRequest {
    <#
    .SYNOPSIS
        Internal: the ONLY place that calls Microsoft Graph.

    .DESCRIPTION
        Thin wrapper around Invoke-MgGraphRequest. Keeping it separate means:
        - Pester tests mock this one function instead of the Graph SDK.
        - Swapping the transport (e.g. raw Invoke-RestMethod) only touches this file.
        Retries, paging and error handling live in Invoke-ITGraphRequest.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Method,

        [string]$Body,

        [hashtable]$Headers
    )

    $params = @{
        Uri         = $Uri
        Method      = $Method
        OutputType  = 'PSObject'
        ErrorAction = 'Stop'
    }
    if ($Body)    { $params['Body'] = $Body; $params['ContentType'] = 'application/json' }
    if ($Headers) { $params['Headers'] = $Headers }

    Invoke-MgGraphRequest @params
}
