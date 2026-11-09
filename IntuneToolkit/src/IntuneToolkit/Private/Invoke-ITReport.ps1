function Invoke-ITReport {
    <#
    .SYNOPSIS
        Internal: calls an Intune reports action (POST /deviceManagement/reports/<name>) and returns rows as objects.

    .DESCRIPTION
        The reports API answers with a table: Schema (column names) + Values (rows) + TotalRowCount.
        The response can arrive as an object, a JSON string or a byte array (octet-stream):
        all three are handled. Rows are read in pages of -PageSize with skip/top until
        TotalRowCount is reached (hard cap: 200 pages).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportName,

        [string]$Filter,

        [string[]]$Select,

        [ValidateRange(1, 50000)]
        [int]$PageSize = 1000
    )

    $skip = 0
    $maxPages = 200
    for ($page = 1; $page -le $maxPages; $page++) {
        $body = [ordered]@{ skip = $skip; top = $PageSize }
        if ($Filter) { $body['filter'] = $Filter }
        if ($Select) { $body['select'] = @($Select) }

        $response = Invoke-ITGraphRequest -Uri ('deviceManagement/reports/{0}' -f $ReportName) -Method POST -Body $body -ApiVersion 'beta'

        if ($response -is [byte[]]) { $response = [System.Text.Encoding]::UTF8.GetString($response) }
        if ($response -is [string]) { $response = $response | ConvertFrom-Json }
        if ($null -eq $response -or -not $response.PSObject.Properties['Schema']) {
            throw "Report '$ReportName' returned no table (Schema/Values missing)."
        }

        $columns = @($response.Schema | ForEach-Object { [string]$_.Column })
        $rows = @()
        if ($response.PSObject.Properties['Values']) { $rows = @($response.Values) }

        foreach ($row in $rows) {
            $values = @($row)
            $out = [ordered]@{}
            for ($c = 0; $c -lt $columns.Count; $c++) {
                $value = $null
                if ($c -lt $values.Count) { $value = $values[$c] }
                $out[$columns[$c]] = $value
            }
            [pscustomobject]$out
        }

        $total = 0
        if ($response.PSObject.Properties['TotalRowCount']) { $total = [int]$response.TotalRowCount }
        $skip += $rows.Count
        if ($rows.Count -eq 0 -or $skip -ge $total) { return }
    }
    Write-Warning -Message "Report '$ReportName': stopped after $maxPages pages."
}
