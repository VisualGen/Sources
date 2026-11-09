function New-ITScript {
    <#
    .SYNOPSIS
        Uploads a PowerShell script as an Intune platform script (Devices > Scripts).

    .DESCRIPTION
        Creates a deviceManagementScript from a .ps1 file. The script is NOT assigned; use
        Add-ITPolicyAssignment -PolicyType Script afterwards (or pipe the result).
        Intune runs a platform script once per device/user (again only when the content changes).
        For repeated runs use a remediation (New-ITRemediation).

    .PARAMETER Path
        The .ps1 file.

    .PARAMETER DisplayName
        Name in Intune. Default: the file name without extension.

    .PARAMETER Description
        Description.

    .PARAMETER RunAsAccount
        system (default) or user (runs in the signed-in user's context).

    .PARAMETER RunAs32Bit
        Run in 32-bit PowerShell on 64-bit Windows.

    .PARAMETER EnforceSignatureCheck
        Only run when the script is signed by a trusted publisher.

    .EXAMPLE
        New-ITScript -Path .\Set-TimeZone.ps1 -WhatIf

    .EXAMPLE
        New-ITScript -Path .\Map-Drives.ps1 -RunAsAccount user | Add-ITPolicyAssignment -GroupId $usersGroup

    .OUTPUTS
        IntuneToolkit.Script

    .NOTES
        Graph permission : DeviceManagementConfiguration.ReadWrite.All
        Graph endpoint   : POST /deviceManagement/deviceManagementScripts
        API version      : beta

    .LINK
        Get-ITScript
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.Script')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [string]$Description = '',

        [ValidateSet('system', 'user')]
        [string]$RunAsAccount = 'system',

        [switch]$RunAs32Bit,

        [switch]$EnforceSignatureCheck
    )

    $info = Get-ITPolicyTypeInfo -PolicyType Script
    Assert-ITGraphConnection -RequiredScope $info.WriteScope

    $file = Get-Item -LiteralPath $Path
    $name = $DisplayName
    if (-not $name) { $name = $file.BaseName }

    $body = [ordered]@{
        '@odata.type'         = '#microsoft.graph.deviceManagementScript'
        displayName           = $name
        description           = $Description
        fileName              = $file.Name
        scriptContent         = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.FullName))
        runAsAccount          = $RunAsAccount
        runAs32Bit            = [bool]$RunAs32Bit
        enforceSignatureCheck = [bool]$EnforceSignatureCheck
    }

    if ($PSCmdlet.ShouldProcess("Script '$name' ($($file.Name))", 'Create')) {
        $created = Invoke-ITGraphRequest -Uri $info.Path -Method POST -Body $body -ApiVersion 'beta'
        Write-ITLog -Message "Script '$name' created ($($created.id))."
        Get-ITIntuneObject -TypeInfo $info -Id $created.id
    }
}
