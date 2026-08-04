# Organization packages

Implements the MVP scope of `docs/07-Catalog-System.md` and
`docs/14-Configuration.md`: a real, versioned, per-organization configuration
package replaces the flat `config.json.ManualFields` list (the Phase 1
placeholder) as the *preferred* source for which manual fields are asked
during collection — while keeping that flat list as a backward-compatible
fallback.

## Scope of this phase

- Organization definitions, profiles, the organization-unit catalog and
  custom-field definitions are **loaded** and available via
  `Modules/InventoryOrganizationPackage.ps1`.
- The **active profile's `manualFields`** are consumed by
  `Read-InventoryManualCapture` to decide which fields to ask at all.
- The **organization-unit catalog** is wired into capture: when one is
  configured, `assignment.organizationUnitId` is answered by picking from a
  numbered menu instead of typing free text, and `assignment.departmentUnitId`
  cascades from that pick — offering only the selected unit's direct children
  (see "Organization unit selection" below). Every other manual field, and
  `assignment.organizationUnitId` itself when no catalog is configured, still
  prompts free text.
- An optional **`catalogs/departments.json`**, loaded by
  `Get-InventoryDepartmentUnitCatalog`, covers institutions whose real
  Dirección/Departamento data has no reliable parent-child relationship: a
  second, independent flat catalog instead of a forced cascade (see
  "Flat/independent mode" below).
- **Custom-field definitions** (`custom-fields.json`) are loaded but not yet
  consumed anywhere — there is no per-field validation, type, or label
  rendering driven by them yet. That remains Fase 5 (interfaz
  administrativa) work.
- `rules.json` and `excel-mapping.json` (also mentioned in `docs/14-Configuration.md`)
  are **not implemented** — nothing in the codebase would consume them yet
  (evaluation rules don't exist until `docs/09-Memory-Assessment.md` is
  implemented, and the Excel engine's column mapping is still hardcoded in
  `Modules/New-InventoryConsolidatedWorkbook.ps1`).

## Package layout

```text
Config/Organizations/<organizationId>/
├── organization.json
├── profiles/
│   └── <profileId>.json
├── catalogs/
│   ├── organization-units.json
│   └── departments.json          # optional — flat/independent mode only
└── custom-fields.json
```

A real, usable example package ships at
`Config/Organizations/org-example/`, with a `basic-inventory` profile
carrying the exact same 6 `manualFields` `config.json` already asks for
today — the system is immediately usable through the package, not just
scaffolding.

### `organization.json`

```json
{
  "schemaVersion": "1.0",
  "packageVersion": "0.1.0",
  "organizationId": "org-example",
  "name": "Organización de ejemplo",
  "defaultProfileId": "basic-inventory",
  "organizationUnitLabels": ["Sede", "Dirección", "Departamento", "Área"],
  "updatedAt": "2026-08-03T12:40:00-06:00"
}
```

### `profiles/<profileId>.json`

```json
{
  "profileId": "basic-inventory",
  "name": "Inventario básico",
  "manualFields": ["assignment.user.fullName", "..."],
  "exports": {"json": true, "html": true, "xlsx": true, "log": true},
  "interactionMode": "compact"
}
```

### `catalogs/organization-units.json`

```json
{
  "units": [
    {"id": "site-center", "name": "Sede Centro", "type": "site", "parentId": null, "sortOrder": 10}
  ]
}
```

### `custom-fields.json`

```json
{
  "fields": [
    {"key": "assignment.user.fullName", "label": "Nombre completo del usuario", "type": "text", "required": false, "allowSkip": true, "askDuringCollection": true, "reusePreviousValue": true}
  ]
}
```

## How the active profile is resolved

Resolution happens in the **launcher** (`Start-Inventory.ps1`), not the
collector — this is where the plan's separation of "recolector ligero /
administración central" (`docs/04-Architecture.md`) keeps living:

