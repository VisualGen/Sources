function Get-ITScopeTag {
    <#
    .SYNOPSIS
        Gets Intune scope tags (role scope tags).

    .DESCRIPTION
        Returns the scope tags used by Intune RBAC to control which admins see which objects,
        including the built-in 'Default' tag (Id 0). Use -Name (wildcards allowed) or -Id to
        narrow the result. With -IncludeAssignment the Entra groups whose devices get the tag
        automatically are added as AssignedGroupIds.

    .PARAMETER Name
        Scope tag display name. Wildcards allowed, e.g. 'NL-*'.

    .PARAMETER Id
        Scope tag ID (a number as string, e.g. '0' for Default).

    .PARAMETER IncludeAssignment
        Also read the auto-assignment groups of each tag (one extra Graph call per tag).

    .EXAMPLE
        Get-ITScopeTag

        Lists all scope tags.

    .EXAMPLE
        Get-ITScopeTag -Name 'NL-*' -IncludeAssignment | Select-Object displayName, AssignedGroupIds

        Country tags and the groups that receive them automatically.

    .EXAMPLE
        Get-ITScopeTag | Where-Object { -not $_.isBuiltIn } | Export-Csv .\ScopeTags.csv -NoTypeInformation -Encoding UTF8

        Exports all custom scope tags (monthly documentation).

    .OUTPUTS
        IntuneToolkit.ScopeTag

    .NOTES
        Graph permission : DeviceManagementRBAC.Read.All
        Graph endpoint   : GET /deviceManagement/roleScopeTags
                           GET /deviceManagement/roleScopeTags/{id}/assignments (-IncludeAssignment)
        API version      : beta (scope tags are not available in v1.0)

    .LINK
        https://learn.microsoft.com/graph/api/intune-rbac-rolescopetag-list?view=graph-rest-beta
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.ScopeTag')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$IncludeAssignment
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementRBAC.Read.All'
        $basePath = 'deviceManagement/roleScopeTags'
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $tags = foreach ($tagId in $Id) {
                try {
                    Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $tagId) -ApiVersion 'beta'
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
            }
        }
        else {
            $tags = Invoke-ITGraphRequest -Uri $basePath -ApiVersion 'beta' -All
            if ($Name) { $tags = $tags | Where-Object { $_.displayName -like $Name } }
        }

        foreach ($tag in @($tags | Where-Object { $_ })) {
            if ($IncludeAssignment) {
                $groupIds = @()
                try {
                    $assignments = @(Invoke-ITGraphRequest -Uri ('{0}/{1}/assignments' -f $basePath, $tag.id) -ApiVersion 'beta' -All)
                    $groupIds = @($assignments | ForEach-Object {
                            if ($_.PSObject.Properties['target'] -and $_.target -and $_.target.PSObject.Properties['groupId']) { $_.target.groupId }
                        } | Where-Object { $_ })
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
                Add-Member -InputObject $tag -NotePropertyName 'AssignedGroupIds' -NotePropertyValue $groupIds -Force
            }
            $tag | ConvertTo-ITObject -TypeName 'ScopeTag'
        }
    }
}
