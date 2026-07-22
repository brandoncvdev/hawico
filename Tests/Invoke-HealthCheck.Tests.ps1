BeforeAll { . "$PSScriptRoot/../Modules/Get-HealthFindings.ps1"; . "$PSScriptRoot/../Modules/New-HealthCheckReport.ps1"; . "$PSScriptRoot/../Modules/Invoke-HealthCheck.ps1" }
Describe 'Invoke-HealthCheck' {
 It 'sums empty or incomplete evidence without relying on Measure-Object Sum' {
  (Get-HealthNumericSum -Items @() -PropertyName 'OccurrenceCount')|Should -Be 0
  (Get-HealthNumericSum -Items @([pscustomobject]@{Other=4},[pscustomobject]@{OccurrenceCount=3}) -PropertyName 'OccurrenceCount')|Should -Be 3
 }
 It 'orchestrates metrics findings score and the compatible report' {
  $input=[ordered]@{BaseInventory=[ordered]@{Computer=@{Hostname='PC1'}};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=2;CPU=@{AverageUsagePercent=92;PeakUsagePercent=95;SamplesAtOrAbove90Percent=80};Memory=@{AverageUsagePercent=20;PeakUsagePercent=30;MinimumAvailableMB=2048;SamplesAtOrAbove70Percent=0;SamplesAtOrAbove85Percent=0;SamplesAtOrAbove95Percent=0;SamplesBelow1024MB=0}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@();EventStatus='Collected';Sample=@{RequestedDurationSeconds=60;ActualDurationSeconds=60;IntervalSeconds=1;ValidSampleCount=2}}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]'2026-01-01T00:00:00Z') -DurationMilliseconds 65000
  $r.SchemaVersion|Should -Be '2.0'
  $r.HealthCheck.Findings.Id|Should -Contain 'CPU-001'
  $r.HealthCheck.Status|Should -Be 'Completed'
  $r.HealthCheck.Recommendations.FindingIds|Should -Contain 'CPU-001'
  $r.HealthCheck.Sections.Name|Should -Contain 'Performance'
  $r.HealthCheck.Sample.ValidSampleCount|Should -Be 2
  $r.Collection.DurationMilliseconds|Should -Be 65000
 }
 It 'marks the report partial when a required section failed' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{};Performance=@{Status='Failed';CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@()}
  (Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)).HealthCheck.Status|Should -Be 'Partial'
 }
 It 'derives storage and event rule metrics from collected evidence' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=1;CPU=@{AverageUsagePercent=10;SamplesAtOrAbove90Percent=0};Memory=@{AverageUsagePercent=20;MinimumAvailableMB=4096;SamplesAtOrAbove70Percent=0;SamplesAtOrAbove85Percent=0;SamplesAtOrAbove95Percent=0;SamplesBelow1024MB=0}};Storage=@{Status='Collected';PhysicalDisks=@(@{HealthStatus='Degraded';MediaType='SSD'});Volumes=@(@{Drive='C:';FreePercent=9;IsSystemVolume=$true})};Events=@(@{Provider='Disk';Id=7;Level='Error';OccurrenceCount=3},@{Provider='WHEA-Logger';Id=1;Level='Error';OccurrenceCount=1});EventStatus='Collected'}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)
  $r.HealthCheck.Findings.Id|Should -Contain 'STO-001'
  $r.HealthCheck.Findings.Id|Should -Contain 'STO-002'
  $r.HealthCheck.Findings.Id|Should -Contain 'STO-005'
  $r.HealthCheck.Findings.Id|Should -Contain 'EVT-001'
 }
 It 'scores only documented diagnostic event identifiers' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=1;CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@(@{Provider='Kernel-Power';Id=42;Level='Information';OccurrenceCount=50},@{Provider='Kernel-Power';Id=41;Level='Critical';OccurrenceCount=1},@{Provider='Ntfs';Id=98;Level='Information';OccurrenceCount=3},@{Provider='Ntfs';Id=999;Level='Error';OccurrenceCount=50});EventStatus='Collected'}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)
  $r.HealthCheck.Findings.Id|Should -Contain 'STO-005'
  $r.HealthCheck.Findings.Id|Should -Not -Contain 'EVT-002'
 }
 It 'detects repeated unexpected shutdowns from Kernel-Power event 41' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=1;CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@(@{Provider='Kernel-Power';Id=41;Level='Critical';OccurrenceCount=2});EventStatus='Collected'}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)
  $r.HealthCheck.Findings.Id|Should -Contain 'EVT-002'
 }
 It 'ignores unrelated storage and application event identifiers' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=1;CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@(@{Provider='Disk';Id=999;Level='Error';OccurrenceCount=50},@{Provider='Ntfs';Id=999;Level='Error';OccurrenceCount=50},@{Provider='Application Error';Id=999;Level='Error';OccurrenceCount=50},@{Provider='Application Hang';Id=999;Level='Error';OccurrenceCount=50});EventStatus='Collected'}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)
  $r.HealthCheck.Findings.Id|Should -Not -Contain 'STO-005'
  $r.HealthCheck.Findings.Id|Should -Not -Contain 'EVT-003'
 }
 It 'detects repeated application crashes from Application Error event 1000' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=1;CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@(@{Provider='Application Error';Id=1000;Level='Error';OccurrenceCount=5});EventStatus='Collected'}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)
  $r.HealthCheck.Findings.Id|Should -Contain 'EVT-003'
 }
 It 'reports denied capabilities and failed sections as partial without inventing availability' {
  $input=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$false;Items=@(@{Name='Administrator';Status='Denied'})};Performance=@{Status='Failed';ValidSampleCount=0;CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@();EventStatus='Failed'}
  $r=Invoke-HealthCheck -InputData $input -CollectedAt ([datetimeoffset]::Now)
  $r.HealthCheck.Status|Should -Be 'Partial'
  $r.HealthCheck.IsAdministrator|Should -BeFalse
  ($r.HealthCheck.Sections|Where-Object Name -eq 'Performance').Status|Should -Be 'Failed'
  $r.HealthCheck.Errors.Code|Should -Contain 'CAP-ADMIN-DENIED'
  $r.HealthCheck.Score.ConfidencePercent|Should -Be 35
  $r.HealthCheck.Score.Value|Should -BeNullOrEmpty
 }
 It 'preserves partial section detail and provider errors in the report' {
  $inputData=[ordered]@{BaseInventory=@{};Capabilities=@{IsAdministrator=$true;Items=@()};Performance=@{Status='Collected';ValidSampleCount=1;CPU=@{};Memory=@{}};Storage=@{Status='Collected';PhysicalDisks=@();Volumes=@()};Events=@();EventStatus='Partial';Sections=@([pscustomobject]@{Name='Events';Status='Partial';StartedAt='2026-01-01T00:00:00Z';DurationMilliseconds=12;ErrorCode='EVENT-QUERY-PARTIAL';ErrorMessage='Unavailable providers: WHEA-Logger.'});EventErrors=@([pscustomobject]@{Provider='WHEA-Logger';Code='EVENT-PROVIDER-FAILED';Message='Provider unavailable.'})}
  $r=Invoke-HealthCheck -InputData $inputData -CollectedAt ([datetimeoffset]::Now)
  $section=$r.HealthCheck.Sections|Where-Object Name -eq 'Events'
  $section.ErrorMessage|Should -Match 'WHEA-Logger'
  $section.DurationMilliseconds|Should -Be 12
  ($r.HealthCheck.Errors|Where-Object Provider -eq 'WHEA-Logger').Code|Should -Be 'EVENT-PROVIDER-FAILED'
 }
}
