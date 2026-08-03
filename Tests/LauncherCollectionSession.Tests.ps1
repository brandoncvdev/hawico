Describe 'Start-Inventory.ps1 collection session forwarding' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Start-Inventory.ps1" -Raw
    }

    It 'reads the configured collection session once at startup' {
        $script | Should -Match '\$config\.CollectionSession'
        $script | Should -Match '\$collectionArguments'
    }

    It 'forwards the same context to full and quick inventory collection' {
        $script | Should -Match '&\s+\$collector\s+-Mode\s+Full\s+@collectionArguments'
        $script | Should -Match '&\s+\$collector\s+-Mode\s+Quick\s+@collectionArguments'
    }

    It 'builds a real CollectionSession entity once, before dispatching any inventory mode' {
        $script | Should -Match 'New-InventoryCollectionSession\.ps1'
        $script | Should -Match '\$collectionSession\s*=\s*New-InventoryCollectionSession'
    }

    It 'forwards only the resolved scalar session id to the collector' {
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*SessionId\s*=\s*\$collectionSession\.SessionId[^}]*\}'
        $script | Should -Not -Match '\$collectionArguments\s*=\s*@\{[^}]*OrganizationId'
    }
}
