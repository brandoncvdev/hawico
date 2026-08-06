# Design: Storage Device Diagnostics Module

## Technical Approach

Extend the existing storage pipeline instead of building a parallel one. SMART
capture is added inside `Get-StorageInventory` (shared by both collectors,
zero call-site changes since it self-resolves `Tools\smartctl.exe` via
`$PSScriptRoot`). New `STO-006..012` rules extend `Get-HealthFinding`'s
existing storage block. A new `Collector_Storage_Diagnostic.ps1` reuses
`Invoke-HealthCheck` + `Export-HealthCheck.ps1` unmodified for scoring/HTML,
supplying empty-but-well-formed CPU/Memory/Events sections so only the
Storage category is `Available` (Score = `InsufficientData`, which is
accurate — no CPU/Memory/Events were sampled).

## Architecture Decisions

| Decision | Choice | Alternatives considered | Rationale |
|---|---|---|---|
| SMART invocation trigger | New pure fn `ConvertFrom-SmartctlJson` (parse) separate from `Invoke-SmartctlCommand` (process spawn) and `Get-DiskSmartData` (orchestrator) | One monolithic function | Strict TDD: parse logic testable with fixture JSON strings, no mocked binary needed |
| `-d` device-type flag | `nvme` for BusType=NVMe; `sat` for BusType=USB (retry once if it fails); omitted (`auto`) otherwise | Always `-d auto` | USB bridges frequently misreport under auto-detect; ATA/SATA/SAS auto-detect reliably |
| Missing smartctl.exe | One `Test-Path` check before the disk loop; if absent, skip process spawning entirely and mark every disk `Unavailable` | Per-disk Test-Path | Avoids N failed spawns; single explicit degrade path |
| Per-disk failure | try/catch around `Get-DiskSmartData` per disk inside `Get-StorageInventory`'s existing `$physical` loop | Abort whole capture on first failure | Matches existing `Get-PhysicalDisk` try/catch convention; one bad disk must not blank the rest |
| Aggregate SMART evidence for findings | New pure fn `Get-StorageSmartSummary` (worst-of across `PhysicalDisks[].Smart`) called from `Invoke-HealthCheck` | Per-disk finding fan-out | Matches existing single-representative aggregation (`$explicitDegraded` pattern) already used for STO-001 |
| New collector's non-storage sections | Reuse `Invoke-HealthCheck` as-is with empty CPU/Memory/Events defaults | Fork a storage-only scoring/report function | Zero new HTML/report code (proposal's explicit goal); `InsufficientData` status is truthful |

## Data Flow

    smartctl.exe -a -j -d <type> \\.\PhysicalDriveN
         │ (stdout JSON, 15s timeout, per-disk try/catch)
         ▼
    Invoke-SmartctlCommand ──▶ ConvertFrom-SmartctlJson ──▶ .Smart on Physical[i]
         │                                                        │
         ▼                                                        ▼
    Get-StorageInventory (Physical[], Detailed[], Logical[])  Get-StorageHealth
                                                                    │ (joins Smart via
                                                                    │  SerialNumber, existing pattern)
                                                                    ▼
                                              Get-StorageSmartSummary (worst-of)
                                                                    │
                                                                    ▼
                                              Invoke-HealthCheck ──▶ Get-HealthFinding (STO-006..012)
                                                                    │
                                                                    ▼
                                              Export-HealthCheck.ps1 (unmodified) ──▶ HTML

## File Changes

| File | Action | Description |
|------|--------|--------------|
| `Modules/Get-StorageInfo.ps1` | Modify | Add `ConvertFrom-SmartctlJson`, `Invoke-SmartctlCommand`, `Get-DiskSmartData`; loop `$physical` to attach `.Smart`; new optional `-SmartctlPath` param (default `$PSScriptRoot`-resolved) |
| `Modules/Get-StorageHealth.ps1` | Modify | Carry `.Smart` from base disk onto each `$disks` record (same join as Manufacturer/Model); add `Get-StorageSmartSummary` |
| `Modules/Get-HealthFindings.ps1` | Modify | New `STO-006..012` rules + `REC-STO-005/006/007` in the catalog |
| `Modules/Invoke-HealthCheck.ps1` | Modify | Call `Get-StorageSmartSummary`, add `Smart` to `$metrics.Storage` |
| `Collector_Storage_Diagnostic.ps1` | Create | Storage-only collector, mirrors `Collector_Windows_HealthCheck.ps1` |
| `Start-Inventory.ps1` | Modify | Menu line "10. Ejecutar diagnóstico de almacenamiento" + `"10"` switch case |
| `config.json` | Modify | New `HealthCheck` SMART threshold keys |
| `Tools/smartctl.exe` | Create | Bundled portable binary (binary asset, not code) |
| `docs/JSON_SCHEMA.md` | Modify | Document `.Smart` shape and new collector artifact |

