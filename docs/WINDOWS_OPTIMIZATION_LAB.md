# Feature futura: Windows Optimization Lab

## 1. Estado

```text
Candidate
```

Este documento describe una posible feature posterior a Windows Performance
Health Check. No forma parte del entregable 1 ni autoriza su implementación
automática.

## 2. Propósito

Windows Optimization Lab permitiría que un usuario autorizado pueda:

- Previsualizar oportunidades de limpieza.
- Probar cambios reversibles de experiencia de usuario.
- Auditar configuraciones contra una política organizacional.
- Aplicar únicamente acciones aprobadas.
- Comparar el estado antes y después.
- Conservar o revertir un experimento según evidencia.

La feature no promete que una modificación vaya a mejorar el rendimiento. Su
objetivo es convertir cambios manuales en sesiones controladas, medibles y
auditables.

## 3. Separación respecto de Health Check

| Health Check | Optimization Lab |
| --- | --- |
| Diagnostica | Propone, prueba o aplica |
| Es de solo lectura | Puede modificar con autorización |
| Produce hallazgos | Consume hallazgos como evidencia |
| Calcula el health score | No altera el score histórico |
| Puede ejecutarse solo | Requiere una línea base reciente para aplicar cambios |

Optimization Lab utiliza el JSON de Health Check como línea base. Sus resultados
se guardan en un contrato independiente para evitar mezclar diagnóstico con
remediación.

## 4. Principios

```text
Medir -> Proponer -> Autorizar -> Aplicar -> Validar -> Conservar o revertir
```

1. Sin evidencia no hay candidato.
2. Sin política no hay acción administrada.
3. Sin autorización no hay modificación.
4. Un cambio reversible debe incluir su plan de reversión antes de ejecutarse.
5. Una eliminación debe declararse irreversible y requiere confirmación específica.
6. Un cambio aplicado no demuestra por sí mismo una mejora.
7. Compliance y experiencia de usuario no afectan el health score.

## 5. Perfiles opcionales

### 5.1 Cleanup

Evalúa y, cuando exista autorización, limpia ubicaciones permitidas.

Vista previa inicial:

- Estimación de archivos temporales del usuario.
- Estimación de temporales administrados por Windows.
- Estado y configuración de Storage Sense.
- Espacio potencialmente recuperable.
- Archivos bloqueados o ubicaciones no evaluadas.

No se incluyen por defecto:

- Descargas.
- Papelera de reciclaje.
- Cachés de aplicaciones corporativas.
- Contenido sincronizado con servicios en la nube.
- Perfiles de otros usuarios.

La vista previa registra cantidades y tamaños agregados. No expone nombres de
archivos en JSON o HTML.

### 5.2 UserExperience

Permite probar cambios reversibles y acotados, por ejemplo:

- Animaciones de ventanas.
- Transparencias.
- Desvanecimientos y sombras decorativas.
- Sugerencias y recomendaciones de Windows.
- Widgets u otros elementos opcionales de la interfaz.

Estos cambios se consideran experimentos, no optimizaciones universales. No deben
recomendarse únicamente por tener poca RAM, un HDD o gráficos integrados.

Cada experimento debe definir:

- Configuración actual.
- Configuración propuesta.
- Alcance de usuario o equipo.
- Métrica que se pretende observar.
- Duración mínima de observación.
- Procedimiento de reversión.
- Criterio para conservar o revertir.

Los cambios de accesibilidad, suavizado de fuentes y controles exigidos por una
política quedan excluidos salvo autorización explícita.

### 5.3 Compliance

Compara el equipo contra una política proporcionada por la organización.

Posibles dominios:

- Aplicaciones de inicio permitidas o prohibidas.
- Software requerido, permitido o no autorizado.
- Estado de Storage Sense.
- Configuración de energía.
- Datos de diagnóstico opcionales.
- Sugerencias, widgets y elementos de interfaz.
- Configuraciones de seguridad que no pertenezcan al health score.

Estados permitidos:

```text
Compliant
NonCompliant
NotApplicable
NotEvaluated
```

