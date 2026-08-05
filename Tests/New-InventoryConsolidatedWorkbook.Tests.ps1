BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryConsolidatedWorkbook.ps1"

    # Fixture built from the REAL property names produced by the collector
    # modules (verified against Modules/Get-ComputerInfo.ps1,
    # Get-ProcessorInfo.ps1, Get-MemoryInfo.ps1, Get-NetworkInfo.ps1 and
    # Get-StorageInfo.ps1) — not from assumptions.
    function New-FixtureRecord {
        param(
            [string]$CollectionId = 'COL-20260803-123000-ABC12345',
            [string]$ComputerName = 'RH-PC-04',
            [string]$AssetStatus = 'Identified',
            [AllowNull()][string]$SessionId = 'SES-20260803-AM-RH',
            [AllowNull()][object[]]$ManualFields = @(
                [PSCustomObject]@{
                    Key = 'assignment.user.fullName'
                    Value = 'Juan Pérez Hernández'
                    Source = 'VisitCapture'
                    CapturedBy = 'Técnico 01'
                }
                [PSCustomObject]@{
                    Key = 'assignment.organizationUnitId'
                    Value = 'dept-hr'
                    Source = 'SessionContext'
                    CapturedBy = 'Técnico 01'
                }
            ),
            [AllowNull()][object[]]$NetworkAdapters = @(
                [PSCustomObject]@{
                    InterfaceAlias = 'Ethernet'
                    MACAddress = '00-11-22-33-44-55'
                    IPv4Addresses = @('192.168.1.225')
                }
            ),
            [AllowNull()][object[]]$Processors = @(
                [PSCustomObject]@{
                    Name = 'Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz'
                    NumberOfCores = 6
                    MaxClockSpeedMHz = 3100
                }
            ),
            [AllowNull()][object[]]$MemoryModules = @(
                [PSCustomObject]@{ DeviceLocator = 'DIMM1'; CapacityGB = 8; MemoryTypeName = 'DDR4' }
                [PSCustomObject]@{ DeviceLocator = 'DIMM2'; CapacityGB = 8; MemoryTypeName = 'DDR4' }
            ),
            [AllowNull()][object]$MemoryUpgrade = [PSCustomObject]@{
                TotalSlots = 4
                OccupiedSlots = 2
                AvailableSlots = 2
                InstalledMemoryGB = 16
                MaximumReportedGB = 128
            },
            [AllowNull()][object[]]$StoragePhysical = @(
                [PSCustomObject]@{ Model = 'Samsung SSD 970 EVO'; SizeGB = 476.94 }
                [PSCustomObject]@{ Model = 'WDC WD10EZEX'; SizeGB = 931.51 }
            ),
            [AllowNull()][object[]]$StorageDetailed = @(
                [PSCustomObject]@{ FriendlyName = 'Samsung SSD 970 EVO'; MediaType = 'SSD'; BusType = 'NVMe'; SizeGB = 476.94 }
                [PSCustomObject]@{ FriendlyName = 'WDC WD10EZEX'; MediaType = 'HDD'; BusType = 'SATA'; SizeGB = 931.51 }
            )
        )

        return [PSCustomObject]@{
            ContractVersion = '1.0'
            CollectionId = $CollectionId
            Asset = [PSCustomObject]@{
                AssetId = $null
                SerialNumber = 'ABC12345'
                SystemUuid = '4C4C4544-0038-4D10-8051-C4C04F503332'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
                ComputerName = $ComputerName
                PreferredIdentifier = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'ABC12345' }
                Status = $AssetStatus
            }
            SessionId = $SessionId
            CollectedAt = '2026-08-03T12:30:00-06:00'
            CollectorVersion = '0.5.0'
            ComputerName = $ComputerName
            TechnicalData = [PSCustomObject]@{
                SchemaVersion = '2.0'
                Computer = [PSCustomObject]@{
                    Hostname = $ComputerName
                    Manufacturer = 'Dell Inc.'
                    Model = 'OptiPlex 7090'
                    SystemType = 'x64-based PC'
                    UUID = '4C4C4544-0038-4D10-8051-C4C04F503332'
                }
                OperatingSystem = [PSCustomObject]@{
                    Caption = 'Microsoft Windows 10 Pro'
                    Version = '10.0.19045'
                }
                Processors = $Processors
                Memory = [PSCustomObject]@{
                    Modules = $MemoryModules
                    Upgrade = $MemoryUpgrade
                }
                NetworkAdapters = $NetworkAdapters
                Storage = [PSCustomObject]@{
                    Physical = $StoragePhysical
                    Detailed = $StorageDetailed
                }
            }
            ManualFields = $ManualFields
            Assessments = @()
            Errors = @()
        }
    }
}

