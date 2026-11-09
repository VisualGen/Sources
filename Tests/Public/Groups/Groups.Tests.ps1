#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Entra ID groups, members (nested), memberships and owners. Graph is mocked by one dispatcher per test
# block: anything not handled answers like Graph does for an unknown object (HTTP 404).

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force

    function Set-FakeConnection {
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'
                Scopes = @('Group.ReadWrite.All', 'User.Read.All', 'Device.Read.All') }
        }
    }

    # IDs
    $script:G1 = '11111111-1111-1111-1111-111111111111'   # All Pilots (parent)
    $script:G2 = '22222222-2222-2222-2222-222222222222'   # Pilot Users
    $script:G3 = '33333333-3333-3333-3333-333333333333'   # dynamic
    $script:G4 = '44444444-4444-4444-4444-444444444444'   # Microsoft 365
    $script:U1 = 'aaaaaaaa-0000-0000-0000-000000000001'   # jane
    $script:U2 = 'aaaaaaaa-0000-0000-0000-000000000002'   # john
    $script:D1 = 'dddddddd-0000-0000-0000-000000000001'   # Entra device object
    $script:AAD1 = 'eeeeeeee-0000-0000-0000-000000000001' # Entra device ID (azureADDeviceId)

    function New-FakeGroup([string]$Id, [string]$Name, [string[]]$Types = @(), [bool]$Mail = $false, [bool]$Security = $true) {
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = $Id; displayName = $Name; groupTypes = $Types
            securityEnabled = $Security; mailEnabled = $Mail; isAssignableToRole = $false; onPremisesSyncEnabled = $null }
    }
    function New-FakeUser([string]$Id, [string]$Name, [string]$Upn) {
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = $Id; displayName = $Name; userPrincipalName = $Upn; accountEnabled = $true }
    }
    function New-FakeAssignment([string]$Type, [string]$GroupId, [string]$Intent, [string]$FilterId) {
        $t = [pscustomobject]@{ '@odata.type' = "#microsoft.graph.$Type" }
        if ($GroupId) { $t | Add-Member -NotePropertyName groupId -NotePropertyValue $GroupId }
        if ($FilterId) {
            $t | Add-Member -NotePropertyName deviceAndAppManagementAssignmentFilterId -NotePropertyValue $FilterId
            $t | Add-Member -NotePropertyName deviceAndAppManagementAssignmentFilterType -NotePropertyValue 'include'
        }
        $a = [pscustomobject]@{ id = [guid]::NewGuid().ToString(); target = $t }
        if ($Intent) { $a | Add-Member -NotePropertyName intent -NotePropertyValue $Intent }
        $a
    }
    function Stop-NotFound([string]$Uri) {
        throw "Graph request failed: GET $Uri -> HTTP 404 [Request_ResourceNotFound]: not found"
    }
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Get-ITGroup' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($Uri -like 'groups/*/members[?]*') { return @([pscustomobject]@{ id = 'm1' }, [pscustomobject]@{ id = 'm2' }) }
            if ($Uri -like "groups/$G1[?]*") { return (New-FakeGroup $G1 'SG-Intune-All-Pilots') }
            New-FakeGroup $G1 'SG-Intune-All-Pilots'
            New-FakeGroup $G3 'SG-Intune-Win-Dynamic' @('DynamicMembership')
            New-FakeGroup $G4 'Team Pilots' @('Unified') $true $false
            New-FakeGroup '55555555-5555-5555-5555-555555555555' 'Mail Security' @() $true $true
        }
    }

    It 'adds GroupType and MembershipType' {
        $all = Get-ITGroup
        ($all | Where-Object id -eq $G1).GroupType | Should -Be 'Security'
        ($all | Where-Object id -eq $G3).MembershipType | Should -Be 'Dynamic'
        ($all | Where-Object id -eq $G4).GroupType | Should -Be 'Microsoft365'
        ($all | Where-Object displayName -eq 'Mail Security').GroupType | Should -Be 'MailEnabledSecurity'
        $all[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.Group'
    }

    It 'sends a prefix as startswith and an exact name as eq' {
        $null = Get-ITGroup -Name 'SG-Intune-*'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*startswith%28displayName%2C%27SG-Intune-%27%29*' }
        $null = Get-ITGroup -Name 'SG-Intune-All-Pilots'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like '*displayName%20eq%20%27SG-Intune-All-Pilots%27*' }
    }

    It 'filters other wildcards locally' {
        $hit = @(Get-ITGroup -Name '*Pilots*')
        $hit.Count | Should -Be 2
    }

    It 'uses $search with ConsistencyLevel eventual' {
        $null = Get-ITGroup -Search 'pilot'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter {
            $Uri -like '*$search=*displayName%3Apilot*' -and $Headers.ConsistencyLevel -eq 'eventual'
        }
    }

    It 'applies -GroupType and -MembershipType exactly' {
        @(Get-ITGroup -GroupType Security).displayName | Should -Be @('SG-Intune-All-Pilots', 'SG-Intune-Win-Dynamic')
        @(Get-ITGroup -MembershipType Assigned).Count | Should -Be 3
    }

    It 'adds MemberCount' {
        (Get-ITGroup -Id $G1 -IncludeMemberCount).MemberCount | Should -Be 2
    }
}

Describe 'New-ITGroup' {
    BeforeEach {
        Set-FakeConnection
        $script:existing = @()
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($verb -eq 'POST' -and $Uri -eq 'groups') {
                $types = @($Body['groupTypes'])
                return (New-FakeGroup $G2 $Body['displayName'] $types)
            }
            if ($Uri -like 'groups[?]*') { return $script:existing }
            if ($Uri -like "users/jane%40contoso.com[?]*") { return (New-FakeUser $U1 'Jane' 'jane@contoso.com') }
            Stop-NotFound $Uri
        }
    }

    It 'creates an assigned security group with members bound in the same request' {
        $g = New-ITGroup -DisplayName 'SG Pilot Users!' -MemberId 'jane@contoso.com'
        $g.id | Should -Be $G2
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body['mailNickname'] -eq 'SGPilotUsers' -and $Body['securityEnabled'] -eq $true -and
            @($Body['members@odata.bind'])[0] -like "*/v1.0/directoryObjects/$U1"
        }
    }

    It 'creates a dynamic group' {
        $null = New-ITGroup -DisplayName 'SG-Win' -MembershipRule '(device.deviceOSType -eq "Windows")'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and @($Body['groupTypes']) -contains 'DynamicMembership' -and $Body['membershipRuleProcessingState'] -eq 'On'
        }
    }

    It 'creates a Microsoft 365 group' {
        $null = New-ITGroup -DisplayName 'Team' -GroupType Microsoft365 -Visibility Private
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and @($Body['groupTypes']) -contains 'Unified' -and $Body['mailEnabled'] -eq $true -and $Body['visibility'] -eq 'Private'
        }
    }

    It 'stops when the name exists, unless -AllowDuplicate' {
        $script:existing = @([pscustomobject]@{ id = $G1 })
        New-ITGroup -DisplayName 'SG-Pilot' -ErrorAction SilentlyContinue -ErrorVariable err | Should -BeNullOrEmpty
        $err[0].Exception.Message | Should -Match 'already exists'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
        $null = New-ITGroup -DisplayName 'SG-Pilot' -AllowDuplicate
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'refuses members on a dynamic group and does nothing with -WhatIf' {
        New-ITGroup -DisplayName 'X' -MembershipRule 'r' -MemberId 'jane@contoso.com' -ErrorAction SilentlyContinue -ErrorVariable err
        $err[0].Exception.Message | Should -Match 'dynamic'
        New-ITGroup -DisplayName 'Y' -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
}

Describe 'Set-ITGroup / Rename-ITGroup / Remove-ITGroup' {
    BeforeEach {
        Set-FakeConnection
        $script:other = @()
        $script:synced = $null
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($verb -in 'PATCH', 'DELETE') { return }
            if ($Uri -like "groups/$G2[?]*") { $g = New-FakeGroup $G2 'Pilot Users'; $g.onPremisesSyncEnabled = $script:synced; return $g }
            if ($Uri -like "groups/$G3[?]*") { return (New-FakeGroup $G3 'Dyn' @('DynamicMembership')) }
            if ($Uri -like 'groups[?]*') { return $script:other }
            Stop-NotFound $Uri
        }
    }

    It 'renames and changes the description in one PATCH' {
        Set-ITGroup -Id $G2 -DisplayName 'SG-Pilot-Users' -Description 'Pilot ring'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq "groups/$G2" -and $Body['displayName'] -eq 'SG-Pilot-Users' -and $Body['description'] -eq 'Pilot ring'
        }
    }

    It 'refuses a rename to a name another group has' {
        $script:other = @([pscustomobject]@{ id = $G1 })
        Rename-ITGroup -Id $G2 -NewName 'Taken' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err[0].Exception.Message | Should -Match 'already exists'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'Rename-ITGroup sends the new name' {
        Rename-ITGroup -Id $G2 -NewName 'SG-New' -Confirm:$false
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body['displayName'] -eq 'SG-New' }
    }

    It 'turns an assigned group into a dynamic one and back' {
        Set-ITGroup -Id $G2 -MembershipRule '(user.department -eq "IT")'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter {
            $Method -eq 'PATCH' -and @($Body['groupTypes']) -contains 'DynamicMembership' -and $Body['membershipRuleProcessingState'] -eq 'On'
        }
        Set-ITGroup -Id $G3 -ConvertToAssigned
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq "groups/$G3" -and @($Body['groupTypes']).Count -eq 0
        }
    }

    It 'sends nothing when nothing changes, and refuses synced groups' {
        Set-ITGroup -Id $G2 -DisplayName 'Pilot Users'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        $script:synced = $true
        Set-ITGroup -Id $G2 -Description 'x' -ErrorAction SilentlyContinue -ErrorVariable err
        $err[0].Exception.Message | Should -Match 'on-premises'
    }

    It 'deletes a group' {
        Remove-ITGroup -Id $G2 -Confirm:$false
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq "groups/$G2" }
    }
}

