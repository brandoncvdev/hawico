# Storage Diagnostic Collector Specification

## Purpose

A standalone, menu-triggered collector that runs a fast, storage-only diagnostic (Nivel 1+2+3) without the full health-check's multi-minute CPU/memory/event sampling.

## Requirements

### Requirement: Menu-Triggered Standalone Collector

`Start-Inventory.ps1` MUST expose a new menu option "10. Ejecutar diagnóstico de almacenamiento" that dispatches `Collector_Storage_Diagnostic.ps1`, following the same session-context (organization/technician) handoff used by existing menu options.

#### Scenario: Technician selects option 10
- GIVEN the technician is at the main menu
- WHEN they select option 10
- THEN `Collector_Storage_Diagnostic.ps1` runs with the active session context and control returns to the menu on completion

### Requirement: Storage-Scoped Content, No Full Sampling

The collector MUST call `Get-StorageInventory` and the storage-scoped subset of `Get-HealthFindings.ps1` only. It MUST NOT run CPU/memory performance sampling or event-log collection.

#### Scenario: No sampling delay
- GIVEN the collector runs on a machine with no storage issues
- WHEN diagnostic collection completes
- THEN the report contains Storage inventory/findings/recommendations only, with no Performance or Events sections and no multi-second sampling loop

### Requirement: Output Artifact Convention

The collector MUST write `<Hostname>-<timestamp>-storage.json`, `<Hostname>-<timestamp>-storage.html`, and a log file, using the same `Output\<Hostname>\` / `Logs\` layout, JSON schema conventions, and open-output-folder behavior as `Collector_Windows_HealthCheck.ps1`.

#### Scenario: Successful run
- GIVEN `GenerateJSON` and `GenerateHTML` are both true
- WHEN the collector completes
- THEN both files exist under `Output\<Hostname>\` and the log file exists under `Logs\`

### Requirement: Reuse Existing Generic Rendering

The HTML report MUST render Storage findings/recommendations through the existing generic findings/recommendations table components. The collector MUST NOT introduce a separate rendering path.

#### Scenario: Findings render without new HTML code
- GIVEN one or more STO-* findings exist
- WHEN the HTML report is generated
- THEN they appear in the same generic findings table markup used by the full health-check report

### Requirement: Graceful Degradation Carries Through

When `smartctl.exe` is absent or a disk yields no SMART data, the collector MUST still complete and produce a report using CIM/`Get-PhysicalDisk`-only data, consistent with `storage-inventory`'s degradation behavior.

#### Scenario: smartctl missing
- GIVEN `Tools\smartctl.exe` is not present
- WHEN the technician runs option 10
- THEN the collector completes successfully and the report shows identity/CIM-based findings only, without SMART-based STO-* findings
