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
            [AllowNull()][object]$PreferredIdentifier = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'ABC12345' },
            [AllowNull()][string]$CollectedAt = '2026-08-03T12:30:00-06:00',
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
            ),
            [AllowNull()][object[]]$StorageFindings = @()
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
                PreferredIdentifier = $PreferredIdentifier
                Status = $AssetStatus
            }
            SessionId = $SessionId
            CollectedAt = $CollectedAt
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
                StorageFindings = $StorageFindings
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

    It 'leaves PC / LAPTOP null (no chassis detector implemented yet)' {
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord)

        $row.'PC / LAPTOP' | Should -BeNullOrEmpty
    }

    It 'leaves CANTIDAD REQUERIDA (CAMBIO) and CAMBIO DE EQUIPO null when there are no storage findings' {
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord -StorageFindings @())

        $row.'CANTIDAD REQUERIDA (CAMBIO)' | Should -BeNullOrEmpty
        $row.'CAMBIO DE EQUIPO' | Should -BeNullOrEmpty
    }

    It 'leaves CANTIDAD REQUERIDA (CAMBIO) and CAMBIO DE EQUIPO null when only Medium-severity storage findings exist' {
        # Medium findings (reallocated sectors, elevated temperature, HDD
        # service-life warning) are monitor-and-watch signals, not a
        # replacement recommendation — only Critical/High should trigger.
        $findings = @(
            [PSCustomObject]@{ Id = 'STO-009'; Category = 'Storage'; Severity = 'Medium'; Title = 'Reallocated sectors detected' }
        )
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord -StorageFindings $findings)

        $row.'CANTIDAD REQUERIDA (CAMBIO)' | Should -BeNullOrEmpty
        $row.'CAMBIO DE EQUIPO' | Should -BeNullOrEmpty
    }

    It 'fills CANTIDAD REQUERIDA (CAMBIO) with 1 and CAMBIO DE EQUIPO with the finding titles when a Critical storage finding exists' {
        $findings = @(
            [PSCustomObject]@{ Id = 'STO-006'; Category = 'Storage'; Severity = 'Critical'; Title = 'Storage device failed SMART self-assessment' }
        )
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord -StorageFindings $findings)

        # Get-StorageSmartSummary aggregates worst-of across every physical
        # disk, so a finding never identifies which specific disk triggered
        # it — 1 ("replace the flagged unit") is the honest ceiling of what
        # this data supports, not an invented per-disk count.
        $row.'CANTIDAD REQUERIDA (CAMBIO)' | Should -Be 1
        $row.'CAMBIO DE EQUIPO' | Should -Be 'Storage device failed SMART self-assessment'
    }

    It 'fills CANTIDAD REQUERIDA (CAMBIO) with 1 and joins titles when a High-severity storage finding exists alongside others' {
        $findings = @(
            [PSCustomObject]@{ Id = 'STO-010'; Category = 'Storage'; Severity = 'High'; Title = 'High storage wear level' }
            [PSCustomObject]@{ Id = 'STO-011'; Category = 'Storage'; Severity = 'Medium'; Title = 'Elevated storage temperature' }
        )
        $row = ConvertTo-InventoryWorkbookRow -Record (New-FixtureRecord -StorageFindings $findings)

        $row.'CANTIDAD REQUERIDA (CAMBIO)' | Should -Be 1
        $row.'CAMBIO DE EQUIPO' | Should -Be 'High storage wear level'
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

Describe 'Get-InventoryFirstNetworkAdapterWithData' {
    # Real reported bug: on a machine with Hyper-V enabled, "vEthernet
    # (Default Switch)" (Hyper-V's built-in NAT virtual switch) and a real
    # physical "Ethernet" NIC both had IPv4 addresses, and this function
    # returned whichever one happened to be first in the array — sometimes
    # the virtual adapter's IP/MAC ended up in the consolidated Excel.
    It 'returns the physical adapter''s IP/MAC over the Hyper-V virtual adapter''s, regardless of array order' {
        $virtualAdapter = [PSCustomObject]@{
            InterfaceAlias = 'vEthernet (Default Switch)'
            AdapterType    = 'Virtual'
            MACAddress     = '00-15-5D-01-02-03'
            IPv4Addresses  = @('172.28.240.1')
        }
        $physicalAdapter = [PSCustomObject]@{
            InterfaceAlias = 'Ethernet'
            AdapterType    = 'Ethernet'
            MACAddress     = '00-11-22-33-44-55'
            IPv4Addresses  = @('192.168.1.50')
        }

        $virtualFirst = Get-InventoryFirstNetworkAdapterWithData -NetworkAdapters @($virtualAdapter, $physicalAdapter)
        $virtualFirst.IPv4Address | Should -Be '192.168.1.50'
        $virtualFirst.MACAddress | Should -Be '00-11-22-33-44-55'

        $virtualLast = Get-InventoryFirstNetworkAdapterWithData -NetworkAdapters @($physicalAdapter, $virtualAdapter)
        $virtualLast.IPv4Address | Should -Be '192.168.1.50'
        $virtualLast.MACAddress | Should -Be '00-11-22-33-44-55'
    }

    It 'falls back to a virtual adapter''s IP/MAC when no physical adapter has any IP data at all' {
        $virtualAdapter = [PSCustomObject]@{
            InterfaceAlias = 'vEthernet (Default Switch)'
            AdapterType    = 'Virtual'
            MACAddress     = '00-15-5D-01-02-03'
            IPv4Addresses  = @('172.28.240.1')
        }
        $physicalNoIp = [PSCustomObject]@{
            InterfaceAlias = 'Ethernet'
            AdapterType    = 'Ethernet'
            MACAddress     = '00-11-22-33-44-55'
            IPv4Addresses  = @()
        }

        $result = Get-InventoryFirstNetworkAdapterWithData -NetworkAdapters @($physicalNoIp, $virtualAdapter)

        $result.IPv4Address | Should -Be '172.28.240.1'
        $result.MACAddress | Should -Be '00-15-5D-01-02-03'
    }

    It 'still works when AdapterType is absent on the adapter objects (backward compatibility)' {
        $adapter = [PSCustomObject]@{
            InterfaceAlias = 'Ethernet'
            MACAddress     = '00-11-22-33-44-55'
            IPv4Addresses  = @('192.168.1.50')
        }

        $result = Get-InventoryFirstNetworkAdapterWithData -NetworkAdapters @($adapter)

        $result.IPv4Address | Should -Be '192.168.1.50'
        $result.MACAddress | Should -Be '00-11-22-33-44-55'
    }

    It 'returns $null when there are no adapters with IP data at all' {
        Get-InventoryFirstNetworkAdapterWithData -NetworkAdapters @() | Should -BeNullOrEmpty
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

Describe 'Get-InventoryLatestHostRecord' {
    # "Already collected" warning (Start-Inventory.ps1): before dispatching a
    # new collection, the launcher looks in the host's own Output\<Hostname>\
    # subfolder for the most recent prior *-record.json, so the technician can
    # be warned instead of silently re-collecting.
    BeforeEach {
        $script:hostDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'returns null when the host output directory does not exist yet (first-ever collection for this computer)' {
        Get-InventoryLatestHostRecord -HostOutputDirectory $script:hostDir | Should -BeNullOrEmpty
    }

    It 'returns null when the host output directory exists but has no record files' {
        New-Item -ItemType Directory -Path $script:hostDir -Force | Out-Null

        Get-InventoryLatestHostRecord -HostOutputDirectory $script:hostDir | Should -BeNullOrEmpty
    }

    It 'returns the single record when only one exists' {
        New-Item -ItemType Directory -Path $script:hostDir -Force | Out-Null
        (New-FixtureRecord -CollectionId 'COL-ONLY') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:hostDir 'PC-01-20260803-record.json') -Encoding UTF8

        $result = Get-InventoryLatestHostRecord -HostOutputDirectory $script:hostDir

        $result.CollectionId | Should -Be 'COL-ONLY'
    }

    It 'returns the most recently collected record when several exist for the same host (repeat collections)' {
        New-Item -ItemType Directory -Path $script:hostDir -Force | Out-Null
        (New-FixtureRecord -CollectionId 'COL-OLDER' -CollectedAt '2026-08-01T09:00:00-06:00') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:hostDir 'PC-01-20260801-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-NEWER' -CollectedAt '2026-08-03T09:00:00-06:00') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:hostDir 'PC-01-20260803-record.json') -Encoding UTF8

        $result = Get-InventoryLatestHostRecord -HostOutputDirectory $script:hostDir

        $result.CollectionId | Should -Be 'COL-NEWER'
    }

    It 'is order-independent — same result regardless of which file is discovered first' {
        New-Item -ItemType Directory -Path $script:hostDir -Force | Out-Null
        (New-FixtureRecord -CollectionId 'COL-NEWER' -CollectedAt '2026-08-03T09:00:00-06:00') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:hostDir 'AAA-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-OLDER' -CollectedAt '2026-08-01T09:00:00-06:00') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $script:hostDir 'ZZZ-record.json') -Encoding UTF8

        $result = Get-InventoryLatestHostRecord -HostOutputDirectory $script:hostDir

        $result.CollectionId | Should -Be 'COL-NEWER'
    }
}

