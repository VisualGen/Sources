function ConvertTo-ITODataString {
    <#
    .SYNOPSIS
        Internal: escapes a value for use inside an OData string literal (' becomes '').

    .EXAMPLE
        "deviceName eq '{0}'" -f (ConvertTo-ITODataString "O'Brien-PC")
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    $Value -replace "'", "''"
}
