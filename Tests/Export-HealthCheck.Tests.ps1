BeforeAll { . "$PSScriptRoot/../Modules/Export-HealthCheck.ps1" }
Describe 'New-HealthCheckHtml' {
 It 'writes a privacy-safe summary report' {
  $path=Join-Path $TestDrive 'health.html';$r=[ordered]@{Computer=@{Hostname='<PC&1>'};Collection=@{CollectedAt='2026-01-01'};HealthCheck=@{Status='Partial';Score=@{Value=92;Status='Healthy';ConfidencePercent=80};PrimaryBottleneck='Memory';Findings=@([pscustomobject]@{Id='MEM-002';Title='High memory';Description='Sustained pressure';Severity='High';Category='Memory'});Metrics=@{CPU=@{AverageUsagePercent=20;PeakUsagePercent=30};Memory=@{AverageUsagePercent=85;MinimumAvailableMB=900};Storage=@{PhysicalDisks=@(@{Name='Disk';HealthStatus='Healthy';MediaType='SSD'});Volumes=@(@{Drive='C:';FreePercent=15;IsSystemVolume=$true})};Events=@(@{Provider='Application Error';Id=1000;OccurrenceCount=5})};Recommendations=@(@{Id='REC-MEM-001';Title='Review memory';Description='Inspect workload';FindingIds=@('MEM-002')});Sections=@(@{Name='Events';Status='Partial';ErrorMessage='Some providers unavailable'})}}
  New-HealthCheckHtml -Report $r -Path $path
  $html=Get-Content $path -Raw
  $html|Should -Match 'Health Score';$html|Should -Match 'MEM-002';$html|Should -Match '&lt;PC&amp;1&gt;';$html|Should -Not -Match '<PC&1>'
  $html|Should -Match 'REC-MEM-001';$html|Should -Match 'MEM-002'
  $html|Should -Match 'C:';$html|Should -Match 'Application Error'
  $html|Should -Match 'Some providers unavailable';$html|Should -Match '2026-01-01'
 }
 It 'renders unavailable performance metrics without throwing under StrictMode' {
  $path=Join-Path $TestDrive 'partial.html';$r=[ordered]@{Computer=@{};Collection=@{CollectedAt='2026-01-01'};HealthCheck=@{Status='Partial';Score=@{Value=$null;Status='InsufficientData';ConfidencePercent=35};PrimaryBottleneck='None';Findings=@();Metrics=@{CPU=@{};Memory=@{};Storage=@{PhysicalDisks=@();Volumes=@()};Events=@()};Recommendations=@();Sections=@(@{Name='Performance';Status='Failed';ErrorMessage='No valid samples'})}}
  { & { Set-StrictMode -Version Latest;New-HealthCheckHtml -Report $r -Path $path } }|Should -Not -Throw
  (Get-Content $path -Raw)|Should -Match 'No disponible'
 }
}
