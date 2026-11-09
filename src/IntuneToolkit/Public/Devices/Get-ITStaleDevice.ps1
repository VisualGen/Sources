function Get-ITStaleDevice {
    <#
    .SYNOPSIS
        Gets managed devices that have not checked in with Intune for a number of days.

    .DESCRIPTION
        Returns managed devices whose last sync is older than -Days, with an extra
        DaysSinceLastSync property, oldest first. Use it for weekly clean-up reports or pipe
        the result to Remove-ITManagedDevice / Invoke-ITDeviceRetire (with -WhatIf first!).

    .PARAMETER Days
        Minimum number of days since the last check-in. Default: 90.

    .PARAMETER OperatingSystem
        Limit to one platform: Windows, iOS, iPadOS, macOS, Android or Linux.

    .PARAMETER OwnerType
        company or personal.

    .EXAMPLE
        Get-ITStaleDevice -Days 30 | Format-Table deviceName, userPrincipalName, DaysSinceLastSync

        Devices without check-in for 30 days or more.

    .EXAMPLE
        Get-ITStaleDevice -Days 180 -OperatingSystem Windows |
            Export-Csv -Path .\StaleWindows.csv -NoTypeInformation -Encoding UTF8

        Weekly report of Windows devices without check-in for half a year.

    .EXAMPLE
        Get-ITStaleDevice -Days 365 | Remove-ITManagedDevice -WhatIf

        Shows which devices a yearly clean-up would delete, without deleting anything.

    .OUTPUTS
        IntuneToolkit.ManagedDevice (with DaysSinceLastSync)

    .NOTES
        Graph permission : DeviceManagementManagedDevices.Read.All
        Graph endpoint   : GET /deviceManagement/managedDevices?$filter=lastSyncDateTime le ...
        API version      : v1.0
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.ManagedDevice')]
    param(
        [ValidateRange(1, 3650)]
        [int]$Days = 90,

        [ValidateSet('Windows', 'iOS', 'iPadOS', 'macOS', 'Android', 'Linux')]
        [string]$OperatingSystem,

        [ValidateSet('company', 'personal')]
        [string]$OwnerType
    )

    $now    = Get-Date
    $cutoff = $now.AddDays(-$Days)

    $params = @{ LastSyncBefore = $cutoff }
    if ($OperatingSystem) { $params['OperatingSystem'] = $OperatingSystem }
    if ($OwnerType)       { $params['OwnerType'] = $OwnerType }

    Write-ITLog -Message "Looking for devices without check-in since $($cutoff.ToString('yyyy-MM-dd'))."

    $devices = foreach ($device in (Get-ITManagedDevice @params)) {
        # Note: not '$days' - PowerShell variable names are case-insensitive and would overwrite -Days.
        $age = $null
        if ($device.PSObject.Properties['lastSyncDateTime'] -and $device.lastSyncDateTime) {
            $lastSync = [datetime]$device.lastSyncDateTime
            if ($lastSync.Year -gt 1) { $age = [int][math]::Floor(($now - $lastSync.ToLocalTime()).TotalDays) }
        }
        Add-Member -InputObject $device -NotePropertyName 'DaysSinceLastSync' -NotePropertyValue $age -Force -PassThru
    }

    # Never-synced devices ($null) first, then oldest first
    $devices | Sort-Object -Property @{ Expression = { if ($null -eq $_.DaysSinceLastSync) { [int]::MaxValue } else { $_.DaysSinceLastSync } }; Descending = $true }
}
