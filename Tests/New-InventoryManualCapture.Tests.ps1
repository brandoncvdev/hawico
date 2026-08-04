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
}
