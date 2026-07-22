BeforeAll { . "$PSScriptRoot/../Modules/Export-HealthCheck.ps1" }
Describe 'New-HealthCheckHtml' {
 It 'writes a privacy-safe summary report' {
  $path=Join-Path $TestDrive 'health.html';$r=[ordered]@{Computer=@{Hostname='<PC&1>'};Collection=@{CollectedAt='2026-01-01'};HealthCheck=@{Status='Completed';Score=@{Value=92;Status='Healthy';ConfidencePercent=100};PrimaryBottleneck='Memory';Findings=@([pscustomobject]@{Id='MEM-002';Severity='High';Category='Memory'});Metrics=@{CPU=@{AverageUsagePercent=20};Memory=@{AverageUsagePercent=85};Storage=@{Volumes=@()};Events=@()};Recommendations=@()}}
  New-HealthCheckHtml -Report $r -Path $path
  $html=Get-Content $path -Raw
  $html|Should -Match 'Health Score';$html|Should -Match 'MEM-002';$html|Should -Match '&lt;PC&amp;1&gt;';$html|Should -Not -Match '<PC&1>'
 }
}
