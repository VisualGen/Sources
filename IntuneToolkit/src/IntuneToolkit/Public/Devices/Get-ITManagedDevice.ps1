function Get-ITManagedDevice {
    <#
    .SYNOPSIS
        Gets Intune managed devices.

    .DESCRIPTION
        Returns managed devices from Intune, either by ID or by a combination of filters that are
        evaluated by Graph (server side): name, user, operating system, compliance state,
        ownership and last check-in date. All pages are returned unless -Top is used.

        -Name supports an exact name ('PC-001'), a prefix ('PC-*', evaluated by Graph) or any other
        wildcard ('*laptop*', evaluated locally after download - slower on large tenants).

    .PARAMETER Id
        One or more Intune managed device IDs.

    .PARAMETER Name
        Device name. Exact, 'Prefix*' or any wildcard pattern.

    .PARAMETER UserPrincipalName
        Primary user UPN, e.g. 'jane@contoso.com'.

    .PARAMETER OperatingSystem
        Windows, iOS, iPadOS, macOS, Android or Linux.

    .PARAMETER ComplianceState
        compliant, noncompliant, conflict, error, unknown, inGracePeriod or configManager.

    .PARAMETER OwnerType
        company or personal.

    .PARAMETER LastSyncBefore
        Only devices whose last check-in is older than this date.

    .PARAMETER Filter
        Additional raw OData filter, combined with the other filters using 'and'.
        Example: "manufacturer eq 'Dell Inc.'"

    .PARAMETER Property
        Properties to return ($select). Fewer properties = faster on large tenants.

    .PARAMETER Top
        Return only the first N devices (no paging).

    .PARAMETER ApiVersion
        Graph API version ('v1.0' or 'beta'). Default: module setting. beta returns more properties.

    .EXAMPLE
        Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant

        All non-compliant Windows devices.

    .EXAMPLE
        Get-ITManagedDevice -Name 'NL-LT-*' -Property id, deviceName, userPrincipalName, osVersion

        Devices whose name starts with 'NL-LT-', returning only four properties.

    .EXAMPLE
        Get-ITManagedDevice -UserPrincipalName 'jane@contoso.com' | Invoke-ITDeviceSync

        Syncs every device of one user.

    .EXAMPLE
        Get-ITManagedDevice -Filter "manufacturer eq 'Microsoft Corporation'" -Top 10

        First 10 Surface devices, using a raw OData filter.

    .OUTPUTS
        IntuneToolkit.ManagedDevice

    .NOTES
        Graph permission : DeviceManagementManagedDevices.Read.All
        Graph endpoint   : GET /deviceManagement/managedDevices
        API version      : v1.0 (beta supported)

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-list
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('IntuneToolkit.ManagedDevice')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'List', Position = 0)]
        [Alias('DeviceName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [Alias('UPN')]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('Windows', 'iOS', 'iPadOS', 'macOS', 'Android', 'Linux')]
        [string]$OperatingSystem,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('compliant', 'noncompliant', 'conflict', 'error', 'unknown', 'inGracePeriod', 'configManager')]
        [string]$ComplianceState,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('company', 'personal')]
        [string]$OwnerType,

        [Parameter(ParameterSetName = 'List')]
        [datetime]$LastSyncBefore,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Property,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, 999)]
        [int]$Top,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = $script:ITConfig.DefaultApiVersion
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All'
        $basePath = 'deviceManagement/managedDevices'
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            foreach ($deviceId in $Id) {
                $uri = New-ITGraphUri -Path ('{0}/{1}' -f $basePath, $deviceId) -Select $Property
                try {
                    Invoke-ITGraphRequest -Uri $uri -ApiVersion $ApiVersion | ConvertTo-ITObject -TypeName 'ManagedDevice'
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
            }
            return
        }

        # --- List: build server-side filter -------------------------------
        $clauses = New-Object -TypeName System.Collections.Generic.List[string]
        $localNamePattern = $null

        if ($Name) {
            if ($Name -notmatch '[\*\?\[]') {
                $clauses.Add(("deviceName eq '{0}'" -f (ConvertTo-ITODataString $Name)))
            }
            elseif ($Name -match '^[^\*\?\[]+\*$') {
                $clauses.Add(("startswith(deviceName,'{0}')" -f (ConvertTo-ITODataString $Name.TrimEnd('*'))))
            }
            else {
                $localNamePattern = $Name
                Write-ITLog -Message "Name pattern '$Name' is evaluated locally; all matching devices are downloaded first."
            }
        }
        if ($UserPrincipalName) { $clauses.Add(("userPrincipalName eq '{0}'" -f (ConvertTo-ITODataString $UserPrincipalName))) }
        if ($OperatingSystem)   { $clauses.Add(("operatingSystem eq '{0}'" -f $OperatingSystem)) }
        if ($ComplianceState)   { $clauses.Add(("complianceState eq '{0}'" -f $ComplianceState)) }
        if ($OwnerType)         { $clauses.Add(("managedDeviceOwnerType eq '{0}'" -f $OwnerType)) }
        if ($PSBoundParameters.ContainsKey('LastSyncBefore')) {
            $clauses.Add(('lastSyncDateTime le {0}' -f $LastSyncBefore.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')))
        }
        if ($Filter) { $clauses.Add($Filter) }

        $select = $Property
        if ($localNamePattern -and $Property -and ($Property -notcontains 'deviceName')) {
            $select = @($Property) + 'deviceName'
        }

        $uriParams = @{ Path = $basePath; Filter = $clauses.ToArray(); Select = $select }
        if ($Top -and -not $localNamePattern) { $uriParams['Top'] = $Top }
        $uri = New-ITGraphUri @uriParams

        $all = -not $Top -or [bool]$localNamePattern
        $devices = Invoke-ITGraphRequest -Uri $uri -ApiVersion $ApiVersion -All:$all

        if ($localNamePattern) {
            $devices = $devices | Where-Object { $_.deviceName -like $localNamePattern }
            if ($Top) { $devices = $devices | Select-Object -First $Top }
        }

        $devices | ConvertTo-ITObject -TypeName 'ManagedDevice'
    }
}
