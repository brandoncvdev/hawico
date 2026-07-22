# Feature: Windows Performance Health Check

## 1. Propósito

Esta funcionalidad amplía el recolector de inventario actual con un diagnóstico de
rendimiento y salud para equipos Windows.

El principio rector es:

> Diagnosticar antes de modificar.

El primer entregable recopila evidencia, calcula hallazgos deterministas y genera
reportes JSON y HTML. No repara, optimiza ni cambia la configuración del equipo.

## 2. Alcance por entregables

### 2.1 Entregable 1: diagnóstico esencial

Incluye exclusivamente:

1. Preparación, identificación del equipo y detección de capacidades.
2. Muestreo de CPU y memoria.
3. Estado de discos físicos y volúmenes.
4. Eventos críticos de hardware, almacenamiento y estabilidad.
5. Hallazgos y recomendaciones deterministas.
6. Puntuación de salud con nivel de confianza.
7. Exportación JSON compatible con el contrato actual.
8. Reporte HTML resumido.
9. Ejecución parcial cuando falten permisos o proveedores de datos.

### 2.2 Entregable 2: diagnóstico extendido

Quedan fuera del primer entregable:

- Procesos de alto consumo y programas de inicio.
- Servicios de Windows y tareas programadas.
- Software instalado.
- Integridad de Windows mediante SFC y DISM en modo de verificación.
- Windows Update y reinicios pendientes.
- Estado de Microsoft Defender, antivirus y firewall.
- Monitor de confiabilidad.
- Rendimiento de arranque e inicio de sesión.
- Estado de energía y batería.
- Diagnóstico de red y temperatura cuando exista una fuente confiable.

### 2.3 Entregable 3: historial y remediación controlada

Quedan fuera de los dos primeros entregables:

- Comparación antes y después.
- Historial local y tendencias.
- Integración con un dashboard centralizado.
- Ejecución remota.
- Optimización segura.
- Optimización avanzada.
- Políticas organizacionales y listas de acciones permitidas.
- Registro de cambios, reversión y puntos de restauración.

Estas capacidades se documentan como una feature futura e independiente en
[`WINDOWS_OPTIMIZATION_LAB.md`](WINDOWS_OPTIMIZATION_LAB.md). Health Check aporta
la línea base y la evidencia, pero no ejecuta los cambios.

Ninguna acción de optimización debe implementarse como parte del entregable 1.

## 3. Compatibilidad

La primera versión debe funcionar con:

- Windows 10.
- Windows 11.
- Windows PowerShell 5.1.
- Ejecución interactiva desde el launcher actual.
- Ejecución directa desde PowerShell.

Ejemplo:

```powershell
.\Collector_Windows_HealthCheck.ps1 `
    -Mode Diagnostic `
    -SampleDurationSeconds 60
```

El único modo permitido en el entregable 1 es `Diagnostic`.

## 4. Arquitectura acoplada al sistema actual

La feature conserva la arquitectura real del repositorio: scripts principales en
la raíz, módulos `.ps1` dentro de `Modules`, un único `config.json` y las carpetas
compartidas `Output` y `Logs`.

No se introducen las carpetas `InventoryApp`, `Collectors` o `Exporters`, ni se
migran los módulos existentes a `.psm1` como parte de esta feature.

Estructura objetivo:

```text
hawico/
├── Bootstrap.ps1
├── Start-Inventory.ps1
├── Collector_Hardware_Inventory.ps1
├── Collector_Windows_HealthCheck.ps1
├── config.json
├── Modules/
│   ├── Common.ps1
│   ├── Get-ComputerInfo.ps1
│   ├── Get-ProcessorInfo.ps1
│   ├── Get-MemoryInfo.ps1
│   ├── Get-StorageInfo.ps1
│   ├── Get-HealthCapabilities.ps1
│   ├── Get-PerformanceHealth.ps1
│   ├── Get-StorageHealth.ps1
│   ├── Get-CriticalEvents.ps1
│   ├── Get-HealthFindings.ps1
│   ├── Export.ps1
│   └── Export-HealthCheck.ps1
├── Output/
├── Logs/
└── docs/
    └── HEALTH_CHECK.md
```

