# API Contract

Defines the contract between the collector and the future inventory platform.

## CollectionRecord 1.0

The hardware collector preserves the existing `SchemaVersion 2.0` evidence file
and creates a second import-ready artifact named `*-record.json`.

```text
CollectionRecord
├── ContractVersion: 1.0
├── CollectionId
├── Asset
│   ├── AssetId
│   ├── SerialNumber
│   ├── SystemUuid
│   ├── Manufacturer
│   ├── Model
│   ├── ComputerName
│   ├── PreferredIdentifier
│   └── Status
├── SessionId
├── CollectedAt
├── CollectorVersion
├── ComputerName
├── TechnicalData
├── ManualFields
├── Assessments
└── Errors
```

`TechnicalData` contains the complete legacy evidence object. This additive
envelope avoids breaking the current HTML renderer or consumers of the original
JSON while the importer and consolidation workflow are introduced.

`SessionId` is a plain scalar reference to a `CollectionSession` (see below), not
an embedded object. The record itself never carries `OrganizationId`, `ProfileId`
or `Technician` — that context belongs to the session, not to each individual
capture, following the `sessionId` reference shape in the plan's data model.

`Assessments` is always an array (`[]` when empty), never an object, so future
evaluation entries (e.g. the RAM upgrade assessment) can be appended without a
contract-breaking shape change.

## Identity rules

The collector does not assign the permanent `AssetId`; the administration layer
owns that decision.

1. A valid normalized BIOS serial number is the preferred candidate.
2. A valid system UUID is the fallback candidate.
3. Manufacturer placeholders and all-zero/all-`F` identifiers are rejected.
4. Hostname, IP address, MAC address, and current user are weak evidence only and
   never become `PreferredIdentifier` by themselves.
5. Missing strong identity produces `Asset.Status = NeedsReview`.

## CollectionId format

`CollectionId` follows `COL-{yyyyMMdd-HHmmssfff}-{suffix}`, where `{suffix}`
carries hardware traceability instead of an opaque random value:

- If `Asset.PreferredIdentifier` was resolved, the suffix is the first 8
  characters of its (already normalized, uppercase) value.
- If the asset needs review (no `PreferredIdentifier`), the suffix is the fixed
  prefix `UNK` followed by 5 random uppercase hexadecimal characters.

## CollectorVersion

`CollectorVersion` is read from `manifest.json` at the repository root (key
`CollectorVersion`) via the shared `Get-CollectorVersion` helper in
`Modules/Common.ps1`, instead of a literal duplicated across files. Both
`Collector_Hardware_Inventory.ps1` and the default parameter value of
`New-InventoryCollectionRecord` resolve the version through that same helper.

## CollectionSession

`CollectionSession` is a separate entity built once per launcher run by
`New-InventoryCollectionSession` (`Modules/New-InventoryCollectionSession.ps1`),
**not** embedded inside `CollectionRecord`:

```text
CollectionSession
├── SessionId
├── OrganizationId
├── ProfileId
├── Technician
├── StartedAt
├── EndedAt
├── EquipmentCount
├── PendingCount
└── Status: Active | Unassigned
```

- `Start-Inventory.ps1` reads `config.json`'s `CollectionSession` block once at
  startup, builds a single `CollectionSession`, and forwards only its resolved
  `SessionId` (the scalar) to both `-Mode Full` and `-Mode Quick` via
  `$collectionArguments`. `OrganizationId`, `ProfileId` and `Technician` are
  consumed to build the session and never reach the collector or the record.
- If the resulting `SessionId` is null, empty, or the literal `SES-UNASSIGNED`
  (the `config.json` default), `Status` is `Unassigned` and the launcher emits a
  `Write-Warning` telling the technician the capture must be reviewed before
  institutional consolidation. Any other `SessionId` yields `Status = Active`.
- `Collector_Hardware_Inventory.ps1` itself only accepts `-SessionId`
  (defaulting to `SES-UNASSIGNED` for backward-compatible direct execution); it
  no longer accepts `-OrganizationId`, `-ProfileId` or `-Technician`.
