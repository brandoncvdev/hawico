BeforeAll { . "$PSScriptRoot/../Modules/Get-CriticalEvents.ps1";if(-not(Get-Command Get-WinEvent -ErrorAction SilentlyContinue)){function Get-WinEvent { param($FilterHashtable,$ListProvider) }} }
Describe 'Group-CriticalEvent' {
 It 'groups repeated provider and id events' {
  $events=@([pscustomobject]@{ProviderName='Disk';Id=7;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='bad sector 123'},[pscustomobject]@{ProviderName='Disk';Id=7;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-02';Message='bad sector 456'})
  $r=Group-CriticalEvent -Events $events
  $r.Count|Should -Be 1
  $r[0].OccurrenceCount|Should -Be 2
  $r[0].FirstSeen|Should -Be ([datetime]'2026-01-01')
 }
 It 'redacts user paths and normalizes variable numbers' {
  $events=@([pscustomobject]@{ProviderName='Application Error';Id=1000;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='C:\Users\alice\app.exe failed code 12345'})
  $r=Group-CriticalEvent -Events $events
  $r[0].Message|Should -Not -Match 'alice'
  $r[0].Message|Should -Match '<USER>'
  $r[0].Message|Should -Match '<N>'
 }
 It 'redacts common identifiers and bounds message length' {
  $message = 'Contact alice@example.com from 192.168.10.5 correlation 550e8400-e29b-41d4-a716-446655440000 ' + ('x' * 400)
  $r=Group-CriticalEvent -Events @([pscustomobject]@{ProviderName='Application Error';Id=1000;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message=$message})
  $r[0].Message|Should -Not -Match 'alice@example.com|192\.168\.10\.5|550e8400'
  $r[0].Message.Length|Should -BeLessOrEqual 240
 }
 It 'returns an empty collection for no evidence' { @(Group-CriticalEvent -Events @()).Count|Should -Be 0 }
}
Describe 'Get-CriticalEvent' {
 It 'recognizes the Windows no matching events condition' {
  $errorRecord=[System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No events were found'), 'NoMatchingEventsFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
  Test-HealthNoMatchingEventError -ErrorRecord $errorRecord|Should -BeTrue
 }
 It 'treats a provider with no matching events as successfully queried' {
  Mock Get-WinEvent {
   if($ListProvider){return [pscustomobject]@{Name=$ListProvider}}
   $errorRecord=[System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No events were found'), 'NoMatchingEventsFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
   throw $errorRecord
  }
  $result=Get-CriticalEventResult -LookbackDays 7
  $result.Status|Should -Be 'Collected'
  $result.Events|Should -BeNullOrEmpty
  $result.Errors|Should -BeNullOrEmpty
 }
 It 'does not hide a missing provider behind a no matching events error' {
  Mock Get-WinEvent {
   if($ListProvider){throw 'provider unavailable'}
   $errorRecord=[System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No events were found'), 'NoMatchingEventsFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
   throw $errorRecord
  }
  $result=Get-CriticalEventResult -LookbackDays 7
  $result.Status|Should -Be 'Failed'
  $result.Errors.Count|Should -BeGreaterThan 0
 }
 It 'queries and groups Windows events' { Mock Get-WinEvent { if($FilterHashtable.ProviderName -eq 'Disk'){@([pscustomobject]@{ProviderName='Disk';Id=7;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='error 1'})}else{@()} };(Get-CriticalEvent -LookbackDays 7)[0].OccurrenceCount|Should -Be 1 }
 It 'returns empty evidence when the provider fails' { Mock Get-WinEvent { throw 'denied' };@(Get-CriticalEvent -LookbackDays 7).Count|Should -Be 0 }
 It 'keeps successful providers when another provider fails' {
  Mock Get-WinEvent {
   if ($FilterHashtable.ProviderName -in @('Disk','Microsoft-Windows-Disk')) { throw 'provider unavailable' }
   if ($FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger') { return @([pscustomobject]@{ProviderName='Microsoft-Windows-WHEA-Logger';Id=1;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='hardware 1'}) }
   return @()
  }
  $result = Get-CriticalEventResult -LookbackDays 7
  $result.Status | Should -Be 'Partial'
  $result.Events.Provider | Should -Contain 'WHEA-Logger'
  $result.Errors.Provider | Should -Contain 'Disk'
  $result.ErrorMessage | Should -Match 'Disk'
 }
 It 'falls back to modern Windows provider aliases and emits canonical names' {
  Mock Get-WinEvent {
   if($FilterHashtable.ProviderName -eq 'Ntfs'){throw 'legacy provider absent'}
   if($FilterHashtable.ProviderName -eq 'Microsoft-Windows-Ntfs'){return @([pscustomobject]@{ProviderName='Microsoft-Windows-Ntfs';Id=55;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='ntfs 1'})}
   return @()
  }
  $result=Get-CriticalEventResult -LookbackDays 7
  $result.Events.Provider|Should -Contain 'Ntfs'
  Should -Invoke -CommandName Get-WinEvent -ParameterFilter {$FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger'}
  Should -Invoke -CommandName Get-WinEvent -ParameterFilter {$FilterHashtable.ProviderName -eq 'Microsoft-Windows-Kernel-Power'}
 }
 It 'reports failed rather than an empty healthy result when every provider fails' {
  Mock Get-WinEvent { throw 'denied' }
  $result = Get-CriticalEventResult -LookbackDays 7
  $result.Status | Should -Be 'Failed'
  $result.Events | Should -BeNullOrEmpty
  $result.ErrorCode | Should -Be 'EVENT-QUERY-FAILED'
 }
 It 'queries providers only in their applicable Windows log' {
  Mock Get-WinEvent { return @() }
  Get-CriticalEventResult -LookbackDays 7 | Out-Null
  Should -Invoke -CommandName Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Disk' -and $FilterHashtable.LogName -eq 'System' }
  Should -Invoke -CommandName Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Application Error' -and $FilterHashtable.LogName -eq 'Application' }
 }
}
