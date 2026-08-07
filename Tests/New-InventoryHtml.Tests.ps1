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

Describe 'New-InventoryHtml — Estado SMART (Phase 8, storage-diagnostics)' {
    It 'renders the raw SMART values table for a healthy disk with no findings' {
        $path = Join-Path $TestDrive 'inventory-smart-healthy.html'
        $inventory = @{
            Storage = @{
                Physical = @(
                    [ordered]@{
                        Index = 0
                        Model = 'Seagate ST500DM005'
                        Smart = [ordered]@{
                            Supported = $true
                            Source = 'ATA'
                            OverallHealth = 'PASSED'
                            TemperatureCelsius = 32
                            PowerOnHours = 8000
                            ReallocatedSectorCount = 0
                            PendingSectorCount = 0
                            UncorrectableSectorCount = 0
                            AvailableSparePercent = $null
                            PercentageUsed = $null
                        }
                    }
                )
                Detailed = @()
                Logical = @()
                Upgrade = @{}
            }
            StorageFindings = @()
            StorageRecommendations = @()
        }

        New-InventoryHtml -Inventory $inventory -Path $path

        $html = Get-Content -LiteralPath $path -Raw

        $html | Should -Match 'Estado SMART'
        $html | Should -Match 'Seagate ST500DM005'
        $html | Should -Match '<td>ATA</td>'
        $html | Should -Match '<td>PASSED</td>'
        $html | Should -Match '<td>32</td>'
        $html | Should -Match '<td>8000</td>'
        $html | Should -Match 'No se detectaron hallazgos de salud en el almacenamiento\.'
        $html | Should -Match 'No hay recomendaciones de almacenamiento para este equipo\.'
    }

    It 'renders the findings/recommendations tables for a disk that produced STO findings' {
        $path = Join-Path $TestDrive 'inventory-smart-findings.html'
        $inventory = @{
            Storage = @{
                Physical = @(
                    [ordered]@{
                        Index = 0
                        Model = 'WDC WD10EZEX'
                        Smart = [ordered]@{
                            Supported = $true
                            Source = 'ATA'
                            OverallHealth = 'FAILED'
                            TemperatureCelsius = 61
                            PowerOnHours = 30000
                            ReallocatedSectorCount = 12
                            PendingSectorCount = 4
                            UncorrectableSectorCount = 2
                            AvailableSparePercent = $null
                            PercentageUsed = $null
                        }
                    }
                )
                Detailed = @()
                Logical = @()
                Upgrade = @{}
            }
            StorageFindings = @(
                [pscustomobject][ordered]@{
                    Id = 'STO-006'
                    Category = 'Storage'
                    Severity = 'Critical'
                    Title = 'Autoevaluación SMART fallida'
                    Description = 'El disco reportó un estado FAILED en su autoevaluación SMART.'
                    RecommendationId = 'REC-STO-001'
                    ScoreImpact = -35
                }
            )
            StorageRecommendations = @(
                [pscustomobject][ordered]@{
                    Id = 'REC-STO-001'
                    Title = 'Validate degraded storage'
                    Description = 'Back up important data and run the manufacturer diagnostic before considering disk replacement.'
                    FindingIds = @('STO-006')
                }
            )
        }

        New-InventoryHtml -Inventory $inventory -Path $path

        $html = Get-Content -LiteralPath $path -Raw

        $html | Should -Match 'STO-006'
        # HTML-encoded (ConvertTo-HtmlSafe), same as every other table in this
        # report — matched on the accent-free tail to avoid depending on the
        # numeric-entity encoding of "ó".
        $html | Should -Match 'SMART fallida'
        $html | Should -Match 'REC-STO-001'
        $html | Should -Match 'Validate degraded storage'
        $html | Should -Not -Match 'No se detectaron hallazgos de salud en el almacenamiento\.'
        $html | Should -Not -Match 'No hay recomendaciones de almacenamiento para este equipo\.'
    }

    It 'shows an informational empty-state message, not a blank table, when no disk supports SMART at all' {
        $path = Join-Path $TestDrive 'inventory-smart-unsupported.html'
        $inventory = @{
            Storage = @{
                Physical = @(
                    [ordered]@{
                        Index = 0
                        Model = 'Generic USB Flash Drive'
                        Smart = [ordered]@{
                            Supported = $false
                            Source = 'Unavailable'
                            OverallHealth = $null
                            TemperatureCelsius = $null
                            PowerOnHours = $null
                            ReallocatedSectorCount = $null
                            PendingSectorCount = $null
                            UncorrectableSectorCount = $null
                            AvailableSparePercent = $null
                            PercentageUsed = $null
                        }
                    }
                )
                Detailed = @()
                Logical = @()
                Upgrade = @{}
            }
            StorageFindings = @()
            StorageRecommendations = @()
        }

        New-InventoryHtml -Inventory $inventory -Path $path

        $html = Get-Content -LiteralPath $path -Raw

        $html | Should -Match 'Estado SMART'
        # Accent-free tail of the informational empty-state message (see note
        # above on HTML-entity encoding of accented characters).
        $html | Should -Match 'SMART compatibles en este equipo\.'
        # The disk itself is still listed in the ordinary "Discos físicos"
        # table (Model column) — only the SMART-specific table is suppressed
        # in favor of the informational message, not the whole disk row.
        $smartSectionStart = $html.IndexOf('Estado SMART')
        $smartSectionEnd = $html.IndexOf('Hallazgos de almacenamiento')
        $smartSectionHtml = $html.Substring($smartSectionStart, $smartSectionEnd - $smartSectionStart)
        $smartSectionHtml | Should -Not -Match 'Generic USB Flash Drive'
    }
}
