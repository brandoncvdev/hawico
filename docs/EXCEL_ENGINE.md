# Excel consolidation engine

Implements the MVP scope of `docs/12-Excel-Engine.md` from the planning
document: regenerating an institutional-style consolidated workbook from the
`*-record.json` files the hardware collector already produces.

## Dependency

The engine uses the [ImportExcel](https://github.com/dfinke/ImportExcel)
PowerShell module (tested against 7.8.10) instead of Excel COM automation or a
hand-rolled OOXML writer. It writes `.xlsx` files directly (via EPPlus under
the hood) and works cross-platform, including on machines without Excel
installed.

Install it once per machine that will run `Export-InventoryWorkbook.ps1`:

```powershell
Install-Module ImportExcel -Scope CurrentUser -Force
```

`Export-InventoryWorkbook.ps1` and `Export-InventoryConsolidatedWorkbook`
check `Get-Module -ListAvailable -Name ImportExcel` up front and throw a clear
error with that exact command if the module is missing, instead of failing
deep inside an `Export-Excel` call.

## Source of data

The engine reads a folder of `*-record.json` files (the `CollectionRecord`
artifacts the collector already writes next to the legacy `SchemaVersion 2.0`
JSON — see `docs/API_CONTRACT.md`), recursively, so records from multiple
session subfolders can be consolidated in one pass. It does **not** read from
SQLite — that store, and the deduplication/administration workflow around it,
is Phase 3 of the plan and does not exist yet.

## MVP scope: 3 sheets

Only **Inventario**, **Pendientes** and **Resumen** are generated.
`Detalle técnico`, `Evaluación` and `Datos originales` (also described in the
plan) are intentionally left out of this MVP: there is no real content to put
in them yet — `Assessments` is still always an empty array (no RAM/disk
evaluation rules exist, see `08-Manual-Capture.md`/`09-Memory-Assessment.md`),
and a raw "original data" dump sheet duplicates what the `*-record.json` /
`*.json` files already preserve untouched. They can be added later without
changing the shape of the sheets that already exist.

- **Inventario** — one row per collection record, mapped by
  `ConvertTo-InventoryWorkbookRow` (see column table below).
- **Pendientes** — one row per record that has at least one open issue
  (`Get-InventoryPendingReviewRows`): asset identity needing review, no
  session assigned, or no user captured during the visit.
- **Resumen** — six aggregate counters (`Get-InventoryConsolidationSummary`):
  total equipment, identity confirmed / needs review, session assigned / not
  assigned, user captured.

## Columns available today vs. pending

`ConvertTo-InventoryWorkbookRow` follows `docs/INSTITUTIONAL_EXCEL_MAPPING.md`
column-by-column. All of the JSON paths that document lists
(`TechnicalData.Computer.Manufacturer`, `TechnicalData.Processors[]`,
`TechnicalData.Memory.Upgrade.*`, `TechnicalData.Memory.Modules[]`,
`TechnicalData.Storage.Physical[]` / `.Detailed[]`,
`TechnicalData.NetworkAdapters[].IPv4Addresses` / `.MACAddress`,
`TechnicalData.OperatingSystem.Caption`) were verified against the actual
collector modules (`Get-ComputerInfo.ps1`, `Get-ProcessorInfo.ps1`,
`Get-MemoryInfo.ps1`, `Get-NetworkInfo.ps1`, `Get-StorageInfo.ps1`) before
being coded — they match exactly, no corrections were needed. `REVISADO` is
also always populated (`CollectionRecord.CollectedAt`, projected as a real
`[datetime]`) — confirmed against the institution's real template that this
column holds the capture date, not a review-status flag.

Always `$null` today, with the reason:

| Column | Why |
| --- | --- |
| `DEPARTAMENTO` | No manual field exists yet for the unit *below* `DIRECCION`; the hierarchical `OrganizationUnit` catalog is Phase 4 (agnostic configuration). |
| `PC / LAPTOP` | No chassis detector (SMBIOS `ChassisTypes`) is implemented. |
| `CANTIDAD REQUERIDA (MEMORIA)`, `MEMORIA REQUERIDA`, `VELOCIDAD`, `CANTIDAD REQUERIDA (DISCOS)`, `DISCOS SSD REQUERIDA`, `CANTIDAD REQUERIDA (CAMBIO)`, `CAMBIO DE EQUIPO` | All 7 depend on RAM/disk evaluation rules (`docs/09-Memory-Assessment.md`) that do not exist yet — `Assessments` is always `[]`. |

### Duplicate header disambiguation

The institutional template visibly repeats the header **CANTIDAD REQUERIDA**
three times (columns S, V and X — see `docs/INSTITUTIONAL_EXCEL_MAPPING.md`).
A single row object cannot have three properties with the same name, so each
one is disambiguated with a short qualifier while staying recognizable as the
same visible header:

- S → `CANTIDAD REQUERIDA (MEMORIA)`
- V → `CANTIDAD REQUERIDA (DISCOS)`
- X → `CANTIDAD REQUERIDA (CAMBIO)`

### TIPO DISCO heuristic

`Get-InventoryDiskTypeLabel` prefers `BusType = NVMe` over `MediaType`,
because `Get-PhysicalDisk` usually reports NVMe drives with `MediaType=SSD`,
which would otherwise make them indistinguishable from SATA SSDs in this
column. If `Storage.Detailed` is empty, it falls back to `Storage.Physical`.
Multiple distinct types (RAM or disk) are joined with `/` instead of picking
one arbitrarily, so a mixed configuration is visible instead of hidden.

## Regeneration policy

The workbook is always regenerated **completely** from the current
`*-record.json` files — `Export-InventoryConsolidatedWorkbook` deletes
`$OutputPath` if it already exists before writing, so sheets never
accumulate stale data across runs (`docs/12-Excel-Engine.md`: "regenerar el
archivo completo de manera reproducible"). If `-HistoryDirectory` is
supplied, the freshly generated file is additionally copied to
`Consolidado-{yyyyMMdd-HHmmss}.xlsx` there, so a dated history of past
consolidations is preserved even though the live file is not incremental.

## Configuration

`config.json`'s `Consolidation` block controls the three paths
`Export-InventoryWorkbook.ps1` uses by default:

```json
"Consolidation": {
  "RecordsPath": ".\\Output",
  "OutputPath": ".\\Output\\Consolidado.xlsx",
  "HistoryDirectory": ".\\Output\\Historico"
}
```