Un resultado `NonCompliant` no significa que el equipo tenga bajo rendimiento. El
reporte de compliance debe mantenerse separado de los estados `Healthy`,
`Attention`, `Degraded` y `Critical`.

## 6. Modos de ejecución

### 6.1 Preview

- No modifica el sistema.
- Enumera candidatos soportados.
- Estima impacto, riesgo y reversibilidad.
- Explica qué dato o política originó cada candidato.

### 6.2 Experiment

- Aplica temporalmente una acción reversible.
- Captura el valor anterior antes de modificarlo.
- Ejecuta la medición posterior con parámetros equivalentes.
- Permite conservar o revertir el cambio.

### 6.3 Audit

- No modifica el sistema.
- Requiere una política versionada.
- Produce resultados de compliance independientes.

### 6.4 Apply

- Ejecuta exclusivamente acciones incluidas en una política.
- Requiere confirmación explícita.
- Registra el resultado de cada acción.
- No continúa silenciosamente después de un fallo crítico.

`Preview` y `Audit` son los únicos modos habilitados por defecto.

## 7. Candidatos iniciales

### 7.1 Integrables

| Candidato | Perfil | Primer modo | Condición |
| --- | --- | --- | --- |
| Estimar espacio temporal | Cleanup | Preview | Sin enumerar nombres en el reporte. |
| Revisar Storage Sense | Cleanup / Compliance | Preview / Audit | Respetar política de Descargas, papelera y nube. |
| Revisar elementos de inicio | Compliance | Audit | Requiere allowlist o denylist institucional. |
| Probar animaciones | UserExperience | Experiment | Solamente como cambio reversible. |
| Probar transparencias | UserExperience | Experiment | Sin asumir beneficio de rendimiento. |
| Revisar sugerencias y widgets | Compliance | Audit | Se evalúa como política o UX, no como salud. |
| Revisar plan de energía | Compliance | Audit | Considerar AC/DC, batería y tipo de equipo. |
| Revisar software instalado | Compliance | Audit | Requiere catálogo institucional. |

### 7.2 Excluidos inicialmente

- Clasificar aplicaciones solamente por nombre, tamaño o fecha.
- Afirmar que una aplicación está sin uso sin telemetría confiable.
- Activar siempre el plan de alto rendimiento.
- Activar siempre programación de GPU acelerada por hardware.
- Deshabilitar todos los servicios que no sean de Microsoft.
- Eliminar aplicaciones preinstaladas de forma masiva.
- Vaciar la papelera o limpiar Descargas por defecto.
- Apagar toda la telemetría como regla genérica.
- Depender de desinstaladores de terceros.
- Ejecutar cambios de drivers, firmware o seguridad como experimentos de UX.

## 8. Modelo de candidatos

Cada candidato debe contener evidencia y límites explícitos:

```json
{
  "Id": "OPT-UX-001",
  "Profile": "UserExperience",
  "Action": "DisableWindowAnimations",
  "EvidenceFindingIds": [],
  "PolicyRuleId": "UX-ANIMATIONS-OPTIONAL",
  "ClassificationSource": "OrganizationPolicy",
  "CurrentState": "Enabled",
  "ProposedState": "Disabled",
  "ExpectedBenefit": "Reduce visual transition overhead",
  "Risk": "Low",
  "Reversible": true,
  "RequiresApproval": true,
  "CanAutomate": true
}
```

Valores permitidos para `ClassificationSource`:

```text
OrganizationPolicy
MeasuredEvidence
Heuristic
Unknown
```

Un candidato con origen `Heuristic` o `Unknown` nunca puede aplicarse
automáticamente.

## 9. Sesión y contrato JSON

La feature conserva el contrato raíz del sistema y agrega una extensión separada:

