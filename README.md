# IntuneToolkit

PowerShell module for **Microsoft Intune** management through **Microsoft Graph**, built for
**Windows PowerShell 5.1** (no PowerShell 7 required).

- Version: see [`CHANGELOG.md`](CHANGELOG.md)
- Design, naming conventions and roadmap: [`docs/Framework.md`](docs/Framework.md)

## Requirements

| Item | Version |
|---|---|
| Windows PowerShell | 5.1 (.NET Framework 4.7.2+) |
| [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication) | 2.0.0 or later |
| Intune role | Intune Administrator, or a custom role with the permissions each function lists in `.NOTES` |

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

Check a machine after loading the module (it also loads without the Graph module, so this tells you what is missing):

```powershell
Import-Module .\src\IntuneToolkit\IntuneToolkit.psd1
Test-ITPrerequisite            # PowerShell, .NET, TLS 1.2, Graph module installed / loaded / same versions
Test-ITPrerequisite -Quiet     # $true or $false, for scripts
```

## Install

**From the repository** (development):

```powershell
Import-Module .\src\IntuneToolkit\IntuneToolkit.psd1 -Force
```

**From a release zip**: extract `IntuneToolkit-<version>.zip` into
`$HOME\Documents\WindowsPowerShell\Modules\` so the path is
`...\Modules\IntuneToolkit\<version>\IntuneToolkit.psd1`, then:

```powershell
Import-Module IntuneToolkit
```

## Quick start

```powershell
# Sign in (read-only Intune scopes by default)
Connect-ITGraph
Connect-ITGraph -UseBrowser    # web browser instead of the Windows account picker (WAM), e.g. in the VS Code terminal

# Who / where am I?
Get-ITContext

# Use the beta endpoint by default
Set-ITConfiguration -DefaultApiVersion beta

# Help for any command
Get-Command -Module IntuneToolkit
Get-Help Connect-ITGraph -Examples