### 4.1 Responsabilidades

| Componente | Responsabilidad |
| --- | --- |
| `Start-Inventory.ps1` | Exponer la opción de diagnóstico y abrir su último reporte. |
| `Collector_Windows_HealthCheck.ps1` | Orquestar la ejecución y aislar errores por sección. |
| `Get-HealthCapabilities.ps1` | Detectar permisos, cmdlets, contadores y proveedores disponibles. |
| `Get-PerformanceHealth.ps1` | Muestrear CPU y memoria sin aplicar cambios. |
| `Get-StorageHealth.ps1` | Evaluar discos físicos, volúmenes y disponibilidad de sus datos. |
| `Get-CriticalEvents.ps1` | Consultar y agrupar eventos relevantes. |
| `Get-HealthFindings.ps1` | Aplicar reglas, scoring y recomendaciones. |
| `Export-HealthCheck.ps1` | Crear el HTML usando los helpers visuales existentes cuando aplique. |

Los módulos actuales de equipo, procesador, memoria y almacenamiento deben
reutilizarse para la información base. Las métricas dinámicas viven dentro de
`HealthCheck` y no alteran la forma de los campos existentes.

## 5. Flujo del entregable 1

```text
Inicio
  |
  v
Cargar config.json
  |
  v
Detectar capacidades y permisos
  |
  v
Recopilar inventario base reutilizable
  |
  v
Muestrear CPU y memoria
  |
  v
Evaluar discos y volúmenes
  |
  v
Consultar eventos críticos
  |
  v
Aplicar reglas y calcular score
  |
  v
Exportar JSON, HTML y log
  |
  v
Fin
```

Un fallo de una sección no debe cancelar las secciones independientes. Cada
sección informa su propio estado y el reporte global pasa a `Partial`.

## 6. Configuración

La configuración se agrega al `config.json` existente bajo una propiedad opcional
`HealthCheck`.

```json
{
  "HealthCheck": {
    "SampleDurationSeconds": 60,
    "SampleIntervalSeconds": 1,
    "EventLookbackDays": 7,
    "MinimumFreeDiskPercent": 20,
    "CriticalFreeDiskPercent": 10,
    "MemoryWarningPercent": 70,
    "MemoryHighPercent": 85,
    "MemoryCriticalPercent": 95,
    "MinimumAvailableMemoryMB": 1024,
    "IncludePersonallyIdentifiableInformation": false
  }
}
```

### 6.1 Validación

- `SampleDurationSeconds`: entero entre 10 y 300.
- `SampleIntervalSeconds`: entero entre 1 y 10, menor que la duración.
- `EventLookbackDays`: entero entre 1 y 30.
- Los umbrales de memoria deben cumplir `Warning < High < Critical`.
- Los umbrales de disco deben cumplir `Critical < Minimum`.
- Una configuración ausente utiliza los valores predeterminados anteriores.
- Una configuración inválida detiene la ejecución antes de recopilar datos.
- La generación de JSON y HTML reutiliza `GenerateJSON` y `GenerateHTML` del nivel
  raíz para evitar dos fuentes de verdad.

## 7. Preparación y capacidades

Antes de recolectar métricas deben registrarse:

- Fecha y hora en formato ISO 8601 con zona horaria.
- Duración solicitada y duración efectiva.
- Estado de permisos administrativos.
- Disponibilidad de los cmdlets y contadores requeridos.
- Versión de PowerShell.
- Versión del colector.
- Identificación base obtenida por los módulos existentes.

Cada capacidad utiliza uno de estos estados:

```text
Available
Unavailable
Denied
NotSupported
```

La falta de permisos administrativos no detiene el diagnóstico. Solamente marca
como `Skipped` o `Failed` las secciones que realmente los necesiten.

## 8. Recolección del diagnóstico esencial

### 8.1 CPU

Recopilar:

- Modelo, núcleos y procesadores lógicos desde el inventario existente.
- Porcentaje promedio durante la muestra.
- Porcentaje máximo durante la muestra.
- Cantidad de muestras válidas.
- Porcentaje de muestras con uso igual o superior al 90%.

