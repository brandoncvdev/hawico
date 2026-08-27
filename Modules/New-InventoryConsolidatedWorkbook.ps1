function Get-InventoryFirstNetworkAdapterWithData {
    param([AllowNull()][object[]]$NetworkAdapters)

    foreach ($adapter in @($NetworkAdapters)) {
        if ($null -eq $adapter) { continue }

        # The whole pipeline must be wrapped in @(), not just its input:
        # Where-Object collapses a single match to a bare scalar otherwise
        # (the same one-element-array unwrap behavior documented elsewhere
        # in this module, here triggered by pipeline assignment instead of
        # `return`).
        $ipv4 = @(@($adapter.IPv4Addresses) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($ipv4.Count -gt 0) {
            return [ordered]@{
                IPv4Address = $ipv4[0]
                MACAddress = Get-SafeString $adapter.MACAddress
            }
        }
    }

    return $null
}

function Get-InventoryManualFieldValueByKey {
    param(
        [AllowNull()][object[]]$ManualFields,
        [Parameter(Mandatory)][string]$Key
    )

    $match = @($ManualFields) | Where-Object { $null -ne $_ -and $_.Key -eq $Key } | Select-Object -First 1
    if ($null -eq $match) { return $null }
    return Get-SafeString $match.Value
}

function Get-InventoryRecordTechnician {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Projects an in-memory value without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$ManualFields
    )

    # CollectionRecord has no single top-level Technician field — the name is
    # only ever stamped on ManualFields[].CapturedBy, once per field, all
    # sharing the same value for one collection run (Read-InventoryManualCapture
    # -Technician stamps every captured field with it). SessionId is a
    # separate concept (groups equipment from the same visit), never the
    # person's name — this reads the technician back from whichever field
    # happens to carry it, instead of duplicating it onto the record schema.
    $match = @($ManualFields) |
        Where-Object { $null -ne $_ -and $null -ne (Get-SafeString $_.CapturedBy) } |
        Select-Object -First 1

    if ($null -eq $match) { return $null }
    return Get-SafeString $match.CapturedBy
}

function Test-InventorySessionUnassigned {
    param([AllowNull()][string]$SessionId)

    $normalized = Get-SafeString $SessionId
    return ($null -eq $normalized) -or ($normalized -eq 'SES-UNASSIGNED')
}

function Get-InventoryDiskTypeLabel {
    # Prefers BusType = NVMe (Get-PhysicalDisk usually reports NVMe drives as
    # MediaType=SSD, which would otherwise hide the distinction the
    # institutional template cares about), falls back to MediaType, then to
    # whatever BusType reports.
    param([AllowNull()][object]$DetailedDisk)

    if ($null -eq $DetailedDisk) { return $null }

    $busType = Get-SafeString $DetailedDisk.BusType
    if ($busType -eq 'NVMe') { return 'NVMe' }

    $mediaType = Get-SafeString $DetailedDisk.MediaType
    if ($null -ne $mediaType -and $mediaType -ne 'Unspecified') { return $mediaType }

    return $busType
}

function Get-InventoryWorkbookCollectedAtDateTime {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Parses an in-memory value without changing system state.'
    )]
    param(
        [AllowNull()][string]$CollectedAt
    )

    $normalized = Get-SafeString $CollectedAt
    if ($null -eq $normalized) {
        return $null
    }

    try {
        $parsed = [datetimeoffset]::Parse($normalized, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }

    # .DateTime (not .LocalDateTime): keeps the wall-clock time exactly as
    # captured on the collection PC, regardless of which timezone the
    # workbook happens to be regenerated in later — administering from a
    # different timezone must never silently shift the displayed hour.
    return $parsed.DateTime
}

