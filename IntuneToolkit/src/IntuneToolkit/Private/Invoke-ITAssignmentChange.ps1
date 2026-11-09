function Invoke-ITAssignmentChange {
    <#
    .SYNOPSIS
        Internal: adds or removes one assignment target on an Intune object; returns an AssignmentChange result.

    .DESCRIPTION
        Shared by Add-/Remove-ITPolicyAssignment and Add-/Remove-ITAppAssignment.
        Add    : skipped (Status 'Unchanged') when the same target type + group already exists.
        Remove : removes every assignment whose target matches (Intent + GroupId);
                 Intent 'Any' with a GroupId removes include AND exclude of that group;
                 -RemoveAll removes everything.
        Failures are written as non-terminating errors and returned with Status 'Failed'.
        ShouldProcess is handled by the public caller.
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.AssignmentChange')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TypeInfo,

        [Parameter(Mandatory)]
        [string]$Id,

        [string]$ObjectName,

        [Parameter(Mandatory)]
        [ValidateSet('Add', 'Remove')]
        [string]$Mode,

        [ValidateSet('Include', 'Exclude', 'AllDevices', 'AllUsers', 'Any')]
        [string]$Intent = 'Include',

        [string]$GroupId,

        [string]$FilterId,

        [string]$FilterType = 'include',

        # Extra assignment properties (apps: intent/settings, remediations: runSchedule)
        [hashtable]$Extra,

        [switch]$RemoveAll
    )

    $typeOf = @{
        Include    = '#microsoft.graph.groupAssignmentTarget'
        Exclude    = '#microsoft.graph.exclusionGroupAssignmentTarget'
        AllDevices = '#microsoft.graph.allDevicesAssignmentTarget'
        AllUsers   = '#microsoft.graph.allLicensedUsersAssignmentTarget'
    }
    $targetLabel = $Intent
    if ($GroupId) { $targetLabel = '{0}:{1}' -f $Intent, $GroupId }
    if ($RemoveAll) { $targetLabel = 'All assignments' }

    # Does a raw assignment match the requested target?
    $matchTarget = {
        param($assignment)
        if (-not $assignment.PSObject.Properties['target'] -or -not $assignment.target) { return $false }
        $t = $assignment.target
        $type = ''
        if ($t.PSObject.Properties['@odata.type']) { $type = [string]$t.'@odata.type' }
        $gid = $null
        if ($t.PSObject.Properties['groupId']) { $gid = [string]$t.groupId }
        if ($Intent -eq 'Any') { return ($GroupId -and $gid -eq $GroupId) }
        if ($type -ne $typeOf[$Intent]) { return $false }
        if ($GroupId) { return ($gid -eq $GroupId) }
        $true
    }.GetNewClosure()

    $status  = 'Changed'
    $message = $null
    $count   = $null
    try {
        if ($Mode -eq 'Add') {
            $existing = @(Get-ITAssignment -Path ('{0}/{1}' -f $TypeInfo.Path, $Id) -ApiVersion 'beta' -Raw)
            if (@($existing | Where-Object { & $matchTarget $_ }).Count) {
                $status  = 'Unchanged'
                $message = 'The target is already assigned.'
            }
            else {
                $assignment = @{ target = New-ITAssignmentTarget -Intent $Intent -GroupId $GroupId -FilterId $FilterId -FilterType $FilterType }
                if ($Extra) { foreach ($key in $Extra.Keys) { $assignment[$key] = $Extra[$key] } }
                $count = Send-ITAssignmentSet -TypeInfo $TypeInfo -Id $Id -Add $assignment
            }
        }
        else {
            $existing = @(Get-ITAssignment -Path ('{0}/{1}' -f $TypeInfo.Path, $Id) -ApiVersion 'beta' -Raw)
            if ($RemoveAll) {
                $remove = { $true }
            }
            else {
                $remove = $matchTarget
            }
            if (-not @($existing | Where-Object { & $remove $_ }).Count) {
                $status  = 'Unchanged'
                $message = 'No matching assignment.'
            }
            else {
                $count = Send-ITAssignmentSet -TypeInfo $TypeInfo -Id $Id -RemoveWhere $remove
            }
        }
    }
    catch {
        $status  = 'Failed'
        $message = $_.Exception.Message
        Write-Error -ErrorRecord $_
    }

    [pscustomobject]@{
        PSTypeName      = 'IntuneToolkit.AssignmentChange'
        PolicyType      = $TypeInfo.PolicyType
        ObjectId        = $Id
        ObjectName      = $ObjectName
        Change          = $Mode
        Target          = $targetLabel
        Status          = $status
        AssignmentCount = $count
        Message         = $message
    }
}
