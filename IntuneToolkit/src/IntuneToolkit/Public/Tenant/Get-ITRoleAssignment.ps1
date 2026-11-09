function Get-ITRoleAssignment {
    <#
    .SYNOPSIS
        Gets Intune RBAC role assignments: who (admin groups) has which role, on which scope.

    .DESCRIPTION
        Returns one row per role assignment with RoleName, Members (admin group IDs),
        ScopeMembers (groups the admins may manage), ScopeType (allDevices, allLicensedUsers,
        resourceScope) and ScopeTagIds. -ResolveName adds MemberNames, ScopeMemberNames and
        ScopeTagNames (needs Group.Read.All). Use it for the monthly access review.

    .PARAMETER RoleName
        Only assignments of roles whose name matches (wildcards allowed).

    .PARAMETER ResolveName
        Translate group and scope tag IDs to names.

    .EXAMPLE
        Get-ITRoleAssignment -ResolveName | Select-Object RoleName, displayName, MemberNames, ScopeMemberNames, ScopeTagNames

    .EXAMPLE
        Get-ITRoleAssignment -RoleName 'Intune Administrator*'

    .OUTPUTS
        IntuneToolkit.RoleAssignment

    .NOTES
        Graph permission : DeviceManagementRBAC.Read.All (+ Group.Read.All for -ResolveName)
        Graph endpoint   : GET /deviceManagement/roleDefinitions, /deviceManagement/roleDefinitions/{id}/roleAssignments,
                           /deviceManagement/roleAssignments/{id}
        API version      : beta

    .LINK
        Get-ITRoleDefinition
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.RoleAssignment')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$RoleName,

        [switch]$ResolveName
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementRBAC.Read.All'
    $get = { param($o, $n) if ($o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }

    $groupCache = @{}
    $resolveGroups = {
        param([string[]]$ids)
        foreach ($gid in @($ids | Where-Object { $_ })) {
            if (-not $groupCache.ContainsKey($gid)) {
                try { $groupCache[$gid] = (Invoke-ITGraphRequest -Uri ('groups/{0}?$select=displayName' -f $gid) -ApiVersion 'v1.0').displayName }
                catch { $groupCache[$gid] = $gid }
            }
            $groupCache[$gid]
        }
    }
    $tagNames = @{}
    if ($ResolveName) {
        try {
            foreach ($tag in @(Invoke-ITGraphRequest -Uri 'deviceManagement/roleScopeTags' -ApiVersion 'beta' -All)) { $tagNames[[string]$tag.id] = $tag.displayName }
        }
        catch {
            Write-Warning -Message "Scope tags not read: $($_.Exception.Message)"
        }
    }

    # roleAssignments list does not return the role; go through the definitions
    $roles = @(Invoke-ITGraphRequest -Uri 'deviceManagement/roleDefinitions' -ApiVersion 'beta' -All)
    if ($RoleName) { $roles = @($roles | Where-Object { $_.displayName -like $RoleName }) }

    foreach ($role in $roles) {
        try {
            $links = @(Invoke-ITGraphRequest -Uri ('deviceManagement/roleDefinitions/{0}/roleAssignments' -f $role.id) -ApiVersion 'beta' -All)
        }
        catch {
            Write-Error -ErrorRecord $_
            continue
        }
        foreach ($link in @($links | Where-Object { $_ })) {
            try {
                $assignment = Invoke-ITGraphRequest -Uri ('deviceManagement/roleAssignments/{0}' -f $link.id) -ApiVersion 'beta'
            }
            catch {
                Write-Error -ErrorRecord $_
                continue
            }
            $members = @(& $get $assignment 'members' | Where-Object { $_ })
            $scopeMembers = @(& $get $assignment 'scopeMembers' | Where-Object { $_ })
            $tags = @(& $get $assignment 'roleScopeTagIds' | Where-Object { $null -ne $_ })
            $out = [ordered]@{
                PSTypeName    = 'IntuneToolkit.RoleAssignment'
                displayName   = & $get $assignment 'displayName'
                RoleName      = $role.displayName
                RoleId        = $role.id
                IsBuiltInRole = [bool](& $get $role 'isBuiltIn')
                Members       = $members
                ScopeMembers  = $scopeMembers
                ScopeType     = & $get $assignment 'scopeType'
                ScopeTagIds   = $tags
                id            = $assignment.id
            }
            if ($ResolveName) {
                $out['MemberNames']      = @(& $resolveGroups $members)
                $out['ScopeMemberNames'] = @(& $resolveGroups $scopeMembers)
                $out['ScopeTagNames']    = @($tags | ForEach-Object { if ($tagNames.ContainsKey([string]$_)) { $tagNames[[string]$_] } else { $_ } })
            }
            [pscustomobject]$out
        }
    }
}
