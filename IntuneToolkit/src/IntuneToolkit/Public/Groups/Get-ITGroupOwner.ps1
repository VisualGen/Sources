function Get-ITGroupOwner {
    <#
    .SYNOPSIS
        Lists the owners of an Entra ID group.

    .DESCRIPTION
        Returns the users and service principals that own the group, in the same shape as
        Get-ITGroupMember (MemberType, displayName, userPrincipalName, accountEnabled ...).

    .PARAMETER Id
        Group object ID or exact display name. Accepts pipeline input by property name (id / GroupId).

    .EXAMPLE
        Get-ITGroupOwner -Id 'SG-Intune-Pilot-Users'

    .EXAMPLE
        Get-ITGroup -Name 'SG-Intune-*' | Where-Object { -not @(Get-ITGroupOwner -Id $_.id).Count } | Select-Object displayName

        Intune groups without an owner.

    .OUTPUTS
        IntuneToolkit.GroupMember

    .NOTES
        Graph permission : Group.Read.All
        Graph endpoint   : GET /groups/{id}/owners
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-list-owners
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.GroupMember')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.Read.All'
        $select = 'id', 'displayName', 'userPrincipalName', 'mail', 'accountEnabled', 'appId'
    }

    process {
        foreach ($identity in $Id) {
            try {
                $group = Resolve-ITGroup -Identity $identity
                $uri = New-ITGraphUri -Path ('groups/{0}/owners' -f $group.id) -Select $select
                foreach ($o in @(Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -All)) {
                    $row = [ordered]@{
                        GroupId           = $group.id
                        GroupName         = $group.displayName
                        MemberType        = Get-ITDirectoryObjectType -InputObject $o
                        id                = $o.id
                        displayName       = $null
                        userPrincipalName = $null
                        mail              = $null
                        accountEnabled    = $null
                        Depth             = 1
                        Path              = $group.displayName
                    }
                    foreach ($p in 'displayName', 'userPrincipalName', 'mail', 'accountEnabled') {
                        if ($o.PSObject.Properties[$p]) { $row[$p] = $o.$p }
                    }
                    [pscustomobject]$row | ConvertTo-ITObject -TypeName 'GroupMember'
                }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
