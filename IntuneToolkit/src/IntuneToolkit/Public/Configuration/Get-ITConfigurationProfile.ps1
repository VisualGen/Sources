function Get-ITConfigurationProfile {
    <#
    .SYNOPSIS
        Gets Intune device configuration profiles (template-based, the "legacy" profile types).

    .DESCRIPTION
        Returns deviceConfigurations (Wi-Fi, VPN, certificates, device restrictions, custom OMA-URI,
        endpoint protection, update rings, ...) with Platform and ObjectType (Graph type, e.g.
        windows10CustomConfiguration). Settings catalog policies are returned by
        Get-ITSettingsCatalogPolicy. -ObjectType filters on the Graph type (wildcards allowed).

    .PARAMETER Name
        Profile display name. Wildcards allowed.

    .PARAMETER Id
        Profile ID(s).

    .PARAMETER Platform
        Only profiles for this platform.

    .PARAMETER ObjectType
        Graph type without namespace, e.g. 'windows10CustomConfiguration' or '*Wifi*'.

    .PARAMETER IncludeAssignment
        Also read the assignments of each profile (one extra Graph call per profile).

    .PARAMETER ApiVersion
        Graph API version. Default: v1.0 ('beta' returns more profile types and properties).

    .EXAMPLE
        Get-ITConfigurationProfile -Platform Windows

    .EXAMPLE
        Get-ITConfigurationProfile -ObjectType '*Custom*' | Format-List displayName, omaSettings

        Custom OMA-URI profiles with their settings.

    .EXAMPLE
        Get-ITConfigurationProfile -IncludeAssignment | Where-Object { -not $_.Assignments } | Select-Object displayName, ObjectType

        Profiles without any assignment.

    .OUTPUTS
        IntuneToolkit.ConfigurationProfile

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/deviceConfigurations
        API version      : v1.0 (default) or beta

    .LINK
        Get-ITSettingsCatalogPolicy
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.ConfigurationProfile')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateSet('Windows', 'Windows8', 'macOS', 'iOS', 'Android', 'Linux')]
        [string]$Platform,

        [ValidateNotNullOrEmpty()]
        [string]$ObjectType,

        [switch]$IncludeAssignment,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'v1.0'
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType DeviceConfiguration
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; ApiVersion = $ApiVersion; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }
        $platformFilter = $Platform
        $typeFilter = $ObjectType
        Get-ITIntuneObject @params | Where-Object {
            (-not $platformFilter -or $_.Platform -eq $platformFilter) -and (-not $typeFilter -or $_.ObjectType -like $typeFilter)
        }
    }
}
