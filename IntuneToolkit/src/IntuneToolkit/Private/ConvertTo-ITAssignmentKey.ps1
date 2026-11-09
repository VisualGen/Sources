function ConvertTo-ITAssignmentKey {
    <#
    .SYNOPSIS
        Internal: turns assignment targets into an order-independent hashtable for comparison.

    .DESCRIPTION
        Key   = '<target type>:<groupId>'  (e.g. 'groupAssignmentTarget:1a2b...', 'allDevicesAssignmentTarget:')
        Value = '<filter type>:<filter id>' or 'noFilter'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Target
    )

    $map = @{}
    foreach ($t in @($Target | Where-Object { $_ })) {
        $type = ''
        if ($t.PSObject.Properties['@odata.type']) { $type = ([string]$t.'@odata.type') -replace '^#microsoft\.graph\.', '' }
        $gid = ''
        if ($t.PSObject.Properties['groupId'] -and $t.groupId) { $gid = [string]$t.groupId }
        $filter = 'noFilter'
        if ($t.PSObject.Properties['deviceAndAppManagementAssignmentFilterId'] -and $t.deviceAndAppManagementAssignmentFilterId) {
            $filter = '{0}:{1}' -f $t.deviceAndAppManagementAssignmentFilterType, $t.deviceAndAppManagementAssignmentFilterId
        }
        $map['{0}:{1}' -f $type, $gid] = $filter
    }
    $map
}
