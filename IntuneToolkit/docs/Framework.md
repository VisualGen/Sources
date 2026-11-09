# Intune PowerShell Library — Framework & Roadmap

> Status: **DRAFT for review** — nothing here is final until the open decisions (section 9) are confirmed.
> Target runtime: **Windows PowerShell 5.1** only.

---

## 1. Goals

1. One PowerShell module that wraps the Intune parts of Microsoft Graph in consistent, documented functions.
2. Works on a stock Windows 10/11 machine (Windows PowerShell 5.1) with a minimum of dependencies.
3. Grows continuously: new functions are added in small batches and shipped through a predictable release cadence.
4. Every function ships with comment-based help, at least one example, and a Pester test.

## 2. PowerShell 5.1 — feasibility

**Yes, staying on 5.1 is fully possible.** Intune has no PowerShell-specific API; everything goes through
Microsoft Graph REST (`https://graph.microsoft.com/v1.0` and `/beta`), which 5.1 can call natively.

### Authentication / transport options

| Option | Pros | Cons | Recommendation |
|---|---|---|---|
| **A. `Microsoft.Graph.Authentication` only** (`Connect-MgGraph` + `Invoke-MgGraphRequest`) | Supported by Microsoft, works on 5.1, handles token caching/refresh, interactive, device code, certificate, managed identity | One dependency (~small module, not the full SDK) | ✅ **Recommended** |
| B. Full Microsoft.Graph SDK (`Microsoft.Graph.DeviceManagement`, …) | Generated cmdlets for everything | Very large, slow import on 5.1, 4,096 function-count limit issues, assembly conflicts with Az modules | ❌ |
| C. Pure `Invoke-RestMethod` + own MSAL/token code | Zero dependencies | We would own token acquisition/refresh/security — high effort and risk | Only as fallback for app-only (client secret/cert) scenarios |
| D. `Microsoft.Graph.Intune` (old Intune PowerShell SDK) | — | **Deprecated**, no longer maintained | ❌ |

Our module will therefore have **one private transport function** (`Invoke-<Prefix>GraphRequest`) that every
public function uses. It handles paging, throttling (HTTP 429 / `Retry-After`), retries, `v1.0` vs `beta`,
and error normalisation. If we ever change transport, only that one function changes.

### 5.1 constraints we must respect (coding rules)

| Do not use (PS 7 only) | Use instead on 5.1 |
|---|---|
| `$a ? $b : $c`, `??`, `?.`, `&&` / `\|\|` pipeline chains | `if/else`, explicit `$null` checks |
| `ForEach-Object -Parallel` | Sequential loops, or Graph `$batch` (20 requests per call) |
| `ConvertFrom-Json -AsHashtable` / `-Depth` | Default object output; always `ConvertTo-Json -Depth 10` (default is 2!) |
| `Invoke-RestMethod -SkipHttpErrorCheck/-StatusCodeVariable` | Central `try/catch` in the transport function |
| `Join-Path a b c` (multiple child paths) | Nested `Join-Path` |
| Default UTF-8 file encoding | Save `.ps1/.psm1/.psd1` as **UTF-8 with BOM** (5.1 reads no-BOM files as ANSI) |
| — | Force TLS 1.2: `[Net.ServicePointManager]::SecurityProtocol = 'Tls12'` at module load |
| — | Manifest: `PowerShellVersion = '5.1'`, `CompatiblePSEditions = @('Desktop')` |

## 3. Naming conventions

### 3.1 Module
- Module name: **`IntuneToolkit`** *(proposal — see decisions)*
- Command noun prefix: **`IT`** *(proposal)* → avoids clashes with Microsoft.Graph (`Mg`) and other modules.
  Example: `Get-ITManagedDevice`.

### 3.2 Functions
- Format: `<ApprovedVerb>-<Prefix><Noun>` — singular noun, PascalCase.
- **Only approved verbs** (`Get-Verb`). Typical set:

| Verb | Use for | Example |
|---|---|---|
| `Get` | Read one/many objects | `Get-ITManagedDevice` |
| `New` | Create object | `New-ITDeviceCategory` |
| `Set` | Update/replace properties | `Set-ITDeviceCategory` |
| `Remove` | Delete object | `Remove-ITDeviceCategory` |
| `Add` / `Remove` | Assignments, group membership | `Add-ITAppAssignment` |
| `Invoke` | Remote device action | `Invoke-ITDeviceSync`, `Invoke-ITDeviceRestart` |
| `Export` / `Import` | Backup / restore configuration (JSON) | `Export-ITConfigurationProfile` |
| `Connect` / `Disconnect` | Session | `Connect-ITGraph` |
| `Test` | Returns `$true/$false` | `Test-ITGraphConnection` |
| `Compare` | Diff two configs | `Compare-ITConfigurationProfile` |