Disconnect-ITGraph
Disconnect-ITGraph -Force      # end any leftover session (also after a failed sign-in); next sign-in asks again
```

More scenarios: [`Examples/`](Examples) — `30-Policies`, `40-Apps`, `50-ScriptsAndUpdates`, `60-Tenant`.

### Logging a script

Add one line at the top and one at the end; the IntuneToolkit commands then log on their own:

```powershell
Import-Module IntuneToolkit
Start-ITLog                    # %TEMP%\IntuneToolkit, or the Intune log folder when Intune runs the script
try {
    Connect-ITGraph
    $stale = Get-ITStaleDevice -Days 60
    if (-not $stale) { Write-ITLog 'No stale devices' -Level Warning }
    $stale | Export-ITReport -Path "$env:TEMP\stale.html"
    $status = 'Success'
}
catch {
    Write-ITLog -ErrorRecord $_ -Message 'Stale device report failed'   # message, exception, line, call stack
    $status = 'Failed'
}
finally { Stop-ITLog -Status $status }
```

Your own events: `Write-ITLog '<text>'` (Info), `-Level Warning`, `-Level Error`, or `-ErrorRecord $_` in a `catch`.
Errors are shown in red but do not create a PowerShell error, so the script continues; the closing summary counts the
errors and warnings your script logged (`errors logged: 2 | warnings logged: 1 | PowerShell errors recorded: 0`).

| File | Content |
|---|---|
| `<Script>_<yyyyMMdd-HHmmss>.log` | IntuneToolkit log in **CMTrace format** (open with CMTrace.exe / OneTrace; warnings yellow, errors red): start header (script, user, SYSTEM, Intune detected), every Graph request / retry / action / warning, the script's errors and a closing summary |
| `<Script>_<yyyyMMdd-HHmmss>.transcript.log` | Transcript of everything the script prints (`-NoTranscript` to skip) |

Folder: `-Path` (folder or `.log` file) > `%ProgramData%\Microsoft\IntuneManagementExtension\Logs` when the script runs
as an Intune platform script, remediation or Win32 app (or with `-Intune`; collected with *Collect diagnostics*) >
`%TEMP%\IntuneToolkit`. Logs of the same name older than 30 days are deleted (`-RetentionDays`).

### Scheduled reports

[`Examples/Scheduled`](Examples/Scheduled) has `Daily.ps1`, `Weekly.ps1` and `Monthly.ps1` for Task Scheduler or
Azure Automation. They are read-only, write CSV + HTML per report and a `Summary.html` to
`C:\IntuneReports\<Daily|Weekly|Monthly>\<date>\`, and the monthly run also writes a JSON configuration backup.
Unattended runs use an app registration with a certificate (application permissions are listed in each script):

```powershell
.\Examples\Scheduled\Daily.ps1 -TenantId contoso.onmicrosoft.com -ClientId <app id> -CertificateThumbprint <thumbprint>
```

## Commands

| Area | Command | Purpose |
|---|---|---|
| Connection | `Connect-ITGraph` | Sign in: interactive, device code, certificate, secret, managed identity |
| | `Disconnect-ITGraph` | Sign out |
| | `Get-ITContext` | Current tenant, account, scopes, API version |
| | `Test-ITGraphConnection` | `$true` if connected with the required scopes |
| Module | `Get-ITConfiguration` / `Set-ITConfiguration` | Module defaults (API version, retries, page size, log) |
| | `Start-ITLog` / `Stop-ITLog` | Log a whole script: temp folder, Intune log folder or custom path; closes with a summary |
| | `Write-ITLog` | Your own Info / Warning / Error events in that log; `-ErrorRecord $_` logs a caught error with line and call stack |
| | `Test-ITPrerequisite` | Is the Graph module installed, loaded and consistent? PowerShell, .NET and TLS 1.2 checks |
| Devices | `Get-ITManagedDevice` | Find devices by name/prefix, user, OS, compliance, ownership, last sync |
| | `Get-ITStaleDevice` | Devices without check-in for N days |
| | `Invoke-ITDeviceSync` / `-Restart` / `-Retire` / `-Wipe` | Remote actions (pipeline, `-WhatIf`) |
| | `Invoke-ITDefenderScan` / `Invoke-ITBitLockerKeyRotation` | Security actions |
| | `Remove-ITManagedDevice` | Delete device record |
| | `Get-ITDeviceBitLockerKey` / `Get-ITDeviceLapsPassword` | Recovery key / local admin password (audited) |
| | `Get-ITDeviceCategory` / `Set-ITManagedDeviceCategory` | Device categories |
| | `Set-ITManagedDevicePrimaryUser` | Change primary user |
| Autopilot | `Get-ITAutopilotDevice` | Registered devices (serial, group tag, model, state) |
| | `Import-ITAutopilotDevice` | Register hardware hashes from CSV (`-Wait`, `-Sync`) |
| | `Set-ITAutopilotDevice` / `Remove-ITAutopilotDevice` | Group tag / user / name; deregister |
| | `Invoke-ITAutopilotSync` / `Get-ITAutopilotSyncStatus` | Sync with the deployment service |
| | `Get-ITAutopilotProfile` | Deployment profiles with assignments |
| Enrollment | `Get-ITEnrollmentRestriction` / `Get-ITEnrollmentStatusPage` | Restrictions, device limits, ESP |
| Compliance | `Get-ITCompliancePolicy` | Compliance policies with platform and assignments |
| | `Get-ITDeviceComplianceStatus` | Compliance per device and policy (pipe a policy or a device) |
| | `Get-ITNonCompliantDevice` | Non-compliant devices, `-IncludePolicy` adds the failing policies |
| Configuration | `Get-ITConfigurationProfile` | Template-based profiles (Wi-Fi, VPN, custom OMA-URI, ...) |
| | `Get-ITSettingsCatalogPolicy` | Settings catalog policies, `-IncludeSetting` lists every configured value |
| | `Get-ITAssignmentFilter` | Assignment filters |
| Assignments | `Get-/Add-/Remove-ITPolicyAssignment` | Assignments of any policy, profile, script, remediation or update profile |
| Backup | `Export-ITPolicy` / `Import-ITPolicy` | JSON backup, restore, copy to another tenant |
| | `Compare-ITPolicy` | Drift between a backup and the tenant |
| Apps | `Get-ITApp` | Apps by type, platform, assigned / unassigned |
| | `Get-/Add-/Remove-ITAppAssignment` | Required / available / uninstall assignments |
| | `Get-ITAppInstallStatus` | Install status per app or per device (`-FailedOnly`, `-Since`) |
| | `New-ITWin32App` | Upload a `.intunewin` as a Win32 app |
| Scripts | `Get-/New-/Export-ITScript`, `Get-ITScriptRunState` | PowerShell platform scripts and their results |
| | `Get-/New-ITRemediation`, `Get-ITRemediationResult` | Remediations and their per-device results |
| | `Invoke-ITRemediationOnDemand` | Run a remediation on a device now |
| Updates | `Get-ITUpdateRing`, `Suspend-/Resume-ITUpdateRing` | Update rings, pause / resume quality or feature updates |
| | `Get-ITFeatureUpdateProfile` / `Get-ITDriverUpdateProfile` | Feature (end of support) and driver update profiles |
| Reports | `Export-ITReport` | CSV or self-contained HTML from any pipeline |
| | `Get-ITAutopilotImportStatus` | Pending / failed Autopilot imports |
| Groups | `Get-ITGroup` | Find Entra ID groups: name/prefix/wildcard, word search, type, dynamic, member count |
| | `New-ITGroup` / `Set-ITGroup` / `Rename-ITGroup` / `Remove-ITGroup` | Create (assigned or dynamic), change, rename, delete |
| | `Get-ITGroupMember` | Members; `-Recurse` shows the nested-group tree, `-Transitive` the flat list |
| | `Add-ITGroupMember` / `Remove-ITGroupMember` | Users, devices (pipe `Get-ITManagedDevice`) or nested groups |
| | `Get-ITGroupMembership` | Which groups a user, device or group is in (`-Transitive`) |
| | `Get-/Add-/Remove-ITGroupOwner` | Group owners |
| | `Get-ITGroupAssignment` | Everything Intune assigns to a group (policies, scripts, updates, apps), also through parent groups |
| Tenant | `Get-ITScopeTag` | Scope tags, optionally with their auto-assignment groups |
| | `Get-ITRoleDefinition` / `Get-ITRoleAssignment` | Intune RBAC roles and who has them |
| | `Get-ITTenantCertificateStatus` | APNs, ADE/DEP and VPP expiry |
| | `Get-ITConnectorStatus` | Connector health (AD, NDES, Exchange, MTD, partners) |

### Permissions per area

| Area | Delegated scopes |
|---|---|
| Read devices | `DeviceManagementManagedDevices.Read.All` |
| Remote actions (sync, restart, retire, wipe, scan, key rotation) | `DeviceManagementManagedDevices.PrivilegedOperations.All` |
| Delete record, category, primary user | `DeviceManagementManagedDevices.ReadWrite.All` (+ `User.Read.All` for UPN lookup) |
| BitLocker key | `BitLockerKey.Read.All` |
| LAPS password | `DeviceLocalCredential.Read.All` |
| Scope tags | `DeviceManagementRBAC.Read.All` (included in the `Connect-ITGraph` defaults) |
| Read Autopilot / enrollment | `DeviceManagementServiceConfig.Read.All` (included in the defaults) |
| Import / change / remove Autopilot devices, sync | `DeviceManagementServiceConfig.ReadWrite.All` |
| Read policies, profiles, scripts, updates, filters | `DeviceManagementConfiguration.Read.All` (included in the defaults) |
| Assign, import, create scripts/remediations, pause rings | `DeviceManagementConfiguration.ReadWrite.All` |
| Read apps, install status, VPP tokens | `DeviceManagementApps.Read.All` (included in the defaults) |
| Assign apps, upload Win32 apps | `DeviceManagementApps.ReadWrite.All` |
| Run a remediation on demand | `DeviceManagementManagedDevices.PrivilegedOperations.All` |
| Group names (`-ResolveName`), find groups, list members / owners / memberships | `Group.Read.All` (included in the defaults; + `User.Read.All` / `Device.Read.All` to resolve UPNs and devices) |
| Create, change, delete groups; add / remove members and owners | `Group.ReadWrite.All` (+ `RoleManagement.ReadWrite.Directory` for role-assignable groups) |

Every function lists its permission in `Get-Help <command> -Full` → NOTES.

## Naming conventions (summary)

- `<ApprovedVerb>-IT<SingularNoun>` — e.g. `Get-ITManagedDevice`, `Invoke-ITDeviceSync`.
- State-changing commands support `-WhatIf` / `-Confirm`; destructive ones ask for confirmation by default.
- Objects are returned with type names `IntuneToolkit.<Noun>`; pipe them into other commands.
- Full rules: [`docs/Framework.md`](docs/Framework.md#3-naming-conventions).

## Development

```powershell
# One-time tools
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -SkipPublisherCheck -Force
Install-Module PSScriptAnalyzer -Scope CurrentUser

