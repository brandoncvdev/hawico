# JSON Schema

Schema version: `2.1`

Top-level areas:

- `Collection`
- `Computer`
- `OperatingSystem`
- `BIOS`
- `Motherboard`
- `Processors`
- `Memory`
- `Storage`
- `GraphicsAdapters`
- `NetworkAdapters`
- `Security`
- `Expansion`
- `Peripherals`
- `DevicesWithErrors`
- `StorageFindings`
- `StorageRecommendations`

`Peripherals` contains:

- `CollectionMethod`: primary Windows source used by the collector.
- `Devices`: connected devices grouped in the HTML by `Category`.
- `Summary`: totals for categories, external devices, USB, Bluetooth and devices with problems.

Each peripheral includes its friendly name, manufacturer, PnP class, inferred connection type, status, problem code, backing service and instance identifier when Windows exposes them.

La extensión de diagnóstico de Windows conserva `SchemaVersion 2.0` y agrega:

```text
HealthCheck (ContractVersion 1.2)
└── ExtendedDiagnostics (ContractVersion 1.0)
    ├── Processes
    ├── StartupPrograms
    └── InstalledSoftware
```

El detalle normativo, los estados parciales y las reglas de privacidad están en
[`HEALTH_CHECK.md`](HEALTH_CHECK.md).

### Diagnóstico SMART de almacenamiento

`Storage.Physical[]` agrega un campo opcional `Smart` con la misma forma sin
importar el origen del dato — `ConvertFrom-AtaSmartAttributeTable` (WMI
`root\wmi` `MSStorageDriver_FailurePredictData`, fuente primaria en discos
ATA/SATA) o `ConvertFrom-SmartctlJson` (`smartctl.exe`, secundaria/opcional
para ATA/SATA y única para NVMe) — ambas en `Modules/Get-StorageInfo.ps1`:

```text
Smart
├── Supported (bool)
├── Source ('ATA' | 'NVMe' | 'Unavailable')
├── OverallHealth ('PASSED' | 'FAILED' | null)
├── TemperatureCelsius (number | null)
├── PowerOnHours (number | null)
├── PowerCycleCount (number | null)
├── ReallocatedSectorCount (number | null — ATA only)
├── PendingSectorCount (number | null — ATA only)
├── UncorrectableSectorCount (number | null — ATA only)
├── AvailableSparePercent (number | null — NVMe only)
├── PercentageUsed (number | null — NVMe only)
├── MediaErrorCount (number | null — NVMe only)
├── CriticalWarningFlags (number | null — NVMe only)
├── ErrorCode (string | null)
└── ErrorMessage (string | null)
```

Para discos no NVMe, `Get-DiskSmartData` consulta primero WMI
(`Get-DiskSmartDataFromWmi`, correlacionado vía `Win32_DiskDrive.PNPDeviceID`
↔ `FailurePredictData.InstanceName`) — no requiere ningún binario externo. Solo
si WMI no tiene datos (`Supported = $false`) recurre a `smartctl.exe`
(`Tools\smartctl.exe`) como respaldo, si está presente. Los discos NVMe
siguen dependiendo exclusivamente de `smartctl.exe` (`-d nvme`), sin cambios.
Cuando ninguna fuente está disponible o falla, `Supported` queda en `false` y
`Source` en `'Unavailable'`; el resto de los campos permanece en `null` sin
lanzar excepción.

Internamente, `Invoke-HealthCheck` (`Modules/Invoke-HealthCheck.ps1`) calcula el
peor caso (worst-of) entre todos los discos vía `Get-StorageSmartSummary`
(`Modules/Get-StorageHealth.ps1`) y lo agrega como `Smart` a la métrica de
almacenamiento que alimenta el motor de hallazgos, exponiendo el mismo
subconjunto de campos salvo `Source`, `PowerCycleCount`, `ErrorCode` y
`ErrorMessage`. Ese agregado es la evidencia que activa las reglas
`STO-006`..`STO-012`, documentadas en [`HEALTH_CHECK.md`](HEALTH_CHECK.md).

### Diagnóstico de almacenamiento independiente

