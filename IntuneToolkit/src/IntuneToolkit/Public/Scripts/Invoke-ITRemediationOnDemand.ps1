function Invoke-ITRemediationOnDemand {
    <#
    .SYNOPSIS
        Runs a remediation on one or more devices now ("Run remediation" in the portal).

    .DESCRIPTION
        Sends initiateOnDemandProactiveRemediation to each device. The device runs the
        detection (and, when needed, the remediation) script at its next check-in; the result
        appears in Get-ITRemediationResult. The remediation does not need to be assigned.
        Returns a DeviceActionResult per device.

    .PARAMETER Id
        Managed device ID(s). Binds from Get-ITManagedDevice objects.

    .PARAMETER DeviceName
        Device name for the result (binds from the pipeline).

    .PARAMETER RemediationId
        ID of the remediation to run (Get-ITRemediation).

    .EXAMPLE
        $fix = Get-ITRemediation -Name 'Fix - Clear Teams cache'
        Get-ITManagedDevice -Name 'PC-0042' | Invoke-ITRemediationOnDemand -RemediationId $fix.id

    .EXAMPLE
        Get-ITNonCompliantDevice -OperatingSystem Windows | Invoke-ITRemediationOnDemand -RemediationId $fixId -WhatIf

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/initiateOnDemandProactiveRemediation
        API version      : beta

    .LINK
        Get-ITRemediationResult
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RemediationId
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.PrivilegedOperations.All'
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($DeviceName) { $label = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, "Run remediation $RemediationId")) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'initiateOnDemandProactiveRemediation' `
                    -ActionName 'RemediationOnDemand' -Body @{ scriptPolicyId = $RemediationId } -ApiVersion 'beta'
            }
        }
    }
}