function Get-InventoryStorageReplacementAssessment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Derives an in-memory assessment from existing findings without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$StorageFindings
    )

    # Only Critical/High-severity storage findings are a genuine "this disk
    # needs replacing soon" signal (SMART self-assessment FAILED, critical
    # pending sectors, critically low NVMe spare, high wear level — see
    # Modules/Get-HealthFindings.ps1 STO-006/007/008/010). Medium findings
    # (reallocated sectors, elevated temperature, HDD service-life warning)
    # are monitor-and-watch signals, not a replacement recommendation, and
    # are intentionally excluded here.
    $triggeringFindings = @(
        @($StorageFindings) | Where-Object {
            $null -ne $_ -and
            (Get-SafeString $_.Category) -eq 'Storage' -and
            (Get-SafeString $_.Severity) -in @('Critical', 'High')
        }
    )

    if ($triggeringFindings.Count -eq 0) {
        return [ordered]@{ Count = $null; Reason = $null }
    }

    # Get-StorageSmartSummary aggregates worst-of across every physical disk
    # (documented design decision in Get-StorageInfo.ps1), so a finding never
    # identifies which specific disk triggered it. A flat 1 ("replace the
    # flagged unit") is the honest ceiling of what this data actually
    # supports — inventing a precise per-disk count would overclaim
    # precision the underlying aggregation does not have.
    $reason = (
        $triggeringFindings |
            ForEach-Object { Get-SafeString $_.Title } |
            Where-Object { $null -ne $_ } |
            Select-Object -Unique
    ) -join '; '

    return [ordered]@{ Count = 1; Reason = $reason }
}

function ConvertTo-InventoryWorkbookRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Projects an in-memory record into a workbook row without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][object]$Record
    )

    $technicalData = $Record.TechnicalData
    $computer = $technicalData.Computer
    $processors = @($technicalData.Processors)
    $memory = $technicalData.Memory
    $memoryUpgrade = $memory.Upgrade
    $storage = $technicalData.Storage

    $adapter = Get-InventoryFirstNetworkAdapterWithData -NetworkAdapters $technicalData.NetworkAdapters

    $firstProcessor = if ($processors.Count -gt 0) { $processors[0] } else { $null }
    $ghz = $null
    if ($null -ne $firstProcessor -and $null -ne $firstProcessor.MaxClockSpeedMHz) {
        $ghz = [math]::Round(([double]$firstProcessor.MaxClockSpeedMHz / 1000), 2)
    }

    $memoryTypes = @(
        @($memory.Modules) |
            ForEach-Object { Get-SafeString $_.MemoryTypeName } |
            Where-Object { $null -ne $_ } |
            Select-Object -Unique
    )

    $diskDetailed = @($storage.Detailed)
    $diskTypeSource = if ($diskDetailed.Count -gt 0) { $diskDetailed } else { @($storage.Physical) }
    $diskTypes = @(
        $diskTypeSource |
            ForEach-Object { Get-InventoryDiskTypeLabel -DetailedDisk $_ } |
            Where-Object { $null -ne $_ } |
            Select-Object -Unique
    )

    $physicalDisks = @($storage.Physical)
    $diskCapacityGB = $null
    if ($physicalDisks.Count -gt 0) {
        $sum = ($physicalDisks | Where-Object { $null -ne $_.SizeGB } | Measure-Object -Property SizeGB -Sum).Sum
        if ($null -ne $sum) { $diskCapacityGB = [math]::Round([double]$sum, 2) }
    }

    $storageReplacement = Get-InventoryStorageReplacementAssessment -StorageFindings $technicalData.StorageFindings

    # Column order and headers follow docs/INSTITUTIONAL_EXCEL_MAPPING.md A-Z,
    # plus HOSTNAME appended as hawico-only column AA (see that column's own
    # comment below). The RAM-assessment columns (S, T, U) and disk-sizing
    # columns (V, W) were removed: hawico has no memory-upgrade or
    # disk-sizing rule engine, so those would only ever be null placeholders.
    # CANTIDAD REQUERIDA (CAMBIO) is disambiguated from the removed "CANTIDAD
    # REQUERIDA" headers it used to share a name with.
    return [PSCustomObject][ordered]@{
        # Confirmed against the institution's real nuevo_equipos_optimizado.xlsx:
        # REVISADO holds the capture date/time, not a generic review-status
        # flag the column name might otherwise suggest. CollectionRecord.CollectedAt
        # is already always populated by New-InventoryCollectionRecord, so
        # this needs no new capture step, only a projection of data already
        # captured. Real DateTime value (not a raw ISO string) so Excel can
        # sort/filter it as a date.
        'REVISADO' = Get-InventoryWorkbookCollectedAtDateTime -CollectedAt $Record.CollectedAt
        'IP' = if ($null -ne $adapter) { $adapter.IPv4Address } else { $null }
        'MAC ADDRESS' = if ($null -ne $adapter) { $adapter.MACAddress } else { $null }
        'DIRECCION' = Get-InventoryManualFieldValueByKey -ManualFields $Record.ManualFields -Key 'assignment.organizationUnitId'
        'USUARIO' = Get-InventoryManualFieldValueByKey -ManualFields $Record.ManualFields -Key 'assignment.user.fullName'
        'DEPARTAMENTO' = Get-InventoryManualFieldValueByKey -ManualFields $Record.ManualFields -Key 'assignment.departmentUnitId'
        'MARCA' = Get-SafeString $computer.Manufacturer
        'MODELO' = Get-SafeString $computer.Model
        # No hay detector de chasis (SMBIOS ChassisTypes) implementado todavía.
        'PC / LAPTOP' = $null
        'PROCESADOR' = if ($null -ne $firstProcessor) { Get-SafeString $firstProcessor.Name } else { $null }
        'GHz' = $ghz
        'RAM INSTALADA' = $memoryUpgrade.InstalledMemoryGB
        'MODULOS INSTALADOS' = $memoryUpgrade.OccupiedSlots
        'SLOTS RAM' = $memoryUpgrade.TotalSlots
        'RAM MAX (GB)' = $memoryUpgrade.MaximumReportedGB
        'TIPO RAM' = if ($memoryTypes.Count -gt 0) { $memoryTypes -join '/' } else { $null }
        'TIPO DISCO' = if ($diskTypes.Count -gt 0) { $diskTypes -join '/' } else { $null }
        'DISCO (GB)' = $diskCapacityGB
        # Derived from Critical/High-severity storage findings
        # (StorageFindings, projected from Get-StorageSmartSummary via
        # Collector_Hardware_Inventory.ps1) — see
        # Get-InventoryStorageReplacementAssessment above for the exact rule.
        'CANTIDAD REQUERIDA (CAMBIO)' = $storageReplacement.Count
        'CAMBIO DE EQUIPO' = $storageReplacement.Reason
        'S.O' = Get-SafeString $technicalData.OperatingSystem.Caption
        # hawico-only addition (column AA) — appended after the institutional
        # A-Z template, never inserted in the middle: docs/INSTITUTIONAL_EXCEL_MAPPING.md
        # requires the existing A-Z layout and its total formulas to stay
        # untouched. Lets a spreadsheet row be matched back to its
        # Output\Equipos Obtenidos\<Hostname>...\ folder without opening it.
        # Sourced from the top-level Record.ComputerName (the sanitized
        # hostname New-InventoryCollectionRecord copies from
        # Asset.ComputerName), not from TechnicalData.Computer.Hostname
        # directly, to read the same value the rest of the record already
        # treats as this computer's canonical name.
        'HOSTNAME' = Get-SafeString $Record.ComputerName
    }
}

