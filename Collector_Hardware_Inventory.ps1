[CmdletBinding()]
param(
    [ValidateSet("Quick","Full")]
    [string]$Mode = "Full"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $basePath "config.json"

if (-not (Test-Path $configPath)) {
    throw "No se encontró config.json"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

$moduleFiles = @(
    "Common.ps1",
    "Get-ComputerInfo.ps1",
    "Get-ProcessorInfo.ps1",
    "Get-MemoryInfo.ps1",
    "Get-NetworkInfo.ps1",
    "Get-StorageInfo.ps1",
    "Get-GraphicsInfo.ps1",
    "Get-UpgradeInfo.ps1",
    "Get-SecurityInfo.ps1",
    "Get-DeviceErrors.ps1",
    "Export.ps1"
)

foreach ($module in $moduleFiles) {
    . (Join-Path $basePath "Modules\$module")
}

$outputDir = Join-Path $basePath ($config.OutputDirectory -replace '^[.][\\/]', '')
$logDir = Join-Path $basePath ($config.LogDirectory -replace '^[.][\\/]', '')

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$hostname = $env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_'
$jsonPath = Join-Path $outputDir "$hostname-$timestamp.json"
$htmlPath = Join-Path $outputDir "$hostname-$timestamp.html"
$logPath = Join-Path $logDir "$hostname-$timestamp.log"

try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host ""
    Write-Host "Recopilando información del equipo..." -ForegroundColor Cyan

    $computerInfo = Get-ComputerInventory
    Write-Progress -Activity "Inventario de hardware" -Status "Procesador" -PercentComplete 15

    $processors = Get-ProcessorInventory
    Write-Progress -Activity "Inventario de hardware" -Status "Memoria" -PercentComplete 30

    $memory = Get-MemoryInventory
    Write-Progress -Activity "Inventario de hardware" -Status "Red" -PercentComplete 45

    $network = Get-NetworkInventory `
        -IncludeIPv6 ([bool]$config.IncludeIPv6) `
        -IncludeDisconnectedAdapters ([bool]$config.IncludeDisconnectedAdapters)

    Write-Progress -Activity "Inventario de hardware" -Status "Almacenamiento" -PercentComplete 60
    $storage = Get-StorageInventory

    $graphics = @()
    $expansion = [ordered]@{ Slots = @(); Summary = @{} }
    $security = @{}
    $deviceErrors = @()

    if ($Mode -eq "Full") {
        Write-Progress -Activity "Inventario de hardware" -Status "Gráficos y expansión" -PercentComplete 75
        $graphics = Get-GraphicsInventory
        $expansion = Get-ExpansionSlotInventory

        Write-Progress -Activity "Inventario de hardware" -Status "Seguridad y dispositivos" -PercentComplete 88
        $security = Get-SecurityInventory

        if ([bool]$config.IncludeDeviceErrors) {
            $deviceErrors = Get-DeviceErrorInventory
        }
    }

    $inventory = [ordered]@{
        SchemaVersion = "2.0"
        Collection = [ordered]@{
            CollectedAt = (Get-Date).ToString("o")
            Mode = $Mode
            ScriptUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        Computer = $computerInfo.Computer
        OperatingSystem = $computerInfo.OperatingSystem
        BIOS = $computerInfo.BIOS
        Motherboard = $computerInfo.Motherboard
        Processors = $processors
        Memory = $memory
        NetworkAdapters = $network
        Storage = $storage
        GraphicsAdapters = $graphics
        Expansion = $expansion
        Security = $security
        DevicesWithErrors = $deviceErrors
    }

    if ([bool]$config.GenerateJSON) {
        $inventory | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    }

    if ([bool]$config.GenerateHTML) {
        New-InventoryHtml -Inventory $inventory -Path $htmlPath
    }

    Write-Progress -Activity "Inventario de hardware" -Completed

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " INVENTARIO COMPLETADO CORRECTAMENTE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Equipo: $env:COMPUTERNAME"
    Write-Host "Modo: $Mode"
    if ([bool]$config.GenerateJSON) { Write-Host "JSON: $jsonPath" }
    if ([bool]$config.GenerateHTML) { Write-Host "HTML: $htmlPath" }
    Write-Host "LOG: $logPath"
    Write-Host ""

    return [ordered]@{
        Success = $true
        OutputDirectory = $outputDir
        JsonPath = $jsonPath
        HtmlPath = $htmlPath
        LogPath = $logPath
    }
}
catch {
    Write-Error ("No se pudo completar el inventario: {0}" -f $_.Exception.Message)
    Write-Host ""
    Write-Host "No se pudo completar el inventario." -ForegroundColor Red
    Write-Host ("Mensaje: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Posición: {0}" -f $_.InvocationInfo.PositionMessage) -ForegroundColor Yellow
    Write-Host ("Stack trace: {0}" -f $_.ScriptStackTrace) -ForegroundColor DarkYellow
    Write-Host ""

    return [ordered]@{
        Success = $false
        OutputDirectory = $outputDir
        LogPath = $logPath
        ErrorMessage = $_.Exception.Message
        ErrorPosition = $_.InvocationInfo.PositionMessage
        ErrorStackTrace = $_.ScriptStackTrace
    }
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
