BeforeAll { . "$PSScriptRoot/../Modules/Get-HealthFindings.ps1"; . "$PSScriptRoot/../Modules/New-HealthCheckReport.ps1"; . "$PSScriptRoot/../Modules/Invoke-HealthCheck.ps1" }
Describe 'Invoke-HealthCheck' {
 It 'orchestrates metrics findings score and the compatible report' {
  $input=[ordered]@{BaseInventory=[ordered]@{Computer=@{Hostname='PC1'}};Capabilities=@{Items=@()};Performance=@{Status='Collected';CPU=@{AverageUsagePercent=92;SamplesAtOrAbove90Percent=80};Memory=@{AverageUsagePercent=20}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@()}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]'2026-01-01T00:00:00Z')
  $r.SchemaVersion|Should -Be '2.0'
  $r.HealthCheck.Findings.Id|Should -Contain 'CPU-001'
  $r.HealthCheck.Status|Should -Be 'Completed'
 }
 It 'marks the report partial when a required section failed' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{};Performance=@{Status='Failed';CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@()}
  (Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)).HealthCheck.Status|Should -Be 'Partial'
 }
}
