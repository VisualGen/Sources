function Get-ITPlatform {
    <#
    .SYNOPSIS
        Internal: derives a friendly platform name (Windows, macOS, iOS, Android, ...) from an Intune object.

    .DESCRIPTION
        Uses the settings catalog 'platforms' property when present, otherwise the @odata.type
        (windows10CompliancePolicy -> Windows, iosGeneralDeviceConfiguration -> iOS, ...).
        Returns 'Any' when nothing matches.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $text = ''
    if ($InputObject.PSObject.Properties['platforms'] -and $InputObject.platforms) {
        $text = [string]$InputObject.platforms
    }
    elseif ($InputObject.PSObject.Properties['@odata.type']) {
        $text = [string]$InputObject.'@odata.type'
    }

    # Order matters: 'windowsPhone' before 'windows', 'macOS' before 'ios' ('macOSIos' does not exist,
    # but 'iosVppApp' does), androidForWork/androidDeviceOwner are all Android.
    switch -Regex ($text) {
        'windowsPhone|windows81|windows8'  { return 'Windows8' }
        'windows|win32|winGet|microsoftStore|officeSuite|edge' { return 'Windows' }
        'macOS'                            { return 'macOS' }
        'ios|ipad'                         { return 'iOS' }
        'android|aosp'                     { return 'Android' }
        'linux'                            { return 'Linux' }
        'webApp'                           { return 'Web' }
    }
    'Any'
}
