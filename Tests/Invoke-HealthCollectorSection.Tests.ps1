BeforeAll { . "$PSScriptRoot/../Modules/Invoke-HealthCollectorSection.ps1" }

Describe 'Invoke-HealthCollectorSection' {
 It 'returns measured collected data' {
  $result = Invoke-HealthCollectorSection -Name 'Storage' -Operation { [ordered]@{Status='Collected';Value=42} } -DefaultData @{}
  $result.Data.Value | Should -Be 42
  $result.Section.Status | Should -Be 'Collected'
  $result.Section.StartedAt | Should -Not -BeNullOrEmpty
  $result.Section.DurationMilliseconds | Should -BeGreaterOrEqual 0
  $result.Section.PSObject.Properties.Name | Should -Contain 'SampleCount'
 }
 It 'preserves partial status and sanitized error metadata from a collector' {
  $result = Invoke-HealthCollectorSection -Name 'Events' -Operation { [ordered]@{Status='Partial';ErrorCode='EVENT-QUERY-PARTIAL';ErrorMessage='Some providers unavailable'} } -DefaultData @{}
  $result.Section.Status | Should -Be 'Partial'
  $result.Section.ErrorCode | Should -Be 'EVENT-QUERY-PARTIAL'
 }
 It 'contains exceptions and returns the declared fallback' {
  $fallback = [ordered]@{Status='Failed';Items=@()}
  $result = Invoke-HealthCollectorSection -Name 'Performance' -Operation { throw 'secret detail' } -DefaultData $fallback
  [object]::ReferenceEquals($result.Data, $fallback) | Should -BeTrue
  $result.Section.Status | Should -Be 'Failed'
  $result.Section.ErrorCode | Should -Be 'PERFORMANCE-COLLECTION-FAILED'
  $result.Section.ErrorMessage | Should -Not -Match 'secret detail'
 }
}
