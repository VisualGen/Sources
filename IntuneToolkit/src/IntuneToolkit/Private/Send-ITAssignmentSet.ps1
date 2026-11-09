function Send-ITAssignmentSet {
    <#
    .SYNOPSIS
        Internal: adds and/or removes assignments of an Intune object and posts the full set to /assign.

    .DESCRIPTION
        Graph's /assign action REPLACES all assignments. To add or remove one, the current set is
        read, changed in memory and posted back in full:
          1. GET  {path}/{id}/assignments                (raw objects)
          2. drop every assignment for which -RemoveWhere returns $true
          3. append -Add
          4. POST {path}/{id}/assign  { <AssignKey>: [...] }
        Read-only properties (id, source, sourceId, @odata.context) are removed before posting.
        Returns the number of assignments that were posted.
        ShouldProcess is handled by the public caller.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TypeInfo,

        [Parameter(Mandatory)]
        [string]$Id,

        [hashtable[]]$Add,

        # Receives one raw assignment as $args[0] ($_ is not set); return $true to remove it.
        [scriptblock]$RemoveWhere
    )

    $objectPath = '{0}/{1}' -f $TypeInfo.Path, $Id
    $current = @(Get-ITAssignment -Path $objectPath -ApiVersion 'beta' -Raw)

    $keep = New-Object -TypeName System.Collections.Generic.List[object]
    foreach ($assignment in $current) {
        if ($RemoveWhere -and (& $RemoveWhere $assignment)) { continue }

        $clean = [ordered]@{}
        foreach ($prop in $assignment.PSObject.Properties) {
            if (@('id', 'source', 'sourceId', '@odata.context') -contains $prop.Name) { continue }
            $clean[$prop.Name] = $prop.Value
        }
        $keep.Add($clean)
    }
    foreach ($new in @($Add | Where-Object { $_ })) { $keep.Add($new) }

    $body = @{ $TypeInfo.AssignKey = $keep.ToArray() }
    $null = Invoke-ITGraphRequest -Uri ('{0}/assign' -f $objectPath) -Method POST -Body $body -ApiVersion 'beta'
    Write-ITLog -Message ('{0} {1}: {2} assignment(s) posted.' -f $TypeInfo.PolicyType, $Id, $keep.Count)
    $keep.Count
}
