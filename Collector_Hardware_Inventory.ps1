[CmdletBinding()]
param(
    [ValidateSet("Quick","Full")]
    [string]$Mode = "Full",
    [string]$SessionId = "SES-UNASSIGNED",
    [AllowNull()][string]$Technician = $null,
    [AllowNull()][string[]]$ManualFieldKeys = $null,
    [AllowNull()][object[]]$OrganizationUnits = $null,
    [AllowNull()][object[]]$DepartmentUnits = $null,
    [AllowNull()][hashtable]$PresetManualFieldValues = $null,
    [AllowNull()][hashtable]$FieldLabels = $null
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
    "New-InventoryCollectionRecord.ps1",
    "New-InventoryManualCapture.ps1",
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

# Every artifact for this computer lands under its own subfolder instead of
# flat in OutputDirectory, grouping one machine's whole history together
# (Modules\Common.ps1's Get-InventoryHostOutputDirectory). Record-discovery
# for Excel consolidation and administration import already scans
# recursively (Get-InventoryConsolidatedRecords -Recurse), so this does not
# break either of those; only Start-Inventory.ps1's "abrir último
# reporte"/"diagnóstico" menu options needed -Recurse added for the same reason.
$hostOutputDir = Get-InventoryHostOutputDirectory -BaseOutputDirectory $outputDir -Hostname $hostname
New-Item -ItemType Directory -Force -Path $hostOutputDir | Out-Null

$jsonPath = Join-Path $hostOutputDir "$hostname-$timestamp.json"
$recordJsonPath = Join-Path $hostOutputDir "$hostname-$timestamp-record.json"
$htmlPath = Join-Path $hostOutputDir "$hostname-$timestamp.html"
$logPath = Join-Path $logDir "$hostname-$timestamp.log"

try {
    Start-Transcript -Path $logPath -Force | Out-Null
}
catch {
    Write-Verbose ("No se pudo iniciar la transcripción: {0}" -f $_.Exception.Message)
}

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

    $collectedAt = [datetimeoffset]::Now
    $scriptUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    $inventory = [ordered]@{
        SchemaVersion = "2.0"
        Collection = [ordered]@{
            CollectedAt = $collectedAt.ToString("o")
            Mode = $Mode
            ScriptUser = $scriptUser
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

    # The launcher resolves the active organization profile's manual fields
    # and passes them in as -ManualFieldKeys. Direct standalone invocation
    # (no launcher involved) still works: it falls back to config.json's
    # flat ManualFields list, exactly as before organization packages
    # existed. The fallback/array-shape logic lives in
    # Resolve-InventoryManualFieldKeys / Resolve-InventoryOrganizationUnits
    # (Modules/Common.ps1) instead of inline here, so it can be covered by a
    # real runtime test (array vs. bare scalar) instead of only the text
    # contract test this script itself gets.
    $configManualFields = $null
    if ($config.PSObject.Properties.Name -contains "ManualFields") {
        $configManualFields = $config.ManualFields
    }
    $resolvedManualFieldKeys = Resolve-InventoryManualFieldKeys -PassedKeys $ManualFieldKeys -ConfigManualFields $configManualFields

    $resolvedOrganizationUnits = Resolve-InventoryOrganizationUnits -PassedUnits $OrganizationUnits

    # Resolve-InventoryOrganizationUnits is a generic array-shape resolver
    # (fallback-to-empty-array plus the same comma-guard), not specific to
    # any one catalog — reused here for the independent, flat department
    # catalog (doc07-Catalog-System.md) instead of a near-duplicate function.
    $resolvedDepartmentUnits = Resolve-InventoryOrganizationUnits -PassedUnits $DepartmentUnits

    # else { @() } would collapse to $null when this branch is taken (no
    # manual fields configured at all) — same if-expression-assignment
    # hazard as the fix above, found via a full-repo sweep for this exact
    # pattern after the collector broke for real on Windows PowerShell 5.1.
    $manualFields = if ($resolvedManualFieldKeys.Count -gt 0) {
        Read-InventoryManualCapture -FieldKeys $resolvedManualFieldKeys -Technician $Technician `
            -OrganizationUnits $resolvedOrganizationUnits -DepartmentUnits $resolvedDepartmentUnits `
            -PresetValues $PresetManualFieldValues -FieldLabels $FieldLabels
    }
    else {
        ,@()
    }

    $collectorVersion = Get-CollectorVersion -BasePath $basePath

    $collectionRecord = New-InventoryCollectionRecord `
        -Inventory $inventory `
        -SessionId $SessionId `
        -CollectorVersion $collectorVersion `
        -CollectedAt $collectedAt `
        -ManualFields $manualFields

    if ([bool]$config.GenerateJSON) {
        $inventory | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        $collectionRecord | ConvertTo-Json -Depth 16 | Set-Content `
            -LiteralPath $recordJsonPath `
            -Encoding UTF8
    }

    if ([bool]$config.GenerateHTML) {
        New-InventoryHtml -Inventory $inventory -Path $htmlPath -ManualFields $manualFields
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
    if ([bool]$config.GenerateJSON) { Write-Host "Registro importable: $recordJsonPath" }
    if ([bool]$config.GenerateHTML) { Write-Host "HTML: $htmlPath" }
    Write-Host "LOG: $logPath"
    Write-Host ""

    return [ordered]@{
        Success = $true
        OutputDirectory = $outputDir
        JsonPath = $jsonPath
        RecordJsonPath = $recordJsonPath
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
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        Write-Verbose ("No se pudo detener la transcripción: {0}" -f $_.Exception.Message)
    }
}
