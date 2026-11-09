function Resolve-ITGroup {
    <#
    .SYNOPSIS
        Internal: returns one Entra ID group by object ID or by exact display name.

    .DESCRIPTION
        A GUID is read directly. Any other text is an exact display name; zero or several matches
        throw, because group names are not unique in Entra ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity
    )

    $select = 'id', 'displayName', 'groupTypes', 'securityEnabled', 'mailEnabled', 'isAssignableToRole', 'membershipRule', 'onPremisesSyncEnabled'

    if ($Identity -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
        $uri = New-ITGraphUri -Path "groups/$Identity" -Select $select
        return (Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' | ConvertTo-ITGroupObject)
    }

    $uri = New-ITGraphUri -Path 'groups' -Filter ("displayName eq '{0}'" -f (ConvertTo-ITODataString $Identity)) -Select $select
    $found = @(Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -All)
    if ($found.Count -eq 0) { throw "Group '$Identity' not found." }
    if ($found.Count -gt 1) { throw "$($found.Count) groups are named '$Identity'. Use the group ID instead." }
    $found[0] | ConvertTo-ITGroupObject
}
