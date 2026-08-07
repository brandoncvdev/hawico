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
 It 'carries Smart from the base physical record onto the disk via the existing SerialNumber join' {
  $smart=[ordered]@{Supported=$true;Source='ATA';OverallHealth='PASSED';TemperatureCelsius=35;PendingSectorCount=0}
  $s=[pscustomobject]@{
   Physical=@([pscustomobject]@{Model='Model X';Manufacturer='Vendor';SerialNumber='SERIAL';SizeGB=512;Smart=$smart})
   Detailed=@([pscustomobject]@{FriendlyName='Friendly';SerialNumber='SERIAL';HealthStatus='Healthy';MediaType='SSD';BusType='NVMe';SizeGB=512;OperationalStatus=@('OK')})
   Logical=@()
  }
  $r=Get-StorageHealth -StorageInventory $s -SystemDrive 'C:'
  $r.PhysicalDisks[0].Smart.Supported|Should -BeTrue
  $r.PhysicalDisks[0].Smart.Source|Should -Be 'ATA'
  $r.PhysicalDisks[0].Smart.TemperatureCelsius|Should -Be 35
 }
 It 'leaves Smart null when the base physical record has no matching SerialNumber' {
  $s=[pscustomobject]@{
   Physical=@([pscustomobject]@{Model='Other';Manufacturer='Vendor';SerialNumber='DIFFERENT';SizeGB=512;Smart=[ordered]@{Supported=$true;Source='ATA'}})
   Detailed=@([pscustomobject]@{FriendlyName='Friendly';SerialNumber='SERIAL';HealthStatus='Healthy';MediaType='SSD';BusType='NVMe';SizeGB=512;OperationalStatus=@('OK')})
   Logical=@()
  }
  $r=Get-StorageHealth -StorageInventory $s -SystemDrive 'C:'
  $r.PhysicalDisks[0].Smart|Should -BeNullOrEmpty
 }
}

Describe 'Get-StorageSmartSummary' {
 It 'reflects the worst overall health across disks (one FAILED beats one PASSED)' {
  $disks=@(
   [pscustomobject]@{Smart=[pscustomobject]@{Supported=$true;OverallHealth='PASSED';TemperatureCelsius=30;PendingSectorCount=0;ReallocatedSectorCount=0;AvailableSparePercent=90;PercentageUsed=10;PowerOnHours=100;UncorrectableSectorCount=0;MediaErrorCount=0;CriticalWarningFlags=0}}
   [pscustomobject]@{Smart=[pscustomobject]@{Supported=$true;OverallHealth='FAILED';TemperatureCelsius=45;PendingSectorCount=2;ReallocatedSectorCount=5;AvailableSparePercent=40;PercentageUsed=85;PowerOnHours=30000;UncorrectableSectorCount=1;MediaErrorCount=3;CriticalWarningFlags=1}}
  )
  $summary=Get-StorageSmartSummary -PhysicalDisks $disks
  $summary.Supported|Should -BeTrue
  $summary.OverallHealth|Should -Be 'FAILED'
 }
 It 'reflects the worst wear, temperature, sector and spare metrics across mixed disks' {
  $disks=@(
   [pscustomobject]@{Smart=[pscustomobject]@{Supported=$true;OverallHealth='PASSED';TemperatureCelsius=30;PendingSectorCount=0;ReallocatedSectorCount=0;AvailableSparePercent=90;PercentageUsed=10;PowerOnHours=100;UncorrectableSectorCount=0;MediaErrorCount=0;CriticalWarningFlags=0}}
   [pscustomobject]@{Smart=[pscustomobject]@{Supported=$true;OverallHealth='PASSED';TemperatureCelsius=61;PendingSectorCount=3;ReallocatedSectorCount=7;AvailableSparePercent=8;PercentageUsed=93;PowerOnHours=40000;UncorrectableSectorCount=2;MediaErrorCount=4;CriticalWarningFlags=2}}
  )
  $summary=Get-StorageSmartSummary -PhysicalDisks $disks
  $summary.TemperatureCelsius|Should -Be 61
  $summary.PendingSectorCount|Should -Be 3
  $summary.ReallocatedSectorCount|Should -Be 7
  $summary.AvailableSparePercent|Should -Be 8
  $summary.PercentageUsed|Should -Be 93
  $summary.PowerOnHours|Should -Be 40000
  $summary.UncorrectableSectorCount|Should -Be 2
  $summary.MediaErrorCount|Should -Be 4
  $summary.CriticalWarningFlags|Should -Be 2
 }
 It 'reports Supported=$false and null fields when no disk has SMART data' {
  $disks=@(
   [pscustomobject]@{Smart=$null}
   [pscustomobject]@{Smart=[pscustomobject]@{Supported=$false;OverallHealth=$null;TemperatureCelsius=$null;PendingSectorCount=$null;ReallocatedSectorCount=$null;AvailableSparePercent=$null;PercentageUsed=$null;PowerOnHours=$null;UncorrectableSectorCount=$null;MediaErrorCount=$null;CriticalWarningFlags=$null}}
  )
  $summary=Get-StorageSmartSummary -PhysicalDisks $disks
  $summary.Supported|Should -BeFalse
  $summary.OverallHealth|Should -BeNullOrEmpty
  $summary.TemperatureCelsius|Should -BeNullOrEmpty
 }
}
