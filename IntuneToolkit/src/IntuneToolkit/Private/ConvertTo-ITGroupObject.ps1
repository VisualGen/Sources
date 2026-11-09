function ConvertTo-ITGroupObject {
    <#
    .SYNOPSIS
        Internal: tags an Entra ID group with IntuneToolkit.Group and adds GroupType / MembershipType.

    .DESCRIPTION
        GroupType      : Microsoft365, Security, MailEnabledSecurity or Distribution.
        MembershipType : Dynamic (groupTypes contains DynamicMembership) or Assigned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) { return }

        $types = @()
        if ($InputObject.PSObject.Properties['groupTypes']) { $types = @($InputObject.groupTypes) }
        $security = $InputObject.PSObject.Properties['securityEnabled'] -and [bool]$InputObject.securityEnabled
        $mail     = $InputObject.PSObject.Properties['mailEnabled'] -and [bool]$InputObject.mailEnabled

        $groupType = 'Distribution'
        if ($types -contains 'Unified')  { $groupType = 'Microsoft365' }
        elseif ($security -and $mail)    { $groupType = 'MailEnabledSecurity' }
        elseif ($security)               { $groupType = 'Security' }

        $membershipType = 'Assigned'
        if ($types -contains 'DynamicMembership') { $membershipType = 'Dynamic' }

        $InputObject | Add-Member -NotePropertyName 'GroupType' -NotePropertyValue $groupType -Force
        $InputObject | Add-Member -NotePropertyName 'MembershipType' -NotePropertyValue $membershipType -Force
        $InputObject | ConvertTo-ITObject -TypeName 'Group'
    }
}
