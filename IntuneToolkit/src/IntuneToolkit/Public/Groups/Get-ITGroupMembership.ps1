function Get-ITGroupMembership {
    <#
    .SYNOPSIS
        Lists the groups a user, device or group is a member of (directly or through nesting).

    .DESCRIPTION
        The reverse of Get-ITGroupMember: "which groups is this object in?". Useful to explain
        why a policy or app reaches a device or user.

        Without -Transitive: the groups the object is a direct member of.
        With -Transitive: also the groups it reaches through nested groups. Direct is $true for
        direct memberships and $false for memberships through nesting.

    .PARAMETER Identity
        UPN, object ID, Entra device ID or exact group/device name. Accepts pipeline input,
        including managed devices (Get-ITManagedDevice), groups and group members.

    .PARAMETER Transitive
        Include groups reached through nested groups.

    .EXAMPLE
        Get-ITGroupMembership -Identity 'jane@contoso.com' -Transitive

        Every group Jane is in, directly or through nesting.

    .EXAMPLE
        Get-ITManagedDevice -Name 'NL-LT-0042' | Get-ITGroupMembership -Transitive | Select-Object displayName, Direct

        The groups of one Intune device (its Entra ID device object).

    .OUTPUTS
        IntuneToolkit.GroupMembership

    .NOTES
        Graph permission : Group.Read.All (+ User.Read.All / Device.Read.All)
        Graph endpoint   : GET /{users|devices|groups|servicePrincipals}/{id}/memberOf (transitiveMemberOf)
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/user-list-transitivememberof
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.GroupMembership')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]]$Identity,

        [switch]$Transitive
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.Read.All'
        $cache = @{}
        $segments = @{ User = 'users'; Device = 'devices'; Group = 'groups'; ServicePrincipal = 'servicePrincipals'; Contact = 'contacts' }
        $select = 'id', 'displayName', 'description', 'groupTypes', 'securityEnabled', 'mailEnabled', 'membershipRule', 'isAssignableToRole', 'onPremisesSyncEnabled'
    }

    process {
        foreach ($item in $Identity) {
            try {
                $obj = Resolve-ITDirectoryObject -InputObject $item -Cache $cache
                $segment = $segments[$obj.ObjectType]
                if (-not $segment) { throw "Cannot list group memberships for object type '$($obj.ObjectType)'." }

                # The cast to microsoft.graph.group leaves out directory roles and administrative units
                $directUri = New-ITGraphUri -Path ('{0}/{1}/memberOf/microsoft.graph.group' -f $segment, $obj.Id) -Select $select
                $direct = @(Invoke-ITGraphRequest -Uri $directUri -ApiVersion 'v1.0' -All)
                $groups = $direct
                if ($Transitive) {
                    $allUri = New-ITGraphUri -Path ('{0}/{1}/transitiveMemberOf/microsoft.graph.group' -f $segment, $obj.Id) -Select $select
                    $groups = @(Invoke-ITGraphRequest -Uri $allUri -ApiVersion 'v1.0' -All)
                }
                $directIds = @($direct | ForEach-Object { [string]$_.id })

                foreach ($g in $groups) {
                    $g | Add-Member -NotePropertyName 'MemberId' -NotePropertyValue $obj.Id -Force
                    $g | Add-Member -NotePropertyName 'MemberName' -NotePropertyValue $obj.DisplayName -Force
                    $g | Add-Member -NotePropertyName 'MemberType' -NotePropertyValue $obj.ObjectType -Force
                    $g | Add-Member -NotePropertyName 'Direct' -NotePropertyValue ($directIds -contains [string]$g.id) -Force
                    $out = $g | ConvertTo-ITGroupObject
                    # Keep IntuneToolkit.Group underneath so groups pipe into the group commands
                    $out | ConvertTo-ITObject -TypeName 'GroupMembership'
                }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
