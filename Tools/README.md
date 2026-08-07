# Tools

Esta carpeta almacena binarios portables de terceros que los recolectores invocan
como procesos externos. No contiene código propio del proyecto.

## smartctl.exe

`Get-StorageInventory` (`Modules/Get-StorageInfo.ps1`) resuelve por defecto la
ruta:

```text
Tools\smartctl.exe
```

relativa a la raíz del repositorio (un nivel arriba de `Modules\`, vía
`$PSScriptRoot`-relative resolution: `Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools'`).
Este es el nombre y la ubicación exactos que debe tener el binario para que la
captura SMART funcione sin pasar `-SmartctlPath` explícitamente.

### Qué colocar aquí

El build portable de Windows de **smartctl**, parte de
[smartmontools](https://www.smartmontools.org/) (licencia GPLv2), específicamente
`smartctl.exe` de la distribución `smartmontools-<versión>-win32-setup.exe` /
`.zip` para Windows (arquitectura x64 recomendada; smartctl no requiere
instalación ni registro, el `.exe` autónomo basta). Cópielo tal cual, sin
renombrar, en:

```text
Tools\smartctl.exe
```

### Por qué no está incluido en el repositorio

Un binario real de terceros no puede generarse ni descargarse desde este
entorno de ejecución, y un archivo simulado o vacío haciéndose pasar por el
binario real induciría a error (falsos positivos/negativos en el diagnóstico
SMART). Por eso esta carpeta se entrega vacía salvo este `README.md`.

### Comportamiento sin el binario

Tanto `Collector_Windows_HealthCheck.ps1` como `Collector_Storage_Diagnostic.ps1`
siguen funcionando sin `Tools\smartctl.exe`: `Get-StorageInventory` hace un único
`Test-Path` antes del bucle de discos (no un intento por disco) y, si el binario
está ausente, omite por completo el lanzamiento de procesos y marca cada disco
con `Smart.Supported = $false`, `Smart.Source = 'Unavailable'` y
`Smart.ErrorCode = 'SMARTCTL-NOT-FOUND'` — sin lanzar excepción y sin degradar el
resto de la captura de almacenamiento. Esta ruta de degradación ya está cubierta
por pruebas (`Tests/Get-StorageInfo.Tests.ps1`,
`Tests/CollectorContract.Tests.ps1`).
