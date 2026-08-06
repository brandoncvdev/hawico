# Proposal: Storage Device Diagnostics Module

## Intent

Field technicians currently see only basic disk identity/health data (Win32_DiskDrive + `Get-PhysicalDisk`) — no SMART attributes, so failing drives (reallocated sectors, wear, thermal issues) go undetected until a hard failure interrupts the customer. This evolves the two existing storage-touching modules (`Get-StorageInfo.ps1`, `Get-HealthFindings.ps1`) to add SMART-based capture and analysis, per the functional spec's 3-tier model (Inventario/Estado/Análisis), so a technician can run a dedicated, storage-scoped diagnostic on suspicion or as routine practice and get an evidence-based recommendation.

## Scope

### In Scope
- SMART attribute capture (Nivel 2) added into `Get-StorageInventory`'s existing `Storage.Physical[]` items — shared automatically by both current collectors.
- **Primary source (ATA/SATA disks): the legacy WMI `root\wmi` `MSStorageDriver_FailurePredictData`/`FailurePredictStatus` interface** — no external binary, ships with Windows, correlated to the disk via `Win32_DiskDrive.PNPDeviceID`. See Real-World Amendment below for why this replaced `smartctl` as the default.
- `smartctl.exe` (optional, secondary): bundled at `Tools\smartctl.exe` if present, used as fallback for ATA/SATA disks when the WMI source is unavailable, and as the primary (only) method for NVMe disks (`-d nvme`, unaffected by this amendment). Missing/failing smartctl degrades gracefully to CIM/`Get-PhysicalDisk`-only data (existing try/catch pattern) — unchanged.
- New `STO-00X` rules in `Get-HealthFindings.ps1` for wear, reallocated/pending sectors, temperature, available spare — flows through existing generic `Findings`/`Recommendations` rendering with zero new HTML code. Option 3 (full health check) picks these up automatically for free, since it already calls `Get-HealthFindings.ps1` — no separate wiring.
- New standalone menu option "10. Ejecutar diagnóstico de almacenamiento" in `Start-Inventory.ps1`, dispatching a new `Collector_Storage_Diagnostic.ps1` (mirrors `Collector_Windows_HealthCheck.ps1`'s structure/output convention: `*-storage.json`/`*-storage.html`/log under `Output\<Hostname>\`).
- SMART thresholds (reallocated/pending sectors, wear%, temperature, available spare) as `config.json`-configurable values, same pattern as existing `HealthCheck` thresholds (`MemoryWarningPercent`, `CriticalFreeDiskPercent`, etc.) — see Severity Calibration below.

### Out of Scope
- Cross-visit SMART comparison (diffing counters against the host's prior collection) — deferred to a future change. `Get-InventoryLatestHostRecord` already provides the lookup mechanism when this is picked up later; no plumbing work is lost by deferring.
- Full historical trend charts/graphs, degradation-trend detection, lightweight benchmarks, cross-module (CPU/memory/network) correlation, predictive alerting — deferred per spec §13.
- Technician confirm/edit/annotate of auto-generated recommendations — findings stay read-only output, same as today's STO-*/REC-* pattern.
- Vendor-specific tools beyond smartctl.
- Following an external SMART compliance standard/norm — none was identified as required; thresholds are project-owned and config.json-adjustable instead (see below).

## Capabilities

### New Capabilities
- `storage-inventory`: Nivel 1+2 raw storage capture (identity + SMART), shared by both existing collectors via `Get-StorageInfo.ps1`.
- `storage-health-findings`: Nivel 3 SMART-based STO-* rules/recommendations in `Get-HealthFindings.ps1`.
- `storage-diagnostic-collector`: new standalone menu-triggered collector producing a storage-scoped JSON/HTML report.

### Modified Capabilities
None (no existing `openspec/specs/` entries — first SDD change in this project).

## Approach

Extend, don't parallel-build: SMART data flows into the same `Get-StorageInventory` object both collectors already call, so option 1/2 (hardware inventory) get richer `record.json` with zero menu changes. Nivel 3 analysis is scoped to a new dedicated menu option so a technician can run a fast, storage-only check without the full CPU/memory/events sampling. The existing full health check (option 3) already calls `Get-HealthFindings.ps1`; extended STO-* rules apply to it automatically for free — **decided: option 3 stays unchanged in wiring and inherits the new findings automatically**, since smartctl capture lives in the shared inventory call both collectors already make.

## Severity Calibration

Thresholds are `config.json`-configurable (same pattern as existing `HealthCheck` settings), starting conservative — no external SMART compliance standard exists to follow (SMART attribute IDs aren't standardized across vendors in the first place; smartctl's own drive database exists precisely to interpret vendor-specific meanings). Real field incidents supplied by the user set the Critical/Medium bar:

- Sudden, active-failure signals → **Critical**: SMART overall-health self-assessment = FAILED, pending-sector count > 0, NVMe available spare below the critical threshold, or a disk transitioning to a non-healthy `HealthStatus` between visits. These map to the user's reported pattern of a disk going from fine to unusable "de un día para otro" and to Windows crashing/rebooting or reporting file corruption tied to that disk.
- Gradual wear without an active-failure signal (elevated wear%, reallocated-sector count present but stable, HDD nearing its typical service-life hours, elevated temperature) → **Medium/High**, matching today's `STO-004`-style informational-to-moderate severity — a maintenance-planning signal, not an emergency.

Exact numeric defaults are a `sdd-spec`/`sdd-design`-level decision (informed by smartctl/smartmontools' own conservative community defaults), not fixed here — this section only fixes the *shape* of the calibration (failure-signal vs. wear-trend) and that they live in `config.json`.

## Affected Areas

| Area | Impact | Description |
|------|--------|--------------|
| `Modules/Get-StorageInfo.ps1` | Modified | Add smartctl invocation + SMART fields per physical disk |
| `Modules/Get-HealthFindings.ps1` | Modified | New STO-* SMART rules |
| `Collector_Storage_Diagnostic.ps1` | New | Storage-only diagnostic collector (new file) |
| `Start-Inventory.ps1` | Modified | New menu option 10 |
| `Tools/smartctl.exe` | New | Bundled portable binary |
| `docs/JSON_SCHEMA.md` | Modified | Document new fields/artifact |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| smartctl output format varies by disk/controller | Medium | Parse defensively, degrade per-field not per-disk |
| Full health check runtime grows if smartctl is slow on old HW | Low | Same shared call already exists; measure, add timeout if needed |
| SMART thresholds picked wrong (false positives/negatives) | Medium | Start conservative, make thresholds config.json-configurable like existing HealthCheck thresholds |

## Rollback Plan

Revert the module/collector/menu commits; `Tools\smartctl.exe` removal alone reverts to today's graceful-degradation (CIM-only) behavior with no schema break, since SMART fields are additive.

## Dependencies

- `smartctl.exe` portable Windows build (smartmontools), bundled under `Tools\`.

## Success Criteria

- [ ] Both existing collectors emit SMART fields when smartctl is present, unchanged output when absent.
- [ ] New menu option 10 runs a storage-only diagnostic and opens its HTML report.
- [ ] New STO-* findings/recommendations render in existing generic HTML tables with no new rendering code.

## Resolved Decisions (user-confirmed, 2026-08-06)

1. Option 3 auto-picks up new SMART-based STO-* findings — no separate wiring, confirmed.
2. Thresholds are `config.json`-configurable, starting conservative — no external compliance standard to follow. See Severity Calibration.
3. Cross-visit SMART comparison is deferred out of this first change (moved to Out of Scope).
4. Real field incidents (sudden "disk error" onset, BSOD-with-reboots tied to a failing disk, file-corruption-triggered crashes) confirmed the Critical bar is active-failure signals, not gradual wear — see Severity Calibration.

## Real-World Amendment (2026-08-06): WMI FailurePredictData replaces smartctl as primary source

Manual field testing on the user's actual fleet (Dell OptiPlex 3050 — `BusType=RAID`, and an HP desktop — `BusType=SATA`) found `smartctl` cannot open the disk via ANY of its supported `-d` device types (`ata`, `scsi`, `sat`, `auto`) on either machine, confirmed by running `smartctl.exe` directly (no PowerShell involved) with admin rights, antivirus (ESET) both on and off — ruled out as the cause. This is a known, documented Windows limitation: unlike Linux's generic `SG_IO` interface, Windows requires each OEM's storage driver to explicitly implement ATA/SCSI pass-through, and many business-desktop OEM drivers don't (confirmed: a third machine, Windows + SSD, failed the same way; the same physical disk's `smartctl` test on a Linux boot worked fine — isolating this to the Windows driver layer, not the disk or `hawico`'s code).

`Get-StorageReliabilityCounter` (the newer Windows Storage Management API) was tried as a fallback — worked with real data on the HP (SATA) but returned empty disk-sourced fields on the Dell (RAID), only OS-measured latency.

The legacy `root\wmi` `MSStorageDriver_FailurePredictData` class **did** return real, verified data on the Dell where both of the above failed: a full standard 512-byte ATA SMART attribute table (validated by hand — 22 real attribute records decoded, including coherent PowerOnHours=22137h, Temperature=41°C, ReallocatedSectorCount=0, PendingSectorCount=0, UncorrectableSectorCount=0). Correlation to the physical disk confirmed via `Win32_DiskDrive.PNPDeviceID` matching `FailurePredictData.InstanceName` (same value, case-insensitive, `InstanceName` has a `_N` suffix).

**Decision**: WMI `MSStorageDriver_FailurePredictData` becomes the primary/default SMART source for ATA/SATA disks (ships with Windows, no external binary, worked where `smartctl` didn't). `smartctl` becomes a secondary/optional fallback for ATA/SATA disks and remains the only method for NVMe disks (this interface is ATA-SMART-specific, does not apply to NVMe — untested/unaffected by this amendment, no NVMe failures observed today).
