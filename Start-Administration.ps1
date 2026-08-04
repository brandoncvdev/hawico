$ErrorActionPreference = "Stop"

try {
    $basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $configPath = Join-Path $basePath "config.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "No se encontró config.json"
    }

    . (Join-Path $basePath "Modules\Common.ps1")
    . (Join-Path $basePath "Modules\New-InventoryCollectionRecord.ps1")
    . (Join-Path $basePath "Modules\InventoryAdministration.ps1")
    . (Join-Path $basePath "Modules\New-InventoryConsolidatedWorkbook.ps1")
    . (Join-Path $basePath "Modules\New-InventoryAdministrationReport.ps1")
    . (Join-Path $basePath "Modules\Export.ps1")

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

    # Reuses the Administration block from Fase 3 (adding ReportsDirectory
    # to it, instead of a new config block) and the Consolidation block
    # from Fase 2 as-is.
    $administration = [ordered]@{
        RecordsPath = ".\Output"
        BasePath = "."
        ReportsDirectory = ".\Administracion\Reportes"
    }

    if ($config.PSObject.Properties.Name -contains "Administration" -and $null -ne $config.Administration) {
        foreach ($propertyName in @("RecordsPath", "BasePath", "ReportsDirectory")) {
            if ($config.Administration.PSObject.Properties.Name -contains $propertyName) {
                $administration[$propertyName] = $config.Administration.$propertyName
            }
        }
    }

    $recordsPath = Join-Path $basePath ($administration.RecordsPath -replace '^[.][\\/]', '')
    $reportsDirectory = Join-Path $basePath ($administration.ReportsDirectory -replace '^[.][\\/]', '')

    # Import-InventoryAdministrationSession forwards -AdministrationBasePath
    # straight into Get-InventoryAssetStorePath, which always appends
    # "Administracion\" itself. So this value must resolve to the FOLDER
    # THAT WILL CONTAIN Administracion\ (the repo root by default, "."),
    # never to ".\Administracion" itself.
    $administrationRootFragment = $administration.BasePath -replace '^[.][\\/]', ''
    $administrationBasePath = if ([string]::IsNullOrWhiteSpace($administrationRootFragment) -or $administrationRootFragment -eq '.') {
        $basePath
    }
    else {
        Join-Path $basePath $administrationRootFragment
    }

    $consolidation = [ordered]@{
        RecordsPath = ".\Output"
        OutputPath = ".\Output\Consolidado.xlsx"
        HistoryDirectory = ".\Output\Historico"
    }

    if ($config.PSObject.Properties.Name -contains "Consolidation" -and $null -ne $config.Consolidation) {
        foreach ($propertyName in @("RecordsPath", "OutputPath", "HistoryDirectory")) {
            if ($config.Consolidation.PSObject.Properties.Name -contains $propertyName) {
                $consolidation[$propertyName] = $config.Consolidation.$propertyName
            }
        }
    }

    $consolidationRecordsPath = Join-Path $basePath ($consolidation.RecordsPath -replace '^[.][\\/]', '')
    $consolidationOutputPath = Join-Path $basePath ($consolidation.OutputPath -replace '^[.][\\/]', '')
    $consolidationHistoryDirectory = Join-Path $basePath ($consolidation.HistoryDirectory -replace '^[.][\\/]', '')

    function Wait-MenuInput {
        Write-Host ""
        [void](Read-Host "Presione Enter para continuar")
    }

    $option = ""

    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "     ADMINISTRACIÓN DE INVENTARIO TI" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1. Importar nuevas capturas"
        Write-Host "2. Ver el último reporte de importación"
        Write-Host "3. Resolver un conflicto manualmente"
        Write-Host "4. Generar Excel consolidado"
        Write-Host "5. Abrir carpeta de administración"
        Write-Host "6. Salir"
        Write-Host ""

        $option = Read-Host "Seleccione una opción"

        switch ($option) {
            "1" {
                $result = Import-InventoryAdministrationSession `
                    -RecordsPath $recordsPath `
                    -AdministrationBasePath $administrationBasePath

                Write-Host ""
                Write-Host "Nuevos equipos:          $(@($result.NuevosEquipos).Count)"
                Write-Host "Equipos actualizados:    $(@($result.EquiposActualizados).Count)"
                Write-Host "Posibles duplicados:     $(@($result.PosiblesDuplicados).Count)"
                Write-Host "Conflictos:              $(@($result.Conflictos).Count)"
                Write-Host "Errores de recolección:  $(@($result.ErroresRecoleccion).Count)"
                Write-Host "Archivos omitidos:       $(@($result.SkippedFiles).Count)"

                New-Item -ItemType Directory -Force -Path $reportsDirectory | Out-Null
                $reportTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $reportPath = Join-Path $reportsDirectory "Importacion-$reportTimestamp.html"
                New-InventoryAdministrationReport -ImportResult $result -OutputPath $reportPath | Out-Null

                Write-Host ""
                Write-Host "Reporte: $reportPath"

                if (Test-Path -LiteralPath $reportPath) {
                    Start-Process -FilePath $reportPath
                }

                Wait-MenuInput
            }

            "2" {
                New-Item -ItemType Directory -Force -Path $reportsDirectory | Out-Null

                $last = Get-ChildItem -LiteralPath $reportsDirectory -Filter "Importacion-*.html" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1

                if ($null -ne $last) {
                    Start-Process -FilePath $last.FullName
                }
                else {
                    Write-Host "Todavía no existe un reporte de importación." -ForegroundColor Yellow
                    Wait-MenuInput
                }
            }

            "3" {
                Write-Host ""
                $assetId = Read-Host "AssetId"
                $key = Read-Host "Key"
                $newValue = Read-Host "Nuevo valor"
                $reviewedBy = Read-Host "Revisado por"
                $reason = Read-Host "Motivo [Enter para omitir]"
                $reasonParameter = if ([string]::IsNullOrWhiteSpace($reason)) { $null } else { $reason }

                try {
                    $applied = Add-InventoryAssetManualReview `
                        -AdministrationBasePath $administrationBasePath `
                        -AssetId $assetId `
                        -Key $key `
                        -NewValue $newValue `
                        -ReviewedBy $reviewedBy `
                        -Reason $reasonParameter

                    Write-Host ""
                    Write-Host "Campo actualizado correctamente." -ForegroundColor Green
                    Write-Host "Valor: $($applied.Value)"
                    Write-Host "Fuente: $($applied.Source)"
                }
                catch {
                    Write-Host ""
                    Write-Host "No se pudo aplicar la revisión: $($_.Exception.Message)" -ForegroundColor Red
                }

                Wait-MenuInput
            }

            "4" {
                if (-not (Install-InventoryImportExcelIfNeeded)) {
                    Write-Host "No se puede generar el Excel sin ImportExcel instalado." -ForegroundColor Yellow
                    Wait-MenuInput
                }
                else {
                    $result = Export-InventoryConsolidatedWorkbook `
                        -RecordsPath $consolidationRecordsPath `
                        -OutputPath $consolidationOutputPath `
                        -HistoryDirectory $consolidationHistoryDirectory

                    Write-Host ""
                    Write-Host "Equipos procesados: $($result.RecordCount)"
                    Write-Host "Workbook: $($result.OutputPath)"

                    if (Test-Path -LiteralPath $result.OutputPath) {
                        Start-Process -FilePath $result.OutputPath
                    }

                    Wait-MenuInput
                }
            }

            "5" {
                $store = Get-InventoryAssetStorePath -BasePath $administrationBasePath
                $administracionFolder = Split-Path -Parent $store.IndexPath

                New-Item -ItemType Directory -Force -Path $administracionFolder | Out-Null
                Start-Process -FilePath "explorer.exe" -ArgumentList $administracionFolder
            }

            "6" {
                Write-Host ""
                Write-Host "Cerrando la administración..."
            }

            default {
                Write-Host "Opción no válida." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
    while ($option -ne "6")

    return
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " ERROR AL INICIAR LA ADMINISTRACIÓN" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Archivo: $($_.InvocationInfo.ScriptName)"
    Write-Host "Línea: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host ""
    [void](Read-Host "Presione Enter para cerrar")
    return
}
