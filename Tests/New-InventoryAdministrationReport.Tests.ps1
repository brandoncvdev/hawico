BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Export.ps1"
    . "$PSScriptRoot/../Modules/New-InventoryAdministrationReport.ps1"

    function New-EmptyImportResult {
        return [ordered]@{
            NuevosEquipos = @()
            EquiposActualizados = @()
            PosiblesDuplicados = @()
            Conflictos = @()
            ErroresRecoleccion = @()
            SkippedFiles = @()
        }
    }
}

Describe 'New-InventoryAdministrationReport' {
    BeforeEach {
        $script:outputPath = Join-Path $TestDrive ('report-' + [guid]::NewGuid().ToString('N') + '.html')
    }

    It 'writes an HTML file and returns the output path' {
        $result = New-InventoryAdministrationReport -ImportResult (New-EmptyImportResult) -OutputPath $script:outputPath

        $result | Should -Be $script:outputPath
        Test-Path -LiteralPath $script:outputPath | Should -BeTrue
    }

    It 'shows the correct counters and rows for populated trays' {
        $importResult = New-EmptyImportResult
        $importResult.NuevosEquipos = @(
            [PSCustomObject]@{ AssetId = 'AST-0001'; CollectionId = 'COL-1'; ComputerName = 'PC-01'; SessionId = 'SES-A'; Technician = 'Técnico 01' }
        )
        $importResult.EquiposActualizados = @(
            [PSCustomObject]@{ AssetId = 'AST-0002'; CollectionId = 'COL-2'; ComputerName = 'PC-02'; SessionId = 'SES-A'; Technician = 'Técnico 02' }
            [PSCustomObject]@{ AssetId = 'AST-0003'; CollectionId = 'COL-3'; ComputerName = 'PC-03'; SessionId = 'SES-A'; Technician = $null }
        )

        New-InventoryAdministrationReport -ImportResult $importResult -OutputPath $script:outputPath | Out-Null
        $html = Get-Content -LiteralPath $script:outputPath -Raw

        $html | Should -Match 'Nuevos equipos'
        $html | Should -Match '<span class="badge">1</span>'
        $html | Should -Match 'AST-0001'
        $html | Should -Match 'PC-01'
        # SessionId (visit grouping) and Technician (who captured it) are
        # different pieces of information shown as two separate columns —
        # neither replaces the other.
        $html | Should -Match 'T&#233;cnico'
        $html | Should -Match 'T&#233;cnico 01'

        $html | Should -Match 'Equipos actualizados'
        $html | Should -Match '<span class="badge">2</span>'
        $html | Should -Match 'AST-0002'
        $html | Should -Match 'AST-0003'
        $html | Should -Match 'T&#233;cnico 02'
    }

    It 'shows "Sin elementos" once per empty tray (6 trays)' {
        New-InventoryAdministrationReport -ImportResult (New-EmptyImportResult) -OutputPath $script:outputPath | Out-Null
        $html = Get-Content -LiteralPath $script:outputPath -Raw

        (Select-String -InputObject $html -Pattern 'Sin elementos' -AllMatches).Matches.Count | Should -Be 6
    }

    It 'HTML-encodes row values so a value containing < or & cannot break the markup' {
        $importResult = New-EmptyImportResult
        $importResult.Conflictos = @(
            [PSCustomObject]@{
                AssetId = 'AST-0004'
                Key = 'assignment.user.fullName'
                ValorActual = 'Juan <script>alert(1)</script> Pérez'
                ValorNuevo = 'AT&T Contractor'
                CollectionId = 'COL-4'
            }
        )

        New-InventoryAdministrationReport -ImportResult $importResult -OutputPath $script:outputPath | Out-Null
        $html = Get-Content -LiteralPath $script:outputPath -Raw

        # WebUtility.HtmlEncode also numeric-encodes non-ASCII characters
        # (e.g. 'é' -> '&#233;'), matching Modules/Export.ps1's existing
        # ConvertTo-HtmlSafe behavior used everywhere else in this codebase.
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match 'Juan &lt;script&gt;alert\(1\)&lt;/script&gt; P&#233;rez'
        $html | Should -Match 'AT&amp;T Contractor'
    }

    It 'shows collection errors (arrays) for the ErroresRecoleccion tray' {
        $importResult = New-EmptyImportResult
        $importResult.ErroresRecoleccion = @(
            [PSCustomObject]@{
                CollectionId = 'COL-5'
                ComputerName = 'PC-05'
                Errors = @('No se pudo leer el sensor de temperatura', 'Timeout al consultar red')
            }
        )

        New-InventoryAdministrationReport -ImportResult $importResult -OutputPath $script:outputPath | Out-Null
        $html = Get-Content -LiteralPath $script:outputPath -Raw

        $html | Should -Match 'No se pudo leer el sensor de temperatura'
        $html | Should -Match 'Timeout al consultar red'
    }

    It 'shows skipped files with their parse error' {
        $importResult = New-EmptyImportResult
        $importResult.SkippedFiles = @(
            [PSCustomObject]@{ Path = 'C:\Output\PC-BAD-record.json'; Error = 'Invalid JSON primitive' }
        )

        New-InventoryAdministrationReport -ImportResult $importResult -OutputPath $script:outputPath | Out-Null
        $html = Get-Content -LiteralPath $script:outputPath -Raw

        $html | Should -Match 'PC-BAD-record\.json'
        $html | Should -Match 'Invalid JSON primitive'
    }

    It 'shows possible-duplicate rows without an AssetId column value' {
        $importResult = New-EmptyImportResult
        $importResult.PosiblesDuplicados = @(
            [PSCustomObject]@{ CollectionId = 'COL-6'; ComputerName = 'PC-NEEDSREVIEW'; SessionId = 'SES-B' }
        )

        New-InventoryAdministrationReport -ImportResult $importResult -OutputPath $script:outputPath | Out-Null
        $html = Get-Content -LiteralPath $script:outputPath -Raw

        $html | Should -Match 'Posibles duplicados'
        $html | Should -Match 'PC-NEEDSREVIEW'
    }
}
