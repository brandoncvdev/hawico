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
- Only the **active profile's `manualFields`** are actually consumed today
  (by `Read-InventoryManualCapture`, unchanged — it still prompts free text).
- The organization-unit catalog and custom-field definitions are loaded but
  **not yet wired into any interactive selector** — `Read-InventoryManualCapture`
  keeps asking free text for every field, including
  `assignment.organizationUnitId`. Turning the catalog into a pick-list during
  capture is Fase 5 (interfaz administrativa) work.
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
│   └── organization-units.json
└── custom-fields.json
```

A real, usable example package ships at
`Config/Organizations/org-example/`, with a `basic-inventory` profile
carrying the exact same 5 `manualFields` `config.json` already asks for
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

## Configuration

```json
"OrganizationPackages": {
  "BasePath": ".\\Config\\Organizations"
}
```
