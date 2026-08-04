BeforeAll {
    . "$PSScriptRoot/../Modules/Export.ps1"
}

Describe 'New-InventoryHtml' {
    It 'renders the manual fields captured during the visit as an HTML-encoded table inside Resumen del equipo' {
        $path = Join-Path $TestDrive 'inventory.html'
        $manualFields = @(
            [ordered]@{
                Key = 'assignment.user.fullName'
                Value = 'Juan <Perez> & Ca.'
                Source = 'VisitCapture'
                CapturedBy = 'Tecnico 01'
            }
        )

        New-InventoryHtml -Inventory @{} -Path $path -ManualFields $manualFields

        $html = Get-Content -LiteralPath $path -Raw

        $html | Should -Match 'Datos capturados en la visita'
        $html | Should -Match '<th>Campo</th>'
        $html | Should -Match '<th>Valor</th>'
        $html | Should -Match '<th>Fuente</th>'
        $html | Should -Match '<th>Capturado por</th>'
        $html | Should -Match 'assignment\.user\.fullName'
        $html | Should -Match 'VisitCapture'
        $html | Should -Match 'Tecnico 01'
        # The raw value contains < and & — must come through HTML-encoded,
        # never as literal markup (same ConvertTo-HtmlSafe path every other
        # table in this report already uses).
        $html | Should -Match 'Juan &lt;Perez&gt; &amp; Ca\.'
        $html | Should -Not -Match 'Juan <Perez> & Ca\.'
    }

    It 'shows the empty-state message when no manual fields were captured' {
        $path = Join-Path $TestDrive 'inventory-empty.html'

        New-InventoryHtml -Inventory @{} -Path $path

        $html = Get-Content -LiteralPath $path -Raw

        $html | Should -Match 'Datos capturados en la visita'
        $html | Should -Match 'No se capturaron datos manuales en esta visita\.'
    }
}
