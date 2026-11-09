#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for the scheduled Daily / Weekly / Monthly report scripts (dot-sourced).

.DESCRIPTION
    Start-ITScheduledReport  - imports the module, creates <ReportPath>\<Name>\<yyyy-MM-dd>\, starts the
                               log (Start-ITLog) and connects (certificate when -ClientId is given, otherwise interactive).
    Save-ITScheduledReport   - writes one report as CSV and HTML and records the row count.
    Stop-ITScheduledReport   - writes Summary.html (report / rows), disconnects, closes the log and returns the summary.
#>

function Start-ITScheduledReport {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$TenantId,
        [string]$ClientId,
        [string]$CertificateThumbprint
    )

    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $manifest = Join-Path $repo 'src\IntuneToolkit\IntuneToolkit.psd1'
    if (Test-Path $manifest) { Import-Module $manifest -Force } else { Import-Module IntuneToolkit -Force }

    $outDir = Join-Path $ReportPath ('{0}\{1:yyyy-MM-dd}' -f $Name, (Get-Date))
    if ($PSCmdlet.ShouldProcess($outDir, 'Create report folder')) { $null = New-Item -ItemType Directory -Path $outDir -Force }
    # IntuneToolkit log + transcript next to the reports (<Name>.log / <Name>.transcript.log)
    Start-ITLog -Path (Join-Path $outDir ('{0}.log' -f $Name)) -RetentionDays 0

    if ($ClientId) {
        Connect-ITGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -ContextScope Process
    }
    else {
        Connect-ITGraph -ContextScope Process
    }

    [pscustomobject]@{
        Name    = $Name
        OutDir  = $outDir
        Summary = New-Object System.Collections.Generic.List[object]
    }
}

function Save-ITScheduledReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][object]$Context,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Title,
        [AllowNull()][AllowEmptyCollection()][object[]]$Data,
        [string[]]$Property
    )

    $params = @{ Title = $Title }
    if ($Property) { $params['Property'] = $Property }
    $rows = @($Data | Where-Object { $null -ne $_ })
    $null = $rows | Export-ITReport -Path (Join-Path $Context.OutDir "$Name.csv") @params
    $null = $rows | Export-ITReport -Path (Join-Path $Context.OutDir "$Name.html") @params
    $Context.Summary.Add([pscustomobject]@{ Report = $Title; Rows = $rows.Count; File = "$Name.html" })
}

function Stop-ITScheduledReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][object]$Context)

    $title = 'Intune {0} report {1:yyyy-MM-dd}' -f $Context.Name, (Get-Date)
    if ($PSCmdlet.ShouldProcess($Context.OutDir, 'Write summary')) {
        $null = $Context.Summary | Export-ITReport -Path (Join-Path $Context.OutDir 'Summary.html') -Title $title
    }
    Disconnect-ITGraph
    Stop-ITLog -Status ('{0} report(s) written to {1}' -f $Context.Summary.Count, $Context.OutDir)
    $Context.Summary
}
