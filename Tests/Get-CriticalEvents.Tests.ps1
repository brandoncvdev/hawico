BeforeAll { . "$PSScriptRoot/../Modules/Get-CriticalEvents.ps1" }
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
 It 'returns an empty collection for no evidence' { @(Group-CriticalEvent -Events @()).Count|Should -Be 0 }
}
