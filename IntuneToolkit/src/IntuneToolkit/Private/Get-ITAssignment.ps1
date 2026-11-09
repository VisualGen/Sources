function Get-ITAssignment {
    <#
    .SYNOPSIS
        Internal: reads the assignments of an Intune object and returns them in one flat format.

    .DESCRIPTION
        Works for every Intune object with an /assignments collection (profiles, enrollment
        configurations, policies, apps). The Graph target type is translated to an Intent:
          groupAssignmentTarget            -> Include
          exclusionGroupAssignmentTarget   -> Exclude
          allDevicesAssignmentTarget       -> AllDevices
          allLicensedUsersAssignmentTarget -> AllUsers

        With -InputObject the assignments are already loaded (for example from $expand=assignments)
        and are only converted; no request is sent.

    .EXAMPLE
        Get-ITAssignment -Path "deviceManagement/windowsAutopilotDeploymentProfiles/$id" -ApiVersion beta
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('IntuneToolkit.Assignment')]
    param(
        # Object path WITHOUT '/assignments'
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        # Assignment objects that were already read (no request is sent)
        [Parameter(Mandatory, ParameterSetName = 'InputObject')]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'beta',

        # Return the Graph assignment objects unchanged (used to rebuild the set for POST /assign)
        [switch]$Raw
    )

    if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
        $items = @($InputObject | Where-Object { $null -ne $_ })
    }
    else {
        $items = @(Invoke-ITGraphRequest -Uri ('{0}/assignments' -f $Path.TrimEnd('/')) -ApiVersion $ApiVersion -All)
    }
    if ($Raw) { $items; return }

    foreach ($item in $items) {
        $target = $null
        if ($item.PSObject.Properties['target']) { $target = $item.target }

        $type = ''
        if ($target -and $target.PSObject.Properties['@odata.type']) { $type = [string]$target.'@odata.type' }

        # 'break' is required: switch runs EVERY matching case, and '*groupAssignmentTarget'
        # also matches 'exclusionGroupAssignmentTarget' (exclusions would become Include).
        switch -Wildcard ($type) {
            '*exclusionGroupAssignmentTarget'   { $intent = 'Exclude'; break }
            '*groupAssignmentTarget'            { $intent = 'Include'; break }
            '*allDevicesAssignmentTarget'       { $intent = 'AllDevices'; break }
            '*allLicensedUsersAssignmentTarget' { $intent = 'AllUsers'; break }
            default                             { $intent = $type -replace '^#microsoft\.graph\.', '' }
        }

        $groupId = $null; $filterId = $null; $filterType = $null
        if ($target) {
            if ($target.PSObject.Properties['groupId']) { $groupId = $target.groupId }
            if ($target.PSObject.Properties['deviceAndAppManagementAssignmentFilterId']) { $filterId = $target.deviceAndAppManagementAssignmentFilterId }
            if ($target.PSObject.Properties['deviceAndAppManagementAssignmentFilterType']) { $filterType = $target.deviceAndAppManagementAssignmentFilterType }
        }
        if ($filterType -eq 'none') { $filterType = $null }

        # Apps: required / available / uninstall; scripts and policies: $null
        $installIntent = $null
        if ($item.PSObject.Properties['intent']) { $installIntent = $item.intent }

        [pscustomobject]@{
            PSTypeName    = 'IntuneToolkit.Assignment'
            Intent        = $intent
            InstallIntent = $installIntent
            GroupId       = $groupId
            FilterId      = $filterId
            FilterType    = $filterType
            AssignmentId  = $item.id
        }
    }
}