Describe 'Get-ITGroupMember' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($Uri -like "groups/$G1[?]*") { return (New-FakeGroup $G1 'All Pilots') }
            if ($Uri -like "groups/$G1/members[?]*") { return @((New-FakeUser $U1 'Jane' 'jane@contoso.com'), (New-FakeGroup $G2 'Pilot Users')) }
            # G2 contains John and (circular) the parent G1
            if ($Uri -like "groups/$G2/members[?]*") { return @((New-FakeUser $U2 'John' 'john@contoso.com'), (New-FakeGroup $G1 'All Pilots')) }
            if ($Uri -like "groups/$G1/transitiveMembers[?]*") {
                return @((New-FakeUser $U1 'Jane' 'jane@contoso.com'), (New-FakeGroup $G2 'Pilot Users'), (New-FakeUser $U2 'John' 'john@contoso.com'))
            }
            Stop-NotFound $Uri
        }
    }

    It 'lists direct members' {
        $m = @(Get-ITGroupMember -Id $G1)
        $m.Count | Should -Be 2
        $m[0].MemberType | Should -Be 'User'
        $m[0].GroupName | Should -Be 'All Pilots'
        $m[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.GroupMember'
    }

    It 'walks nested groups with depth and path, and stops at circular nesting' {
        $m = @(Get-ITGroupMember -Id $G1 -Recurse)
        $m.Count | Should -Be 4
        $john = $m | Where-Object id -eq $U2
        $john.Depth | Should -Be 2
        $john.ParentGroupName | Should -Be 'Pilot Users'
        $john.Path | Should -Be 'All Pilots > Pilot Users'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like "groups/$G1/members[?]*" }
    }

    It 'filters on member type but still follows nested groups' {
        @(Get-ITGroupMember -Id $G1 -Recurse -MemberType User).displayName | Should -Be @('Jane', 'John')
    }

    It 'uses transitiveMembers with -Transitive' {
        @(Get-ITGroupMember -Id $G1 -Transitive).Count | Should -Be 3
        { Get-ITGroupMember -Id $G1 -Transitive -Recurse } | Should -Throw '*not both*'
    }
}

