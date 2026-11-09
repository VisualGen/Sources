function New-ITAssignmentTarget {
    <#
    .SYNOPSIS
        Internal: builds a Graph assignment target (group include/exclude, all devices, all users).

    .DESCRIPTION
        Returns a hashtable ready for an assignment body:
          Include    -> #microsoft.graph.groupAssignmentTarget            (GroupId)
          Exclude    -> #microsoft.graph.exclusionGroupAssignmentTarget   (GroupId)
          AllDevices -> #microsoft.graph.allDevicesAssignmentTarget
          AllUsers   -> #microsoft.graph.allLicensedUsersAssignmentTarget
        An assignment filter (FilterId + FilterType include/exclude) is added when given;
        Graph does not allow filters on exclusion targets.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object only; nothing is changed.')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Include', 'Exclude', 'AllDevices', 'AllUsers')]
        [string]$Intent,

        [string]$GroupId,

        [string]$FilterId,

        [ValidateSet('include', 'exclude')]
        [string]$FilterType = 'include'
    )

    $types = @{
        Include    = '#microsoft.graph.groupAssignmentTarget'
        Exclude    = '#microsoft.graph.exclusionGroupAssignmentTarget'
        AllDevices = '#microsoft.graph.allDevicesAssignmentTarget'
        AllUsers   = '#microsoft.graph.allLicensedUsersAssignmentTarget'
    }

    $target = @{ '@odata.type' = $types[$Intent] }
    if ($Intent -eq 'Include' -or $Intent -eq 'Exclude') {
        if (-not $GroupId) { throw "A GroupId is required for a '$Intent' assignment." }
        $target['groupId'] = $GroupId
    }
    if ($FilterId) {
        if ($Intent -eq 'Exclude') { throw 'Assignment filters cannot be used on exclusion assignments.' }
        $target['deviceAndAppManagementAssignmentFilterId']   = $FilterId
        $target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
    }
    $target
}
