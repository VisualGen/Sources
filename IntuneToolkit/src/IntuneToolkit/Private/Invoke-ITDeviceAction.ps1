function Invoke-ITDeviceAction {
    <#
    .SYNOPSIS
        Internal: sends one remote action to one managed device and returns a result object.

    .DESCRIPTION
        Shared by Invoke-ITDeviceSync, -Restart, -Retire, -Wipe, Invoke-ITDefenderScan,
        Invoke-ITBitLockerKeyRotation and Remove-ITManagedDevice. ShouldProcess is handled by
        the public function. A failure is written as a non-terminating error AND returned as a
        result with Status 'Failed', so bulk runs continue and can be exported as a report.
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [string]$DeviceName,

        # Graph action segment, e.g. 'syncDevice'. Empty = the device itself (used with DELETE).
        [AllowEmptyString()]
        [string]$Action,

        # Friendly action name for the result object.
        [Parameter(Mandatory)]
        [string]$ActionName,

        [ValidateSet('POST', 'DELETE')]
        [string]$Method = 'POST',

        [object]$Body,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'v1.0',

        # Collection the device lives in (Autopilot devices use windowsAutopilotDeviceIdentities).
        [string]$BasePath = 'deviceManagement/managedDevices'
    )

    $uri = '{0}/{1}' -f $BasePath, $Id
    if ($Action) { $uri = '{0}/{1}' -f $uri, $Action }

    $status  = 'Sent'
    $message = $null
    try {
        $null = Invoke-ITGraphRequest -Uri $uri -Method $Method -Body $Body -ApiVersion $ApiVersion
        Write-ITLog -Message "$ActionName sent to device $Id $(if ($DeviceName) { "($DeviceName)" })."
    }
    catch {
        $status  = 'Failed'
        $message = $_.Exception.Message
        Write-Error -ErrorRecord $_
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneToolkit.DeviceActionResult'
        DeviceId   = $Id
        DeviceName = $DeviceName
        Action     = $ActionName
        Status     = $status
        Message    = $message
        Timestamp  = Get-Date
    }
}
