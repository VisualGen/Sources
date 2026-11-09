function Invoke-ITDefenderScan {
    <#
    .SYNOPSIS
        Starts a Microsoft Defender Antivirus scan on one or more Windows devices.

    .DESCRIPTION
        Sends the 'windowsDefenderScan' remote action. Quick scan by default, full scan with -FullScan.
        Results appear in the Intune / Defender portals, not in the return value.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .PARAMETER FullScan
        Run a full scan instead of a quick scan.

    .EXAMPLE
        Get-ITManagedDevice -Name 'LT-0815' | Invoke-ITDefenderScan -FullScan

    .EXAMPLE
        Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant | Invoke-ITDefenderScan

        Quick scan on every non-compliant Windows device.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/windowsDefenderScan
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-windowsdefenderscan
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName,

        [switch]$FullScan
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.PrivilegedOperations.All'
        $body = @{ quickScan = -not $FullScan }
        $scanType = 'Quick'
        if ($FullScan) { $scanType = 'Full' }
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $label = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, "Start Defender $($scanType.ToLower()) scan")) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'windowsDefenderScan' -ActionName "DefenderScan$scanType" -Body $body
            }
        }
    }
}
