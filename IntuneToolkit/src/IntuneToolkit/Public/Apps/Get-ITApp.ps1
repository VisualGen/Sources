function Get-ITApp {
    <#
    .SYNOPSIS
        Gets Intune apps (Win32, Microsoft Store, Microsoft 365, LOB, iOS/Android store, web links, ...).

    .DESCRIPTION
        Returns the mobileApps with ObjectType (Graph type, e.g. win32LobApp, winGetApp,
        iosStoreApp) and Platform. Like the Intune portal, the Microsoft built-in managed apps
        (appAvailability 'global', not assigned) are hidden unless -IncludeBuiltIn is used.
        -Assigned / -Unassigned filter on isAssigned. Results pipe into Get-ITAppAssignment,
        Add-/Remove-ITAppAssignment and Get-ITAppInstallStatus.

    .PARAMETER Name
        App display name. Wildcards allowed.

    .PARAMETER Id
        App ID(s).

    .PARAMETER ObjectType
        Graph app type without namespace, wildcards allowed: 'win32LobApp', 'winGetApp', '*ios*'.

    .PARAMETER Platform
        Only apps for this platform.

    .PARAMETER Assigned
        Only apps with at least one assignment.

    .PARAMETER Unassigned
        Only apps without assignments (clean-up report).

    .PARAMETER IncludeBuiltIn
        Also return the Microsoft built-in managed apps.

    .PARAMETER IncludeAssignment
        Also read the assignments of each app (one extra Graph call per app).

    .EXAMPLE
        Get-ITApp -ObjectType win32LobApp

    .EXAMPLE
        Get-ITApp -Unassigned | Select-Object displayName, ObjectType, createdDateTime

        Monthly: apps nobody receives.

    .EXAMPLE
        Get-ITApp -Name '7-Zip*' | Get-ITAppInstallStatus -FailedOnly

    .OUTPUTS
        IntuneToolkit.App

    .NOTES
        Graph permission : DeviceManagementApps.Read.All
        Graph endpoint   : GET /deviceAppManagement/mobileApps
        API version      : beta (isAssigned and several app types exist only in beta)

    .LINK
        Get-ITAppAssignment
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.App')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateNotNullOrEmpty()]
        [string]$ObjectType,

        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Web')]
        [string]$Platform,

        [switch]$Assigned,

        [switch]$Unassigned,

        [switch]$IncludeBuiltIn,

        [switch]$IncludeAssignment
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType App
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
        if ($Assigned -and $Unassigned) { throw 'Use either -Assigned or -Unassigned.' }
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }

        foreach ($app in @(Get-ITIntuneObject @params)) {
            $isAssigned = $false
            if ($app.PSObject.Properties['isAssigned']) { $isAssigned = [bool]$app.isAssigned }
            $builtIn = $app.PSObject.Properties['appAvailability'] -and [string]$app.appAvailability -eq 'global'

            if ($builtIn -and -not $isAssigned -and -not $IncludeBuiltIn -and $PSCmdlet.ParameterSetName -ne 'ById') { continue }
            if ($ObjectType -and $app.ObjectType -notlike $ObjectType) { continue }
            if ($Platform -and $app.Platform -ne $Platform) { continue }
            if ($Assigned -and -not $isAssigned) { continue }
            if ($Unassigned -and $isAssigned) { continue }
            $app
        }
    }
}