Describe 'Add-ITGroupMember / Remove-ITGroupMember' {
    BeforeEach {
        Set-FakeConnection
        $script:patchFails = $false
        $script:many = @{}
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($verb -eq 'PATCH') { if ($script:patchFails) { throw 'Graph request failed: PATCH -> HTTP 400 [Request_BadRequest]: one bad member' }; return }
            if ($verb -eq 'POST') { if ($Body['@odata.id'] -like "*$U2") { throw 'Graph request failed: POST -> HTTP 400: bad' }; return }
            if ($verb -eq 'DELETE') { return }
            if ($Uri -like "groups/$G1[?]*") { return (New-FakeGroup $G1 'All Pilots') }
            if ($Uri -like "groups/$G2[?]*") { return (New-FakeGroup $G2 'Pilot Users') }
            if ($Uri -like "groups/$G3[?]*") { return (New-FakeGroup $G3 'Dyn' @('DynamicMembership')) }
            if ($Uri -like "groups/$G4[?]*") { return (New-FakeGroup $G4 'Team' @('Unified') $true $false) }
            if ($Uri -like "groups/$G2/members[?]*") { return @([pscustomobject]@{ id = $U1 }) }
            if ($Uri -like 'groups/*/members[?]*') { return @() }
            # Below G1 sits G2: adding G1 into G2 would be circular
            if ($Uri -like "groups/$G1/transitiveMembers/microsoft.graph.group[?]*") { return @([pscustomobject]@{ id = $G2 }) }
            if ($Uri -like 'groups/*/transitiveMembers/microsoft.graph.group[?]*') { return @() }
            if ($Uri -like 'users/jane%40contoso.com[?]*') { return (New-FakeUser $U1 'Jane' 'jane@contoso.com') }
            if ($Uri -like "users/$U2[?]*") { return (New-FakeUser $U2 'John' 'john@contoso.com') }
            if ($Uri -match '^users/(aaaaaaaa-1111-[^?]+)\?') { return (New-FakeUser $Matches[1] 'Bulk' 'b@c.com') }
            if ($Uri -like 'devices[?]*') { return [pscustomobject]@{ id = $D1; displayName = 'PC1' } }
            Stop-NotFound $Uri
        }
    }

    It 'skips existing members and adds the rest in one PATCH' {
        $r = Add-ITGroupMember -GroupId $G2 -MemberId 'jane@contoso.com', $U2
        ($r | Where-Object MemberId -eq $U1).Status | Should -Be 'Unchanged'
        ($r | Where-Object MemberId -eq $U2).Status | Should -Be 'Added'
        $r[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.GroupMemberChange'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq "groups/$G2" -and @($Body['members@odata.bind']).Count -eq 1 -and @($Body['members@odata.bind'])[0] -like "*directoryObjects/$U2"
        }
    }

    It 'adds in batches of 20' {
        $ids = 1..25 | ForEach-Object { 'aaaaaaaa-1111-0000-0000-{0:D12}' -f $_ }
        $r = Add-ITGroupMember -GroupId $G1 -MemberId $ids
        @($r | Where-Object Status -eq 'Added').Count | Should -Be 25
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'retries one by one when a batch fails' {
        $script:patchFails = $true
        $r = Add-ITGroupMember -GroupId $G1 -MemberId 'jane@contoso.com', $U2 -ErrorAction SilentlyContinue -ErrorVariable err
        ($r | Where-Object MemberId -eq $U1).Status | Should -Be 'Added'
        ($r | Where-Object MemberId -eq $U2).Status | Should -Be 'Failed'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -eq "groups/$G1/members/`$ref" }
        @($err).Count | Should -BeGreaterThan 0
    }

    It 'nests a group and refuses circular nesting' {
        (Add-ITGroupMember -GroupId $G1 -MemberId $G2).Status | Should -Be 'Added'
        $r = Add-ITGroupMember -GroupId $G2 -MemberId $G1 -ErrorAction SilentlyContinue
        $r.Status | Should -Be 'Failed'
        $r.Message | Should -Match 'Circular'
    }

    It 'refuses dynamic groups and groups inside Microsoft 365 groups' {
        (Add-ITGroupMember -GroupId $G3 -MemberId 'jane@contoso.com' -ErrorAction SilentlyContinue).Message | Should -Match 'dynamic'
        (Add-ITGroupMember -GroupId $G4 -MemberId $G2 -ErrorAction SilentlyContinue).Message | Should -Match 'Microsoft 365'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'resolves Intune managed devices from the pipeline by azureADDeviceId' {
        $md = [pscustomobject]@{ id = 'md1'; deviceName = 'PC1'; azureADDeviceId = $AAD1 }
        $r = $md | Add-ITGroupMember -GroupId $G1
        $r.MemberId | Should -Be $D1
        $r.MemberType | Should -Be 'Device'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Uri -like "devices[?]*deviceId%20eq%20%27$AAD1%27*" }
    }

    It 'does nothing with -WhatIf' {
        Add-ITGroupMember -GroupId $G1 -MemberId $U2 -WhatIf
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -in 'PATCH', 'POST' }
    }

    It 'removes direct members and reports non-members as Unchanged' {
        $r = Remove-ITGroupMember -GroupId $G2 -MemberId 'jane@contoso.com', $U2 -Confirm:$false
        ($r | Where-Object MemberId -eq $U1).Status | Should -Be 'Removed'
        ($r | Where-Object MemberId -eq $U2).Status | Should -Be 'Unchanged'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq "groups/$G2/members/$U1/`$ref" }
    }
}

