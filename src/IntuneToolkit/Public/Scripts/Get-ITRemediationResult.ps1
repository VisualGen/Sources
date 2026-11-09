function Get-ITRemediationResult {
    <#
    .SYNOPSIS
        Gets the per-device results of a remediation (detection and remediation state, script output).

    .DESCRIPTION
        Returns one row per device: DetectionState (success = no issue, fail = issue found),
        RemediationState (success = fixed, remediationFailed, skipped, ...), the script output
        before and after remediation, and LastStateUpdateDateTime.
        -Status filters: IssueFound (detection fail), Fixed, RemediationFailed, NoIssue, Error.

    .PARAMETER Id
        Remediation ID. Binds from the id of Get-ITRemediation objects.

    .PARAMETER Status
        Only rows in this state.

    .EXAMPLE
        Get-ITRemediation -Name 'Fix - Clear Teams cache' | Get-ITRemediationResult

    .EXAMPLE
        Get-ITRemediation -ExcludeBuiltIn | Get-ITRemediationResult -Status RemediationFailed |
            Select-Object RemediationName, DeviceName, PostRemediationDetectionOutput

    .OUTPUTS
        IntuneToolkit.RemediationResult

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All (+ DeviceManagementManagedDevices.Read.All for device names)
        Graph endpoint   : GET /deviceManagement/deviceHealthScripts/{id}/deviceRunStates?$expand=managedDevice
        API version      : beta

    .LINK
        Invoke-ITRemediationOnDemand
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.RemediationResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [ValidateSet('IssueFound', 'Fixed', 'RemediationFailed', 'NoIssue', 'Error')]
        [string]$Status
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
        $get = { param($o, $n) if ($o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    }

    process {
        $remediationName = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $remediationName = $_.displayName }

        try {
            $uri = New-ITGraphUri -Path ('deviceManagement/deviceHealthScripts/{0}/deviceRunStates' -f $Id) -Expand 'managedDevice($select=id,deviceName,userPrincipalName)'
            $states = Invoke-ITGraphRequest -Uri $uri -ApiVersion 'beta' -All
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }

        foreach ($state in @($states | Where-Object { $_ })) {
            $detection = [string](& $get $state 'detectionState')
            $remediation = [string](& $get $state 'remediationState')

            $summary = 'Other'
            if ($detection -eq 'success') { $summary = 'NoIssue' }
            if ($detection -eq 'fail') { $summary = 'IssueFound' }
            if ($remediation -eq 'success') { $summary = 'Fixed' }
            if ($remediation -eq 'remediationFailed') { $summary = 'RemediationFailed' }
            if ($detection -match 'error|scriptError' -or $remediation -eq 'scriptError') { $summary = 'Error' }
            if ($Status -and $summary -ne $Status) { continue }

            $device = & $get $state 'managedDevice'
            [pscustomobject]@{
                PSTypeName                     = 'IntuneToolkit.RemediationResult'
                RemediationId                  = $Id
                RemediationName                = $remediationName
                DeviceId                       = & $get $device 'id'
                DeviceName                     = & $get $device 'deviceName'
                UserPrincipalName              = & $get $device 'userPrincipalName'
                Result                         = $summary
                DetectionState                 = $detection
                RemediationState               = $remediation
                PreRemediationDetectionOutput  = & $get $state 'preRemediationDetectionScriptOutput'
                RemediationOutput              = & $get $state 'remediationScriptError'
                PostRemediationDetectionOutput = & $get $state 'postRemediationDetectionScriptOutput'
                LastStateUpdateDateTime        = & $get $state 'lastStateUpdateDateTime'
            }
        }
    }
}
