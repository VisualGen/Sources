function Invoke-ITDeviceWipe {
    <#
    .SYNOPSIS
        Wipes (factory resets) one or more managed devices.

    .DESCRIPTION
        Sends the 'wipe' remote action. By default ALL data on the device is erased.
        This cannot be undone. Always asks for confirmation unless -Confirm:$false is given.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages and the result object (bound from the pipeline).

    .PARAMETER KeepEnrollmentData
        Windows: keep the provisioning/enrollment data so the device re-enrolls (Autopilot reset style).

    .PARAMETER KeepUserData
        Windows: keep user accounts and data (removes apps and settings only).

    .PARAMETER MacOsUnlockCode
        macOS: 6-digit PIN that unlocks the device after the wipe.

    .PARAMETER PersistEsimDataPlan
        Keep the eSIM data plan on the device.

    .PARAMETER ProtectedWipe
        Windows: protected wipe - the wipe cannot be bypassed by powering off; resumes after restart.
        Uses the beta endpoint.

    .EXAMPLE
        Get-ITManagedDevice -Name 'LT-LOST-042' | Invoke-ITDeviceWipe

        Full wipe of a lost laptop (prompts for confirmation).

    .EXAMPLE
        Get-ITManagedDevice -Name 'LT-RESET-01' | Invoke-ITDeviceWipe -KeepEnrollmentData -ProtectedWipe

        Resets a Windows device for a new user; it re-enrolls automatically.

    .EXAMPLE
        Get-ITManagedDevice -UserPrincipalName 'leaver@contoso.com' | Invoke-ITDeviceWipe -WhatIf

        Shows which devices of a leaver would be wiped.

    .OUTPUTS
        IntuneToolkit.DeviceActionResult

    .NOTES
        Graph permission : DeviceManagementManagedDevices.PrivilegedOperations.All
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/wipe
        API version      : v1.0 (beta with -ProtectedWipe)

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-wipe
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName,

        [switch]$KeepEnrollmentData,

        [switch]$KeepUserData,

        [ValidatePattern('^\d{6}$')]
        [string]$MacOsUnlockCode,

        [switch]$PersistEsimDataPlan,

        [switch]$ProtectedWipe
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.PrivilegedOperations.All'

        $body = @{
            keepEnrollmentData  = [bool]$KeepEnrollmentData
            keepUserData        = [bool]$KeepUserData
            persistEsimDataPlan = [bool]$PersistEsimDataPlan
        }
        if ($MacOsUnlockCode) { $body['macOsUnlockCode'] = $MacOsUnlockCode }

        $apiVersion = 'v1.0'
        if ($ProtectedWipe) {
            $body['useProtectedWipe'] = $true
            $apiVersion = 'beta'
        }

        $what = 'WIPE device - all data will be erased'
        if ($KeepUserData) { $what = 'Wipe device (keep user data)' }
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $label = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, $what)) {
                Invoke-ITDeviceAction -Id $deviceId -DeviceName $DeviceName -Action 'wipe' -ActionName 'Wipe' -Body $body -ApiVersion $apiVersion
            }
        }
    }
}
