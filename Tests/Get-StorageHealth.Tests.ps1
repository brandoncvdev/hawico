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
 It 'preserves required physical and volume evidence and normalizes NVMe media' {
  $s=[pscustomobject]@{
   Physical=@([pscustomobject]@{Model='Model X';Manufacturer='Vendor';SerialNumber='SERIAL';SizeGB=512})
   Detailed=@([pscustomobject]@{FriendlyName='Friendly';SerialNumber='SERIAL';HealthStatus='Healthy';MediaType='SSD';BusType='NVMe';SizeGB=512;OperationalStatus=@('OK')})
   Logical=@([pscustomobject]@{Drive='C:';VolumeName='OS';FileSystem='NTFS';SizeGB=500;FreeSpaceGB=100;FreePercent=20})
  }
  $r=Get-StorageHealth -StorageInventory $s -SystemDrive 'C:'
  $r.PhysicalDisks[0].Manufacturer|Should -Be 'Vendor'
  $r.PhysicalDisks[0].Model|Should -Be 'Model X'
  $r.PhysicalDisks[0].SerialNumber|Should -Be 'SERIAL'
  $r.PhysicalDisks[0].MediaType|Should -Be 'NVMe'
  $r.PhysicalDisks[0].IsSystemDisk|Should -BeTrue
  $r.Volumes[0].FileSystem|Should -Be 'NTFS'
  $r.Volumes[0].FreeSpaceGB|Should -Be 100
 }
 It 'uses physical inventory as partial evidence without inventing health' {
  $s=[pscustomobject]@{Physical=@([pscustomobject]@{Model='Legacy';Manufacturer='Vendor';SerialNumber='S';InterfaceType='SATA';MediaType='Fixed hard disk media';SizeGB=100;Status='OK'});Detailed=@();Logical=@([pscustomobject]@{Drive='C:';FreePercent=50})}
  $r=Get-StorageHealth -StorageInventory $s -SystemDrive 'C:'
  $r.Status|Should -Be 'Partial'
  $r.PhysicalDisks[0].HealthStatus|Should -Be 'Unknown'
  $r.PhysicalDisks[0].OperationalStatus|Should -Contain 'OK'
 }
}
