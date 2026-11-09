function Get-ITDirectoryObjectType {
    <#
    .SYNOPSIS
        Internal: maps a directory object's @odata.type to User, Group, Device, ServicePrincipal, Contact or Other.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties['@odata.type']) { return 'Other' }
    switch ([string]$InputObject.'@odata.type') {
        '#microsoft.graph.user'             { return 'User' }
        '#microsoft.graph.group'            { return 'Group' }
        '#microsoft.graph.device'           { return 'Device' }
        '#microsoft.graph.servicePrincipal' { return 'ServicePrincipal' }
        '#microsoft.graph.orgContact'       { return 'Contact' }
        default                             { return 'Other' }
    }
}