Describe 'Owners' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($verb -in 'PATCH', 'DELETE') { return }
            if ($Uri -like "groups/$G2[?]*") { return (New-FakeGroup $G2 'Pilot Users') }
            if ($Uri -like "groups/$G2/owners[?]*") { return @(New-FakeUser $U1 'Jane' 'jane@contoso.com') }
            if ($Uri -like 'users/jane%40contoso.com[?]*') { return (New-FakeUser $U1 'Jane' 'jane@contoso.com') }
            if ($Uri -like "users/$U2[?]*") { return (New-FakeUser $U2 'John' 'john@contoso.com') }
            if ($Uri -like 'devices[?]*') { return [pscustomobject]@{ id = $D1; displayName = 'PC1' } }
            Stop-NotFound $Uri
        }
    }

    It 'lists owners' {
        $o = Get-ITGroupOwner -Id $G2
        $o.userPrincipalName | Should -Be 'jane@contoso.com'
        $o.MemberType | Should -Be 'User'
    }

    It 'adds users as owners and refuses devices' {
        (Add-ITGroupOwner -GroupId $G2 -MemberId $U2).Status | Should -Be 'Added'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -ParameterFilter { $Method -eq 'PATCH' -and @($Body['owners@odata.bind'])[0] -like "*$U2" }
        $md = [pscustomobject]@{ id = 'md1'; azureADDeviceId = $AAD1 }
        ($md | Add-ITGroupOwner -GroupId $G2 -ErrorAction SilentlyContinue).Status | Should -Be 'Failed'
    }

    It 'removes an owner' {
        (Remove-ITGroupOwner -GroupId $G2 -MemberId 'jane@contoso.com' -Confirm:$false).Status | Should -Be 'Removed'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "groups/$G2/owners/$U1/`$ref" }
    }
}

