function Get-ITRoleDefinition {
    <#
    .SYNOPSIS
        Gets Intune RBAC role definitions (built-in and custom roles) with their permissions.

    .DESCRIPTION
        Returns the roles with isBuiltIn and AllowedActions (flat list of the allowed
        resource actions, e.g. Microsoft.Intune_ManagedDevices_Read).

    .PARAMETER Name
        Role display name. Wildcards allowed.

    .PARAMETER Id
        Role ID(s).

    .PARAMETER CustomOnly
        Only custom roles.

    .EXAMPLE
        Get-ITRoleDefinition -CustomOnly

    .EXAMPLE
        Get-ITRoleDefinition -Name 'Help Desk Operator' | Select-Object -ExpandProperty AllowedActions

    .OUTPUTS
        IntuneToolkit.RoleDefinition

    .NOTES
        Graph permission : DeviceManagementRBAC.Read.All
        Graph endpoint   : GET /deviceManagement/roleDefinitions
        API version      : beta

    .LINK
        Get-ITRoleAssignment
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.RoleDefinition')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$CustomOnly
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementRBAC.Read.All'
    $basePath = 'deviceManagement/roleDefinitions'

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $roles = foreach ($roleId in $Id) {
            try { Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $roleId) -ApiVersion 'beta' }
            catch { Write-Error -ErrorRecord $_ }
        }
    }
    else {
        $roles = Invoke-ITGraphRequest -Uri $basePath -ApiVersion 'beta' -All
        if ($Name) { $roles = $roles | Where-Object { $_.displayName -like $Name } }
    }

    foreach ($role in @($roles | Where-Object { $_ })) {
        if ($CustomOnly -and $role.PSObject.Properties['isBuiltIn'] -and $role.isBuiltIn) { continue }
        $actions = @()
        if ($role.PSObject.Properties['rolePermissions']) {
            $actions = @($role.rolePermissions | Where-Object { $_ } | ForEach-Object {
                    $perm = $_
                    if ($perm.PSObject.Properties['resourceActions']) {
                        $perm.resourceActions | Where-Object { $_ -and $_.PSObject.Properties['allowedResourceActions'] } | ForEach-Object { $_.allowedResourceActions }
                    }
                    elseif ($perm.PSObject.Properties['actions']) { $perm.actions }
                } | Sort-Object -Unique)
        }
        Add-Member -InputObject $role -NotePropertyName 'AllowedActions' -NotePropertyValue $actions -Force
        $role | ConvertTo-ITObject -TypeName 'RoleDefinition'
    }
}