function Get-InventoryConsolidatedRecords {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads and parses existing record files without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$RecordsPath
    )

    if (-not (Test-Path -LiteralPath $RecordsPath)) {
        throw "No se encontró la carpeta de registros: $RecordsPath"
    }

    $records = @()
    $skipped = @()

    $files = @(
        Get-ChildItem -LiteralPath $RecordsPath -Filter '*-record.json' -Recurse -File -ErrorAction SilentlyContinue
    )

    foreach ($file in $files) {
        try {
            $parsed = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            $records += $parsed
        }
        catch {
            $skipped += [ordered]@{
                Path = $file.FullName
                Error = $_.Exception.Message
            }
        }
    }

    # Records/Skipped are values inside a hashtable literal here (not the
    # sole thing returned via `return`), so there is no pipeline-enumeration
    # risk of a one-element array collapsing to its bare element — that bug
    # only bites a bare `return @($array)`. See Get-InventoryPendingReviewRows
    # and Get-InventoryConsolidationSummary below, which DO return a raw
    # array and DO need the `,` guard.
    return [ordered]@{
        Records = @($records)
        Skipped = @($skipped)
    }
}

function Get-InventoryLatestHostRecord {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads existing record files without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$HostOutputDirectory
    )

    # "Already collected" warning (Start-Inventory.ps1): a computer's own
    # Output\<Hostname>\ subfolder may not exist yet at all (first-ever
    # collection for this machine) — Get-InventoryConsolidatedRecords throws
    # on a missing path, so that case is short-circuited here instead of
    # forcing every caller to Test-Path first.
    if (-not (Test-Path -LiteralPath $HostOutputDirectory)) {
        return $null
    }

    $consolidated = Get-InventoryConsolidatedRecords -RecordsPath $HostOutputDirectory
    $records = @(@($consolidated.Records) | Where-Object { $null -ne $_ })
    if ($records.Count -eq 0) {
        return $null
    }

    # Same "keep the most recent, unparsable/missing CollectedAt never wins"
    # rule as Get-InventoryDeduplicatedRecords below — a single host's own
    # subfolder only ever needs the newest of its own repeat collections, not
    # cross-host identity matching.
    $latest = $null
    $latestCollectedAt = $null

    foreach ($record in $records) {
        $candidateCollectedAt = Get-InventoryWorkbookCollectedAtDateTime -CollectedAt $record.CollectedAt

        $shouldReplace = $false
        if ($null -eq $latest) {
            $shouldReplace = $true
        }
        elseif ($null -eq $latestCollectedAt -and $null -ne $candidateCollectedAt) {
            $shouldReplace = $true
        }
        elseif ($null -ne $latestCollectedAt -and $null -ne $candidateCollectedAt -and $candidateCollectedAt -gt $latestCollectedAt) {
            $shouldReplace = $true
        }

        if ($shouldReplace) {
            $latest = $record
            $latestCollectedAt = $candidateCollectedAt
        }
    }

    return $latest
}

