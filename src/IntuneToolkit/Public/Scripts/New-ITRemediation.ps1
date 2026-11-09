function New-ITRemediation {
    <#
    .SYNOPSIS
        Creates an Intune remediation from a detection script and an optional remediation script.

    .DESCRIPTION
        Detection script: exit 1 = issue found (the remediation script runs), exit 0 = OK.
        Without -RemediationScriptPath the package is detection-only (a reporting script).
        The remediation is NOT assigned; use Add-ITPolicyAssignment -PolicyType Remediation
        (daily schedule by default) or Invoke-ITRemediationOnDemand for single devices.

    .PARAMETER DisplayName
        Name in Intune.

    .PARAMETER DetectionScriptPath
        Detection .ps1 file.

    .PARAMETER RemediationScriptPath
        Remediation .ps1 file (optional).

    .PARAMETER Description
        Description.

    .PARAMETER Publisher
        Publisher shown in Intune. Default: the signed-in account.

    .PARAMETER RunAsAccount
        system (default) or user.

    .PARAMETER RunAs32Bit
        Run in 32-bit PowerShell on 64-bit Windows.

    .PARAMETER EnforceSignatureCheck
        Only run signed scripts.

    .EXAMPLE
        New-ITRemediation -DisplayName 'Fix - Clear Teams cache' -DetectionScriptPath .\detect.ps1 -RemediationScriptPath .\remediate.ps1 -WhatIf

    .EXAMPLE
        New-ITRemediation -DisplayName 'Report - Local admins' -DetectionScriptPath .\Get-LocalAdmins.ps1 |
            Add-ITPolicyAssignment -AllDevices

        Detection-only reporting script on all devices.

    .OUTPUTS
        IntuneToolkit.Remediation

    .NOTES
        Graph permission : DeviceManagementConfiguration.ReadWrite.All
        Graph endpoint   : POST /deviceManagement/deviceHealthScripts
        API version      : beta

    .LINK
        Get-ITRemediation
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.Remediation')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$DetectionScriptPath,

        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$RemediationScriptPath,

        [string]$Description = '',

        [ValidateNotNullOrEmpty()]
        [string]$Publisher,

        [ValidateSet('system', 'user')]
        [string]$RunAsAccount = 'system',

        [switch]$RunAs32Bit,

        [switch]$EnforceSignatureCheck
    )

    $info = Get-ITPolicyTypeInfo -PolicyType Remediation
    Assert-ITGraphConnection -RequiredScope $info.WriteScope

    $pub = $Publisher
    if (-not $pub) {
        $context = Get-MgContext
        if ($context -and $context.Account) { $pub = [string]$context.Account } else { $pub = 'IntuneToolkit' }
    }
    $encode = { param($p) [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $p).ProviderPath)) }

    $body = [ordered]@{
        '@odata.type'            = '#microsoft.graph.deviceHealthScript'
        displayName              = $DisplayName
        description              = $Description
        publisher                = $pub
        detectionScriptContent   = & $encode $DetectionScriptPath
        remediationScriptContent = ''
        runAsAccount             = $RunAsAccount
        runAs32Bit               = [bool]$RunAs32Bit
        enforceSignatureCheck    = [bool]$EnforceSignatureCheck
    }
    if ($RemediationScriptPath) { $body['remediationScriptContent'] = & $encode $RemediationScriptPath }

    if ($PSCmdlet.ShouldProcess("Remediation '$DisplayName'", 'Create')) {
        $created = Invoke-ITGraphRequest -Uri $info.Path -Method POST -Body $body -ApiVersion 'beta'
        Write-ITLog -Message "Remediation '$DisplayName' created ($($created.id))."
        Get-ITIntuneObject -TypeInfo $info -Id $created.id
    }
}