Describe 'ConvertTo-InventoryWorkbookRow' {
    It 'maps every available field using the real collector property paths' {
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord)

        # REVISADO holds the capture date/time (confirmed by the institution
        # against its real nuevo_equipos_optimizado.xlsx template — this is
        # NOT the generic "review status" the column name might suggest).
        # Real DateTime value (not a raw ISO string), so Excel can sort/filter
        # it as a date instead of plain text — CollectionRecord.CollectedAt
        # ('2026-08-03T12:30:00-06:00' in this fixture) is already always
        # populated by New-InventoryCollectionRecord, so this needs no new
        # capture step, only a projection of data already captured.
        # .DateTime (not .LocalDateTime): keeps the wall-clock time exactly as
        # recorded at the collection PC, regardless of which timezone the
        # workbook happens to be generated in later — administering from a
        # different timezone must never silently shift the displayed hour.
        $row.'REVISADO' | Should -BeOfType [datetime]
        $row.'REVISADO' | Should -Be ([datetimeoffset]'2026-08-03T12:30:00-06:00').DateTime
        $row.'IP' | Should -Be '192.168.1.225'
        $row.'MAC ADDRESS' | Should -Be '00-11-22-33-44-55'
        $row.'DIRECCION' | Should -Be 'dept-hr'
        $row.'USUARIO' | Should -Be 'Juan Pérez Hernández'
        $row.'MARCA' | Should -Be 'Dell Inc.'
        $row.'MODELO' | Should -Be 'OptiPlex 7090'
        $row.'PROCESADOR' | Should -Be 'Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz'
        $row.'GHz' | Should -Be 3.1
        $row.'RAM INSTALADA' | Should -Be 16
        $row.'MODULOS INSTALADOS' | Should -Be 2
        $row.'SLOTS RAM' | Should -Be 4
        $row.'RAM MAX (GB)' | Should -Be 128
        $row.'TIPO RAM' | Should -Be 'DDR4'
        $row.'TIPO DISCO' | Should -Be 'NVMe/HDD'
        $row.'DISCO (GB)' | Should -Be 1408.45
        $row.'S.O' | Should -Be 'Microsoft Windows 10 Pro'
    }

    It 'returns a PSCustomObject with columns in the documented A-to-Z order' {
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord)

        $row | Should -BeOfType [System.Management.Automation.PSCustomObject]
        $names = @($row.PSObject.Properties.Name)
        $names | Should -Be @(
            'REVISADO', 'IP', 'MAC ADDRESS', 'DIRECCION', 'USUARIO', 'DEPARTAMENTO',
            'MARCA', 'MODELO', 'PC / LAPTOP', 'PROCESADOR', 'GHz',
            'RAM INSTALADA', 'MODULOS INSTALADOS', 'SLOTS RAM', 'RAM MAX (GB)',
            'TIPO RAM', 'TIPO DISCO', 'DISCO (GB)',
            'CANTIDAD REQUERIDA (MEMORIA)', 'MEMORIA REQUERIDA', 'VELOCIDAD',
            'CANTIDAD REQUERIDA (DISCOS)', 'DISCOS SSD REQUERIDA',
            'CANTIDAD REQUERIDA (CAMBIO)', 'CAMBIO DE EQUIPO', 'S.O'
        )
    }

    It 'leaves REVISADO null instead of throwing when CollectedAt is missing or unparsable' {
        $record = New-FixtureRecord
        $record.CollectedAt = $null
        (ConvertTo-InventoryWorkbookRow -Record $record).'REVISADO' | Should -BeNullOrEmpty

        $record2 = New-FixtureRecord
        $record2.CollectedAt = 'no-es-una-fecha'
        (ConvertTo-InventoryWorkbookRow -Record $record2).'REVISADO' | Should -BeNullOrEmpty
    }

    It 'leaves DEPARTAMENTO null when no assignment.departmentUnitId manual field was captured' {
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord)

        $row.'DEPARTAMENTO' | Should -BeNullOrEmpty
    }

    It 'reads DEPARTAMENTO from the assignment.departmentUnitId manual field when it was captured' {
        $manualFields = @(
            [PSCustomObject]@{
                Key = 'assignment.organizationUnitId'
                Value = 'Dirección Administrativa'
                Source = 'SessionContext'
                CapturedBy = 'Técnico 01'
            }
            [PSCustomObject]@{
                Key = 'assignment.departmentUnitId'
                Value = 'Recursos Humanos'
                Source = 'SessionContext'
                CapturedBy = 'Técnico 01'
            }
        )
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord -ManualFields $manualFields)

        $row.'DIRECCION' | Should -Be 'Dirección Administrativa'
        $row.'DEPARTAMENTO' | Should -Be 'Recursos Humanos'
    }

    It 'leaves PC / LAPTOP and every Assessment column null (not implemented yet)' {
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord)

        $row.'PC / LAPTOP' | Should -BeNullOrEmpty
        $row.'CANTIDAD REQUERIDA (MEMORIA)' | Should -BeNullOrEmpty
        $row.'MEMORIA REQUERIDA' | Should -BeNullOrEmpty
        $row.'VELOCIDAD' | Should -BeNullOrEmpty
        $row.'CANTIDAD REQUERIDA (DISCOS)' | Should -BeNullOrEmpty
        $row.'DISCOS SSD REQUERIDA' | Should -BeNullOrEmpty
        $row.'CANTIDAD REQUERIDA (CAMBIO)' | Should -BeNullOrEmpty
        $row.'CAMBIO DE EQUIPO' | Should -BeNullOrEmpty
    }

    It 'leaves IP, MAC, DIRECCION, USUARIO, GHz, TIPO RAM and TIPO DISCO null when the evidence is missing' {
        $record = New-FixtureRecord `
            -ManualFields @() `
            -NetworkAdapters @() `
            -Processors @() `
            -MemoryModules @() `
            -StoragePhysical @() `
            -StorageDetailed @()

        $row = ConvertTo-InventoryWorkbookRow -Record $record

        $row.'IP' | Should -BeNullOrEmpty
        $row.'MAC ADDRESS' | Should -BeNullOrEmpty
        $row.'DIRECCION' | Should -BeNullOrEmpty
        $row.'USUARIO' | Should -BeNullOrEmpty
        $row.'PROCESADOR' | Should -BeNullOrEmpty
        $row.'GHz' | Should -BeNullOrEmpty
        $row.'TIPO RAM' | Should -BeNullOrEmpty
        $row.'TIPO DISCO' | Should -BeNullOrEmpty
        $row.'DISCO (GB)' | Should -BeNullOrEmpty
    }

    It 'skips network adapters without any IPv4 address and uses the first one that has data' {
        $record = New-FixtureRecord -NetworkAdapters @(
            [PSCustomObject]@{ InterfaceAlias = 'Wi-Fi'; MACAddress = 'AA-AA-AA-AA-AA-AA'; IPv4Addresses = @() }
            [PSCustomObject]@{ InterfaceAlias = 'Ethernet'; MACAddress = 'BB-BB-BB-BB-BB-BB'; IPv4Addresses = @('10.0.0.5') }
        )

        $row = ConvertTo-InventoryWorkbookRow -Record $record

        $row.'IP' | Should -Be '10.0.0.5'
        $row.'MAC ADDRESS' | Should -Be 'BB-BB-BB-BB-BB-BB'
    }

    It 'joins multiple distinct RAM and disk types with a slash instead of hiding the conflict' {
        $record = New-FixtureRecord `
            -MemoryModules @(
                [PSCustomObject]@{ DeviceLocator = 'DIMM1'; CapacityGB = 8; MemoryTypeName = 'DDR3' }
                [PSCustomObject]@{ DeviceLocator = 'DIMM2'; CapacityGB = 8; MemoryTypeName = 'DDR4' }
            ) `
            -StorageDetailed @(
                [PSCustomObject]@{ FriendlyName = 'Disk1'; MediaType = 'HDD'; BusType = 'SATA'; SizeGB = 500 }
                [PSCustomObject]@{ FriendlyName = 'Disk2'; MediaType = 'SSD'; BusType = 'SATA'; SizeGB = 250 }
            )

        $row = ConvertTo-InventoryWorkbookRow -Record $record

        $row.'TIPO RAM' | Should -Be 'DDR3/DDR4'
        $row.'TIPO DISCO' | Should -Be 'HDD/SSD'
    }
}