function Get-InventoryHostHistoryDefaultValues {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Projects an in-memory prior record into a default-value hashtable without changing system state.'
    )]
    param(
        [AllowNull()][object]$PriorRecord,
        [AllowNull()][hashtable]$PresetValues = @{}
    )

    $defaultValues = @{}
    if ($null -eq $PriorRecord) {
        return $defaultValues
    }

    $hasPresetValues = $null -ne $PresetValues

    # Exactly these 3 keys, by design: assignment.user.fullName,
    # assignment.organizationUnitId, assignment.departmentUnitId.
    # collection.observations is deliberately excluded — notes go stale, so
    # it must always be prompted fresh with no default, every time.
    $candidateKeys = @(
        'assignment.user.fullName',
        'assignment.organizationUnitId',
        'assignment.departmentUnitId'
    )

    foreach ($key in $candidateKeys) {
        # Precedence rule: an already-resolved visit-level PresetValues entry
        # is more current/authoritative than old host history and must never
        # be overridden by it.
        if ($hasPresetValues -and $PresetValues.ContainsKey($key)) {
            continue
        }

        $priorValue = Get-InventoryManualFieldValueByKey -ManualFields $PriorRecord.ManualFields -Key $key
        if ($null -ne $priorValue) {
            $defaultValues[$key] = $priorValue
        }
    }

    return $defaultValues
}

