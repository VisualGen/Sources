function Get-ITNuGetProviderVersion {
    <#
    .SYNOPSIS
        Internal: newest installed NuGet package provider version (needed by Install-Module), or $null.

    .DESCRIPTION
        Reads the PackageManagement provider folders (machine and user) instead of calling
        Get-PackageProvider, which is not available in every Windows PowerShell 5.1 build and can
        prompt to download the provider.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param()

    $folders = @(
        (Join-Path $env:ProgramFiles 'PackageManagement\ProviderAssemblies\nuget')
        (Join-Path $env:LOCALAPPDATA 'PackageManagement\ProviderAssemblies\nuget')
    )
    $versions = foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue)) {
            $v = $null
            if ([version]::TryParse($dir.Name, [ref]$v)) { $v }
        }
    }
    @($versions | Sort-Object -Descending | Select-Object -First 1)[0]
}
