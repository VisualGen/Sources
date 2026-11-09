function Remove-ITGroupMember {
    <#
    .SYNOPSIS
        Removes users, devices or nested groups from an Entra ID group.

    .DESCRIPTION
        Removes direct members (asks for confirmation; use -Confirm:$false in scripts). Members
        that only come from a nested group are not direct members: remove them from that group,
        or remove the nested group itself. Removing a nested group removes all its members'
        access through this group. Policies and apps assigned to the group stop applying.

        One IntuneToolkit.GroupMemberChange is returned per member: Status Removed, Unchanged
        (not a direct member) or Failed (also written as an error).

    .PARAMETER GroupId
        Group object ID or exact display name. Alias: Group.

    .PARAMETER MemberId
        UPNs, object IDs (users, groups, devices), Entra device IDs, or exact group/device names.

    .PARAMETER InputObject
        Members from the pipeline: IntuneToolkit groups and group members, managed devices (Get-ITManagedDevice: matched on
        azureADDeviceId), Autopilot devices, user objects or plain strings (as -MemberId).

    .EXAMPLE
        Remove-ITGroupMember -GroupId 'SG-Intune-Pilot-Users' -MemberId 'jane@contoso.com'

    .EXAMPLE
        Get-ITGroupMember -Id 'SG-Intune-Pilot-Devices' -MemberType Device |
            Where-Object displayName -like 'OLD-*' | Remove-ITGroupMember -GroupId 'SG-Intune-Pilot-Devices' -WhatIf

        Previews removing old devices from a group.

    .OUTPUTS
        IntuneToolkit.GroupMemberChange

    .NOTES
        Graph permission : Group.ReadWrite.All (+ User.Read.All / Device.Read.All to resolve members)
        Graph endpoint   : DELETE /groups/{id}/members/{memberId}/$ref
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-delete-members
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
            if ($PSCmdlet.ShouldProcess($target, "Remove member from group '$($group.displayName)'")) {
                $approved.Add($resolved)
            }
        }
    }

    end {
        if ($approved.Count) {
            Invoke-ITGroupLinkChange -Group $group -Relation 'Members' -Mode 'Remove' -Member $approved.ToArray()
        }
    }
}
