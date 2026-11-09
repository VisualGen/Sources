function Get-ITDriverUpdateProfile {
    <#
    .SYNOPSIS
        Gets Windows driver update profiles, optionally with the driver inventory.

    .DESCRIPTION
        Returns the driver update profiles (approvalType manual/automatic, deferral, number of
        new updates). -IncludeInventory adds Drivers: the driver/firmware updates the profile
        knows (name, version, manufacturer, approvalStatus, applicableDeviceCount).

    .PARAMETER Name
        Profile display name. Wildcards allowed.

    .PARAMETER Id
        Profile ID(s).

    .PARAMETER IncludeInventory
        Add the driver inventory (one extra Graph call per profile).

    .PARAMETER IncludeAssignment
        Also read the assignments.

    .EXAMPLE
        Get-ITDriverUpdateProfile

    .EXAMPLE
        Get-ITDriverUpdateProfile -IncludeInventory | Select-Object -ExpandProperty Drivers |
            Where-Object approvalStatus -eq 'needsReview' | Select-Object name, version, manufacturer, applicableDeviceCount

        Drivers waiting for approval.

    .OUTPUTS
        IntuneToolkit.DriverUpdateProfile

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/windowsDriverUpdateProfiles (+ /driverInventories)
        API version      : beta

    .LINK
        Get-ITFeatureUpdateProfile
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.DriverUpdateProfile')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$IncludeInventory,

        [switch]$IncludeAssignment
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType DriverUpdate
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }
        foreach ($item in @(Get-ITIntuneObject @params)) {
            if ($IncludeInventory) {
                $drivers = @()
                try {
                    $drivers = @(Invoke-ITGraphRequest -Uri ('{0}/{1}/driverInventories' -f $info.Path, $item.id) -ApiVersion 'beta' -All)
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
                Add-Member -InputObject $item -NotePropertyName 'Drivers' -NotePropertyValue $drivers -Force
            }
            $item
        }
    }
}
