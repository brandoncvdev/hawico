BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryCollectionRecord.ps1"
}

Describe 'New-InventoryAssetIdentity' {
    It 'prioritizes a valid serial number over the system UUID' {
        $identity = New-InventoryAssetIdentity `
            -Computer ([ordered]@{
                Hostname = 'PC-01'
                UUID = '4C4C4544-0038-4D10-8051-C4C04F503332'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
            }) `
            -BIOS ([ordered]@{ SerialNumber = ' abc-123 ' })

        $identity.SerialNumber | Should -Be 'ABC-123'
        $identity.SystemUuid | Should -Be '4C4C4544-0038-4D10-8051-C4C04F503332'
        $identity.PreferredIdentifier.Type | Should -Be 'SerialNumber'
        $identity.PreferredIdentifier.Value | Should -Be 'ABC-123'
        $identity.Status | Should -Be 'Identified'
    }

    It 'rejects manufacturer placeholders and falls back to a valid UUID' {
        $identity = New-InventoryAssetIdentity `
            -Computer ([ordered]@{
                Hostname = 'PC-02'
                UUID = '03000200-0400-0500-0006-000700080009'
                Manufacturer = 'Vendor'
                Model = 'Model'
            }) `
            -BIOS ([ordered]@{ SerialNumber = 'To Be Filled By O.E.M.' })

        $identity.SerialNumber | Should -BeNullOrEmpty
        $identity.PreferredIdentifier.Type | Should -Be 'SystemUuid'
        $identity.PreferredIdentifier.Value | Should -Be '03000200-0400-0500-0006-000700080009'
    }

    It 'requires review instead of using hostname as a strong identifier' {
        $identity = New-InventoryAssetIdentity `
            -Computer ([ordered]@{
                Hostname = 'PC-REUSED'
                UUID = '00000000-0000-0000-0000-000000000000'
                Manufacturer = 'Vendor'
                Model = 'Model'
            }) `
            -BIOS ([ordered]@{ SerialNumber = 'Default string' })

        $identity.PreferredIdentifier | Should -BeNullOrEmpty
        $identity.Status | Should -Be 'NeedsReview'
        $identity.ComputerName | Should -Be 'PC-REUSED'
    }
}

Describe 'New-InventoryCollectionRecord' {
    It 'wraps the existing technical evidence in an importable record with a scalar session id' {
        $collectedAt = [datetimeoffset]'2026-08-03T12:30:00-06:00'
        $inventory = [ordered]@{
            SchemaVersion = '2.0'
            Collection = [ordered]@{ CollectedAt = $collectedAt.ToString('o'); Mode = 'Full' }
            Computer = [ordered]@{
                Hostname = 'PC-01'
                UUID = '4C4C4544-0038-4D10-8051-C4C04F503332'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
            }
            BIOS = [ordered]@{ SerialNumber = 'ABC-123' }
            NetworkAdapters = @()
        }

        $record = New-InventoryCollectionRecord `
            -Inventory $inventory `
            -CollectionId 'COL-20260803-123000-ABC123' `
            -SessionId 'SES-20260803-AM-RH' `
            -CollectorVersion '0.5.0' `
            -CollectedAt $collectedAt

        $record.ContractVersion | Should -Be '1.0'
        $record.CollectionId | Should -Be 'COL-20260803-123000-ABC123'
        $record.SessionId | Should -Be 'SES-20260803-AM-RH'
        $record.Contains('Session') | Should -BeFalse
        $record.CollectedAt | Should -Be $collectedAt.ToString('o')
        $record.CollectorVersion | Should -Be '0.5.0'
        $record.Asset.PreferredIdentifier.Value | Should -Be 'ABC-123'
        [object]::ReferenceEquals($record.TechnicalData, $inventory) | Should -BeTrue
        @($record.ManualFields).Count | Should -Be 0
        @($record.Errors).Count | Should -Be 0
    }

    It 'defaults SessionId to SES-UNASSIGNED when no session context is supplied' {
        $inventory = [ordered]@{
            SchemaVersion = '2.0'
            Computer = [ordered]@{
                Hostname = 'PC-03'
                UUID = '4C4C4544-0038-4D10-8051-C4C04F503332'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
            }
            BIOS = [ordered]@{ SerialNumber = 'XYZ-999' }
        }

        $record = New-InventoryCollectionRecord -Inventory $inventory

        $record.SessionId | Should -Be 'SES-UNASSIGNED'
    }
}

Describe 'New-InventoryCollectionRecord collection identifiers' {
    BeforeAll {
        $collectedAt = [datetimeoffset]'2026-08-03T12:30:00-06:00'
        $expectedTimestamp = $collectedAt.ToString('yyyyMMdd-HHmmssfff')
    }

    It 'derives the collection id suffix from the first 8 characters of the preferred identifier' {
        $inventory = [ordered]@{
            SchemaVersion = '2.0'
            Computer = [ordered]@{
                Hostname = 'PC-10'
                UUID = '4C4C4544-0038-4D10-8051-C4C04F503332'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
            }
            BIOS = [ordered]@{ SerialNumber = 'ABCDEFGHIJK' }
        }

        $record = New-InventoryCollectionRecord -Inventory $inventory -CollectedAt $collectedAt

        $record.CollectionId | Should -Be ('COL-{0}-ABCDEFGH' -f $expectedTimestamp)
    }

    It 'keeps the full identifier as the suffix when it is shorter than 8 characters' {
        $inventory = [ordered]@{
            SchemaVersion = '2.0'
            Computer = [ordered]@{
                Hostname = 'PC-11'
                UUID = '4C4C4544-0038-4D10-8051-C4C04F503333'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
            }
            BIOS = [ordered]@{ SerialNumber = 'AB1' }
        }

        $record = New-InventoryCollectionRecord -Inventory $inventory -CollectedAt $collectedAt

        $record.CollectionId | Should -Be ('COL-{0}-AB1' -f $expectedTimestamp)
    }

    It 'falls back to an UNK-prefixed random suffix when the asset needs review' {
        $inventory = [ordered]@{
            SchemaVersion = '2.0'
            Computer = [ordered]@{
                Hostname = 'PC-REUSED'
                UUID = '00000000-0000-0000-0000-000000000000'
                Manufacturer = 'Vendor'
                Model = 'Model'
            }
            BIOS = [ordered]@{ SerialNumber = 'Default string' }
        }

        $record = New-InventoryCollectionRecord -Inventory $inventory -CollectedAt $collectedAt

        $expectedPrefix = 'COL-{0}-UNK' -f $expectedTimestamp
        $record.CollectionId | Should -Match ('^{0}[0-9A-F]{{5}}$' -f [regex]::Escape($expectedPrefix))
        $record.Asset.Status | Should -Be 'NeedsReview'
    }
}

Describe 'New-InventoryCollectionRecord assessments contract' {
    It 'exposes Assessments as an array, not an object, so future entries can be appended' {
        $inventory = [ordered]@{
            SchemaVersion = '2.0'
            Computer = [ordered]@{
                Hostname = 'PC-20'
                UUID = '4C4C4544-0038-4D10-8051-C4C04F503334'
                Manufacturer = 'Dell Inc.'
                Model = 'OptiPlex 7090'
            }
            BIOS = [ordered]@{ SerialNumber = 'ASSESS-001' }
        }

        $record = New-InventoryCollectionRecord -Inventory $inventory

        $record.Assessments.GetType().IsArray | Should -BeTrue
        @($record.Assessments).Count | Should -Be 0
    }
}
