function Get-ITAppInstallStatus {
    <#
    .SYNOPSIS
        Gets app installation status per device, for an app or for a device.

    .DESCRIPTION
        Uses the Intune reports API (the same data as the portal's "Device install status").
          -AppId    : every device that reported for the app (pipe Get-ITApp).
          -DeviceId : every app that reported on the device (pipe Get-ITManagedDevice).
        Rows are returned with the report's own columns (DeviceName, UserPrincipalName,
        AppVersion, InstallState, InstallStateDetail, ErrorCode, LastModifiedDateTime, ...).
        -FailedOnly keeps rows whose install state contains 'fail' or 'error'.
        -Since keeps rows changed after a date (e.g. the last 24 hours for the daily report).

    .PARAMETER AppId
        App ID.

    .PARAMETER DeviceId
        Managed device ID (Intune).

    .PARAMETER InputObject
        Objects from Get-ITApp (by app) or Get-ITManagedDevice (by device).

    .PARAMETER FailedOnly
        Only failed installations.

    .PARAMETER Since
        Only rows with LastModifiedDateTime after this date.

    .EXAMPLE
        Get-ITApp -Name '7-Zip' | Get-ITAppInstallStatus -FailedOnly

    .EXAMPLE
        Get-ITApp -ObjectType win32LobApp -Assigned | Get-ITAppInstallStatus -FailedOnly -Since (Get-Date).AddDays(-1)

        Daily report: failed Win32 installs in the last 24 hours.

    .EXAMPLE
        Get-ITManagedDevice -Name 'PC-0042' | Get-ITAppInstallStatus

    .OUTPUTS
        IntuneToolkit.AppInstallStatus

    .NOTES
        Graph permission : DeviceManagementApps.Read.All
        Graph endpoint   : POST /deviceManagement/reports/retrieveDeviceAppInstallationStatusReport
                           (filter ApplicationId by app, DeviceId by device; falls back to
                           getDeviceInstallStatusReport for apps where the new report does not exist)
        API version      : beta

    .LINK
        https://learn.microsoft.com/mem/intune/fundamentals/reports-export-graph-apis
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType('IntuneToolkit.AppInstallStatus')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByApp')]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory, ParameterSetName = 'ByDevice')]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceId,

        [Parameter(Mandatory, ParameterSetName = 'Pipeline', ValueFromPipeline)]
        [object]$InputObject,

        [switch]$FailedOnly,

        [datetime]$Since
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementApps.Read.All'
    }

    process {
        $mode = $PSCmdlet.ParameterSetName
        $appRef = $AppId
        $deviceRef = $DeviceId
        $appName = $null
        if ($mode -eq 'Pipeline') {
            $isDevice = ($InputObject.PSObject.TypeNames -contains 'IntuneToolkit.ManagedDevice') -or [bool]$InputObject.PSObject.Properties['deviceName']
            if ($isDevice) { $mode = 'ByDevice'; $deviceRef = [string]$InputObject.id }
            else {
                $mode = 'ByApp'; $appRef = [string]$InputObject.id
                if ($InputObject.PSObject.Properties['displayName']) { $appName = $InputObject.displayName }
            }
        }

        try {
            if ($mode -eq 'ByApp') {
                # getDeviceInstallStatusReport has been removed from (some) tenants; use its successor
                # and fall back to the old report only where the successor does not exist yet.
                $appFilter = "(ApplicationId eq '{0}')" -f (ConvertTo-ITODataString $appRef)
                try {
                    $rows = Invoke-ITReport -ReportName 'retrieveDeviceAppInstallationStatusReport' -Filter $appFilter
                }
                catch {
                    if ($_.Exception.Message -notmatch 'Resource not found for the segment') { throw }
                    Write-ITLog -Level Warning -Message 'retrieveDeviceAppInstallationStatusReport not available; using getDeviceInstallStatusReport.'
                    $rows = Invoke-ITReport -ReportName 'getDeviceInstallStatusReport' -Filter $appFilter
                }
            }
            else {
                $rows = Invoke-ITReport -ReportName 'retrieveDeviceAppInstallationStatusReport' -Filter ("(DeviceId eq '{0}')" -f (ConvertTo-ITODataString $deviceRef))
            }
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }

        foreach ($row in @($rows | Where-Object { $_ })) {
            if ($FailedOnly) {
                $stateText = @($row.PSObject.Properties | Where-Object { $_.Name -like '*InstallState*' } | ForEach-Object { [string]$_.Value }) -join ' '
                if ($stateText -notmatch 'fail|error') { continue }
            }
            if ($PSBoundParameters.ContainsKey('Since') -and $row.PSObject.Properties['LastModifiedDateTime'] -and $row.LastModifiedDateTime) {
                $changed = [datetime]::MinValue
                if ([datetime]::TryParse([string]$row.LastModifiedDateTime, [ref]$changed) -and $changed -lt $Since) { continue }
            }
            if ($appName -and -not $row.PSObject.Properties['AppName']) {
                Add-Member -InputObject $row -NotePropertyName 'AppName' -NotePropertyValue $appName
            }
            $row | ConvertTo-ITObject -TypeName 'AppInstallStatus'
        }
    }
}
