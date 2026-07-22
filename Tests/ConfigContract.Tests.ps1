Describe 'config.json HealthCheck contract' {
 It 'contains the documented validated defaults' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.HealthCheck.SampleDurationSeconds|Should -Be 60
  $c.HealthCheck.SampleIntervalSeconds|Should -Be 1
  $c.HealthCheck.EventLookbackDays|Should -Be 7
  $c.HealthCheck.MinimumFreeDiskPercent|Should -Be 20
  $c.HealthCheck.CriticalFreeDiskPercent|Should -Be 10
  $c.HealthCheck.MemoryWarningPercent|Should -Be 70
  $c.HealthCheck.MemoryHighPercent|Should -Be 85
  $c.HealthCheck.MemoryCriticalPercent|Should -Be 95
 }
}
