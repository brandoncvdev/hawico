BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
    }
}

Describe 'Get-CimDataSafe' {
    It 'returns a real array, not a bare object, when exactly one instance is found (no filter)' {
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'Win32_OperatingSystem' } }

        $result = Get-CimDataSafe -ClassName 'Win32_OperatingSystem'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'returns a real array, not a bare object, when exactly one instance is found (with a filter)' {
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'C:' } }

        $result = Get-CimDataSafe -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'returns an empty array instead of throwing when the query fails' {
        Mock Get-CimInstance { throw 'access denied' }

        $result = Get-CimDataSafe -ClassName 'Win32_Processor' -WarningAction SilentlyContinue

        @($result).Count | Should -Be 0
    }
}

Describe 'Resolve-InventoryManualFieldKeys' {
    It 'returns a real array, not a bare scalar, when exactly one key is passed in directly' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys @('assignment.user.fullName') -ConfigManualFields @('fallback.one', 'fallback.two')

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'assignment.user.fullName'
    }

    It 'returns a real array, not a bare scalar, when falling back to exactly one config manual field' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys $null -ConfigManualFields @('assignment.organizationUnitId')

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'assignment.organizationUnitId'
    }

    It 'returns a real empty array when there is nothing to fall back to' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys $null -ConfigManualFields $null

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'prefers the passed-in keys over the config fallback when both are present' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys @('from.launcher') -ConfigManualFields @('from.config')

        $result.Count | Should -Be 1
        $result[0] | Should -Be 'from.launcher'
    }

    It 'returns every passed-in key when there is more than one' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys @('field.one', 'field.two') -ConfigManualFields $null

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 2
    }
}

Describe 'Resolve-InventoryOrganizationUnits' {
    It 'returns a real array, not a bare scalar, when exactly one unit is passed in' {
        $unit = [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; parentId = $null; sortOrder = 10 }

        $result = Resolve-InventoryOrganizationUnits -PassedUnits @($unit)

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].id | Should -Be 'site-center'
    }

    It 'returns a real empty array when nothing was passed' {
        $result = Resolve-InventoryOrganizationUnits -PassedUnits $null

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }
}

Describe 'Install-InventoryImportExcelIfNeeded' {
    It 'returns true immediately when already available, without prompting or installing' {
        $calls = [ordered]@{ Confirm = 0; Installer = 0 }
        $isAvailable = { $true }
        $confirm = { param($Prompt) $calls.Confirm++; 'S' }
        $installer = { $calls.Installer++ }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeTrue
        $calls.Confirm | Should -Be 0
        $calls.Installer | Should -Be 0
    }

    It 'returns false and never installs when the user declines' {
        $calls = [ordered]@{ Installer = 0 }
        $isAvailable = { $false }
        $confirm = { param($Prompt) 'N' }
        $installer = { $calls.Installer++ }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeFalse
        $calls.Installer | Should -Be 0
    }

    It 'treats an empty answer (Enter) as declining, without installing' {
        $calls = [ordered]@{ Installer = 0 }
        $isAvailable = { $false }
        $confirm = { param($Prompt) '' }
        $installer = { $calls.Installer++ }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeFalse
        $calls.Installer | Should -Be 0
    }

    It 'passes a prompt describing what will be installed to Confirm' {
        $script:capturedPrompt = $null
        $isAvailable = { $false }
        $confirm = { param($Prompt) $script:capturedPrompt = $Prompt; 'N' }
        $installer = { }

        Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer | Out-Null

        $script:capturedPrompt | Should -Match 'ImportExcel'
    }

    It 'installs and returns true when the user accepts (uppercase S) and the install succeeds' {
        $state = [ordered]@{ Installed = $false; InstallerCalls = 0 }
        $isAvailable = { $state.Installed }
        $confirm = { param($Prompt) 'S' }
        $installer = { $state.InstallerCalls++; $state.Installed = $true }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeTrue
        $state.InstallerCalls | Should -Be 1
    }

    It 'accepts a lowercase s answer too' {
        $state = [ordered]@{ Installed = $false }
        $isAvailable = { $state.Installed }
        $confirm = { param($Prompt) 's' }
        $installer = { $state.Installed = $true }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeTrue
    }

    It 'returns false and prints the error when the install throws' {
        $isAvailable = { $false }
        $confirm = { param($Prompt) 'S' }
        $installer = { throw 'network unreachable' }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer `
            -InformationVariable infoOutput -InformationAction SilentlyContinue

        $result | Should -BeFalse
        ($infoOutput | Out-String) | Should -Match 'network unreachable'
    }

    It 'does not re-check availability a second time when the user declines' {
        $calls = [ordered]@{ IsAvailable = 0 }
        $isAvailable = { $calls.IsAvailable++; $false }
        $confirm = { param($Prompt) 'N' }
        $installer = { }

        Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer | Out-Null

        $calls.IsAvailable | Should -Be 1
    }
}

Describe 'Get-InventoryHostOutputDirectory' {
    It 'joins the base output directory with the (already-sanitized) hostname' {
        # Both collectors already sanitize $env:COMPUTERNAME
        # (-replace '[^a-zA-Z0-9_-]', '_') before calling this, so this stays
        # a pure Join-Path wrapper instead of duplicating that sanitization.
        Get-InventoryHostOutputDirectory -BaseOutputDirectory 'C:\Output' -Hostname 'RH-PC-04' |
            Should -Be (Join-Path 'C:\Output' 'RH-PC-04')
    }

    It 'groups every artifact for the same hostname under the same subfolder regardless of collection timestamp' {
        $first = Get-InventoryHostOutputDirectory -BaseOutputDirectory 'C:\Output' -Hostname 'RH-PC-04'
        $second = Get-InventoryHostOutputDirectory -BaseOutputDirectory 'C:\Output' -Hostname 'RH-PC-04'

        $first | Should -Be $second
    }
}
