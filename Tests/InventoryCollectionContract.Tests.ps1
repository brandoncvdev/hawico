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

    It 'accepts pre-resolved organization units for the catalog-based organizationUnitId selection' {
        $script | Should -Match '\[AllowNull\(\)\]\[object\[\]\]\$OrganizationUnits'
        $script | Should -Match '-OrganizationUnits'
    }

    It 'resolves manual field keys and organization units through testable Modules/Common.ps1 functions instead of inline array-collapse-prone logic' {
        $script | Should -Match 'Resolve-InventoryManualFieldKeys'
        $script | Should -Match 'Resolve-InventoryOrganizationUnits'
    }

    It 'accepts pre-resolved independent department units for the flat/independent departmentUnitId selection' {
        # doc07-Catalog-System.md flat/independent mode: Resolve-InventoryOrganizationUnits
        # is a generic array-shape resolver (not specific to any one catalog),
        # reused here for -DepartmentUnits instead of a duplicate function.
        $script | Should -Match '\[AllowNull\(\)\]\[object\[\]\]\$DepartmentUnits'
        $script | Should -Match 'Resolve-InventoryOrganizationUnits\s+-PassedUnits\s+\$DepartmentUnits'
        $script | Should -Match '-DepartmentUnits\s+\$resolvedDepartmentUnits'
    }

    It 'accepts preset manual field values decided once for the whole visit (doc07 "Reutilización durante visita")' {
        $script | Should -Match '\[AllowNull\(\)\]\[hashtable\]\$PresetManualFieldValues'
        $script | Should -Match '-PresetValues\s+\$PresetManualFieldValues'
    }

    It 'accepts readable field labels for the manual capture prompts instead of raw dotted keys' {
        $script | Should -Match '\[AllowNull\(\)\]\[hashtable\]\$FieldLabels'
        $script | Should -Match '-FieldLabels\s+\$FieldLabels'
    }

    It 'comma-guards the empty-manual-fields fallback branch against the if-expression array-collapse bug' {
        # $manualFields = if (...) { Read-InventoryManualCapture ... } else { @() }
        # The else branch must be ,@() — a bare @() here collapses to $null when
        # this branch is taken, since `$var = if (...) {...} else {...}` routes
        # each branch's trailing value through the same output-stream boundary
        # a `return` does (confirmed empirically; broke the collector for real
        # on Windows PowerShell 5.1 for a different branch in this same file).
        $script | Should -Match 'else\s*\{\s*,@\(\)\s*\}'
    }

    It 'passes the captured manual fields into the collection record' {
        $script | Should -Match '-ManualFields\s+\$manualFields'
    }

    It 'passes the captured manual fields into the HTML report as well' {
        $script | Should -Match 'New-InventoryHtml\s+-Inventory\s+\$inventory\s+-Path\s+\$htmlPath\s+-ManualFields\s+\$manualFields'
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
