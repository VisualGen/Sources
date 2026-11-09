function Get-ITTenantCertificateStatus {
    <#
    .SYNOPSIS
        Gets the expiry of the Apple tokens and certificates Intune depends on (APNs, ADE/DEP, VPP).

    .DESCRIPTION
        Monthly check. When one of these expires, Apple devices stop being managed (APNs),
        new devices cannot enrol automatically (ADE/DEP) or apps stop deploying (VPP).
        Returns one row per token: Type (APNs, DEP, VPP), Name, AppleId, ExpirationDateTime,
        DaysRemaining and Status: OK, Warning (fewer than -WarningDays days left) or Expired.
        Types that are not configured in the tenant are skipped.

    .PARAMETER WarningDays
        Days before expiry that count as Warning. Default: 30.

    .EXAMPLE
        Get-ITTenantCertificateStatus

    .EXAMPLE
        Get-ITTenantCertificateStatus | Where-Object Status -ne 'OK'

        Only tokens that need attention (use in the monthly scheduled report).

    .OUTPUTS
        IntuneToolkit.TenantCertificateStatus

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All (APNs, DEP), DeviceManagementApps.Read.All (VPP)
        Graph endpoint   : GET /deviceManagement/applePushNotificationCertificate
                           GET /deviceManagement/depOnboardingSettings
                           GET /deviceAppManagement/vppTokens
        API version      : beta

    .LINK
        Get-ITConnectorStatus
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.TenantCertificateStatus')]
    param(
        [ValidateRange(1, 365)]
        [int]$WarningDays = 30
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'
    $get = { param($o, $n) if ($o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    $now = Get-Date
    $warnAt = $WarningDays

    $newRow = {
        param($type, $name, $appleId, $expires, $state, $id)
        $daysLeft = $null
        $status = 'Unknown'
        $expiry = [datetime]::MinValue
        if ($expires -and [datetime]::TryParse([string]$expires, [ref]$expiry)) {
            $daysLeft = [int][math]::Floor(($expiry - $now).TotalDays)
            if ($daysLeft -lt 0) { $status = 'Expired' } elseif ($daysLeft -lt $warnAt) { $status = 'Warning' } else { $status = 'OK' }
        }
        [pscustomobject]@{
            PSTypeName         = 'IntuneToolkit.TenantCertificateStatus'
            Type               = $type
            Name               = $name
            AppleId            = $appleId
            ExpirationDateTime = $expires
            DaysRemaining      = $daysLeft
            Status             = $status
            State              = $state
            Id                 = $id
        }
    }

    # Not configured -> 404 (or 400 for some tenants): skip quietly
    $notConfigured = { param($err) $err.Exception.Message -match 'HTTP 404|NotFound|HTTP 400' }

    try {
        $apns = Invoke-ITGraphRequest -Uri 'deviceManagement/applePushNotificationCertificate' -ApiVersion 'beta'
        if ($apns -and (& $get $apns 'expirationDateTime')) {
            & $newRow 'APNs' (& $get $apns 'topicIdentifier') (& $get $apns 'appleIdentifier') (& $get $apns 'expirationDateTime') (& $get $apns 'certificateUploadStatus') (& $get $apns 'id')
        }
    }
    catch {
        if (-not (& $notConfigured $_)) { Write-Error -ErrorRecord $_ }
    }

    try {
        foreach ($dep in @(Invoke-ITGraphRequest -Uri 'deviceManagement/depOnboardingSettings' -ApiVersion 'beta' -All | Where-Object { $_ })) {
            & $newRow 'DEP' (& $get $dep 'tokenName') (& $get $dep 'appleIdentifier') (& $get $dep 'tokenExpirationDateTime') (& $get $dep 'lastSyncErrorCode') (& $get $dep 'id')
        }
    }
    catch {
        if (-not (& $notConfigured $_)) { Write-Error -ErrorRecord $_ }
    }

    try {
        foreach ($vpp in @(Invoke-ITGraphRequest -Uri 'deviceAppManagement/vppTokens' -ApiVersion 'beta' -All | Where-Object { $_ })) {
            & $newRow 'VPP' (& $get $vpp 'organizationName') (& $get $vpp 'appleId') (& $get $vpp 'expirationDateTime') (& $get $vpp 'state') (& $get $vpp 'id')
        }
    }
    catch {
        if (-not (& $notConfigured $_)) { Write-Error -ErrorRecord $_ }
    }
}
