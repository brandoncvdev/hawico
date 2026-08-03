Describe 'Collector_Hardware_Inventory.ps1 collection record contract' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Collector_Hardware_Inventory.ps1" -Raw
    }

    It 'accepts a collection session id without requiring organization or technician context' {
        $script | Should -Match '\[string\]\$SessionId'
        $script | Should -Not -Match '\$OrganizationId'
        $script | Should -Not -Match '\$ProfileId'
        $script | Should -Not -Match '\$Technician'
    }

    It 'loads and creates the versioned collection record' {
        $script | Should -Match 'New-InventoryCollectionRecord\.ps1'
        $script | Should -Match 'New-InventoryCollectionRecord'
    }

    It 'writes a distinct importable record without replacing legacy evidence' {
        $script | Should -Match '-record\.json'
        $script | Should -Match 'RecordJsonPath'
        $script | Should -Match '\$inventory\s*\|\s*ConvertTo-Json'
        $script | Should -Match '\$collectionRecord\s*\|\s*ConvertTo-Json'
    }

    It 'resolves the collector version from the shared manifest instead of a hardcoded literal' {
        $script | Should -Match 'Get-CollectorVersion'
        $script | Should -Not -Match "'0\.5\.0'"
        $script | Should -Not -Match '"0\.5\.0"'
    }
}