function Get-InventoryDeduplicatedRecords {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Projects an in-memory record list without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Records
    )

    # Bugfix: re-collecting the same physical computer (technician re-running
    # "Generar inventario completo", or a follow-up visit) creates a
    # brand-new *-record.json every time — by design, kept as an audit trail
    # (doc06). Get-InventoryConsolidatedRecords reads every one of those
    # files as-is; without this step, the same computer showed up once per
    # collection instead of once per computer everywhere records feed into
    # (Inventario/Pendientes/Resumen sheets, RecordCount). Same identity rule
    # Modules/InventoryAdministration.ps1 already enforces
    # (doc10-Asset-Identity.md): only records sharing a strong identity
    # (SerialNumber or SystemUuid, Type AND Value matched together) are ever
    # merged — a record with none is never merged with anything, since there
    # is nothing safe to match it on. Keeps whichever duplicate has the most
    # recent CollectedAt (the current known state of that computer).
    $safeRecords = @(@($Records) | Where-Object { $null -ne $_ })

    $latestByIdentity = [ordered]@{}
    $withoutIdentity = @()

    foreach ($record in $safeRecords) {
        $identifier = $record.Asset.PreferredIdentifier
        $identityType = if ($null -ne $identifier) { Get-SafeString $identifier.Type } else { $null }
        $identityValue = if ($null -ne $identifier) { Get-SafeString $identifier.Value } else { $null }

        if ($null -eq $identityType -or $null -eq $identityValue) {
            $withoutIdentity += $record
            continue
        }

        $identityKey = '{0}|{1}' -f $identityType, $identityValue
        $existing = if ($latestByIdentity.Contains($identityKey)) { $latestByIdentity[$identityKey] } else { $null }

        if ($null -eq $existing) {
            $latestByIdentity[$identityKey] = $record
            continue
        }

        $existingCollectedAt = Get-InventoryWorkbookCollectedAtDateTime -CollectedAt $existing.CollectedAt
        $candidateCollectedAt = Get-InventoryWorkbookCollectedAtDateTime -CollectedAt $record.CollectedAt

        # An unparsable/missing CollectedAt never displaces an already-kept
        # record that has a real, comparable timestamp — better to keep a
        # known snapshot than silently swap it for one we can't compare.
        $shouldReplace = $false
        if ($null -eq $existingCollectedAt -and $null -ne $candidateCollectedAt) {
            $shouldReplace = $true
        }
        elseif ($null -ne $existingCollectedAt -and $null -ne $candidateCollectedAt -and $candidateCollectedAt -gt $existingCollectedAt) {
            $shouldReplace = $true
        }

        if ($shouldReplace) {
            $latestByIdentity[$identityKey] = $record
        }
    }

    return ,@(@($latestByIdentity.Values) + $withoutIdentity)
}

function Get-InventoryPendingReviewRows {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Projects existing records into pending-review rows without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Records
    )

    $pendingRows = @()

    foreach ($record in @($Records)) {
        if ($null -eq $record) { continue }

        $reasons = @()

        if ($record.Asset.Status -eq 'NeedsReview') {
            $reasons += 'Identidad de activo requiere revisión'
        }

        if (Test-InventorySessionUnassigned -SessionId $record.SessionId) {
            $reasons += 'Sesión no asignada'
        }

        if ($null -eq (Get-InventoryManualFieldValueByKey -ManualFields $record.ManualFields -Key 'assignment.user.fullName')) {
            $reasons += 'Usuario no capturado'
        }

        if ($reasons.Count -gt 0) {
            $pendingRows += [PSCustomObject][ordered]@{
                CollectionId = $record.CollectionId
                ComputerName = $record.ComputerName
                SessionId = $record.SessionId
                Motivos = $reasons -join '; '
            }
        }
    }

    # The unary comma forces the array itself onto the output stream so a
    # single pending row is not unwrapped into a bare object by the caller.
    return ,@($pendingRows)
}

function Get-InventoryConsolidationSummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Aggregates existing records into summary rows without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Records
    )

    $all = @(@($Records) | Where-Object { $null -ne $_ })
    $total = $all.Count
    $identified = @($all | Where-Object { $_.Asset.Status -eq 'Identified' }).Count
    $needsReview = @($all | Where-Object { $_.Asset.Status -eq 'NeedsReview' }).Count
    $withSession = @($all | Where-Object { -not (Test-InventorySessionUnassigned -SessionId $_.SessionId) }).Count
    $withoutSession = $total - $withSession
    $withUser = @(
        $all | Where-Object {
            $null -ne (Get-InventoryManualFieldValueByKey -ManualFields $_.ManualFields -Key 'assignment.user.fullName')
        }
    ).Count

    # Same single-element unwrap guard as Get-InventoryPendingReviewRows,
    # kept even though this list currently always has 6 rows so it stays
    # correct if the metric set ever shrinks to one.
    return ,@(
        [PSCustomObject][ordered]@{ Metrica = 'Total de equipos'; Valor = $total }
        [PSCustomObject][ordered]@{ Metrica = 'Con identidad confirmada'; Valor = $identified }
        [PSCustomObject][ordered]@{ Metrica = 'Requieren revisión de identidad'; Valor = $needsReview }
        [PSCustomObject][ordered]@{ Metrica = 'Con sesión asignada'; Valor = $withSession }
        [PSCustomObject][ordered]@{ Metrica = 'Sin sesión asignada'; Valor = $withoutSession }
        [PSCustomObject][ordered]@{ Metrica = 'Con usuario capturado'; Valor = $withUser }
    )
}

