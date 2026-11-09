function New-ITGroup {
    <#
    .SYNOPSIS
        Creates an Entra ID (Azure AD) security or Microsoft 365 group, assigned or dynamic.

    .DESCRIPTION
        Creates the group and optionally adds owners and members in the same step. With
        -MembershipRule the group gets dynamic membership (members come from the rule).

        Entra ID allows several groups with the same name, which makes Intune assignments hard
        to read. New-ITGroup therefore stops when a group with the same name exists, unless
        -AllowDuplicate is used.

        Members can be users (UPN or ID), groups (ID or exact name: nested groups) or devices
        (Entra object ID, Entra device ID or exact name). Up to 20 are added during creation,
        the rest right after it.

    .PARAMETER DisplayName
        Name of the new group.

    .PARAMETER Description
        Group description.

    .PARAMETER GroupType
        Security (default) or Microsoft365.

    .PARAMETER MailNickname
        Mail alias. Default: the display name without spaces and special characters.

    .PARAMETER MembershipRule
        Dynamic membership rule, for example
        '(device.deviceOSType -eq "Windows") and (device.deviceOwnership -eq "Company")'.

    .PARAMETER MembershipRuleProcessingState
        On (default) or Paused. Only with -MembershipRule.

    .PARAMETER IsAssignableToRole
        Allow the group to be assigned to Entra ID roles. Cannot be changed later, cannot be
        dynamic and cannot contain other groups. Needs RoleManagement.ReadWrite.Directory.

    .PARAMETER Visibility
        Private (default) or Public. Microsoft 365 groups only.

    .PARAMETER OwnerId
        Owners: UPNs or object IDs of users or service principals.

    .PARAMETER MemberId
        Members: UPNs, object IDs, Entra device IDs, or exact group/device names.

    .PARAMETER AllowDuplicate
        Create the group even if another group already has this name.

    .EXAMPLE
        New-ITGroup -DisplayName 'SG-Intune-Pilot-Users' -Description 'Pilot ring users' -MemberId 'jane@contoso.com', 'john@contoso.com'

        Assigned security group with two members.

    .EXAMPLE
        New-ITGroup -DisplayName 'SG-Intune-Win-Corporate' -MembershipRule '(device.deviceOSType -eq "Windows") and (device.deviceOwnership -eq "Company")'

        Dynamic device group with all corporate Windows devices.

    .EXAMPLE
        New-ITGroup -DisplayName 'SG-Intune-All-Pilots' -MemberId 'SG-Intune-Pilot-Users', 'SG-Intune-Pilot-Devices'

        Group that contains two other groups (nested).

    .OUTPUTS
        IntuneToolkit.Group

    .NOTES
        Graph permission : Group.ReadWrite.All (+ User.Read.All / Device.Read.All to resolve members)
        Graph endpoint   : POST /groups
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-post-groups
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.Group')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateLength(1, 256)]
        [string]$DisplayName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Description,

        [ValidateSet('Security', 'Microsoft365')]
        [string]$GroupType = 'Security',

        [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
        [string]$MailNickname,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$MembershipRule,

        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState = 'On',

        [switch]$IsAssignableToRole,

        [ValidateSet('Private', 'Public')]
        [string]$Visibility,

        [string[]]$OwnerId,

        [string[]]$MemberId,

        [switch]$AllowDuplicate
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.ReadWrite.All'
        $cache = @{}
        $bindBase = '{0}/v1.0/directoryObjects/' -f $script:ITConfig.GraphBaseUri.TrimEnd('/')
    }

    process {
        # --- Validation ---------------------------------------------------------------------
        if ($MembershipRule -and $MemberId) { Write-Error "'$DisplayName': a dynamic group cannot have -MemberId (members come from the rule)."; return }
        if ($MembershipRule -and $IsAssignableToRole) { Write-Error "'$DisplayName': a role-assignable group cannot be dynamic."; return }
        if ($Visibility -and $GroupType -ne 'Microsoft365') { Write-Error "'$DisplayName': -Visibility applies to Microsoft 365 groups only."; return }

        if (-not $AllowDuplicate) {
            $dupUri = New-ITGraphUri -Path 'groups' -Filter ("displayName eq '{0}'" -f (ConvertTo-ITODataString $DisplayName)) -Select 'id'
            $existing = @(Invoke-ITGraphRequest -Uri $dupUri -ApiVersion 'v1.0')
            if ($existing.Count) {
                Write-Error "A group named '$DisplayName' already exists ($($existing[0].id)). Use -AllowDuplicate to create another one."
                return
            }
        }

        $nickname = $MailNickname
        if (-not $nickname) {
            $nickname = ($DisplayName -replace '[^A-Za-z0-9._-]', '')
            if ($nickname.Length -gt 64) { $nickname = $nickname.Substring(0, 64) }
            if (-not $nickname) { $nickname = 'group' + [guid]::NewGuid().ToString('N').Substring(0, 8) }
        }

        $body = [ordered]@{
            displayName     = $DisplayName
            mailNickname    = $nickname
            securityEnabled = $true
            mailEnabled     = $false
            groupTypes      = @()
        }
        if ($Description) { $body['description'] = $Description }
        if ($GroupType -eq 'Microsoft365') {
            $body['mailEnabled'] = $true
            $body['securityEnabled'] = $false
            $body['groupTypes'] = @('Unified')
            if ($Visibility) { $body['visibility'] = $Visibility }
        }
        if ($MembershipRule) {
            $body['groupTypes'] = @(@($body['groupTypes']) + 'DynamicMembership')
            $body['membershipRule'] = $MembershipRule
            $body['membershipRuleProcessingState'] = $MembershipRuleProcessingState
        }
        if ($IsAssignableToRole) { $body['isAssignableToRole'] = $true }

        if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create $GroupType group")) { return }

        # --- Resolve owners and members -------------------------------------------------------
        try {
            $owners  = @($OwnerId | Where-Object { $_ } | ForEach-Object { Resolve-ITDirectoryObject -InputObject $_ -Cache $cache })
            $members = @($MemberId | Where-Object { $_ } | ForEach-Object { Resolve-ITDirectoryObject -InputObject $_ -Cache $cache })
        }
        catch {
            Write-Error "'$DisplayName' was not created: $($_.Exception.Message)"
            return
        }
        $badOwner = @($owners | Where-Object { @('User', 'ServicePrincipal') -notcontains $_.ObjectType })
        if ($badOwner.Count) { Write-Error "'$DisplayName' was not created: only users and service principals can own a group ($($badOwner[0].DisplayName))."; return }
        $groupMembers = @($members | Where-Object { $_.ObjectType -eq 'Group' })
        if ($groupMembers.Count -and ($GroupType -eq 'Microsoft365' -or $IsAssignableToRole)) {
            Write-Error "'$DisplayName' was not created: Microsoft 365 and role-assignable groups cannot contain other groups."
            return
        }

        if ($owners.Count)  { $body['owners@odata.bind']  = @($owners | Select-Object -First 20 | ForEach-Object { $bindBase + $_.Id }) }
        if ($members.Count) { $body['members@odata.bind'] = @($members | Select-Object -First 20 | ForEach-Object { $bindBase + $_.Id }) }

        # --- Create ------------------------------------------------------------------------------
        try {
            $created = Invoke-ITGraphRequest -Uri 'groups' -Method POST -Body $body -ApiVersion 'v1.0' | ConvertTo-ITGroupObject
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }
        Write-ITLog -Message ("Created group '{0}' ({1})." -f $created.displayName, $created.id)

        # --- Members/owners beyond the first 20 ----------------------------------------------
        foreach ($extra in @(@('Members', $members), @('Owners', $owners))) {
            $rest = @($extra[1] | Select-Object -Skip 20)
            if (-not $rest.Count) { continue }
            # Failures are written as errors by the helper; the group itself exists
            $null = Invoke-ITGroupLinkChange -Group $created -Relation $extra[0] -Mode Add -Member $rest
        }

        $created
    }
}