# Daily: encoding, export list, analyzer, tests
.\build\build.ps1

# Weekly preview release
.\build\build.ps1 -Task Bump, Package -Version Minor -Prerelease preview1

# Monthly stable release
.\build\build.ps1 -Task Encoding, Manifest, Analyze, Test, Bump, Package -Version Minor
```

Read-only test against a real tenant (interactive sign-in, nothing is changed; results in `TestResults\`):

```powershell
.\Tests\Integration\Invoke-ITTenantSmokeTest.ps1                 # all read commands, export + drift check
.\Tests\Integration\Invoke-ITTenantSmokeTest.ps1 -IncludeSecrets  # + BitLocker/LAPS (audited, values never shown)
```

Adding a function:
1. Copy [`templates/Verb-ITNoun.ps1`](templates/Verb-ITNoun.ps1) to `src/IntuneToolkit/Public/<Area>/<Verb>-IT<Noun>.ps1`.
2. Write a test in `Tests/Public/<Area>/`.
3. Add a line under `## [Unreleased]` in `CHANGELOG.md`.
4. Run `.\build\build.ps1` — it updates the manifest export list and must pass.

## Versioning

[Semantic Versioning](https://semver.org/): **MAJOR** = breaking change, **MINOR** = new functions,
**PATCH** = fixes. Pre-releases use the manifest `Prerelease` tag (e.g. `0.2.0-preview1`).
