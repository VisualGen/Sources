function Get-ITAutopilotProfile {
    <#
    .SYNOPSIS
        Gets Windows Autopilot deployment profiles.

    .DESCRIPTION
        Returns the deployment profiles with a JoinType property (EntraJoined / HybridJoined).
        With -IncludeAssignment the included and excluded groups are added as Assignments
        (Intent, GroupId, FilterId, FilterType).

    .PARAMETER Name
        Profile display name. Wildcards allowed.

    .PARAMETER Id
        Profile ID(s).

    .PARAMETER IncludeAssignment
        Also read the group assignments of each profile (one extra Graph call per profile).

    .EXAMPLE
        Get-ITAutopilotProfile

    .EXAMPLE
        Get-ITAutopilotProfile -IncludeAssignment |
            Select-Object displayName, JoinType, @{ n = 'Groups'; e = { ($_.Assignments | ForEach-Object { "$($_.Intent):$($_.GroupId)" }) -join '; ' } }

        Which groups each profile targets.

    .EXAMPLE
        Get-ITAutopilotProfile -Name '*Kiosk*' | Format-List *

        All settings of the kiosk profile(s).

    .OUTPUTS
        IntuneToolkit.AutopilotProfile

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All
        Graph endpoint   : GET /deviceManagement/windowsAutopilotDeploymentProfiles
        API version      : beta (not available in v1.0)

    .LINK
        https://learn.microsoft.com/graph/api/intune-enrollment-windowsautopilotdeploymentprofile-list?view=graph-rest-beta
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.AutopilotProfile')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$IncludeAssignment
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'
    $basePath = 'deviceManagement/windowsAutopilotDeploymentProfiles'

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $profiles = foreach ($profileId in $Id) {
            try {
                Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $profileId) -ApiVersion 'beta'
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
    else {
        $profiles = Invoke-ITGraphRequest -Uri $basePath -ApiVersion 'beta' -All
        if ($Name) { $profiles = $profiles | Where-Object { $_.displayName -like $Name } }
    }

    foreach ($item in @($profiles | Where-Object { $_ })) {
        $odataType = ''
        if ($item.PSObject.Properties['@odata.type']) { $odataType = [string]$item.'@odata.type' }
        $joinType = 'Unknown'
        if ($odataType -like '*azureADWindowsAutopilotDeploymentProfile') { $joinType = 'EntraJoined' }
        elseif ($odataType -like '*activeDirectoryWindowsAutopilotDeploymentProfile') { $joinType = 'HybridJoined' }
        Add-Member -InputObject $item -NotePropertyName 'JoinType' -NotePropertyValue $joinType -Force

        if ($IncludeAssignment) {
            $assignments = @()
            try {
                $assignments = @(Get-ITAssignment -Path ('{0}/{1}' -f $basePath, $item.id) -ApiVersion 'beta')
            }
            catch {
                Write-Error -ErrorRecord $_
            }
            Add-Member -InputObject $item -NotePropertyName 'Assignments' -NotePropertyValue $assignments -Force
        }
        $item | ConvertTo-ITObject -TypeName 'AutopilotProfile'
    }
}