Describe 'Get-InventoryRecordTechnician' {
    # CollectionRecord has no single top-level "Technician" field — the
    # technician's name is only ever stamped on ManualFields[].CapturedBy,
    # once per field, all sharing the same value for one collection run
    # (Read-InventoryManualCapture -Technician stamps every captured field
    # with it). This reads it back from whichever field is present, instead
    # of duplicating a Technician property onto the record's own schema.
    It 'reads the technician from the first manual field that has one' {
        $manualFields = @(
            [PSCustomObject]@{ Key = 'assignment.user.fullName'; Value = 'Juan Pérez'; CapturedBy = 'Técnico 01' }
            [PSCustomObject]@{ Key = 'asset.assetTag'; Value = 'AT-001'; CapturedBy = 'Técnico 01' }
        )

        Get-InventoryRecordTechnician -ManualFields $manualFields | Should -Be 'Técnico 01'
    }

    It 'returns null without throwing when there are no manual fields at all' {
        Get-InventoryRecordTechnician -ManualFields @() | Should -BeNullOrEmpty
        Get-InventoryRecordTechnician -ManualFields $null | Should -BeNullOrEmpty
    }

    It 'skips a field with a blank CapturedBy and uses the next one that has a real value' {
        $manualFields = @(
            [PSCustomObject]@{ Key = 'assignment.user.fullName'; Value = 'Juan Pérez'; CapturedBy = $null }
            [PSCustomObject]@{ Key = 'asset.assetTag'; Value = 'AT-001'; CapturedBy = 'Técnico 02' }
        )

        Get-InventoryRecordTechnician -ManualFields $manualFields | Should -Be 'Técnico 02'
    }
}

