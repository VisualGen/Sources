#Requires -Version 5.1
<#
    IntuneToolkit module loader.
    - Enforces TLS 1.2 (Windows PowerShell 5.1 may default to TLS 1.0).
    - Initialises module-scoped state.
    - Dot-sources Private\*.ps1 and Public\**\*.ps1 and exports only the Public functions.
#>

Set-StrictMode -Version 2.0

# TLS 1.2 for Graph / login endpoints (add, do not replace, existing protocols)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Module-scoped state
# ---------------------------------------------------------------------------
$script:ITConfig = @{
    DefaultApiVersion = 'v1.0'   # 'v1.0' or 'beta'
    GraphBaseUri      = 'https://graph.microsoft.com'
    MaxRetry          = 5        # retries on 429 / 5xx
    RetryDelaySeconds = 5        # fallback delay when no Retry-After header is returned
    PageSize          = 100      # default $top used by list functions
    LogPath           = $null    # optional file log, set with Set-ITConfiguration -LogPath
}

$script:ITSession = $null       # populated by Connect-ITGraph
$script:ITLogSession = $null    # populated by Start-ITLog

# Graph SDK dependency (checked by Test-ITPrerequisite, loaded below)
$script:ITGraphModule = @{ Name = 'Microsoft.Graph.Authentication'; MinimumVersion = [version]'2.0.0' }

# ---------------------------------------------------------------------------
# Load functions
# ---------------------------------------------------------------------------
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "IntuneToolkit: failed to load '$($file.FullName)': $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Graph SDK: load it if available; otherwise warn instead of failing the import
# ---------------------------------------------------------------------------
$loadedGraph = Get-Module -Name $script:ITGraphModule.Name
if (-not $loadedGraph -or $loadedGraph.Version -lt $script:ITGraphModule.MinimumVersion) {
    try {
        Import-Module -Name $script:ITGraphModule.Name -MinimumVersion $script:ITGraphModule.MinimumVersion -Global -ErrorAction Stop
    }
    catch {
        Write-Warning ("IntuneToolkit: {0} {1} or later could not be loaded ({2}). Run Test-ITPrerequisite to see what is missing." -f
            $script:ITGraphModule.Name, $script:ITGraphModule.MinimumVersion, $_.Exception.Message)
    }
}

Export-ModuleMember -Function $public.BaseName
