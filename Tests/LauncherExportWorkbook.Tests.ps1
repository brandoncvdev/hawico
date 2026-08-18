Describe 'Export-InventoryWorkbook.ps1 ImportExcel handling' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Export-InventoryWorkbook.ps1" -Raw
    }

    It 'offers to install ImportExcel on the spot instead of just printing the install command' {
        $script | Should -Match 'Install-InventoryImportExcelIfNeeded'
        $script | Should -Not -Match 'Get-Module -ListAvailable -Name ImportExcel'
    }

    It 'still throws a clear error when ImportExcel could not be made available' {
        $script | Should -Match 'if\s*\(\s*-not\s*\(\s*Install-InventoryImportExcelIfNeeded\s*\)\s*\)\s*\{'
        $script | Should -Match 'throw'
    }

    It 'still generates the consolidated workbook the same way as before' {
        $script | Should -Match 'Export-InventoryConsolidatedWorkbook'
    }
}