Describe 'Get-ITGroupMembership' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($Uri -like 'users/jane%40contoso.com[?]*') { return (New-FakeUser $U1 'Jane' 'jane@contoso.com') }
            if ($Uri -like "users/$U1/memberOf/microsoft.graph.group[?]*") { return @(New-FakeGroup $G2 'Pilot Users') }
            if ($Uri -like "users/$U1/transitiveMemberOf/microsoft.graph.group[?]*") { return @((New-FakeGroup $G2 'Pilot Users'), (New-FakeGroup $G1 'All Pilots')) }
            Stop-NotFound $Uri
        }
    }

    It 'lists direct memberships' {
        $m = Get-ITGroupMembership -Identity 'jane@contoso.com'
        $m.displayName | Should -Be 'Pilot Users'
        $m.Direct | Should -BeTrue
        $m.MemberName | Should -Be 'Jane'
        $m.PSObject.TypeNames | Should -Contain 'IntuneToolkit.Group'
    }

    It 'marks memberships through nesting as not direct' {
        $m = @(Get-ITGroupMembership -Identity 'jane@contoso.com' -Transitive)
        $m.Count | Should -Be 2
        ($m | Where-Object id -eq $G1).Direct | Should -BeFalse
        ($m | Where-Object id -eq $G2).Direct | Should -BeTrue
    }
}

