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

    # Column order and headers follow docs/INSTITUTIONAL_EXCEL_MAPPING.md A-Z.
    # S, V and X are all labeled "CANTIDAD REQUERIDA" in the institutional
    # template; an object cannot carry three properties with the same name,
    # so each is disambiguated with a short qualifier while staying
    # recognizable as the same visible header.
    return [PSCustomObject][ordered]@{
        'REVISADO' = $null
        'IP' = if ($null -ne $adapter) { $adapter.IPv4Address } else { $null }
        'MAC ADDRESS' = if ($null -ne $adapter) { $adapter.MACAddress } else { $null }
        'DIRECCION' = Get-InventoryManualFieldValueByKey -ManualFields $Record.ManualFields -Key 'assignment.organizationUnitId'
        'USUARIO' = Get-InventoryManualFieldValueByKey -ManualFields $Record.ManualFields -Key 'assignment.user.fullName'
        # No existe todavía un campo manual separado para el departamento
        # (hijo de DIRECCION); el catálogo jerárquico de OrganizationUnit es
        # Fase 4 del plan. No se inventa este dato.
        'DEPARTAMENTO' = $null
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
        # Las 7 columnas de evaluación dependen de reglas de RAM/disco (doc
        # 09-Memory-Assessment.md) que todavía no existen; se dejan en null
        # en vez de inventar un valor.
        'CANTIDAD REQUERIDA (MEMORIA)' = $null
        'MEMORIA REQUERIDA' = $null
        'VELOCIDAD' = $null
        'CANTIDAD REQUERIDA (DISCOS)' = $null
        'DISCOS SSD REQUERIDA' = $null
        'CANTIDAD REQUERIDA (CAMBIO)' = $null
        'CAMBIO DE EQUIPO' = $null
        'S.O' = Get-SafeString $technicalData.OperatingSystem.Caption
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
            $parsed = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop |
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
    $records = @($collected.Records)
    $skipped = @($collected.Skipped)

    $inventoryRows = @($records | ForEach-Object { ConvertTo-InventoryWorkbookRow -Record $_ })
    $pendingRows = @(Get-InventoryPendingReviewRows -Records $records)
    $summaryRows = @(Get-InventoryConsolidationSummary -Records $records)

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
