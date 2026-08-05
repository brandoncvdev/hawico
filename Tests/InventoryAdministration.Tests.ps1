BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryConsolidatedWorkbook.ps1"
    . "$PSScriptRoot/../Modules/InventoryAdministration.ps1"

    function New-FixtureManualField {
        param(
            [Parameter(Mandatory)][string]$Key,
            [Parameter(Mandatory)][string]$Value,
            [string]$Source = 'VisitCapture',
            [string]$CapturedBy = 'Técnico 01'
        )

        return [PSCustomObject]@{
            Key = $Key
            Value = $Value
            Source = $Source
            CapturedAt = ([datetimeoffset]::Now).ToString('o')
            CapturedBy = $CapturedBy
            Confidence = 'Unconfirmed'
            Status = 'Present'
        }
    }

    function New-FixtureCollectionRecord {
        param(
            [string]$CollectionId = ('COL-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 8))),
            [string]$ComputerName = 'PC-01',
            [string]$SessionId = 'SES-20260803-AM-RH',
            [AllowNull()][string]$SerialNumber = 'ABC12345',
            [AllowNull()][string]$SystemUuid = '4C4C4544-0038-4D10-8051-C4C04F503332',
            [AllowNull()][object]$PreferredIdentifier = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'ABC12345' },
            [string]$AssetStatus = 'Identified',
            [AllowNull()][object[]]$ManualFields = @(),
            [AllowNull()][object[]]$Errors = @()
        )

        return [PSCustomObject]@{
            ContractVersion = '1.0'
            CollectionId = $CollectionId
            Asset = [PSCustomObject]@{
                AssetId = $null
                SerialNumber = $SerialNumber
                SystemUuid = $SystemUuid
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
                ComputerName = $ComputerName
                PreferredIdentifier = $PreferredIdentifier
                Status = $AssetStatus
            }
            SessionId = $SessionId
            CollectedAt = ([datetimeoffset]::Now).ToString('o')
            CollectorVersion = '0.5.0'
            ComputerName = $ComputerName
            TechnicalData = [PSCustomObject]@{ SchemaVersion = '2.0' }
            ManualFields = @($ManualFields)
            Assessments = @()
            Errors = @($Errors)
        }
    }

    function Write-FixtureRecordFile {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [Parameter(Mandatory)][object]$Record
        )

        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
        $fileName = "$($Record.ComputerName)-$([guid]::NewGuid().ToString('N').Substring(0, 6))-record.json"
        $path = Join-Path $Directory $fileName
        $Record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
}

Describe 'Get-InventoryAssetStorePath' {
    It 'builds the assets directory and index path under Administracion/' {
        $basePath = Join-Path $TestDrive 'store-test'

        $store = Get-InventoryAssetStorePath -BasePath $basePath

        $expectedAssetsDirectory = Join-Path (Join-Path $basePath 'Administracion') 'Assets'
        $expectedIndexPath = Join-Path (Join-Path $basePath 'Administracion') 'assets-index.json'
        $store.AssetsDirectory | Should -Be $expectedAssetsDirectory
        $store.IndexPath | Should -Be $expectedIndexPath
    }
}

Describe 'Get-InventoryAssetIndex' {
    It 'returns an empty index with NextSequence 1 when the file does not exist' {
        $index = Get-InventoryAssetIndex -IndexPath (Join-Path $TestDrive 'missing-index.json')

        $index.NextSequence | Should -Be 1
        @($index.Entries).Count | Should -Be 0
    }

    It 'round-trips a saved index' {
        $indexPath = Join-Path $TestDrive 'roundtrip-index.json'
        $index = [ordered]@{
            NextSequence = 3
            Entries = @(
                [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'ABC12345'; AssetId = 'AST-0001' }
                [PSCustomObject]@{ Type = 'SystemUuid'; Value = 'UUID-2'; AssetId = 'AST-0002' }
            )
        }

        Save-InventoryAssetIndex -IndexPath $indexPath -Index $index
        $loaded = Get-InventoryAssetIndex -IndexPath $indexPath

        $loaded.NextSequence | Should -Be 3
        @($loaded.Entries).Count | Should -Be 2
        $loaded.Entries[0].AssetId | Should -Be 'AST-0001'
        $loaded.Entries[1].AssetId | Should -Be 'AST-0002'
    }
}

