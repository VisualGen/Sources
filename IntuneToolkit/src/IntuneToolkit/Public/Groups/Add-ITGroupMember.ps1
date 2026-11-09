function Add-ITGroupMember {
    <#
    .SYNOPSIS
        Adds users, devices or groups (nested groups) to an Entra ID group.

    .DESCRIPTION
        Members are added in batches of 20. Members that are already in the group are skipped.
        Adding a group makes it a nested group: its members get everything assigned to the parent.

        Checked before Graph is called: dynamic groups (members come from the rule), groups
        synced from on-premises AD, Microsoft 365 and role-assignable groups (cannot contain
        groups) and circular nesting (the parent is already a nested member of the new group).

        One IntuneToolkit.GroupMemberChange is returned per member: Status Added, Unchanged
        (already a member) or Failed (also written as an error).

    .PARAMETER GroupId
        Group object ID or exact display name. Alias: Group.

    .PARAMETER MemberId
        UPNs, object IDs (users, groups, devices), Entra device IDs, or exact group/device names.

    .PARAMETER InputObject
        Members from the pipeline: IntuneToolkit groups and group members, managed devices (Get-ITManagedDevice: matched on
        azureADDeviceId), Autopilot devices, user objects or plain strings (as -MemberId).

    .EXAMPLE
        Add-ITGroupMember -GroupId 'SG-Intune-Pilot-Users' -MemberId 'jane@contoso.com', 'john@contoso.com'

        Adds two users.

    .EXAMPLE
        Get-ITManagedDevice -Name 'NL-LT-*' | Add-ITGroupMember -GroupId 'SG-Intune-Pilot-Devices'

        Adds Intune devices (their Entra ID device objects) to a device group.

    .EXAMPLE
        Add-ITGroupMember -GroupId 'SG-Intune-All-Pilots' -MemberId 'SG-Intune-Pilot-Users'

        Nests one group in another.

    .OUTPUTS
        IntuneToolkit.GroupMemberChange

    .NOTES
        Graph permission : Group.ReadWrite.All (+ User.Read.All / Device.Read.All to resolve members)
        Graph endpoint   : PATCH /groups/{id} (members@odata.bind), POST /groups/{id}/members/$ref
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-post-members
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
            if ($PSCmdlet.ShouldProcess($target, "Add member to group '$($group.displayName)'")) {
                $approved.Add($resolved)
            }
        }
    }

    end {
        if ($approved.Count) {
            Invoke-ITGroupLinkChange -Group $group -Relation 'Members' -Mode 'Add' -Member $approved.ToArray()
        }
    }
}
