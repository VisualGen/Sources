function Export-ITScript {
    <#
    .SYNOPSIS
        Saves the content of Intune platform scripts and remediations as .ps1 files.

    .DESCRIPTION
        Platform scripts are saved as <Path>\<fileName or name>.ps1. Remediations are saved as
        <Path>\<name>\detect.ps1 and remediate.ps1. Use Export-ITPolicy for a restorable JSON
        backup; this command produces readable source files (for review or source control).
        Existing files are overwritten only with -Force.

    .PARAMETER Path
        Target folder. Created when missing.

    .PARAMETER Id
        Script or remediation ID. Binds from the pipeline (Get-ITScript, Get-ITRemediation).

    .PARAMETER PolicyType
        Script (default) or Remediation. Binds from the pipeline.

    .PARAMETER Force
        Overwrite existing files.

    .EXAMPLE
        Get-ITScript | Export-ITScript -Path .\IntuneScripts

    .EXAMPLE
        Get-ITRemediation -Name 'Fix-*' | Export-ITScript -Path .\Remediations -Force

    .OUTPUTS
        System.IO.FileInfo

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/deviceManagementScripts/{id}, /deviceManagement/deviceHealthScripts/{id}
        API version      : beta

    .LINK
        Get-ITScript
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('Script', 'Remediation')]
        [string]$PolicyType = 'Script',

        [switch]$Force
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
        if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -ItemType Directory -Force }
        $root = (Resolve-Path -LiteralPath $Path).ProviderPath
        $utf8Bom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
        $safe = { param([string]$s) $clean = ($s -replace '[\\/:*?"<>|\x00-\x1f]', '_').Trim(); if (-not $clean) { 'unnamed' } else { $clean } }
    }

    process {
        $info = Get-ITPolicyTypeInfo -PolicyType $PolicyType
        try {
            $item = Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $info.Path, $Id) -ApiVersion 'beta'
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }

        $files = @()
        if ($PolicyType -eq 'Script') {
            $fileName = $null
            if ($item.PSObject.Properties['fileName'] -and $item.fileName) { $fileName = [string]$item.fileName }
            if (-not $fileName) { $fileName = '{0}.ps1' -f $item.displayName }
            $files += @{ Path = Join-Path $root (& $safe $fileName); Content = $item.scriptContent }
        }
        else {
            $folder = Join-Path $root (& $safe ([string]$item.displayName))
            if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
            $files += @{ Path = Join-Path $folder 'detect.ps1'; Content = $item.detectionScriptContent }
            if ($item.PSObject.Properties['remediationScriptContent'] -and $item.remediationScriptContent) {
                $files += @{ Path = Join-Path $folder 'remediate.ps1'; Content = $item.remediationScriptContent }
            }
        }

        foreach ($entry in $files) {
            if ((Test-Path -LiteralPath $entry.Path) -and -not $Force) {
                Write-Error -Message "File exists (use -Force): $($entry.Path)" -Category ResourceExists -TargetObject $entry.Path
                continue
            }
            $text = ConvertFrom-ITBase64 $entry.Content
            if ($null -eq $text) { $text = '' }
            [System.IO.File]::WriteAllText($entry.Path, $text, $utf8Bom)
            Get-Item -LiteralPath $entry.Path
        }
    }
}
