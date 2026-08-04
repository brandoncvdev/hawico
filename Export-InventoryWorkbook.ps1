[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

try {
    $basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $configPath = Join-Path $basePath "config.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "No se encontró config.json"
    }

    . (Join-Path $basePath "Modules\Common.ps1")
    . (Join-Path $basePath "Modules\New-InventoryConsolidatedWorkbook.ps1")

    if (-not (Install-InventoryImportExcelIfNeeded)) {
        throw "El módulo ImportExcel es necesario para generar el Excel consolidado."
    }

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

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

    $recordsPath = Join-Path $basePath ($consolidation.RecordsPath -replace '^[.][\\/]', '')
    $outputPath = Join-Path $basePath ($consolidation.OutputPath -replace '^[.][\\/]', '')
    $historyDirectory = Join-Path $basePath ($consolidation.HistoryDirectory -replace '^[.][\\/]', '')

    Write-Host ""
    Write-Host "Consolidando registros de inventario..." -ForegroundColor Cyan

    $result = Export-InventoryConsolidatedWorkbook `
        -RecordsPath $recordsPath `
        -OutputPath $outputPath `
        -HistoryDirectory $historyDirectory

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " CONSOLIDACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Equipos procesados:      $($result.RecordCount)"
    Write-Host "Archivos omitidos:       $($result.SkippedCount)"
    Write-Host "Pendientes de revisión:  $($result.PendingCount)"
    Write-Host "Workbook:  $($result.OutputPath)"
    if (-not [string]::IsNullOrWhiteSpace($result.HistoryPath)) {
        Write-Host "Histórico: $($result.HistoryPath)"
    }
    Write-Host ""

    return [ordered]@{
        Success = $true
        OutputPath = $result.OutputPath
        HistoryPath = $result.HistoryPath
        RecordCount = $result.RecordCount
        SkippedCount = $result.SkippedCount
        PendingCount = $result.PendingCount
    }
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " ERROR AL CONSOLIDAR EL INVENTARIO" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    return [ordered]@{
        Success = $false
        ErrorMessage = $_.Exception.Message
    }
}
