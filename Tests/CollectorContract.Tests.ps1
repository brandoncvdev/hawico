Describe 'Collector_Windows_HealthCheck.ps1 contract' {
 BeforeAll { $script=Get-Content "$PSScriptRoot/../Collector_Windows_HealthCheck.ps1" -Raw }
 It 'exists and accepts only Diagnostic mode' { $script|Should -Match 'ValidateSet\([''"]Diagnostic[''"]\)' }
 It 'loads every delivery-one module' { foreach($name in @('Get-HealthConfig','Get-HealthCapabilities','Get-PerformanceHealth','Get-StorageHealth','Get-CriticalEvents','Get-HealthFindings','Invoke-HealthCheck','New-HealthCheckReport')){$script|Should -Match ([regex]::Escape($name))} }
 It 'uses distinct health output names' { $script|Should -Match '-health\.json';$script|Should -Match '-health\.html' }
 It 'does not contain repair or optimization commands' { $script|Should -Not -Match '(?i)chkdsk|RestoreHealth|scannow|defrag|Optimize-Volume' }
 It 'produces the documented log artifact and measures the collection' { $script|Should -Match '-health\.log';$script|Should -Match 'LogPath';$script|Should -Match 'Stopwatch' }
 It 'contains independent collection failures instead of aborting later sections' { $script|Should -Match 'Invoke-HealthCollectorSection';$script|Should -Match 'Get-CriticalEventResult' }
 It 'shows collection progress while the diagnostic is running' { $script|Should -Match 'Write-Progress';$script|Should -Match 'PercentComplete' }
 It 'records section error codes and messages in the local log' { $script|Should -Match 'ErrorCode=';$script|Should -Match 'ErrorMessage=' }
 It 'collects the first extended diagnostic slice' {
  foreach($name in @('Get-ExtendedDiagnostics','Get-ProcessDiagnostic','Get-StartupDiagnostic','Get-InstalledSoftwareDiagnostic')){$script|Should -Match ([regex]::Escape($name))}
 }
 It 'writes json/html inside a per-hostname subfolder, not flat in OutputDirectory, matching Collector_Hardware_Inventory.ps1' {
  $script|Should -Match 'Get-InventoryHostOutputDirectory'
  $script|Should -Match '\$hostOutputDir\s*=\s*Get-InventoryHostOutputDirectory\s+-BaseOutputDirectory\s+\$outputDir\s+-Hostname\s+\$hostName'
  $script|Should -Match '\$jsonPath\s*=\s*Join-Path\s+\$hostOutputDir'
  $script|Should -Match '\$htmlPath\s*=\s*Join-Path\s+\$hostOutputDir'
  # LogPath stays flat in LogDirectory — only "el output" was in scope.
  $script|Should -Match '\$logPath\s*=\s*Join-Path\s+\$logDir'
 }
}

