function Get-InventoryAssetStorePath {
    param([Parameter(Mandatory)][string]$BasePath)

    $administrationRoot = Join-Path $BasePath 'Administracion'

    return [ordered]@{
        AssetsDirectory = Join-Path $administrationRoot 'Assets'
        IndexPath = Join-Path $administrationRoot 'assets-index.json'
    }
}

function Get-InventoryAssetIndex {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads the existing asset index without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$IndexPath
    )

    if (-not (Test-Path -LiteralPath $IndexPath)) {
        return [ordered]@{
            NextSequence = 1
            Entries = @()
        }
    }

    $parsed = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json

    $nextSequence = if ($null -ne $parsed.NextSequence) { [int]$parsed.NextSequence } else { 1 }
    # The whole pipeline is wrapped in @() (not just its input) so a saved
    # index with exactly one entry does not collapse to a bare object.
    $entries = @(@($parsed.Entries) | Where-Object { $null -ne $_ })

    return [ordered]@{
        NextSequence = $nextSequence
        Entries = $entries
    }
}

function Save-InventoryAssetIndex {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Persisting the asset index to disk is the purpose of this function.'
    )]
    param(
        [Parameter(Mandatory)][string]$IndexPath,
        [Parameter(Mandatory)][object]$Index
    )

    $indexDirectory = Split-Path -Parent $IndexPath
    if (-not [string]::IsNullOrWhiteSpace($indexDirectory)) {
        New-Item -ItemType Directory -Force -Path $indexDirectory | Out-Null
    }

    $Index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
}

function New-InventoryAssetId {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory asset id and index without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][object]$Index
    )

    $sequence = [int]$Index.NextSequence
    $assetId = 'AST-{0:D4}' -f $sequence

    # Does not mutate the caller's $Index: builds a brand-new ordered
    # dictionary and copies Entries into a fresh array instead of writing
    # back into $Index.NextSequence / $Index.Entries.
    $updatedIndex = [ordered]@{
        NextSequence = $sequence + 1
        Entries = @($Index.Entries)
    }

    return [ordered]@{
        AssetId = $assetId
        UpdatedIndex = $updatedIndex
    }
}

function Find-InventoryAssetByIdentity {
    param(
        [Parameter(Mandatory)][object]$Index,
        [AllowNull()][object]$PreferredIdentifier
    )

    # Without a strong identifier there is nothing safe to match against —
    # never dedupe by hostname, IP, MAC or any other weak evidence (doc
    # 10-Asset-Identity.md).
    if ($null -eq $PreferredIdentifier) {
        return $null
    }

    $type = Get-SafeString $PreferredIdentifier.Type
    $value = Get-SafeString $PreferredIdentifier.Value
    if ($null -eq $type -or $null -eq $value) {
        return $null
    }

    # Type AND Value must both match: a SerialNumber and a SystemUuid must
    # never be treated as interchangeable even if their text happens to
    # coincide.
    $match = @($Index.Entries) | Where-Object {
        $null -ne $_ -and $_.Type -eq $type -and $_.Value -eq $value
    } | Select-Object -First 1

    if ($null -eq $match) { return $null }
    return $match.AssetId
}

