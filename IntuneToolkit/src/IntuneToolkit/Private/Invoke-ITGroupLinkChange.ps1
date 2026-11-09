function Invoke-ITGroupLinkChange {
    <#
    .SYNOPSIS
        Internal: adds or removes members or owners of one Entra ID group and reports each change.

    .DESCRIPTION
        Shared by Add-/Remove-ITGroupMember and Add-/Remove-ITGroupOwner. The caller has already
        resolved the group (Resolve-ITGroup) and the members (Resolve-ITDirectoryObject) and asked
        ShouldProcess. This function:
          - checks the rules Graph would reject with an unclear error (dynamic group, group synced
            from on-premises AD, groups nested into a Microsoft 365 or role-assignable group,
            a group nested into itself or into one of its own members = circular nesting,
            owners that are not users or service principals);
          - skips members that are already there (Add) or not there (Remove): Status Unchanged;
          - adds in batches of 20 (PATCH members@odata.bind) and retries one by one when a batch
            fails, so one bad member does not block the rest;
          - returns one IntuneToolkit.GroupMemberChange per member; failures are also written as
            non-terminating errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Group,

        [Parameter(Mandatory)]
        [ValidateSet('Members', 'Owners')]
        [string]$Relation,

        [Parameter(Mandatory)]
        [ValidateSet('Add', 'Remove')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Member
    )

    $segment  = $Relation.ToLowerInvariant()
    $label    = $Relation.TrimEnd('s')
    $bindBase = '{0}/v1.0/directoryObjects/' -f $script:ITConfig.GraphBaseUri.TrimEnd('/')

    $result = {
        param($m, [string]$Status, [string]$Message)
        if ($Status -eq 'Failed') {
            Write-Error ("{0} {1} '{2}' {3} '{4}': {5}" -f $Mode, $label.ToLowerInvariant(), $m.DisplayName, $(if ($Mode -eq 'Add') { 'to' } else { 'from' }), $Group.displayName, $Message)
        }
        [pscustomobject]@{
            PSTypeName = 'IntuneToolkit.GroupMemberChange'
            GroupId    = $Group.id
            GroupName  = $Group.displayName
            Relation   = $label
            Action     = $Mode
            MemberId   = $m.Id
            MemberName = $m.DisplayName
            MemberType = $m.ObjectType
            Status     = $Status
            Message    = $Message
        }
    }

    if (-not @($Member).Count) { return }

    # --- Rules that apply to the whole group ------------------------------------------------
    $blocked = $null
    if ($Relation -eq 'Members') {
        if ($Group.MembershipType -eq 'Dynamic') {
            $blocked = 'The group has dynamic membership; members come from its rule (Set-ITGroup -MembershipRule).'
        }
        elseif ($Group.PSObject.Properties['onPremisesSyncEnabled'] -and $Group.onPremisesSyncEnabled) {
            $blocked = 'The group is synced from on-premises Active Directory; change its members there.'
        }
    }
    if ($blocked) {
        foreach ($m in $Member) { & $result $m 'Failed' $blocked }
        return
    }

    # --- Current members/owners ------------------------------------------------------------------
    $current = @{}
    $uri = New-ITGraphUri -Path ('groups/{0}/{1}' -f $Group.id, $segment) -Select 'id'
    foreach ($row in @(Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -All)) { $current[[string]$row.id] = $true }

    $todo = New-Object -TypeName System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($m in $Member) {
        if ($seen.ContainsKey($m.Id)) { continue }
        $seen[$m.Id] = $true

        if ($Mode -eq 'Remove') {
            if (-not $current.ContainsKey($m.Id)) { & $result $m 'Unchanged' "Not a $($label.ToLowerInvariant()) of the group."; continue }
            $todo.Add($m)
            continue
        }

        if ($current.ContainsKey($m.Id)) { & $result $m 'Unchanged' "Already a $($label.ToLowerInvariant()) of the group."; continue }

        if ($Relation -eq 'Owners' -and @('User', 'ServicePrincipal') -notcontains $m.ObjectType) {
            & $result $m 'Failed' 'Only users and service principals can own a group.'; continue
        }
        if ($Relation -eq 'Members' -and $m.ObjectType -eq 'Group') {
            if ($m.Id -eq $Group.id) { & $result $m 'Failed' 'A group cannot be a member of itself.'; continue }
            if ($Group.GroupType -eq 'Microsoft365') { & $result $m 'Failed' 'Microsoft 365 groups cannot contain other groups.'; continue }
            if ($Group.PSObject.Properties['isAssignableToRole'] -and $Group.isAssignableToRole) {
                & $result $m 'Failed' 'Role-assignable groups cannot contain other groups.'; continue
            }
            # Circular nesting: is the target group already somewhere below the group we add?
            $nestedUri = New-ITGraphUri -Path ('groups/{0}/transitiveMembers/microsoft.graph.group' -f $m.Id) -Select 'id'
            $below = @(Invoke-ITGraphRequest -Uri $nestedUri -ApiVersion 'v1.0' -All | ForEach-Object { [string]$_.id })
            if ($below -contains $Group.id) {
                & $result $m 'Failed' "Circular nesting: '$($Group.displayName)' is already a nested member of '$($m.DisplayName)'."; continue
            }
        }
        $todo.Add($m)
    }

    if (-not $todo.Count) { return }

    # --- Remove: one request per member ----------------------------------------------------------
    if ($Mode -eq 'Remove') {
        foreach ($m in $todo) {
            try {
                $null = Invoke-ITGraphRequest -Uri ('groups/{0}/{1}/{2}/$ref' -f $Group.id, $segment, $m.Id) -Method DELETE -ApiVersion 'v1.0'
                Write-ITLog -Message ("Removed {0} '{1}' from group '{2}'." -f $label.ToLowerInvariant(), $m.DisplayName, $Group.displayName)
                & $result $m 'Removed' ''
            }
            catch {
                & $result $m 'Failed' $_.Exception.Message
            }
        }
        return
    }

    # --- Add: batches of 20, single retry on failure -------------------------------------------
    $bindKey = '{0}@odata.bind' -f $segment
    for ($i = 0; $i -lt $todo.Count; $i += 20) {
        $batch = @($todo.GetRange($i, [math]::Min(20, $todo.Count - $i)))
        try {
            $body = @{ $bindKey = @($batch | ForEach-Object { $bindBase + $_.Id }) }
            $null = Invoke-ITGraphRequest -Uri ('groups/{0}' -f $Group.id) -Method PATCH -Body $body -ApiVersion 'v1.0'
            Write-ITLog -Message ("Added {0} {1}(s) to group '{2}'." -f $batch.Count, $label.ToLowerInvariant(), $Group.displayName)
            foreach ($m in $batch) { & $result $m 'Added' '' }
        }
        catch {
            if ($batch.Count -eq 1) { & $result $batch[0] 'Failed' $_.Exception.Message; continue }
            Write-ITLog -Level Warning -Message "Batch add failed ($($_.Exception.Message)); retrying one by one."
            foreach ($m in $batch) {
                try {
                    $one = @{ '@odata.id' = $bindBase + $m.Id }
                    $null = Invoke-ITGraphRequest -Uri ('groups/{0}/{1}/$ref' -f $Group.id, $segment) -Method POST -Body $one -ApiVersion 'v1.0'
                    & $result $m 'Added' ''
                }
                catch {
                    & $result $m 'Failed' $_.Exception.Message
                }
            }
        }
    }
}
