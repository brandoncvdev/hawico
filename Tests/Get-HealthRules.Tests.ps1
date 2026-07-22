BeforeAll { . "$PSScriptRoot/../Modules/Get-HealthFindings.ps1" }
Describe 'Get-HealthFinding' {
 It 'selects exactly one sustained memory utilization rule at boundaries' {
  (Get-HealthFinding -Metrics ([pscustomobject]@{Memory=[pscustomobject]@{UsagePercent=85;MatchingSamplePercent=80}})).Id|Should -Contain 'MEM-002'
  (Get-HealthFinding -Metrics ([pscustomobject]@{Memory=[pscustomobject]@{UsagePercent=85;MatchingSamplePercent=80}})).Id|Should -Not -Contain 'MEM-003'
 }
 It 'does not penalize unknown disk health' {
  @(Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{HealthStatus='Unknown'}})).Id|Should -Not -Contain 'STO-001'
 }
 It 'detects critical system volume space' {
  (Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{SystemFreePercent=9.99}})).Id|Should -Contain 'STO-002'
 }
 It 'detects sustained CPU saturation' {
  (Get-HealthFinding -Metrics ([pscustomobject]@{CPU=[pscustomobject]@{AverageUsagePercent=92;SamplesAtOrAbove90Percent=80}})).Id|Should -Contain 'CPU-001'
 }
}
