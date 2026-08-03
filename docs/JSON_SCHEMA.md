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

## Registro importable de inventario

El recolector de hardware conserva el JSON técnico `SchemaVersion 2.0` y genera un
artefacto adicional `*-record.json` con `ContractVersion 1.0`. Este registro agrega
identidad fuerte candidata, contexto de sesión y trazabilidad sin duplicar reglas
de detección ni romper el HTML existente.

El contrato normativo está documentado en [`API_CONTRACT.md`](API_CONTRACT.md) y el
mapeo hacia la plantilla institucional en
[`INSTITUTIONAL_EXCEL_MAPPING.md`](INSTITUTIONAL_EXCEL_MAPPING.md).