function Import-InventoryAdministrationSession {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Importing collection records into the administration store is this function''s purpose.'
    )]
    param(
        [Parameter(Mandatory)][string]$RecordsPath,
        [Parameter(Mandatory)][string]$AdministrationBasePath
    )

    $store = Get-InventoryAssetStorePath -BasePath $AdministrationBasePath
    New-Item -ItemType Directory -Force -Path $store.AssetsDirectory | Out-Null

    $index = Get-InventoryAssetIndex -IndexPath $store.IndexPath

    $collected = Get-InventoryConsolidatedRecords -RecordsPath $RecordsPath
    $records = @($collected.Records)
    $skippedFiles = @($collected.Skipped)

    $nuevosEquipos = @()
    $equiposActualizados = @()
    $posiblesDuplicados = @()
    $conflictos = @()
    $erroresRecoleccion = @()

    foreach ($record in $records) {
        if ($null -eq $record) { continue }

        $now = [datetimeoffset]::Now

        if (@($record.Errors).Count -gt 0) {
            $erroresRecoleccion += [PSCustomObject][ordered]@{
                CollectionId = $record.CollectionId
                ComputerName = $record.ComputerName
                Errors = @($record.Errors)
            }
        }

        $preferredIdentifier = $record.Asset.PreferredIdentifier

        # No strong identity: this cannot be safely matched or merged
        # automatically (doc10-Asset-Identity.md). It goes to manual
        # triage instead of creating or updating any asset.
        if ($null -eq $preferredIdentifier) {
            $posiblesDuplicados += [PSCustomObject][ordered]@{
                CollectionId = $record.CollectionId
                ComputerName = $record.ComputerName
                SessionId = $record.SessionId
            }
            continue
        }

        $historyEntry = [PSCustomObject][ordered]@{
            CollectionId = $record.CollectionId
            CollectedAt = $record.CollectedAt
            SessionId = $record.SessionId
        }

        $existingAssetId = Find-InventoryAssetByIdentity -Index $index -PreferredIdentifier $preferredIdentifier

        if ($null -ne $existingAssetId) {
            $assetPath = Join-Path $store.AssetsDirectory "$existingAssetId.json"
            $asset = Get-Content -LiteralPath $assetPath -Raw | ConvertFrom-Json

            $assetManualFields = @(@($asset.ManualFields) | Where-Object { $null -ne $_ })

            foreach ($newField in @($record.ManualFields)) {
                if ($null -eq $newField) { continue }

                $existingValue = Get-InventoryManualFieldValueByKey -ManualFields $assetManualFields -Key $newField.Key
                $newValue = Get-SafeString $newField.Value

                if ($null -eq $existingValue) {
                    # First time this field is seen for this asset: no
                    # previous value to conflict with, add it directly.
                    $assetManualFields += $newField
                }
                elseif ($existingValue -ne $newValue) {
                    # Doc13-Administration.md: every edit needs a reviewed
                    # reason before it is applied — a differing value is
                    # never silently overwritten.
                    $conflictos += [PSCustomObject][ordered]@{
                        AssetId = $existingAssetId
                        Key = $newField.Key
                        ValorActual = $existingValue
                        ValorNuevo = $newValue
                        CollectionId = $record.CollectionId
                    }
                }
                # else: the exact same value was re-submitted, nothing to do.
            }

            $asset | Add-Member -NotePropertyName 'ManualFields' -NotePropertyValue @($assetManualFields) -Force
            $existingHistory = @(@($asset.CollectionHistory) | Where-Object { $null -ne $_ })
            $asset | Add-Member -NotePropertyName 'CollectionHistory' `
                -NotePropertyValue (@($existingHistory) + $historyEntry) -Force
            $asset | Add-Member -NotePropertyName 'UpdatedAt' -NotePropertyValue $now.ToString('o') -Force

            $asset | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $assetPath -Encoding UTF8

            $equiposActualizados += [PSCustomObject][ordered]@{
                AssetId = $existingAssetId
                CollectionId = $record.CollectionId
                ComputerName = $record.ComputerName
                SessionId = $record.SessionId
            }
        }
        else {
            # ADR-005 / doc06: the collector never assigns AssetId — this is
            # the first place in the pipeline where one is minted.
            $created = New-InventoryAssetId -Index $index
            $index = $created.UpdatedIndex
            $newAssetId = $created.AssetId

            $newAsset = [ordered]@{
                AssetId = $newAssetId
                SerialNumber = $record.Asset.SerialNumber
                SystemUuid = $record.Asset.SystemUuid
                Manufacturer = $record.Asset.Manufacturer
                Model = $record.Asset.Model
                Status = 'New'
                CreatedAt = $now.ToString('o')
                UpdatedAt = $now.ToString('o')
                ManualFields = @($record.ManualFields)
                CollectionHistory = @($historyEntry)
                ReviewHistory = @()
            }

            $assetPath = Join-Path $store.AssetsDirectory "$newAssetId.json"
            $newAsset | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $assetPath -Encoding UTF8

            $index.Entries = @($index.Entries) + [PSCustomObject][ordered]@{
                Type = Get-SafeString $preferredIdentifier.Type
                Value = Get-SafeString $preferredIdentifier.Value
                AssetId = $newAssetId
            }

            $nuevosEquipos += [PSCustomObject][ordered]@{
                AssetId = $newAssetId
                CollectionId = $record.CollectionId
                ComputerName = $record.ComputerName
                SessionId = $record.SessionId
            }
        }
    }

    # Single write at the end of the batch, not one per record.
    Save-InventoryAssetIndex -IndexPath $store.IndexPath -Index $index

    return [ordered]@{
        NuevosEquipos = @($nuevosEquipos)
        EquiposActualizados = @($equiposActualizados)
        PosiblesDuplicados = @($posiblesDuplicados)
        Conflictos = @($conflictos)
        ErroresRecoleccion = @($erroresRecoleccion)
        SkippedFiles = @($skippedFiles)
    }
}

function Add-InventoryAssetManualReview {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Applying a human-reviewed correction to the asset store is this function''s purpose.'
    )]
    param(
        [Parameter(Mandatory)][string]$AdministrationBasePath,
        [Parameter(Mandatory)][string]$AssetId,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$NewValue,
        [Parameter(Mandatory)][string]$ReviewedBy,
        [AllowNull()][string]$Reason
    )

    $store = Get-InventoryAssetStorePath -BasePath $AdministrationBasePath
    $assetPath = Join-Path $store.AssetsDirectory "$AssetId.json"

    if (-not (Test-Path -LiteralPath $assetPath)) {
        throw "No se encontró el activo: $AssetId"
    }

    $asset = Get-Content -LiteralPath $assetPath -Raw | ConvertFrom-Json
    $manualFields = @(@($asset.ManualFields) | Where-Object { $null -ne $_ })

    $previousValue = Get-InventoryManualFieldValueByKey -ManualFields $manualFields -Key $Key
    $normalizedValue = Get-SafeString $NewValue
    $now = [datetimeoffset]::Now

    # doc08-Manual-Capture.md: a value corrected after the visit is saved as
    # ManualReview/Confirmed, and the previous value is never discarded.
    $reviewedField = [PSCustomObject][ordered]@{
        Key = $Key
        Value = $normalizedValue
        Source = 'ManualReview'
        CapturedAt = $now.ToString('o')
        CapturedBy = $ReviewedBy
        Confidence = 'Confirmed'
        Status = 'Present'
    }

    $remainingFields = @($manualFields | Where-Object { $_.Key -ne $Key })
    $asset | Add-Member -NotePropertyName 'ManualFields' -NotePropertyValue (@($remainingFields) + $reviewedField) -Force

    # doc13-Administration.md: every edit records previous value, new
    # value, date, reviewer and an optional reason — kept as a flat
    # ReviewHistory list on the asset, the same shape already used for
    # CollectionHistory, instead of nesting history inside the FieldValue
    # itself (which would make it a different shape from the plain doc06
    # FieldValue used everywhere else in the codebase).
    $reviewEntry = [PSCustomObject][ordered]@{
        Key = $Key
        PreviousValue = $previousValue
        NewValue = $normalizedValue
        CapturedAt = $now.ToString('o')
        ReviewedBy = $ReviewedBy
        Reason = Get-SafeString $Reason
    }
    $existingReviewHistory = @(@($asset.ReviewHistory) | Where-Object { $null -ne $_ })
    $asset | Add-Member -NotePropertyName 'ReviewHistory' -NotePropertyValue (@($existingReviewHistory) + $reviewEntry) -Force
    $asset | Add-Member -NotePropertyName 'UpdatedAt' -NotePropertyValue $now.ToString('o') -Force

    $asset | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $assetPath -Encoding UTF8

    return $reviewedField
}
