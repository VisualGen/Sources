function Export-ITReport {
    <#
    .SYNOPSIS
        Writes pipeline objects to a CSV or a self-contained HTML report.

    .DESCRIPTION
        Report helper for the scheduled Daily / Weekly / Monthly scripts. Collects every piped
        object and writes one file:
          CSV  - UTF-8, ';' or ',' delimiter (-Delimiter), no type header
          HTML - one table with title, generation time, row count and inline CSS (no external
                  files, opens in any browser and can be mailed). All values are HTML-encoded.
        The format follows the file extension unless -Format is given. Array values are joined
        with '; '. Returns the FileInfo of the report. An empty input still writes a report
        ("No rows"), so a scheduled job always produces evidence that it ran.

    .PARAMETER InputObject
        Objects to write (pipeline).

    .PARAMETER Path
        Target file (.csv or .html). The folder is created when missing.

    .PARAMETER Format
        Csv or Html. Default: from the extension of -Path.

    .PARAMETER Title
        HTML title / heading. Default: the file name.

    .PARAMETER Property
        Columns to write, in this order. Default: the properties of the first object.

    .PARAMETER Delimiter
        CSV delimiter. Default: ','.

    .EXAMPLE
        Get-ITStaleDevice -Days 90 | Export-ITReport -Path .\Reports\Stale90.csv

    .EXAMPLE
        Get-ITNonCompliantDevice -IncludePolicy |
            Export-ITReport -Path ".\Reports\NonCompliant_$(Get-Date -Format yyyy-MM-dd).html" -Title 'Non-compliant devices' `
                -Property deviceName, userPrincipalName, operatingSystem, lastSyncDateTime, FailedPolicies

    .OUTPUTS
        System.IO.FileInfo

    .NOTES
        No Graph call.

    .LINK
        Get-ITNonCompliantDevice
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('Csv', 'Html')]
        [string]$Format,

        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [ValidateNotNullOrEmpty()]
        [string[]]$Property,

        [ValidateLength(1, 1)]
        [string]$Delimiter = ','
    )

    begin {
        $rows = New-Object -TypeName System.Collections.Generic.List[object]
    }

    process {
        if ($null -ne $InputObject) { $rows.Add($InputObject) }
    }

    end {
        $fmt = $Format
        if (-not $fmt) {
            if ($Path -match '\.html?$') { $fmt = 'Html' } else { $fmt = 'Csv' }
        }
        $folder = Split-Path -Parent $Path
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
        $reportTitle = $Title
        if (-not $reportTitle) { $reportTitle = [System.IO.Path]::GetFileNameWithoutExtension($Path) }

        $columns = $Property
        if (-not $columns -and $rows.Count) {
            $columns = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
        }
        $columns = @($columns | Where-Object { $_ })

        # Flatten: arrays -> '; ', nested objects -> JSON
        $flat = foreach ($row in $rows) {
            $out = [ordered]@{}
            foreach ($col in $columns) {
                $value = $null
                if ($row.PSObject.Properties[$col]) { $value = $row.$col }
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $value = @($value | ForEach-Object { if ($_ -is [string] -or $_ -is [ValueType]) { [string]$_ } else { ConvertTo-Json -InputObject $_ -Compress -Depth 5 } }) -join '; '
                }
                elseif ($null -ne $value -and -not ($value -is [string] -or $value -is [ValueType])) {
                    $value = ConvertTo-Json -InputObject $value -Compress -Depth 5
                }
                $out[$col] = $value
            }
            [pscustomobject]$out
        }

        if ($fmt -eq 'Csv') {
            if ($rows.Count) {
                $flat | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
            }
            else {
                Set-Content -LiteralPath $Path -Value '"No rows"' -Encoding UTF8
            }
        }
        else {
            $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
            $sb = New-Object -TypeName System.Text.StringBuilder
            $null = $sb.AppendLine('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">')
            $null = $sb.AppendLine(('<title>{0}</title>' -f (& $enc $reportTitle)))
            $null = $sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;font-size:13px;margin:24px;color:#222}h1{font-size:20px;margin:0 0 4px}' +
                '.meta{color:#666;margin-bottom:12px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:4px 8px;text-align:left;vertical-align:top}' +
                'th{background:#0078d4;color:#fff;position:sticky;top:0}tr:nth-child(even){background:#f5f8fc}</style></head><body>')
            $null = $sb.AppendLine(('<h1>{0}</h1>' -f (& $enc $reportTitle)))
            $null = $sb.AppendLine(('<div class="meta">Generated {0} &middot; {1} row(s) &middot; IntuneToolkit</div>' -f (& $enc (Get-Date -Format 'yyyy-MM-dd HH:mm')), $rows.Count))
            if ($rows.Count) {
                $null = $sb.Append('<table><thead><tr>')
                foreach ($col in $columns) { $null = $sb.Append(('<th>{0}</th>' -f (& $enc $col))) }
                $null = $sb.AppendLine('</tr></thead><tbody>')
                foreach ($row in $flat) {
                    $null = $sb.Append('<tr>')
                    foreach ($col in $columns) { $null = $sb.Append(('<td>{0}</td>' -f (& $enc $row.$col))) }
                    $null = $sb.AppendLine('</tr>')
                }
                $null = $sb.AppendLine('</tbody></table>')
            }
            else {
                $null = $sb.AppendLine('<p>No rows.</p>')
            }
            $null = $sb.AppendLine('</body></html>')
            [System.IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path), $sb.ToString(), (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        }
        Get-Item -LiteralPath $Path
    }
}
