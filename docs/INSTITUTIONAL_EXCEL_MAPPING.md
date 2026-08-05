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
| S | CANTIDAD REQUERIDA (memoria) | Assessment | Cantidad de módulos recomendados por la evaluación de memoria. | Pendiente de reglas versionadas |
| T | MEMORIA REQUERIDA | Assessment | Capacidad y tipo recomendado. | Pendiente de reglas versionadas |
| U | VELOCIDAD | Assessment | Velocidad recomendada compatible con los módulos detectados y la verificación física. | Pendiente de reglas versionadas |
| V | CANTIDAD REQUERIDA (discos) | Assessment | Cantidad de unidades recomendadas. | Pendiente de reglas versionadas |
| W | DISCOS SSD REQUERIDA | Assessment | Capacidad y tecnología recomendada. | Pendiente de reglas versionadas |
| X | CANTIDAD REQUERIDA (cambio) | Assessment/ManualReview | Valor numérico utilizado por el consolidado. | Pendiente de reglas versionadas |
| Y | CAMBIO DE EQUIPO | Assessment/ManualReview | Motivo o recomendación de reemplazo. | Pendiente de reglas versionadas |
| Z | S.O | Windows | `TechnicalData.OperatingSystem.Caption`. | Disponible |

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

