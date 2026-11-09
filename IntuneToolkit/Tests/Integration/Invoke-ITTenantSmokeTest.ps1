#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only smoke test of IntuneToolkit against a real tenant.

.DESCRIPTION
    Signs in interactively with READ-ONLY scopes and runs the read commands against Graph.
    Nothing in the tenant is changed. Results (PASS / FAIL / SKIP) are shown on screen and
    written to TestResults\tenant-smoketest.txt; the Graph calls are logged to
    TestResults\tenant-smoketest.log. Both folders are git-ignored (they contain tenant data).

    BitLocker and LAPS reads are written to the Entra ID audit log, so they only run with
    -IncludeSecrets. Even then no key or password is shown or saved - only whether it worked.

.PARAMETER TenantId
    Tenant ID or domain to sign in to. Optional.

.PARAMETER IncludeSecrets
    Also test Get-ITDeviceBitLockerKey and Get-ITDeviceLapsPassword (audited reads).

.PARAMETER UseDeviceCode
    Use the device code sign-in instead of the browser/account picker.

.PARAMETER UseBrowser
    Sign in through the web browser instead of the Windows account picker (WAM), e.g. when the WAM
    window stays hidden behind the editor.

.EXAMPLE
    .\Tests\Integration\Invoke-ITTenantSmokeTest.ps1

.EXAMPLE
    .\Tests\Integration\Invoke-ITTenantSmokeTest.ps1 -IncludeSecrets
#>
[CmdletBinding()]
param(
    [string]$TenantId,

    [switch]$IncludeSecrets,

    [switch]$UseDeviceCode,

    [switch]$UseBrowser
)

$ErrorActionPreference = 'Stop'
$root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outDir    = Join-Path $root 'TestResults'
$null      = New-Item -ItemType Directory -Path $outDir -Force
$resultTxt = Join-Path $outDir 'tenant-smoketest.txt'
$logFile   = Join-Path $outDir 'tenant-smoketest.log'
Remove-Item -Path $resultTxt, $logFile -ErrorAction SilentlyContinue

Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force
Set-ITConfiguration -LogPath $logFile

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Check {
    param([string]$Name, [scriptblock]$Test)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = 'PASS'
    $detail = ''
    try {
        $detail = [string](& $Test)
        if ($detail -like 'SKIP:*') { $status = 'SKIP'; $detail = $detail.Substring(5).Trim() }
    }
    catch {
        $status = 'FAIL'
        $detail = $_.Exception.Message
    }
    $sw.Stop()
    $color = @{ PASS = 'Green'; FAIL = 'Red'; SKIP = 'DarkYellow' }[$status]
    Write-Host ('[{0}] {1,-48} {2,6}ms  {3}' -f $status, $Name, $sw.ElapsedMilliseconds, $detail) -ForegroundColor $color
    $results.Add([pscustomobject]@{ Status = $status; Check = $Name; Ms = $sw.ElapsedMilliseconds; Detail = $detail })
}

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

# ---------------------------------------------------------------------------
Write-Host "`nIntuneToolkit tenant smoke test (read-only)" -ForegroundColor Cyan
Write-Host 'A sign-in window (or device code) will appear - sign in with an Intune admin account.' -ForegroundColor Cyan

$scopes = @('DeviceManagementManagedDevices.Read.All', 'DeviceManagementRBAC.Read.All', 'DeviceManagementServiceConfig.Read.All', 'User.Read.All',
    'DeviceManagementConfiguration.Read.All', 'DeviceManagementApps.Read.All', 'Group.Read.All')
if ($IncludeSecrets) { $scopes += 'BitLockerKey.Read.All', 'DeviceLocalCredential.Read.All' }

$connect = @{ Scopes = $scopes; ContextScope = 'Process' }
if ($TenantId)      { $connect['TenantId'] = $TenantId }
if ($UseDeviceCode) { $connect['UseDeviceCode'] = $true }
if ($UseBrowser)    { $connect['UseBrowser'] = $true }

Invoke-Check 'Connect-ITGraph (read-only scopes)' {
    Connect-ITGraph @connect
    $ctx = Get-ITContext
    Assert-True ($null -ne $ctx) 'No context after connect'
    "tenant $($ctx.TenantId), $($ctx.AuthType)"
}

if (-not (Test-ITGraphConnection)) {
    Write-Host 'Not connected - stopping.' -ForegroundColor Red
    $results | Format-Table -AutoSize | Out-String -Width 250 | Set-Content -Path $resultTxt -Encoding UTF8
    return
}

