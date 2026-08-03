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
    . (Join-Path $basePath "Modules\InventoryAdministration.ps1")

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

    $administration = [ordered]@{
        RecordsPath = ".\Output"
        BasePath = "."
    }

    if ($config.PSObject.Properties.Name -contains "Administration" -and $null -ne $config.Administration) {
        foreach ($propertyName in @("RecordsPath", "BasePath")) {
            if ($config.Administration.PSObject.Properties.Name -contains $propertyName) {
                $administration[$propertyName] = $config.Administration.$propertyName
            }
        }
    }

    $recordsPath = Join-Path $basePath ($administration.RecordsPath -replace '^[.][\\/]', '')

    # Import-InventoryAdministrationSession forwards -AdministrationBasePath
    # straight into Get-InventoryAssetStorePath, which always appends
    # "Administracion\" itself. So this value must resolve to the FOLDER
    # THAT WILL CONTAIN Administracion\ (the repo root by default, "."),
    # never to ".\Administracion" itself — that would create
    # "Administracion\Administracion\...".
    $administrationRootFragment = $administration.BasePath -replace '^[.][\\/]', ''
    $administrationBasePath = if ([string]::IsNullOrWhiteSpace($administrationRootFragment) -or $administrationRootFragment -eq '.') {
        $basePath
    }
    else {
        Join-Path $basePath $administrationRootFragment
    }

    Write-Host ""
    Write-Host "Importando registros de inventario a la administración local..." -ForegroundColor Cyan

    $result = Import-InventoryAdministrationSession `
        -RecordsPath $recordsPath `
        -AdministrationBasePath $administrationBasePath

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " IMPORTACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Nuevos equipos:          $(@($result.NuevosEquipos).Count)"
    Write-Host "Equipos actualizados:    $(@($result.EquiposActualizados).Count)"
    Write-Host "Posibles duplicados:     $(@($result.PosiblesDuplicados).Count)"
    Write-Host "Conflictos:              $(@($result.Conflictos).Count)"
    Write-Host "Errores de recolección:  $(@($result.ErroresRecoleccion).Count)"
    Write-Host "Archivos omitidos:       $(@($result.SkippedFiles).Count)"
    Write-Host ""
    Write-Host "Administración: $administrationBasePath"
    Write-Host ""

    return [ordered]@{
        Success = $true
        NuevosEquipos = $result.NuevosEquipos
        EquiposActualizados = $result.EquiposActualizados
        PosiblesDuplicados = $result.PosiblesDuplicados
        Conflictos = $result.Conflictos
        ErroresRecoleccion = $result.ErroresRecoleccion
        SkippedFiles = $result.SkippedFiles
    }
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " ERROR AL IMPORTAR LOS REGISTROS" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    return [ordered]@{
        Success = $false
        ErrorMessage = $_.Exception.Message
    }
}
