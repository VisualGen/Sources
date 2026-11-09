function Get-ITDeviceBitLockerKey {
    <#
    .SYNOPSIS
        Gets the BitLocker recovery key(s) of a device from Entra ID.

    .DESCRIPTION
        Looks up the recovery keys escrowed for a device and reads each key value.
        Every key read is written to the Entra ID audit log - only use it for real recovery cases.

        Find the device by -DeviceName (looked up in Intune) or pipe Get-ITManagedDevice output
        (uses its azureADDeviceId).

    .PARAMETER DeviceName
        Intune device name. Must match exactly one or more devices.

    .PARAMETER AzureADDeviceId
        Entra ID device ID (the 'azureADDeviceId' property of a managed device). Accepts pipeline input.

    .PARAMETER KeyId
        Return only the key with this recovery key ID (the ID shown on the BitLocker recovery screen).

    .EXAMPLE
        Get-ITDeviceBitLockerKey -DeviceName 'LT-0815'

    .EXAMPLE
        Get-ITManagedDevice -UserPrincipalName 'jane@contoso.com' -OperatingSystem Windows | Get-ITDeviceBitLockerKey

        Keys for all Windows devices of one user.

    .EXAMPLE
        Get-ITDeviceBitLockerKey -DeviceName 'LT-0815' -KeyId '1a2b3c4d-*'

        Only the key whose ID starts with the value the user reads from the recovery screen.

    .OUTPUTS
        IntuneToolkit.BitLockerKey

    .NOTES
        Graph permission : BitLockerKey.Read.All (+ DeviceManagementManagedDevices.Read.All for -DeviceName)
        Graph endpoint   : GET /informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq '{id}'
                           GET /informationProtection/bitlocker/recoveryKeys/{keyId}?$select=key
        API version      : v1.0
        Entra role       : Cloud Device Administrator, Helpdesk Administrator or Intune Administrator

    .LINK
        https://learn.microsoft.com/graph/api/bitlockerrecoverykey-get
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.BitLockerKey')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceName,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AzureADDeviceId,

        [string]$KeyId
    )

    begin {
        $scopes = @('BitLockerKey.Read.All')
        if ($PSCmdlet.ParameterSetName -eq 'ByName') { $scopes += 'DeviceManagementManagedDevices.Read.All' }
        Assert-ITGraphConnection -RequiredScope $scopes
        $headers = Get-ITClientHeader
    }

    process {
        $targets = @()
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $targets = @(Get-ITManagedDevice -Name $DeviceName -Property id, deviceName, azureADDeviceId |
                    Where-Object { $_.azureADDeviceId -and $_.azureADDeviceId -ne '00000000-0000-0000-0000-000000000000' } |
                    ForEach-Object { [pscustomobject]@{ DeviceId = $_.azureADDeviceId; DeviceName = $_.deviceName } })
            if (-not $targets.Count) {
                Write-Error -Message "No Entra-joined/registered Intune device named '$DeviceName' found." -Category ObjectNotFound -TargetObject $DeviceName
                return
            }
        }
        else {
            $targets = @($AzureADDeviceId | ForEach-Object { [pscustomobject]@{ DeviceId = $_; DeviceName = $DeviceName } })
        }

        foreach ($target in $targets) {
            $listUri = New-ITGraphUri -Path 'informationProtection/bitlocker/recoveryKeys' -Filter ("deviceId eq '{0}'" -f (ConvertTo-ITODataString $target.DeviceId))
            try {
                $keys = @(Invoke-ITGraphRequest -Uri $listUri -ApiVersion 'v1.0' -Headers $headers -All)
            }
            catch {
                Write-Error -ErrorRecord $_
                continue
            }

            if ($KeyId) { $keys = @($keys | Where-Object { $_.id -like $KeyId }) }
            if (-not $keys.Count) {
                Write-ITLog -Level Warning -Message "No BitLocker recovery key found for device $($target.DeviceName) ($($target.DeviceId))."
                continue
            }

            foreach ($key in $keys) {
                $keyUri = New-ITGraphUri -Path ('informationProtection/bitlocker/recoveryKeys/{0}' -f $key.id) -Select 'key'
                $value = $null
                try {
                    $value = (Invoke-ITGraphRequest -Uri $keyUri -ApiVersion 'v1.0' -Headers $headers).key
                }
                catch {
                    Write-Error -ErrorRecord $_
                }

                [pscustomobject]@{
                    PSTypeName      = 'IntuneToolkit.BitLockerKey'
                    DeviceName      = $target.DeviceName
                    DeviceId        = $target.DeviceId
                    KeyId           = $key.id
                    VolumeType      = $key.volumeType
                    CreatedDateTime = $key.createdDateTime
                    Key             = $value
                }
            }
        }
    }
}
