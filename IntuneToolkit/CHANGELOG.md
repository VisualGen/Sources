# Changelog

All notable changes to **IntuneToolkit** are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `Start-ITLog` / `Stop-ITLog`: one line at the start and end of a script logs every IntuneToolkit command (Graph requests,
  retries, actions, warnings) plus a transcript; Intune log folder when run by Intune, `%TEMP%\IntuneToolkit` otherwise,
  or a custom path; retention; closing summary with status, duration and the script's errors.
- Log files are written in CMTrace format (CMTrace.exe, OneTrace, Support Center): type 1/2/3 = Info/Warning/Error,
  component = script or command, file = script:line, thread = process ID; error details in the entry's detail pane.
- `Write-ITLog` (now public): Info / Warning / Error events from your script into the `Start-ITLog` file; `-ErrorRecord $_`
  adds exception type, script line and call stack; errors are shown in red without creating a PowerShell error;
  `Stop-ITLog` counts the errors and warnings the script logged.
- `Test-ITPrerequisite`: PowerShell 5.1, .NET Framework 4.7.2+, TLS 1.2, Microsoft.Graph.Authentication installed / loaded /
  newest, mixed Microsoft.Graph.* versions, install tools; returns a Fix command per check (`-Quiet` for scripts).
- Entra ID groups: `Get-ITGroup` (name/prefix/wildcard, `-Search`, `-GroupType`, `-MembershipType`, `-IncludeMemberCount`),
  `New-ITGroup` (security / Microsoft 365, assigned / dynamic, owners and members, duplicate-name check), `Set-ITGroup`
  (description, alias, dynamic rule, pause rule, convert dynamic to assigned), `Rename-ITGroup`, `Remove-ITGroup`.
- Group members including nested groups: `Get-ITGroupMember` (`-Recurse` tree with Depth/Path, `-Transitive`, `-MemberType`),
  `Add-ITGroupMember` / `Remove-ITGroupMember` (UPN, ID, device ID, name or pipeline objects such as managed devices; batches of 20;
  checks for dynamic, synced, Microsoft 365 / role-assignable and circular nesting), `Get-ITGroupMembership` (`-Transitive`, `Direct`),
  `Get-ITGroupOwner`, `Add-ITGroupOwner`, `Remove-ITGroupOwner`. Example `70-Groups.ps1`.
- `Get-ITGroupAssignment`: Intune policies, profiles, scripts, remediations, update profiles and apps assigned to a group
  (include and exclude, through parent groups by default, `-DirectOnly`, `-IncludeAllTargets`, filter names; one read per type).
- Compliance: `Get-ITCompliancePolicy`, `Get-ITDeviceComplianceStatus` (by policy or device), `Get-ITNonCompliantDevice` (`-IncludePolicy`, `-IncludeGracePeriod`).
- Configuration: `Get-ITConfigurationProfile`, `Get-ITSettingsCatalogPolicy` (`-IncludeSetting` with flat `SettingList`), `Get-ITAssignmentFilter`.
- Assignments for every policy type: `Get-ITPolicyAssignment` (`-ResolveName`), `Add-ITPolicyAssignment`, `Remove-ITPolicyAssignment`
  (one target at a time, existing assignments kept; remediations get a daily schedule).
- Backup: `Export-ITPolicy` (JSON per object with assignments and metadata), `Import-ITPolicy` (restore / tenant-to-tenant,
  skips existing names, scope tags dropped and assignments skipped for another tenant), `Compare-ITPolicy` (drift).
- Apps: `Get-ITApp`, `Get-ITAppAssignment`, `Add-ITAppAssignment`, `Remove-ITAppAssignment`, `Get-ITAppInstallStatus` (reports API),
  `New-ITWin32App` (`.intunewin` upload with commit and cleanup on failure).
- Scripts: `Get-ITScript`, `New-ITScript`, `Export-ITScript`, `Get-ITScriptRunState`; remediations: `Get-ITRemediation`,
  `New-ITRemediation`, `Invoke-ITRemediationOnDemand`, `Get-ITRemediationResult`.
- Updates: `Get-ITUpdateRing`, `Suspend-ITUpdateRing`, `Resume-ITUpdateRing`, `Get-ITFeatureUpdateProfile` (`DaysToEndOfSupport`), `Get-ITDriverUpdateProfile`.
- Reports: `Export-ITReport` (CSV / self-contained HTML), `Get-ITAutopilotImportStatus`, `Examples\Scheduled\Daily|Weekly|Monthly.ps1`.
- Tenant: `Get-ITRoleDefinition`, `Get-ITRoleAssignment`, `Get-ITTenantCertificateStatus` (APNs/DEP/VPP), `Get-ITConnectorStatus`.
- Examples `30-Policies`, `40-Apps`, `50-ScriptsAndUpdates`, `60-Tenant`; table views for the new object types; tenant smoke test extended.
- Devices: `Get-ITManagedDevice` (server-side filters: name/prefix, user, OS, compliance, ownership, last sync, raw OData; `-Property`, `-Top`).
- Devices: `Get-ITStaleDevice` (no check-in for N days, adds `DaysSinceLastSync`).
- Device actions (pipeline-friendly, `-WhatIf`/`-Confirm`, return `DeviceActionResult`): `Invoke-ITDeviceSync`, `Invoke-ITDeviceRestart`,
  `Invoke-ITDeviceRetire`, `Invoke-ITDeviceWipe`, `Invoke-ITDefenderScan`, `Invoke-ITBitLockerKeyRotation`, `Remove-ITManagedDevice`.
