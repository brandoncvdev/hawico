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
 It 'returns a real array, not a bare object, when exactly one finding is produced' {
  $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{SystemFreePercent=9.99}})
  $result.GetType().IsArray | Should -BeTrue
  $result.Count | Should -Be 1
 }
 It 'applies validated configurable memory and disk thresholds' {
  $thresholds = [pscustomobject]@{MemoryWarningPercent=60;MemoryHighPercent=75;MemoryCriticalPercent=90;MinimumAvailableMemoryMB=1500;CriticalFreeDiskPercent=5;MinimumFreeDiskPercent=15}
  $metrics = [pscustomobject]@{Memory=[pscustomobject]@{UsagePercent=76;WarningMatchingSamplePercent=100;HighMatchingSamplePercent=80;CriticalMatchingSamplePercent=0;AvailableMemoryMB=1400;LowAvailableMatchingSamplePercent=80};Storage=[pscustomobject]@{SystemFreePercent=7}}
  $ids = @((Get-HealthFinding -Metrics $metrics -Thresholds $thresholds).Id)
  $ids | Should -Contain 'MEM-002'
  $ids | Should -Contain 'MEM-004'
  $ids | Should -Contain 'STO-003'
  $ids | Should -Not -Contain 'STO-002'
 }
 It 'detects a SMART overall-health self-assessment failure as Critical' {
  $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{OverallHealth='FAILED'}}})
  $finding = @($result | Where-Object { $_.Id -eq 'STO-006' })
  $finding.Count | Should -Be 1
  $finding[0].Severity | Should -Be 'Critical'
  $finding[0].RecommendationId | Should -Be 'REC-STO-001'
 }
 It 'detects pending sectors at or above the critical threshold as Critical' {
  $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{PendingSectorCount=1}}})
  $finding = @($result | Where-Object { $_.Id -eq 'STO-007' })
  $finding.Count | Should -Be 1
  $finding[0].Severity | Should -Be 'Critical'
  $finding[0].RecommendationId | Should -Be 'REC-STO-001'
 }
 It 'does not raise STO-007 below the configured critical pending-sector threshold' {
  @((Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{PendingSectorCount=0}}})).Id) | Should -Not -Contain 'STO-007'
 }
 It 'detects NVMe available spare below the default critical threshold as Critical' {
  $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{AvailableSparePercent=9.99}}})
  $finding = @($result | Where-Object { $_.Id -eq 'STO-008' })
  $finding.Count | Should -Be 1
  $finding[0].Severity | Should -Be 'Critical'
  $finding[0].RecommendationId | Should -Be 'REC-STO-001'
 }
 It 'honors a configured NVMe available spare critical threshold' {
  $thresholds = [pscustomobject]@{StorageAvailableSpareCriticalPercent=20}
  @((Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{AvailableSparePercent=15}}}) -Thresholds $thresholds).Id) | Should -Contain 'STO-008'
  @((Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{AvailableSparePercent=25}}}) -Thresholds $thresholds).Id) | Should -Not -Contain 'STO-008'
 }
 It 'raises only a Medium STO-009 for reallocated sectors when there are no pending sectors' {
  $findings = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{ReallocatedSectorCount=3;PendingSectorCount=0}}})
  $sto009 = @($findings | Where-Object { $_.Id -eq 'STO-009' })
  $sto009.Count | Should -Be 1
  $sto009[0].Severity | Should -Be 'Medium'
  $sto009[0].RecommendationId | Should -Be 'REC-STO-005'
  @($findings.Id) | Should -Not -Contain 'STO-007'
  @($findings | Where-Object { $_.Severity -eq 'Critical' }).Count | Should -Be 0
 }
 It 'honors every storage wear boundary' {
  $cases = @(
   @{ Value = 69.99; Expected = $null },
   @{ Value = 70; Expected = 'Medium' },
   @{ Value = 89.99; Expected = 'Medium' },
   @{ Value = 90; Expected = 'High' }
  )
  foreach ($case in $cases) {
   $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{PercentageUsed=$case.Value}}})
   $findings = @($result | Where-Object { $_.Id -eq 'STO-010' })
   if ($null -eq $case.Expected) { $findings.Count | Should -Be 0 }
   else {
    $findings.Count | Should -Be 1
    $findings[0].Severity | Should -Be $case.Expected
    $findings[0].RecommendationId | Should -Be 'REC-STO-006'
   }
  }
 }
 It 'honors every storage temperature boundary' {
  $cases = @(
   @{ Value = 54.99; Expected = $null },
   @{ Value = 55; Expected = 'Medium' },
   @{ Value = 64.99; Expected = 'Medium' },
   @{ Value = 65; Expected = 'High' }
  )
  foreach ($case in $cases) {
   $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{Smart=[pscustomobject]@{TemperatureCelsius=$case.Value}}})
   $findings = @($result | Where-Object { $_.Id -eq 'STO-011' })
   if ($null -eq $case.Expected) { $findings.Count | Should -Be 0 }
   else {
    $findings.Count | Should -Be 1
    $findings[0].Severity | Should -Be $case.Expected
    $findings[0].RecommendationId | Should -Be 'REC-STO-007'
   }
  }
 }
 It 'detects an HDD approaching its configured service-life hours as Medium, never Critical or High' {
  $result = Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{SystemMediaType='HDD';Smart=[pscustomobject]@{PowerOnHours=26280}}})
  $finding = @($result | Where-Object { $_.Id -eq 'STO-012' })
  $finding.Count | Should -Be 1
  $finding[0].Severity | Should -Be 'Medium'
 }
 It 'does not raise STO-012 for non-HDD media even at high power-on hours' {
  @((Get-HealthFinding -Metrics ([pscustomobject]@{Storage=[pscustomobject]@{SystemMediaType='SSD';Smart=[pscustomobject]@{PowerOnHours=26280}}})).Id) | Should -Not -Contain 'STO-012'
 }
 It 'extends the recommendation catalog with REC-STO-005/006/007 grouped by finding id' {
  $findings = @(
   [pscustomobject]@{ Id='STO-009'; RecommendationId='REC-STO-005' },
   [pscustomobject]@{ Id='STO-010'; RecommendationId='REC-STO-006' },
   [pscustomobject]@{ Id='STO-012'; RecommendationId='REC-STO-006' },
   [pscustomobject]@{ Id='STO-011'; RecommendationId='REC-STO-007' }
  )
  $recommendations = @(Get-HealthRecommendation -Findings $findings)
  $recommendations.Count | Should -Be 3
  ($recommendations | Where-Object Id -eq 'REC-STO-005').FindingIds | Should -Contain 'STO-009'
  ($recommendations | Where-Object Id -eq 'REC-STO-006').FindingIds | Should -Contain 'STO-010'
  ($recommendations | Where-Object Id -eq 'REC-STO-006').FindingIds | Should -Contain 'STO-012'
  ($recommendations | Where-Object Id -eq 'REC-STO-007').FindingIds | Should -Contain 'STO-011'
 }
}
