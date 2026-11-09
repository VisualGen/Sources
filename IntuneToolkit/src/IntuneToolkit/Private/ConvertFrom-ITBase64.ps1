function ConvertFrom-ITBase64 {
    <#
    .SYNOPSIS
        Internal: decodes Base64 script content (Intune scriptContent) to text; UTF-8 BOM removed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not $Value) { return $null }
    $bytes = [Convert]::FromBase64String($Value)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $offset = 3 }
    [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
}