Describe 'Resolve-ITDirectoryObject' {
    BeforeEach {
        Set-FakeConnection
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            $verb = 'GET'; if (Test-Path -Path 'variable:Method') { $verb = $Method }
            if ($Uri -like "devices[?]*$AAD1*") { return [pscustomobject]@{ id = $D1; displayName = 'PC1' } }
            if ($Uri -like 'groups[?]*') { return @([pscustomobject]@{ id = 'x1'; displayName = 'Dup' }, [pscustomobject]@{ id = 'x2'; displayName = 'Dup' }) }
            Stop-NotFound $Uri
        }
    }

    It 'falls back from object ID to Entra device ID' {
        InModuleScope IntuneToolkit -Parameters @{ Id = $AAD1; Expected = $D1 } {
            param($Id, $Expected)
            $r = Resolve-ITDirectoryObject -InputObject $Id
            $r.Id | Should -Be $Expected
            $r.ObjectType | Should -Be 'Device'
        }
    }

    It 'refuses an ambiguous group name' {
        InModuleScope IntuneToolkit {
            { Resolve-ITDirectoryObject -InputObject 'Dup' } | Should -Throw '*2 groups*'
        }
    }

    It 'refuses a device that is not registered in Entra ID' {
        InModuleScope IntuneToolkit {
            $md = [pscustomobject]@{ id = 'md1'; azureADDeviceId = '00000000-0000-0000-0000-000000000000' }
            { Resolve-ITDirectoryObject -InputObject $md } | Should -Throw '*not registered*'
        }
    }
}

