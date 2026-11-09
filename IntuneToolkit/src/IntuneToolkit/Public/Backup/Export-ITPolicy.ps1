function Export-ITPolicy {
    <#
    .SYNOPSIS
        Backs up Intune policies, profiles, scripts and update profiles to JSON files.

    .DESCRIPTION
        Writes one JSON file per object to <Path>\<PolicyType>\<Name>__<Id>.json with the full
        object (beta), its assignments and export metadata (tenant, source ID, date). The files
        can be restored or copied to another tenant with Import-ITPolicy and checked for drift
        with Compare-ITPolicy.
        Without -Id every object of the selected PolicyType(s) is exported; objects from the
        Get-IT* commands can also be piped in.
        Secrets are NOT exported by Graph (Wi-Fi keys, encrypted OMA-URI values, certificates).

    .PARAMETER Path
        Backup folder. Created when missing.

    .PARAMETER PolicyType
        Type(s) to export. Default: all supported types. Update rings are part of DeviceConfiguration.

    .PARAMETER Id
        Export only this object (requires a single PolicyType). Binds from the pipeline.

    .PARAMETER Name
        Only objects whose name matches (wildcards allowed).

    .EXAMPLE
        Export-ITPolicy -Path "D:\IntuneBackup\$(Get-Date -Format yyyy-MM-dd)"

        Monthly full configuration backup.

    .EXAMPLE
        Export-ITPolicy -Path .\Backup -PolicyType SettingsCatalog, Compliance -Name 'Win - *'

    .EXAMPLE
        Get-ITCompliancePolicy -Name 'Win - Baseline' | Export-ITPolicy -Path .\Backup

    .OUTPUTS
        IntuneToolkit.PolicyExportResult

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /{collection}/{id} (+ /settings, /assignments)
        API version      : beta

    .LINK
        Import-ITPolicy
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.PolicyExportResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('Compliance', 'DeviceConfiguration', 'SettingsCatalog', 'Script', 'Remediation',
            'UpdateRing', 'FeatureUpdate', 'DriverUpdate')]
        [string[]]$PolicyType = @('Compliance', 'DeviceConfiguration', 'SettingsCatalog', 'Script', 'Remediation', 'FeatureUpdate', 'DriverUpdate'),

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
        if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -ItemType Directory -Force }
        $root = (Resolve-Path -LiteralPath $Path).ProviderPath
    }

    process {
        $targets = New-Object -TypeName System.Collections.Generic.List[object]
        if ($Id) {
            if (@($PolicyType).Count -ne 1) { throw '-Id requires exactly one -PolicyType.' }
            $targets.Add(@{ Type = $PolicyType[0]; Id = $Id })
        }
        else {
            foreach ($type in $PolicyType) {
                $info = Get-ITPolicyTypeInfo -PolicyType $type
                $listParams = @{ TypeInfo = $info }
                if ($Name) { $listParams['Name'] = $Name }
                foreach ($item in @(Get-ITIntuneObject @listParams)) {
                    # Built-in Microsoft remediations cannot be re-imported: skip them
                    if ($type -eq 'Remediation' -and $item.PSObject.Properties['isGlobalScript'] -and $item.isGlobalScript) { continue }
                    $targets.Add(@{ Type = $type; Id = $item.id })
                }
            }
        }

        foreach ($target in $targets) {
            $info = Get-ITPolicyTypeInfo -PolicyType $target.Type
            try {
                $doc = Get-ITPolicyExport -TypeInfo $info -Id $target.Id
                $displayName = [string]$doc.IntuneToolkit.DisplayName
                $safeName = ($displayName -replace '[\\/:*?"<>|\x00-\x1f]', '_').Trim()
                if ($safeName.Length -gt 80) { $safeName = $safeName.Substring(0, 80) }
                if (-not $safeName) { $safeName = 'unnamed' }

                $folder = Join-Path $root $target.Type
                if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
                $file = Join-Path $folder ('{0}__{1}.json' -f $safeName, $target.Id)

                $json = ConvertTo-Json -InputObject $doc -Depth 64
                [System.IO.File]::WriteAllText($file, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
                Write-ITLog -Message ('Exported {0} {1} to {2}' -f $target.Type, $target.Id, $file)

                [pscustomobject]@{
                    PSTypeName  = 'IntuneToolkit.PolicyExportResult'
                    PolicyType  = $target.Type
                    DisplayName = $displayName
                    Id          = $target.Id
                    Assignments = @($doc.Assignments).Count
                    Path        = $file
                }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
