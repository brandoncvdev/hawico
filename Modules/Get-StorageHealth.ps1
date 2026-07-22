function Get-StorageHealth {
 param([Parameter(Mandatory)][object]$StorageInventory,[Parameter(Mandatory)][string]$SystemDrive)
 $disks=@($StorageInventory.Detailed|ForEach-Object{
  [pscustomobject][ordered]@{
   Name=$_.FriendlyName
   HealthStatus=if([string]::IsNullOrWhiteSpace([string]$_.HealthStatus)){"Unknown"}else{[string]$_.HealthStatus}
   MediaType=if([string]::IsNullOrWhiteSpace([string]$_.MediaType)){"Unknown"}else{[string]$_.MediaType}
   BusType=if([string]::IsNullOrWhiteSpace([string]$_.BusType)){"Unknown"}else{[string]$_.BusType}
   Source="Get-PhysicalDisk"
  }
 })
 $volumes=@($StorageInventory.Logical|ForEach-Object{
  [pscustomobject][ordered]@{Drive=$_.Drive;FreePercent=$_.FreePercent;IsSystemVolume=([string]$_.Drive -eq $SystemDrive)}
 })
 return [ordered]@{
  Status=if($disks.Count -eq 0 -and $volumes.Count -eq 0){"Failed"}else{"Collected"}
  PhysicalDisks=$disks
  Volumes=$volumes
 }
}