- Noun families (consistent across the module):
  `ManagedDevice`, `AutopilotDevice`, `CompliancePolicy`, `ConfigurationProfile`, `SettingsCatalogPolicy`,
  `App`, `AppAssignment`, `AppInstallStatus`, `Script`, `Remediation`, `UpdateRing`, `FeatureUpdateProfile`,
  `EnrollmentRestriction`, `DeviceCategory`, `ScopeTag`, `RoleAssignment`, `Filter` (assignment filter), `Report`.
- Private (internal) functions: same verb-noun rule, live in `Private\`, **not exported**
  (e.g. `Invoke-ITGraphRequest`, `ConvertTo-ITObject`, `Write-ITLog`).

### 3.3 Parameters
- PascalCase, singular: `-DeviceId`, `-DeviceName`, `-GroupId`, `-PolicyId`.
- Standard names reused everywhere: `-Id`, `-Name`, `-Filter` (raw OData), `-Property` ($select), `-Top`, `-ApiVersion` (`v1.0|beta`), `-Path` (files), `-PassThru`.
- List functions return **all pages** by default; `-Top N` returns only the first N.
- Pipeline: accept `-Id` via `ValueFromPipelineByPropertyName` so `Get-… | Invoke-…` works.
- Every state-changing function: `[CmdletBinding(SupportsShouldProcess)]` → `-WhatIf` / `-Confirm` for free.
  Destructive ones (`Remove-*`, `Invoke-ITDeviceWipe`) use `ConfirmImpact = 'High'`.

### 3.4 Output
- Return objects, never formatted text. Custom type name per object (`IntuneToolkit.ManagedDevice`) so we can add default views via `.ps1xml` later.
- No `Write-Host` in public functions — use `Write-Verbose`, `Write-Warning`, `Write-Error`, `Write-Progress`.

### 3.5 Files
- One function per file, file name = function name: `Public\Devices\Get-ITManagedDevice.ps1`.
- Tests mirror the structure: `Tests\Public\Devices\Get-ITManagedDevice.Tests.ps1`.

## 4. Repository layout

```
IntuneScripting/
├─ src/IntuneToolkit/
│  ├─ IntuneToolkit.psd1          # manifest (version, author, exports, dependency)
│  ├─ IntuneToolkit.psm1          # loader: dot-sources Private + Public, exports Public
│  ├─ Public/
│  │  ├─ Connection/  Devices/  Apps/  Compliance/  Configuration/
│  │  ├─ Autopilot/   Updates/  Scripts/  Reports/  Tenant/
│  ├─ Private/                    # transport, paging, logging, helpers
│  ├─ Formats/                    # .ps1xml default table views (later)
│  └─ en-US/about_IntuneToolkit.help.txt
├─ Tests/                         # Pester 5 tests (Graph calls mocked)
├─ Examples/                      # runnable sample scripts per scenario
├─ docs/                          # this document, per-function markdown (platyPS)
├─ build/                         # build.ps1: lint, test, bump version, package
├─ CHANGELOG.md
├─ README.md
└─ PSScriptAnalyzerSettings.psd1
```

During development all functions are separate files (easy to diff/review); the build step can optionally merge
them into a single `.psm1` for faster import on 5.1.

## 5. Function standard (template)

Every public function contains:
1. Comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (each), `.EXAMPLE` (≥1), `.OUTPUTS`, `.NOTES` (required Graph permission + API version), `.LINK` (Graph doc).
2. `[CmdletBinding()]` + typed, validated parameters.
3. Call to `Test-ITGraphConnection` (clear error if not connected / missing scope).
4. Only the private transport function talks to Graph.
5. `begin/process/end` when pipeline input is supported.

The concrete template file will be the first code deliverable (Phase 0).

## 6. Versioning, metadata & release

- **Semantic Versioning** `MAJOR.MINOR.PATCH` in the manifest `ModuleVersion`.
  - PATCH = bug fix, MINOR = new functions (backwards compatible), MAJOR = breaking change (renamed/removed function or parameter).
  - Pre-releases: `PrivateData.PSData.Prerelease = 'preview1'`.
- Manifest metadata: `Author`, `CompanyName`, `Copyright`, `Description`, `Tags` (Intune, Graph, MEM, Endpoint), `ProjectUri`, `LicenseUri`, `ReleaseNotes`,
  `RequiredModules = @(@{ModuleName='Microsoft.Graph.Authentication'; ModuleVersion='2.0.0'})`.
- `CHANGELOG.md` in *Keep a Changelog* format; `ReleaseNotes` filled from it at build time.
- Distribution options: internal file share / private PSRepository, GitHub Releases (zip), or PowerShell Gallery (`Publish-Module`).

### Proposed cadence

| Cadence | What happens |
|---|---|
| **Daily** (working sessions) | Write 1–3 functions + tests + help on a feature branch; merge to `main` when tests pass. |
| **Weekly** | Cut a **MINOR preview** (`x.Y.0-previewN`) with that week's functions; update CHANGELOG; try in test tenant. |
| **Monthly** | Promote to **stable** `x.Y.0`; publish; update README/examples; review deprecated `beta` endpoints. |

## 7. Activity list (backlog)

### Phase 0 — Foundation (must come first)
- [x] `git init` inside this folder (today the folder sits inside a repository rooted at `C:\` — not intended)
- [x] Repository skeleton (section 4), `.gitignore`, `.editorconfig` (UTF-8 BOM, CRLF)
- [x] Module manifest + loader `.psm1`
- [x] Function template + PSScriptAnalyzer rules (incl. `PSUseCompatibleSyntax` targeting 5.1)
- [x] Private: `Invoke-ITGraphRequest` (paging `@odata.nextLink`, 429/503 retry with `Retry-After`, `beta`/`v1.0`, error normalisation)
- [x] Private: `Write-ITLog` (Verbose + optional file log), `ConvertTo-ITObject` (type names)
- [x] Public: `Connect-ITGraph` (interactive, device code, certificate app-only, client secret, managed identity), `Disconnect-ITGraph`, `Test-ITGraphConnection`, `Get-ITContext`, `Get/Set-ITConfiguration`
- [x] Pester 5 test harness with mocked Graph; `build.ps1` (encoding → manifest → analyze → test → version bump → package)
- [x] README (install, connect, first commands) + `Examples\00-Connect.ps1`

### Phase 1 — Devices (most used in daily ops)
- [x] `Get-ITManagedDevice` (by Id/Name/User/OS/compliance state/ownership/last sync; all pages unless `-Top`)
- [x] `Invoke-ITDeviceSync`, `Invoke-ITDeviceRestart`, `Invoke-ITDeviceRetire`, `Invoke-ITDeviceWipe`, `Invoke-ITDefenderScan`, `Invoke-ITBitLockerKeyRotation`
- [x] `Get-ITDeviceBitLockerKey`, `Get-ITDeviceLapsPassword` (with clear permission notes)
- [x] `Get-ITStaleDevice` (no check-in for N days), `Remove-ITManagedDevice`
- [x] `Get-ITDeviceCategory` / `Set-ITManagedDeviceCategory`, `Set-ITManagedDevicePrimaryUser`
- [x] Default table views (`.ps1xml`) for device objects
- [ ] Later: `Get-ITManagedDevicePrimaryUser`, `Invoke-ITDeviceRemoteLock`, `Invoke-ITDeviceFreshStart`, `Invoke-ITDefenderSignatureUpdate`

### Phase 2 — Autopilot & enrollment
- [x] `Get/Import/Remove-ITAutopilotDevice` (hardware hash CSV)
- [x] `Set-ITAutopilotDevice` (instead of `Set-ITAutopilotGroupTag`: noun = object; covers group tag, user, display name)
- [x] `Invoke-ITAutopilotSync`, `Get-ITAutopilotSyncStatus`
- [x] `Get-ITAutopilotProfile`, `Get-ITEnrollmentRestriction`, `Get-ITEnrollmentStatusPage`
- [ ] Later: `New/Set-ITAutopilotProfile`, `Add/Remove-ITAutopilotProfileAssignment`, ESP blocking-app names

### Phase 3 — Compliance & configuration
- [x] `Get-ITCompliancePolicy`, `Get-ITDeviceComplianceStatus` (by policy or by device), `Get-ITNonCompliantDevice` (`-IncludePolicy`)
- [x] `Get-ITConfigurationProfile` (template profiles) + `Get-ITSettingsCatalogPolicy` (`-IncludeSetting` → flat `SettingList`)
- [x] `Export-ITPolicy` / `Import-ITPolicy` (one pair for all policy types instead of one per type; JSON backup/restore, tenant-to-tenant: scope tags dropped, assignments only in the source tenant, existing names skipped)
- [x] `Compare-ITPolicy` (instead of `Compare-ITConfigurationProfile`: works for every exported type; settings compared by definition ID, assignments included)
- [x] Assignments: `Get/Add/Remove-ITPolicyAssignment` (one target at a time, the rest is kept), `Get-ITAssignmentFilter`
- [ ] Later: administrative templates (groupPolicyConfigurations) in export/import, endpoint security intents (legacy)

### Phase 4 — Apps
- [x] `Get-ITApp`, `Get-ITAppAssignment`, `Add/Remove-ITAppAssignment`
- [x] `Get-ITAppInstallStatus` (reports API; per app or per device, `-FailedOnly`, `-Since`)
- [x] `New-ITWin32App` (`.intunewin` → app, content version, 6 MB block upload, commit with encryption info, cleanup on failure)
- [ ] Later: supersedence / dependencies, `Set-ITWin32App` (new content version), WinGet / Store app creation

### Phase 5 — Scripts, remediations, updates
- [x] `Get/New/Export-ITScript` (PowerShell platform scripts), `Get-ITScriptRunState`
- [x] `Get/New-ITRemediation`, `Invoke-ITRemediationOnDemand`, `Get-ITRemediationResult`
- [x] `Get-ITUpdateRing`, `Get-ITFeatureUpdateProfile`, `Get-ITDriverUpdateProfile`, `Suspend-ITUpdateRing` + `Resume-ITUpdateRing`
- [ ] Later: driver approval (`Approve-ITDriverUpdate`), quality update (expedite) profiles, macOS shell scripts

### Phase 6 — Reports & operations (scheduled use)
Functions designed to be run by Task Scheduler / Azure Automation and produce CSV/HTML:

| Frequency | Report function |
|---|---|
| Daily | `Get-ITNonCompliantDevice`, failed app installs (24 h), devices without check-in > 7 days, Autopilot import errors (`Get-ITAutopilotImportStatus`) |
| Weekly | Stale devices (30/60/90 d), encryption status, OS version distribution, remediation and script failures |
| Monthly | Full device inventory, configuration backup (`Export-ITPolicy`), unassigned policies/apps, Apple token & certificate expiry (APNs, VPP, DEP), connectors, role assignments |

- [x] `Export-ITReport` (CSV / self-contained HTML) and `Examples\Scheduled\Daily.ps1`, `Weekly.ps1`, `Monthly.ps1` (+ `Common.ps1`; certificate app-only or interactive)
- [ ] Later: Defender status per device (reports API), mail delivery of the summary

### Phase 7 — Tenant administration
- [x] `Get-ITScopeTag` (delivered early, on request)
- [x] `Get-ITRoleAssignment` (+ `Get-ITRoleDefinition`), `Get-ITTenantCertificateStatus` (APNs/DEP/VPP expiry), `Get-ITConnectorStatus`

### Next — additional functions
Collected here as they are requested; same rules (template, tests, CHANGELOG, daily check).

- [x] **Entra ID groups** (`Public\Groups`): `Get-ITGroup`, `New-ITGroup`, `Set-ITGroup`, `Rename-ITGroup`, `Remove-ITGroup`,
      `Get-ITGroupMember` (`-Recurse` / `-Transitive` for nested groups), `Add-ITGroupMember`, `Remove-ITGroupMember`,
      `Get-ITGroupMembership`, `Get-ITGroupOwner`, `Add-ITGroupOwner`, `Remove-ITGroupOwner`,
      `Get-ITGroupAssignment` (what Intune assigns to a group, also through parent groups).
- [x] **Script logging** (`Public\Module`): `Start-ITLog` / `Stop-ITLog` - configured once at the top of a script, no log
      calls inside functions; Intune Management Extension log folder when Intune runs the script (`Test-ITIntuneContext`).
- [x] **Script events**: `Write-ITLog` is public (Info / Warning / Error, `-ErrorRecord`), CMTrace format; `Write` counts as a
      read-only verb in the conventions test (like Write-Verbose, logging must keep working under -WhatIf).
- [x] **Prerequisite check**: `Test-ITPrerequisite`; the Graph module moved from `RequiredModules` to the module loader.
      Shared helpers: `Resolve-ITGroup`, `Resolve-ITDirectoryObject` (UPN / ID / device ID / name / pipeline object),
      `Invoke-ITGroupLinkChange` (members and owners, batches of 20, rule checks). Graph v1.0.

## 8. How the module will be used (target experience)

```powershell
# Install (once)
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Import-Module .\src\IntuneToolkit\IntuneToolkit.psd1

# Connect
Connect-ITGraph -Scopes 'DeviceManagementManagedDevices.ReadWrite.All'

# Use
Get-ITManagedDevice -OperatingSystem Windows -ComplianceState noncompliant |
    Invoke-ITDeviceSync -WhatIf

Get-ITStaleDevice -Days 90 | Export-Csv .\stale.csv -NoTypeInformation -Encoding UTF8

Get-Help Get-ITManagedDevice -Examples
```

## 9. Open decisions (please confirm)

1. **Module name and prefix** — `IntuneToolkit` / `IT`? (Alternatives: `IntuneOps`/`IO`, your company abbreviation.)
2. **Author / CompanyName / Copyright** to put in the manifest.
3. **Auth model** — interactive admin only, or also unattended app-only (certificate) for scheduled reports?
4. **Distribution** — internal share, private repository, GitHub, or PowerShell Gallery? (Drives licence choice.)
5. **API level** — allow `beta` endpoints (many Intune features exist only there) with `-ApiVersion` switch? *(Recommended: yes, default `v1.0` where possible.)*
6. **Test tenant** available for integration testing?