Describe 'Get-InventoryHostHistoryDefaultValues' {
    # Prefill (Start-Inventory.ps1): unlike -PresetValues (silent skip), the
    # prior record's values become visible, editable defaults for exactly 3
    # keys — collection.observations is deliberately never defaulted, notes
    # go stale and must always be captured fresh.
    It 'returns an empty hashtable when there is no prior record' {
        $result = Get-InventoryHostHistoryDefaultValues -PriorRecord $null -PresetValues @{}

        @($result.Keys).Count | Should -Be 0
    }

    It 'extracts exactly the 3 documented keys from the prior record''s ManualFields' {
        $priorRecord = New-FixtureRecord -ManualFields @(
            [PSCustomObject]@{ Key = 'assignment.user.fullName'; Value = 'Juan Pérez' }
            [PSCustomObject]@{ Key = 'assignment.organizationUnitId'; Value = 'Dirección Administrativa' }
            [PSCustomObject]@{ Key = 'assignment.departmentUnitId'; Value = 'Recursos Humanos' }
            [PSCustomObject]@{ Key = 'collection.observations'; Value = 'Nota de la visita anterior' }
        )

        $result = Get-InventoryHostHistoryDefaultValues -PriorRecord $priorRecord -PresetValues @{}

        $result['assignment.user.fullName'] | Should -Be 'Juan Pérez'
        $result['assignment.organizationUnitId'] | Should -Be 'Dirección Administrativa'
        $result['assignment.departmentUnitId'] | Should -Be 'Recursos Humanos'
    }

    It 'never defaults collection.observations — notes must always be captured fresh' {
        $priorRecord = New-FixtureRecord -ManualFields @(
            [PSCustomObject]@{ Key = 'collection.observations'; Value = 'Nota de la visita anterior' }
        )

        $result = Get-InventoryHostHistoryDefaultValues -PriorRecord $priorRecord -PresetValues @{}

        $result.ContainsKey('collection.observations') | Should -BeFalse
    }

    It 'never overrides an already-resolved visit-level PresetValues entry for the same key' {
        $priorRecord = New-FixtureRecord -ManualFields @(
            [PSCustomObject]@{ Key = 'assignment.organizationUnitId'; Value = 'Dirección Anterior' }
        )

        $result = Get-InventoryHostHistoryDefaultValues -PriorRecord $priorRecord `
            -PresetValues @{ 'assignment.organizationUnitId' = 'Dirección Actual' }

        $result.ContainsKey('assignment.organizationUnitId') | Should -BeFalse
    }

    It 'omits a key that has no value at all in the prior record' {
        $priorRecord = New-FixtureRecord -ManualFields @(
            [PSCustomObject]@{ Key = 'assignment.user.fullName'; Value = 'Juan Pérez' }
        )

        $result = Get-InventoryHostHistoryDefaultValues -PriorRecord $priorRecord -PresetValues @{}

        $result.ContainsKey('assignment.organizationUnitId') | Should -BeFalse
        $result.ContainsKey('assignment.departmentUnitId') | Should -BeFalse
    }
}

Describe 'Get-InventoryDeduplicatedRecords' {
    # Bugfix: re-collecting the same physical computer (technician re-running
    # "Generar inventario completo", or a second visit) creates a brand-new
    # *-record.json every time (by design — kept as an audit trail). Without
    # this, every one of those files became its own row in the Inventario
    # sheet — the same computer showing up once per collection instead of
    # once per computer. Same identity rule Modules/InventoryAdministration.ps1
    # already enforces (doc10-Asset-Identity.md): only records sharing a
    # strong identity (SerialNumber or SystemUuid, matched on Type AND Value
    # together) are ever merged; anything without one is left exactly as-is.
    # Each identifier is built fresh inside its own It block (not shared at
    # Describe scope) to stay clear of Pester's discovery-vs-run phase
    # variable-scoping rules.

    It 'keeps only the most recently collected record when two share the same strong identity' {
        $sameSerial = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'SAME-001' }
        $older = New-FixtureRecord -CollectionId 'COL-OLDER' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-01T09:00:00-06:00'
        $newer = New-FixtureRecord -CollectionId 'COL-NEWER' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-03T09:00:00-06:00'

        $result = Get-InventoryDeduplicatedRecords -Records @($older, $newer)

        @($result).Count | Should -Be 1
        $result[0].CollectionId | Should -Be 'COL-NEWER'
    }

    It 'is order-independent — the same result whether the newer record appears first or last' {
        $sameSerial = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'SAME-001' }
        $older = New-FixtureRecord -CollectionId 'COL-OLDER' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-01T09:00:00-06:00'
        $newer = New-FixtureRecord -CollectionId 'COL-NEWER' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-03T09:00:00-06:00'

        $result = Get-InventoryDeduplicatedRecords -Records @($newer, $older)

        @($result).Count | Should -Be 1
        $result[0].CollectionId | Should -Be 'COL-NEWER'
    }

    It 'keeps records with different identities as separate rows' {
        $sameSerial = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'SAME-001' }
        $otherSerial = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'OTHER-002' }
        $first = New-FixtureRecord -CollectionId 'COL-A' -PreferredIdentifier $sameSerial
        $second = New-FixtureRecord -CollectionId 'COL-B' -PreferredIdentifier $otherSerial

        $result = Get-InventoryDeduplicatedRecords -Records @($first, $second)

        @($result).Count | Should -Be 2
        (@($result) | ForEach-Object { $_.CollectionId }) | Should -Contain 'COL-A'
        (@($result) | ForEach-Object { $_.CollectionId }) | Should -Contain 'COL-B'
    }

    It 'never merges records with no strong identity, even if there is more than one' {
        $first = New-FixtureRecord -CollectionId 'COL-NR-1' -PreferredIdentifier $null -AssetStatus 'NeedsReview'
        $second = New-FixtureRecord -CollectionId 'COL-NR-2' -PreferredIdentifier $null -AssetStatus 'NeedsReview'

        $result = Get-InventoryDeduplicatedRecords -Records @($first, $second)

        @($result).Count | Should -Be 2
    }

    It 'returns an array, not a bare scalar, when deduplication collapses everything to exactly one record' {
        $sameSerial = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'SAME-001' }
        $older = New-FixtureRecord -CollectionId 'COL-OLDER' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-01T09:00:00-06:00'
        $newer = New-FixtureRecord -CollectionId 'COL-NEWER' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-03T09:00:00-06:00'

        $result = Get-InventoryDeduplicatedRecords -Records @($older, $newer)

        $result.GetType().IsArray | Should -BeTrue
    }

    It 'returns an empty array without throwing when Records is null or empty' {
        $fromNull = Get-InventoryDeduplicatedRecords -Records $null
        $fromEmpty = Get-InventoryDeduplicatedRecords -Records @()

        $fromNull.GetType().IsArray | Should -BeTrue
        $fromNull.Count | Should -Be 0
        $fromEmpty.Count | Should -Be 0
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
        (New-FixtureRecord -CollectionId 'COL-EXPORT-2' -AssetStatus 'NeedsReview' -PreferredIdentifier $null -SessionId 'SES-UNASSIGNED' -ManualFields @()) |
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

        (New-FixtureRecord -CollectionId 'COL-PENDING-1' -AssetStatus 'NeedsReview' -PreferredIdentifier $null -SessionId 'SES-UNASSIGNED' -ManualFields @()) |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-PENDING-2' -AssetStatus 'NeedsReview' -PreferredIdentifier $null -SessionId 'SES-UNASSIGNED' -ManualFields @()) |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-02-record.json') -Encoding UTF8

        $outputPath = Join-Path $TestDrive 'Consolidado-PendingCount.xlsx'

        $result = Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath

        $result.PendingCount | Should -Be 2

        $pendientesRows = @(Import-Excel -Path $outputPath -WorksheetName 'Pendientes')
        $pendientesRows.Count | Should -Be 2
    }

    It 'shows only one Inventario row when the same computer was collected more than once (bugfix: repeated "Generar inventario completo" runs used to duplicate rows)' {
        $recordsDir = Join-Path $TestDrive 'export-same-computer-twice'
        New-Item -ItemType Directory -Path $recordsDir -Force | Out-Null

        $sameSerial = [PSCustomObject]@{ Type = 'SerialNumber'; Value = 'REPEAT-001' }
        (New-FixtureRecord -CollectionId 'COL-FIRST-VISIT' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-01T09:00:00-06:00') |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-20260801-record.json') -Encoding UTF8
        (New-FixtureRecord -CollectionId 'COL-SECOND-VISIT' -PreferredIdentifier $sameSerial -CollectedAt '2026-08-03T09:00:00-06:00') |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-20260803-record.json') -Encoding UTF8

        $outputPath = Join-Path $TestDrive 'Consolidado-SameComputer.xlsx'

        $result = Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath

        $result.RecordCount | Should -Be 1

        $inventoryRows = @(Import-Excel -Path $outputPath -WorksheetName 'Inventario')
        $inventoryRows.Count | Should -Be 1
    }

    It 'regenerates the workbook from scratch instead of accumulating stale sheets' {
        $recordsDir = Join-Path $TestDrive 'export-regen'
        New-Item -ItemType Directory -Path $recordsDir -Force | Out-Null
        (New-FixtureRecord -CollectionId 'COL-REGEN') | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-01-record.json') -Encoding UTF8

        $outputPath = Join-Path $TestDrive 'Consolidado-Regen.xlsx'

        Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath | Out-Null
        $firstRun = @(Import-Excel -Path $outputPath -WorksheetName 'Inventario')

        # A genuinely different second computer (distinct identity), not a
        # re-collection of the same one — otherwise Get-InventoryDeduplicatedRecords
        # would correctly collapse them to 1 row, defeating this test's real
        # purpose (checking regeneration, not deduplication).
        (New-FixtureRecord -CollectionId 'COL-REGEN-2' -PreferredIdentifier ([PSCustomObject]@{ Type = 'SerialNumber'; Value = 'REGEN-002' })) |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $recordsDir 'PC-02-record.json') -Encoding UTF8
        Export-InventoryConsolidatedWorkbook -RecordsPath $recordsDir -OutputPath $outputPath | Out-Null
        $secondRun = @(Import-Excel -Path $outputPath -WorksheetName 'Inventario')

        $firstRun.Count | Should -Be 1
        $secondRun.Count | Should -Be 2
    }
}
