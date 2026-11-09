function Set-ITConfiguration {
    <#
    .SYNOPSIS
        Changes IntuneToolkit module settings for the current session.

    .DESCRIPTION
        Sets module-wide defaults used by every IntuneToolkit function. Settings live in
        memory only and reset when the module is re-imported.

    .PARAMETER DefaultApiVersion
        Graph API version used when a function is not told otherwise: 'v1.0' or 'beta'.

    .PARAMETER MaxRetry
        Number of retries for throttled (429) or transient (5xx) Graph responses.

    .PARAMETER RetryDelaySeconds
        Delay used between retries when Graph does not return a Retry-After header.

    .PARAMETER PageSize
        Default page size ($top) for list requests (1-999).

    .PARAMETER LogPath
        Path of a log file. Every Write-ITLog entry is appended to it. Use an empty string to disable.

    .PARAMETER PassThru
        Returns the resulting configuration.

    .EXAMPLE
        Set-ITConfiguration -DefaultApiVersion beta

        Uses the Graph beta endpoint by default (many Intune features only exist there).

    .EXAMPLE
        Set-ITConfiguration -LogPath "$env:TEMP\IntuneToolkit.log" -MaxRetry 8 -PassThru

        Enables file logging, raises the retry count and shows the new settings.

    .OUTPUTS
        None, or IntuneToolkit.Configuration with -PassThru.

    .NOTES
        Graph permission: none.

    .LINK
        Get-ITConfiguration
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneToolkit.Configuration')]
    param(
        [ValidateSet('v1.0', 'beta')]
        [string]$DefaultApiVersion,

        [ValidateRange(0, 20)]
        [int]$MaxRetry,

        [ValidateRange(1, 300)]
        [int]$RetryDelaySeconds,

        [ValidateRange(1, 999)]
        [int]$PageSize,

        [AllowEmptyString()]
        [string]$LogPath,

        [switch]$PassThru
    )

    $settable = 'DefaultApiVersion', 'MaxRetry', 'RetryDelaySeconds', 'PageSize', 'LogPath'
    foreach ($name in $settable) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $value = $PSBoundParameters[$name]
            if ($name -eq 'LogPath' -and [string]::IsNullOrWhiteSpace($value)) { $value = $null }
            if ($PSCmdlet.ShouldProcess("IntuneToolkit setting '$name'", "Set to '$value'")) {
                $script:ITConfig[$name] = $value
                Write-ITLog -Message "Configuration '$name' set to '$value'."
            }
        }
    }

    if ($PassThru) { Get-ITConfiguration }
}
