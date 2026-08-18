# Hardware Inventory Collector v2

## Uso rápido

1. Descomprime la carpeta completa.
2. Haz doble clic en `Ejecutar_Inventario.bat`.
3. Acepta la solicitud de permisos de administrador.
4. Selecciona inventario completo o rápido.
5. El reporte HTML se abrirá automáticamente.

## Overview

Hardware Inventory Collector is a standalone Windows hardware inventory
agent that collects reliable information from Windows computers and
exports it as JSON and HTML. It feeds an inventory platform rather than
replacing it.

## Starting the tools

On real machines, double-click the `.cmd` launcher instead of opening the
`.ps1` scripts directly:

- **`Iniciar-Recolector.cmd`** on field equipment — launches `Bootstrap.ps1`,
  which requests administrator elevation and opens `Start-Inventory.ps1`'s
  menu.
- **`Iniciar-Administracion.cmd`** on the support machine — launches
  `Start-Administration.ps1`'s menu directly.

The `.ps1` scripts are not meant to be double-clicked (or run via Windows'
"Run with PowerShell") directly in Windows: PowerShell's default execution
policy blocks unsigned scripts, and — depending on how the window was
opened — an unhandled error can close the console before anyone can read
it. The `.cmd` files exist specifically to avoid both problems: they set
`-ExecutionPolicy Bypass` for that single process and use `%~dp0` so they
work regardless of which drive letter the folder ends up on (e.g. a USB
stick), and every menu script blocks with `Read-Host` on both normal exit
and on error, so the window never disappears before its message can be
read.

## Carpetas

- `Output`: archivos JSON y HTML.
- `Logs`: registros de ejecución.
- `Modules`: módulos internos de PowerShell.

## Modos

- **Rápido:** equipo, Windows, CPU, RAM, red y almacenamiento.
- **Completo:** agrega gráficos, expansión, TPM, Secure Boot, BitLocker, periféricos conectados y dispositivos con errores.

## Configuración

El archivo `config.json` permite activar o desactivar formatos y secciones sin modificar el código.

## Compatibilidad

- Windows 10
- Windows 11
- Windows PowerShell 5.1 o superior

Ejecutar preferentemente como administrador.

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

## Local administration

`Import-InventoryRecords.ps1` imports every `*-record.json` under
`config.json`'s `Administration.RecordsPath` into a local, plain-JSON asset
store (`Administracion/`), assigning the permanent `AssetId` for the first
time, matching returning equipment by serial/UUID, and sorting each record
into `NuevosEquipos`, `EquiposActualizados`, `PosiblesDuplicados`,
`Conflictos` or `ErroresRecoleccion`. `Start-Administration.ps1` ties import,
an HTML report, manual conflict review and the consolidated Excel export
into one menu — the actual administration interface. See
[`docs/ADMINISTRATION.md`](docs/ADMINISTRATION.md) for the storage format,
the import trays, the menu, and why there is no SQLite dependency yet.

## Organization packages

`config.json.CollectionSession.OrganizationId`/`ProfileId` can point at a real
package under `Config/Organizations/<organizationId>/` (a usable
`org-example` package with a `basic-inventory` profile ships in the repo).
`Start-Inventory.ps1` resolves the active profile's manual fields from that
package and only falls back to `config.json.ManualFields` when no
organization is configured. See
[`docs/ORGANIZATION_PACKAGES.md`](docs/ORGANIZATION_PACKAGES.md) for the
package layout and what is loaded but not wired into capture yet (catalogs,
custom fields).

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

## Network inventory

The collector maps physical Ethernet and Wi-Fi adapters, including disconnected interfaces when `IncludeDisconnectedAdapters` is enabled. The HTML dashboard renders one card per adapter and distinguishes active and inactive interfaces.

## Inventario de periféricos

El modo completo recopila los dispositivos PnP presentes y genera áreas separadas para USB y docks, Bluetooth, audio, cámaras, teclados, mouse, controles HID, pantallas, impresoras, almacenamiento removible, puertos, biometría, tarjetas inteligentes y sensores.

La opción `IncludePeripherals` de `config.json` permite desactivar esta recopilación. El collector excluye controladores host, hubs raíz y dispositivos virtuales conocidos para reducir duplicados y ruido, pero conserva el identificador PnP para diagnóstico.

## Historial de versiones

### Versión 2.0.1

Se corrigió el inicio elevado para evitar que la ventana se cierre sin mostrar errores.

Use `Ejecutar_Inventario.bat`. Si existe un error de inicio, la ventana permanecerá abierta y mostrará el archivo y la línea afectada.

También se incluye `Diagnostico.ps1` para comprobar rutas, versión de PowerShell y archivos esenciales.

### Versión 2.0.2

El arranque ahora usa `Bootstrap.ps1` y PowerShell con `-NoExit`.

Esto garantiza que la consola elevada permanezca abierta aunque ocurra un error antes de cargar el menú.

Los errores de arranque se guardan automáticamente en:

`Logs\startup-error.txt`

Para diagnóstico adicional puede ejecutarse:

`Ejecutar_Modo_Diagnostico.bat`

### Versión 2.0.3

Se corrigió el error:

`El término '.\Bootstrap.ps1' no se reconoce...`

Los lanzadores ahora usan la ruta absoluta obtenida desde `%~dp0`, por lo que funcionan aunque Windows o UAC cambien la carpeta de trabajo.

Se recomienda extraer el ZIP completo antes de ejecutarlo.

### Versión 2.0.4

Se corrigió la excepción `No se encuentra la propiedad Count en este objeto`.

PowerShell puede convertir automáticamente una colección de un solo elemento en un objeto individual. Los módulos de memoria, almacenamiento, procesador, gráficos y expansión ahora fuerzan explícitamente sus resultados a arreglos mediante `@(...)`.

También se mejoró el reporte de errores para mostrar el archivo y la línea reales del módulo que falla, en lugar de señalar únicamente la llamada desde `Start-Inventory.ps1`.
