[CmdletBinding()]
param(
    [ValidateSet('Diagnostic')][string]$Mode = 'Diagnostic'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Mode -ne 'Diagnostic') { throw 'Solo se admite el modo Diagnostic.' }
$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
# Storage-only diagnostic: reuses Invoke-HealthCheck + Export-HealthCheck.ps1
# unmodified for scoring/HTML (design.md), so this module list intentionally
# leaves out the performance-sampling, critical-events and extended
# diagnostics modules used by Collector_Windows_HealthCheck.ps1 — no
# CPU/Memory sampling and no event-log querying happen in this collector.
$modules = @(
    'Common.ps1',
    'Get-ComputerInfo.ps1',
    'Get-ProcessorInfo.ps1',
    'Get-MemoryInfo.ps1',
    'Get-StorageInfo.ps1',
    'Get-HealthConfig.ps1',
    'Get-HealthCapabilities.ps1',
    'Get-StorageHealth.ps1',
    'Get-HealthFindings.ps1',
    'New-HealthCheckReport.ps1',
    'Invoke-HealthCheck.ps1',
    'Invoke-HealthCollectorSection.ps1',
    'Export-HealthCheck.ps1'
)
foreach ($module in $modules) { . (Join-Path $basePath "Modules/$module") }

$configPath = Join-Path $basePath 'config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$healthConfig = Get-HealthCheckConfig -Config $config

$outputDir = Join-Path $basePath ($config.OutputDirectory -replace '^[.][\\/]', '')
$logDir = Join-Path $basePath ($config.LogDirectory -replace '^[.][\\/]', '')
New-Item -ItemType Directory -Force -Path $outputDir, $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hostName = [string]$env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_'
if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'UNKNOWN' }
# Same per-hostname subfolder as the other collectors, so a machine's storage
# diagnostic output lands next to its inventory/health-check output instead
# of a separate flat file elsewhere in OutputDirectory. This collector never
# runs manual capture, so it cannot independently know the assigned user's
# display name — reuse whatever folder Collector_Hardware_Inventory.ps1
# already created (display-name suffix included) instead of creating a
# second, differently-named duplicate. Only fall back to a hostname-only
# folder when no prior folder exists yet for this machine (first-ever
# collection here).
$hostOutputDir = Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $outputDir -Hostname $hostName
if ($null -eq $hostOutputDir) {
    $hostOutputDir = Get-InventoryHostOutputDirectory -BaseOutputDirectory $outputDir -Hostname $hostName
}
New-Item -ItemType Directory -Force -Path $hostOutputDir | Out-Null
$jsonPath = Join-Path $hostOutputDir "$hostName-$stamp-storage.json"
$htmlPath = Join-Path $hostOutputDir "$hostName-$stamp-storage.html"
$logPath = Join-Path $logDir "$hostName-$stamp-storage.log"
$collectionTimer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Progress -Activity 'Diagnóstico de almacenamiento' -Status 'Detectando capacidades' -PercentComplete 10
$capabilityResult = Invoke-HealthCollectorSection -Name 'Capabilities' -DefaultData ([ordered]@{ IsAdministrator = $false; Items = @() }) -Operation { Get-HealthCapability }
Write-Progress -Activity 'Diagnóstico de almacenamiento' -Status 'Recopilando inventario base' -PercentComplete 25
$computerResult = Invoke-HealthCollectorSection -Name 'Computer' -DefaultData ([ordered]@{ Computer = @{}; OperatingSystem = @{}; BIOS = @{}; Motherboard = @{} }) -Operation { Get-ComputerInventory }
$processorResult = Invoke-HealthCollectorSection -Name 'Processors' -DefaultData @() -Operation { @(Get-ProcessorInventory) }
$memoryResult = Invoke-HealthCollectorSection -Name 'MemoryInventory' -DefaultData @{} -Operation { Get-MemoryInventory }
$storageInventoryResult = Invoke-HealthCollectorSection -Name 'StorageInventory' -DefaultData ([ordered]@{ Physical = @(); Detailed = @(); Logical = @() }) -Operation { Get-StorageInventory }

Write-Progress -Activity 'Diagnóstico de almacenamiento' -Status 'Evaluando almacenamiento' -PercentComplete 70
$storageResult = Invoke-HealthCollectorSection -Name 'Storage' -DefaultData ([ordered]@{ Status = 'Failed'; PhysicalDisks = @(); Volumes = @() }) -Operation {
    Get-StorageHealth -StorageInventory $storageInventoryResult.Data -SystemDrive $env:SystemDrive
}

$collectionTimer.Stop()

