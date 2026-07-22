BeforeAll { . "$PSScriptRoot/../Modules/Get-StorageHealth.ps1" }
Describe 'Get-StorageHealth' {
 It 'identifies the system volume and preserves explicit health' {
  $s=[pscustomobject]@{Detailed=@([pscustomobject]@{FriendlyName='Disk';HealthStatus='Healthy';MediaType='SSD';BusType='NVMe'});Logical=@([pscustomobject]@{Drive='C:';FreePercent=15})}
  $r=Get-StorageHealth -StorageInventory $s -SystemDrive 'C:'
  $r.Volumes[0].IsSystemVolume|Should -BeTrue
  $r.PhysicalDisks[0].HealthStatus|Should -Be 'Healthy'
 }
 It 'uses Unknown instead of inventing health' {
  $s=[pscustomobject]@{Detailed=@([pscustomobject]@{FriendlyName='Disk';HealthStatus=$null;MediaType=$null;BusType=$null});Logical=@()}
  $r=Get-StorageHealth -StorageInventory $s -SystemDrive 'C:'
  $r.PhysicalDisks[0].HealthStatus|Should -Be 'Unknown'
  $r.PhysicalDisks[0].MediaType|Should -Be 'Unknown'
 }
 It 'fails explicitly when no storage evidence exists' {
  $r=Get-StorageHealth -StorageInventory ([pscustomobject]@{Detailed=@();Logical=@()}) -SystemDrive 'C:'
  $r.Status|Should -Be 'Failed'
 }
}
