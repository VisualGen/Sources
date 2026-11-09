function Get-ITAutopilotDevice {
    <#
    .SYNOPSIS
        Gets Windows Autopilot device registrations.

    .DESCRIPTION
        Returns the devices registered in Windows Autopilot (hardware hash uploaded).
        -SerialNumber is evaluated by Graph (contains); -GroupTag, -Model and -EnrollmentState
        are evaluated locally after download (Graph supports few filters on this collection).

        Note: the 'id' of an Autopilot device is NOT the Intune managed device ID. Use the
        managedDeviceId property to find the Intune device:
            Get-ITManagedDevice -Id (Get-ITAutopilotDevice -SerialNumber 'ABC123').managedDeviceId

    .PARAMETER Id
        Autopilot device identity ID(s).

    .PARAMETER SerialNumber
        Full or partial serial number (server-side 'contains').

    .PARAMETER GroupTag
        Group tag. Wildcards allowed; use '' to find devices without a group tag.

    .PARAMETER Model
        Device model. Wildcards allowed, e.g. 'Surface*'.

    .PARAMETER EnrollmentState
        unknown, enrolled, pendingReset, failed, notContacted or blocked.

    .EXAMPLE
        Get-ITAutopilotDevice

        All Autopilot devices.

    .EXAMPLE
        Get-ITAutopilotDevice -SerialNumber 'PF3A'

        Devices whose serial number contains 'PF3A'.

    .EXAMPLE
        Get-ITAutopilotDevice -GroupTag '' | Set-ITAutopilotDevice -GroupTag 'Standard' -WhatIf

        Shows which devices without a group tag would get 'Standard'.

    .EXAMPLE
        Get-ITAutopilotDevice -EnrollmentState notContacted | Export-Csv .\NotDeployed.csv -NoTypeInformation -Encoding UTF8

        Registered devices that were never deployed (monthly report).

    .OUTPUTS
        IntuneToolkit.AutopilotDevice

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All
        Graph endpoint   : GET /deviceManagement/windowsAutopilotDeviceIdentities
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/intune-enrollment-windowsautopilotdeviceidentity-list
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('IntuneToolkit.AutopilotDevice')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'List', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(ParameterSetName = 'List')]
        [AllowEmptyString()]
        [string]$GroupTag,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Model,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('unknown', 'enrolled', 'pendingReset', 'failed', 'notContacted', 'blocked')]
        [string]$EnrollmentState
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'
    $basePath = 'deviceManagement/windowsAutopilotDeviceIdentities'

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        foreach ($deviceId in $Id) {
            try {
                Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $deviceId) -ApiVersion 'v1.0' |
                    ConvertTo-ITObject -TypeName 'AutopilotDevice'
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
        return
    }

    $filter = $null
    if ($SerialNumber) { $filter = "contains(serialNumber,'{0}')" -f (ConvertTo-ITODataString $SerialNumber) }
    $uri = New-ITGraphUri -Path $basePath -Filter $filter

    $devices = Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -All

    if ($PSBoundParameters.ContainsKey('GroupTag')) {
        if ($GroupTag -eq '') {
            $devices = $devices | Where-Object { [string]::IsNullOrEmpty($_.groupTag) }
        }
        else {
            $devices = $devices | Where-Object { $_.groupTag -like $GroupTag }
        }
    }
    if ($Model)           { $devices = $devices | Where-Object { $_.model -like $Model } }
    if ($EnrollmentState) { $devices = $devices | Where-Object { $_.enrollmentState -eq $EnrollmentState } }

    $devices | ConvertTo-ITObject -TypeName 'AutopilotDevice'
}