La evaluación utiliza una serie temporal. Un valor máximo aislado no genera un
hallazgo.

### 8.2 Memoria

Recopilar:

- Memoria física instalada desde el inventario existente.
- Promedio y máximo del porcentaje de uso.
- Promedio y mínimo de memoria disponible en MB.
- Memoria comprometida y límite cuando el contador esté disponible.
- Cantidad de muestras válidas.

Los hallazgos de utilización requieren que la condición se cumpla en al menos el
80% de las muestras válidas.

### 8.3 Discos físicos y volúmenes

Por cada disco físico recopilar, cuando Windows lo exponga:

- Fabricante, modelo y número de serie.
- Tipo de medio: `HDD`, `SSD`, `NVMe` o `Unknown`.
- Capacidad.
- Estado operativo.
- Estado de salud.
- Fuente utilizada para obtener el estado.

Por cada volumen recopilar:

- Letra o identificador.
- Sistema de archivos.
- Capacidad total.
- Espacio libre.
- Porcentaje libre.
- Indicador de volumen del sistema operativo.

`Unknown` o un dato no disponible nunca debe convertirse en `Healthy`. Debe
registrarse como no evaluado.

El entregable 1 no ejecuta `chkdsk`, desfragmentación, TRIM ni pruebas de escritura.

### 8.4 Eventos críticos

Consultar los últimos `EventLookbackDays` días y agrupar por proveedor, ID y mensaje
normalizado.

Proveedores iniciales:

```text
Disk
Ntfs
StorPort
stornvme
WHEA-Logger
Kernel-Power
Application Error
Application Hang
```

Registrar:

- Proveedor.
- ID.
- Nivel.
- Cantidad.
- Primera y última aparición.
- Mensaje resumido y redactado.

Los eventos de disco alimentan únicamente la categoría `Storage`; no se vuelven a
penalizar en `Events`.

## 9. Estados de sección y manejo de errores

Cada sección debe producir este sobre:

```json
{
  "Name": "Performance",
  "Status": "Collected",
  "StartedAt": "2026-07-22T10:30:00-06:00",
  "DurationMilliseconds": 60123,
  "SampleCount": 60,
  "ErrorCode": null,
  "ErrorMessage": null
}
```

Estados permitidos:

```text
Collected
Partial
Skipped
Failed
```

Los mensajes deben ser útiles para soporte, pero no deben incluir stack traces,
tokens, argumentos sensibles ni contenido privado dentro del JSON o HTML.

## 10. Contrato JSON

### 10.1 Estrategia de compatibilidad

El documento raíz conserva `SchemaVersion: "2.0"` y las propiedades existentes del
inventario. La feature agrega:

- `Collection.Type` con el valor `WindowsHealthCheck`.
- `Collection.DurationMilliseconds`.
- La propiedad raíz `HealthCheck`.

Los consumidores actuales deben poder ignorar propiedades nuevas. La forma de
`Computer`, `OperatingSystem`, `BIOS`, `Motherboard`, `Processors`, `Memory` y
`Storage` no cambia.

`HealthCheck.ContractVersion` versiona únicamente la extensión de diagnóstico.

### 10.2 Estructura normativa

```json
{
  "SchemaVersion": "2.0",
  "Collection": {
    "CollectedAt": "2026-07-22T10:31:05-06:00",
    "Mode": "Diagnostic",
    "Type": "WindowsHealthCheck",
    "ScriptUser": "<REDACTED>",
    "DurationMilliseconds": 65000
  },
  "Computer": {},
  "OperatingSystem": {},
  "BIOS": {},
  "Motherboard": {},
  "Processors": [],
  "Memory": {},
  "Storage": {},
  "HealthCheck": {
    "ContractVersion": "1.1",
    "Status": "Completed",
    "IsAdministrator": true,
    "Capabilities": [],
    "Sections": [],
    "Sample": {
      "RequestedDurationSeconds": 60,
      "ActualDurationSeconds": 60,
      "IntervalSeconds": 1,
      "ValidSampleCount": 60
    },
    "Metrics": {
      "CPU": {},
      "Memory": {},
      "Storage": {},
      "Events": {}
    },
    "Score": {
      "Value": 92,
      "Status": "Healthy",
      "ConfidencePercent": 100,
      "ScoringVersion": "1.0",
      "EvaluatedWeight": 100,
      "TotalDeduction": 8,
      "Categories": []
    },
    "PrimaryBottleneck": "Memory",
    "Findings": [],
    "Recommendations": [],
    "Errors": []
  }
}
```

