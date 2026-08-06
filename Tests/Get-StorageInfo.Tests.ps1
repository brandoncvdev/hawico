BeforeAll { . "$PSScriptRoot/../Modules/Get-StorageInfo.ps1" }
Describe 'ConvertFrom-SmartctlJson' {
 It 'parses a successful ATA disk report' {
  $json = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true},"temperature":{"current":34},"power_on_time":{"hours":12000},"power_cycle_count":450,"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":0}},{"id":197,"name":"Current_Pending_Sector","raw":{"value":0}},{"id":198,"name":"Offline_Uncorrectable","raw":{"value":0}}]}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.OverallHealth | Should -Be 'PASSED'
  $r.TemperatureCelsius | Should -Be 34
  $r.PowerOnHours | Should -Be 12000
  $r.PowerCycleCount | Should -Be 450
  $r.ReallocatedSectorCount | Should -Be 0
  $r.PendingSectorCount | Should -Be 0
  $r.UncorrectableSectorCount | Should -Be 0
  $r.AvailableSparePercent | Should -BeNullOrEmpty
  $r.PercentageUsed | Should -BeNullOrEmpty
  $r.MediaErrorCount | Should -BeNullOrEmpty
  $r.CriticalWarningFlags | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
  $r.ErrorMessage | Should -BeNullOrEmpty
 }
 It 'parses a successful NVMe disk report' {
  $json = '{"device":{"protocol":"NVMe"},"smart_status":{"passed":true},"temperature":{"current":40},"power_on_time":{"hours":500},"power_cycle_count":50,"nvme_smart_health_information_log":{"critical_warning":0,"available_spare":100,"percentage_used":5,"media_errors":0}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'NVMe'
  $r.OverallHealth | Should -Be 'PASSED'
  $r.TemperatureCelsius | Should -Be 40
  $r.PowerOnHours | Should -Be 500
  $r.PowerCycleCount | Should -Be 50
  $r.AvailableSparePercent | Should -Be 100
  $r.PercentageUsed | Should -Be 5
  $r.MediaErrorCount | Should -Be 0
  $r.CriticalWarningFlags | Should -Be 0
  $r.ReallocatedSectorCount | Should -BeNullOrEmpty
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
  $r.ErrorMessage | Should -BeNullOrEmpty
 }
 It 'reports a FAILED self-assessment without inventing a passing status' {
  $json = '{"device":{"protocol":"ATA"},"smart_status":{"passed":false}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.OverallHealth | Should -Be 'FAILED'
 }
 It 'never throws and degrades gracefully on truncated JSON text' {
  $truncated = '{"device":{"protocol":"ATA","name":"/dev/sda"'
  { ConvertFrom-SmartctlJson -SmartctlOutput $truncated } | Should -Not -Throw
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $truncated
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'SMARTCTL-PARSE-ERROR'
  $r.ErrorMessage | Should -Not -BeNullOrEmpty
 }
 It 'never throws and degrades gracefully on null output' {
  { ConvertFrom-SmartctlJson -SmartctlOutput $null } | Should -Not -Throw
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $null
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'SMARTCTL-PARSE-ERROR'
 }
 It 'degrades gracefully when the protocol cannot be identified' {
  $json = '{"device":{"protocol":"SCSI"},"smart_status":{"passed":true}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'SMARTCTL-UNKNOWN-PROTOCOL'
  $r.ErrorMessage | Should -Not -BeNullOrEmpty
 }
 It 'leaves individual fields null when the ATA report is missing sub-sections, without failing the whole disk' {
  $json = '{"device":{"protocol":"ATA"}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.OverallHealth | Should -BeNullOrEmpty
  $r.TemperatureCelsius | Should -BeNullOrEmpty
  $r.PowerOnHours | Should -BeNullOrEmpty
  $r.PowerCycleCount | Should -BeNullOrEmpty
  $r.ReallocatedSectorCount | Should -BeNullOrEmpty
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
 }
 It 'leaves individual fields null when the NVMe report is missing sub-sections, without failing the whole disk' {
  $json = '{"device":{"protocol":"NVMe"}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'NVMe'
  $r.AvailableSparePercent | Should -BeNullOrEmpty
  $r.PercentageUsed | Should -BeNullOrEmpty
  $r.MediaErrorCount | Should -BeNullOrEmpty
  $r.CriticalWarningFlags | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
 }
 It 'reads a single ATA attribute correctly despite the single-element-array collapse risk' {
  $json = '{"device":{"protocol":"ATA"},"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":3}}]}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.ReallocatedSectorCount | Should -Be 3
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
 }
}
