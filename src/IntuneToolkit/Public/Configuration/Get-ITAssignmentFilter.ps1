function Get-ITAssignmentFilter {
    <#
    .SYNOPSIS
        Gets Intune assignment filters.

    .DESCRIPTION
        Returns the assignment filters (rule, platform, managed devices or apps). Use the id
        with Add-ITPolicyAssignment / Add-ITAppAssignment -FilterId, or to translate the FilterId
        of Get-ITPolicyAssignment output into a name.

    .PARAMETER Name
        Filter display name. Wildcards allowed.

    .PARAMETER Id
        Filter ID(s).

    .PARAMETER Platform
        Graph platform value, e.g. windows10AndLater, iOS, androidForWork, macOS.

    .EXAMPLE
        Get-ITAssignmentFilter

    .EXAMPLE
        Get-ITAssignmentFilter -Name 'Corporate Windows*' | Select-Object displayName, rule

    .EXAMPLE
        $filter = Get-ITAssignmentFilter -Name 'Windows 11 only'
        Get-ITCompliancePolicy -Name 'Win - Baseline' | Add-ITPolicyAssignment -GroupId $groupId -FilterId $filter.id -WhatIf

    .OUTPUTS
        IntuneToolkit.AssignmentFilter

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/assignmentFilters
        API version      : beta

    .LINK
        Add-ITPolicyAssignment
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.AssignmentFilter')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateNotNullOrEmpty()]
        [string]$Platform
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
    $basePath = 'deviceManagement/assignmentFilters'

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $filters = foreach ($filterId in $Id) {
            try { Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $filterId) -ApiVersion 'beta' }
            catch { Write-Error -ErrorRecord $_ }
        }
    }
    else {
        $filters = Invoke-ITGraphRequest -Uri $basePath -ApiVersion 'beta' -All
        if ($Name) { $filters = $filters | Where-Object { $_.displayName -like $Name } }
    }

    $platformFilter = $Platform
    $filters | Where-Object { $_ -and (-not $platformFilter -or $_.platform -eq $platformFilter) } | ConvertTo-ITObject -TypeName 'AssignmentFilter'
}
