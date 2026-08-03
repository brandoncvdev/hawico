BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryCollectionSession.ps1"
}

Describe 'New-InventoryCollectionSession' {
    It 'builds an active session entity with the supplied context' {
        $startedAt = [datetimeoffset]'2026-08-03T08:00:00-06:00'

        $session = New-InventoryCollectionSession `
            -SessionId 'SES-20260803-AM-RH' `
            -OrganizationId 'ORG-001' `
            -ProfileId 'basic-inventory' `
            -Technician 'Brandon' `
            -StartedAt $startedAt

        $session.SessionId | Should -Be 'SES-20260803-AM-RH'
        $session.OrganizationId | Should -Be 'ORG-001'
        $session.ProfileId | Should -Be 'basic-inventory'
        $session.Technician | Should -Be 'Brandon'
        $session.StartedAt | Should -Be $startedAt.ToString('o')
        $session.EndedAt | Should -BeNullOrEmpty
        $session.EquipmentCount | Should -Be 0
        $session.PendingCount | Should -Be 0
        $session.Status | Should -Be 'Active'
    }

    It 'defaults ProfileId to basic-inventory when not supplied' {
        $session = New-InventoryCollectionSession -SessionId 'SES-20260803-AM-RH'

        $session.ProfileId | Should -Be 'basic-inventory'
    }

    It 'marks the session Unassigned and warns when no SessionId is supplied' {
        $session = New-InventoryCollectionSession -WarningVariable warnings -WarningAction SilentlyContinue

        $session.SessionId | Should -Be 'SES-UNASSIGNED'
        $session.Status | Should -Be 'Unassigned'
        $warnings.Count | Should -BeGreaterThan 0
        [string]$warnings[0] | Should -Match 'sin sesión de recolección asignada'
    }

    It 'marks the session Unassigned and warns when SessionId is the empty string' {
        $session = New-InventoryCollectionSession -SessionId '' -WarningVariable warnings -WarningAction SilentlyContinue

        $session.SessionId | Should -Be 'SES-UNASSIGNED'
        $session.Status | Should -Be 'Unassigned'
        $warnings.Count | Should -BeGreaterThan 0
    }

    It 'marks the session Unassigned and warns when SessionId is the default literal SES-UNASSIGNED' {
        $session = New-InventoryCollectionSession -SessionId 'SES-UNASSIGNED' -WarningVariable warnings -WarningAction SilentlyContinue

        $session.SessionId | Should -Be 'SES-UNASSIGNED'
        $session.Status | Should -Be 'Unassigned'
        $warnings.Count | Should -BeGreaterThan 0
    }

    It 'does not warn when a real SessionId is supplied' {
        $session = New-InventoryCollectionSession -SessionId 'SES-20260803-AM-RH' -WarningVariable warnings -WarningAction SilentlyContinue

        $session.Status | Should -Be 'Active'
        $warnings.Count | Should -Be 0
    }
}
