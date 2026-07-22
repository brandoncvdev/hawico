BeforeAll { . "$PSScriptRoot/../Modules/Get-CriticalEvents.ps1";if(-not(Get-Command Get-WinEvent -ErrorAction SilentlyContinue)){function Get-WinEvent { param($FilterHashtable) }} }
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
 It 'queries and groups Windows events' { Mock Get-WinEvent { if($FilterHashtable.ProviderName -eq 'Disk'){@([pscustomobject]@{ProviderName='Disk';Id=7;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='error 1'})}else{@()} };(Get-CriticalEvent -LookbackDays 7)[0].OccurrenceCount|Should -Be 1 }
 It 'returns empty evidence when the provider fails' { Mock Get-WinEvent { throw 'denied' };@(Get-CriticalEvent -LookbackDays 7).Count|Should -Be 0 }
 It 'keeps successful providers when another provider fails' {
  Mock Get-WinEvent {
   if ($FilterHashtable.ProviderName -eq 'Disk') { throw 'provider unavailable' }
   if ($FilterHashtable.ProviderName -eq 'WHEA-Logger') { return @([pscustomobject]@{ProviderName='WHEA-Logger';Id=1;LevelDisplayName='Error';TimeCreated=[datetime]'2026-01-01';Message='hardware 1'}) }
   return @()
  }
  $result = Get-CriticalEventResult -LookbackDays 7
  $result.Status | Should -Be 'Partial'
  $result.Events.Provider | Should -Contain 'WHEA-Logger'
  $result.Errors.Provider | Should -Contain 'Disk'
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
