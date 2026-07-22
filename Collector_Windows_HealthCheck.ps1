[CmdletBinding()]
param(
    [ValidateSet('Diagnostic')][string]$Mode = 'Diagnostic',
    [ValidateRange(10, 300)][Nullable[int]]$SampleDurationSeconds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Mode -ne 'Diagnostic') { throw 'Solo se admite el modo Diagnostic.' }
$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modules = @(
    'Common.ps1',
    'Get-ComputerInfo.ps1',
    'Get-ProcessorInfo.ps1',
    'Get-MemoryInfo.ps1',
    'Get-StorageInfo.ps1',
    'Get-HealthConfig.ps1',
    'Get-HealthCapabilities.ps1',
    'Get-PerformanceHealth.ps1',
    'Get-StorageHealth.ps1',
    'Get-CriticalEvents.ps1',
    'Get-HealthFindings.ps1',
    'New-HealthCheckReport.ps1',
    'Invoke-HealthCheck.ps1',
    'Invoke-HealthCollectorSection.ps1',
    'Export-HealthCheck.ps1'
)
foreach ($module in $modules) { . (Join-Path $basePath "Modules/$module") }

$configPath = Join-Path $basePath 'config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($null -ne $SampleDurationSeconds) {
    if ($config.PSObject.Properties.Name -notcontains 'HealthCheck') { $config | Add-Member -MemberType NoteProperty -Name HealthCheck -Value ([pscustomobject]@{}) }
    if ($config.HealthCheck.PSObject.Properties.Name -contains 'SampleDurationSeconds') { $config.HealthCheck.SampleDurationSeconds = $SampleDurationSeconds.Value }
    else { $config.HealthCheck | Add-Member -MemberType NoteProperty -Name SampleDurationSeconds -Value $SampleDurationSeconds.Value }
}
$healthConfig = Get-HealthCheckConfig -Config $config

$outputDir = Join-Path $basePath ($config.OutputDirectory -replace '^[.][\\/]', '')
$logDir = Join-Path $basePath ($config.LogDirectory -replace '^[.][\\/]', '')
New-Item -ItemType Directory -Force -Path $outputDir, $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hostName = [string]$env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_'
if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'UNKNOWN' }
$jsonPath = Join-Path $outputDir "$hostName-$stamp-health.json"
$htmlPath = Join-Path $outputDir "$hostName-$stamp-health.html"
$logPath = Join-Path $logDir "$hostName-$stamp-health.log"
$collectionTimer = [System.Diagnostics.Stopwatch]::StartNew()

$capabilityResult = Invoke-HealthCollectorSection -Name 'Capabilities' -DefaultData ([ordered]@{ IsAdministrator = $false; Items = @() }) -Operation { Get-HealthCapability }
$computerResult = Invoke-HealthCollectorSection -Name 'Computer' -DefaultData ([ordered]@{ Computer = @{}; OperatingSystem = @{}; BIOS = @{}; Motherboard = @{} }) -Operation { Get-ComputerInventory }
$processorResult = Invoke-HealthCollectorSection -Name 'Processors' -DefaultData @() -Operation { @(Get-ProcessorInventory) }
$memoryResult = Invoke-HealthCollectorSection -Name 'MemoryInventory' -DefaultData @{} -Operation { Get-MemoryInventory }
$storageInventoryResult = Invoke-HealthCollectorSection -Name 'StorageInventory' -DefaultData ([ordered]@{ Physical = @(); Detailed = @(); Logical = @() }) -Operation { Get-StorageInventory }

$performanceResult = Invoke-HealthCollectorSection -Name 'Performance' -DefaultData ([ordered]@{ Status = 'Failed'; ValidSampleCount = 0; CPU = @{}; Memory = @{} }) -Operation {
    $samples = @()
    $sampleCount = [math]::Ceiling($healthConfig.SampleDurationSeconds / $healthConfig.SampleIntervalSeconds)
    for ($index = 0; $index -lt $sampleCount; $index++) {
        $samples += Get-PerformanceSample
        if ($index -lt ($sampleCount - 1)) { Start-Sleep -Seconds $healthConfig.SampleIntervalSeconds }
    }
    Measure-PerformanceHealth -Samples $samples -Thresholds $healthConfig
}
$storageResult = Invoke-HealthCollectorSection -Name 'Storage' -DefaultData ([ordered]@{ Status = 'Failed'; PhysicalDisks = @(); Volumes = @() }) -Operation {
    Get-StorageHealth -StorageInventory $storageInventoryResult.Data -SystemDrive $env:SystemDrive
}
$eventResult = Invoke-HealthCollectorSection -Name 'Events' -DefaultData ([ordered]@{ Status = 'Failed'; Events = @(); ErrorCode = 'EVENT-QUERY-FAILED'; ErrorMessage = 'Event collection failed.' }) -Operation {
    Get-CriticalEventResult -LookbackDays $healthConfig.EventLookbackDays
}

$collectionTimer.Stop()
$inventorySections = @($computerResult.Section, $processorResult.Section, $memoryResult.Section, $storageInventoryResult.Section)
$inventoryStatus = if (@($inventorySections | Where-Object Status -eq 'Failed').Count -eq 0) { 'Collected' } else { 'Partial' }
$inventorySection = [pscustomobject][ordered]@{
    Name = 'Inventory'
    Status = $inventoryStatus
    StartedAt = $inventorySections[0].StartedAt
    DurationMilliseconds = [long](($inventorySections | Measure-Object -Property DurationMilliseconds -Sum).Sum)
    SampleCount = $null
    ErrorCode = if ($inventoryStatus -eq 'Partial') { 'INVENTORY-COLLECTION-PARTIAL' } else { $null }
    ErrorMessage = if ($inventoryStatus -eq 'Partial') { 'One or more base inventory providers failed.' } else { $null }
}
$actualSampleSeconds = [math]::Round($performanceResult.Section.DurationMilliseconds / 1000, 2)
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
    Performance = $performanceResult.Data
    Storage = $storageResult.Data
    Events = @($eventResult.Data.Events)
    EventStatus = $eventResult.Section.Status
    Sections = @($inventorySection, $capabilityResult.Section, $performanceResult.Section, $storageResult.Section, $eventResult.Section)
    Sample = [ordered]@{
        RequestedDurationSeconds = $healthConfig.SampleDurationSeconds
        ActualDurationSeconds = $actualSampleSeconds
        IntervalSeconds = $healthConfig.SampleIntervalSeconds
        ValidSampleCount = [int]$performanceResult.Data.ValidSampleCount
    }
}
$report = Invoke-HealthCheck -InputData $inputData -CollectedAt ([datetimeoffset]::Now) -DurationMilliseconds $collectionTimer.ElapsedMilliseconds

$logLines = @(
    "CollectedAt=$($report.Collection.CollectedAt)",
    "Status=$($report.HealthCheck.Status)",
    "DurationMilliseconds=$($report.Collection.DurationMilliseconds)"
)
$logLines += @($report.HealthCheck.Sections | ForEach-Object { "Section=$($_.Name);Status=$($_.Status);DurationMilliseconds=$($_.DurationMilliseconds)" })
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
return [ordered]@{
    Success = (-not $healthConfig.GenerateJSON -or $jsonWritten) -and (-not $healthConfig.GenerateHTML -or $htmlWritten)
    OutputDirectory = $outputDir
    JsonPath = if ($jsonWritten) { $jsonPath } else { $null }
    HtmlPath = if ($htmlWritten) { $htmlPath } else { $null }
    LogPath = $logPath
}
