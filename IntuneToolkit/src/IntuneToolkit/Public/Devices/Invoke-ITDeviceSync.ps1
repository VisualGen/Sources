function Invoke-ITDeviceSync {
    <#
    .SYNOPSIS
        Asks one or more managed devices to check in with Intune now.

    .DESCRIPTION
        Sends the 'syncDevice' remote action. The device receives a push notification and
        checks in for policies, apps and compliance. Returns one result object per device.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .EXAMPLE
        Invoke-ITDeviceSync -Id 'b1b2c3d4-0000-0000-0000-000000000000'

    .EXAMPLE
        Get-ITManagedDevice -ComplianceState noncompliant -OperatingSystem Windows | Invoke-ITDeviceSync

        Forces a check-in on every non-compliant Windows device.

    .EXAMPLE
        Get-ITManagedDevice -Name 'KIOSK-*' | Invoke-ITDeviceSync | Where-Object Status -eq 'Failed'

        Syncs kiosk devices and shows only the failures.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/syncDevice
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-syncdevice
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.PrivilegedOperations.All'
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $label = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, 'Sync device')) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'syncDevice' -ActionName 'Sync'
            }
        }
    }
}