```json
{
  "SchemaVersion": "2.0",
  "Collection": {
    "CollectedAt": "2026-07-22T12:00:00-06:00",
    "Mode": "Experiment",
    "Type": "WindowsOptimizationSession",
    "ScriptUser": "<REDACTED>",
    "DurationMilliseconds": 125000
  },
  "OptimizationSession": {
    "ContractVersion": "1.0",
    "SessionId": "OPT-PC01-20260722-120000",
    "Profile": "UserExperience",
    "Status": "Validated",
    "BaselineReport": "PC01-20260722-115000-health.json",
    "PolicyVersion": "2026.07",
    "Actions": [],
    "Validation": {
      "Before": {},
      "After": {},
      "Differences": {},
      "Decision": "Reverted"
    },
    "ComplianceResults": [],
    "Errors": []
  }
}
```

El contrato no se agrega como placeholder vacío a Health Check. Se incorpora
solamente cuando esta feature tenga una implementación real.

## 10. Ciclo de una acción

Cada acción atraviesa estados explícitos:

```text
Proposed
Approved
Applied
Validated
Kept
Reverted
Skipped
Failed
```

Antes de aplicar:

1. Verificar que la línea base corresponde al mismo equipo.
2. Verificar que la línea base no haya expirado.
3. Confirmar que la política autoriza la acción.
4. Evaluar permisos administrativos.
5. Capturar el estado anterior.
6. Persistir el plan de reversión.
7. Solicitar confirmación explícita.

Después de aplicar:

1. Registrar resultado y duración.
2. Repetir las métricas comparables.
3. Registrar efectos secundarios observables.
4. Solicitar la decisión `Keep` o `Revert` cuando corresponda.
5. Generar JSON, HTML y log independientes.

## 11. Medición antes y después

La comparación utiliza la misma duración, intervalo y categorías disponibles en
la línea base. Debe registrar si la carga de trabajo cambió entre mediciones.

Posibles resultados:

```text
Improved
Unchanged
Regressed
Inconclusive
```

Una variación no demuestra causalidad cuando cambiaron aplicaciones, carga,
energía, temperatura o actividad del usuario. En ese caso el resultado es
`Inconclusive`.

Para cambios puramente visuales o de compliance puede no existir una métrica de
rendimiento válida. El éxito se evalúa contra la preferencia del usuario o la
política, no contra el health score.

## 12. Seguridad y auditoría

- Usar semántica equivalente a `SupportsShouldProcess` y permitir `-WhatIf`.
- Mantener una lista explícita de acciones soportadas.
- Rechazar acciones desconocidas aunque aparezcan en la política.
- Registrar estado anterior y posterior.
- Redactar usuarios, rutas y mensajes según la política de Health Check.
- No almacenar contenido de archivos eliminados.
- No registrar secretos dentro de argumentos o valores del registro.
- No considerar la creación de un punto de restauración como garantía de reversión.
- Detener una sesión cuando no pueda persistirse su bitácora.

Las eliminaciones de archivos son irreversibles dentro de la aplicación. Una vista
previa o un punto de restauración no sustituyen un respaldo.

## 13. Roadmap tentativo

### Fase A: observación

- `Preview` de limpieza.
- `Audit` de compliance.
- Lectura de Storage Sense, inicio, energía y configuraciones de UX.
- Contrato JSON y HTML sin acciones.

### Fase B: experimentos reversibles

- Experimentos de animaciones y transparencias.
- Captura de estado anterior.
- Validación antes y después.
- Reversión y decisión de conservar.

### Fase C: aplicación administrada

- Limpieza autorizada.
- Configuración de Storage Sense.
- Aplicación de políticas permitidas.
- Firma, versionado y auditoría de políticas.

## 14. Criterios para aceptar la feature

La feature solamente debe pasar de `Candidate` a planificación cuando exista:

- Un caso de uso concreto y usuarios autorizados identificados.
- Una lista limitada de acciones iniciales.
- Una política versionada de prueba.
- Una estrategia de reversión por acción reversible.
- Confirmación separada para acciones irreversibles.
- Fixtures y pruebas Pester para Preview, Apply, fallo y rollback.
- Evidencia de que la bitácora persiste aun cuando una acción falle.
- Separación comprobada entre health score y compliance.

Hasta entonces, este documento funciona como registro de la oportunidad y sus
límites, no como compromiso de implementación.
