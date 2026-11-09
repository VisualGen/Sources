function Add-ITGroupOwner {
    <#
    .SYNOPSIS
        Adds owners (users or service principals) to an Entra ID group.

    .DESCRIPTION
        Owners can manage the group (name, members) without an admin role. Only users and
        service principals can be owners.

        One IntuneToolkit.GroupMemberChange is returned per owner: Status Added, Unchanged
        (already an owner) or Failed (also written as an error).

    .PARAMETER GroupId
        Group object ID or exact display name. Alias: Group.

    .PARAMETER MemberId
        UPNs or object IDs of users or service principals.

    .PARAMETER InputObject
        Owners from the pipeline: user objects, group members (Get-ITGroupMember) or plain strings (as -MemberId).

    .EXAMPLE
        Add-ITGroupOwner -GroupId 'SG-Intune-Pilot-Users' -MemberId 'servicedesk.lead@contoso.com'

        Lets a service desk lead manage the pilot group.

    .OUTPUTS
        IntuneToolkit.GroupMemberChange

    .NOTES
        Graph permission : Group.ReadWrite.All (+ User.Read.All / Device.Read.All to resolve owners)
        Graph endpoint   : PATCH /groups/{id} (owners@odata.bind), POST /groups/{id}/owners/$ref
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-post-owners
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ById')]
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
            if ($PSCmdlet.ShouldProcess($target, "Add owner to group '$($group.displayName)'")) {
                $approved.Add($resolved)
            }
        }
    }

    end {
        if ($approved.Count) {
            Invoke-ITGroupLinkChange -Group $group -Relation 'Owners' -Mode 'Add' -Member $approved.ToArray()
        }
    }
}
