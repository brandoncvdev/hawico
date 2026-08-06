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

## Phase 2b: RAID/passthrough device-type fallback (PR8) — domain: storage-inventory

Real-world finding (2026-08-06, real Dell OptiPlex hardware): OEM desktops
(Dell/Lenovo/Acer/HP/Gateway and others) commonly ship Intel RST configured
in "RAID" mode even for a single passthrough disk — Windows/Get-PhysicalDisk
reports `BusType = "RAID"` for what is physically a plain SATA disk. The
existing device-type flag selection (`nvme` for NVMe, `sat`-then-auto for
USB, bare `auto` for everything else) never tries `sat` for RAID/unrecognized
bus types, so smartctl's auto-detect fails to see through the RAID/SCSI
layer and returns `SMARTCTL-UNKNOWN-PROTOCOL` — confirmed against a real
generated `*-storage.json` (both disks: the real HDD behind BusType=RAID and,
separately and correctly, a USB flash drive with no SMART support at all —
that second one is not a bug, plain USB flash media genuinely has no SMART).

- [x] 2.6 RED: `Get-DiskSmartData` for BusType='RAID' (and any other value that
      isn't 'NVMe') tries `-d sat` first, same as the existing USB path — not
      bare `auto`. If `sat` also fails with an unknown-protocol result, falls
      back to `auto`, same retry-then-degrade contract already established.
- [x] 2.7 GREEN+REFACTOR: unify the USB and RAID/other-bus-type cases onto the
      same `sat`-first-then-`auto` fallback ladder in `Get-DiskSmartData`; only
      `NVMe` keeps its own direct `nvme` flag with no retry needed.

## Phase 2c: WMI FailurePredictData as primary SMART source (PR9) — domain: storage-inventory

Real-World Amendment (2026-08-06, see proposal.md): `smartctl` cannot open
the disk on the user's actual fleet (Dell RAID-mode, HP SATA-mode, both
tested by hand, antivirus ruled out) — a documented Windows OEM-driver
limitation, not fixable via `-d` flag selection (PR8 already exhausted
every device type `smartctl` supports). The legacy `root\wmi`
`MSStorageDriver_FailurePredictData`/`FailurePredictStatus` WMI classes
return real, hand-verified SMART data on the same Dell where `smartctl`
and `Get-StorageReliabilityCounter` both failed — a standard 512-byte ATA
SMART attribute table (2-byte header + up to 30 × 12-byte attribute
records: Id/FlagsLo/FlagsHi/Current/Worst/Raw[6]/Reserved), correlated to
the physical disk via `Win32_DiskDrive.PNPDeviceID` matching
`FailurePredictData.InstanceName` (case-insensitive, `InstanceName` has a
trailing `_N`).

**Real fixture data** (Dell OptiPlex 3050, Seagate ST500DM005, hand-decoded
and verified against this exact task's RED tests — use as literal test
fixture bytes, not synthetic data):
- Raw 512-byte array: `16,0,1,47,0,100,100,0,5,0,0,0,0,0,2,38,0,252,252,0,0,0,0,0,0,0,3,35,0,83,74,198,20,0,0,0,0,0,4,50,0,99,99,91,7,0,0,0,0,0,5,51,0,252,252,0,0,0,0,0,0,0,7,46,0,252,252,0,0,0,0,0,0,0,8,36,0,252,252,0,0,0,0,0,0,0,9,50,0,100,100,121,86,0,0,0,0,0,10,50,0,252,252,0,0,0,0,0,0,0,11,50,0,252,252,0,0,0,0,0,0,0,12,50,0,99,99,250,6,0,0,0,0,0,191,34,0,100,100,29,0,0,0,0,0,0,192,34,0,252,252,0,0,0,0,0,0,0,194,2,0,59,44,41,0,11,0,56,0,0,195,58,0,100,100,0,0,0,0,0,0,0,196,50,0,252,252,0,0,0,0,0,0,0,197,50,0,252,100,0,0,0,0,0,0,0,198,48,0,252,252,0,0,0,0,0,0,0,199,54,0,92,92,160,16,0,0,0,0,0,200,42,0,100,100,24,37,0,0,0,0,0,223,50,0,252,252,0,0,0,0,0,0,0,225,50,0,84,84,116,138,2,0,0,0,0,0` followed by zero-padding to 512 bytes (trailing status region, non-attribute).
- Expected decode: Attr 5 (ReallocatedSectorCount) raw=0; Attr 9 (PowerOnHours) raw=22137; Attr 194 (Temperature, first raw byte only) =41; Attr 197 (PendingSectorCount) raw=0; Attr 198 (UncorrectableSectorCount) raw=0.
- `Win32_DiskDrive.PNPDeviceID` = `SCSI\DISK&VEN_ST500DM0&PROD_05\4&3714EEF5&0&000000` ↔ `FailurePredictData.InstanceName` = `SCSI\Disk&Ven_ST500DM0&Prod_05\4&3714eef5&0&000000_0` (confirms the case-insensitive-prefix + trailing `_N` correlation rule).

