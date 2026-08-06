# Tasks: Storage Device Diagnostics Module

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1,590 (authored; excludes bundled `Tools/smartctl.exe` binary) |
| 400-line budget risk | High (whole change); per-PR risk Low–High (see table) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 → PR2 → PR3 → PR4 → PR5 → PR6 → PR7 (sequential, dependency-ordered) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending — ask user before apply |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | `ConvertFrom-SmartctlJson` pure parser (~200 lines) | PR1 | `Invoke-Pester -Path .\Tests\Get-StorageInfo.Tests.ps1 -Output Detailed` | N/A — fixture JSON strings only, no binary needed | Delete new function + test file; no other file touched |
| 2 | SMART invocation + `Get-StorageInventory` wiring, degrade paths (~320 lines) | PR2 | `Invoke-Pester -Path .\Tests\Get-StorageInfo.Tests.ps1 -Output Detailed` | N/A in CI — stubbed `Invoke-SmartctlCommand`; manual smoke on real disks recommended | Revert `Get-StorageInfo.ps1` diff; `.Smart` field disappears, rest of Physical[] unaffected |
| 3 | `Get-StorageHealth` carry-through + `Get-StorageSmartSummary` (~170 lines) | PR3 | `Invoke-Pester -Path .\Tests\Get-StorageHealth.Tests.ps1 -Output Detailed` | N/A — in-memory objects | Revert `Get-StorageHealth.ps1` diff independently of PR1/PR2 behavior |
| 4 | `Storage*` config thresholds + validation + `config.json` defaults (~130 lines) | PR4 | `Invoke-Pester -Path .\Tests\ConfigContract.Tests.ps1,.\Tests\HealthCore.Tests.ps1 -Output Detailed` | N/A — config load only | Revert `Get-HealthConfig.ps1`/`config.json`; existing keys unaffected |
| 5 | STO-006..012 findings + REC-STO-005/006/007 (~340 lines) | PR5 | `Invoke-Pester -Path .\Tests\Get-HealthRules.Tests.ps1 -Output Detailed` | N/A — synthetic metrics objects, same pattern as existing MEM-*/STO-* tests | Revert `Get-HealthFindings.ps1` diff; STO-001..005 untouched |
| 6 | `Invoke-HealthCheck` Storage.Smart wiring + schema docs (~150 lines) | PR6 | `Invoke-Pester -Path .\Tests\Invoke-HealthCheck.Tests.ps1 -Output Detailed` | N/A — synthetic InputData | Revert `Invoke-HealthCheck.ps1`/doc diff |
| 7 | `Collector_Storage_Diagnostic.ps1` + menu option 10 + bundled binary (~280 authored lines + binary) | PR7 | `Invoke-Pester -Path .\Tests\CollectorContract.Tests.ps1,.\Tests\LauncherScripts.Tests.ps1 -Output Detailed` | Manual E2E: run menu option 10 on a real Windows machine (per spec, not CI-automatable) | Delete new collector file + menu lines; existing collectors/menu options unaffected |

Individual PRs stay under budget except PR2 and PR5, which run close to it (Medium–High); keep their scope frozen as listed — do not fold additional findings/tests into them.

## Phase 1: SMART JSON Parsing (PR1) — domain: storage-inventory

- [x] 1.1 RED `Tests/Get-StorageInfo.Tests.ps1` (new): `ConvertFrom-SmartctlJson` fixtures — ATA success, NVMe success, malformed/truncated JSON (threat matrix), missing-field. Assert `Supported`, `Source`, `ErrorCode`. Fails (fn missing).
- [x] 1.2 GREEN+REFACTOR: implement `ConvertFrom-SmartctlJson` in `Modules/Get-StorageInfo.ps1`; never throws, returns `Supported=$false`+`ErrorCode` on malformed input.

## Phase 2: SMART Invocation & Capture (PR2) — domain: storage-inventory

- [x] 2.1 RED (threat: binary missing) — `Get-StorageInventory` with absent `smartctl.exe`: all disks `Unavailable`, no spawn, no exception.
- [x] 2.2 RED (threat: process hangs) — stub `Invoke-SmartctlCommand` with no exit: 15s timeout, disk `ErrorCode=SMARTCTL-TIMEOUT`.
- [x] 2.3 RED — per-disk failure: disk0 succeeds, disk1 errors; both remain, disk0 populated, disk1 null (Graceful Degradation).
- [x] 2.4 RED — device-type flag: `nvme` for BusType=NVMe, `sat` for USB (retry once on failure), omitted otherwise.
- [x] 2.5 GREEN+REFACTOR: implement `Invoke-SmartctlCommand`, `Get-DiskSmartData`, `-SmartctlPath` param; wire into `$physical` loop with per-disk try/catch and one `Test-Path` pre-check.