### 10.3 Valores nulos y propiedades ausentes

- Una propiedad definida por el contrato debe existir aunque su valor sea `null`.
- Una colección sin elementos se representa como `[]`.
- Un objeto sin datos se representa como `{}` solamente cuando su sección explica
  por qué no pudo recopilarse.
- `null` significa desconocido o no disponible; nunca significa saludable, cero o
  falso.
- Todos los tamaños incluyen la unidad en el nombre: `MB`, `GB` o `Bytes`.
- Todos los porcentajes son números entre 0 y 100.

### 10.4 Estado global

Valores permitidos para `HealthCheck.Status`:

```text
Completed
Partial
Failed
```

- `Completed`: todas las secciones obligatorias fueron recopiladas.
- `Partial`: al menos una sección fue omitida o falló, pero existe evidencia útil.
- `Failed`: no se pudo producir un diagnóstico utilizable.

## 11. Hallazgos y recomendaciones

Cada hallazgo sigue esta estructura:

```json
{
  "Id": "MEM-002",
  "Category": "Memory",
  "Severity": "High",
  "Title": "Sustained high memory utilization",
  "Description": "Memory usage remained between 85% and 95% during at least 80% of the sample.",
  "Evidence": {
    "AverageUsagePercent": 89.2,
    "PeakUsagePercent": 93.1,
    "MatchingSamplePercent": 86.7
  },
  "RecommendationId": "REC-MEM-001",
  "ScoreImpact": -15
}
```

Severidades permitidas:

```text
Info
Low
Medium
High
Critical
```

Una recomendación debe referenciar al menos un hallazgo. No se generan
recomendaciones genéricas sin evidencia.

## 12. Puntuación de salud 1.0

### 12.1 Categorías

El scoring del entregable 1 utiliza únicamente categorías que el propio entregable
puede medir:

| Categoría | Peso máximo |
| --- | ---: |
| Storage | 35 |
| Memory | 25 |
| CPU | 20 |
| Events | 20 |
| **Total** | **100** |

Cada categoría tiene una deducción entre cero y su peso máximo. Las deducciones de
reglas diferentes se suman y luego se limitan al peso de la categoría.

### 12.2 Datos no disponibles y confianza

Una categoría sin datos suficientes:

- No suma deducciones.
- No se considera saludable.
- No participa en `EvaluatedWeight`.
- Reduce `ConfidencePercent` en el valor de su peso.

Fórmulas:

```text
EvaluatedWeight = suma de pesos de categorías evaluadas
TotalDeduction = suma de deducciones limitadas por categoría
Value = round(100 * (1 - TotalDeduction / EvaluatedWeight))
ConfidencePercent = EvaluatedWeight
```

Si `EvaluatedWeight` es menor que 60, `Score.Status` es `InsufficientData` y
`Score.Value` es `null`.

### 12.3 Clasificación

| Puntuación | Estado |
| --- | --- |
| 90-100 | Healthy |
| 75-89 | Attention |
| 50-74 | Degraded |
| 0-49 | Critical |
| Sin cobertura suficiente | InsufficientData |

### 12.4 PrimaryBottleneck

Se selecciona la categoría con mayor proporción:

```text
CategoryDeduction / CategoryWeight
```

Si no existen deducciones, el valor es `None`. En caso de empate se usa la mayor
severidad y luego el orden `Storage`, `Memory`, `CPU`, `Events`.

Valores permitidos:

```text
None
CPU
Memory
Storage
Events
Unknown
```