# Empty-but-well-formed Performance (CPU/Memory) and Events sections: this
# collector never samples performance counters or queries the event log, so
# Invoke-HealthCheck (reused unmodified, see design.md) marks those
# categories Unavailable and only Storage Available. That makes
# Score.Status = InsufficientData, which is accurate — no CPU/Memory/Events
# evidence was ever collected here.
$performanceData = [ordered]@{ Status = 'Skipped'; ValidSampleCount = 0; CPU = @{}; Memory = @{} }
$performanceSection = [pscustomobject][ordered]@{
    Name = 'Performance'
    Status = 'Skipped'
    StartedAt = [datetimeoffset]::Now
    DurationMilliseconds = 0
    SampleCount = 0
    ErrorCode = $null
    ErrorMessage = 'Performance sampling is out of scope for the storage-only diagnostic.'
}
$eventSection = [pscustomobject][ordered]@{
    Name = 'Events'
    Status = 'Skipped'
    StartedAt = [datetimeoffset]::Now
    DurationMilliseconds = 0
    SampleCount = 0
    ErrorCode = $null
    ErrorMessage = 'Event log evaluation is out of scope for the storage-only diagnostic.'
}

$inventorySections = @($computerResult.Section, $processorResult.Section, $memoryResult.Section, $storageInventoryResult.Section)
$inventoryStatus = if (@($inventorySections | Where-Object Status -eq 'Failed').Count -eq 0) { 'Collected' } else { 'Partial' }
$inventorySection = [pscustomobject][ordered]@{
    Name = 'Inventory'
    Status = $inventoryStatus
    StartedAt = $inventorySections[0].StartedAt
    DurationMilliseconds = [long](Get-HealthNumericSum -Items $inventorySections -PropertyName 'DurationMilliseconds')
    SampleCount = $null
    ErrorCode = if ($inventoryStatus -eq 'Partial') { 'INVENTORY-COLLECTION-PARTIAL' } else { $null }
    ErrorMessage = if ($inventoryStatus -eq 'Partial') { 'One or more base inventory providers failed.' } else { $null }
}
$inputData = [ordered]@{
    BaseInventory = [ordered]@{
        Computer = $computerResult.Data.Computer
        OperatingSystem = $computerResult.Data.OperatingSystem
        BIOS = $computerResult.Data.BIOS
        Motherboard = $computerResult.Data.Motherboard
        Processors = @($processorResult.Data)
        Memory = $memoryResult.Data
        Storage = $storageInventoryResult.Data
    }
    Capabilities = $capabilityResult.Data
    HealthConfig = $healthConfig
    Performance = $performanceData
    Storage = $storageResult.Data
    Events = @()
    EventStatus = 'Skipped'
    EventErrors = @()
    ExtendedDiagnostics = [ordered]@{ ContractVersion = '1.0' }
    Sections = @($inventorySection, $capabilityResult.Section, $performanceSection, $storageResult.Section, $eventSection)
    Sample = [ordered]@{
        RequestedDurationSeconds = $null
        ActualDurationSeconds = $null
        IntervalSeconds = $null
        ValidSampleCount = 0
    }
}
Write-Progress -Activity 'Diagnóstico de almacenamiento' -Status 'Generando reporte' -PercentComplete 95
$report = Invoke-HealthCheck -InputData $inputData -CollectedAt ([datetimeoffset]::Now) -DurationMilliseconds $collectionTimer.ElapsedMilliseconds

$logLines = @(
    "CollectedAt=$($report.Collection.CollectedAt)",
    "Status=$($report.HealthCheck.Status)",
    "DurationMilliseconds=$($report.Collection.DurationMilliseconds)"
)
$logLines += @($report.HealthCheck.Sections | ForEach-Object { "Section=$($_.Name);Status=$($_.Status);DurationMilliseconds=$($_.DurationMilliseconds);ErrorCode=$($_.ErrorCode);ErrorMessage=$($_.ErrorMessage)" })
$logLines | Set-Content -LiteralPath $logPath -Encoding UTF8

$jsonWritten = $false
$htmlWritten = $false
if ($healthConfig.GenerateJSON) {
    $report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $jsonWritten = $true
}
if ($healthConfig.GenerateHTML) {
    New-HealthCheckHtml -Report $report -Path $htmlPath
    $htmlWritten = $true
}
Write-Progress -Activity 'Diagnóstico de almacenamiento' -Completed
return [ordered]@{
    Success = (-not $healthConfig.GenerateJSON -or $jsonWritten) -and (-not $healthConfig.GenerateHTML -or $htmlWritten)
    OutputDirectory = $outputDir
    JsonPath = if ($jsonWritten) { $jsonPath } else { $null }
    HtmlPath = if ($htmlWritten) { $htmlPath } else { $null }
    LogPath = $logPath
}