## Phase 3: Aggregation (PR3) — domain: storage-inventory

- [x] 3.1 RED `Tests/Get-StorageHealth.Tests.ps1`: `.Smart` carried onto `$disks` via existing SerialNumber join.
- [x] 3.2 RED: `Get-StorageSmartSummary` worst-of across N disks (mixed health/wear/temperature).
- [x] 3.3 GREEN+REFACTOR: implement carry-through + `Get-StorageSmartSummary` in `Modules/Get-StorageHealth.ps1`.

## Phase 4: Config Thresholds (PR4) — domain: storage-health-findings

- [x] 4.1 RED: new `Storage*` keys load with documented defaults; misordered `StorageWearWarningPercent`/`HighPercent` or `StorageTemperatureWarningC`/`HighC` throws descriptive error.
- [x] 4.2 GREEN+REFACTOR: add keys + validation to `Modules/Get-HealthConfig.ps1`; add defaults to `config.json`.

## Phase 5: STO-006..012 Findings (PR5) — domain: storage-health-findings

- [x] 5.1 RED `Tests/Get-HealthRules.Tests.ps1`: STO-006 (FAILED self-assessment), STO-007 (pending sectors ≥ threshold), STO-008 (NVMe spare < critical/own threshold) → Critical + `RecommendationId`.
- [x] 5.2 RED: STO-009 (reallocated sectors, Medium-only, no Critical when pending=0), STO-010 (wear warning/high boundaries), STO-011 (temperature warning/high boundaries), STO-012 (HDD `PowerOnHours` ≥ service-life).
- [x] 5.3 GREEN+REFACTOR: implement STO-006..012 in `Get-HealthFinding` (`Modules/Get-HealthFindings.ps1`).
- [x] 5.4 RED: `Get-HealthRecommendation` returns `REC-STO-005/006/007`; STO-006/007/008 map to existing `REC-STO-001`.
- [x] 5.5 GREEN+REFACTOR: extend catalog in `Get-HealthRecommendation`.

## Phase 6: HealthCheck Wiring (PR6) — domain: storage-health-findings

- [x] 6.1 RED `Tests/Invoke-HealthCheck.Tests.ps1`: `metrics.Storage.Smart` populated via `Get-StorageSmartSummary`; STO-006..012 reachable end-to-end.
- [x] 6.2 GREEN+REFACTOR: call `Get-StorageSmartSummary`, add `Smart` in `Modules/Invoke-HealthCheck.ps1`.
- [x] 6.3 Update `docs/JSON_SCHEMA.md` with the `.Smart` shape.

## Phase 7: Standalone Collector (PR7) — domain: storage-diagnostic-collector

- [ ] 7.1 RED `Tests/CollectorContract.Tests.ps1` (extend): `Collector_Storage_Diagnostic.ps1` — Storage-only sections, no Performance/Events, output `<Hostname>-<ts>-storage.{json,html}` + log, reuses `Export-HealthCheck.ps1` unmodified.
- [ ] 7.2 GREEN+REFACTOR: create `Collector_Storage_Diagnostic.ps1` (mirrors `Collector_Windows_HealthCheck.ps1`; empty-but-well-formed CPU/Memory/Events defaults).
- [ ] 7.3 RED `Tests/LauncherScripts.Tests.ps1`: menu option "10" dispatches `Collector_Storage_Diagnostic.ps1` with active session context, returns to menu.
- [ ] 7.4 GREEN+REFACTOR: add menu line "10. Ejecutar diagnóstico de almacenamiento" + `"10"` switch case in `Start-Inventory.ps1`.
- [ ] 7.5 Add `Tools/smartctl.exe` (bundled binary asset); update `docs/HEALTH_CHECK.md` and `docs/JSON_SCHEMA.md` for the new collector artifact.
- [ ] 7.6 Manual E2E: run menu option 10 on a real Windows machine, including a run with `smartctl.exe` absent (not CI-automatable, per spec).