## Interfaces / Contracts

```powershell
# Pure — unit-testable with fixture strings, no process spawn
function ConvertFrom-SmartctlJson {
    param([Parameter(Mandatory)][object]$SmartctlOutput)  # already ConvertFrom-Json'd
    # returns [ordered]@{ Supported; Source('ATA'|'NVMe'|'Unavailable'); OverallHealth;
    #   TemperatureCelsius; PowerOnHours; PowerCycleCount;
    #   ReallocatedSectorCount; PendingSectorCount; UncorrectableSectorCount;   # ATA-only, else $null
    #   AvailableSparePercent; PercentageUsed; MediaErrorCount; CriticalWarningFlags;  # NVMe-only, else $null
    #   ErrorCode; ErrorMessage }
}
function Invoke-SmartctlCommand { param([string]$SmartctlPath,[int]$DiskIndex,[string]$DeviceTypeFlag,[int]$TimeoutMs = 15000) }
function Get-DiskSmartData { param([string]$SmartctlPath,[int]$DiskIndex,[string]$BusType) }
function Get-StorageSmartSummary { param([object[]]$PhysicalDisks) }  # worst-of, pure
```

New `config.json` → `HealthCheck` keys (all optional, defaulted like existing ones,
names match the spec exactly):
`StoragePendingSectorCriticalCount`(1), `StorageAvailableSpareCriticalPercent`(10),
`StorageReallocatedSectorWarningCount`(1) — single-tier, no High variant,
`StorageWearWarningPercent`(70)/`StorageWearHighPercent`(90),
`StorageTemperatureWarningC`(55)/`StorageTemperatureHighC`(65),
`StorageHddServiceLifeWarningHours`(26280).

`STO-00X` severities: `STO-006` FAILED self-assessment → Critical(40); `STO-007` ATA
pending sectors → Critical(35); `STO-008` NVMe spare below critical → Critical(35);
`STO-009` reallocated sectors → Medium(10) only, no High tier; `STO-010` wear% used →
Medium(10)/High(18); `STO-011` temperature → Medium(8)/High(15); `STO-012` HDD
`PowerOnHours` ≥ service-life warning hours → Medium(10).

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | `ConvertFrom-SmartctlJson` ATA/NVMe/malformed/missing-field fixtures | Static JSON strings, no binary |
| Unit | `Get-StorageSmartSummary` worst-of across N disks | In-memory objects |
| Unit | `Get-HealthFinding` STO-006..012 threshold boundaries | Same pattern as existing MEM-*/STO-* tests |
| Integration | `Get-StorageInventory` with missing smartctl.exe, with a stub `Invoke-SmartctlCommand` returning failure | Verify per-disk degrade, no exception |
| E2E | Menu option "10" end-to-end on a real machine (manual, Windows-only) | Not automatable in CI |

## Threat Matrix

Applicable — this design adds a new subprocess invocation (`smartctl.exe`).

| Case | Applicable | Expected behavior | RED test |
|---|---|---|---|
| Binary missing | Yes | Skip spawn, degrade all disks to `Unavailable`, no exception | `Get-StorageInventory` with absent path |
| Process hangs | Yes | 15s timeout kills process, disk marked `ErrorCode=SMARTCTL-TIMEOUT` | Stub invoker simulating no exit |
| Malformed/partial JSON | Yes | `ConvertFrom-SmartctlJson` returns `Supported=$false` + `ErrorCode`, never throws | Fixture with truncated JSON |
| Arbitrary/injected args | N/A | Device path built only from `$_.Index` (int) and a fixed flag set; no user/string interpolation into args | — |
| Elevation | N/A | Existing `Bootstrap.ps1` elevation already covers the whole collector process | — |

## Migration / Rollout

No migration required. New `.Smart` fields are additive; absent `Tools\smartctl.exe`
reproduces today's behavior exactly (proposal's stated rollback plan).

## Open Questions

- [ ] Exact ATA wear-leveling SMART attribute ID to read (vendor-dependent: 233 or
      177) — resolve empirically against sample fixture drives during `sdd-apply`.
