function Get-ITAppAssignment {
    <#
    .SYNOPSIS
        Gets the assignments of an Intune app with install intent (required, available, uninstall).

    .DESCRIPTION
        Returns one row per assignment: InstallIntent (required / available / uninstall /
        availableWithoutEnrollment), Intent (Include / Exclude / AllDevices / AllUsers), GroupId,
        FilterId, FilterType. -ResolveName adds GroupName and FilterName.
        Same output as Get-ITPolicyAssignment -PolicyType App.

    .PARAMETER Id
        App ID. Binds from the id of Get-ITApp objects.

    .PARAMETER ResolveName
        Add GroupName and FilterName (needs Group.Read.All).

    .EXAMPLE
        Get-ITApp -Name 'Company Portal' | Get-ITAppAssignment -ResolveName

    .EXAMPLE
        Get-ITApp -ObjectType win32LobApp | Get-ITAppAssignment | Where-Object InstallIntent -eq 'required'

        All required Win32 app assignments.

    .OUTPUTS
        IntuneToolkit.PolicyAssignment

    .NOTES
        Graph permission : DeviceManagementApps.Read.All (+ Group.Read.All for -ResolveName)
        Graph endpoint   : GET /deviceAppManagement/mobileApps/{id}/assignments
        API version      : beta

    .LINK
        Add-ITAppAssignment
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.PolicyAssignment')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [switch]$ResolveName
    )

    process {
        $input_ = $_
        if ($input_ -and $input_.PSObject.Properties['displayName']) {
            $input_ | Select-Object -Property @{ n = 'PolicyType'; e = { 'App' } }, @{ n = 'Id'; e = { $Id } }, displayName |
                Get-ITPolicyAssignment -ResolveName:$ResolveName
        }
        else {
            Get-ITPolicyAssignment -PolicyType App -Id $Id -ResolveName:$ResolveName
        }
    }
}