Describe 'New-InventoryAssetId' {
    It 'formats a zero-padded sequential id and returns an updated, non-mutated index' {
        $index = [ordered]@{ NextSequence = 1; Entries = @() }

        $created = New-InventoryAssetId -Index $index

        $created.AssetId | Should -Be 'AST-0001'
        $created.UpdatedIndex.NextSequence | Should -Be 2
        $index.NextSequence | Should -Be 1
    }

    It 'reaches AST-0042 style padding for double-digit sequences' {
        $index = [ordered]@{ NextSequence = 42; Entries = @() }

        $created = New-InventoryAssetId -Index $index

        $created.AssetId | Should -Be 'AST-0042'
    }
}

Describe 'Find-InventoryAssetByIdentity' {
    BeforeAll {
        $script:matchIndex = [ordered]@{
            NextSequence = 3
            Entries = @(
                [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'ABC12345'; AssetId = 'AST-0001' }
                [PSCustomObject]@{ Type = 'SystemUuid'; Value = 'ABC12345'; AssetId = 'AST-0002' }
            )
        }
    }

    It 'matches on the combination of Type and Value, never on Value alone' {
        $serialMatch = Find-InventoryAssetByIdentity -Index $script:matchIndex `
            -PreferredIdentifier ([PSCustomObject]@{ Type = 'SerialNumber'; Value = 'ABC12345' })
        $uuidMatch = Find-InventoryAssetByIdentity -Index $script:matchIndex `
            -PreferredIdentifier ([PSCustomObject]@{ Type = 'SystemUuid'; Value = 'ABC12345' })

        $serialMatch | Should -Be 'AST-0001'
        $uuidMatch | Should -Be 'AST-0002'
    }

    It 'never matches when PreferredIdentifier is null' {
        $result = Find-InventoryAssetByIdentity -Index $script:matchIndex -PreferredIdentifier $null

        $result | Should -BeNullOrEmpty
    }

    It 'returns null when there is no entry for that identity' {
        $result = Find-InventoryAssetByIdentity -Index $script:matchIndex `
            -PreferredIdentifier ([PSCustomObject]@{ Type = 'SerialNumber'; Value = 'DOES-NOT-EXIST' })

        $result | Should -BeNullOrEmpty
    }
}

Describe 'Import-InventoryAdministrationSession' {
    BeforeEach {
        $script:recordsDir = Join-Path $TestDrive ('records-' + [guid]::NewGuid().ToString('N'))
        $script:adminDir = Join-Path $TestDrive ('admin-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:recordsDir | Out-Null
    }

    It 'creates AST-0001 for a brand-new strongly identified asset and lists it under NuevosEquipos' {
        $record = New-FixtureCollectionRecord -CollectionId 'COL-1' -ComputerName 'PC-01'
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $record

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.NuevosEquipos).Count | Should -Be 1
        $result.NuevosEquipos[0].AssetId | Should -Be 'AST-0001'
        @($result.EquiposActualizados).Count | Should -Be 0
        @($result.PosiblesDuplicados).Count | Should -Be 0
        @($result.Conflictos).Count | Should -Be 0

        $store = Get-InventoryAssetStorePath -BasePath $script:adminDir
        $assetPath = Join-Path $store.AssetsDirectory 'AST-0001.json'
        Test-Path -LiteralPath $assetPath | Should -BeTrue

        $asset = Get-Content -LiteralPath $assetPath -Raw | ConvertFrom-Json
        $asset.AssetId | Should -Be 'AST-0001'
        $asset.SerialNumber | Should -Be 'ABC12345'
        $asset.Status | Should -Be 'New'
        @($asset.CollectionHistory).Count | Should -Be 1
        $asset.CollectionHistory[0].CollectionId | Should -Be 'COL-1'
    }

    It 'adds a manual field that did not exist before without creating a conflict (EquiposActualizados)' {
        $first = New-FixtureCollectionRecord -CollectionId 'COL-1' -ComputerName 'PC-01'
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $first
        Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir | Out-Null

        Remove-Item -LiteralPath (Get-ChildItem -LiteralPath $script:recordsDir -Filter '*-record.json').FullName -Force
        $second = New-FixtureCollectionRecord -CollectionId 'COL-2' -ComputerName 'PC-01' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $second

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.NuevosEquipos).Count | Should -Be 0
        @($result.EquiposActualizados).Count | Should -Be 1
        $result.EquiposActualizados[0].AssetId | Should -Be 'AST-0001'
        @($result.Conflictos).Count | Should -Be 0

        $store = Get-InventoryAssetStorePath -BasePath $script:adminDir
        $asset = Get-Content -LiteralPath (Join-Path $store.AssetsDirectory 'AST-0001.json') -Raw | ConvertFrom-Json
        @($asset.CollectionHistory).Count | Should -Be 2
        $fullNameField = @($asset.ManualFields) | Where-Object { $_.Key -eq 'assignment.user.fullName' }
        $fullNameField.Value | Should -Be 'Juan Pérez'
    }

    It 'includes the technician (from ManualFields[].CapturedBy) alongside SessionId in NuevosEquipos, EquiposActualizados and PosiblesDuplicados' {
        # SessionId groups equipment from the same visit; it is not the
        # technician's name — that only ever lives on ManualFields[].CapturedBy.
        # The administration report shows both, as separate columns.
        $newEquipment = New-FixtureCollectionRecord -CollectionId 'COL-NEW' -ComputerName 'PC-NEW' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez' -CapturedBy 'Técnico 01'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $newEquipment

        $noIdentity = New-FixtureCollectionRecord -CollectionId 'COL-DUP' -ComputerName 'PC-DUP' `
            -PreferredIdentifier $null -AssetStatus 'NeedsReview' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Otra Persona' -CapturedBy 'Técnico 02'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $noIdentity

        $firstResult = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        $firstResult.NuevosEquipos[0].Technician | Should -Be 'Técnico 01'
        $firstResult.PosiblesDuplicados[0].Technician | Should -Be 'Técnico 02'

        Remove-Item -LiteralPath (Get-ChildItem -LiteralPath $script:recordsDir -Filter '*-record.json').FullName -Force
        $updated = New-FixtureCollectionRecord -CollectionId 'COL-UPD' -ComputerName 'PC-NEW' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez' -CapturedBy 'Técnico 03'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $updated

        $secondResult = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        $secondResult.EquiposActualizados[0].Technician | Should -Be 'Técnico 03'
    }

    It 'sends a differing value for an already-captured key to Conflictos without overwriting it' {
        $first = New-FixtureCollectionRecord -CollectionId 'COL-1' -ComputerName 'PC-01' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $first
        Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir | Out-Null

        Remove-Item -LiteralPath (Get-ChildItem -LiteralPath $script:recordsDir -Filter '*-record.json').FullName -Force
        $second = New-FixtureCollectionRecord -CollectionId 'COL-2' -ComputerName 'PC-01' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Otra Persona'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $second

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.EquiposActualizados).Count | Should -Be 1
        @($result.Conflictos).Count | Should -Be 1
        $result.Conflictos[0].AssetId | Should -Be 'AST-0001'
        $result.Conflictos[0].Key | Should -Be 'assignment.user.fullName'
        $result.Conflictos[0].ValorActual | Should -Be 'Juan Pérez'
        $result.Conflictos[0].ValorNuevo | Should -Be 'Otra Persona'
        $result.Conflictos[0].CollectionId | Should -Be 'COL-2'

        $store = Get-InventoryAssetStorePath -BasePath $script:adminDir
        $asset = Get-Content -LiteralPath (Join-Path $store.AssetsDirectory 'AST-0001.json') -Raw | ConvertFrom-Json
        $fullNameField = @($asset.ManualFields) | Where-Object { $_.Key -eq 'assignment.user.fullName' }
        $fullNameField.Value | Should -Be 'Juan Pérez'
    }

    It 'does not create a conflict when the exact same value is re-submitted' {
        $first = New-FixtureCollectionRecord -CollectionId 'COL-1' -ComputerName 'PC-01' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $first
        Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir | Out-Null

        Remove-Item -LiteralPath (Get-ChildItem -LiteralPath $script:recordsDir -Filter '*-record.json').FullName -Force
        $second = New-FixtureCollectionRecord -CollectionId 'COL-2' -ComputerName 'PC-01' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $second

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.Conflictos).Count | Should -Be 0
        @($result.EquiposActualizados).Count | Should -Be 1
    }

    It 'sends a record without a strong identity to PosiblesDuplicados and creates no asset' {
        $record = New-FixtureCollectionRecord -CollectionId 'COL-NR' -ComputerName 'PC-NEEDSREVIEW' `
            -PreferredIdentifier $null -AssetStatus 'NeedsReview'
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $record

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.PosiblesDuplicados).Count | Should -Be 1
        $result.PosiblesDuplicados[0].CollectionId | Should -Be 'COL-NR'
        @($result.NuevosEquipos).Count | Should -Be 0

        $store = Get-InventoryAssetStorePath -BasePath $script:adminDir
        $index = Get-InventoryAssetIndex -IndexPath $store.IndexPath
        $index.NextSequence | Should -Be 1
        @($index.Entries).Count | Should -Be 0
    }

    It 'lists a record with collection errors under ErroresRecoleccion in addition to its normal tray' {
        $record = New-FixtureCollectionRecord -CollectionId 'COL-ERR' -ComputerName 'PC-ERR' `
            -Errors @('No se pudo leer el sensor de temperatura')
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $record

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.NuevosEquipos).Count | Should -Be 1
        @($result.ErroresRecoleccion).Count | Should -Be 1
        $result.ErroresRecoleccion[0].CollectionId | Should -Be 'COL-ERR'
        $result.ErroresRecoleccion[0].ComputerName | Should -Be 'PC-ERR'
        @($result.ErroresRecoleccion[0].Errors) | Should -Contain 'No se pudo leer el sensor de temperatura'
    }

    It 'surfaces malformed record files as SkippedFiles without aborting the import' {
        $record = New-FixtureCollectionRecord -CollectionId 'COL-OK' -ComputerName 'PC-OK'
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $record
        '{ not valid json' | Set-Content -LiteralPath (Join-Path $script:recordsDir 'PC-BAD-record.json') -Encoding UTF8

        $result = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        @($result.NuevosEquipos).Count | Should -Be 1
        @($result.SkippedFiles).Count | Should -Be 1
        $result.SkippedFiles[0].Path | Should -Match 'PC-BAD-record\.json'
    }

    It 'persists NextSequence across separate import runs instead of reusing ids' {
        $pc01 = New-FixtureCollectionRecord -CollectionId 'COL-1' -ComputerName 'PC-01' `
            -SerialNumber 'SERIAL-01' -PreferredIdentifier ([PSCustomObject]@{ Type = 'SerialNumber'; Value = 'SERIAL-01' })
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $pc01
        $firstRun = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir
        $firstRun.NuevosEquipos[0].AssetId | Should -Be 'AST-0001'

        Remove-Item -LiteralPath (Get-ChildItem -LiteralPath $script:recordsDir -Filter '*-record.json').FullName -Force
        $pc02 = New-FixtureCollectionRecord -CollectionId 'COL-2' -ComputerName 'PC-02' `
            -SerialNumber 'SERIAL-02' -PreferredIdentifier ([PSCustomObject]@{ Type = 'SerialNumber'; Value = 'SERIAL-02' })
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $pc02
        $secondRun = Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir

        $secondRun.NuevosEquipos[0].AssetId | Should -Be 'AST-0002'
    }
}

