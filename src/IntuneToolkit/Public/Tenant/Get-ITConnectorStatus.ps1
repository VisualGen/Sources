function Get-ITConnectorStatus {
    <#
    .SYNOPSIS
        Gets the health of the Intune connectors (Intune Connector for AD, certificate/NDES, Exchange, MTD, partners).

    .DESCRIPTION
        Returns one row per connector: Type, Name, State, LastSeen, HoursSinceLastSeen and
        Status: OK, Warning (not seen for more than -WarningHours) or Error (state reports a
        problem). Connector types that are not used or not licensed in the tenant are skipped.
          Type           Source
          ADConnector    Intune Connector for Active Directory (hybrid join)
          NdesConnector  Certificate connector (NDES / SCEP / PKCS)
          Exchange       Exchange on-premises connector
          MobileThreat   Mobile Threat Defense connectors (Defender for Endpoint, ...)
          Partner        Device management partners (Jamf, ...)

    .PARAMETER WarningHours
        Hours without a heartbeat that count as Warning. Default: 24.

    .PARAMETER Type
        Only these connector types.

    .EXAMPLE
        Get-ITConnectorStatus

    .EXAMPLE
        Get-ITConnectorStatus | Where-Object Status -ne 'OK'

    .OUTPUTS
        IntuneToolkit.ConnectorStatus

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All, DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/domainJoinConnectors, /ndesConnectors, /exchangeConnectors,
                               /mobileThreatDefenseConnectors, /deviceManagementPartners
        API version      : beta

    .LINK
        Get-ITTenantCertificateStatus
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.ConnectorStatus')]
    param(
        [ValidateRange(1, 8760)]
        [int]$WarningHours = 24,

        [ValidateSet('ADConnector', 'NdesConnector', 'Exchange', 'MobileThreat', 'Partner')]
        [string[]]$Type = @('ADConnector', 'NdesConnector', 'Exchange', 'MobileThreat', 'Partner')
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'
    $get = { param($o, $n) if ($o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    $now = Get-Date

    # Type -> endpoint, name property, state property, last-seen property, states that mean OK
    $sources = [ordered]@{
        ADConnector   = @{ Path = 'deviceManagement/domainJoinConnectors'; NameProp = 'displayName'; StateProp = 'state'; SeenProp = 'lastConnectionDateTime'; OkStates = @('active') }
        NdesConnector = @{ Path = 'deviceManagement/ndesConnectors'; NameProp = 'displayName'; StateProp = 'state'; SeenProp = 'lastConnectionDateTime'; OkStates = @('active') }
        Exchange      = @{ Path = 'deviceManagement/exchangeConnectors'; NameProp = 'serverName'; StateProp = 'status'; SeenProp = 'lastSyncDateTime'; OkStates = @('healthy') }
        MobileThreat  = @{ Path = 'deviceManagement/mobileThreatDefenseConnectors'; NameProp = 'id'; StateProp = 'partnerState'; SeenProp = 'lastHeartbeatDateTime'; OkStates = @('available', 'enabled') }
        Partner       = @{ Path = 'deviceManagement/deviceManagementPartners'; NameProp = 'displayName'; StateProp = 'partnerState'; SeenProp = 'lastHeartbeatDateTime'; OkStates = @('enabled') }
    }

    foreach ($key in $sources.Keys) {
        if ($Type -notcontains $key) { continue }
        $src = $sources[$key]
        try {
            $items = @(Invoke-ITGraphRequest -Uri $src.Path -ApiVersion 'beta' -All | Where-Object { $_ })
        }
        catch {
            # 501 NotSupported: e.g. exchangeConnectors in tenants without the on-premises Exchange connector
            if ($_.Exception.Message -notmatch 'HTTP 40[034]|HTTP 501|NotFound|NotSupported|Forbidden|BadRequest') { Write-Error -ErrorRecord $_ }
            else { Write-Verbose -Message "$key not available: $($_.Exception.Message)" }
            continue
        }

        foreach ($item in $items) {
            $state = [string](& $get $item $src.StateProp)
            $seenRaw = & $get $item $src.SeenProp
            $hours = $null
            $seen = [datetime]::MinValue
            if ($seenRaw -and [datetime]::TryParse([string]$seenRaw, [ref]$seen) -and $seen.Year -gt 1601) {
                $hours = [math]::Round(($now - $seen).TotalHours, 1)
            }

            $status = 'OK'
            if ($state -and $src.OkStates -notcontains $state) { $status = 'Error' }
            elseif ($null -eq $hours -or $hours -gt $WarningHours) { $status = 'Warning' }

            [pscustomobject]@{
                PSTypeName         = 'IntuneToolkit.ConnectorStatus'
                Type               = $key
                Name               = & $get $item $src.NameProp
                State              = $state
                LastSeen           = $seenRaw
                HoursSinceLastSeen = $hours
                Status             = $status
                Version            = & $get $item 'connectorVersion'
                Id                 = & $get $item 'id'
            }
        }
    }
}
