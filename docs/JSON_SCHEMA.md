# JSON Schema

Collection Computer OperatingSystem BIOS Motherboard Processors Memory
Storage GraphicsAdapters NetworkAdapters Security Expansion
DevicesWithErrors

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

`Storage.Physical[]` agrega un campo opcional `Smart` con la forma devuelta por
`ConvertFrom-SmartctlJson` (`Modules/Get-StorageInfo.ps1`):

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

Cuando `Tools\smartctl.exe` no está disponible o falla, `Supported` queda en
`false` y `Source` en `'Unavailable'`; el resto de los campos permanece en
`null` sin lanzar excepción.

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

## Registro importable de inventario

El recolector de hardware conserva el JSON técnico `SchemaVersion 2.0` y genera un
artefacto adicional `*-record.json` con `ContractVersion 1.0`. Este registro agrega
identidad fuerte candidata, contexto de sesión y trazabilidad sin duplicar reglas
de detección ni romper el HTML existente.

El contrato normativo está documentado en [`API_CONTRACT.md`](API_CONTRACT.md) y el
mapeo hacia la plantilla institucional en
[`INSTITUTIONAL_EXCEL_MAPPING.md`](INSTITUTIONAL_EXCEL_MAPPING.md).