## 13. Reglas deterministas 1.0

Los límites inferiores son inclusivos y los superiores exclusivos.

### 13.1 Storage

| Regla | Condición | Severidad | Deducción |
| --- | --- | --- | ---: |
| STO-001 | Estado explícito del disco distinto de `Healthy` | Critical | 35 |
| STO-002 | Volumen del sistema con espacio libre menor a 10% | Critical | 20 |
| STO-003 | Volumen del sistema con espacio libre desde 10% y menor a 20% | High | 10 |
| STO-004 | Disco del sistema identificado como HDD | Medium | 5 |
| STO-005 | Tres o más eventos diagnósticos de `Disk`, `Ntfs`, `StorPort` o `stornvme` | High | 15 |

`STO-002` y `STO-003` son mutuamente excluyentes. La categoría se limita a 35.
Un estado `Unknown` no activa `STO-001`.

Para `STO-005`, `Disk` considera los IDs 7, 9, 11, 51, 153 y 157;
`Ntfs`, los IDs 50, 55, 98 y 140; y `StorPort`/`stornvme`, únicamente
eventos con nivel `Critical`, `Error` o `Warning`. Los demás eventos permanecen
como evidencia observable, pero no reducen la puntuación.

### 13.2 Memory

Todas las reglas de esta categoría se basan en al menos 80% de muestras
coincidentes:

| Regla | Condición | Severidad | Deducción |
| --- | --- | --- | ---: |
| MEM-001 | Uso igual o superior a 95% | Critical | 25 |
| MEM-002 | Uso desde 85% y menor a 95% | High | 15 |
| MEM-003 | Uso desde 70% y menor a 85% | Medium | 8 |
| MEM-004 | Memoria disponible menor a 1024 MB | High | 10 |

`MEM-001`, `MEM-002` y `MEM-003` son mutuamente excluyentes. `MEM-004` puede
acumularse y la categoría se limita a 25.

### 13.3 CPU

| Regla | Condición | Severidad | Deducción |
| --- | --- | --- | ---: |
| CPU-001 | Uso igual o superior a 90% en al menos 80% de las muestras | High | 20 |
| CPU-002 | Promedio desde 80% y menor a 90% | Medium | 10 |

`CPU-001` y `CPU-002` son mutuamente excluyentes. Un pico aislado no penaliza.

### 13.4 Events

| Regla | Condición dentro del periodo configurado | Severidad | Deducción |
| --- | --- | --- | ---: |
| EVT-001 | Uno o más eventos `WHEA-Logger` | Critical | 20 |
| EVT-002 | Dos o más reinicios inesperados `Kernel-Power` ID 41 | High | 12 |
| EVT-003 | Cinco o más fallos `Application Error` ID 1000 o `Application Hang` ID 1002 | Medium | 8 |

Las reglas pueden acumularse y la categoría se limita a 20. Los eventos ya
utilizados por `STO-005` se excluyen de esta categoría.

Una consulta sin coincidencias no vuelve parcial la sección: significa que el
proveedor pudo consultarse y no produjo evidencia dentro del periodo. Sólo un
error real de acceso o disponibilidad del proveedor degrada su estado.

## 14. Privacidad y seguridad

El diagnóstico no debe recopilar:

- Contraseñas, tokens, claves privadas o credenciales.
- Contenido de archivos personales.
- Historial de navegación.
- Argumentos completos de líneas de comando.
- Exclusiones de antivirus durante el entregable 1.
- Mensajes de eventos sin normalización y redacción.

Con `IncludePersonallyIdentifiableInformation: false`:

- `Collection.ScriptUser` conserva su tipo `string` con el valor `<REDACTED>`.
- Los nombres de usuario en rutas se reemplazan por `<USER>`.
- Los mensajes de eventos se resumen sin datos variables sensibles.
- El HTML no muestra usuario, rutas completas ni números de serie.

El JSON conserva los campos del contrato aunque sus valores sean `null`.

## 15. Reporte HTML

El reporte reutiliza el lenguaje visual actual y contiene:

