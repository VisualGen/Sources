function Set-ITManagedDevicePrimaryUser {
    <#
    .SYNOPSIS
        Changes the primary user of one or more managed devices.

    .DESCRIPTION
        Sets the Intune primary user (shown in Company Portal and used for user-targeted
        assignments and reports). Specify the user by -UserPrincipalName or -UserId.

    .PARAMETER Id
        Intune managed device ID(s). Accepts pipeline input from Get-ITManagedDevice.

    .PARAMETER DeviceName
        Device name, used only for messages (bound from the pipeline).

    .PARAMETER UserPrincipalName
        UPN of the new primary user.

    .PARAMETER UserId
        Entra ID object ID of the new primary user.

    .PARAMETER PassThru
        Return a result object per device.

    .EXAMPLE
        Get-ITManagedDevice -Name 'LT-0815' | Set-ITManagedDevicePrimaryUser -UserPrincipalName 'new.owner@contoso.com'

    .EXAMPLE
        Import-Csv .\handover.csv | ForEach-Object {
            Get-ITManagedDevice -Name $_.DeviceName | Set-ITManagedDevicePrimaryUser -UserPrincipalName $_.NewUser -PassThru
        }

        Bulk device hand-over from a CSV with DeviceName and NewUser columns.

    .OUTPUTS
        None, or IntuneToolkit.DeviceActionResult with -PassThru.

    .NOTES
        Graph permission : DeviceManagementManagedDevices.ReadWrite.All, User.Read.All (for -UserPrincipalName)
        Graph endpoint   : POST /deviceManagement/managedDevices/{id}/users/$ref
        API version      : beta
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByUpn')]
    [OutputType('IntuneToolkit.DeviceActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ManagedDeviceId')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceName,

        [Parameter(Mandatory, ParameterSetName = 'ByUpn')]
        [ValidatePattern('^[^@\s]+@[^@\s]+$')]
        [string]$UserPrincipalName,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string]$UserId,

        [switch]$PassThru
    )

    begin {
        $scopes = @('DeviceManagementManagedDevices.ReadWrite.All')
        if ($PSCmdlet.ParameterSetName -eq 'ByUpn') { $scopes += 'User.Read.All' }
        Assert-ITGraphConnection -RequiredScope $scopes

        $label = $UserId
        if ($PSCmdlet.ParameterSetName -eq 'ByUpn') {
            $userUri = New-ITGraphUri -Path ('users/{0}' -f [uri]::EscapeDataString($UserPrincipalName)) -Select 'id', 'userPrincipalName'
            $user = Invoke-ITGraphRequest -Uri $userUri -ApiVersion 'v1.0'
            $UserId = $user.id
            $label = $UserPrincipalName
        }

        $body = @{ '@odata.id' = '{0}/beta/users/{1}' -f $script:ITConfig.GraphBaseUri.TrimEnd('/'), $UserId }
    }

    process {
        foreach ($deviceId in $Id) {
            $target = $deviceId
            if ($DeviceName -and $Id.Count -eq 1) { $target = '{0} ({1})' -f $DeviceName, $deviceId }
            if ($PSCmdlet.ShouldProcess($target, "Set primary user to '$label'")) {
                $status = 'Sent'
                $message = $null
                try {
                    $uri = 'deviceManagement/managedDevices/{0}/users/$ref' -f $deviceId
                    $null = Invoke-ITGraphRequest -Uri $uri -Method POST -Body $body -ApiVersion 'beta'
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
                        Action     = "SetPrimaryUser:$label"
                        Status     = $status
                        Message    = $message
                        Timestamp  = Get-Date
                    }
                }
            }
        }
    }
}
