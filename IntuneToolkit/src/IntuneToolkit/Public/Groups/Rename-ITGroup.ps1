function Rename-ITGroup {
    <#
    .SYNOPSIS
        Renames an Entra ID group.

    .DESCRIPTION
        Short form of Set-ITGroup -DisplayName. Stops when another group already has the new
        name, unless -AllowDuplicate is used. Intune assignments use the group ID, so they keep
        working after a rename.

    .PARAMETER Id
        Group object ID or exact display name. Accepts pipeline input by property name (id / GroupId).

    .PARAMETER NewName
        The new display name.

    .PARAMETER AllowDuplicate
        Allow a name another group already has.

    .PARAMETER PassThru
        Return the renamed group.

    .EXAMPLE
        Rename-ITGroup -Id 'Pilot users' -NewName 'SG-Intune-Pilot-Users'

    .EXAMPLE
        Get-ITGroup -Name 'Intune-*' | ForEach-Object { Rename-ITGroup -Id $_.id -NewName ('SG-' + $_.displayName) -WhatIf }

        Previews adding a 'SG-' prefix to a set of groups.

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

        [Parameter(Mandatory, Position = 1)]
        [ValidateLength(1, 256)]
        [string]$NewName,

        [switch]$AllowDuplicate,

        [switch]$PassThru
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id, "Rename group to '$NewName'")) {
            # Already confirmed here: Set-ITGroup must not ask again
            Set-ITGroup -Id $Id -DisplayName $NewName -AllowDuplicate:$AllowDuplicate -PassThru:$PassThru -Confirm:$false -WhatIf:$false
        }
    }
}
