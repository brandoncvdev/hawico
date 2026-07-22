[CmdletBinding()]
param(
    [ValidateSet("Diagnostic")][string]$Mode = "Diagnostic",
    [int]$SampleDurationSeconds
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if($Mode -ne "Diagnostic"){throw "Solo se admite el modo Diagnostic."}
$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modules = @("Common.ps1","Get-ComputerInfo.ps1","Get-ProcessorInfo.ps1","Get-MemoryInfo.ps1","Get-StorageInfo.ps1","Get-HealthConfig.ps1","Get-HealthCapabilities.ps1","Get-PerformanceHealth.ps1","Get-StorageHealth.ps1","Get-CriticalEvents.ps1","Get-HealthFindings.ps1","New-HealthCheckReport.ps1","Invoke-HealthCheck.ps1","Export-HealthCheck.ps1")
foreach($module in $modules){. (Join-Path $basePath "Modules/$module")}
$config=Get-Content (Join-Path $basePath "config.json") -Raw|ConvertFrom-Json
$healthConfig=Get-HealthCheckConfig -Config $config
if($SampleDurationSeconds -gt 0){$healthConfig.SampleDurationSeconds=$SampleDurationSeconds}
$outputDir=Join-Path $basePath ($config.OutputDirectory -replace '^[.][\\/]','')
New-Item -ItemType Directory -Force -Path $outputDir|Out-Null
$stamp=Get-Date -Format "yyyyMMdd-HHmmss";$hostName=$env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]','_'
$jsonPath=Join-Path $outputDir "$hostName-$stamp-health.json";$htmlPath=Join-Path $outputDir "$hostName-$stamp-health.html"
$computer=Get-ComputerInventory;$storageInventory=Get-StorageInventory
$samples=@();$count=[math]::Ceiling($healthConfig.SampleDurationSeconds/$healthConfig.SampleIntervalSeconds)
for($i=0;$i-lt$count;$i++){ $samples+=Get-PerformanceSample;if($i-lt($count-1)){Start-Sleep -Seconds $healthConfig.SampleIntervalSeconds} }
$performance=Measure-PerformanceHealth -Samples $samples
$storage=Get-StorageHealth -StorageInventory $storageInventory -SystemDrive $env:SystemDrive
$inputData=[ordered]@{BaseInventory=[ordered]@{Computer=$computer.Computer;OperatingSystem=$computer.OperatingSystem;BIOS=$computer.BIOS;Motherboard=$computer.Motherboard;Processors=Get-ProcessorInventory;Memory=Get-MemoryInventory;Storage=$storageInventory};Capabilities=Get-HealthCapability;Performance=$performance;Storage=$storage;Events=Get-CriticalEvent -LookbackDays $healthConfig.EventLookbackDays}
$report=Invoke-HealthCheck -InputData $inputData -CollectedAt ([datetimeoffset]::Now)
if($healthConfig.GenerateJSON){$report|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $jsonPath -Encoding UTF8}
if($healthConfig.GenerateHTML){New-HealthCheckHtml -Report $report -Path $htmlPath}
return [ordered]@{Success=$true;OutputDirectory=$outputDir;JsonPath=$jsonPath;HtmlPath=$htmlPath}
