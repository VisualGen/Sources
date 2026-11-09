function Get-ITDeviceCategory {
    <#
    .SYNOPSIS
        Gets Intune device categories.

    .DESCRIPTION
        Returns all device categories, or those matching -Name (wildcards allowed) or -Id.
        Categories are used for dynamic group membership (deviceCategory -eq "...").

    .PARAMETER Name
        Category display name. Wildcards allowed.

    .PARAMETER Id
        Category ID.

    .EXAMPLE
        Get-ITDeviceCategory

    .EXAMPLE
        Get-ITDeviceCategory -Name 'Kiosk*'

    .OUTPUTS
        IntuneToolkit.DeviceCategory

    .NOTES
        Graph permission : DeviceManagementManagedDevices.Read.All
        Graph endpoint   : GET /deviceManagement/deviceCategories
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-shared-devicecategory-list
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.DeviceCategory')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All'

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        Invoke-ITGraphRequest -Uri ('deviceManagement/deviceCategories/{0}' -f $Id) -ApiVersion 'v1.0' |
            ConvertTo-ITObject -TypeName 'DeviceCategory'
        return
    }

    $categories = Invoke-ITGraphRequest -Uri 'deviceManagement/deviceCategories' -ApiVersion 'v1.0' -All
    if ($Name) { $categories = $categories | Where-Object { $_.displayName -like $Name } }
    $categories | ConvertTo-ITObject -TypeName 'DeviceCategory'
}
