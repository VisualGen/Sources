function Connect-ITGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for Intune management.

    .DESCRIPTION
        Wraps Connect-MgGraph (module Microsoft.Graph.Authentication) and records the session for
        IntuneToolkit. Supports:
          - Interactive sign-in (default) or device code (-UseDeviceCode) with delegated scopes
          - App-only with a certificate (-CertificateThumbprint) - recommended for scheduled jobs
          - App-only with a client secret (-ClientSecretCredential)
          - Managed identity (-Identity) for Azure Automation / Azure VMs

        Without -Scopes, a read-only Intune scope set is requested. Add write scopes only when needed.

        Interactive sign-in uses the Windows account picker (WAM) by default. WAM needs a console
        window; in embedded terminals (VS Code, Windows Terminal panes, IDE consoles) it fails with
        "A window handle must be configured". Connect-ITGraph then signs in once more through the web
        browser automatically. Use -UseBrowser to skip WAM from the start. Your MFA and Conditional
        Access policies apply in both cases. The Graph WAM setting is restored right after sign-in.

    .PARAMETER Scopes
        Delegated permissions to request. Default: read-only Intune scopes plus Group.Read.All.

    .PARAMETER TenantId
        Tenant ID or primary domain (contoso.onmicrosoft.com). Required for app-only sign-in.

    .PARAMETER UseDeviceCode
        Use the device code flow (sign in on another device / browser).

    .PARAMETER UseBrowser
        Interactive sign-in through the web browser instead of the Windows account picker (WAM).
        Alias: DisableWAM.

    .PARAMETER ClientId
        Application (client) ID of the app registration. For -Identity: client ID of a user-assigned identity.

    .PARAMETER CertificateThumbprint
        Thumbprint of a certificate in Cert:\CurrentUser\My or Cert:\LocalMachine\My for app-only sign-in.

    .PARAMETER ClientSecretCredential
        PSCredential where UserName = client ID and Password = client secret.

    .PARAMETER Identity
        Sign in with a managed identity.

    .PARAMETER ApiVersion
        Sets the module default Graph API version ('v1.0' or 'beta') for this session.

    .PARAMETER ContextScope
        'Process' keeps the token in memory only; 'CurrentUser' (default) caches it for the user.

    .PARAMETER PassThru
        Returns the resulting IntuneToolkit context.

    .EXAMPLE
        Connect-ITGraph

        Interactive sign-in with the default read-only Intune scopes.

    .EXAMPLE
        Connect-ITGraph -Scopes 'DeviceManagementManagedDevices.ReadWrite.All','DeviceManagementManagedDevices.PrivilegedOperations.All'

        Interactive sign-in with permissions to run device actions (sync, restart, wipe).

    .EXAMPLE
        Connect-ITGraph -UseBrowser

        Signs in through the web browser (e.g. from the VS Code terminal, where WAM cannot show its window).

    .EXAMPLE
        Connect-ITGraph -TenantId 'contoso.onmicrosoft.com' -ClientId $appId -CertificateThumbprint 'A1B2C3...'

        Unattended app-only sign-in, e.g. for a scheduled daily report.

    .EXAMPLE
        Connect-ITGraph -UseDeviceCode -ApiVersion beta -PassThru

        Device code sign-in, use the beta endpoint by default and show the context.

    .OUTPUTS
        None, or IntuneToolkit.Context with -PassThru.

    .NOTES
        Requires module Microsoft.Graph.Authentication 2.x.
        App-only permissions are granted as application permissions on the app registration (admin consent).

    .LINK
        https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    [OutputType('IntuneToolkit.Context')]
    param(
        [Parameter(ParameterSetName = 'Interactive')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Scopes = @(
            'DeviceManagementManagedDevices.Read.All'
            'DeviceManagementConfiguration.Read.All'
            'DeviceManagementApps.Read.All'
            'DeviceManagementServiceConfig.Read.All'
            'DeviceManagementRBAC.Read.All'
            'Group.Read.All'
        ),

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [Parameter(ParameterSetName = 'ClientSecret', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$UseDeviceCode,

        [Parameter(ParameterSetName = 'Interactive')]
        [Alias('DisableWAM')]
        [switch]$UseBrowser,

        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [Parameter(ParameterSetName = 'Identity')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string]$CertificateThumbprint,

        [Parameter(ParameterSetName = 'ClientSecret', Mandatory)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $ClientSecretCredential,

        [Parameter(ParameterSetName = 'Identity', Mandatory)]
        [switch]$Identity,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion,

        [ValidateSet('Process', 'CurrentUser')]
        [string]$ContextScope = 'CurrentUser',

        [switch]$PassThru
    )

    if (-not (Get-Command -Name 'Connect-MgGraph' -ErrorAction SilentlyContinue)) {
        $text = '{0} {1} or later is not installed or could not be loaded. Run Test-ITPrerequisite for details, or: Install-Module {0} -Scope CurrentUser' -f $script:ITGraphModule.Name, $script:ITGraphModule.MinimumVersion
        $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList @(
            (New-Object -TypeName System.InvalidOperationException -ArgumentList $text), 'IntuneToolkit.GraphModuleMissing',
            [System.Management.Automation.ErrorCategory]::NotInstalled, $script:ITGraphModule.Name)
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $connectParams = @{
        NoWelcome    = $true
        ContextScope = $ContextScope
        ErrorAction  = 'Stop'
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Interactive' {
            $connectParams['Scopes'] = $Scopes
            if ($TenantId)      { $connectParams['TenantId'] = $TenantId }
            if ($UseDeviceCode) { $connectParams['UseDeviceCode'] = $true }
        }
        'Certificate' {
            $connectParams['TenantId']              = $TenantId
            $connectParams['ClientId']              = $ClientId
            $connectParams['CertificateThumbprint'] = $CertificateThumbprint
        }
        'ClientSecret' {
            $connectParams['TenantId']               = $TenantId
            $connectParams['ClientSecretCredential'] = $ClientSecretCredential
        }
        'Identity' {
            $connectParams['Identity'] = [bool]$Identity
            if ($ClientId) { $connectParams['ClientId'] = $ClientId }
        }
    }

    # WAM (Windows account picker) applies to interactive browser sign-in only
    $browserSignIn = ($PSCmdlet.ParameterSetName -eq 'Interactive') -and -not $UseDeviceCode
    $wamPrevious = $null
    Write-ITLog -Message "Connecting to Microsoft Graph ($($PSCmdlet.ParameterSetName))."
    try {
        if ($browserSignIn -and $UseBrowser) {
            $wamPrevious = Set-ITWamLogin -Disable
            Write-ITLog -Message 'Signing in through the web browser (-UseBrowser).'
        }
        try {
            Connect-MgGraph @connectParams | Out-Null
        }
        catch {
            # WAM cannot show its window from this host (no console window handle): retry with the browser
            $noWindow = $_.Exception.Message -match 'window handle|parent-window-handles'
            if (-not ($browserSignIn -and $noWindow -and $null -eq $wamPrevious)) { throw }
            $wamPrevious = Set-ITWamLogin -Disable
            if ($null -eq $wamPrevious) { throw }
            Write-ITLog -Level Warning -Message 'Windows sign-in (WAM) cannot open its window from this terminal; signing in through the web browser instead. Use -UseBrowser to skip WAM.'
            Connect-MgGraph @connectParams | Out-Null
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    finally {
        # The Graph option is saved for the Windows user: put it back as it was
        if ($null -ne $wamPrevious) { Set-ITWamLogin -Restore $wamPrevious }
    }

    if ($ApiVersion) { $script:ITConfig.DefaultApiVersion = $ApiVersion }

    $mg = Get-MgContext
    $script:ITSession = @{
        ConnectedAt  = Get-Date
        Method       = $PSCmdlet.ParameterSetName
        ContextScope = $ContextScope
    }
    Write-ITLog -Message ("Connected to tenant {0} as {1} ({2})." -f $mg.TenantId, $(if ($mg.Account) { $mg.Account } else { $mg.AppName }), $mg.AuthType)

    if ($PassThru) { Get-ITContext }
}
