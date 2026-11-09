function Read-ITIntuneWinPackage {
    <#
    .SYNOPSIS
        Internal: reads Detection.xml from a .intunewin file and extracts the encrypted content to a temp file.

    .DESCRIPTION
        A .intunewin (from IntuneWinAppUtil.exe) is a zip with
          IntuneWinPackage/Metadata/Detection.xml   - name, setup file, sizes, encryption info, MSI info
          IntuneWinPackage/Contents/<FileName>      - the encrypted payload that is uploaded
        Returns an object with the metadata and EncryptedFilePath (caller deletes it).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        # Entry names can use '/' or a backslash depending on the tool that built the zip
        $detectionEntry = $zip.Entries | Where-Object { $_.FullName.Replace([char]92, [char]47) -eq 'IntuneWinPackage/Metadata/Detection.xml' } | Select-Object -First 1
        if (-not $detectionEntry) { throw "'$Path' is not a valid .intunewin file (Detection.xml missing)." }

        $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $detectionEntry.Open()
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        # SelectSingleNode instead of $xml.A.B: a missing element would throw under StrictMode
        $text = { param($node, $name) $child = $null; if ($node) { $child = $node.SelectSingleNode($name) }; if ($child) { $child.InnerText } else { '' } }
        $appInfo = $xml.SelectSingleNode('ApplicationInfo')
        if (-not $appInfo) { throw "'$Path': Detection.xml has no ApplicationInfo." }
        $enc = $appInfo.SelectSingleNode('EncryptionInfo')

        $innerName = & $text $appInfo 'FileName'
        $contentEntry = $zip.Entries | Where-Object { $_.FullName.Replace([char]92, [char]47) -eq ('IntuneWinPackage/Contents/{0}' -f $innerName) } | Select-Object -First 1
        if (-not $contentEntry) { throw "'$Path': encrypted content '$innerName' missing." }

        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ('IntuneToolkit_{0}.bin' -f [guid]::NewGuid())
        $in = $contentEntry.Open()
        $out = [System.IO.File]::Create($tempFile)
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }

        $msi = $null
        $m = $appInfo.SelectSingleNode('MsiInfo')
        if ($m) {
            $msi = [pscustomobject]@{
                ProductCode      = & $text $m 'MsiProductCode'
                ProductVersion   = & $text $m 'MsiProductVersion'
                UpgradeCode      = & $text $m 'MsiUpgradeCode'
                Publisher        = & $text $m 'MsiPublisher'
                ExecutionContext = & $text $m 'MsiExecutionContext'
                RequiresReboot   = (& $text $m 'MsiRequiresReboot') -eq 'true'
            }
        }

        [pscustomobject]@{
            Name                   = & $text $appInfo 'Name'
            FileName               = $innerName
            SetupFile              = & $text $appInfo 'SetupFile'
            UnencryptedContentSize = [long](& $text $appInfo 'UnencryptedContentSize')
            EncryptedFilePath      = $tempFile
            EncryptedSize          = (Get-Item -LiteralPath $tempFile).Length
            Msi                    = $msi
            EncryptionInfo         = [ordered]@{
                encryptionKey        = & $text $enc 'EncryptionKey'
                macKey               = & $text $enc 'MacKey'
                initializationVector = & $text $enc 'InitializationVector'
                mac                  = & $text $enc 'Mac'
                profileIdentifier    = 'ProfileVersion1'
                fileDigest           = & $text $enc 'FileDigest'
                fileDigestAlgorithm  = & $text $enc 'FileDigestAlgorithm'
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}