- `Get-ITDeviceBitLockerKey`, `Get-ITDeviceLapsPassword` (SecureString by default).
- `Get-ITDeviceCategory`, `Set-ITManagedDeviceCategory`, `Set-ITManagedDevicePrimaryUser`.
- Autopilot: `Get-ITAutopilotDevice` (serial server-side; group tag/model/state locally), `Import-ITAutopilotDevice`
  (hash CSV or pipeline, `-Wait`, `-Sync`, cleans up import records), `Set-ITAutopilotDevice` (group tag, user, display name),
  `Remove-ITAutopilotDevice`, `Invoke-ITAutopilotSync` (429 within 10 minutes = warning), `Get-ITAutopilotSyncStatus`,
  `Get-ITAutopilotProfile` (`JoinType`, `-IncludeAssignment`).
- Enrollment: `Get-ITEnrollmentRestriction` (platform + device limit, evaluation order), `Get-ITEnrollmentStatusPage`.
- Internal: `Get-ITAssignment` (Include/Exclude/AllDevices/AllUsers + filters), `-NoRetry` on the Graph transport.
- Example `Examples\20-Autopilot.ps1`.
- Tenant: `Get-ITScopeTag` (name wildcard, `-Id`, `-IncludeAssignment` for auto-assignment groups; beta endpoint).
- Default table views (`Formats\IntuneToolkit.Format.ps1xml`) for devices, action results, keys, LAPS, categories and scope tags.
- Example `Examples\10-Devices.ps1`.
- Read-only tenant smoke test `Tests\Integration\Invoke-ITTenantSmokeTest.ps1` (+ `Get-ITGraphErrorSample.ps1` diagnostic).

### Changed
- Microsoft.Graph.Authentication is no longer a hard `RequiredModules` entry: IntuneToolkit loads it itself and only warns
  when it is missing, so `Test-ITPrerequisite` can run. `Connect-ITGraph` stops with a clear message if it is not available.

### Fixed
- `Connect-ITGraph`: "A window handle must be configured" (WAM sign-in from an embedded terminal such as VS Code) -
  the sign-in is retried once through the web browser; new `-UseBrowser` (alias `-DisableWAM`) skips WAM. The Graph
  WAM option, which is saved for the Windows user, is restored right after the sign-in.
- `Disconnect-ITGraph -Force`: disconnects even when no session is visible, ignores errors, no confirmation.
- Intune error messages: the JSON body (in `Exception.Message`) and the JSON nested inside `error.message` are now unpacked
  to a short text with Activity ID; the Graph `request-id` is appended for support cases.
- `Get-ITAutopilotSyncStatus` / `Invoke-ITAutopilotSync`: use beta; `windowsAutopilotSettings` does not exist in v1.0 (found in tenant test).
- `Get-ITAppInstallStatus` per app: uses `retrieveDeviceAppInstallationStatusReport` (filter ApplicationId);
  `getDeviceInstallStatusReport` no longer exists in the tenant (HTTP 400 "Resource not found for the segment"). The old
  report is only used as a fallback where the new one is missing (found in tenant test).
- Graph transport: HTTP 501 / 505 are no longer retried (permanent answers; cost 75 s per call before).
- `Get-ITConnectorStatus`: skips connector types that answer 501 NotSupported (`exchangeConnectors` without an
  on-premises Exchange connector) instead of failing (found in tenant test).
- `Get-ITStaleDevice`: local variable overwrote the `-Days` parameter (case-insensitive names).
- OData query encoding identical on .NET Framework 4.x and .NET Core (`'`, `(`, `)`).

## [0.1.0] - 2026-11-08

### Added
- Module skeleton for Windows PowerShell 5.1 (`IntuneToolkit.psd1`, loader `IntuneToolkit.psm1`, TLS 1.2 enforced).
- `Connect-ITGraph` — interactive, device code, certificate, client secret and managed identity sign-in.
- `Disconnect-ITGraph`, `Get-ITContext`, `Test-ITGraphConnection`.
- `Get-ITConfiguration`, `Set-ITConfiguration` — default API version, retry, page size, log file.
- Internal Graph transport `Invoke-ITGraphRequest` with paging (`-All`), 429/5xx retry honouring `Retry-After`, and normalised errors.
- Function template, PSScriptAnalyzer rules (5.1 compatibility), Pester 5 tests, `build\build.ps1`.
