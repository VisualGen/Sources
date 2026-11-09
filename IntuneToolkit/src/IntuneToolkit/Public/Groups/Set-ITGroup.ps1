function Set-ITGroup {
    <#
    .SYNOPSIS
        Changes an Entra ID group: name, description, alias, dynamic rule or membership type.

    .DESCRIPTION
        Only the parameters you pass are changed.

        -MembershipRule on an assigned group turns it into a dynamic group: its current members
        are replaced by the result of the rule. -ConvertToAssigned turns a dynamic group into an
        assigned group: the members it has at that moment stay, the rule stops.

        Renaming checks that no other group has the new name, unless -AllowDuplicate is used.
        Groups synced from on-premises Active Directory must be changed there.

    .PARAMETER Id
        Group object ID or exact display name. Accepts pipeline input by property name (id / GroupId).

    .PARAMETER DisplayName
        New display name (rename). Alias: NewName.

    .PARAMETER Description
        New description. Use '' to clear it.

    .PARAMETER MailNickname
        New mail alias.

    .PARAMETER MembershipRule
        New dynamic membership rule (makes the group dynamic).

    .PARAMETER MembershipRuleProcessingState
        On or Paused: start or pause the evaluation of the dynamic rule.

    .PARAMETER ConvertToAssigned
        Turn a dynamic group into an assigned group (keeps the current members).

    .PARAMETER Visibility
        Private or Public (Microsoft 365 groups).

    .PARAMETER AllowDuplicate
        Allow renaming to a name another group already has.

    .PARAMETER PassThru
        Return the updated group.

    .EXAMPLE
        Set-ITGroup -Id 'SG-Intune-Pilot' -DisplayName 'SG-Intune-Pilot-Users' -Description 'Pilot ring - users'

        Renames a group and changes its description.

    .EXAMPLE
        Get-ITGroup -Name 'SG-Intune-Win-*' -MembershipType Dynamic | Set-ITGroup -MembershipRuleProcessingState Paused -WhatIf

        Previews pausing the dynamic rule of several groups.

    .OUTPUTS
        IntuneToolkit.Group (with -PassThru)

    .NOTES
        Graph permission : Group.ReadWrite.All
        Graph endpoint   : PATCH /groups/{id}
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-update
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.Group')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Alias('NewName')]
        [ValidateLength(1, 256)]
        [string]$DisplayName,

        [AllowEmptyString()]
        [string]$Description,

        [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
        [string]$MailNickname,

        [ValidateNotNullOrEmpty()]
        [string]$MembershipRule,

        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState,

        [switch]$ConvertToAssigned,

        [ValidateSet('Private', 'Public')]
        [string]$Visibility,

        [switch]$AllowDuplicate,

        [switch]$PassThru
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.ReadWrite.All'
    }

    process {
        try {
            $group = Resolve-ITGroup -Identity $Id
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }
        $name = $group.displayName

        if ($MembershipRule -and $ConvertToAssigned) { Write-Error "'$name': use -MembershipRule or -ConvertToAssigned, not both."; return }
        if ($group.PSObject.Properties['onPremisesSyncEnabled'] -and $group.onPremisesSyncEnabled) {
            Write-Error "'$name' is synced from on-premises Active Directory; change it there."
            return
        }

        $body = [ordered]@{}
        $changes = New-Object -TypeName System.Collections.Generic.List[string]

        if ($PSBoundParameters.ContainsKey('DisplayName') -and $DisplayName -cne $name) {
            if (-not $AllowDuplicate) {
                $dupUri = New-ITGraphUri -Path 'groups' -Filter ("displayName eq '{0}'" -f (ConvertTo-ITODataString $DisplayName)) -Select 'id'
                $other = @(Invoke-ITGraphRequest -Uri $dupUri -ApiVersion 'v1.0' | Where-Object { $_.id -ne $group.id })
                if ($other.Count) { Write-Error "Cannot rename '$name': a group named '$DisplayName' already exists ($($other[0].id)). Use -AllowDuplicate."; return }
            }
            $body['displayName'] = $DisplayName
            $changes.Add("rename to '$DisplayName'")
        }
        if ($PSBoundParameters.ContainsKey('Description')) {
            if ($Description) { $body['description'] = $Description } else { $body['description'] = $null }
            $changes.Add('description')
        }
        if ($MailNickname) { $body['mailNickname'] = $MailNickname; $changes.Add('mail alias') }
        if ($Visibility)   { $body['visibility'] = $Visibility; $changes.Add("visibility $Visibility") }

        $types = @($group.groupTypes | Where-Object { $_ })
        if ($MembershipRule) {
            if ($group.PSObject.Properties['isAssignableToRole'] -and $group.isAssignableToRole) { Write-Error "'$name' is role-assignable and cannot be dynamic."; return }
            if ($types -notcontains 'DynamicMembership') {
                $body['groupTypes'] = @($types + 'DynamicMembership')
                if (-not $MembershipRuleProcessingState) { $body['membershipRuleProcessingState'] = 'On' }
                $changes.Add('convert to dynamic')
            }
            $body['membershipRule'] = $MembershipRule
            $changes.Add('membership rule')
        }
        if ($ConvertToAssigned) {
            if ($types -contains 'DynamicMembership') {
                $body['groupTypes'] = @($types | Where-Object { $_ -ne 'DynamicMembership' })
                $changes.Add('convert to assigned')
            }
            else {
                Write-Verbose "'$name' already has assigned membership."
            }
        }
        if ($MembershipRuleProcessingState) {
            if (-not $MembershipRule -and $group.MembershipType -ne 'Dynamic') { Write-Error "'$name' is not a dynamic group."; return }
            $body['membershipRuleProcessingState'] = $MembershipRuleProcessingState
            $changes.Add("rule processing $MembershipRuleProcessingState")
        }

        if (-not $body.Count) {
            Write-Verbose "'$name': nothing to change."
            if ($PassThru) { $group }
            return
        }

        if ($PSCmdlet.ShouldProcess($name, 'Update group: ' + ($changes -join ', '))) {
            try {
                $null = Invoke-ITGraphRequest -Uri ('groups/{0}' -f $group.id) -Method PATCH -Body $body -ApiVersion 'v1.0'
                Write-ITLog -Message ("Updated group '{0}' ({1}): {2}." -f $name, $group.id, ($changes -join ', '))
                if ($PassThru) { Get-ITGroup -Id $group.id }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
