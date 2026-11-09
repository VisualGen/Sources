function Import-ITAutopilotDevice {
    <#
    .SYNOPSIS
        Registers devices in Windows Autopilot from hardware hashes (CSV or pipeline).

    .DESCRIPTION
        Uploads hardware hashes as created by Get-WindowsAutopilotInfo or OEM/partner CSV files.
        Accepted column names: 'Device Serial Number' or SerialNumber, 'Hardware Hash' or
        HardwareHash, 'Windows Product ID' or ProductKey, 'Group Tag' or GroupTag,
        'Assigned User' or AssignedUser.

        Without -Wait the upload is only submitted (Status 'Submitted'). With -Wait the function
        polls until every device is 'complete' or 'error' (or -TimeoutMinutes), removes the
        temporary import records of completed devices, and with -Sync starts an Autopilot sync so
        the devices appear in Get-ITAutopilotDevice sooner.

    .PARAMETER Path
        CSV file with hardware hashes.

    .PARAMETER SerialNumber
        Device serial number (pipeline: 'Device Serial Number' or SerialNumber).

    .PARAMETER HardwareHash
        Base64 hardware hash (pipeline: 'Hardware Hash' or HardwareHash).

    .PARAMETER ProductKey
        Windows product ID (optional; pipeline: 'Windows Product ID' or ProductKey).

    .PARAMETER GroupTag
        Group tag. With -Path it overrides the CSV column for every row.

    .PARAMETER AssignedUser
        UPN of the user to pre-assign (optional; user-driven mode only).

    .PARAMETER Wait
        Wait until the import has finished for every device.

    .PARAMETER TimeoutMinutes
        Maximum wait time with -Wait. Default 30.

    .PARAMETER Sync
        Start an Autopilot sync after a successful import (requires -Wait).

    .EXAMPLE
        Import-ITAutopilotDevice -Path .\AutopilotHWID.csv -Wait

        Imports a hash file and shows the result per device.

    .EXAMPLE
        Import-ITAutopilotDevice -Path .\NewLaptops.csv -GroupTag 'Sales' -Wait -Sync

        Imports with group tag 'Sales' for all rows and syncs Autopilot afterwards.

    .EXAMPLE
        Import-Csv .\Hashes.csv | Where-Object 'Device Serial Number' -like 'PF*' | Import-ITAutopilotDevice -WhatIf

        Shows which rows would be imported.

    .OUTPUTS
        IntuneToolkit.AutopilotImportResult

    .NOTES
        Graph permission : DeviceManagementServiceConfig.ReadWrite.All
        Graph endpoint   : POST /deviceManagement/importedWindowsAutopilotDeviceIdentities
                           GET / DELETE /deviceManagement/importedWindowsAutopilotDeviceIdentities/{id}
        API version      : v1.0
        Common errors    : 806 ZtdDeviceAlreadyAssigned (already registered in this tenant),
                           808 ZtdDeviceAssignedToOtherTenant (deregister it in the other tenant first)

    .LINK
        https://learn.microsoft.com/graph/api/intune-enrollment-importedwindowsautopilotdeviceidentity-create
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Path')]
    [OutputType('IntuneToolkit.AutopilotImportResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipelineByPropertyName)]
        [Alias('Device Serial Number')]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipelineByPropertyName)]
        [Alias('Hardware Hash')]
        [ValidateNotNullOrEmpty()]
        [string]$HardwareHash,

        [Parameter(ParameterSetName = 'Object', ValueFromPipelineByPropertyName)]
        [Alias('Windows Product ID')]
        [AllowEmptyString()]
        [string]$ProductKey,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Group Tag')]
        [AllowEmptyString()]
        [string]$GroupTag,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Assigned User')]
        [AllowEmptyString()]
        [string]$AssignedUser,

        [switch]$Wait,

        [ValidateRange(1, 240)]
        [int]$TimeoutMinutes = 30,

        [switch]$Sync
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.ReadWrite.All'
        $basePath = 'deviceManagement/importedWindowsAutopilotDeviceIdentities'
        $rows = New-Object -TypeName System.Collections.Generic.List[object]
        $groupTagOverride = $null
        if ($PSCmdlet.ParameterSetName -eq 'Path' -and $PSBoundParameters.ContainsKey('GroupTag')) { $groupTagOverride = $GroupTag }

        # Reads a column by any of its accepted names (Strict Mode safe)
        function Get-Column($Row, [string[]]$Names) {
            foreach ($n in $Names) {
                $p = $Row.PSObject.Properties[$n]
                if ($p -and $p.Value) { return [string]$p.Value }
            }
            ''
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($row in (Import-Csv -Path $Path)) {
                $tag = Get-Column $row 'Group Tag', 'GroupTag'
                if ($null -ne $groupTagOverride) { $tag = $groupTagOverride }
                $rows.Add([pscustomobject]@{
                        SerialNumber = Get-Column $row 'Device Serial Number', 'SerialNumber'
                        HardwareHash = Get-Column $row 'Hardware Hash', 'HardwareHash'
                        ProductKey   = Get-Column $row 'Windows Product ID', 'ProductKey'
                        GroupTag     = $tag
                        AssignedUser = Get-Column $row 'Assigned User', 'AssignedUser'
                    })
            }
        }
        else {
            $rows.Add([pscustomobject]@{
                    SerialNumber = $SerialNumber
                    HardwareHash = $HardwareHash
                    ProductKey   = $ProductKey
                    GroupTag     = $GroupTag
                    AssignedUser = $AssignedUser
                })
        }
    }

    end {
        $results = New-Object -TypeName System.Collections.Generic.List[object]

        foreach ($row in $rows) {
            $result = [pscustomobject]@{
                PSTypeName   = 'IntuneToolkit.AutopilotImportResult'
                SerialNumber = $row.SerialNumber
                GroupTag     = $row.GroupTag
                ImportId     = $null
                Status       = 'NotSubmitted'
                ErrorCode    = $null
                ErrorName    = $null
                Message      = $null
            }

            if (-not $row.SerialNumber -or -not $row.HardwareHash) {
                $result.Status = 'Invalid'
                $result.Message = 'Serial number or hardware hash missing.'
                Write-Error -Message "Row skipped: $($result.Message) (serial '$($row.SerialNumber)')" -Category InvalidData
                $results.Add($result)
                continue
            }
            try {
                $null = [Convert]::FromBase64String($row.HardwareHash)
            }
            catch {
                $result.Status = 'Invalid'
                $result.Message = 'Hardware hash is not valid Base64.'
                Write-Error -Message "Row skipped: $($result.Message) (serial '$($row.SerialNumber)')" -Category InvalidData
                $results.Add($result)
                continue
            }

            $what = 'Register in Windows Autopilot'
            if ($row.GroupTag) { $what = "$what (group tag '$($row.GroupTag)')" }
            if (-not $PSCmdlet.ShouldProcess("Serial $($row.SerialNumber)", $what)) { continue }

            $body = @{
                '@odata.type'             = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
                serialNumber              = $row.SerialNumber
                hardwareIdentifier        = $row.HardwareHash
                productKey                = [string]$row.ProductKey
                groupTag                  = [string]$row.GroupTag
                assignedUserPrincipalName = [string]$row.AssignedUser
                state                     = @{
                    '@odata.type'        = 'microsoft.graph.importedWindowsAutopilotDeviceIdentityState'
                    deviceImportStatus   = 'pending'
                    deviceRegistrationId = ''
                    deviceErrorCode      = 0
                    deviceErrorName      = ''
                }
            }

            try {
                $created = Invoke-ITGraphRequest -Uri $basePath -Method POST -Body $body -ApiVersion 'v1.0'
                $result.ImportId = $created.id
                $result.Status = 'Submitted'
                Write-ITLog -Message "Autopilot import submitted for $($row.SerialNumber) (import id $($created.id))."
            }
            catch {
                $result.Status = 'Failed'
                $result.Message = $_.Exception.Message
                Write-Error -ErrorRecord $_
            }
            $results.Add($result)
        }

        # --- Wait for completion ------------------------------------------
        if ($Wait) {
            $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
            $open = @($results | Where-Object { $_.Status -eq 'Submitted' })
            $maxPolls = $TimeoutMinutes * 4 + 1   # 15-second polls; hard stop independent of the clock
            $polls = 0
            while ($open.Count -and (Get-Date) -lt $deadline -and $polls -lt $maxPolls) {
                $polls++
                Write-Progress -Activity 'Autopilot import' -Status "$($open.Count) device(s) still processing"
                Start-Sleep -Seconds 15
                foreach ($item in $open) {
                    try {
                        $state = (Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $item.ImportId) -ApiVersion 'v1.0').state
                    }
                    catch {
                        Write-ITLog -Level Warning -Message "Status check for $($item.SerialNumber) failed: $($_.Exception.Message)"
                        continue
                    }
                    switch ($state.deviceImportStatus) {
                        'complete' { $item.Status = 'Complete' }
                        'error' {
                            $item.Status = 'Error'
                            $item.ErrorCode = $state.deviceErrorCode
                            $item.ErrorName = $state.deviceErrorName
                        }
                    }
                }
                $open = @($results | Where-Object { $_.Status -eq 'Submitted' })
            }
            Write-Progress -Activity 'Autopilot import' -Completed
            foreach ($item in $open) {
                $item.Status = 'Timeout'
                $item.Message = "Still processing after $TimeoutMinutes minute(s); check later with Get-ITAutopilotDevice."
            }

            # Remove temporary import records of completed devices (they are not needed anymore)
            foreach ($item in @($results | Where-Object { $_.Status -eq 'Complete' })) {
                try {
                    $null = Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $basePath, $item.ImportId) -Method DELETE -ApiVersion 'v1.0'
                }
                catch {
                    Write-ITLog -Level Warning -Message "Could not remove import record $($item.ImportId): $($_.Exception.Message)"
                }
            }

            if ($Sync -and @($results | Where-Object { $_.Status -eq 'Complete' }).Count) {
                $null = Invoke-ITAutopilotSync -Confirm:$false
            }
        }
        elseif ($Sync) {
            Write-ITLog -Level Warning -Message '-Sync is only used together with -Wait; no sync started.'
        }

        $results
    }
}
