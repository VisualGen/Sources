function Send-ITBlobRequest {
    <#
    .SYNOPSIS
        Internal: PUTs data to the Azure Storage SAS URI that Intune hands out for app content.

    .DESCRIPTION
        Only used by New-ITWin32App. This is NOT a Graph call: the SAS URI already carries the
        authorisation (it must never be logged). Retries 3 times on network / 5xx errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [object]$Body,

        [string]$ContentType = 'application/octet-stream'
    )

    $headers = @{ 'x-ms-blob-type' = 'BlockBlob' }
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $null = Invoke-WebRequest -Uri $Uri -Method Put -Body $Body -Headers $headers -ContentType $ContentType -UseBasicParsing -ErrorAction Stop
            return
        }
        catch {
            # Strip the SAS signature from any error text
            $text = $_.Exception.Message -replace 'sig=[^&\s]+', 'sig=REDACTED'
            if ($attempt -ge $maxAttempts) { throw "Upload to Azure Storage failed after $maxAttempts attempt(s): $text" }
            Write-Verbose -Message "Upload attempt $attempt failed, retrying: $text"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}
