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
}
