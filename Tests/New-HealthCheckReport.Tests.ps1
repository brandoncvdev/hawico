BeforeAll { . "$PSScriptRoot/../Modules/New-HealthCheckReport.ps1" }
Describe 'ConvertTo-HealthCheckReport' {
 It 'preserves schema 2.0 and existing inventory shapes' {
  $base=[ordered]@{Computer=@{Hostname='PC1'};OperatingSystem=@{Caption='Windows'};BIOS=@{};Motherboard=@{};Processors=@();Memory=@{};Storage=@{}}
  $r=ConvertTo-HealthCheckReport -BaseInventory $base -HealthCheck ([ordered]@{Status='Completed'}) -CollectedAt ([datetimeoffset]'2026-01-01T00:00:00Z') -DurationMilliseconds 50
  $r.SchemaVersion|Should -Be '2.0'
  $r.Collection.Type|Should -Be 'WindowsHealthCheck'
  $r.Collection.Mode|Should -Be 'Diagnostic'
  $r.HealthCheck.ContractVersion|Should -Be '1.2'
  $r.HealthCheck.ExtendedDiagnostics.ContractVersion|Should -Be '1.0'
  $r.Computer.Hostname|Should -Be 'PC1'
 }
 It 'redacts the script user by default' {
  $r=ConvertTo-HealthCheckReport -BaseInventory @{} -HealthCheck @{} -CollectedAt ([datetimeoffset]::Now) -DurationMilliseconds 1
  $r.Collection.ScriptUser|Should -Be '<REDACTED>'
 }
 It 'returns a real array, not a bare scalar, for Processors when exactly one processor is present' {
  $base=[ordered]@{Computer=@{Hostname='PC1'};OperatingSystem=@{};BIOS=@{};Motherboard=@{};Processors=@([pscustomobject]@{Name='CPU0'});Memory=@{};Storage=@{}}
  $r=ConvertTo-HealthCheckReport -BaseInventory $base -HealthCheck ([ordered]@{Status='Completed'}) -CollectedAt ([datetimeoffset]::Now) -DurationMilliseconds 1
  $r.Processors.GetType().IsArray|Should -BeTrue
  $r.Processors.Count|Should -Be 1
  $r.Processors[0].Name|Should -Be 'CPU0'
 }
 It 'returns a real empty array, not null, for Processors when the base inventory has none' {
  $base=[ordered]@{Computer=@{};OperatingSystem=@{};BIOS=@{};Motherboard=@{};Processors=@();Memory=@{};Storage=@{}}
  $r=ConvertTo-HealthCheckReport -BaseInventory $base -HealthCheck ([ordered]@{Status='Completed'}) -CollectedAt ([datetimeoffset]::Now) -DurationMilliseconds 1
  $r.Processors.GetType().IsArray|Should -BeTrue
  $r.Processors.Count|Should -Be 0
 }
 It 'preserves a nested object field (Computer) as itself, not wrapped in an array, after the comma guard' {
  $base=[ordered]@{Computer=@{Hostname='PC1'};OperatingSystem=@{};BIOS=@{};Motherboard=@{};Processors=@();Memory=@{};Storage=@{}}
  $r=ConvertTo-HealthCheckReport -BaseInventory $base -HealthCheck ([ordered]@{Status='Completed'}) -CollectedAt ([datetimeoffset]::Now) -DurationMilliseconds 1
  $r.Computer.GetType().IsArray|Should -BeFalse
  $r.Computer.Hostname|Should -Be 'PC1'
 }
}