function Export-InventoryConsolidatedWorkbook {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Regenerating the consolidated workbook on disk is the purpose of this orchestrator.'
    )]
    param(
        [Parameter(Mandatory)][string]$RecordsPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [AllowNull()][string]$HistoryDirectory
    )

    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        throw ("El módulo ImportExcel no está instalado. Ejecute: " +
            "Install-Module ImportExcel -Scope CurrentUser -Force")
    }

    $collected = Get-InventoryConsolidatedRecords -RecordsPath $RecordsPath
    # Bugfix: re-collecting the same computer used to add another full row
    # to Inventario per collection instead of per computer, since every
    # *-record.json file (kept as an audit trail by design) was projected
    # 1:1 into a row. Deduplicated once here, before any sheet is built, so
    # Inventario/Pendientes/Resumen and RecordCount all agree with each other.
    # No extra @() around this call: Get-InventoryDeduplicatedRecords already
    # returns a correctly-flat array via its own ,@() return guard — wrapping
    # an already comma-guarded call in another @() re-nests it into a
    # 1-element array whose sole element is the real array (same footgun the
    # comment below already warns about for the two calls right after this).
    $records = Get-InventoryDeduplicatedRecords -Records $collected.Records
    $skipped = @($collected.Skipped)

    # No extra @() around the two calls below: Get-InventoryPendingReviewRows
    # and Get-InventoryConsolidationSummary already return a correctly-flat
    # array via their own `,@()` return guard. Wrapping an already
    # comma-guarded call in another @() re-nests it into a 1-element array
    # whose sole element is the real array — `.Count` then always reports 1
    # regardless of the actual row count (piping the nested result into
    # Export-Excel still happened to work, since `|` auto-enumerates one
    # level, which is why this went unnoticed: it only corrupted the
    # PendingCount reported back to the caller, not the sheet content).
    $inventoryRows = @($records | ForEach-Object { ConvertTo-InventoryWorkbookRow -Record $_ })
    $pendingRows = Get-InventoryPendingReviewRows -Records $records
    $summaryRows = Get-InventoryConsolidationSummary -Records $records

    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    $outputDir = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }

    # The workbook is regenerated completely on every run (doc
    # 12-Excel-Engine.md: "regenerar el archivo completo de manera
    # reproducible"), so $OutputPath was just deleted above and every sheet
    # below is written exactly once.
    if ($inventoryRows.Count -gt 0) {
        $inventoryRows | Export-Excel -Path $OutputPath -WorksheetName 'Inventario' `
            -AutoSize -FreezeTopRow -AutoFilter -BoldTopRow
    }
    else {
        [PSCustomObject]@{ Aviso = 'No se encontraron registros para consolidar.' } |
            Export-Excel -Path $OutputPath -WorksheetName 'Inventario' -AutoSize -BoldTopRow
    }

    if ($pendingRows.Count -gt 0) {
        $pendingRows | Export-Excel -Path $OutputPath -WorksheetName 'Pendientes' `
            -AutoSize -FreezeTopRow -AutoFilter -BoldTopRow
    }
    else {
        [PSCustomObject]@{ Aviso = 'No hay equipos pendientes de revisión.' } |
            Export-Excel -Path $OutputPath -WorksheetName 'Pendientes' -AutoSize -BoldTopRow
    }

    $summaryRows | Export-Excel -Path $OutputPath -WorksheetName 'Resumen' -AutoSize -BoldTopRow

    $historyPath = $null
    if (-not [string]::IsNullOrWhiteSpace($HistoryDirectory)) {
        New-Item -ItemType Directory -Force -Path $HistoryDirectory | Out-Null
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $historyPath = Join-Path $HistoryDirectory "Consolidado-$timestamp.xlsx"
        Copy-Item -LiteralPath $OutputPath -Destination $historyPath -Force
    }

    return [ordered]@{
        OutputPath = $OutputPath
        HistoryPath = $historyPath
        RecordCount = $records.Count
        SkippedCount = $skipped.Count
        PendingCount = $pendingRows.Count
    }
}
