function Get-ITEnrollmentRestriction {
    <#
    .SYNOPSIS
        Gets Intune enrollment restrictions (platform restrictions and device limits).

    .DESCRIPTION
        Returns the enrollment restriction configurations in evaluation order: by priority,
        with the built-in default restrictions last (IsDefault = $true).
        ConfigurationType is one of:
          PlatformRestrictions - the built-in all-platforms default
          PlatformRestriction  - a per-platform restriction (platformType: windows, ios, android...)
          DeviceLimit          - maximum number of devices per user (limit)

    .PARAMETER Type
        Platform, DeviceLimit or All (default).

    .PARAMETER Name
        Display name. Wildcards allowed.

    .PARAMETER IncludeAssignment
        Also read the group assignments of each restriction.

    .EXAMPLE
        Get-ITEnrollmentRestriction

    .EXAMPLE
        Get-ITEnrollmentRestriction -Type DeviceLimit | Select-Object displayName, priority, limit, IsDefault

        Device limits per user.

    .EXAMPLE
        Get-ITEnrollmentRestriction -Type Platform -IncludeAssignment | Format-List displayName, platformType, Assignments

    .OUTPUTS
        IntuneToolkit.EnrollmentConfiguration

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All
        Graph endpoint   : GET /deviceManagement/deviceEnrollmentConfigurations
        API version      : beta (v1.0 does not return per-platform restrictions)

    .LINK
        https://learn.microsoft.com/graph/api/intune-onboarding-deviceenrollmentconfiguration-list?view=graph-rest-beta
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.EnrollmentConfiguration')]
    param(
        [ValidateSet('All', 'Platform', 'DeviceLimit')]
        [string]$Type = 'All',

        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$IncludeAssignment
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'

    switch ($Type) {
        'Platform'    { $types = @('PlatformRestrictions', 'PlatformRestriction') }
        'DeviceLimit' { $types = @('DeviceLimit') }
        default       { $types = @('PlatformRestrictions', 'PlatformRestriction', 'DeviceLimit') }
    }

    $params = @{ ConfigurationType = $types; IncludeAssignment = $IncludeAssignment }
    if ($Name) { $params['Name'] = $Name }

    Get-ITEnrollmentConfiguration @params | ConvertTo-ITObject -TypeName 'EnrollmentConfiguration'
}
