function New-ITWin32App {
    <#
    .SYNOPSIS
        Creates a Win32 app in Intune from a .intunewin package and uploads its content.

    .DESCRIPTION
        Full upload flow:
          1. read Detection.xml from the .intunewin (name, setup file, encryption info, MSI info)
          2. create the win32LobApp
          3. create a content version and a content file, wait for the Azure Storage upload URI
          4. upload the encrypted payload in 6 MB blocks and commit the block list
          5. commit the file with the encryption info, wait for 'commitFileSuccess'
          6. set the committed content version on the app
        Every wait has a hard limit. When a step fails the half-created app is deleted
        (use -KeepOnFailure to keep it for troubleshooting).

        Detection: -DetectionScriptPath (PowerShell script), -DetectionRule (raw Graph rule
        objects for file / registry / product code), or - for MSI packages - automatically the
        MSI product code. Install/uninstall commands default to msiexec for MSI packages.
        The app is NOT assigned; use Add-ITAppAssignment afterwards.

    .PARAMETER Path
        The .intunewin file (created with IntuneWinAppUtil.exe).

    .PARAMETER DisplayName
        App name in Intune. Default: the name in the package.

    .PARAMETER Description
        Description (Graph requires one). Default: the display name.

    .PARAMETER Publisher
        Publisher. Default: the MSI publisher, otherwise required.

    .PARAMETER AppVersion
        Version shown in Intune (displayVersion).

    .PARAMETER InstallCommandLine
        Install command. Default for MSI: msiexec /i "<setup>" /qn.

    .PARAMETER UninstallCommandLine
        Uninstall command. Default for MSI: msiexec /x "<product code>" /qn.

    .PARAMETER RunAsAccount
        system (default) or user.

    .PARAMETER RestartBehavior
        basedOnReturnCode (default), allow, suppress or force.

    .PARAMETER DetectionScriptPath
        PowerShell detection script (exit 0 + STDOUT output = detected).

    .PARAMETER DetectionRule
        Graph detection rule object(s) (hashtables), e.g. a win32LobAppFileSystemRule or
        win32LobAppRegistryRule. 'ruleType = detection' is added when missing.

    .PARAMETER Architecture
        Applicable architectures. Default: x64 and x86.

    .PARAMETER MinimumWindowsRelease
        Minimum Windows release, e.g. '1607', '21H2', '22H2'. Default: '1607'.

    .PARAMETER KeepOnFailure
        Do not delete the app when the upload fails.

    .EXAMPLE
        New-ITWin32App -Path .\7zip.intunewin -Publisher 'Igor Pavlov' -AppVersion '24.08'

        MSI package: install, uninstall and detection are taken from the MSI information.

    .EXAMPLE
        New-ITWin32App -Path .\Tool.intunewin -DisplayName 'Contoso Tool' -Publisher 'Contoso' `
            -InstallCommandLine 'install.cmd' -UninstallCommandLine 'uninstall.cmd' -DetectionScriptPath .\Detect-Tool.ps1

    .EXAMPLE
        $rule = @{ '@odata.type' = '#microsoft.graph.win32LobAppFileSystemRule'; path = 'C:\Program Files\Contoso'; fileOrFolderName = 'tool.exe'
                   check32BitOn64System = $false; operationType = 'exists'; operator = 'notConfigured'; comparisonValue = $null }
        New-ITWin32App -Path .\Tool.intunewin -Publisher 'Contoso' -InstallCommandLine 'setup.exe /S' -UninstallCommandLine 'uninstall.exe /S' -DetectionRule $rule |
            Add-ITAppAssignment -Intent required -GroupId $pilotGroup

    .OUTPUTS
        IntuneToolkit.App

    .NOTES
        Graph permission : DeviceManagementApps.ReadWrite.All
        Graph endpoint   : POST /deviceAppManagement/mobileApps, .../contentVersions, .../files, .../commit
        API version      : beta
        Upload           : Azure Storage SAS URI (HTTPS, outside Graph)

    .LINK
        https://learn.microsoft.com/mem/intune/apps/apps-win32-app-management
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.App')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [ValidateNotNullOrEmpty()]
        [string]$Publisher,

        [ValidateNotNullOrEmpty()]
        [string]$AppVersion,

        [ValidateNotNullOrEmpty()]
        [string]$InstallCommandLine,

        [ValidateNotNullOrEmpty()]
        [string]$UninstallCommandLine,

        [ValidateSet('system', 'user')]
        [string]$RunAsAccount = 'system',

        [ValidateSet('basedOnReturnCode', 'allow', 'suppress', 'force')]
        [string]$RestartBehavior = 'basedOnReturnCode',

        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$DetectionScriptPath,

        [hashtable[]]$DetectionRule,

        [ValidateSet('x86', 'x64', 'arm64')]
        [string[]]$Architecture = @('x64', 'x86'),

        [ValidateNotNullOrEmpty()]
        [string]$MinimumWindowsRelease = '1607',

        [switch]$KeepOnFailure
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementApps.ReadWrite.All'

    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $package = Read-ITIntuneWinPackage -Path $fullPath
    $appId = $null
    try {
        $msi = $package.Msi

        # ---- Defaults from the package ---------------------------------------------------
        $name = $DisplayName
        if (-not $name) { $name = $package.Name }
        $desc = $Description
        if (-not $desc) { $desc = $name }
        $pub = $Publisher
        if (-not $pub -and $msi -and $msi.Publisher) { $pub = $msi.Publisher }
        if (-not $pub) { throw '-Publisher is required (the package has no MSI publisher).' }

        $installCmd = $InstallCommandLine
        $uninstallCmd = $UninstallCommandLine
        if ($msi) {
            if (-not $installCmd) { $installCmd = 'msiexec /i "{0}" /qn' -f $package.SetupFile }
            if (-not $uninstallCmd) { $uninstallCmd = 'msiexec /x "{0}" /qn' -f $msi.ProductCode }
        }
        if (-not $installCmd -or -not $uninstallCmd) { throw '-InstallCommandLine and -UninstallCommandLine are required for non-MSI packages.' }

        # ---- Detection rules -------------------------------------------------------------
        $rules = New-Object -TypeName System.Collections.Generic.List[object]
        foreach ($rule in @($DetectionRule | Where-Object { $_ })) {
            $copy = @{}
            foreach ($key in $rule.Keys) { $copy[$key] = $rule[$key] }
            if (-not $copy.ContainsKey('ruleType')) { $copy['ruleType'] = 'detection' }
            $rules.Add($copy)
        }
        if ($DetectionScriptPath) {
            $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $DetectionScriptPath).ProviderPath)
            $rules.Add(@{
                    '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptRule'
                    ruleType              = 'detection'
                    enforceSignatureCheck = $false
                    runAs32Bit            = $false
                    scriptContent         = [Convert]::ToBase64String($bytes)
                    operationType         = 'notConfigured'
                    operator              = 'notConfigured'
                    comparisonValue       = $null
                })
        }
        if (-not $rules.Count -and $msi -and $msi.ProductCode) {
            $rules.Add(@{
                    '@odata.type'          = '#microsoft.graph.win32LobAppProductCodeRule'
                    ruleType               = 'detection'
                    productCode            = $msi.ProductCode
                    productVersionOperator = 'notConfigured'
                    productVersion         = $null
                })
        }
        if (-not $rules.Count) { throw 'A detection rule is required: use -DetectionScriptPath or -DetectionRule.' }

        $body = [ordered]@{
            '@odata.type'                  = '#microsoft.graph.win32LobApp'
            displayName                    = $name
            description                    = $desc
            publisher                      = $pub
            fileName                       = [System.IO.Path]::GetFileName($fullPath)
            setupFilePath                  = $package.SetupFile
            installCommandLine             = $installCmd
            uninstallCommandLine           = $uninstallCmd
            applicableArchitectures        = ($Architecture -join ',')
            minimumSupportedWindowsRelease = $MinimumWindowsRelease
            installExperience              = @{ runAsAccount = $RunAsAccount; deviceRestartBehavior = $RestartBehavior }
            rules                          = $rules.ToArray()
            returnCodes                    = @(
                @{ returnCode = 0; type = 'success' }
                @{ returnCode = 1707; type = 'success' }
                @{ returnCode = 3010; type = 'softReboot' }
                @{ returnCode = 1641; type = 'hardReboot' }
                @{ returnCode = 1618; type = 'retry' }
            )
        }
        if ($AppVersion) { $body['displayVersion'] = $AppVersion }
        if ($msi) {
            $body['msiInformation'] = @{
                productCode    = $msi.ProductCode
                productVersion = $msi.ProductVersion
                upgradeCode    = $msi.UpgradeCode
                requiresReboot = $msi.RequiresReboot
                packageType    = $(if ($msi.ExecutionContext -eq 'User') { 'perUser' } elseif ($msi.ExecutionContext -eq 'Any') { 'dualPurpose' } else { 'perMachine' })
                productName    = $name
                publisher      = $pub
            }
        }

        if (-not $PSCmdlet.ShouldProcess("Win32 app '$name' ($([math]::Round($package.EncryptedSize / 1MB, 1)) MB)", 'Create and upload')) { return }

        # ---- 1. App ------------------------------------------------------------------------
        $app = Invoke-ITGraphRequest -Uri 'deviceAppManagement/mobileApps' -Method POST -Body $body -ApiVersion 'beta'
        $appId = $app.id
        Write-ITLog -Message "Win32 app '$name' created ($appId)."
        $lobPath = 'deviceAppManagement/mobileApps/{0}/microsoft.graph.win32LobApp' -f $appId

        # ---- 2. Content version + file -------------------------------------------------
        $version = Invoke-ITGraphRequest -Uri ('{0}/contentVersions' -f $lobPath) -Method POST -Body @{} -ApiVersion 'beta'
        $filesPath = '{0}/contentVersions/{1}/files' -f $lobPath, $version.id
        $fileBody = @{
            '@odata.type' = '#microsoft.graph.mobileAppContentFile'
            name          = $package.FileName
            size          = $package.UnencryptedContentSize
            sizeEncrypted = $package.EncryptedSize
            manifest      = $null
            isDependency  = $false
        }
        $file = Invoke-ITGraphRequest -Uri $filesPath -Method POST -Body $fileBody -ApiVersion 'beta'
        $filePath = '{0}/{1}' -f $filesPath, $file.id

        $file = Wait-ITContentFileState -Uri $filePath -SuccessState 'azureStorageUriRequestSuccess' -FailureState 'azureStorageUriRequestFailed'

        # ---- 3. Upload in blocks --------------------------------------------------------
        $sasUri = [string]$file.azureStorageUri
        $chunkSize = 6MB
        $blockIds = New-Object -TypeName System.Collections.Generic.List[string]
        $stream = [System.IO.File]::OpenRead($package.EncryptedFilePath)
        try {
            $buffer = New-Object -TypeName byte[] -ArgumentList $chunkSize
            $index = 0
            $maxBlocks = 50000   # Azure block blob limit
            while ($index -lt $maxBlocks) {
                $read = $stream.Read($buffer, 0, $chunkSize)
                if ($read -le 0) { break }
                $chunk = $buffer
                if ($read -lt $chunkSize) { $chunk = New-Object -TypeName byte[] -ArgumentList $read; [Array]::Copy($buffer, $chunk, $read) }
                $blockId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(('block-{0:D6}' -f $index)))
                Send-ITBlobRequest -Uri ('{0}&comp=block&blockid={1}' -f $sasUri, [uri]::EscapeDataString($blockId)) -Body $chunk
                $blockIds.Add($blockId)
                $index++
                Write-Progress -Activity "Uploading $name" -Status ('{0:N0} MB' -f ($stream.Position / 1MB)) -PercentComplete ([math]::Min(100, 100 * $stream.Position / [math]::Max(1, $stream.Length)))
            }
        }
        finally {
            $stream.Dispose()
            Write-Progress -Activity "Uploading $name" -Completed
        }
        $blockList = '<?xml version="1.0" encoding="utf-8"?><BlockList>{0}</BlockList>' -f (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '')
        Send-ITBlobRequest -Uri ('{0}&comp=blocklist' -f $sasUri) -Body $blockList -ContentType 'application/xml'

        # ---- 4. Commit -------------------------------------------------------------------
        $null = Invoke-ITGraphRequest -Uri ('{0}/commit' -f $filePath) -Method POST -Body @{ fileEncryptionInfo = $package.EncryptionInfo } -ApiVersion 'beta'
        $null = Wait-ITContentFileState -Uri $filePath -SuccessState 'commitFileSuccess' -FailureState 'commitFileFailed'

        $null = Invoke-ITGraphRequest -Uri ('deviceAppManagement/mobileApps/{0}' -f $appId) -Method PATCH -ApiVersion 'beta' `
            -Body @{ '@odata.type' = '#microsoft.graph.win32LobApp'; committedContentVersion = $version.id }
        Write-ITLog -Message "Win32 app '$name' ($appId): content committed (version $($version.id))."

        Get-ITApp -Id $appId
    }
    catch {
        $err = $_
        if ($appId -and -not $KeepOnFailure) {
            try {
                $null = Invoke-ITGraphRequest -Uri ('deviceAppManagement/mobileApps/{0}' -f $appId) -Method DELETE -ApiVersion 'beta'
                Write-Warning -Message "Upload failed: the incomplete app $appId was deleted."
            }
            catch {
                Write-Warning -Message "Upload failed and the incomplete app $appId could not be deleted: $($_.Exception.Message)"
            }
        }
        elseif ($appId) {
            Write-Warning -Message "Upload failed: the incomplete app $appId was kept (-KeepOnFailure)."
        }
        $PSCmdlet.ThrowTerminatingError($err)
    }
    finally {
        if ($package.EncryptedFilePath -and (Test-Path -LiteralPath $package.EncryptedFilePath)) {
            Remove-Item -LiteralPath $package.EncryptedFilePath -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        }
    }
}
