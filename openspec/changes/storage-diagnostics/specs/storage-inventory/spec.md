# Storage Inventory Specification

## Purpose

Nivel 1 (identity) and Nivel 2 (state) storage capture, extended with SMART attributes via `smartctl.exe`, shared automatically by both existing collectors through `Get-StorageInventory`.

## Requirements

### Requirement: SMART Attribute Capture

The system MUST invoke `Tools\smartctl.exe -j` per physical disk found by `Get-StorageInventory` and merge parsed Nivel 2 fields — `OverallHealthPassed`, `TemperatureCelsius`, `PowerOnHours`, `PowerCycleCount`, `ReallocatedSectorCount`, `PendingSectorCount`, `UncorrectableErrorCount`, `AvailableSpare`, `AvailableSpareThreshold`, `PercentageUsed`, `WearLevelingCount`, `VendorAttributesRaw` — into each disk's `Storage.Physical[]` entry.

#### Scenario: SMART data available
- GIVEN a physical disk supports SMART and smartctl succeeds
- WHEN `Get-StorageInventory` runs
- THEN the disk's entry includes populated SMART fields alongside existing identity fields

#### Scenario: Disk without SMART support
- GIVEN a disk (e.g. unsupported USB bridge) returns no SMART data
- WHEN `Get-StorageInventory` runs
- THEN SMART fields for that disk are null and identity fields stay populated

### Requirement: Graceful Degradation

The system MUST NOT fail the collection when `Tools\smartctl.exe` is missing, errors, times out, or returns non-JSON for one or more disks. Degradation MUST be per-field, not per-disk: unaffected identity/CIM data is preserved, per the existing try/catch pattern.

#### Scenario: smartctl.exe absent
- GIVEN `Tools\smartctl.exe` is not present on the collection medium
- WHEN `Get-StorageInventory` runs
- THEN identity/CIM fields are captured as before, all SMART fields are null, and no exception is thrown

#### Scenario: smartctl fails on one disk only
- GIVEN smartctl succeeds for disk 0 and errors for disk 1
- WHEN `Get-StorageInventory` runs
- THEN disk 0 has populated SMART fields, disk 1 has null SMART fields, and both disks remain in the result

### Requirement: Wear Percentage Normalization

The system MUST normalize wear indicators from any source (NVMe `percentage_used`, SATA SSD countdown wear attributes) into one `WearPercentUsed` field on a 0 (new) to 100 (fully worn) scale, so downstream analysis compares HDD/SSD/NVMe consistently.

#### Scenario: SATA SSD countdown attribute
- GIVEN a SATA SSD reports a wear-remaining normalized value of 80
- WHEN normalization runs
- THEN `WearPercentUsed` is 20 (the equivalent used-percentage)

### Requirement: Shared Capture, No Duplicate Wiring

Both `Collector_Hardware_Inventory.ps1` and `Collector_Windows_HealthCheck.ps1` MUST receive the extended SMART fields automatically through their existing call to `Get-StorageInventory`, with no change to their own invocation code.

#### Scenario: Existing collectors unchanged
- GIVEN both collectors already call `Get-StorageInventory`
- WHEN SMART capture is added inside that function
- THEN both collectors' `record.json` gains the new fields with zero collector-level code change
