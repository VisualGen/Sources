function Remove-ITGroupOwner {
    <#
    .SYNOPSIS
        Removes owners from an Entra ID group.

    .DESCRIPTION
        Removes owners (asks for confirmation). Graph refuses to remove the last owner of a
        Microsoft 365 group; that owner is returned with Status Failed.

        One IntuneToolkit.GroupMemberChange is returned per owner: Status Removed, Unchanged
        (not an owner) or Failed (also written as an error).

    .PARAMETER GroupId
        Group object ID or exact display name. Alias: Group.

    .PARAMETER MemberId
        UPNs or object IDs of the owners to remove.

    .PARAMETER InputObject
        Owners from the pipeline: owners from Get-ITGroupOwner, user objects or plain strings (as -MemberId).

    .EXAMPLE
        Remove-ITGroupOwner -GroupId 'SG-Intune-Pilot-Users' -MemberId 'former.admin@contoso.com'

    .EXAMPLE
        Get-ITGroupOwner -Id 'SG-Intune-Pilot-Users' | Where-Object accountEnabled -eq $false |
            Remove-ITGroupOwner -GroupId 'SG-Intune-Pilot-Users' -WhatIf

        Previews removing disabled accounts as owners.

    .OUTPUTS
        IntuneToolkit.GroupMemberChange

    .NOTES
        Graph permission : Group.ReadWrite.All (+ User.Read.All / Device.Read.All to resolve owners)
        Graph endpoint   : DELETE /groups/{id}/owners/{ownerId}/$ref
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-delete-owners
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType('IntuneToolkit.GroupMemberChange')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Group')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupId,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$MemberId,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [ValidateNotNull()]
        [object[]]$InputObject
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.ReadWrite.All'
        $group = Resolve-ITGroup -Identity $GroupId
        $cache = @{}
        $approved = New-Object -TypeName System.Collections.Generic.List[object]
    }

    process {
        $items = $InputObject
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $items = $MemberId }
        foreach ($item in @($items)) {
            try {
                $resolved = Resolve-ITDirectoryObject -InputObject $item -Cache $cache
            }
            catch {
                Write-Error -ErrorRecord $_
                continue
            }
            $target = '{0} ({1})' -f $resolved.DisplayName, $resolved.ObjectType
            if ($PSCmdlet.ShouldProcess($target, "Remove owner from group '$($group.displayName)'")) {
                $approved.Add($resolved)
            }
        }
    }

    end {
        if ($approved.Count) {
            Invoke-ITGroupLinkChange -Group $group -Relation 'Owners' -Mode 'Remove' -Member $approved.ToArray()
        }
    }
}
