# Local administration (import, identity, review)

Implements the local-administration scope of `docs/04-Architecture.md` and
`docs/13-Administration.md`: importing `*-record.json` files into a durable
asset store, resolving identity across visits, and triaging what needs human
review — the first-time assignment of the permanent `AssetId` (ADR-005 in
`docs/17-Architecture-Decisions.md`: the collector never assigns it).

## Why no SQLite yet

`docs/04-Architecture.md` says explicitly: *"La fuente de verdad lógica será
el conjunto de registros estructurados y su historial. En la primera etapa
pueden almacenarse como JSON. En fases posteriores podrán migrarse a
SQLite... sin cambiar el contrato de los datos."* This phase stores
everything as plain JSON files, like the rest of the project. No database
dependency is introduced. A future migration to SQLite should be able to
read the same `AssetId`, `SerialNumber`/`SystemUuid`, `ManualFields`,
`CollectionHistory` and `ReviewHistory` shapes documented below without
changing what they mean.

## Storage layout

```text
Administracion/
├── assets-index.json
└── Assets/
    └── AST-0001.json
```

`Modules/InventoryAdministration.ps1`'s `Get-InventoryAssetStorePath -BasePath`
builds both paths from a single root (`<BasePath>/Administracion/Assets` and
`<BasePath>/Administracion/assets-index.json`). `config.json`'s
`Administration.BasePath` (default `"."`) is that root — **not** the
`Administracion` folder itself, since the helper always appends
`Administracion\` on its own.

### `assets-index.json`

```json
{
  "NextSequence": 3,
  "Entries": [
    { "Type": "SerialNumber", "Value": "ABC12345", "AssetId": "AST-0001" },
    { "Type": "SystemUuid", "Value": "4C4C4544-...", "AssetId": "AST-0002" }
  ]
}
```

Lookup always matches on the **combination** of `Type` and `Value`, never on
`Value` alone — a `SerialNumber` and a `SystemUuid` must never be treated as
interchangeable even if their text happens to coincide
(`docs/10-Asset-Identity.md`). `AssetId` follows the plan's example format,
`AST-{0:D4}`, assigned sequentially from `NextSequence` the first time an
asset with a given identity is seen — this is the only place in the pipeline
that mints an `AssetId`; the collector never does (ADR-005).

### `Assets/<AssetId>.json`

```json
{
  "AssetId": "AST-0001",
  "SerialNumber": "ABC12345",
  "SystemUuid": "4C4C4544-...",
  "Manufacturer": "Dell Inc.",
  "Model": "OptiPlex 7090",
  "Status": "New",
  "CreatedAt": "2026-08-03T12:30:00-06:00",
  "UpdatedAt": "2026-08-03T12:30:00-06:00",
  "ManualFields": [ /* FieldValue objects, doc06-Data-Model.md */ ],
  "CollectionHistory": [
    { "CollectionId": "COL-...", "CollectedAt": "...", "SessionId": "SES-..." }
  ],
  "ReviewHistory": [
    {
      "Key": "assignment.user.fullName",
      "PreviousValue": "Juan Pérez",
      "NewValue": "María Fernanda López Hernández",
      "CapturedAt": "2026-08-05T09:10:00-06:00",
      "ReviewedBy": "Administrador TI",
      "Reason": "Nombre completo verificado con RRHH"
    }
  ]
}
```

`CollectionHistory` grows by one entry every time a record for this asset is
imported (`docs/13-Administration.md`: "Comparar capturas históricas").
`ReviewHistory` grows by one entry every time `Add-InventoryAssetManualReview`
applies a correction — the previous value is never discarded
(`docs/08-Manual-Capture.md`), kept as a flat audit list on the asset rather
than nested inside each `FieldValue`, so `ManualFields` entries keep the
plain `doc06` `FieldValue` shape used everywhere else in this codebase.

## Import trays

`Import-InventoryAdministrationSession -RecordsPath -AdministrationBasePath`
reads every `*-record.json` under `RecordsPath` (via the same
`Get-InventoryConsolidatedRecords` the Excel engine uses) and files each
record into one of five trays, matching the subset of
`docs/13-Administration.md`'s suggested trays this phase implements:

| Tray | When |
| --- | --- |
| `NuevosEquipos` | Strong identity (`Asset.PreferredIdentifier` present), no existing match — a new `AssetId` is minted. |
| `EquiposActualizados` | Strong identity, matches an existing `AssetId` — `CollectionHistory` gets a new entry; any manual field with no prior value is added directly. |
| `PosiblesDuplicados` | `Asset.PreferredIdentifier` is `null` (`Status = NeedsReview`) — no `AssetId` is created or matched; weak evidence (hostname/IP/MAC) is never used to dedupe. |
| `Conflictos` | A manual field key already has a *different* value on the asset — the existing value is never silently overwritten; it waits for `Add-InventoryAssetManualReview`. |
| `ErroresRecoleccion` | `record.Errors` is non-empty — independent of the other four; a record can land here **and** in `NuevosEquipos`/`EquiposActualizados`/`PosiblesDuplicados` at the same time. |

`SkippedFiles` (from `Get-InventoryConsolidatedRecords`) is passed through
unchanged for files that failed to parse as JSON at all.

The same identical value re-submitted for an already-captured key is treated
as a no-op (not a conflict, nothing changes) — only a *differing* value
triggers review. The asset index is written once at the end of the import
batch, not once per record.

### Known limitation: identity type must stay stable across visits

Matching requires the **same** `PreferredIdentifier.Type` (`SerialNumber` or
`SystemUuid`) across visits. If a machine's serial number reads successfully
on one visit but fails on another (falling back to `SystemUuid`, or vice
versa), the two captures will not automatically match and a second asset can
be created. `docs/10-Asset-Identity.md` explicitly asks for this: *"cuando
existe conflicto en serie o UUID, el sistema no debe fusionarlas
automáticamente. Debe generar una tarea de revisión"* — so this is the
intended, cautious behavior, not a bug: it shows up as a second
`NuevosEquipos` entry instead of a silent, possibly-wrong auto-merge.

## Manual review

`Add-InventoryAssetManualReview -AdministrationBasePath -AssetId -Key
-NewValue -ReviewedBy [-Reason]` is how a human resolves a `Conflictos` entry
or corrects any manual field. It replaces the field's current value with one
carrying `Source = 'ManualReview'` and `Confidence = 'Confirmed'`, records
the previous value (or `null` if the key had none) in `ReviewHistory`, and
returns the applied `FieldValue`.

## Configuration

```json
"Administration": {
  "RecordsPath": ".\\Output",
  "BasePath": "."
}
```

`Import-InventoryRecords.ps1` reads this block and calls
`Import-InventoryAdministrationSession`, printing the count for each tray.
