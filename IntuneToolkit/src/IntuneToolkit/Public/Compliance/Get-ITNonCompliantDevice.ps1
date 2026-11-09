function Get-ITNonCompliantDevice {
    <#
    .SYNOPSIS
        Gets devices that are not compliant, optionally with the policies they fail.

    .DESCRIPTION
        Daily report function. Returns managed devices with complianceState 'noncompliant'
        (and 'inGracePeriod' with -IncludeGracePeriod). With -IncludePolicy each device gets
        a FailedPolicies property: the names of the compliance policies in state noncompliant
        or error on that device (one extra Graph call per device).

    .PARAMETER OperatingSystem
        Only devices with this operating system.

    .PARAMETER IncludeGracePeriod
        Also return devices that are in the grace period (will become non-compliant).

    .PARAMETER IncludePolicy
        Add FailedPolicies (names of the failing compliance policies) to every device.

    .EXAMPLE
        Get-ITNonCompliantDevice

    .EXAMPLE
        Get-ITNonCompliantDevice -OperatingSystem Windows -IncludePolicy |
            Select-Object deviceName, userPrincipalName, lastSyncDateTime, @{ n = 'Failed'; e = { $_.FailedPolicies -join '; ' } } |
            Export-ITReport -Path .\Reports\NonCompliant.html -Title 'Non-compliant devices'

    .OUTPUTS
        IntuneToolkit.ManagedDevice

    .NOTES
        Graph permission : DeviceManagementManagedDevices.Read.All
        Graph endpoint   : GET /deviceManagement/managedDevices?$filter=complianceState eq 'noncompliant'
                           GET /deviceManagement/managedDevices/{id}/deviceCompliancePolicyStates (-IncludePolicy)
        API version      : v1.0

    .LINK
        Get-ITDeviceComplianceStatus
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.ManagedDevice')]
    param(
        [ValidateSet('Windows', 'iOS', 'iPadOS', 'macOS', 'Android', 'Linux')]
        [string]$OperatingSystem,

        [switch]$IncludeGracePeriod,

        [switch]$IncludePolicy
    )

    $states = @('noncompliant')
    if ($IncludeGracePeriod) { $states += 'inGracePeriod' }

    foreach ($state in $states) {
        $params = @{ ComplianceState = $state; ApiVersion = 'v1.0' }
        if ($OperatingSystem) { $params['OperatingSystem'] = $OperatingSystem }

        foreach ($device in @(Get-ITManagedDevice @params)) {
            if ($IncludePolicy) {
                $failed = @()
                try {
                    $policyStates = Invoke-ITGraphRequest -Uri ('deviceManagement/managedDevices/{0}/deviceCompliancePolicyStates' -f $device.id) -ApiVersion 'v1.0' -All
                    $failed = @($policyStates | Where-Object { $_ -and @('noncompliant', 'error', 'nonCompliant') -contains [string]$_.state } |
                            ForEach-Object { $_.displayName })
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
                Add-Member -InputObject $device -NotePropertyName 'FailedPolicies' -NotePropertyValue $failed -Force
            }
            $device
        }
    }
}
