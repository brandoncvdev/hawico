Describe 'Start-Administration.ps1 menu wiring' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Start-Administration.ps1" -Raw
    }

    It 'dot-sources every module the administration menu depends on' {
        $script | Should -Match 'Common\.ps1'
        $script | Should -Match 'InventoryAdministration\.ps1'
        $script | Should -Match 'New-InventoryConsolidatedWorkbook\.ps1'
        $script | Should -Match 'New-InventoryAdministrationReport\.ps1'
        $script | Should -Match 'Export\.ps1'
    }

    It 'reuses the existing Administration and Consolidation config blocks instead of duplicating them' {
        $script | Should -Match '\$config\.Administration'
        $script | Should -Match '\$config\.Consolidation'
    }

    It 'imports new captures, prints the tray counts, and generates the HTML report' {
        $script | Should -Match 'Import-InventoryAdministrationSession'
        $script | Should -Match 'New-InventoryAdministrationReport'
        $script | Should -Match 'NuevosEquipos'
        $script | Should -Match 'Conflictos'
    }

    It 'opens the most recent import report when it exists' {
        $script | Should -Match 'Importacion-\*\.html'
    }

    It 'resolves manual conflicts through Add-InventoryAssetManualReview with the reviewer prompts' {
        $script | Should -Match 'Add-InventoryAssetManualReview'
        $script | Should -Match 'AssetId'
        $script | Should -Match 'ReviewedBy'
    }

    It 'generates the consolidated Excel workbook the same way Export-InventoryWorkbook.ps1 does' {
        $script | Should -Match 'Export-InventoryConsolidatedWorkbook'
    }

    It 'offers to install ImportExcel on the spot instead of just printing the install command' {
        $script | Should -Match 'Install-InventoryImportExcelIfNeeded'
        $script | Should -Not -Match 'Get-Module -ListAvailable -Name ImportExcel'
    }

    It 'follows the same menu loop and error handling pattern as Start-Inventory.ps1' {
        $script | Should -Match 'function Wait-MenuInput'
        $script | Should -Match 'do\s*\{'
        $script | Should -Match 'switch\s*\(\$option\)'
        $script | Should -Match 'while\s*\(\$option'
        $script | Should -Match 'catch\s*\{'
    }
}
