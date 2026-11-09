function Set-ITManagedDeviceCategory {
    <#
    .SYNOPSIS
        Sets the device category of one or more managed devices.

    .DESCRIPTION
        Assigns an existing Intune device category to devices. Specify the category by
        -CategoryName (exact display name) or -CategoryId.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages (bound from the pipeline).

    .PARAMETER CategoryName
        Exact display name of the device category.

    .PARAMETER CategoryId
        ID of the device category.

    .PARAMETER PassThru
        Return a result object per device.

    .EXAMPLE
        Get-ITManagedDevice -Name 'KIOSK-*' | Set-ITManagedDeviceCategory -CategoryName 'Kiosk'

    .EXAMPLE
        Import-Csv .\devices.csv | Set-ITManagedDeviceCategory -CategoryName 'Finance' -WhatIf

        CSV with an 'Id' column; shows what would change.

    .OUTPUTS
        None, or IntuneToolkit.DeviceActionResult with -PassThru.

    .NOTES
        Graph permission : DeviceManagementManagedDevices.ReadWrite.All
        Graph endpoint   : PUT /deviceManagement/managedDevices/{id}/deviceCategory/$ref
        API version      : beta

    .LINK
        Get-ITDeviceCategory
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$CategoryName,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$CategoryId,

        [switch]$PassThru
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.ReadWrite.All'

        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $category = @(Get-ITDeviceCategory | Where-Object { $_.displayName -eq $CategoryName })
            if ($category.Count -ne 1) {
                $known = (Get-ITDeviceCategory | ForEach-Object { $_.displayName }) -join ', '
                throw "Device category '$CategoryName' not found (or not unique). Existing categories: $known"
            }
            $CategoryId = $category[0].id
        }

        $body = @{ '@odata.id' = '{0}/beta/deviceManagement/deviceCategories/{1}' -f $script:ITConfig.GraphBaseUri.TrimEnd('/'), $CategoryId }
        $label = $CategoryName
        if (-not $label) { $label = $CategoryId }
    }

    process {
        foreach ($deviceId in $Id) {
            $target = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $target = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($target, "Set device category to '$label'")) {
                $status = 'Sent'
                $message = $null
                try {
                    $uri = 'deviceManagement/managedDevices/{0}/deviceCategory/$ref' -f $deviceId
                    $null = Invoke-ITGraphRequest -Uri $uri -Method PUT -Body $body -ApiVersion 'beta'
                }
                catch {
                    $status = 'Failed'
                    $message = $_.Exception.Message
                    Write-Error -ErrorRecord $_
                }
                if ($PassThru) {
                    [pscustomobject]@{
                        PSTypeName = 'IntuneToolkit.DeviceActionResult'
                        DeviceId   = $deviceId
                        DeviceName = $DeviceName
                        Action     = "SetCategory:$label"
                        Status     = $status
                        Message    = $message
                        Timestamp  = Get-Date
                    }
                }
            }
        }
    }
}