Describe 'Get-InventoryConsolidatedRecords' {
    BeforeEach {
        $script:recordsDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:recordsDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:recordsDir 'session-a') -Force | Out-Null
    }

    It 'parses every *-record.json file recursively and reports a valid Records array' {
        (New-FixtureRecord -CollectionId 'COL-1') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:recordsDir 'PC-01-20260803-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-2') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:recordsDir 'session-a\PC-02-20260803-record.json') -Encoding UTF8
        'not a record' | Set-Content -LiteralPath (Join-Path $script:recordsDir 'PC-01-20260803.json') -Encoding UTF8

        $result = Get-InventoryConsolidatedRecords -RecordsPath $script:recordsDir

        @($result.Records).Count | Should -Be 2
        @($result.Skipped).Count | Should -Be 0
        (@($result.Records) | ForEach-Object { $_.CollectionId }) | Should -Contain 'COL-1'
        (@($result.Records) | ForEach-Object { $_.CollectionId }) | Should -Contain 'COL-2'
    }

    It 'accumulates malformed files as skipped instead of aborting the whole run' {
        (New-FixtureRecord -CollectionId 'COL-OK') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:recordsDir 'PC-OK-record.json') -Encoding UTF8
        '{ not valid json' | Set-Content -LiteralPath (Join-Path $script:recordsDir 'PC-BAD-record.json') -Encoding UTF8

        $result = Get-InventoryConsolidatedRecords -RecordsPath $script:recordsDir

        @($result.Records).Count | Should -Be 1
        @($result.Skipped).Count | Should -Be 1
        $result.Skipped[0].Path | Should -Match 'PC-BAD-record\.json'
        $result.Skipped[0].Error | Should -Not -BeNullOrEmpty
    }

    It 'returns an array for Records even when exactly one record is found (single-element array bug)' {
        (New-FixtureRecord -CollectionId 'COL-ONLY') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:recordsDir 'PC-ONLY-record.json') -Encoding UTF8

        $result = Get-InventoryConsolidatedRecords -RecordsPath $script:recordsDir

        $result.Records.GetType().IsArray | Should -BeTrue
        $result.Records.Count | Should -Be 1
    }

    It 'throws a clear error when the records path does not exist' {
        { Get-InventoryConsolidatedRecords -RecordsPath (Join-Path $script:recordsDir 'does-not-exist') } |
            Should -Throw
    }
}

