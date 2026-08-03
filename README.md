# Hardware Inventory Collector

## Overview

Hardware Inventory Collector is a standalone Windows hardware inventory
agent that collects reliable information from Windows computers and
exports it as JSON and HTML. It feeds an inventory platform rather than
replacing it.

## Session-aware inventory records

Hardware inventory now preserves the existing `SchemaVersion 2.0` JSON and also
creates an import-ready `*-record.json` artifact. The new record carries a
versioned collection ID, strong asset identity candidates, and the shared session
context required to consolidate results from many computers.

Before a collection journey, update `CollectionSession` in `config.json`:

```json
{
  "CollectionSession": {
    "SessionId": "SES-20260803-AM-RH",
    "OrganizationId": "ORG-001",
    "ProfileId": "basic-inventory",
    "Technician": "Brandon"
  }
}
```

The launcher builds a `CollectionSession` from that block once at startup and
forwards only the resolved `SessionId` to both full and quick inventory modes.
`OrganizationId`, `ProfileId` and `Technician` are session-only context — they
are never passed to the collector or stored on the `CollectionRecord`. When
running the collector directly, only the session id is available as a
parameter:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Collector_Hardware_Inventory.ps1 `
  -Mode Full `
  -SessionId "SES-20260803-AM-RH"
```

`SES-UNASSIGNED` remains the backward-compatible default, but those records must
be reviewed before institutional consolidation — running without a real session
id prints a warning. See [`docs/API_CONTRACT.md`](docs/API_CONTRACT.md) and
[`docs/INSTITUTIONAL_EXCEL_MAPPING.md`](docs/INSTITUTIONAL_EXCEL_MAPPING.md).

## Excel consolidation

`Export-InventoryWorkbook.ps1` consolidates every `*-record.json` under
`config.json`'s `Consolidation.RecordsPath` into a single regenerated
`.xlsx` workbook (`Inventario`, `Pendientes`, `Resumen`), using the
[ImportExcel](https://github.com/dfinke/ImportExcel) module
(`Install-Module ImportExcel -Scope CurrentUser -Force`). See
[`docs/EXCEL_ENGINE.md`](docs/EXCEL_ENGINE.md) for the MVP scope, the
columns available today vs. pending, and the regeneration policy.

## Windows health diagnostic

The first delivery of the read-only Windows Performance Health Check is available
from option **3** of `Start-Inventory.ps1` or directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Collector_Windows_HealthCheck.ps1 `
  -Mode Diagnostic
```

For a shorter provider smoke test, override the sample duration with the minimum
validated value:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Collector_Windows_HealthCheck.ps1 `
  -Mode Diagnostic `
  -SampleDurationSeconds 10
```

The collector writes differentiated `*-health.json`, `*-health.html`, and
`*-health.log` artifacts. It never runs repair or optimization commands. A provider
failure is reported as partial evidence instead of being treated as a healthy value.

Run the Windows-only integration acceptance test on a Windows 10 and a Windows 11
target after installing Pester:

```powershell
Invoke-Pester -Path .\Tests\WindowsHealthIntegration.Tests.ps1 -Output Detailed
```

The architecture, contract, scoring rules, privacy policy, and phased roadmap are
defined in [`docs/HEALTH_CHECK.md`](docs/HEALTH_CHECK.md).
