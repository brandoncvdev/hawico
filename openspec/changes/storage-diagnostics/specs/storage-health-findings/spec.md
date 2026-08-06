# Storage Health Findings Specification

## Purpose

Nivel 3 SMART-based rules that turn Nivel 2 storage-inventory data into `STO-*` findings and `REC-STO-*` recommendations, rendered through the existing generic findings/recommendations tables. New IDs continue after the existing `STO-005`.

## Requirements

### Requirement: Active-Failure Critical Signals

The system MUST raise a Critical finding for each active/imminent-failure signal below, using conservative, `config.json`-configurable defaults:

| Id | Condition | Config key (default) |
|----|-----------|----------------------|
| STO-006 | SMART overall-health self-assessment = FAILED | n/a (boolean) |
| STO-007 | Pending-sector count ≥ `StoragePendingSectorCriticalCount` | 1 |
| STO-008 | NVMe available spare < `StorageAvailableSpareCriticalPercent`, or the drive's own reported spare threshold when present | 10 |

#### Scenario: SMART self-assessment failed
- GIVEN a disk's SMART overall-health self-assessment is FAILED
- WHEN `Get-HealthFinding` runs
- THEN a Critical STO-006 finding is added with `RecommendationId = REC-STO-001`

#### Scenario: Pending sectors present
- GIVEN a disk reports 1 pending sector at the default threshold
- WHEN `Get-HealthFinding` runs
- THEN a Critical STO-007 finding is added

### Requirement: Gradual-Wear Medium/High Signals

The system MUST raise Medium or High findings — never Critical — for wear trends without an active-failure signal, using two-tier (warning/high) thresholds where applicable:

| Id | Condition | Config keys (defaults) | Severity |
|----|-----------|--------------------------|----------|
| STO-009 | Reallocated-sector count ≥ `StorageReallocatedSectorWarningCount` | 1 | Medium |
| STO-010 | `WearPercentUsed` ≥ `StorageWearWarningPercent` / ≥ `StorageWearHighPercent` | 70 / 90 | Medium / High |
| STO-011 | Temperature ≥ `StorageTemperatureWarningC` / ≥ `StorageTemperatureHighC` | 55 / 65 | Medium / High |
| STO-012 | HDD `PowerOnHours` ≥ `StorageHddServiceLifeWarningHours` (~3y continuous use) | 26280 | Medium |

#### Scenario: Wear crosses warning tier only
- GIVEN `WearPercentUsed = 75`
- WHEN `Get-HealthFinding` runs
- THEN a Medium STO-010 finding is added, not High

#### Scenario: Wear crosses high tier
- GIVEN `WearPercentUsed = 92`
- WHEN `Get-HealthFinding` runs
- THEN a High STO-010 finding is added

#### Scenario: Reallocated sectors present but no pending sectors
- GIVEN reallocated-sector count = 3 and pending-sector count = 0
- WHEN `Get-HealthFinding` runs
- THEN only a Medium STO-009 finding is added, no Critical finding

### Requirement: Threshold Validation

Loaded storage thresholds MUST be validated the same way existing `HealthCheck` thresholds are (e.g. `StorageWearWarningPercent < StorageWearHighPercent`, `StorageTemperatureWarningC < StorageTemperatureHighC`). The system MUST throw a descriptive error on misconfiguration rather than silently misclassify severity.

#### Scenario: Misordered thresholds
- GIVEN `StorageWearWarningPercent = 95` and `StorageWearHighPercent = 70`
- WHEN configuration loads
- THEN the system throws a descriptive configuration error before any finding is evaluated

### Requirement: Recommendation Catalog Extension

The system MUST add `REC-STO-005` (monitor reallocated sectors, back up data), `REC-STO-006` (plan storage replacement), and `REC-STO-007` (improve thermal conditions) to the existing `Get-HealthRecommendation` catalog. STO-006/007/008 MUST map to the existing `REC-STO-001` where its corrective action already applies.

#### Scenario: New finding maps to new recommendation
- GIVEN an STO-010 (wear) finding exists
- WHEN `Get-HealthRecommendation` runs
- THEN a REC-STO-006 recommendation listing STO-010 in `FindingIds` is returned
