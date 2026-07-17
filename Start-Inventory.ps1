$ErrorActionPreference = "Stop"

try {
    $basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $collector = Join-Path $basePath "Collector_Hardware_Inventory.ps1"
    $configPath = Join-Path $basePath "config.json"

    if (-not (Test-Path -LiteralPath $collector)) {
        throw "No se encontró el recolector principal: $collector"
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "No se encontró el archivo de configuración: $configPath"
    }

    function Pause-Menu {
        Write-Host ""
        [void](Read-Host "Presione Enter para continuar")
    }

    $option = ""

    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "     RECOLECTOR DE INVENTARIO TI" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Equipo: $env:COMPUTERNAME"
        Write-Host "Usuario: $env:USERNAME"
        Write-Host ""
        Write-Host "1. Generar inventario completo"
        Write-Host "2. Generar inventario rápido"
        Write-Host "3. Abrir carpeta de resultados"
        Write-Host "4. Abrir último reporte HTML"
        Write-Host "5. Abrir carpeta de logs"
        Write-Host "6. Salir"
        Write-Host ""

        $option = Read-Host "Seleccione una opción"

        switch ($option) {
            "1" {
                $result = & $collector -Mode Full

                if ($null -ne $result -and $result.Success) {
                    if (Test-Path -LiteralPath $result.HtmlPath) {
                        Start-Process -FilePath $result.HtmlPath
                    }
                }
                else {
                    Write-Host "El inventario no pudo completarse." -ForegroundColor Red
                }

                Pause-Menu
            }

            "2" {
                $result = & $collector -Mode Quick

                if ($null -ne $result -and $result.Success) {
                    if (Test-Path -LiteralPath $result.HtmlPath) {
                        Start-Process -FilePath $result.HtmlPath
                    }
                }
                else {
                    Write-Host "El inventario no pudo completarse." -ForegroundColor Red
                }

                Pause-Menu
            }

            "3" {
                $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                $relativeOutput = $config.OutputDirectory -replace '^[.][\\/]', ''
                $output = Join-Path $basePath $relativeOutput

                New-Item -ItemType Directory -Force -Path $output | Out-Null
                Start-Process -FilePath "explorer.exe" -ArgumentList $output
            }

            "4" {
                $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                $relativeOutput = $config.OutputDirectory -replace '^[.][\\/]', ''
                $output = Join-Path $basePath $relativeOutput

                New-Item -ItemType Directory -Force -Path $output | Out-Null

                $last = Get-ChildItem -LiteralPath $output -Filter "*.html" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1

                if ($null -ne $last) {
                    Start-Process -FilePath $last.FullName
                }
                else {
                    Write-Host "Todavía no existe un reporte HTML." -ForegroundColor Yellow
                    Pause-Menu
                }
            }

            "5" {
                $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                $relativeLogs = $config.LogDirectory -replace '^[.][\\/]', ''
                $logs = Join-Path $basePath $relativeLogs

                New-Item -ItemType Directory -Force -Path $logs | Out-Null
                Start-Process -FilePath "explorer.exe" -ArgumentList $logs
            }

            "6" {
                Write-Host ""
                Write-Host "Cerrando el recolector..."
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
    Write-Host " ERROR AL INICIAR EL RECOLECTOR" -ForegroundColor Red
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
