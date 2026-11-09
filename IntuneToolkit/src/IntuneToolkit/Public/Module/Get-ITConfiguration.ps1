function Get-ITConfiguration {
    <#
    .SYNOPSIS
        Returns the current IntuneToolkit module settings.

    .DESCRIPTION
        Shows the module-wide defaults used by every IntuneToolkit function:
        default Graph API version, retry behaviour, page size and optional log file.
        Change them with Set-ITConfiguration.

    .EXAMPLE
        Get-ITConfiguration

        Displays the current settings.

    .OUTPUTS
        IntuneToolkit.Configuration

    .NOTES
        Graph permission: none.

    .LINK
        Set-ITConfiguration
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.Configuration')]
    param()

    $result = [ordered]@{ PSTypeName = 'IntuneToolkit.Configuration' }
    foreach ($key in ($script:ITConfig.Keys | Sort-Object)) {
        $result[$key] = $script:ITConfig[$key]
    }
    [pscustomobject]$result
}
