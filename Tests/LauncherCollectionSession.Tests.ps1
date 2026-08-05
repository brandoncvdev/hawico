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

    It 'forwards the visit-resolved technician (not the raw session technician) alongside the session id' {
        # doc07-Catalog-System.md "Reutilización durante visita": the
        # technician can be confirmed/overridden interactively once per
        # visit via Read-InventoryVisitContext, so $collectionArguments
        # forwards $visitTechnician, not $collectionSession.Technician directly.
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*SessionId\s*=\s*\$collectionSession\.SessionId[^}]*Technician\s*=\s*\$visitTechnician[^}]*\}'
    }

    It 'resolves manual field keys from the active organization profile, falling back to config.json' {
        $script | Should -Match 'InventoryOrganizationPackage\.ps1'
        $script | Should -Match 'Get-InventoryProfileManualFields'
        $script | Should -Match '-OrganizationId\s+\$collectionSession\.OrganizationId'
        $script | Should -Match '-ProfileId\s+\$collectionSession\.ProfileId'
        $script | Should -Match '-FallbackFields\s+@\(\$config\.ManualFields\)'
    }

    It 'forwards the resolved manual field keys to the collector' {
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*ManualFieldKeys\s*=\s*\$manualFieldKeys[^}]*\}'
    }

    It 'loads the organization unit catalog and forwards it to the collector' {
        $script | Should -Match 'Get-InventoryOrganizationUnitCatalog'
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*OrganizationUnits\s*=\s*\$organizationUnits[^}]*\}'
    }

    It 'loads the independent department unit catalog and forwards it to the collector' {
        # doc07-Catalog-System.md flat/independent mode: institutions whose
        # Dirección and Departamento have no reliable parent-child
        # relationship ship a second, independent catalogs/departments.json.
        $script | Should -Match 'Get-InventoryDepartmentUnitCatalog'
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*DepartmentUnits\s*=\s*\$departmentUnits[^}]*\}'
    }

    It 'resolves a reusable visit context (Técnico/Dirección/Departamento) once, before the main menu loop' {
        # doc07-Catalog-System.md "Reutilización durante visita": the
        # technician confirms/overrides these once for a whole batch of
        # machines instead of being asked on every single collection.
        $script | Should -Match 'Modules\\New-InventoryManualCapture\.ps1'
        $script | Should -Match 'function\s+Read-InventoryVisitContext'
        $script | Should -Match '\$visitContext\s*=\s*Read-InventoryVisitContext'
        $script | Should -Match '\$visitTechnician\s*=\s*\$visitContext\.Technician'
        $script | Should -Match '\$visitPresetValues\s*=\s*\$visitContext\.PresetValues'
        # Resolved before the do/while menu loop starts, not inside it.
        $script | Should -Match '(?s)\$visitContext\s*=\s*Read-InventoryVisitContext.*?\bdo\s*\{'
    }

    It 'forwards the visit-resolved preset manual field values to the collector' {
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*PresetManualFieldValues\s*=\s*\$visitPresetValues[^}]*\}'
    }

    It 'offers a menu option to change the visit context (Dirección/Departamento/Técnico) without restarting' {
        $script | Should -Match '"9\.\s+Cambiar contexto de esta visita'
        $script | Should -Match '(?s)"9"\s*\{.*?Read-InventoryVisitContext'
    }

    It 'auto-detects the organization package when config.json does not pin one explicitly, before building the session' {
        $script | Should -Match 'Get-InventoryAutoDetectedOrganizationId'
        # Must run before New-InventoryCollectionSession is called, so an
        # auto-detected OrganizationId actually reaches $collectionSession
        # instead of arriving too late to matter.
        $script | Should -Match '(?s)Get-InventoryAutoDetectedOrganizationId.*?New-InventoryCollectionSession\s+@sessionParameters'
    }

    It 'builds readable field labels combining the hardcoded defaults with the active organization''s custom-fields.json' {
        # "Labels legibles" task: the technician sees "Dirección" / "Número
        # patrimonial" / etc. instead of the raw assignment.organizationUnitId
        # / asset.assetTag dotted keys, both in the per-machine capture and in
        # the reusable visit-context prompts.
        $script | Should -Match 'Get-InventoryCustomFieldDefinitions'
        $script | Should -Match '\$fieldLabels\s*='
        $script | Should -Match '\$collectionArguments\s*=\s*@\{[^}]*FieldLabels\s*=\s*\$fieldLabels[^}]*\}'
    }

    It 'forwards the readable field labels into the reusable visit context' {
        $script | Should -Match '(?s)function\s+Read-InventoryVisitContext\s*\{.*?\$FieldLabels'
        $script | Should -Match '(?s)\$visitContext\s*=\s*Read-InventoryVisitContext.*?-FieldLabels\s+\$fieldLabels'
    }

    It 'searches recursively for the last report/diagnostic, since outputs now live in per-hostname subfolders' {
        # Collector_Hardware_Inventory.ps1/Collector_Windows_HealthCheck.ps1
        # write into $outputDir\<Hostname>\... now (Get-InventoryHostOutputDirectory),
        # not flat in $outputDir — without -Recurse these menu options would
        # silently find nothing.
        $script | Should -Match 'Get-ChildItem\s+-LiteralPath\s+\$output\s+-Filter\s+"\*\.html"\s+-Recurse'
        $script | Should -Match 'Get-ChildItem\s+-LiteralPath\s+\$output\s+-Filter\s+"\*-health\.html"\s+-Recurse'
    }

    It 'auto-generates a real SessionId when config.json does not pin one explicitly, before building the session' {
        # Bugfix: entering a Técnico via the visit-context prompt used to
        # leave the administration "Nuevos equipos" table showing
        # SES-UNASSIGNED anyway, since SessionId and Technician were resolved
        # completely independently. Same pattern as the OrganizationId
        # auto-detection right above: an explicit config.json SessionId
        # always wins over auto-generation.
        $script | Should -Match 'Test-InventorySessionIdUnassigned'
        $script | Should -Match 'Get-InventoryAutoGeneratedSessionId'
        $script | Should -Match '(?s)Test-InventorySessionIdUnassigned.*?New-InventoryCollectionSession\s+@sessionParameters'
    }
}
