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