`Collector_Storage_Diagnostic.ps1` reutiliza sin cambios `Invoke-HealthCheck` y
`Export-HealthCheck.ps1` (`Modules/Invoke-HealthCheck.ps1`,
`Modules/Export-HealthCheck.ps1`) para producir el mismo contrato
`SchemaVersion 2.0` / `HealthCheck.ContractVersion 1.2` descrito arriba, pero sin
muestrear rendimiento (CPU/Memoria) ni consultar el registro de eventos: las
secciones `Performance` y `Events` quedan siempre en `Status: "Skipped"` con
`Score.Categories` marcando `CPU`, `Memory` y `Events` como `Available: false`.
Solo `Storage` se evalúa, por lo que `Score.Status` es `InsufficientData` de
forma intencional (`EvaluatedWeight` = 35, por debajo del umbral de 60 descrito
en [`HEALTH_CHECK.md`](HEALTH_CHECK.md) §12.2) — no representa un fallo, sino la
cobertura real de este diagnóstico enfocado.

Artefactos, siguiendo la misma convención de subcarpeta por equipo que
`Collector_Windows_HealthCheck.ps1`:

```text
Output/<hostname>/<hostname>-<timestamp>-storage.json
Output/<hostname>/<hostname>-<timestamp>-storage.html
Logs/<hostname>-<timestamp>-storage.log
```

### Hallazgos de almacenamiento en el inventario completo (opciones 1/2)

`Collector_Hardware_Inventory.ps1` agrega dos campos nuevos de nivel superior
al JSON técnico `SchemaVersion 2.0` — `StorageFindings` y
`StorageRecommendations` — reutilizando sin cambios el mismo motor de reglas
`STO-006`..`STO-012` que ya usa el diagnóstico independiente (opción 10):
tras capturar `Storage = Get-StorageInventory`, el recolector ejecuta
`Get-StorageHealth -StorageInventory $storage -SystemDrive $env:SystemDrive`
y luego `Invoke-HealthCheck` con el mismo patrón "vacío pero bien formado"
de `Performance`/`Events` (`Status: "Skipped"`) que
`Collector_Storage_Diagnostic.ps1` — solo `Storage` se evalúa. Únicamente se
extraen `HealthCheck.Findings` y `HealthCheck.Recommendations`; el resto del
reporte de salud (`Score`, `Sections`, etc.) se descarta y no se persiste.
Esta evaluación es de solo presentación adicional: nunca aborta la
recolección — una falla degrada silenciosamente ambos campos a `[]`.

```text
StorageFindings[]                 // misma forma que HealthCheck.Findings
├── Id                            // p.ej. "STO-006".."STO-012"
├── Category                      // "Storage"
├── Severity                      // "Critical" | "High" | "Medium" | "Low"
├── Title
├── Description
├── Evidence
├── RecommendationId
└── ScoreImpact

StorageRecommendations[]          // misma forma que HealthCheck.Recommendations
├── Id                            // p.ej. "REC-STO-001".."REC-STO-007"
├── Title
├── Description
└── FindingIds[]
```

`Modules/Export.ps1` (`New-InventoryHtml`) renderiza estos dos campos como
tablas nuevas bajo la sección "Almacenamiento", junto con una tabla de
valores SMART crudos por disco ("Estado SMART") construida a partir de
`Storage.Physical[].Smart` — mostrada siempre que al menos un disco tenga
`Smart.Supported = true`, independientemente de si hubo hallazgos (nivel 2,
distinto de los hallazgos condicionales de nivel 3). Cuando ningún disco
soporta SMART, se muestra un mensaje informativo en vez de una tabla vacía.

## Registro importable de inventario

El recolector de hardware conserva el JSON técnico `SchemaVersion 2.0` y genera un
artefacto adicional `*-record.json` con `ContractVersion 1.0`. Este registro agrega
identidad fuerte candidata, contexto de sesión y trazabilidad sin duplicar reglas
de detección ni romper el HTML existente.

El contrato normativo está documentado en [`API_CONTRACT.md`](API_CONTRACT.md) y el
mapeo hacia la plantilla institucional en
[`INSTITUTIONAL_EXCEL_MAPPING.md`](INSTITUTIONAL_EXCEL_MAPPING.md).