Describe 'Get-InventoryPendingReviewRows' {
    It 'flags identity, session and user capture gaps with readable reasons' {
        $clean = New-FixtureRecord -CollectionId 'COL-CLEAN'
        $allIssues = New-FixtureRecord -CollectionId 'COL-ALL' -AssetStatus 'NeedsReview' -SessionId 'SES-UNASSIGNED' -ManualFields @()
        $missingUserOnly = New-FixtureRecord -CollectionId 'COL-USER' -SessionId 'SES-REAL-002' -ManualFields @()

        $result = Get-InventoryPendingReviewRows -Records @($clean, $allIssues, $missingUserOnly)

        $result.GetType().IsArray | Should -BeTrue
        @($result).Count | Should -Be 2

        $allIssuesRow = $result | Where-Object { $_.CollectionId -eq 'COL-ALL' }
        $allIssuesRow.Motivos | Should -Match 'Identidad de activo requiere revisión'
        $allIssuesRow.Motivos | Should -Match 'Sesión no asignada'
        $allIssuesRow.Motivos | Should -Match 'Usuario no capturado'

        $missingUserRow = $result | Where-Object { $_.CollectionId -eq 'COL-USER' }
        $missingUserRow.Motivos | Should -Be 'Usuario no capturado'
    }

    It 'returns an array even when exactly one record is pending review (single-element array bug)' {
        $onlyPending = New-FixtureRecord -CollectionId 'COL-ONLY-PENDING' -SessionId $null -ManualFields @()

        $result = Get-InventoryPendingReviewRows -Records @($onlyPending)

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'treats a null or SES-UNASSIGNED session id as unassigned' {
        $nullSession = New-FixtureRecord -CollectionId 'COL-NULL-SESSION' -SessionId $null
        $unassignedSession = New-FixtureRecord -CollectionId 'COL-UNASSIGNED-SESSION' -SessionId 'SES-UNASSIGNED'

        $result = Get-InventoryPendingReviewRows -Records @($nullSession, $unassignedSession)

        @($result).Count | Should -Be 2
        ($result | Where-Object { $_.CollectionId -eq 'COL-NULL-SESSION' }).Motivos | Should -Match 'Sesión no asignada'
        ($result | Where-Object { $_.CollectionId -eq 'COL-UNASSIGNED-SESSION' }).Motivos | Should -Match 'Sesión no asignada'
    }
}

Describe 'Get-InventoryConsolidationSummary' {
    It 'aggregates totals, identity, session and user-capture coverage' {
        $clean = New-FixtureRecord -CollectionId 'COL-CLEAN'
        $needsReview = New-FixtureRecord -CollectionId 'COL-REVIEW' -AssetStatus 'NeedsReview' -SessionId 'SES-UNASSIGNED' -ManualFields @()
        $missingUserOnly = New-FixtureRecord -CollectionId 'COL-USER' -SessionId 'SES-REAL-002' -ManualFields @()

        $summary = Get-InventoryConsolidationSummary -Records @($clean, $needsReview, $missingUserOnly)

        $summary.GetType().IsArray | Should -BeTrue

        $byMetric = @{}
        foreach ($row in $summary) { $byMetric[$row.Metrica] = $row.Valor }

        $byMetric['Total de equipos'] | Should -Be 3
        $byMetric['Con identidad confirmada'] | Should -Be 2
        $byMetric['Requieren revisión de identidad'] | Should -Be 1
        $byMetric['Con sesión asignada'] | Should -Be 2
        $byMetric['Sin sesión asignada'] | Should -Be 1
        $byMetric['Con usuario capturado'] | Should -Be 1
    }
}

Describe 'Export-InventoryConsolidatedWorkbook' -Skip:(-not (Get-Module -ListAvailable -Name ImportExcel)) {
    BeforeAll {
        Import-Module ImportExcel -ErrorAction Stop
    }

    It 'generates a workbook with the Inventario, Pendientes and Resumen sheets' {
        $recordsDir = Join-Path $TestDrive 'export-records'
        New-Item -ItemType Directory -Path $recordsDir -Force | Out-Null

        (New-FixtureRecord -CollectionId 'COL-EXPORT-1') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-EXPORT-2' -AssetStatus 'NeedsReview' -SessionId 'SES-UNASSIGNED' -ManualFields @()) |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-02-record.json') -Encoding UTF8

        $outputPath = Join-Path $TestDrive 'Consolidado.xlsx'
        $historyDirectory = Join-Path $TestDrive 'Historico'

        $result = Export-InventoryConsolidatedWorkbook `
            -RecordsPath $recordsDir `
            -OutputPath $outputPath `
            -HistoryDirectory $historyDirectory

        Test-Path -LiteralPath $outputPath | Should -BeTrue
        $result.RecordCount | Should -Be 2
        $result.SkippedCount | Should -Be 0
        $result.PendingCount | Should -Be 1

        $sheetNames = @((Get-ExcelSheetInfo -Path $outputPath).Name)
        $sheetNames | Should -Contain 'Inventario'
        $sheetNames | Should -Contain 'Pendientes'
        $sheetNames | Should -Contain 'Resumen'

        $inventoryRows = @(Import-Excel -Path $outputPath -WorksheetName 'Inventario')
        $inventoryRows.Count | Should -Be 2

        $result.HistoryPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $result.HistoryPath | Should -BeTrue
    }

    It 'reports the real PendingCount when more than one record needs review (not always 1)' {
        $recordsDir = Join-Path $TestDrive 'export-pending-count'
        New-Item -ItemType Directory -Path $recordsDir -Force | Out-Null

        (New-FixtureRecord -CollectionId 'COL-PENDING-1' -AssetStatus 'NeedsReview' -SessionId 'SES-UNASSIGNED' -ManualFields @()) |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-PENDING-2' -AssetStatus 'NeedsReview' -SessionId 'SES-UNASSIGNED' -ManualFields @()) |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-02-record.json') -Encoding UTF8

        $outputPath = Join-Path $TestDrive 'Consolidado-PendingCount.xlsx'

        $result = Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath

        $result.PendingCount | Should -Be 2

        $pendientesRows = @(Import-Excel -Path $outputPath -WorksheetName 'Pendientes')
        $pendientesRows.Count | Should -Be 2
    }

    It 'regenerates the workbook from scratch instead of accumulating stale sheets' {
        $recordsDir = Join-Path $TestDrive 'export-regen'
        New-Item -ItemType Directory -Path $recordsDir -Force | Out-Null
        (New-FixtureRecord -CollectionId 'COL-REGEN') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-record.json') -Encoding UTF8

        $outputPath = Join-Path $TestDrive 'Consolidado-Regen.xlsx'

        Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath | Out-Null
        $firstRun = @(Import-Excel -Path $outputPath -WorksheetName 'Inventario')

        (New-FixtureRecord -CollectionId 'COL-REGEN-2') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-02-record.json') -Encoding UTF8
        Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath | Out-Null
        $secondRun = @(Import-Excel -Path $outputPath -WorksheetName 'Inventario')

        $firstRun.Count | Should -Be 1
        $secondRun.Count | Should -Be 2
    }
}
