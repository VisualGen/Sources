function Get-ITDeviceComplianceStatus {
    <#
    .SYNOPSIS
        Gets the compliance state per device and policy.

    .DESCRIPTION
        Two directions:
          -PolicyId : every device evaluated by that compliance policy (pipe Get-ITCompliancePolicy).
          -DeviceId : every compliance policy evaluated on that device (pipe Get-ITManagedDevice).
        Both return the same flat object: DeviceId, DeviceName, UserPrincipalName, PolicyId,
        PolicyName, Status, LastReportedDateTime. -Status filters locally.

    .PARAMETER PolicyId
        Compliance policy ID.

    .PARAMETER DeviceId
        Managed device ID.

    .PARAMETER InputObject
        Objects from Get-ITCompliancePolicy (by policy) or Get-ITManagedDevice (by device).

    .PARAMETER Status
        Only rows with this status (compliant, noncompliant, error, conflict, inGracePeriod, notApplicable, unknown).

    .EXAMPLE
        Get-ITCompliancePolicy -Name 'Win - Baseline' | Get-ITDeviceComplianceStatus -Status noncompliant

    .EXAMPLE
        Get-ITManagedDevice -Name 'PC-0042' | Get-ITDeviceComplianceStatus

        Which policies pass or fail on one device.

    .OUTPUTS
        IntuneToolkit.ComplianceStatus

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All (by policy),
                           DeviceManagementManagedDevices.Read.All (by device)
        Graph endpoint   : GET /deviceManagement/deviceCompliancePolicies/{id}/deviceStatuses
                           GET /deviceManagement/managedDevices/{id}/deviceCompliancePolicyStates
        API version      : v1.0

    .LINK
        Get-ITNonCompliantDevice
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPolicy')]
    [OutputType('IntuneToolkit.ComplianceStatus')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPolicy')]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyId,

        [Parameter(Mandatory, ParameterSetName = 'ByDevice')]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceId,

        [Parameter(Mandatory, ParameterSetName = 'Pipeline', ValueFromPipeline)]
        [object]$InputObject,

        [ValidateSet('compliant', 'noncompliant', 'error', 'conflict', 'inGracePeriod', 'notApplicable', 'unknown', 'notAssigned')]
        [string]$Status
    )

    begin {
        if ($PSCmdlet.ParameterSetName -eq 'ByPolicy') {
            Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByDevice') {
            Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All'
        }
        else {
            Assert-ITGraphConnection
        }
        $get = { param($o, $n) if ($o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    }

    process {
        $mode = $PSCmdlet.ParameterSetName
        $policyName = $null
        $deviceName = $null
        $policyRef = $PolicyId
        $deviceRef = $DeviceId
        if ($mode -eq 'Pipeline') {
            $isDevice = ($InputObject.PSObject.TypeNames -contains 'IntuneToolkit.ManagedDevice') -or [bool]$InputObject.PSObject.Properties['deviceName']
            if ($isDevice) {
                $mode = 'ByDevice'; $deviceRef = $InputObject.id; $deviceName = $InputObject.deviceName
            }
            else {
                $mode = 'ByPolicy'; $policyRef = $InputObject.id
                if ($InputObject.PSObject.Properties['displayName']) { $policyName = $InputObject.displayName }
            }
        }

        $results = try {
            if ($mode -eq 'ByPolicy') {
                $rows = Invoke-ITGraphRequest -Uri ('deviceManagement/deviceCompliancePolicies/{0}/deviceStatuses' -f $policyRef) -ApiVersion 'v1.0' -All
                foreach ($row in @($rows | Where-Object { $_ })) {
                    # deviceStatuses id = <policyId>_<deviceId>_<userId>
                    $devId = $null
                    $parts = ([string]$row.id) -split '_'
                    if ($parts.Count -ge 2) { $devId = $parts[1] }
                    [pscustomobject]@{
                        PSTypeName           = 'IntuneToolkit.ComplianceStatus'
                        DeviceId             = $devId
                        DeviceName           = & $get $row 'deviceDisplayName'
                        UserPrincipalName    = & $get $row 'userPrincipalName'
                        PolicyId             = $policyRef
                        PolicyName           = $policyName
                        Status               = & $get $row 'status'
                        LastReportedDateTime = & $get $row 'lastReportedDateTime'
                    }
                }
            }
            else {
                $rows = Invoke-ITGraphRequest -Uri ('deviceManagement/managedDevices/{0}/deviceCompliancePolicyStates' -f $deviceRef) -ApiVersion 'v1.0' -All
                foreach ($row in @($rows | Where-Object { $_ })) {
                    [pscustomobject]@{
                        PSTypeName           = 'IntuneToolkit.ComplianceStatus'
                        DeviceId             = $deviceRef
                        DeviceName           = $deviceName
                        UserPrincipalName    = & $get $row 'userPrincipalName'
                        PolicyId             = $row.id
                        PolicyName           = & $get $row 'displayName'
                        Status               = & $get $row 'state'
                        LastReportedDateTime = $null
                    }
                }
            }
        }
        catch {
            Write-Error -ErrorRecord $_
        }
        $statusFilter = $Status
        foreach ($r in @($results | Where-Object { $_ })) {
            if (-not $statusFilter -or $r.Status -eq $statusFilter) { $r }
        }
    }
}
