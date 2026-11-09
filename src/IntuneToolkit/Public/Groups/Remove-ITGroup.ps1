function Remove-ITGroup {
    <#
    .SYNOPSIS
        Deletes an Entra ID group.

    .DESCRIPTION
        Deletes the group (asks for confirmation; use -Confirm:$false in scripts).

        Microsoft 365 groups can be restored for 30 days (Entra admin center, Deleted groups).
        Security groups are deleted permanently. Intune policies and apps assigned to the group
        stop applying to its members, and nested groups lose the membership it gave them.
        Groups synced from on-premises Active Directory must be deleted there.

    .PARAMETER Id
        Group object ID or exact display name. Accepts pipeline input by property name (id / GroupId).

    .EXAMPLE
        Remove-ITGroup -Id 'SG-Intune-Old-Pilot'

    .EXAMPLE
        Get-ITGroup -GroupType Security -IncludeMemberCount | Where-Object MemberCount -eq 0 | Remove-ITGroup -WhatIf

        Previews deleting every empty security group.

    .NOTES
        Graph permission : Group.ReadWrite.All
        Graph endpoint   : DELETE /groups/{id}
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-delete
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.ReadWrite.All'
    }

    process {
        foreach ($identity in $Id) {
            try {
                $group = Resolve-ITGroup -Identity $identity
            }
            catch {
                Write-Error -ErrorRecord $_
                continue
            }
            if ($group.PSObject.Properties['onPremisesSyncEnabled'] -and $group.onPremisesSyncEnabled) {
                Write-Error "'$($group.displayName)' is synced from on-premises Active Directory; delete it there."
                continue
            }

            $what = '{0} group' -f $group.GroupType
            if ($group.GroupType -ne 'Microsoft365') { $what += ' (permanent, cannot be restored)' }
            if ($PSCmdlet.ShouldProcess(('{0} ({1})' -f $group.displayName, $group.id), "Delete $what")) {
                try {
                    $null = Invoke-ITGraphRequest -Uri ('groups/{0}' -f $group.id) -Method DELETE -ApiVersion 'v1.0'
                    Write-ITLog -Message ("Deleted group '{0}' ({1})." -f $group.displayName, $group.id)
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
            }
        }
    }
}
