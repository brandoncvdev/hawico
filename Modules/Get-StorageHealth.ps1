function Get-StorageProperty {
    param([AllowNull()][object]$Object, [string]$Name, [AllowNull()][object]$DefaultValue = $null)
    if ($null -eq $Object) { return $DefaultValue }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $DefaultValue
}

function ConvertTo-HealthMediaType {
    param([AllowNull()][object]$MediaType, [AllowNull()][object]$BusType)
    if ([string]$BusType -match '(?i)^NVMe$') { return 'NVMe' }
    if ([string]$MediaType -match '(?i)^SSD$|solid state') { return 'SSD' }
    if ([string]$MediaType -match '(?i)^HDD$|rotational') { return 'HDD' }
    return 'Unknown'
}

function Get-StorageHealth {
    param([Parameter(Mandatory)][object]$StorageInventory, [Parameter(Mandatory)][string]$SystemDrive)

    $physicalInventory = @(Get-StorageProperty -Object $StorageInventory -Name 'Physical' -DefaultValue @())
    $detailedInventory = @(Get-StorageProperty -Object $StorageInventory -Name 'Detailed' -DefaultValue @())
    $logicalInventory = @(Get-StorageProperty -Object $StorageInventory -Name 'Logical' -DefaultValue @())
    $disks = @()
    foreach ($detail in $detailedInventory) {
        $serialNumber = [string](Get-StorageProperty -Object $detail -Name 'SerialNumber')
        $baseDisk = @($physicalInventory | Where-Object { [string]$_.SerialNumber -eq $serialNumber } | Select-Object -First 1)
        $base = if ($baseDisk.Count -gt 0) { $baseDisk[0] } else { $null }
        $busType = Get-StorageProperty -Object $detail -Name 'BusType'
        $mediaType = ConvertTo-HealthMediaType -MediaType (Get-StorageProperty -Object $detail -Name 'MediaType') -BusType $busType
        $healthStatus = [string](Get-StorageProperty -Object $detail -Name 'HealthStatus')
        if ([string]::IsNullOrWhiteSpace($healthStatus)) { $healthStatus = 'Unknown' }
        $friendlyName = Get-StorageProperty -Object $detail -Name 'FriendlyName'
        $model = Get-StorageProperty -Object $base -Name 'Model' -DefaultValue $friendlyName
        $disks += [pscustomobject][ordered]@{
            Name = $friendlyName
            Manufacturer = Get-StorageProperty -Object $base -Name 'Manufacturer'
            Model = $model
            SerialNumber = if ([string]::IsNullOrWhiteSpace($serialNumber)) { $null } else { $serialNumber }
            MediaType = $mediaType
            BusType = if ([string]::IsNullOrWhiteSpace([string]$busType)) { 'Unknown' } else { [string]$busType }
            CapacityGB = Get-StorageProperty -Object $detail -Name 'SizeGB' -DefaultValue (Get-StorageProperty -Object $base -Name 'SizeGB')
            OperationalStatus = @(Get-StorageProperty -Object $detail -Name 'OperationalStatus' -DefaultValue @())
            HealthStatus = $healthStatus
            HealthSource = 'Get-PhysicalDisk'
            IsSystemDisk = $null
        }
    }
    if ($disks.Count -eq 0) {
        foreach ($base in $physicalInventory) {
            $busType = Get-StorageProperty -Object $base -Name 'InterfaceType'
            $disks += [pscustomobject][ordered]@{
                Name = Get-StorageProperty -Object $base -Name 'Model'
                Manufacturer = Get-StorageProperty -Object $base -Name 'Manufacturer'
                Model = Get-StorageProperty -Object $base -Name 'Model'
                SerialNumber = Get-StorageProperty -Object $base -Name 'SerialNumber'
                MediaType = ConvertTo-HealthMediaType -MediaType (Get-StorageProperty -Object $base -Name 'MediaType') -BusType $busType
                BusType = if ([string]::IsNullOrWhiteSpace([string]$busType)) { 'Unknown' } else { [string]$busType }
                CapacityGB = Get-StorageProperty -Object $base -Name 'SizeGB'
                OperationalStatus = @((Get-StorageProperty -Object $base -Name 'Status'))
                HealthStatus = 'Unknown'
                HealthSource = 'Unavailable'
                IsSystemDisk = $null
            }
        }
    }
    if ($disks.Count -eq 1) { $disks[0].IsSystemDisk = $true }

    $volumes = @($logicalInventory | ForEach-Object {
        [pscustomobject][ordered]@{
            Drive = Get-StorageProperty -Object $_ -Name 'Drive'
            VolumeName = Get-StorageProperty -Object $_ -Name 'VolumeName'
            FileSystem = Get-StorageProperty -Object $_ -Name 'FileSystem'
            CapacityGB = Get-StorageProperty -Object $_ -Name 'SizeGB'
            FreeSpaceGB = Get-StorageProperty -Object $_ -Name 'FreeSpaceGB'
            FreePercent = Get-StorageProperty -Object $_ -Name 'FreePercent'
            IsSystemVolume = ([string](Get-StorageProperty -Object $_ -Name 'Drive') -eq $SystemDrive)
        }
    })

    $status = if ($disks.Count -eq 0 -and $volumes.Count -eq 0) { 'Failed' }
        elseif ($disks.Count -eq 0 -or $volumes.Count -eq 0 -or @($disks | Where-Object HealthStatus -ne 'Unknown').Count -eq 0) { 'Partial' }
        else { 'Collected' }
    return [ordered]@{
        Status = $status
        PhysicalDisks = $disks
        Volumes = $volumes
    }
}
