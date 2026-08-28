# Mapeo del Excel institucional

Este documento mapea la plantilla de referencia
`nuevo_equipos_optimizado.xlsx` al contrato técnico actual del recolector y al
registro importable `CollectionRecord 1.0`.

## Regla de arquitectura

El Excel es una proyección de presentación. No es la fuente de verdad.

- El JSON técnico conserva colecciones completas, valores originales y evidencia.
- El registro importable agrega identidad, sesión y trazabilidad.
- El futuro exportador XLSX reduce esas colecciones a las columnas exigidas por la
  plantilla, sin destruir el detalle original.
- Los campos manuales no reemplazan silenciosamente valores detectados.

## Columnas

| Columna | Encabezado institucional | Origen | Mapeo o regla | Estado |
| --- | --- | --- | --- | --- |
| A | REVISADO | CollectionRecord | Fecha y hora de la captura (`CollectionRecord.CollectedAt`), confirmada contra la plantilla real de la institución — pese al nombre de la columna, no es un estado de revisión administrativa. Ya siempre está poblada por `New-InventoryCollectionRecord`, así que no requiere una captura nueva. Se proyecta como valor `[datetime]` real (no texto) para que Excel la pueda ordenar/filtrar como fecha; usa la hora tal como se registró en el equipo recolectado (`.DateTime`, no `.LocalDateTime`), para que administrar el consolidado desde otra zona horaria nunca corra la hora mostrada. | Disponible |
| B | IP | Network | Proyección de `TechnicalData.NetworkAdapters[].IPv4Addresses`; el JSON conserva todas las direcciones. | Disponible |
| C | MAC ADDRESS | Network | Proyección de `TechnicalData.NetworkAdapters[].MACAddress`; nunca se usa sola para identificar el activo. | Disponible |
| D | DIRECCION | VisitCapture/Catalog | Unidad organizacional superior seleccionada durante la visita (`assignment.organizationUnitId`). | Disponible |
| E | USUARIO | VisitCapture | Persona asignada al equipo. No debe copiarse desde `Collection.ScriptUser`, porque ese valor identifica a quien ejecutó el recolector. | Pendiente de captura manual |
| F | DEPARTAMENTO | VisitCapture/Catalog | Unidad o departamento hijo de DIRECCION (`assignment.departmentUnitId`), seleccionado en cascada: el menú solo ofrece los hijos directos de la DIRECCION ya elegida. Se omite sin preguntar si la DIRECCION no tiene hijos o no fue seleccionada. | Disponible |
| G | MARCA | Hardware | `TechnicalData.Computer.Manufacturer`. | Disponible |
| H | MODELO | Hardware | `TechnicalData.Computer.Model`. | Disponible |
| I | PC / LAPTOP | Hardware/Calculated | Clasificación por chasis. `Computer.SystemType` no es suficiente para distinguir portátil y escritorio. | Requiere detector de chasis |
| J | PROCESADOR | Hardware | Primer elemento de `TechnicalData.Processors[].Name`; se conserva la colección completa. | Disponible |
| K | GHz | Calculated | `Processors[].MaxClockSpeedMHz / 1000`, conservando MHz en el JSON. | Disponible con proyección |
| L | RAM INSTALADA | Hardware | `TechnicalData.Memory.Upgrade.InstalledMemoryGB`. | Disponible |
| M | MODULOS INSTALADOS | Hardware | `TechnicalData.Memory.Upgrade.OccupiedSlots`. | Disponible |
| N | SLOTS RAM | Hardware | `TechnicalData.Memory.Upgrade.TotalSlots`. | Disponible; puede requerir verificación física |
| O | RAM MAX (GB) | Hardware | `TechnicalData.Memory.Upgrade.MaximumReportedGB`. | Disponible; confiabilidad del fabricante |
| P | TIPO RAM | Hardware/Calculated | Tipos distintos de `TechnicalData.Memory.Modules[].MemoryTypeName`; conflictos quedan para revisión. | Disponible con proyección |
| Q | TIPO DISCO | Hardware/Calculated | Medios y buses de `Storage.Detailed[]`, con respaldo en `Storage.Physical[]`. | Disponible con proyección |
| R | DISCO (GB) | Hardware/Calculated | Capacidades de discos físicos. El JSON conserva cada disco; Excel aplicará la regla institucional de presentación. | Disponible con proyección |
| — | ~~CANTIDAD REQUERIDA (memoria)~~ | Assessment | Removida (2026-08-07): no existe motor de recomendación de memoria en hawico, ni SMART aporta datos de RAM. Rellenarla habría sido inventar un valor. | Eliminada de la plantilla |
| — | ~~MEMORIA REQUERIDA~~ | Assessment | Removida (2026-08-07), mismo motivo que la anterior. | Eliminada de la plantilla |
| — | ~~VELOCIDAD~~ | Assessment | Removida (2026-08-07), mismo motivo que la anterior. | Eliminada de la plantilla |
| — | ~~CANTIDAD REQUERIDA (discos)~~ | Assessment | Removida (2026-08-07): SMART reporta *estado* de un disco, no una regla de cuántas unidades/qué capacidad instalar. | Eliminada de la plantilla |
| — | ~~DISCOS SSD REQUERIDA~~ | Assessment | Removida (2026-08-07), mismo motivo que la anterior. | Eliminada de la plantilla |
| X | CANTIDAD REQUERIDA (cambio) | Assessment (SMART) | `Get-InventoryStorageReplacementAssessment` sobre `TechnicalData.StorageFindings` (proyección de `Get-StorageSmartSummary`/STO-006..012). `1` si hay al menos un hallazgo `Critical`/`High` de almacenamiento; `null` si no. `Get-StorageSmartSummary` agrega "peor caso" entre todos los discos, así que no identifica cuál disco específico — no se inventa un conteo por disco. | Disponible |
| Y | CAMBIO DE EQUIPO | Assessment (SMART) | Títulos (join `; `) de los hallazgos `Critical`/`High` que dispararon la columna X. `null` si X es `null`. | Disponible |
| Z | S.O | Windows | `TechnicalData.OperatingSystem.Caption`. | Disponible |
| AA | HOSTNAME | CollectionRecord | Adición exclusiva de hawico, **no forma parte de la plantilla institucional original**. Se agrega al final, después de la columna Z, sin reordenar, renombrar ni tocar ninguna columna A-Z existente ni sus fórmulas de totales. Proyecta `CollectionRecord.ComputerName` (el nombre de equipo saneado que `New-InventoryCollectionRecord` copia de `Asset.ComputerName`), no `TechnicalData.Computer.Hostname` directamente. Permite ubicar la carpeta `Output\Equipos Obtenidos\<Hostname>...\` de un equipo a partir de su fila en el consolidado, sin necesidad de abrirla. | Disponible |
| AB | OBSERVACIONES | VisitCapture | Adición exclusiva de hawico, **no forma parte de la plantilla institucional original**. Misma regla de solo-agregar-al-final que HOSTNAME. Proyecta el campo manual `collection.observations` (las notas libres que captura el técnico en cada visita, etiquetado "Observaciones" en `Modules/New-InventoryManualCapture.ps1`). Ese campo nunca se reutiliza como valor por defecto en una visita posterior en otra parte del código ("las notas caducan"), pero eso solo afecta qué se precarga al capturar — no impide proyectar aquí la nota ya capturada. `null` si el técnico la omitió esa visita. | Disponible |

## Campos adicionales que no caben en la plantilla

El sistema debe conservar fuera del Excel, como mínimo:

- `CollectionId`, `SessionId`, versión del recolector y técnico. (La fecha de
  recolección sí está en el Excel — columna A, REVISADO, ver arriba — porque
  el equipo administrativo la necesita visible ahí; el resto de estos campos
  sigue disponible únicamente en el JSON/registro importable. El técnico que
  hizo la captura se puede ver en el reporte de Administración, columna
  "Técnico", derivada de `ManualFields[].CapturedBy`.)
- Número de serie y UUID usados para deduplicación.
- Todas las interfaces de red, direcciones IP y MAC.
- Todos los procesadores, módulos de memoria y discos físicos.
- Evidencia de confiabilidad, errores parciales y campos omitidos.
- Origen, fecha, responsable, confianza y estado de cada dato manual.

## Limitación encontrada en la plantilla

Las fórmulas actuales de totales usan los rangos `S6:S158`, `V6:V158` y
`X6:X158`, aunque la tabla llega hasta la fila 1009. El futuro motor XLSX debe
generar fórmulas sobre el rango real de datos o usar referencias estructuradas de
tabla; no debe copiar esos límites fijos.

