Describe 'Collector_Hardware_Inventory.ps1 collection record contract' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Collector_Hardware_Inventory.ps1" -Raw
    }

    It 'accepts a collection session id and a technician for manual capture attribution, without organization or profile context' {
        $script | Should -Match '\[string\]\$SessionId'
        $script | Should -Match '\[AllowNull\(\)\]\[string\]\$Technician'
        $script | Should -Not -Match '\$OrganizationId'
        $script | Should -Not -Match '\$ProfileId'
    }

    It 'loads and creates the versioned collection record' {
        $script | Should -Match 'New-InventoryCollectionRecord\.ps1'
        $script | Should -Match 'New-InventoryCollectionRecord'
    }

    It 'loads the manual capture module and prompts only the configured manual fields' {
        $script | Should -Match 'New-InventoryManualCapture\.ps1'
        $script | Should -Match 'Read-InventoryManualCapture'
        $script | Should -Match '\$config\.ManualFields'
    }

    It 'accepts pre-resolved manual field keys from the launcher, falling back to config.json when absent' {
        $script | Should -Match '\[AllowNull\(\)\]\[string\[\]\]\$ManualFieldKeys'
    }

    It 'passes the captured manual fields into the collection record' {
        $script | Should -Match '-ManualFields\s+\$manualFields'
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