Invoke-Check 'Test-ITGraphConnection -RequiredScope' {
    Assert-True (Test-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.Read.All') 'Scope not granted (check admin consent)'
    'scope granted'
}

$sample = $null
Invoke-Check 'Get-ITManagedDevice -Top 5' {
    $r = @(Get-ITManagedDevice -Top 5)
    Assert-True ($r.Count -le 5) "Expected <= 5, got $($r.Count)"
    if ($r.Count) {
        Assert-True ($r[0].PSObject.TypeNames[0] -eq 'IntuneToolkit.ManagedDevice') 'Type name missing'
        $script:sample = $r | Where-Object { $_.deviceName } | Select-Object -First 1
    }
    "$($r.Count) device(s)"
}

$allDevices = @()
Invoke-Check 'Get-ITManagedDevice (all pages, 4 properties)' {
    $script:allDevices = @(Get-ITManagedDevice -Property id, deviceName, operatingSystem, userPrincipalName)
    $pages = @(Select-String -Path $logFile -Pattern 'GET .*managedDevices.*page (\d+), attempt 1' -AllMatches |
            ForEach-Object { [int]$_.Matches[0].Groups[1].Value } | Measure-Object -Maximum).Maximum
    $os = ($script:allDevices | Group-Object operatingSystem | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
    "$($script:allDevices.Count) devices, $pages page(s) [$os]"
}

if (-not $sample) {
    Write-Host 'Tenant has no managed devices - device lookups skipped.' -ForegroundColor DarkYellow
}
else {
    Invoke-Check 'Get-ITManagedDevice -Id' {
        $r = Get-ITManagedDevice -Id $sample.id
        Assert-True ($r.id -eq $sample.id) 'Wrong device returned'
        'ok'
    }

    Invoke-Check 'Get-ITManagedDevice -Name (exact, server side)' {
        $r = @(Get-ITManagedDevice -Name $sample.deviceName)
        Assert-True ($r.Count -ge 1) 'Not found by exact name'
        Assert-True (@($r | Where-Object { $_.deviceName -ne $sample.deviceName }).Count -eq 0) 'Returned other names'
        "$($r.Count) match(es)"
    }

    Invoke-Check 'Get-ITManagedDevice -Name Prefix* (startswith)' {
        $prefix = $sample.deviceName.Substring(0, [math]::Min(3, $sample.deviceName.Length))
        $r = @(Get-ITManagedDevice -Name "$prefix*" -Property id, deviceName)
        Assert-True ($r.Count -ge 1) 'Prefix search returned nothing'
        Assert-True (@($r | Where-Object { $_.deviceName -notlike "$prefix*" }).Count -eq 0) 'Prefix not respected'
        "'$prefix*' -> $($r.Count) device(s)"
    }

    Invoke-Check 'Get-ITManagedDevice -Name *x* (local wildcard)' {
        $mid = $sample.deviceName.Substring([math]::Floor($sample.deviceName.Length / 2), 1)
        $r = @(Get-ITManagedDevice -Name "*$mid*" -Property id, deviceName)
        Assert-True ($r.Count -ge 1) 'Wildcard search returned nothing'
        "'*$mid*' -> $($r.Count) device(s)"
    }

    Invoke-Check 'Get-ITManagedDevice -UserPrincipalName' {
        $withUser = $allDevices | Where-Object { $_.userPrincipalName } | Select-Object -First 1
        if (-not $withUser) { return 'SKIP: no device with a primary user' }
        $r = @(Get-ITManagedDevice -UserPrincipalName $withUser.userPrincipalName -Property id, userPrincipalName)
        Assert-True ($r.Count -ge 1) 'Not found by UPN'
        "$($r.Count) device(s) for that user"
    }
}

Invoke-Check 'Get-ITManagedDevice -OperatingSystem -ComplianceState' {
    $r = @(Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant -Property id, deviceName, complianceState)
    Assert-True (@($r | Where-Object { $_.complianceState -ne 'noncompliant' }).Count -eq 0) 'Filter not respected'
    "$($r.Count) non-compliant Windows device(s)"
}

Invoke-Check 'Get-ITManagedDevice -OwnerType company' {
    $r = @(Get-ITManagedDevice -OwnerType company -Top 5)
    "$($r.Count) device(s) (first page)"
}

Invoke-Check 'Get-ITManagedDevice -Filter (raw OData)' {
    $r = @(Get-ITManagedDevice -Filter "managedDeviceOwnerType eq 'company'" -Top 3)
    "$($r.Count) device(s)"
}

Invoke-Check 'Get-ITManagedDevice -ApiVersion beta' {
    $r = @(Get-ITManagedDevice -Top 1 -ApiVersion beta)
    "$($r.Count) device(s), $(if ($r.Count) { @($r[0].PSObject.Properties).Count } else { 0 }) properties"
}

Invoke-Check 'Get-ITStaleDevice -Days 30' {
    $r = @(Get-ITStaleDevice -Days 30)
    $bad = @($r | Where-Object { $null -ne $_.DaysSinceLastSync -and $_.DaysSinceLastSync -lt 30 })
    Assert-True ($bad.Count -eq 0) "$($bad.Count) device(s) younger than 30 days returned"
    if (-not $r.Count) { return '0 stale device(s)' }
    $oldest = ($r | Select-Object -First 1).DaysSinceLastSync
    if ($null -eq $oldest) { $oldest = 'never synced' } else { $oldest = "$oldest day(s)" }
    "$($r.Count) stale device(s), oldest: $oldest"
}

Invoke-Check 'Get-ITDeviceCategory' {
    $r = @(Get-ITDeviceCategory)
    "$($r.Count) categor(y/ies)"
}

Invoke-Check 'Get-ITScopeTag -IncludeAssignment' {
    $r = @(Get-ITScopeTag -IncludeAssignment)
    Assert-True (@($r | Where-Object { $_.id -eq '0' }).Count -eq 1) "Built-in 'Default' tag (Id 0) missing"
    $custom = @($r | Where-Object { -not $_.isBuiltIn })
    $assigned = @($custom | Where-Object { $_.AssignedGroupIds.Count })
    "$($r.Count) tag(s), $($custom.Count) custom, $($assigned.Count) with auto-assignment"
}

# --- Phase 2: Autopilot & enrollment (read-only) ----------------------------
$apDevices = @()
Invoke-Check 'Get-ITAutopilotDevice' {
    $script:apDevices = @(Get-ITAutopilotDevice)
    $states = ($script:apDevices | Group-Object enrollmentState | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
    $tags = @($script:apDevices | Where-Object { $_.groupTag } | Select-Object -ExpandProperty groupTag -Unique).Count
    "$($script:apDevices.Count) device(s) [$states], $tags distinct group tag(s)"
}

Invoke-Check 'Get-ITAutopilotDevice -SerialNumber (server contains)' {
    $withSerial = $apDevices | Where-Object { $_.serialNumber } | Select-Object -First 1
    if (-not $withSerial) { return 'SKIP: no Autopilot device' }
    $part = $withSerial.serialNumber.Substring(0, [math]::Min(4, $withSerial.serialNumber.Length))
    $r = @(Get-ITAutopilotDevice -SerialNumber $part)
    Assert-True (@($r | Where-Object { $_.id -eq $withSerial.id }).Count -eq 1) 'Device not found by partial serial'
    Assert-True (@($r | Where-Object { $_.serialNumber -notlike "*$part*" }).Count -eq 0) 'Filter not respected'
    "'$part' -> $($r.Count) device(s)"
}

Invoke-Check 'Get-ITAutopilotSyncStatus' {
    $s = Get-ITAutopilotSyncStatus
    "status $($s.SyncStatus), last sync $($s.LastSyncDateTime)"
}

Invoke-Check 'Get-ITAutopilotProfile -IncludeAssignment' {
    $r = @(Get-ITAutopilotProfile -IncludeAssignment)
    $join = ($r | Group-Object JoinType | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
    $assigned = @($r | Where-Object { @($_.Assignments).Count }).Count
    "$($r.Count) profile(s) [$join], $assigned assigned"
}

Invoke-Check 'Get-ITEnrollmentRestriction -IncludeAssignment' {
    $r = @(Get-ITEnrollmentRestriction -IncludeAssignment)
    Assert-True (@($r | Where-Object { $_.IsDefault }).Count -ge 1) 'No default restriction found'
    Assert-True ($r[-1].IsDefault) 'Default restriction not sorted last'
    $types = ($r | Group-Object ConfigurationType | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
    "$($r.Count) restriction(s) [$types]"
}

Invoke-Check 'Get-ITEnrollmentStatusPage' {
    $r = @(Get-ITEnrollmentStatusPage)
    Assert-True (@($r | Where-Object { $_.IsDefault }).Count -eq 1) 'Expected exactly one default ESP'
    "$($r.Count) ESP profile(s)"
}

# --- Phase 3-7: policies, apps, scripts, updates, reports, tenant (read-only) ----
$summarise = { param($items, $prop) ($items | Group-Object $prop | Sort-Object Count -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ' }

Invoke-Check 'Get-ITCompliancePolicy -IncludeAssignment' {
    $r = @(Get-ITCompliancePolicy -IncludeAssignment)
    "$($r.Count) policy(ies) [$(& $summarise $r 'Platform')], $(@($r | Where-Object { @($_.Assignments).Count }).Count) assigned"
}

Invoke-Check 'Get-ITDeviceComplianceStatus (first policy)' {
    $p = Get-ITCompliancePolicy | Select-Object -First 1
    if (-not $p) { return 'SKIP: no compliance policy' }
    $r = @($p | Get-ITDeviceComplianceStatus)
    "'$($p.displayName)': $($r.Count) row(s) [$(& $summarise $r 'Status')]"
}

Invoke-Check 'Get-ITNonCompliantDevice -IncludePolicy' {
    $r = @(Get-ITNonCompliantDevice -IncludePolicy)
    "$($r.Count) non-compliant device(s)"
}

Invoke-Check 'Get-ITConfigurationProfile' {
    $r = @(Get-ITConfigurationProfile -ApiVersion beta)
    "$($r.Count) profile(s) [$(& $summarise $r 'ObjectType')]"
}

$scPolicies = @()
Invoke-Check 'Get-ITSettingsCatalogPolicy -IncludeSetting' {
    $script:scPolicies = @(Get-ITSettingsCatalogPolicy -IncludeSetting)
    $settings = ($script:scPolicies | ForEach-Object { @($_.SettingList).Count } | Measure-Object -Sum).Sum
    "$($script:scPolicies.Count) policy(ies), $settings setting value(s)"
}

Invoke-Check 'Get-ITAssignmentFilter' {
    $r = @(Get-ITAssignmentFilter)
    "$($r.Count) filter(s)"
}

Invoke-Check 'Get-ITPolicyAssignment -ResolveName (settings catalog)' {
    if (-not $scPolicies.Count) { return 'SKIP: no settings catalog policy' }
    $r = @($scPolicies | Get-ITPolicyAssignment -ResolveName)
    $unresolved = @($r | Where-Object { $_.GroupId -and -not $_.GroupName }).Count
    "$($r.Count) assignment(s) [$(& $summarise $r 'Intent')], $unresolved group name(s) not resolved"
}

Invoke-Check 'Export-ITPolicy + Compare-ITPolicy (no drift)' {
    $dir = Join-Path $outDir 'Backup'
    Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    $exported = @(Export-ITPolicy -Path $dir -PolicyType Compliance, SettingsCatalog, DeviceConfiguration, Script, Remediation)
    if (-not $exported.Count) { return 'SKIP: nothing to export' }
    $drift = @(Compare-ITPolicy -Path $dir)
    Assert-True ($drift.Count -eq 0) ("{0} difference(s) right after export, e.g. {1} {2}" -f $drift.Count, $drift[0].DisplayName, $drift[0].Property)
    "$($exported.Count) object(s) exported to TestResults\Backup, 0 differences"
}

$apps = @()
Invoke-Check 'Get-ITApp' {
    $script:apps = @(Get-ITApp)
    "$($script:apps.Count) app(s) [$(& $summarise $script:apps 'ObjectType')], $(@($script:apps | Where-Object { -not $_.isAssigned }).Count) unassigned"
}

Invoke-Check 'Get-ITAppInstallStatus (reports API)' {
    $app = $apps | Where-Object { $_.isAssigned } | Select-Object -First 1
    if (-not $app) { return 'SKIP: no assigned app' }
    $r = @($app | Get-ITAppInstallStatus)
    $cols = ''
    if ($r.Count) { $cols = ($r[0].PSObject.Properties.Name | Select-Object -First 6) -join ',' }
    "'$($app.displayName)': $($r.Count) row(s); columns $cols"
}

Invoke-Check 'Get-ITScript + Get-ITScriptRunState' {
    $r = @(Get-ITScript)
    if (-not $r.Count) { return 'SKIP: no platform script' }
    $states = @($r[0] | Get-ITScriptRunState)
    "$($r.Count) script(s); '$($r[0].displayName)': $($states.Count) device result(s)"
}

Invoke-Check 'Get-ITRemediation + Get-ITRemediationResult' {
    $r = @(Get-ITRemediation)
    if (-not $r.Count) { return 'SKIP: no remediation (licence?)' }
    $first = $r | Select-Object -First 1
    $res = @($first | Get-ITRemediationResult)
    "$($r.Count) remediation(s), $(@($r | Where-Object IsBuiltIn).Count) built-in; '$($first.displayName)': $($res.Count) result(s)"
}

Invoke-Check 'Get-ITUpdateRing / Feature / Driver profiles' {
    $rings = @(Get-ITUpdateRing)
    $feature = @(Get-ITFeatureUpdateProfile)
    $driver = @(Get-ITDriverUpdateProfile)
    "$($rings.Count) ring(s), $($feature.Count) feature profile(s), $($driver.Count) driver profile(s)"
}

Invoke-Check 'Get-ITAutopilotImportStatus' {
    $r = @(Get-ITAutopilotImportStatus)
    "$($r.Count) import record(s), $(@($r | Where-Object Status -eq 'error').Count) error(s)"
}

Invoke-Check 'Get-ITRoleDefinition / Get-ITRoleAssignment -ResolveName' {
    $roles = @(Get-ITRoleDefinition)
    $assign = @(Get-ITRoleAssignment -ResolveName)
    "$($roles.Count) role(s) ($(@($roles | Where-Object { -not $_.isBuiltIn }).Count) custom), $($assign.Count) assignment(s)"
}

Invoke-Check 'Get-ITTenantCertificateStatus' {
    $r = @(Get-ITTenantCertificateStatus)
    if (-not $r.Count) { return 'SKIP: no APNs / DEP / VPP configured' }
    ($r | ForEach-Object { "$($_.Type) $($_.Status) ($($_.DaysRemaining) d)" }) -join ', '
}

Invoke-Check 'Get-ITConnectorStatus' {
    $r = @(Get-ITConnectorStatus)
    if (-not $r.Count) { return 'SKIP: no connectors in use' }
    ($r | ForEach-Object { "$($_.Type) $($_.Status)" }) -join ', '
}

Invoke-Check 'Export-ITReport (HTML)' {
    $f = Get-ITCompliancePolicy | Select-Object displayName, Platform, lastModifiedDateTime | Export-ITReport -Path (Join-Path $outDir 'Reports\compliance.html') -Title 'Compliance policies'
    Assert-True ((Get-Content $f.FullName -Raw) -match '<table>|No rows') 'No table in report'
    "report written ($([math]::Round($f.Length / 1KB, 1)) KB)"
}

$script:smokeGroup = $null
Invoke-Check 'Get-ITGroup (types, -Search)' {
    $groups = @(Get-ITGroup -Top 50)
    Assert-True ($groups.Count -gt 0) 'No groups returned'
    $script:smokeGroup = $groups[0]
    $prefix = ($groups[0].displayName -split '[\s_-]')[0]
    $found = @(Get-ITGroup -Search $prefix -Top 10)
    $kinds = ($groups | Group-Object GroupType | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ', '
    '{0} group(s) [{1}], search ''{2}'' -> {3}' -f $groups.Count, $kinds, $prefix, $found.Count
}

Invoke-Check 'Get-ITGroupMember -Recurse / -Transitive, Get-ITGroupOwner' {
    if (-not $script:smokeGroup) { return 'SKIP: no group' }
    $tree = @(Get-ITGroupMember -Id $script:smokeGroup.id -Recurse -MaxDepth 5)
    $flat = @(Get-ITGroupMember -Id $script:smokeGroup.id -Transitive)
    $owners = @(Get-ITGroupOwner -Id $script:smokeGroup.id)
    "'{0}': {1} row(s) in tree, max depth {2}, {3} transitive, {4} owner(s)" -f $script:smokeGroup.displayName, $tree.Count,
        (@($tree | ForEach-Object { $_.Depth }) + 0 | Measure-Object -Maximum).Maximum, $flat.Count, $owners.Count
}

Invoke-Check 'Get-ITGroupAssignment (first assigned group)' {
    $assigned = @(Get-ITCompliancePolicy | Get-ITPolicyAssignment -ErrorAction SilentlyContinue | Where-Object GroupId | Select-Object -First 1)
    if (-not $assigned.Count) { return 'SKIP: no compliance policy assigned to a group' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $rows = @(Get-ITGroupAssignment -Id $assigned[0].GroupId)
    Assert-True (@($rows | Where-Object { $_.PolicyType -eq 'Compliance' -and $_.Via -eq 'Direct' }).Count -gt 0) 'Known compliance assignment not found'
    $kinds = ($rows | Group-Object PolicyType | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ', '
    '{0} assignment(s) [{1}] in {2:N1}s' -f $rows.Count, $kinds, $sw.Elapsed.TotalSeconds
}

Invoke-Check 'Get-ITGroupMembership -Transitive (signed-in user)' {
    $me = (Get-ITContext).Account
    $m = @(Get-ITGroupMembership -Identity $me -Transitive)
    '{0} group(s), {1} direct' -f $m.Count, @($m | Where-Object Direct).Count
}

Invoke-Check 'Format view renders' {
    $text = Get-ITManagedDevice -Top 2 | Out-String
    Assert-True ($text -match 'DeviceName\s+OS\s+OsVersion') 'Default table view not used'
    'table view ok'
}

Invoke-Check 'Error handling: unknown device Id' {
    $err = $null
    $r = Get-ITManagedDevice -Id '00000000-0000-0000-0000-000000000000' -ErrorAction SilentlyContinue -ErrorVariable err
    Assert-True ($null -eq $r) 'Returned an object for an unknown Id'
    Assert-True ($err.Count -ge 1) 'No error written'
    $msg = $err[0].Exception.Message
    Assert-True ($msg -match 'HTTP 4\d\d') "Unexpected message: $msg"
    Assert-True ($msg -notmatch '\}\}') "Raw JSON in message: $msg"
    ($msg -replace '^.*?-> ', '')
}

if ($IncludeSecrets) {
    $win = @($allDevices | Where-Object { $_.operatingSystem -eq 'Windows' })
    Invoke-Check 'Get-ITDeviceBitLockerKey (value not shown)' {
        if (-not $win.Count) { return 'SKIP: no Windows device' }
        foreach ($d in ($win | Select-Object -First 10)) {
            $k = @(Get-ITDeviceBitLockerKey -DeviceName $d.deviceName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            if ($k.Count) {
                Assert-True ($k[0].Key -match '^\d{6}(-\d{6}){7}$') 'Key format unexpected'
                return "key found for 1 device ($($k.Count) key(s))"
            }
        }
        'SKIP: none of the first 10 Windows devices has an escrowed key'
    }

    Invoke-Check 'Get-ITDeviceLapsPassword (value not shown)' {
        if (-not $win.Count) { return 'SKIP: no Windows device' }
        foreach ($d in ($win | Select-Object -First 10)) {
            $c = @(Get-ITDeviceLapsPassword -DeviceName $d.deviceName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            if ($c.Count) {
                Assert-True ($c[0].Password -is [System.Security.SecureString]) 'Password is not a SecureString'
                Assert-True ($c[0].Password.Length -gt 0) 'Empty password'
                return "LAPS credential found (account $($c[0].AccountName))"
            }
        }
        'SKIP: none of the first 10 Windows devices has a LAPS backup'
    }
}
else {
    Invoke-Check 'BitLocker / LAPS' { 'SKIP: run with -IncludeSecrets (audited reads)' }
}

Invoke-Check 'Disconnect-ITGraph' {
    Disconnect-ITGraph
    Assert-True (-not (Test-ITGraphConnection)) 'Still connected'
    'ok'
}

# ---------------------------------------------------------------------------
$summary = '{0} passed, {1} failed, {2} skipped' -f @($results | Where-Object Status -eq 'PASS').Count,
    @($results | Where-Object Status -eq 'FAIL').Count, @($results | Where-Object Status -eq 'SKIP').Count
$color = 'Green'
if (@($results | Where-Object Status -eq 'FAIL').Count) { $color = 'Red' }
Write-Host "`n$summary" -ForegroundColor $color

$header = 'IntuneToolkit tenant smoke test {0:yyyy-MM-dd HH:mm} - PS {1} - {2}' -f (Get-Date), $PSVersionTable.PSVersion, $summary
@($header, ($results | Format-Table -AutoSize -Wrap | Out-String -Width 250)) | Set-Content -Path $resultTxt -Encoding UTF8
Write-Host "Results: $resultTxt"
Write-Host "Graph log: $logFile"
