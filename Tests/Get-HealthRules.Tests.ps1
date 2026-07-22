BeforeAll { . "$PSScriptRoot/../Modules/Get-HealthFindings.ps1" }
Describe 'Get-HealthFinding' {
 It 'honors every sustained memory utilization boundary' {
  $cases = @(
   @{ Value = 69.99; Expected = $null },
   @{ Value = 70; Expected = 'MEM-003' },
   @{ Value = 84.99; Expected = 'MEM-003' },
   @{ Value = 85; Expected = 'MEM-002' },
   @{ Value = 94.99; Expected = 'MEM-002' },
   @{ Value = 95; Expected = 'MEM-001' }
  )
  foreach ($case in $cases) {
   $ids = @((Get-HealthFinding -Metrics ([pscustomobject]@{Memory=[pscustomobject]@{UsagePercent=$case.Value;MatchingSamplePercent=80}})).Id)
   if ($null -eq $case.Expected) { $ids | Should -BeNullOrEmpty }
   else { $ids | Should -Contain $case.Expected; @($ids | Where-Object { $_ -like 'MEM-00[123]' }).Count | Should -Be 1 }
  }
 }
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
 It 'honors every system volume free-space boundary' {
  $cases = @(
   @{ Value = 9.99; Expected = 'STO-002' },
   @{ Value = 10; Expected = 'STO-003' },
   @{ Value = 19.99; Expected = 'STO-003' },
   @{ Value = 20; Expected = $null }
  )
  foreach ($case in $cases) {
   $ids = @((Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{SystemFreePercent=$case.Value}})).Id)
   if ($null -eq $case.Expected) { $ids | Should -BeNullOrEmpty }
   else { $ids | Should -Contain $case.Expected; @($ids | Where-Object { $_ -in @('STO-002','STO-003') }).Count | Should -Be 1 }
  }
 }
 It 'detects sustained CPU saturation' {
  (Get-HealthFinding -Metrics ([pscustomobject]@{CPU=[pscustomobject]@{AverageUsagePercent=92;SamplesAtOrAbove90Percent=80}})).Id|Should -Contain 'CPU-001'
 }
 It 'evaluates non-storage event rules without double-penalizing disk events' {
  $events = [pscustomobject]@{ WHEACount=1; KernelPowerCount=2; ApplicationFailureCount=5 }
  $ids = @((Get-HealthFinding -Metrics ([pscustomobject]@{Events=$events;Storage=[pscustomobject]@{DiskEventCount=3}})).Id)
  $ids | Should -Contain 'EVT-001'
  $ids | Should -Contain 'EVT-002'
  $ids | Should -Contain 'EVT-003'
  @($ids | Where-Object { $_ -eq 'STO-005' }).Count | Should -Be 1
 }
 It 'returns explainable findings and recommendations linked by id' {
  $finding = Get-HealthFinding -Metrics ([pscustomobject]@{CPU=[pscustomobject]@{AverageUsagePercent=92;SamplesAtOrAbove90Percent=80}}) | Select-Object -First 1
  $finding.Title | Should -Not -BeNullOrEmpty
  $finding.Description | Should -Not -BeNullOrEmpty
  $finding.Evidence.AverageUsagePercent | Should -Be 92
  $finding.RecommendationId | Should -Be 'REC-CPU-001'
  $recommendations = @(Get-HealthRecommendation -Findings @($finding))
  $recommendations.Count | Should -Be 1
  $recommendations[0].FindingIds | Should -Contain 'CPU-001'
 }
}
