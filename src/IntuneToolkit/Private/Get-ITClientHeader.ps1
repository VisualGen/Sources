function Get-ITClientHeader {
    <#
    .SYNOPSIS
        Internal: client identification headers required by the BitLocker and LAPS Graph APIs.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $version = '0.0.0'
    if ($MyInvocation.MyCommand.Module) { $version = [string]$MyInvocation.MyCommand.Module.Version }

    @{
        'ocp-client-name'    = 'IntuneToolkit'
        'ocp-client-version' = $version
    }
}
