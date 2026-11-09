function New-ITGraphUri {
    <#
    .SYNOPSIS
        Internal: builds a relative Graph URI with encoded OData query options.

    .DESCRIPTION
        Several -Filter clauses are joined with ' and ' (each wrapped in parentheses when there
        is more than one). Values are URL-encoded so names with spaces, '#' or '&' are safe.

    .EXAMPLE
        New-ITGraphUri -Path 'deviceManagement/managedDevices' -Filter "operatingSystem eq 'Windows'" -Select id, deviceName -Top 10
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds a string; changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Filter,

        [string[]]$Select,

        [string[]]$Expand,

        [string]$OrderBy,

        [int]$Top
    )

    # .NET Framework 4.x EscapeDataString leaves ' ( ) unencoded (.NET Core encodes them): encode explicitly
    $encode = { param([string]$s) [uri]::EscapeDataString($s).Replace("'", '%27').Replace('(', '%28').Replace(')', '%29') }

    $query = New-Object -TypeName System.Collections.Generic.List[string]

    $clauses = @($Filter | Where-Object { $_ })
    if ($clauses.Count -gt 1) { $clauses = @($clauses | ForEach-Object { "($_)" }) }
    if ($clauses.Count) { $query.Add('$filter=' + (& $encode ($clauses -join ' and '))) }

    $fields = @($Select | Where-Object { $_ })
    if ($fields.Count) { $query.Add('$select=' + (& $encode ($fields -join ','))) }

    $expands = @($Expand | Where-Object { $_ })
    if ($expands.Count) { $query.Add('$expand=' + (& $encode ($expands -join ','))) }

    if ($OrderBy) { $query.Add('$orderby=' + (& $encode $OrderBy)) }
    if ($Top -gt 0) { $query.Add('$top=' + $Top) }

    if ($query.Count) {
        '{0}?{1}' -f $Path, ($query -join '&')
    }
    else {
        $Path
    }
}
