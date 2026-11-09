function Get-ITDeviceLapsPassword {
    <#
    .SYNOPSIS
        Gets the Windows LAPS local administrator password of a device from Entra ID.

    .DESCRIPTION
        Reads the local administrator credential that Windows LAPS backed up to Entra ID.
        The password is returned as a SecureString unless -AsPlainText is used, so it is not
        shown on screen or written to transcripts by accident. Every read is audited in Entra ID.

        Only the current password is returned unless -IncludeHistory is used.

    .PARAMETER DeviceName
        Device name as known in Entra ID.

    .PARAMETER AzureADDeviceId
        Entra ID device ID (the 'azureADDeviceId' property of a managed device). Accepts pipeline input.

    .PARAMETER AsPlainText
        Return the password as plain text instead of a SecureString.

    .PARAMETER IncludeHistory
        Also return previous passwords that are still stored.

    .EXAMPLE
        Get-ITDeviceLapsPassword -DeviceName 'LT-0815'

        Shows account name and backup date; the password stays a SecureString.

    .EXAMPLE
        (Get-ITDeviceLapsPassword -DeviceName 'LT-0815' -AsPlainText).Password

        Shows the current password in clear text.

    .EXAMPLE
        $cred = Get-ITDeviceLapsPassword -DeviceName 'LT-0815'
        $credential = New-Object System.Management.Automation.PSCredential ("LT-0815\$($cred.AccountName)", $cred.Password)
        Enter-PSSession -ComputerName 'LT-0815' -Credential $credential

        Uses the LAPS password for a remote session without ever showing it.

    .OUTPUTS
        IntuneToolkit.LapsCredential

    .NOTES
        Graph permission : DeviceLocalCredential.Read.All
        Graph endpoint   : GET /directory/deviceLocalCredentials/{deviceId}?$select=credentials
        API version      : v1.0
        Entra role       : Cloud Device Administrator, Intune Administrator or a custom role with
                           microsoft.directory/deviceLocalCredentials/password/read

    .LINK
        https://learn.microsoft.com/graph/api/devicelocalcredentialinfo-get
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.LapsCredential')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceName,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AzureADDeviceId,

        [switch]$AsPlainText,

        [switch]$IncludeHistory
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceLocalCredential.Read.All'
        $headers = Get-ITClientHeader
        $basePath = 'directory/deviceLocalCredentials'
    }

    process {
        $deviceIds = @()
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $listUri = New-ITGraphUri -Path $basePath -Filter ("deviceName eq '{0}'" -f (ConvertTo-ITODataString $DeviceName))
            try {
                $deviceIds = @(Invoke-ITGraphRequest -Uri $listUri -ApiVersion 'v1.0' -Headers $headers -All | ForEach-Object { $_.id })
            }
            catch {
                Write-Error -ErrorRecord $_
                return
            }
            if (-not $deviceIds.Count) {
                Write-Error -Message "No LAPS password backed up for a device named '$DeviceName'." -Category ObjectNotFound -TargetObject $DeviceName
                return
            }
        }
        else {
            $deviceIds = $AzureADDeviceId
        }

        foreach ($deviceId in $deviceIds) {
            $uri = New-ITGraphUri -Path ('{0}/{1}' -f $basePath, $deviceId) -Select 'id', 'deviceName', 'lastBackupDateTime', 'refreshDateTime', 'credentials'
            try {
                $info = Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0' -Headers $headers
            }
            catch {
                Write-Error -ErrorRecord $_
                continue
            }

            $name = $DeviceName
            if ($info.PSObject.Properties['deviceName'] -and $info.deviceName) { $name = $info.deviceName }

            $credentials = @()
            if ($info.PSObject.Properties['credentials']) {
                $credentials = @($info.credentials | Where-Object { $_ } | Sort-Object -Property { [datetime]$_.backupDateTime } -Descending)
            }
            if (-not $credentials.Count) {
                Write-ITLog -Level Warning -Message "Device $name ($deviceId) has no stored LAPS credential."
                continue
            }
            if (-not $IncludeHistory) { $credentials = @($credentials[0]) }

            $refresh = $null
            if ($info.PSObject.Properties['refreshDateTime']) { $refresh = $info.refreshDateTime }

            foreach ($credential in $credentials) {
                $plain = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($credential.passwordBase64))
                if ($AsPlainText) {
                    $password = $plain
                }
                else {
                    $password = New-Object -TypeName System.Security.SecureString
                    foreach ($char in $plain.ToCharArray()) { $password.AppendChar($char) }
                    $password.MakeReadOnly()
                }
                $plain = $null

                [pscustomobject]@{
                    PSTypeName      = 'IntuneToolkit.LapsCredential'
                    DeviceName      = $name
                    DeviceId        = $deviceId
                    AccountName     = $credential.accountName
                    AccountSid      = $credential.accountSid
                    BackupDateTime  = $credential.backupDateTime
                    RefreshDateTime = $refresh
                    Password        = $password
                }
            }
        }
    }
}
