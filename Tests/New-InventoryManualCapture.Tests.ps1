BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryManualCapture.ps1"
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
    It 'visits every field key in order using the injected prompter' {
        $visited = [System.Collections.Generic.List[string]]::new()
        $answers = @{
            'assignment.user.fullName' = 'Juan Pérez Hernández'
            'assignment.organizationUnitId' = 'dept-hr'
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

        @($visited) | Should -Be @('assignment.user.fullName', 'assignment.organizationUnitId')
        @($result).Count | Should -Be 2
        $result[0].Key | Should -Be 'assignment.user.fullName'
        $result[0].Value | Should -Be 'Juan Pérez Hernández'
        $result[1].Key | Should -Be 'assignment.organizationUnitId'
        $result[1].Value | Should -Be 'dept-hr'
    }

    It 'omits fields skipped with Enter and keeps the ones that were answered' {
        $answers = @{
            'assignment.user.fullName' = ''
            'assignment.organizationUnitId' = 'dept-hr'
            'asset.assetTag' = '   '
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
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'site-center'; sortOrder = 20 }
        )
        $freeTextResponses = @{ 'assignment.user.fullName' = 'Juan Pérez' }
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
        ($result | Where-Object { $_.Key -eq 'assignment.organizationUnitId' }).Value | Should -Be 'Recursos Humanos'
        $calls.Menu | Should -Be 1
    }

    It 'keeps assignment.organizationUnitId as free text when no catalog is supplied (default -OrganizationUnits)' {
        $prompter = { param($Key) 'texto libre tipeado a mano' }

        $result = Read-InventoryManualCapture `
            -FieldKeys @('assignment.organizationUnitId') `
            -Prompter $prompter

        $result[0].Value | Should -Be 'texto libre tipeado a mano'
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

Describe 'Get-InventoryOrganizationUnitChildren' {
    # ConvertTo-InventoryOrganizationUnitMenu's own external contract (a
    # flat, correctly-shaped menu array) stayed correct even before this fix,
    # because PowerShell 7 (used to run this suite) tolerates .Count/[0]
    # indexing on a bare, collapsed scalar via features Windows PowerShell
    # 5.1 does not have — the same blind spot that hid the original bug this
    # session started from. Extracting the previously-inline
    # `$roots = if (...) { $childrenByParent[key] } else { @() }` lookup
    # into this small function makes the collapse directly observable via
    # .GetType().IsArray, instead of relying on downstream tolerance.
    It 'returns a real array, not a bare scalar, when the parent has exactly one child' {
        $childrenByParent = @{ '' = @([PSCustomObject]@{ id = 'root1'; name = 'Root One' }) }

        $result = Get-InventoryOrganizationUnitChildren -ChildrenByParent $childrenByParent -ParentKey ''

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].id | Should -Be 'root1'
    }

    It 'returns every child when the parent has more than one' {
        $childrenByParent = @{ 'dir-admin' = @([PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' }) }

        $result = Get-InventoryOrganizationUnitChildren -ChildrenByParent $childrenByParent -ParentKey 'dir-admin'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 2
    }

    It 'returns a real empty array, not null, when the parent key is not present' {
        $result = Get-InventoryOrganizationUnitChildren -ChildrenByParent @{} -ParentKey 'missing'

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

    It 'returns the Name of the selected unit for a valid numeric choice' {
        $units = @(
            [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
            [PSCustomObject]@{ id = 'dept-hr'; name = 'Recursos Humanos'; type = 'department'; parentId = 'site-center'; sortOrder = 20 }
        )
        $prompter = { param($Prompt) '2' }

        $result = Read-InventoryOrganizationUnitSelection -Units $units -Prompter $prompter

        $result | Should -Be 'Recursos Humanos'
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

        $result | Should -Be 'Recursos Humanos'
        $state.Index | Should -Be 3
    }
}
