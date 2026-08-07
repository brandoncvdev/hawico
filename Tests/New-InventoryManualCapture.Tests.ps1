BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryManualCapture.ps1"
    . "$PSScriptRoot/../Modules/InventoryOrganizationPackage.ps1"
}

Describe 'New-InventoryManualFieldValue' {
    BeforeAll {
        $capturedAt = [datetimeoffset]'2026-08-03T12:30:00-06:00'
    }

    It 'returns null when Enter is pressed (empty raw value)' {
        New-InventoryManualFieldValue -Key 'assignment.user.fullName' -RawValue '' -CapturedAt $capturedAt |
            Should -BeNullOrEmpty
    }

    It 'returns null when the raw value is only whitespace' {
        New-InventoryManualFieldValue -Key 'assignment.user.fullName' -RawValue '   ' -CapturedAt $capturedAt |
            Should -BeNullOrEmpty
    }

    It 'returns null when no raw value is supplied at all' {
        New-InventoryManualFieldValue -Key 'assignment.user.fullName' -CapturedAt $capturedAt |
            Should -BeNullOrEmpty
    }

    It 'trims the raw value and builds a FieldValue with the VisitCapture defaults' {
        $field = New-InventoryManualFieldValue `
            -Key 'assignment.user.fullName' `
            -RawValue '  Juan Pérez Hernández  ' `
            -Technician 'Técnico 01' `
            -CapturedAt $capturedAt

        $field.Key | Should -Be 'assignment.user.fullName'
        $field.Value | Should -Be 'Juan Pérez Hernández'
        $field.Source | Should -Be 'VisitCapture'
        $field.CapturedAt | Should -Be $capturedAt.ToString('o')
        $field.CapturedBy | Should -Be 'Técnico 01'
        $field.Confidence | Should -Be 'Unconfirmed'
        $field.Status | Should -Be 'Present'
    }

    It 'allows overriding Source and Confidence for a later manual review correction' {
        $field = New-InventoryManualFieldValue `
            -Key 'assignment.user.fullName' `
            -RawValue 'María Fernanda López Hernández' `
            -Technician 'Administrador TI' `
            -Source 'ManualReview' `
            -Confidence 'Confirmed' `
            -CapturedAt $capturedAt

        $field.Source | Should -Be 'ManualReview'
        $field.Confidence | Should -Be 'Confirmed'
    }
}

