function Assert-ITGraphConnection {
    <#
    .SYNOPSIS
        Internal: throws a clear terminating error if there is no Graph connection or a required scope is missing.

    .DESCRIPTION
        Public functions call this first, e.g.:
            Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All'
        A scope is satisfied when the context holds it or a broader variant
        (*.ReadWrite.All satisfies *.Read.All).
    #>
    [CmdletBinding()]
    param(
        [string[]]$RequiredScope
    )

    $result = Test-ITGraphConnection -RequiredScope $RequiredScope -Detailed
    if ($result.Connected -and $result.MissingScopes.Count -eq 0) { return }

    if (-not $result.Connected) {
        $text = 'Not connected to Microsoft Graph. Run Connect-ITGraph first.'
        $id   = 'IntuneToolkit.NotConnected'
    }
    else {
        $text = 'The current Graph session is missing permission(s): {0}. Reconnect with: Connect-ITGraph -Scopes {0}' -f ($result.MissingScopes -join ', ')
        $id   = 'IntuneToolkit.MissingScope'
    }

    $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList @(
        (New-Object -TypeName System.InvalidOperationException -ArgumentList $text),
        $id, [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
    $PSCmdlet.ThrowTerminatingError($record)
}