Describe 'Get-ITGroupAssignment' {
    BeforeEach {
        Mock -ModuleName IntuneToolkit Get-MgContext {
            [pscustomobject]@{ TenantId = 't1'; Account = 'admin@contoso.com'; AuthType = 'Delegated'
                Scopes = @('Group.Read.All', 'DeviceManagementConfiguration.Read.All', 'DeviceManagementApps.Read.All') }
        }
        Mock -ModuleName IntuneToolkit Invoke-ITGraphRequest {
            if ($Uri -like "groups/$G2[?]*") { return (New-FakeGroup $G2 'Pilot Users') }
            if ($Uri -like "groups/$G2/transitiveMemberOf/microsoft.graph.group[?]*") { return @([pscustomobject]@{ id = $G1; displayName = 'All Pilots' }) }
            if ($Uri -like "groups/$G1[?]*") { return (New-FakeGroup $G1 'All Pilots') }
            if ($Uri -like "groups/$G1/transitiveMemberOf/microsoft.graph.group[?]*") { return @() }
            if ($Uri -eq 'deviceManagement/deviceCompliancePolicies?$expand=assignments') {
                return [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; id = 'c1'; displayName = 'Win - Baseline'
                    assignments = @((New-FakeAssignment 'groupAssignmentTarget' $G2), (New-FakeAssignment 'groupAssignmentTarget' $G3),
                        (New-FakeAssignment 'exclusionGroupAssignmentTarget' $G1)) }
            }
            if ($Uri -eq 'deviceManagement/configurationPolicies?$expand=assignments') {
                return [pscustomobject]@{ id = 's1'; name = 'Win - Edge'; platforms = 'windows10'
                    assignments = @((New-FakeAssignment 'allDevicesAssignmentTarget'), (New-FakeAssignment 'groupAssignmentTarget' $G1 '' 'f1')) }
            }
            if ($Uri -eq 'deviceAppManagement/mobileApps?$expand=assignments') {
                return [pscustomobject]@{ '@odata.type' = '#microsoft.graph.win32LobApp'; id = 'a1'; displayName = '7-Zip'
                    assignments = @(New-FakeAssignment 'groupAssignmentTarget' $G2 'required') }
            }
            # Scripts: Graph leaves the expanded assignments out -> read per object
            if ($Uri -like 'deviceManagement/deviceManagementScripts*' -and $Uri -notlike '*/assignments') {
                return [pscustomobject]@{ id = 'sc1'; displayName = 'Set time zone' }
            }
            if ($Uri -eq 'deviceManagement/deviceManagementScripts/sc1/assignments') { return @(New-FakeAssignment 'groupAssignmentTarget' $G2) }
            if ($Uri -eq 'deviceManagement/assignmentFilters') { return [pscustomobject]@{ id = 'f1'; displayName = 'Windows 11' } }
            if ($Uri -like 'deviceManagement/*' -or $Uri -like 'deviceAppManagement/*') { return }
            Stop-NotFound $Uri
        }
    }

    It 'returns direct and parent-group assignments, inclusions and exclusions' {
        $r = @(Get-ITGroupAssignment -Id $G2)
        $r.Count | Should -Be 5
        $r[0].PSObject.TypeNames[0] | Should -Be 'IntuneToolkit.GroupAssignment'
        $c = @($r | Where-Object ObjectId -eq 'c1')
        ($c | Where-Object Via -eq 'Direct').Intent | Should -Be 'Include'
        $ex = $c | Where-Object Via -eq 'Parent group'
        $ex.Intent | Should -Be 'Exclude'
        $ex.ViaGroupName | Should -Be 'All Pilots'
        ($r | Where-Object ObjectId -eq 'a1').InstallIntent | Should -Be 'required'
        $s = $r | Where-Object ObjectId -eq 's1'
        $s.ObjectName | Should -Be 'Win - Edge'
        $s.FilterName | Should -Be 'Windows 11'
    }

    It 'falls back to per-object reads when the expand is left out' {
        (Get-ITGroupAssignment -Id $G2 -PolicyType Script).ObjectName | Should -Be 'Set time zone'
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'deviceManagement/deviceManagementScripts/sc1/assignments' }
    }

    It 'skips parent groups with -DirectOnly and adds All devices with -IncludeAllTargets' {
        @(Get-ITGroupAssignment -Id $G2 -DirectOnly).Count | Should -Be 3
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*transitiveMemberOf*' }
        $all = @(Get-ITGroupAssignment -Id $G2 -IncludeAllTargets)
        $all.Count | Should -Be 6
        ($all | Where-Object Via -eq 'AllDevices').ObjectId | Should -Be 's1'
    }

    It 'reads the Intune objects once for several groups' {
        $r = @([pscustomobject]@{ id = $G2 }, [pscustomobject]@{ id = $G1 } | Get-ITGroupAssignment -PolicyType Compliance)
        @($r | Where-Object GroupId -eq $G1).Count | Should -Be 1
        Should -Invoke -ModuleName IntuneToolkit Invoke-ITGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'deviceManagement/deviceCompliancePolicies?$expand=assignments' }
    }
}
