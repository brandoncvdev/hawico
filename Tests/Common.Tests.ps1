BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
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