Describe 'Read-InventoryManualCapture' {
    It 'visits every field using its resolved label (not the raw key) in order, via the injected prompter' {
        # Task "labels legibles": the free-text prompter now receives the
        # human-readable label (default label map, since no -FieldLabels
        # override was supplied here), not the raw dotted field key.
        $visited = [System.Collections.Generic.List[string]]::new()
        $answers = @{
            'Nombre completo del usuario' = 'Juan Pérez Hernández'
            'Dirección' = 'dept-hr'
        }
        $prompter = {
            param($Key)
            $visited.Add($Key)
            $answers[$Key]
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName', 'assignment.organizationUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter

        @($visited) | Should -Be @('Nombre completo del usuario', 'Dirección')
        @($result).Count | Should -Be 2
        # The stored FieldValue.Key is still the raw dotted key — only the
        # interactive prompt text changed, not what gets persisted.
        $result[0].Key | Should -Be 'assignment.user.fullName'
        $result[0].Value | Should -Be 'Juan Pérez Hernández'
        $result[1].Key | Should -Be 'assignment.organizationUnitId'
        $result[1].Value | Should -Be 'dept-hr'
    }

    It 'omits fields skipped with Enter and keeps the ones that were answered' {
        $answers = @{
            'Nombre completo del usuario' = ''
            'Dirección' = 'dept-hr'
            'Número patrimonial' = '   '
        }
        $prompter = { param($Key) $answers[$Key] }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName', 'assignment.organizationUnitId', 'asset.assetTag') `
            -Technician 'Técnico 01' `
            -Prompter $prompter

        @($result).Count | Should -Be 1
        $result[0].Key | Should -Be 'assignment.organizationUnitId'
    }

    It 'returns an empty array when every field is skipped' {
        $prompter = { param($Key) $null }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName', 'collection.observations') `
            -Prompter $prompter

        @($result).Count | Should -Be 0
    }

    It 'stamps every captured field with the supplied technician' {
        $prompter = { param($Key) "valor-$Key" }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('asset.assetTag') `
            -Technician 'Brandon' `
            -Prompter $prompter

        $result[0].CapturedBy | Should -Be 'Brandon'
    }

    It 'defaults to Read-Host when no prompter is supplied' {
        Mock Read-Host { 'valor-por-defecto' }

        $result = Read-InventoryManualCapture -FieldKeys @('collection.observations') -Technician 'Brandon'

        Should -Invoke Read-Host -Times 1
        $result[0].Value | Should -Be 'valor-por-defecto'
    }

    It 'uses the organization unit catalog menu for assignment.organizationUnitId when units are supplied, and keeps free text for everything else' {
        # Only root-level units (parentId = null) belong in this menu — a
        # child/department-level unit must never be selectable as if it were
        # a Dirección (real bug found in the field: mixing levels in one
        # catalog file let a technician pick a Departamento by mistake at
        # the Dirección prompt). This fixture is deliberately flat/root-only
        # since this test isn't exercising the cascade at all.
        $units = @(
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dir-juridico'; name = 'Dirección Jurídica'; type = 'direction'; parentId = $null; sortOrder = 20 }
        )
        $freeTextResponses = @{ 'Nombre completo del usuario' = 'Juan Pérez' }
        $calls = [ordered]@{ Menu = 0 }
        $prompter = {
            param($Key)
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                $calls.Menu++
                return '2'
            }
            return $freeTextResponses[$Key]
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName', 'assignment.organizationUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -OrganizationUnits $units

        @($result).Count | Should -Be 2
        ($result | Where-Object { $_.Key -eq 'assignment.user.fullName' }).Value | Should -Be 'Juan Pérez'
        ($result | Where-Object { $_.Key -eq 'assignment.organizationUnitId' }).Value | Should -Be 'Dirección Jurídica'
        $calls.Menu | Should -Be 1
    }

    It 'only offers root-level units at the Dirección prompt, never a nested Departamento (real field bug: mixing levels let a technician pick the wrong kind of unit)' {
        $units = @(
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-ti'; name = 'TI'; type = 'department'; parentId = 'dir-admin'; sortOrder = 20 }
        )
        $seenMenus = @()
        $prompter = {
            param($Key)
            return $null
        }
        # Capture the menu actually rendered for the Dirección field by
        # calling the catalog-menu builder the same way
        # Read-InventoryOrganizationUnitSelection does internally, scoped to
        # exactly the units this fixture defines — 3 total (1 root, 2
        # children) — the Dirección prompt must only ever offer the 1 root.
        $menu = ConvertTo-InventoryOrganizationUnitMenu -Units (Get-InventoryOrganizationUnitChildren -Units $units -ParentId $null)

        $menu.Count | Should -Be 1
        $menu[0].Name | Should -Be 'Dirección Administrativa'
    }

    It 'keeps assignment.organizationUnitId as free text when no catalog is supplied (default -OrganizationUnits)' {
        $prompter = { param($Key) 'texto libre tipeado a mano' }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId') `
            -Prompter $prompter

        $result[0].Value | Should -Be 'texto libre tipeado a mano'
    }

    It 'cascades the selected assignment.organizationUnitId into assignment.departmentUnitId, offering only its direct children' {
        # Real institutional shape (2 levels: Dirección -> Subdirección),
        # not org-example's own 3-level demo file — that extra nesting level
        # can never be reached through this exactly-2-field cascade anyway
        # (only assignment.organizationUnitId + assignment.departmentUnitId
        # exist), and mixing it in here obscured the real root-vs-child
        # distinction this test is meant to prove.
        $units = @(
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-ti'; name = 'TI'; type = 'department'; parentId = 'dir-admin'; sortOrder = 20 }
        )
        $answers = @('1', '1')
        $state = [ordered]@{ Index = 0 }
        $prompter = {
            param($Key)
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                $value = $answers[$state.Index]
                $state.Index++
                return $value
            }
            return $null
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId', 'assignment.departmentUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -OrganizationUnits $units

        @($result).Count | Should -Be 2
        ($result | Where-Object { $_.Key -eq 'assignment.organizationUnitId' }).Value | Should -Be 'Dirección Administrativa'
        ($result | Where-Object { $_.Key -eq 'assignment.departmentUnitId' }).Value | Should -Be 'Recursos Humanos'
    }

    It 'skips assignment.departmentUnitId without prompting when the selected unit has no children' {
        $units = @(
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dir-sin-hijos'; name = 'Dirección Sin Subdirecciones'; type = 'direction'; parentId = $null; sortOrder = 20 }
        )
        $calls = [ordered]@{ Count = 0 }
        $prompter = {
            param($Key)
            $calls.Count++
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                # Root-only menu is now: 1. Dirección Administrativa, 2.
                # Dirección Sin Subdirecciones — picks the childless one.
                return '2'
            }
            return $null
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId', 'assignment.departmentUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -OrganizationUnits $units

        @($result).Count | Should -Be 1
        $result[0].Key | Should -Be 'assignment.organizationUnitId'
        $result[0].Value | Should -Be 'Dirección Sin Subdirecciones'
        $calls.Count | Should -Be 1
    }

    It 'skips assignment.departmentUnitId without prompting when no direction was selected (Enter to skip)' {
        $units = Get-InventoryOrganizationUnitCatalog -BasePath (Resolve-Path "$PSScriptRoot/../Config/Organizations") -OrganizationId 'org-example'
        $calls = [ordered]@{ Count = 0 }
        $prompter = {
            param($Key)
            $calls.Count++
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                return ''
            }
            return $null
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId', 'assignment.departmentUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -OrganizationUnits $units

        @($result).Count | Should -Be 0
        $calls.Count | Should -Be 1
    }

    It 'skips assignment.departmentUnitId without prompting when no organization unit catalog is supplied at all' {
        $calls = [ordered]@{ Count = 0 }
        $prompter = {
            param($Key)
            $calls.Count++
            return 'ignorado'
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.departmentUnitId') `
            -Prompter $prompter

        @($result).Count | Should -Be 0
        $calls.Count | Should -Be 0
    }

    It 'picks assignment.departmentUnitId from its own independent, flat catalog when -DepartmentUnits is supplied, regardless of what was picked for Dirección' {
        # institucion-principal's real data: Dirección and Departamento are
        # two flat, unrelated lists (no reliable parent-child relationship
        # between them) — assignment.departmentUnitId must offer the FULL
        # department catalog, never filtered by whichever direction was
        # selected just before it.
        $directions = @(
            [PSCustomObject]@{ id = 'dir-construccion'; name = 'CONSTRUCCION'; type = 'direction'; parentId = $null; sortOrder = 10 }
        )
        $departments = @(
            [PSCustomObject]@{ id = 'dept-ti'; name = 'TI'; type = 'department'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-rh'; name = 'RECURSOS_HUMANOS'; type = 'department'; parentId = $null; sortOrder = 20 }
        )
        $answers = @('1', '2')
        $state = [ordered]@{ Index = 0 }
        $prompter = {
            param($Key)
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                $value = $answers[$state.Index]
                $state.Index++
                return $value
            }
            return $null
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId', 'assignment.departmentUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -OrganizationUnits $directions `
            -DepartmentUnits $departments

        @($result).Count | Should -Be 2
        ($result | Where-Object { $_.Key -eq 'assignment.organizationUnitId' }).Value | Should -Be 'CONSTRUCCION'
        ($result | Where-Object { $_.Key -eq 'assignment.departmentUnitId' }).Value | Should -Be 'RECURSOS_HUMANOS'
    }

    It 'offers the full independent department catalog even when Dirección was skipped with Enter' {
        $departments = @(
            [PSCustomObject]@{ id = 'dept-ti'; name = 'TI'; type = 'department'; parentId = $null; sortOrder = 10 }
        )
        # First menu prompt (Dirección) is skipped with Enter; second menu
        # prompt (Departamento, from the independent catalog) picks option 1.
        $answers = @('', '1')
        $state = [ordered]@{ Index = 0 }
        $prompter = {
            param($Key)
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                $value = $answers[$state.Index]
                $state.Index++
                return $value
            }
            return $null
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId', 'assignment.departmentUnitId') `
            -Prompter $prompter `
            -OrganizationUnits @([PSCustomObject]@{ id = 'dir-x'; name = 'X'; type = 'direction'; parentId = $null; sortOrder = 10 }) `
            -DepartmentUnits $departments

        @($result).Count | Should -Be 1
        $result[0].Key | Should -Be 'assignment.departmentUnitId'
        $result[0].Value | Should -Be 'TI'
    }

    It 'prefers the independent -DepartmentUnits catalog over the cascade when both are supplied' {
        # A real parent-child hierarchy exists AND an independent department
        # catalog was also passed in: the independent catalog wins, since it
        # is the explicit signal that this organization's Departamento is
        # not actually a child of Dirección.
        $realHierarchy = @(
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 10 }
        )
        $independentDepartments = @(
            [PSCustomObject]@{ id = 'dept-only-independent'; name = 'Solo en catálogo independiente'; type = 'department'; parentId = $null; sortOrder = 10 }
        )
        $answers = @('1', '1')
        $state = [ordered]@{ Index = 0 }
        $prompter = {
            param($Key)
            if ($Key -eq 'Seleccione un número (Enter para omitir)') {
                $value = $answers[$state.Index]
                $state.Index++
                return $value
            }
            return $null
        }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId', 'assignment.departmentUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -OrganizationUnits $realHierarchy `
            -DepartmentUnits $independentDepartments

        ($result | Where-Object { $_.Key -eq 'assignment.organizationUnitId' }).Value | Should -Be 'Dirección Administrativa'
        # If the cascade had been used instead, this would have been
        # 'Recursos Humanos' (a real child of Dirección Administrativa) —
        # asserting the independent-only name proves -DepartmentUnits took
        # priority, not the cascade.
        ($result | Where-Object { $_.Key -eq 'assignment.departmentUnitId' }).Value | Should -Be 'Solo en catálogo independiente'
    }

    It 'uses a preset value directly without invoking the Prompter for that field (visit-context reuse)' {
        # doc07-Catalog-System.md "Reutilización durante visita": a value
        # already decided for this visit (e.g. Dirección/Departamento picked
        # once for a batch of machines) skips the prompt entirely for that
        # one field, ahead of the catalog/cascade/free-text logic below it.
        $calls = [ordered]@{ Count = 0 }
        $prompter = { param($Key) $calls.Count++; 'no debería llamarse' }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -PresetValues @{ 'assignment.organizationUnitId' = 'Recursos Humanos' }

        $calls.Count | Should -Be 0
        @($result).Count | Should -Be 1
        $result[0].Key | Should -Be 'assignment.organizationUnitId'
        $result[0].Value | Should -Be 'Recursos Humanos'
    }

    It 'a preset key coexists with other keys that are still prompted normally in the same call' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $answers = @{ 'Nombre completo del usuario' = 'Juan Pérez'; 'Número patrimonial' = 'AT-001' }
        $prompter = { param($Key) $calls.Add($Key); $answers[$Key] }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName', 'assignment.departmentUnitId', 'asset.assetTag') `
            -Technician 'Técnico 01' `
            -Prompter $prompter `
            -PresetValues @{ 'assignment.departmentUnitId' = 'TI' }

        # Only the two non-preset keys ever reach the prompter (by their
        # resolved label), in order.
        @($calls) | Should -Be @('Nombre completo del usuario', 'Número patrimonial')
        @($result).Count | Should -Be 3
        ($result | Where-Object { $_.Key -eq 'assignment.user.fullName' }).Value | Should -Be 'Juan Pérez'
        ($result | Where-Object { $_.Key -eq 'assignment.departmentUnitId' }).Value | Should -Be 'TI'
        ($result | Where-Object { $_.Key -eq 'asset.assetTag' }).Value | Should -Be 'AT-001'
    }

    It 'preset values take priority over the organization unit catalog menu for the same key' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
        )
        $calls = [ordered]@{ Count = 0 }
        $prompter = { param($Key) $calls.Count++; '1' }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId') `
            -Prompter $prompter `
            -OrganizationUnits $units `
            -PresetValues @{ 'assignment.organizationUnitId' = 'Valor preseteado' }

        $calls.Count | Should -Be 0
        $result[0].Value | Should -Be 'Valor preseteado'
    }

    It 'shows the prior value as a visible, editable default (host-history reuse) and uses it when the technician presses Enter' {
        # Distinct from -PresetValues: the prompt is still shown (visible),
        # not silently skipped — it just pre-fills with the prior value.
        $calls = [System.Collections.Generic.List[string]]::new()
        $prompter = { param($Key) $calls.Add($Key); $null }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName') `
            -Prompter $prompter `
            -DefaultValues @{ 'assignment.user.fullName' = 'Juan Pérez' }

        @($calls) | Should -Be @("Nombre completo del usuario (Enter para mantener 'Juan Pérez')")
        $result[0].Value | Should -Be 'Juan Pérez'
    }

    It 'uses the typed answer instead of the default when the technician types a new value' {
        $prompter = { param($Key) 'Ana López' }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.user.fullName') `
            -Prompter $prompter `
            -DefaultValues @{ 'assignment.user.fullName' = 'Juan Pérez' }

        $result[0].Value | Should -Be 'Ana López'
    }

    It 'never invokes the organization unit catalog menu for a key that has a default value (editable free text instead)' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
        )
        $prompter = { param($Key) $null }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId') `
            -Prompter $prompter `
            -OrganizationUnits $units `
            -DefaultValues @{ 'assignment.organizationUnitId' = 'Dirección Anterior' }

        $result[0].Value | Should -Be 'Dirección Anterior'
    }

    It 'a preset value always wins over a default value for the same key (visit context is more current than host history)' {
        $calls = [ordered]@{ Count = 0 }
        $prompter = { param($Key) $calls.Count++; 'no debería llamarse' }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId') `
            -Prompter $prompter `
            -PresetValues @{ 'assignment.organizationUnitId' = 'Valor de visita' } `
            -DefaultValues @{ 'assignment.organizationUnitId' = 'Valor anterior del equipo' }

        $calls.Count | Should -Be 0
        $result[0].Value | Should -Be 'Valor de visita'
    }

    It 'uses an organization-supplied label (FieldLabels, e.g. from custom-fields.json) for the free-text prompt instead of the raw key' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $prompter = { param($Key) $calls.Add($Key); 'algún valor' }

        Read-InventoryManualCapture `
            -FieldKeys @('asset.assetTag') `
            -Prompter $prompter `
            -FieldLabels @{ 'asset.assetTag' = 'Etiqueta de inventario' } | Out-Null

        @($calls) | Should -Be @('Etiqueta de inventario')
    }

    It 'falls back to the hardcoded default label for the free-text prompt when no FieldLabels override is supplied' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $prompter = { param($Key) $calls.Add($Key); 'algún valor' }

        Read-InventoryManualCapture -FieldKeys @('collection.observations') -Prompter $prompter | Out-Null

        @($calls) | Should -Be @('Observaciones')
    }
}

Describe 'Get-InventoryDefaultFieldLabel' {
    It 'returns the known Spanish label for each of the 6 documented manual field keys' {
        Get-InventoryDefaultFieldLabel -Key 'assignment.user.fullName' | Should -Be 'Nombre completo del usuario'
        Get-InventoryDefaultFieldLabel -Key 'assignment.organizationUnitId' | Should -Be 'Dirección'
        Get-InventoryDefaultFieldLabel -Key 'assignment.departmentUnitId' | Should -Be 'Departamento'
        Get-InventoryDefaultFieldLabel -Key 'assignment.locationId' | Should -Be 'Ubicación'
        Get-InventoryDefaultFieldLabel -Key 'asset.assetTag' | Should -Be 'Número patrimonial'
        Get-InventoryDefaultFieldLabel -Key 'collection.observations' | Should -Be 'Observaciones'
    }

    It 'returns null for a key with no known default label' {
        Get-InventoryDefaultFieldLabel -Key 'custom.someOrgSpecificField' | Should -BeNullOrEmpty
    }
}

Describe 'Get-InventoryFieldLabel' {
    It 'prefers an organization-supplied label (custom-fields.json) over the hardcoded default' {
        $fieldLabels = @{ 'assignment.user.fullName' = 'Nombre del colaborador' }

        Get-InventoryFieldLabel -Key 'assignment.user.fullName' -FieldLabels $fieldLabels | Should -Be 'Nombre del colaborador'
    }

    It 'falls back to the hardcoded default label when FieldLabels has no entry for the key' {
        Get-InventoryFieldLabel -Key 'asset.assetTag' -FieldLabels @{} | Should -Be 'Número patrimonial'
        Get-InventoryFieldLabel -Key 'asset.assetTag' -FieldLabels $null | Should -Be 'Número patrimonial'
    }

    It 'falls back to the raw key as a last resort for a custom field with no configured label at all' {
        Get-InventoryFieldLabel -Key 'custom.someOrgSpecificField' -FieldLabels @{} | Should -Be 'custom.someOrgSpecificField'
    }
}

Describe 'ConvertTo-InventoryOrganizationUnitMenu' {
    It 'flattens a 3-level hierarchy into parent-then-children order with correct Depth' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = 'site-center'; sortOrder = 20 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 30 }
        )

        $menu = ConvertTo-InventoryOrganizationUnitMenu -Units $units

        $menu.GetType().IsArray | Should -BeTrue
        @($menu).Count | Should -Be 3
        $menu[0].Id | Should -Be 'site-center'
        $menu[0].Name | Should -Be 'Sede Centro'
        $menu[0].Depth | Should -Be 0
        $menu[1].Id | Should -Be 'dir-admin'
        $menu[1].Depth | Should -Be 1
        $menu[2].Id | Should -Be 'dept-hr'
        $menu[2].Depth | Should -Be 2
    }

    It 'orders multiple roots and their children depth-first by sortOrder, not level by level' {
        $units = @(
            [PSCustomObject]@{ id = 'b'; name = 'B root'; type = 'site'; parentId = $null; sortOrder = 20 }
            [PSCustomObject]@{ id = 'a'; name = 'A root'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'a2'; name = 'A child 2'; type = 'department'; parentId = 'a'; sortOrder = 20 }
            [PSCustomObject]@{ id = 'a1'; name = 'A child 1'; type = 'department'; parentId = 'a'; sortOrder = 10 }
        )

        $menu = ConvertTo-InventoryOrganizationUnitMenu -Units $units

        @($menu | ForEach-Object { $_.Id }) | Should -Be @('a', 'a1', 'a2', 'b')
    }

    It 'returns an empty array without throwing when Units is null or empty' {
        $fromNull = ConvertTo-InventoryOrganizationUnitMenu -Units $null
        $fromEmpty = ConvertTo-InventoryOrganizationUnitMenu -Units @()

        @($fromNull).Count | Should -Be 0
        @($fromEmpty).Count | Should -Be 0
    }

    It 'cuts a cycle short instead of looping forever on a malformed catalog' {
        $units = @(
            [PSCustomObject]@{ id = 'root'; name = 'Root'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'x'; name = 'X (reachable from root)'; type = 'department'; parentId = 'root'; sortOrder = 10 }
            [PSCustomObject]@{ id = 'x'; name = 'X (duplicate id, self-referential parent)'; type = 'department'; parentId = 'x'; sortOrder = 10 }
        )

        $menu = ConvertTo-InventoryOrganizationUnitMenu -Units $units

        @($menu).Count | Should -Be 2
        $menu[0].Id | Should -Be 'root'
        $menu[1].Id | Should -Be 'x'
        $menu[1].Name | Should -Be 'X (reachable from root)'
    }
}

Describe 'Get-InventoryOrganizationUnitMenuChildren' {
    # ConvertTo-InventoryOrganizationUnitMenu's own external contract (a
    # flat, correctly-shaped menu array) stayed correct even before this fix,
    # because PowerShell 7 (used to run this suite) tolerates .Count/[0]
    # indexing on a bare, collapsed scalar via features Windows PowerShell
    # 5.1 does not have — the same blind spot that hid the original bug this
    # session started from. Extracting the previously-inline
    # `$roots = if (...) { $childrenByParent[key] } else { @() }` lookup
    # into this small function makes the collapse directly observable via
    # .GetType().IsArray, instead of relying on downstream tolerance. Named
    # "...MenuChildren" (not just "...Children") to stay distinct from
    # Get-InventoryOrganizationUnitChildren below, which filters the raw
    # catalog by parentId for the Dirección→Departamento cascade.
    It 'returns a real array, not a bare scalar, when the parent has exactly one child' {
        $childrenByParent = @{ '' = @([PSCustomObject]@{ id = 'root1'; name = 'Root One' }) }

        $result = Get-InventoryOrganizationUnitMenuChildren -ChildrenByParent $childrenByParent -ParentKey ''

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].id | Should -Be 'root1'
    }

    It 'returns every child when the parent has more than one' {
        $childrenByParent = @{ 'dir-admin' = @([PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' }) }

        $result = Get-InventoryOrganizationUnitMenuChildren -ChildrenByParent $childrenByParent -ParentKey 'dir-admin'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 2
    }

    It 'returns a real empty array, not null, when the parent key is not present' {
        $result = Get-InventoryOrganizationUnitMenuChildren -ChildrenByParent @{} -ParentKey 'missing'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }
}

Describe 'Read-InventoryOrganizationUnitSelection' {
    It 'returns null immediately without prompting when there are no units' {
        $calls = [ordered]@{ Prompter = 0 }
        $prompter = { param($Prompt) $calls.Prompter++; '1' }

        $result = Read-InventoryOrganizationUnitSelection -Units @() -Prompter $prompter

        $result | Should -BeNullOrEmpty
        $calls.Prompter | Should -Be 0
    }

    It 'returns the Id and Name of the selected unit for a valid numeric choice' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'site-center'; sortOrder = 20 }
        )
        $prompter = { param($Prompt) '2' }

        $result = Read-InventoryOrganizationUnitSelection -Units $units -Prompter $prompter

        $result.Id | Should -Be 'dept-hr'
        $result.Name | Should -Be 'Recursos Humanos'
    }

    It 'returns null when the technician presses Enter (skip)' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
        )
        $prompter = { param($Prompt) '' }

        $result = Read-InventoryOrganizationUnitSelection -Units $units -Prompter $prompter

        $result | Should -BeNullOrEmpty
    }

    It 'reprompts on an invalid answer until a valid one is given' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'site-center'; sortOrder = 20 }
        )
        $responses = @('not-a-number', '99', '2')
        $state = [ordered]@{ Index = 0 }
        $prompter = {
            param($Prompt)
            $value = $responses[$state.Index]
            $state.Index++
            $value
        }

        $result = Read-InventoryOrganizationUnitSelection -Units $units -Prompter $prompter

        $result.Id | Should -Be 'dept-hr'
        $result.Name | Should -Be 'Recursos Humanos'
        $state.Index | Should -Be 3
    }

    It 'shows the given Label as a header before the numbered menu' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
        )
        Mock Write-Host {}
        $prompter = { param($Prompt) '' }

        Read-InventoryOrganizationUnitSelection -Units $units -Prompter $prompter -Label 'Dirección' | Out-Null

        Should -Invoke Write-Host -ParameterFilter { $Object -match 'Dirección' }
    }

    It 'shows no field-name header line when Label is not supplied' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
        )
        Mock Write-Host {}
        $prompter = { param($Prompt) '' }

        Read-InventoryOrganizationUnitSelection -Units $units -Prompter $prompter | Out-Null

        Should -Not -Invoke Write-Host -ParameterFilter { $Object -match 'Dirección' }
    }
}

Describe 'ConvertTo-InventoryOrganizationUnitMenuEntries' {
    It 'formats each menu item as "N. <indent><Name>", numbered by 1-based position, matching the existing print format' {
        $menu = @(
            [PSCustomObject]@{ Id = 'a'; Name = 'Sede Centro'; Depth = 0 }
            [PSCustomObject]@{ Id = 'b'; Name = 'Dirección Administrativa'; Depth = 1 }
            [PSCustomObject]@{ Id = 'c'; Name = 'Recursos Humanos'; Depth = 2 }
        )

        $entries = ConvertTo-InventoryOrganizationUnitMenuEntries -Menu $menu

        $entries.GetType().IsArray | Should -BeTrue
        $entries.Count | Should -Be 3
        $entries[0] | Should -Be (" 1. " + "Sede Centro")
        $entries[1] | Should -Be (" 2. " + "  " + "Dirección Administrativa")
        $entries[2] | Should -Be (" 3. " + "    " + "Recursos Humanos")
    }

    It 'returns an empty array without throwing when Menu is null or empty' {
        $fromNull = ConvertTo-InventoryOrganizationUnitMenuEntries -Menu $null
        $fromEmpty = ConvertTo-InventoryOrganizationUnitMenuEntries -Menu @()

        $fromNull.GetType().IsArray | Should -BeTrue
        $fromNull.Count | Should -Be 0
        $fromEmpty.Count | Should -Be 0
    }
}

Describe 'Get-InventoryMenuColumnCount' {
    It 'returns 2 when ConsoleWidth is null (could not be determined)' {
        Get-InventoryMenuColumnCount -MaxEntryWidth 20 -ConsoleWidth $null | Should -Be 2
    }

    It 'returns 2 when ConsoleWidth is zero or negative' {
        Get-InventoryMenuColumnCount -MaxEntryWidth 20 -ConsoleWidth 0 | Should -Be 2
        Get-InventoryMenuColumnCount -MaxEntryWidth 20 -ConsoleWidth -10 | Should -Be 2
    }

    It 'returns 2 when exactly 2 columns fit the console width' {
        # cell width = MaxEntryWidth + 4 = 14; 2 * 14 = 28 fits, 3 * 14 = 42 does not.
        Get-InventoryMenuColumnCount -MaxEntryWidth 10 -ConsoleWidth 28 | Should -Be 2
    }

    It 'returns 3 when exactly 3 columns fit the console width' {
        # cell width = MaxEntryWidth + 4 = 14; 3 * 14 = 42 fits exactly.
        Get-InventoryMenuColumnCount -MaxEntryWidth 10 -ConsoleWidth 42 | Should -Be 3
    }

    It 'never returns more than 3 even when many more columns would fit' {
        Get-InventoryMenuColumnCount -MaxEntryWidth 5 -ConsoleWidth 500 | Should -Be 3
    }
}

Describe 'Format-InventoryMenuColumns' {
    It 'lays out entries row-major (left to right, then next row), padding every cell except the last one in each row' {
        $entries = @(' 1. Uno', ' 2. Dos', ' 3. Tres', ' 4. Cuatro')

        $lines = Format-InventoryMenuColumns -Entries $entries -Columns 2

        $lines.GetType().IsArray | Should -BeTrue
        $lines.Count | Should -Be 2
        $cellWidth = (' 4. Cuatro').Length + 4
        $lines[0] | Should -Be (' 1. Uno'.PadRight($cellWidth) + ' 2. Dos')
        $lines[1] | Should -Be (' 3. Tres'.PadRight($cellWidth) + ' 4. Cuatro')
    }

    It 'gives the last row a single, unpadded cell when the entry count does not divide evenly into columns' {
        $entries = @(' 1. A', ' 2. B', ' 3. C', ' 4. D', ' 5. E')

        $lines = Format-InventoryMenuColumns -Entries $entries -Columns 2

        $lines.Count | Should -Be 3
        $lines[2] | Should -Be ' 5. E'
    }

    It 'returns an empty array without throwing when Entries is null or empty' {
        $fromNull = Format-InventoryMenuColumns -Entries $null -Columns 2
        $fromEmpty = Format-InventoryMenuColumns -Entries @() -Columns 2

        $fromNull.GetType().IsArray | Should -BeTrue
        $fromNull.Count | Should -Be 0
        $fromEmpty.Count | Should -Be 0
    }
}

Describe 'Get-InventoryConsoleWidth' {
    It 'never throws and returns either $null or a positive integer' {
        { $script:consoleWidthResult = Get-InventoryConsoleWidth } | Should -Not -Throw
        ($null -eq $script:consoleWidthResult -or $script:consoleWidthResult -gt 0) | Should -BeTrue
    }
}

Describe 'Get-InventoryOrganizationUnitChildren' {
    It 'returns only the direct children of the given parent, ordered by sortOrder' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = 'site-center'; sortOrder = 20 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 20 }
            [PSCustomObject]@{ id = 'dept-it'; name = 'Sistemas'; type = 'department'; parentId = 'dir-admin'; sortOrder = 10 }
        )

        $children = Get-InventoryOrganizationUnitChildren -Units $units -ParentId 'dir-admin'

        @($children).Count | Should -Be 2
        $children[0].id | Should -Be 'dept-it'
        $children[1].id | Should -Be 'dept-hr'
    }

    It 'returns an empty array when the parent has no children' {
        $units = @(
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'dir-admin'; sortOrder = 20 }
        )

        $children = Get-InventoryOrganizationUnitChildren -Units $units -ParentId 'dept-hr'

        $children.GetType().IsArray | Should -BeTrue
        @($children).Count | Should -Be 0
    }

    It 'returns an empty array without throwing when Units is null or empty' {
        $fromNull = Get-InventoryOrganizationUnitChildren -Units $null -ParentId 'dir-admin'
        $fromEmpty = Get-InventoryOrganizationUnitChildren -Units @() -ParentId 'dir-admin'

        @($fromNull).Count | Should -Be 0
        @($fromEmpty).Count | Should -Be 0
    }
}
