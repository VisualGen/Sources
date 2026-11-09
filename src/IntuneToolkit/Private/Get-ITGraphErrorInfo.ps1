function Get-ITGraphErrorInfo {
    <#
    .SYNOPSIS
        Internal: extracts HTTP status, Retry-After, Graph error code/message and request-id from an ErrorRecord.

    .DESCRIPTION
        Invoke-MgGraphRequest throws an HttpResponseException whose .Response is an
        HttpResponseMessage. The Graph error body ({ "error": { "code", "message", "innerError" } })
        can be in ErrorDetails.Message OR directly in Exception.Message - both are checked.

        Intune services nest a second JSON document inside error.message, e.g.
          "{ \"_version\": 3, \"Message\": \"An error has occurred - Operation ID ...: x - Activity ID: y - Url: z\" }"
        That inner Message is extracted and shortened to the useful part (text + Activity ID).

        Every lookup is defensive so an unexpected format never hides the original error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = $null
    $retryAfter = $null
    $code       = $null
    $requestId  = $null
    $message    = $ErrorRecord.Exception.Message

    # --- HTTP status and Retry-After from the response ---------------------
    $response = $null
    if ($ErrorRecord.Exception.PSObject.Properties['Response']) {
        $response = $ErrorRecord.Exception.Response
    }
    if ($null -ne $response) {
        try { $statusCode = [int]$response.StatusCode } catch { $statusCode = $null }
        try {
            if ($response.Headers -and $response.Headers.RetryAfter) {
                if ($response.Headers.RetryAfter.Delta) {
                    $retryAfter = [int][math]::Ceiling($response.Headers.RetryAfter.Delta.TotalSeconds)
                }
                elseif ($response.Headers.RetryAfter.Date) {
                    $retryAfter = [int][math]::Max(1, [math]::Ceiling(($response.Headers.RetryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds))
                }
            }
        }
        catch { $retryAfter = $null }
    }

    # --- Graph error body: ErrorDetails first, then the exception text ------
    $candidates = @()
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { $candidates += $ErrorRecord.ErrorDetails.Message }
    if ($ErrorRecord.Exception.Message) { $candidates += $ErrorRecord.Exception.Message }

    # The text may be a full HTTP dump (request line, headers, body). Locate '{"error":' and walk
    # to its matching '}' (ignoring braces inside JSON strings), then parse only that part.
    $found = $false
    foreach ($text in $candidates) {
        $match = [regex]::Match($text, '\{\s*"error"\s*:')
        if (-not $match.Success) { continue }

        $jsonText = $null
        $depth = 0; $inString = $false; $escape = $false
        for ($i = $match.Index; $i -lt $text.Length; $i++) {
            $c = $text[$i]
            if ($escape) { $escape = $false; continue }
            if ($inString) {
                if ($c -eq '\') { $escape = $true }
                elseif ($c -eq '"') { $inString = $false }
                continue
            }
            if ($c -eq '"') { $inString = $true }
            elseif ($c -eq '{') { $depth++ }
            elseif ($c -eq '}') {
                $depth--
                if ($depth -eq 0) { $jsonText = $text.Substring($match.Index, $i - $match.Index + 1); break }
            }
        }

        if ($jsonText) {
            try {
                $err = ($jsonText | ConvertFrom-Json -ErrorAction Stop).error
                if ($err.PSObject.Properties['code'])    { $code = $err.code }
                if ($err.PSObject.Properties['message']) { $message = [string]$err.message }
                if ($err.PSObject.Properties['innerError'] -and $err.innerError -and $err.innerError.PSObject.Properties['request-id']) {
                    $requestId = $err.innerError.'request-id'
                }
                $found = $true
                break
            }
            catch { Write-Verbose -Message "Get-ITGraphErrorInfo: JSON parse failed: $($_.Exception.Message)" }
        }

        # Fallback: pick the fields with regular expressions
        $m = [regex]::Match($text, '"code"\s*:\s*"([^"]*)"')
        if ($m.Success) { $code = $m.Groups[1].Value }
        $m = [regex]::Match($text, '"message"\s*:\s*"((?:[^"\\]|\\.)*)"')
        if ($m.Success) {
            try { $message = ('"' + $m.Groups[1].Value + '"') | ConvertFrom-Json -ErrorAction Stop }
            catch { $message = $m.Groups[1].Value }
        }
        $m = [regex]::Match($text, '"request-id"\s*:\s*"([^"]*)"')
        if ($m.Success) { $requestId = $m.Groups[1].Value }
        if ($code) { $found = $true; break }
    }
    if (-not $found) { Write-Verbose -Message 'Get-ITGraphErrorInfo: no Graph error body found.' }

    # --- Intune: JSON document nested inside error.message ------------------
    if ($message -and $message.TrimStart().StartsWith('{')) {
        try {
            $inner = $message | ConvertFrom-Json -ErrorAction Stop
            if ($inner.PSObject.Properties['Message'] -and $inner.Message) { $message = [string]$inner.Message }
        }
        catch { Write-Verbose -Message 'Get-ITGraphErrorInfo: nested message is not JSON.' }
    }

    # "An error has occurred - Operation ID (for customer support): <id> - Activity ID: <id> - Url: <url>"
    if ($message) {
        $message = $message -replace '\s+-\s+Url:\s+\S+.*$', ''
        $message = $message -replace '\s+-\s+Operation ID \(for customer support\):\s+[0-9a-fA-F-]+', ''
        $message = $message.Trim()
    }

    [pscustomobject]@{
        StatusCode = $statusCode
        RetryAfter = $retryAfter
        Code       = $code
        Message    = $message
        RequestId  = $requestId
    }
}
