function Invoke-ITGraphRequest {
    <#
    .SYNOPSIS
        Internal: calls Microsoft Graph with paging, throttling/retry handling and error normalisation.

    .DESCRIPTION
        Every public IntuneToolkit function uses this function to talk to Graph.

        - Relative URIs ('deviceManagement/managedDevices') are prefixed with the base URI and API version.
        - Collection responses ('value') are unrolled to individual objects on the pipeline.
        - -All follows '@odata.nextLink' until every page has been read.
        - HTTP 429 and 5xx responses are retried up to MaxRetry times, honouring Retry-After.
        - Other errors are re-thrown as a terminating error with the Graph error code and message.

    .PARAMETER Uri
        Relative Graph path (without version) or an absolute https://graph.microsoft.com/... URI.

    .PARAMETER Method
        HTTP method.

    .PARAMETER Body
        Request body: an object/hashtable (converted to JSON with depth 20) or a JSON string.

    .PARAMETER ApiVersion
        'v1.0' or 'beta'. Defaults to the module setting DefaultApiVersion.

    .PARAMETER All
        Follow @odata.nextLink and return every page.

    .PARAMETER Headers
        Additional request headers, for example @{ ConsistencyLevel = 'eventual' }.

    .EXAMPLE
        Invoke-ITGraphRequest -Uri 'deviceManagement/managedDevices' -All

    .EXAMPLE
        Invoke-ITGraphRequest -Uri "deviceManagement/managedDevices/$id/syncDevice" -Method POST
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = $script:ITConfig.DefaultApiVersion,

        [switch]$All,

        [hashtable]$Headers,

        # Fail at once on 429/5xx instead of retrying (e.g. Autopilot sync, which answers 429 for 10 minutes).
        [switch]$NoRetry
    )

    # --- Build the request URI -------------------------------------------
    if ($Uri -match '^https?://') {
        $requestUri = $Uri
    }
    else {
        $requestUri = '{0}/{1}/{2}' -f $script:ITConfig.GraphBaseUri.TrimEnd('/'), $ApiVersion, $Uri.TrimStart('/')
    }

    # --- Serialise body (ConvertTo-Json default depth is only 2 on 5.1) --
    $jsonBody = $null
    if ($null -ne $Body) {
        if ($Body -is [string]) { $jsonBody = $Body }
        else { $jsonBody = ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
    }

    $page = 0
    while ($requestUri) {
        $page++
        $attempt  = 0
        $response = $null

        # --- Send with retry ------------------------------------------------
        while ($true) {
            $attempt++
            Write-ITLog -Message "$Method $requestUri (page $page, attempt $attempt)"
            try {
                $sendParams = @{ Uri = $requestUri; Method = $Method }
                if ($jsonBody) { $sendParams['Body'] = $jsonBody }
                if ($Headers)  { $sendParams['Headers'] = $Headers }

                $response = Send-ITGraphRequest @sendParams
                break
            }
            catch {
                $info = Get-ITGraphErrorInfo -ErrorRecord $_
                # 501 Not Implemented / 505 are permanent answers: retrying only wastes time
                $retryable = ($info.StatusCode -eq 429) -or ($info.StatusCode -ge 500 -and $info.StatusCode -le 599 -and @(501, 505) -notcontains $info.StatusCode)

                if ($retryable -and -not $NoRetry -and $attempt -le $script:ITConfig.MaxRetry) {
                    $delay = $script:ITConfig.RetryDelaySeconds * $attempt
                    if ($info.RetryAfter) { $delay = $info.RetryAfter }
                    Write-ITLog -Level Warning -Message ("Graph returned HTTP {0}; retry {1}/{2} in {3}s." -f $info.StatusCode, $attempt, $script:ITConfig.MaxRetry, $delay)
                    Start-Sleep -Seconds $delay
                    continue
                }

                # Raw details to the log file only (diagnostics); never the Authorization header
                if ($script:ITConfig.LogPath) {
                    $raw = ''
                    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $raw = $_.ErrorDetails.Message } else { $raw = $_.Exception.Message }
                    $raw = (($raw -split "`r?`n") | Where-Object { $_ -notmatch '^\s*Authorization\s*:' }) -join ' | '
                    if ($raw.Length -gt 4000) { $raw = $raw.Substring(0, 4000) + '...' }
                    Write-ITLog -Level Error -Message "Raw error ($($_.Exception.GetType().Name)): $raw"
                }

                $text = 'Graph request failed: {0} {1}' -f $Method, $requestUri
                if ($info.StatusCode) { $text += " -> HTTP $($info.StatusCode)" }
                if ($info.Code)       { $text += " [$($info.Code)]" }
                $text += ": $($info.Message)"
                if ($info.PSObject.Properties['RequestId'] -and $info.RequestId) { $text += " (request-id: $($info.RequestId))" }

                $exception = New-Object -TypeName System.Exception -ArgumentList $text, $_.Exception
                $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList @(
                    $exception, 'IntuneToolkit.GraphRequestFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $requestUri)
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }

        # --- Emit results ---------------------------------------------------
        $requestUri = $null
        if ($null -eq $response) { break }

        # A collection response has exactly one non-OData property: 'value'.
        # (Single objects may also have a 'value' property, e.g. OMA settings, so check both.)
        $dataProps = @($response.PSObject.Properties | Where-Object { $_.Name -notlike '@odata.*' })
        $isCollection = ($dataProps.Count -eq 1 -and $dataProps[0].Name -eq 'value')

        if ($isCollection) {
            if ($null -ne $response.value) {
                foreach ($item in @($response.value)) { $item }
            }
        }
        else {
            $response
        }

        if ($response.PSObject.Properties['@odata.nextLink'] -and $response.'@odata.nextLink') {
            if ($All) {
                $requestUri = $response.'@odata.nextLink'
            }
            else {
                Write-ITLog -Message 'More results are available. Use -All to retrieve every page.'
            }
        }
    }
}