Describe 'Add-InventoryAssetManualReview' {
    BeforeEach {
        $script:recordsDir = Join-Path $TestDrive ('review-records-' + [guid]::NewGuid().ToString('N'))
        $script:adminDir = Join-Path $TestDrive ('review-admin-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:recordsDir | Out-Null

        $record = New-FixtureCollectionRecord -CollectionId 'COL-1' -ComputerName 'PC-01' `
            -ManualFields @((New-FixtureManualField -Key 'assignment.user.fullName' -Value 'Juan Pérez'))
        Write-FixtureRecordFile -Directory $script:recordsDir -Record $record
        Import-InventoryAdministrationSession -RecordsPath $script:recordsDir -AdministrationBasePath $script:adminDir | Out-Null
    }

    It 'applies a ManualReview correction, keeps the previous value in history, and returns the applied field' {
        $applied = Add-InventoryAssetManualReview -AdministrationBasePath $script:adminDir `
            -AssetId 'AST-0001' -Key 'assignment.user.fullName' -NewValue 'María Fernanda López Hernández' `
            -ReviewedBy 'Administrador TI' -Reason 'Nombre completo verificado con RRHH'

        $applied.Value | Should -Be 'María Fernanda López Hernández'
        $applied.Source | Should -Be 'ManualReview'
        $applied.Confidence | Should -Be 'Confirmed'
        $applied.CapturedBy | Should -Be 'Administrador TI'

        $store = Get-InventoryAssetStorePath -BasePath $script:adminDir
        $asset = Get-Content -LiteralPath (Join-Path $store.AssetsDirectory 'AST-0001.json') -Raw | ConvertFrom-Json

        $currentField = @($asset.ManualFields) | Where-Object { $_.Key -eq 'assignment.user.fullName' }
        $currentField.Value | Should -Be 'María Fernanda López Hernández'
        $currentField.Source | Should -Be 'ManualReview'

        @($asset.ReviewHistory).Count | Should -Be 1
        $asset.ReviewHistory[0].Key | Should -Be 'assignment.user.fullName'
        $asset.ReviewHistory[0].PreviousValue | Should -Be 'Juan Pérez'
        $asset.ReviewHistory[0].NewValue | Should -Be 'María Fernanda López Hernández'
        $asset.ReviewHistory[0].ReviewedBy | Should -Be 'Administrador TI'
        $asset.ReviewHistory[0].Reason | Should -Be 'Nombre completo verificado con RRHH'
    }

    It 'records a null PreviousValue when the key had no prior value' {
        Add-InventoryAssetManualReview -AdministrationBasePath $script:adminDir `
            -AssetId 'AST-0001' -Key 'asset.assetTag' -NewValue 'INV-2026-001' -ReviewedBy 'Administrador TI' | Out-Null

        $store = Get-InventoryAssetStorePath -BasePath $script:adminDir
        $asset = Get-Content -LiteralPath (Join-Path $store.AssetsDirectory 'AST-0001.json') -Raw | ConvertFrom-Json

        $asset.ReviewHistory[0].PreviousValue | Should -BeNullOrEmpty
        $asset.ReviewHistory[0].NewValue | Should -Be 'INV-2026-001'
    }

    It 'throws a clear error when the asset does not exist' {
        { Add-InventoryAssetManualReview -AdministrationBasePath $script:adminDir `
            -AssetId 'AST-9999' -Key 'assignment.user.fullName' -NewValue 'X' -ReviewedBy 'Y' } |
            Should -Throw
    }
}