Describe 'Collector_Storage_Diagnostic.ps1 contract' {
 BeforeAll { $script=Get-Content "$PSScriptRoot/../Collector_Storage_Diagnostic.ps1" -Raw }
 It 'exists and accepts only Diagnostic mode' { $script|Should -Match 'ValidateSet\([''"]Diagnostic[''"]\)' }
 It 'is Storage-only: no Performance sampling or Events querying' {
  $script|Should -Not -Match 'Get-PerformanceHealth\.ps1'
  $script|Should -Not -Match 'Get-CriticalEvents\.ps1'
  $script|Should -Not -Match 'Get-ExtendedDiagnostics\.ps1'
  $script|Should -Not -Match 'Get-PerformanceSample'
  $script|Should -Not -Match 'Measure-PerformanceHealth'
  $script|Should -Not -Match 'Get-CriticalEventResult'
  $script|Should -Not -Match 'Get-ProcessDiagnostic'
  $script|Should -Not -Match 'Get-StartupDiagnostic'
  $script|Should -Not -Match 'Get-InstalledSoftwareDiagnostic'
 }
 It 'still loads and reuses the storage pipeline and unmodified export/scoring modules' {
  foreach($name in @('Get-HealthConfig','Get-HealthCapabilities','Get-StorageHealth','Get-HealthFindings','Invoke-HealthCheck','New-HealthCheckReport','Export-HealthCheck')){$script|Should -Match ([regex]::Escape($name))}
 }
 It 'does not define a new HTML export function — reuses Export-HealthCheck.ps1 unmodified' {
  $script|Should -Not -Match 'function\s+New-HealthCheckHtml'
  $script|Should -Match 'New-HealthCheckHtml\s+-Report'
 }
 It 'uses distinct storage output names' { $script|Should -Match '-storage\.json';$script|Should -Match '-storage\.html' }
 It 'does not contain repair or optimization commands' { $script|Should -Not -Match '(?i)chkdsk|RestoreHealth|scannow|defrag|Optimize-Volume' }
 It 'produces the documented log artifact and measures the collection' { $script|Should -Match '-storage\.log';$script|Should -Match 'LogPath';$script|Should -Match 'Stopwatch' }
 It 'contains independent collection failures instead of aborting later sections' { $script|Should -Match 'Invoke-HealthCollectorSection' }
 It 'shows collection progress while the diagnostic is running' { $script|Should -Match 'Write-Progress';$script|Should -Match 'PercentComplete' }
 It 'writes json/html inside a per-hostname subfolder, not flat in OutputDirectory, matching the other collectors' {
  $script|Should -Match 'Get-InventoryHostOutputDirectory'
  $script|Should -Match '\$hostOutputDir\s*=\s*Get-InventoryHostOutputDirectory\s+-BaseOutputDirectory\s+\$outputDir\s+-Hostname\s+\$hostName'
  $script|Should -Match '\$jsonPath\s*=\s*Join-Path\s+\$hostOutputDir'
  $script|Should -Match '\$htmlPath\s*=\s*Join-Path\s+\$hostOutputDir'
  $script|Should -Match '\$logPath\s*=\s*Join-Path\s+\$logDir'
 }
}

Describe 'Collector_Hardware_Inventory.ps1 storage health wiring (Phase 8)' {
 BeforeAll { $script=Get-Content "$PSScriptRoot/../Collector_Hardware_Inventory.ps1" -Raw }
 It 'dot-sources the storage-health analysis pipeline modules' {
  foreach($name in @('Get-HealthConfig.ps1','Get-StorageHealth.ps1','Get-HealthFindings.ps1','Invoke-HealthCheck.ps1')){$script|Should -Match ([regex]::Escape($name))}
 }
 It 'runs Get-StorageHealth against the captured storage inventory' {
  $script|Should -Match 'Get-StorageHealth\s+-StorageInventory\s+\$storage\s+-SystemDrive\s+\$env:SystemDrive'
 }
 It 'runs Invoke-HealthCheck with an empty-but-well-formed Performance/Events pair, same as Collector_Storage_Diagnostic.ps1' {
  $script|Should -Match 'Invoke-HealthCheck\s+-InputData'
  $script|Should -Match '(?i)Status\s*=\s*"Skipped"'
 }
 It 'extracts HealthCheck.Findings/Recommendations and attaches them to the inventory result passed to New-InventoryHtml' {
  $script|Should -Match '\$storageHealthCheck\.HealthCheck\.Findings'
  $script|Should -Match '\$storageHealthCheck\.HealthCheck\.Recommendations'
  $script|Should -Match 'StorageFindings\s*=\s*\$storageFindings'
  $script|Should -Match 'StorageRecommendations\s*=\s*\$storageRecommendations'
 }
 It 'never lets a storage-health evaluation failure abort the rest of the inventory collection' {
  $script|Should -Match '(?s)try\s*\{.*Invoke-HealthCheck.*\}\s*catch\s*\{'
 }
}
