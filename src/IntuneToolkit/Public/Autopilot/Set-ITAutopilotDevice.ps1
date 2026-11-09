function Set-ITAutopilotDevice {
    <#
    .SYNOPSIS
        Changes properties of Windows Autopilot devices (group tag, user, display name).

    .DESCRIPTION
        Updates the Autopilot registration with updateDeviceProperties. Only the parameters you
        specify are changed. Use -GroupTag '' to clear the group tag.
        Dynamic groups (ZTDId / OrderID rules) pick up a new group tag after a few minutes;
        run Invoke-ITAutopilotSync to speed things up.

    .PARAMETER Id
        Autopilot device identity ID(s). Accepts pipeline input from Get-ITAutopilotDevice.

    .PARAMETER SerialNumber
        Serial number, used only for messages (bound from the pipeline).

    .PARAMETER GroupTag
        New group tag ('' clears it).

    .PARAMETER DisplayName
        Device name to apply during deployment (only for profiles that allow it).

    .PARAMETER UserPrincipalName
        UPN of the user to pre-assign ('' clears it).

    .PARAMETER AddressableUserName
        Friendly name shown on the sign-in page ('Welcome, ...').

    .PARAMETER PassThru
        Return a result object per device.

    .EXAMPLE
        Get-ITAutopilotDevice -SerialNumber 'PF3A1234' | Set-ITAutopilotDevice -GroupTag 'Kiosk'

    .EXAMPLE
        Get-ITAutopilotDevice -GroupTag 'Old*' | Set-ITAutopilotDevice -GroupTag 'Standard' -PassThru

        Renames a group tag for many devices and shows the result.

    .EXAMPLE
        Import-Csv .\Assign.csv | ForEach-Object {
            Get-ITAutopilotDevice -SerialNumber $_.Serial |
                Set-ITAutopilotDevice -UserPrincipalName $_.UPN -AddressableUserName $_.Name
        }

        Pre-assigns users from a CSV with Serial, UPN and Name columns.

    .OUTPUTS
        None, or IntuneToolkit.DeviceActionResult with -PassThru.

    .NOTES
        Graph permission : DeviceManagementServiceConfig.ReadWrite.All
        Graph endpoint   : POST /deviceManagement/windowsAutopilotDeviceIdentities/{id}/updateDeviceProperties
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-enrollment-windowsautopilotdeviceidentity-updatedeviceproperties
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SerialNumber,

        [AllowEmptyString()]
        [string]$GroupTag,

        [ValidateLength(0, 15)]
        [string]$DisplayName,

        [AllowEmptyString()]
        [string]$UserPrincipalName,

        [AllowEmptyString()]
        [string]$AddressableUserName,

        [switch]$PassThru
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.ReadWrite.All'

        $body = @{}
        $map = @{ GroupTag = 'groupTag'; DisplayName = 'displayName'; UserPrincipalName = 'userPrincipalName'; AddressableUserName = 'addressableUserName' }
        foreach ($param in $map.Keys) {
            if ($PSBoundParameters.ContainsKey($param)) { $body[$map[$param]] = [string]$PSBoundParameters[$param] }
        }
        if (-not $body.Count) {
            throw 'Specify at least one of -GroupTag, -DisplayName, -UserPrincipalName or -AddressableUserName.'
        }
        $changes = ($body.Keys | Sort-Object | ForEach-Object { "$_='$($body[$_])'" }) -join ', '
    }

    process {
        foreach ($deviceId in $Id) {
            $label = $deviceId
            if ($SerialNumber -and $Id.Count -eq 1) { $label = 'Serial {0} ({1})' -f $SerialNumber, $deviceId }
            if ($PSCmdlet.ShouldProcess($label, "Set Autopilot properties: $changes")) {
                $result = Invoke-ITDeviceAction -Id $deviceId -DeviceName $SerialNumber -Action 'updateDeviceProperties' `
                    -ActionName 'SetAutopilotProperties' -Body $body -BasePath 'deviceManagement/windowsAutopilotDeviceIdentities'
                if ($PassThru) { $result }
            }
        }
    }
}
