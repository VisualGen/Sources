function Get-ITGroup {
    <#
    .SYNOPSIS
        Finds Entra ID (Azure AD) groups.

    .DESCRIPTION
        Returns groups by ID, by name or by type. Every group gets two extra properties:
        GroupType (Microsoft365, Security, MailEnabledSecurity, Distribution) and
        MembershipType (Assigned or Dynamic).

        -Name supports an exact name ('SG-Pilot'), a prefix ('SG-Intune-*', evaluated by Graph)
        or any other wildcard ('*Pilot*', evaluated locally after download - slower on large tenants).
        -Search does a word search in the display name and description (Graph $search), for example
        -Search 'pilot' finds 'SG-Intune-Pilot-Devices' and 'Windows pilot users'.

    .PARAMETER Id
        One or more group object IDs. Accepts pipeline input by property name (id / GroupId).

    .PARAMETER Name
        Display name. Exact, 'Prefix*' or any wildcard pattern.

    .PARAMETER Search
        Words to find in the display name or description (each word matches the start of a word).

    .PARAMETER GroupType
        Microsoft365, Security, MailEnabledSecurity or Distribution.

    .PARAMETER MembershipType
        Assigned or Dynamic.

    .PARAMETER RoleAssignable
        Only groups that can be assigned to Entra ID roles.

    .PARAMETER Filter
        Additional raw OData filter, combined with the other filters using 'and'.

    .PARAMETER Property
        Properties to return ($select). Default: the common group properties.

    .PARAMETER IncludeMemberCount
        Adds MemberCount (direct members). One extra request per group.

    .PARAMETER Top
        Return only the first N groups.

    .EXAMPLE
        Get-ITGroup -Name 'SG-Intune-*'

        Groups whose name starts with 'SG-Intune-'.

    .EXAMPLE
        Get-ITGroup -Search 'pilot' -MembershipType Dynamic | Select-Object displayName, membershipRule

        Dynamic groups with 'pilot' in the name or description, with their rule.

    .EXAMPLE
        Get-ITGroup -GroupType Security -IncludeMemberCount | Where-Object MemberCount -eq 0

        Empty security groups (clean-up).

    .OUTPUTS
        IntuneToolkit.Group

    .NOTES
        Graph permission : Group.Read.All
        Graph endpoint   : GET /groups
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/group-list
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('IntuneToolkit.Group')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'List', Position = 0)]
        [Alias('DisplayName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Search,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('Microsoft365', 'Security', 'MailEnabledSecurity', 'Distribution')]
        [string]$GroupType,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('Assigned', 'Dynamic')]
        [string]$MembershipType,

        [Parameter(ParameterSetName = 'List')]
        [switch]$RoleAssignable,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [ValidateNotNullOrEmpty()]
        [string[]]$Property,

        [switch]$IncludeMemberCount,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, 999)]
        [int]$Top
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'Group.Read.All'
        $select = $Property
        if (-not $select) {
            $select = @('id', 'displayName', 'description', 'groupTypes', 'securityEnabled', 'mailEnabled', 'mailNickname', 'mail',
                'membershipRule', 'membershipRuleProcessingState', 'isAssignableToRole', 'onPremisesSyncEnabled', 'createdDateTime')
        }
        # GroupType / MembershipType are computed from these
        $select = @(@($select) + 'id', 'displayName', 'groupTypes', 'securityEnabled', 'mailEnabled' | Select-Object -Unique)

        $withCount = [bool]$IncludeMemberCount
        $addCount = {
            param($g)
            if ($withCount) {
                $countUri = New-ITGraphUri -Path ('groups/{0}/members' -f $g.id) -Select 'id' -Top 999
                $count = @(Invoke-ITGraphRequest -Uri $countUri -ApiVersion 'v1.0' -All).Count
                $g | Add-Member -NotePropertyName 'MemberCount' -NotePropertyValue $count -Force
            }
            $g
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            foreach ($groupId in $Id) {
                try {
                    $g = Invoke-ITGraphRequest -Uri (New-ITGraphUri -Path "groups/$groupId" -Select $select) -ApiVersion 'v1.0'
                    & $addCount ($g | ConvertTo-ITGroupObject)
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
            }
            return
        }

        # --- Server-side filter (local checks below make the result exact) --------------------
        $clauses = New-Object -TypeName System.Collections.Generic.List[string]
        $localNamePattern = $null
        if ($Name) {
            if ($Name -notmatch '[\*\?\[]') {
                $clauses.Add(("displayName eq '{0}'" -f (ConvertTo-ITODataString $Name)))
            }
            elseif ($Name -match '^[^\*\?\[]+\*$') {
                $clauses.Add(("startswith(displayName,'{0}')" -f (ConvertTo-ITODataString $Name.TrimEnd('*'))))
            }
            else {
                $localNamePattern = $Name
                Write-ITLog -Message "Name pattern '$Name' is evaluated locally; all groups are downloaded first."
            }
        }
        switch ($GroupType) {
            'Microsoft365'        { $clauses.Add("groupTypes/any(c:c eq 'Unified')"); break }
            'Security'            { $clauses.Add('securityEnabled eq true'); $clauses.Add('mailEnabled eq false'); break }
            'MailEnabledSecurity' { $clauses.Add('securityEnabled eq true'); $clauses.Add('mailEnabled eq true'); break }
            'Distribution'        { $clauses.Add('securityEnabled eq false'); $clauses.Add('mailEnabled eq true'); break }
        }
        if ($MembershipType -eq 'Dynamic') { $clauses.Add("groupTypes/any(c:c eq 'DynamicMembership')") }
        if ($RoleAssignable) { $clauses.Add('isAssignableToRole eq true') }
        if ($Filter) { $clauses.Add($Filter) }

        $local = -not $Top -or $localNamePattern -or $GroupType -or $MembershipType -eq 'Assigned'
        $uriParams = @{ Path = 'groups'; Filter = $clauses.ToArray(); Select = $select }
        if ($Top -and -not $local) { $uriParams['Top'] = $Top }
        $uri = New-ITGraphUri @uriParams

        $request = @{ Uri = $uri; ApiVersion = 'v1.0'; All = [bool]$local }
        if ($Search) {
            # $search needs ConsistencyLevel: eventual; double quotes are the $search delimiters
            $words = $Search.Replace('"', '').Trim()
            $term = '"displayName:{0}" OR "description:{0}"' -f $words
            $joiner = '?'
            if ($uri.Contains('?')) { $joiner = '&' }
            $request['Uri'] = '{0}{1}$search={2}' -f $uri, $joiner, [uri]::EscapeDataString($term)
            $request['Headers'] = @{ ConsistencyLevel = 'eventual' }
        }

        $typeFilter = $GroupType
        $membershipFilter = $MembershipType
        $groups = Invoke-ITGraphRequest @request | ConvertTo-ITGroupObject
        if ($localNamePattern) { $groups = $groups | Where-Object { $_.displayName -like $localNamePattern } }
        if ($typeFilter)       { $groups = $groups | Where-Object { $_.GroupType -eq $typeFilter } }
        if ($membershipFilter) { $groups = $groups | Where-Object { $_.MembershipType -eq $membershipFilter } }
        if ($Top)              { $groups = $groups | Select-Object -First $Top }

        foreach ($g in @($groups)) { & $addCount $g }
    }
}