- [x] 2c.1 RED: add `PNPDeviceID` to `Get-StorageInventory`'s `$physical` array
      (`Modules/Get-StorageInfo.ps1`) — new field alongside existing
      Model/Manufacturer/SerialNumber/etc., sourced from `Win32_DiskDrive`.
- [x] 2c.2 GREEN+REFACTOR: implement 2c.1.
- [x] 2c.3 RED: new pure fn `ConvertFrom-AtaSmartAttributeTable -RawBytes [byte[]]`
      — parses the 512-byte block into the SAME output shape
      `ConvertFrom-SmartctlJson` already returns (Supported/Source/
      OverallHealth/TemperatureCelsius/PowerOnHours/PowerCycleCount/
      ReallocatedSectorCount/PendingSectorCount/UncorrectableSectorCount/
      AvailableSparePercent=$null/PercentageUsed=$null/MediaErrorCount=$null/
      CriticalWarningFlags=$null/ErrorCode/ErrorMessage) so downstream code
      (`Get-StorageSmartSummary`, STO-006..012) needs zero changes — only the
      `.Smart` object's origin changes. Test against the real fixture bytes
      above; assert the exact expected decode values listed. Also cover:
      byte array shorter than 512 (malformed), all-zero block (no attributes
      present), unrecognized attribute IDs (skip gracefully, don't throw).
- [x] 2c.4 GREEN+REFACTOR: implement 2c.3.
- [x] 2c.5 RED: new fn `Get-DiskSmartDataFromWmi -PnpDeviceId [string]` —
      queries `Get-CimInstance -Namespace root\wmi -ClassName
      MSStorageDriver_FailurePredictData` (and `...Status` for the
      `PredictFailure` boolean as `OverallHealth` when the full table can't
      be parsed), correlates by `InstanceName` matching `PnpDeviceId`
      (case-insensitive, allow `InstanceName` to carry a trailing `_N` the
      `PnpDeviceId` doesn't have), calls `ConvertFrom-AtaSmartAttributeTable`.
      Cover: no matching instance (WMI class not populated for this disk),
      `Active=$false`, WMI namespace/class entirely unavailable (older
      Windows/driver) — all degrade to `Supported=$false`, never throw.
- [x] 2c.6 GREEN+REFACTOR: implement 2c.5.
- [x] 2c.7 RED: `Get-DiskSmartData` priority flip — for non-NVMe `BusType`,
      try `Get-DiskSmartDataFromWmi` FIRST; only if that returns
      `Supported=$false` (or throws/unavailable), fall back to the existing
      `smartctl` sat-then-auto ladder (PR2/PR8, unchanged) IF `Tools\smartctl.exe`
      exists. NVMe path (`-d nvme` via smartctl) is UNCHANGED by this task —
      WMI FailurePredictData does not apply to NVMe.
- [x] 2c.8 GREEN+REFACTOR: implement 2c.7.
- [x] 2c.9 Update `openspec/changes/storage-diagnostics/proposal.md`'s
      "Dependencies"/"Affected Areas" and `docs/JSON_SCHEMA.md` to reflect
      `smartctl.exe` as optional/secondary rather than a hard dependency.

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

- [x] 7.1 RED `Tests/CollectorContract.Tests.ps1` (extended, new `Describe` block): `Collector_Storage_Diagnostic.ps1` — Storage-only sections, no Performance/Events, output `<Hostname>-<ts>-storage.{json,html}` + log, reuses `Export-HealthCheck.ps1` unmodified.
- [x] 7.2 GREEN+REFACTOR: create `Collector_Storage_Diagnostic.ps1` (mirrors `Collector_Windows_HealthCheck.ps1`; empty-but-well-formed CPU/Memory/Events defaults).
- [x] 7.3 RED `Tests/LauncherStorageDiagnostic.Tests.ps1` (new file, mirrors `LauncherHealthCheck.Tests.ps1`'s pattern for option 3): menu option "10" dispatches `Collector_Storage_Diagnostic.ps1 -Mode Diagnostic`, returns to menu. Note: dispatched WITHOUT SessionId/OrganizationId/Technician — verified `Collector_Windows_HealthCheck.ps1`/option 3 never receive those params either (only options 1-2, the full/quick hardware inventory collectors backed by `New-InventoryCollectionSession`, do); the new Storage-only diagnostic follows the option-3 precedent it actually mirrors, not a "1-3" pattern that doesn't exist in the codebase.
- [x] 7.4 GREEN+REFACTOR: add menu line "10. Ejecutar diagnóstico de almacenamiento" + `"10"` switch case in `Start-Inventory.ps1`, placed after "9" (Cambiar contexto), leaving "8"/"9" untouched.
- [x] 7.5 Did NOT add a real `Tools/smartctl.exe` binary (cannot be produced from this environment; a fake one would be misleading). Created `Tools/README.md` documenting the exact expected path (`Tools\smartctl.exe`, confirmed against PR2's `-SmartctlPath` default resolution in `Modules/Get-StorageInfo.ps1`) and what to place there. Added `Tests/StorageDiagnosticIntegration.Tests.ps1` (Windows-gated, mirrors `WindowsHealthIntegration.Tests.ps1`) asserting the collector's already-built graceful-degradation path (PR2's single `Test-Path` pre-check) correctly handles the binary being absent end-to-end. Updated `docs/HEALTH_CHECK.md` (§17.4, new collector + architecture tree) and `docs/JSON_SCHEMA.md` (new "Diagnóstico de almacenamiento independiente" section) for the new collector artifact.
- [ ] 7.6 NOT attempted — manual E2E on a real Windows machine is not achievable in this (macOS) environment. Outstanding manual step for the user/a Windows machine: run menu option "10" end-to-end, including one run with `Tools\smartctl.exe` absent (current repo state) and, if a real binary is later placed per `Tools/README.md`, one run with it present.

## Phase 8: Storage findings + raw SMART values in the full inventory report (PR10) — domain: storage-diagnostic-collector

User request (2026-08-06): the full inventory (options 1/2) already captures raw `.Smart` per disk silently into `record.json` (since PR9 always populates it), but nothing ever runs the STO-006..012 analysis there or shows it in the inventory HTML — only the separate storage-only diagnostic (option 10) does. User wants this as a complementary section of the FULL inventory report itself, not only in the standalone option.

Reuse everything already built — no new analysis engine code, only wiring + a new HTML section:

- [ ] 8.1 RED: `Collector_Hardware_Inventory.ps1` dot-sources `Get-HealthConfig.ps1`, `Get-StorageHealth.ps1`, `Get-HealthFindings.ps1`, `Invoke-HealthCheck.ps1` (new additions to its existing module list) and, after capturing `$storage = Get-StorageInventory`, runs `Get-StorageHealth -StorageInventory $storage -SystemDrive $env:SystemDrive` then `Invoke-HealthCheck` with the SAME empty-but-well-formed CPU/Memory/Events pattern `Collector_Storage_Diagnostic.ps1` already uses (read that file — `Modules/Get-HealthConfig.ps1` config load, `$performanceData`/`$performanceSection`/`$eventSection` construction — copy the exact pattern, don't reinvent it), extracting just `.HealthCheck.Findings`/`.HealthCheck.Recommendations` (Storage-only findings, same STO-006..012 rules already implemented). Assert these end up attached to the `CollectionRecord`/inventory result passed to `New-InventoryHtml`.
- [ ] 8.2 GREEN+REFACTOR: implement 8.1.
- [ ] 8.3 RED `Tests/Export.Tests.ps1` (extend if exists, check first): `New-InventoryHtml` renders a new "SMART" subsection under "Almacenamiento" — a raw-values table (per physical disk: Model, Source, OverallHealth, TemperatureCelsius, PowerOnHours, ReallocatedSectorCount, PendingSectorCount, UncorrectableSectorCount, AvailableSparePercent, PercentageUsed) using `$storage.Physical[].Smart`, ALWAYS shown when `Smart.Supported=$true` regardless of findings (this is the Nivel-2 "state" the functional spec asked for, distinct from Nivel-3 conditional findings) — plus a findings/recommendations table for the new storage findings, reusing `New-InventoryTable`'s existing conventions (read `Modules/Export.ps1`'s current "Almacenamiento" section, ~line 393-464, for the exact pattern/columns style to match — same file already has `$physicalDiskTable`/`$detailedDiskTable`/`$logicalDiskTable` as the model to follow). Cover: no Smart data at all (Supported=false for every disk — show an informational message, not an empty confusing table, per the earlier UX note this session about not looking like a bug), and a disk with real findings.
- [ ] 8.4 GREEN+REFACTOR: implement 8.3 — new params on `New-InventoryHtml` (or read from the existing `$Inventory` hashtable if that's a cleaner fit, your call after reading the current signature) for the findings/recommendations data from 8.1/8.2.
- [ ] 8.5 Update `docs/JSON_SCHEMA.md`/`docs/INSTITUTIONAL_EXCEL_MAPPING.md` if the inventory record's JSON shape gains a new top-level findings field (check whether 8.1's attachment point changes the record schema or stays HTML-only presentation; document whichever it ends up being).
