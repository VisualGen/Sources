function Get-ITMgContext {
    <#
    .SYNOPSIS
        Internal: Get-MgContext, or $null when Microsoft.Graph.Authentication is not available.

    .DESCRIPTION
        IntuneToolkit loads without the Graph module (so Test-ITPrerequisite can explain what is
        missing). Status commands use this wrapper and report "not connected" instead of failing
        with "The term 'Get-MgContext' is not recognized".
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue)) { return $null }
    Get-MgContext
}