1. Equipo y fecha de diagnóstico.
2. Estado global, puntuación y confianza.
3. Cuello de botella principal.
4. Hallazgos críticos y altos.
5. Resumen de CPU y memoria.
6. Discos y volúmenes.
7. Resumen de eventos.
8. Recomendaciones vinculadas a hallazgos.
9. Secciones omitidas o fallidas.

El HTML es un resumen compartible. El detalle técnico permanece en JSON y log,
respetando la política de privacidad.

## 16. Archivos de salida

Se reutilizan las rutas configuradas en `OutputDirectory` y `LogDirectory`.

Formato:

```text
Output/<hostname>-<timestamp>-health.json
Output/<hostname>-<timestamp>-health.html
Logs/<hostname>-<timestamp>-health.log
```

El resultado del collector conserva el patrón actual:

```powershell
[ordered]@{
    Success         = $true
    OutputDirectory = $outputDir
    JsonPath        = $jsonPath
    HtmlPath        = $htmlPath
    LogPath         = $logPath
}
```

## 17. Pruebas y criterios de aceptación

La implementación debe desarrollarse con pruebas Pester y fixtures, sin depender
exclusivamente del estado de la máquina que ejecuta las pruebas.

### 17.1 Casos mínimos de reglas

- Memoria en `69.99`, `70`, `84.99`, `85`, `94.99` y `95` por ciento.
- Disco en `9.99`, `10`, `19.99` y `20` por ciento libre.
- Reglas mutuamente excluyentes.
- Suma de deducciones limitada al peso de la categoría.
- Categoría no disponible excluida de `EvaluatedWeight`.
- Score nulo cuando la confianza sea menor a 60%.
- Desempate determinista del cuello de botella.
- Eventos de almacenamiento sin doble penalización.

### 17.2 Escenarios funcionales

1. Equipo saludable con SSD, memoria suficiente y sin eventos relevantes:
   `Healthy` con puntuación entre 90 y 100.
2. Volumen del sistema con menos de 10% libre: hallazgo `STO-002`.
3. Uso de memoria igual o superior a 95% de forma sostenida: `MEM-001`.
4. Disco con estado explícitamente degradado: `STO-001`.
5. Equipo sin permisos administrativos: ejecución `Partial` con explicación.
6. Contadores de rendimiento ausentes: sección afectada sin inventar valores.
7. Una sección falla y las secciones independientes se completan.
8. JSON válido, serializable y compatible con `SchemaVersion 2.0`.
9. HTML legible y sin información restringida.

### 17.3 Definición de terminado del entregable 1

- Ejecuta en Windows 10 y Windows 11 con PowerShell 5.1.
- Acepta solamente `Mode Diagnostic`.
- No ejecuta comandos de reparación u optimización.
- Produce JSON y HTML con nombres diferenciados del inventario.
- Conserva las propiedades existentes del contrato 2.0.
- Reporta capacidades, estados de sección y errores parciales.
- Aplica exactamente las reglas de scoring 1.0.
- No confunde datos desconocidos con estados saludables.
- Cumple la política de privacidad configurada.
- Tiene pruebas deterministas para límites, scoring y fallos parciales.

## 18. Evolución del contrato

- `HealthCheck.ContractVersion 1.1` agrega detalle aditivo de proveedores de eventos
  fallidos, aliases canónicos para proveedores modernos de Windows y una
  explicación visual de la diferencia entre completitud y cobertura del score.
- `ScoringVersion 1.0` y sus reglas permanecen sin cambios.

- Cambios aditivos en `HealthCheck` incrementan su versión menor.
- Cambios incompatibles incrementan `HealthCheck.ContractVersion` mayor.
- La evolución del contrato raíz se coordina con `docs/JSON_SCHEMA.md` y los
  consumidores existentes.
- Agregar categorías del entregable 2 requiere una nueva `ScoringVersion`; nunca se
  reinterpretan silenciosamente resultados históricos.

El objetivo del primer entregable es producir evidencia confiable y explicable.
Una medición que no puede obtenerse debe declararse como no disponible: inventar
certeza es peor que admitir que falta información.