1. `Start-Inventory.ps1` builds the `CollectionSession` from
   `config.json.CollectionSession` (`OrganizationId`, `ProfileId`) — unchanged
   from earlier phases, no new config key duplicates this.

   Before that, if `CollectionSession.OrganizationId` is null/empty,
   `Get-InventoryAutoDetectedOrganizationId -BasePath <resolved
   OrganizationPackages.BasePath>` looks for exactly one real organization
   folder under `Config/Organizations/` (`org-example` is never a candidate —
   it's the reference format, not a real institution) and uses it
   automatically. This exists so dropping a real organization package onto a
   machine is enough on its own — no `config.json` edit required — for the
   common single-institution case. Zero or more than one real candidate
   folder leaves `OrganizationId` unresolved rather than guessing; an
   explicit `OrganizationId` already set in `config.json` always wins over
   auto-detection.
2. It calls `Get-InventoryProfileManualFields -BasePath <resolved
   OrganizationPackages.BasePath> -OrganizationId $collectionSession.OrganizationId
   -ProfileId $collectionSession.ProfileId -FallbackFields @($config.ManualFields)`.
3. The result becomes `$collectionArguments.ManualFieldKeys`, forwarded to
   both `-Mode Full` and `-Mode Quick`.

`Get-InventoryProfileManualFields` falls back to `$FallbackFields`
(`config.json.ManualFields`, unchanged default behavior) whenever:

- `OrganizationId` is null or empty (the `config.json` default — nothing
  changes for an operator who never touches `CollectionSession.OrganizationId`), or
- the organization package doesn't exist at `<BasePath>/<OrganizationId>/`, or
- the profile doesn't exist at `<BasePath>/<OrganizationId>/profiles/<ProfileId>.json`.

None of the loader functions (`Get-InventoryOrganizationDefinition`,
`Get-InventoryProfileDefinition`, `Get-InventoryOrganizationUnitCatalog`,
`Get-InventoryCustomFieldDefinitions`) throw when a package or file is
missing — an unconfigured organization is the normal, expected state, not an
error condition.

`Collector_Hardware_Inventory.ps1` accepts the already-resolved
`-ManualFieldKeys` from the launcher. Running the collector directly,
without the launcher, still works exactly as before: with no
`-ManualFieldKeys` supplied, it falls back to reading `config.json.ManualFields`
itself, unchanged.

## Organization unit selection

`Start-Inventory.ps1` also resolves `$organizationUnits` via
`Get-InventoryOrganizationUnitCatalog -BasePath ... -OrganizationId
$collectionSession.OrganizationId` and forwards it as
`$collectionArguments.OrganizationUnits`. `Collector_Hardware_Inventory.ps1`
passes it straight through to `Read-InventoryManualCapture -OrganizationUnits`.

Inside `Modules/New-InventoryManualCapture.ps1`:

- `ConvertTo-InventoryOrganizationUnitMenu -Units` (pure) flattens the
  catalog's parent/child `units` array into an ordered `{Id; Name; Depth}`
  list — roots first (by `sortOrder`), each one immediately followed by its
  own children (by `sortOrder`, recursively), matching the nested example
  in `docs/07-Catalog-System.md`. It guards against a malformed catalog
  (duplicate `id`, a `parentId` chain that loops back on itself) with a
  visited-id set: a repeated `id` cuts that branch short instead of hanging
  the collector.
- `Read-InventoryOrganizationUnitSelection -Units -Prompter` shows that menu
  with `Write-Host` (indented by `Depth`), asks for a number through the
  same `-Prompter` scriptblock `Read-InventoryManualCapture` already uses,
  and re-prompts on anything that isn't a valid option number until the
  technician picks one or presses Enter to skip. With no units at all it
  returns `$null` immediately without printing anything. On a valid pick it
  returns `{Id; Name}` (not a bare string) — the `Id` is what the next
  cascade step needs to filter children; the `Name` is what gets stored.
- `Get-InventoryOrganizationUnitChildren -Units -ParentId` (pure) filters the
  full catalog down to the direct children of `ParentId`, ordered by
  `sortOrder`. Each returned clone has its `parentId` reset to `$null`:
  `ConvertTo-InventoryOrganizationUnitMenu` only recognizes a `$null`
  `parentId` as a root, and it has no notion that `ParentId` itself was
  excluded from this filtered subset — without the reset, every child would
  still point at its real (now-absent) parent, the DFS would find zero
  roots, and the department menu would come back empty and silently skip
  instead of listing anything. The original catalog objects are never
  mutated.
- `Read-InventoryManualCapture` calls `Read-InventoryOrganizationUnitSelection`
  for the `assignment.organizationUnitId` key (only when `-OrganizationUnits`
  was actually supplied and non-empty), and it remembers the selected unit's
  `Id` for the rest of the walk.

### Cascading `assignment.departmentUnitId`

`assignment.departmentUnitId` must come **after** `assignment.organizationUnitId`
in `-FieldKeys` (and therefore in `config.json.ManualFields` / a profile's
`manualFields`) — it never runs its own independent catalog pick:

1. If no direction was selected just before it (skipped with Enter, or no
   catalog was supplied at all), `assignment.departmentUnitId` is skipped
   too — no prompt, no free-text fallback.
2. Otherwise, `Get-InventoryOrganizationUnitChildren` filters the full
   catalog to the selected direction's direct children.
3. If there are none, `assignment.departmentUnitId` is skipped the same
   way — a direction with no children has nothing meaningful to ask.
4. If there are children, `Read-InventoryOrganizationUnitSelection` shows a
   menu built **only** from that filtered list (never the whole catalog
   again), and the technician's pick becomes the field's value.

In every skip case the technician is never prompted at all for this field —
it never degrades to typing a department by hand, since a hand-typed
department wouldn't be tied to any direction.

The stored `FieldValue.Value` for both fields is the selected unit's
**`name`** (e.g. `"Recursos Humanos"`), not its catalog `id` (e.g.
`"dept-hr"`) — `FieldValue` (`docs/06-Data-Model.md`) only has one text
`value`, and the Excel `DIRECCION` / `DEPARTAMENTO` columns
(`docs/INSTITUTIONAL_EXCEL_MAPPING.md`) need the readable name. This is
exactly what a technician would have typed by hand before, just without
typos now.

### Flat/independent mode: when Dirección and Departamento have no real hierarchy

The cascade above assumes a genuine parent-child relationship: every
Departamento is a real child of some Dirección in `organization-units.json`.
Some institutions' actual data doesn't have that — `Config/Organizations/institucion-principal/`
ships with 6 Direcciones and 48 Departamentos as **two separate, unrelated
flat lists** (every unit has `parentId: null` in both catalogs). The row
counts don't line up and there is no reliable way to derive which
Departamento belongs to which Dirección without inventing data, so this
package uses a second mode instead of forcing a fake cascade:

- `catalogs/departments.json` (same `{units: [...]}` shape as
  `organization-units.json`, loaded by `Get-InventoryDepartmentUnitCatalog
  -BasePath -OrganizationId` in `Modules/InventoryOrganizationPackage.ps1`)
  is a **second, independent** catalog — not a child list of anything.
- `Start-Inventory.ps1` loads it the same way it loads `$organizationUnits`,
  and forwards it as `$collectionArguments.DepartmentUnits`.
  `Collector_Hardware_Inventory.ps1` resolves it through the same generic
  `Resolve-InventoryOrganizationUnits -PassedUnits` used for
  `-OrganizationUnits` (it is a plain array-shape resolver, not specific to
  any one catalog) and forwards it to `Read-InventoryManualCapture
  -DepartmentUnits`.
- Inside `Read-InventoryManualCapture`: whenever `-DepartmentUnits` is
  supplied and non-empty, `assignment.departmentUnitId` is answered by
  picking from that **whole, independent catalog** — the same
  `Read-InventoryOrganizationUnitSelection` menu mechanism as
  `assignment.organizationUnitId` itself, never filtered by whatever
  Dirección was just selected. This takes priority over the cascade even if
  `-OrganizationUnits` also happens to carry a real hierarchy, since
  supplying `-DepartmentUnits` is the explicit signal that this
  organization's Departamento is not actually a child of Dirección.
- When `-DepartmentUnits` is **not** supplied (empty, or the organization
  has no `departments.json`), behavior is unchanged from the cascade
  described above — this keeps `org-example` and any future organization
  with a real hierarchy working exactly as before.

In short: an organization ships **either** a nested `organization-units.json`
(cascade) **or** a flat `organization-units.json` + `departments.json` pair
(two independent picks) depending on what its real data supports — never
both modes active for the same `assignment.departmentUnitId` field at once,
since `-DepartmentUnits` always wins when present.

## Reusable visit context (doc07 "Reutilización durante visita")

> El técnico selecciona un contexto. Los valores se heredan hasta que se
> cambien, evitando capturar el mismo departamento en cada equipo.

Before this, every single collection re-asked Dirección, Departamento and
free text for every manual field — including Técnico, which was never asked
interactively at all (only read once from `config.json.CollectionSession.Technician`).
A technician working through 10 machines in the same office had to answer
the same catalog picks 10 times.

`Start-Inventory.ps1` now resolves a **visit context** once, before the main
menu loop, via a local `Read-InventoryVisitContext` function (dot-sources
`Modules\New-InventoryManualCapture.ps1` for
`Read-InventoryOrganizationUnitSelection` / `Get-InventoryOrganizationUnitChildren`):

1. **Técnico**: `Read-Host "Técnico responsable de esta visita (Enter para
   mantener '<current>')"`. Enter keeps whatever `$collectionSession.Technician`
   (or the previous visit-context answer) already was; typing a name
   overrides it **for this launcher session only** — never written back to
   `config.json`.
2. **Dirección**: if `$organizationUnits` has data, picked once via
   `Read-InventoryOrganizationUnitSelection`.
3. **Departamento**: resolved once, using the exact same priority
   `Read-InventoryManualCapture` itself uses — the flat/independent
   `$departmentUnits` catalog first (offered regardless of whether Dirección
   was picked), the cascade (`Get-InventoryOrganizationUnitChildren` off the
   picked Dirección) only when no independent catalog is configured.

The result is stored as `$visitTechnician` (a plain string, forwarded as
`$collectionArguments.Technician`) and `$visitPresetValues` (a hashtable —
`assignment.organizationUnitId` / `assignment.departmentUnitId` → the
selected unit's `Name`, **only for the keys that were actually resolved**;
forwarded as `$collectionArguments.PresetManualFieldValues`).

`Read-InventoryManualCapture` gained a matching generic `-PresetValues`
parameter (`Modules/New-InventoryManualCapture.ps1`): for any `-FieldKeys`
entry present in `-PresetValues`, that value is used directly — no menu, no
`Read-Host`, checked **before** the catalog/cascade/free-text logic already
described above. `Collector_Hardware_Inventory.ps1` forwards
`-PresetManualFieldValues` straight through as `-PresetValues`.

Every other manual field (`assignment.user.fullName`, `assignment.locationId`,
`asset.assetTag`, `collection.observations`, …) is **never** added to
`$visitPresetValues` — those are per-machine/per-user data, not visit
context, and are still asked on every single collection.

If the technician skips Dirección with Enter, `assignment.organizationUnitId`
is left out of `$visitPresetValues` entirely, and both
`assignment.organizationUnitId`/`assignment.departmentUnitId` fall through to
being asked normally on every machine (the existing per-machine catalog/cascade
behavior, unchanged). The same happens if Dirección has children but the
technician skips Departamento specifically: `Read-InventoryVisitContext`
un-presets Dirección too in that case, rather than presetting a Dirección
whose real `Id` (needed by the per-machine cascade to look up children) would
otherwise be lost — a preset only ever carries the selected unit's `Name`.

The visit context can be changed at any point without restarting the
launcher: menu option **"9. Cambiar contexto de esta visita
(Dirección/Departamento/Técnico)"** re-runs `Read-InventoryVisitContext` and
updates `$collectionArguments` in place, so the next collection (options 1/2)
picks up the new values immediately.

## Configuration

```json
"OrganizationPackages": {
  "BasePath": ".\\Config\\Organizations"
}
```
