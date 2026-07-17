function Get-StorageInventory {
    $physicalRaw = Get-CimDataSafe -ClassName "Win32_DiskDrive"
    $logicalRaw = Get-CimDataSafe -ClassName "Win32_LogicalDisk" -Filter "DriveType = 3"

    $physical = @(
        $physicalRaw | ForEach-Object {
            [ordered]@{
                Index         = $_.Index
                Model         = Get-SafeString $_.Model
                Manufacturer  = Get-SafeString $_.Manufacturer
                SerialNumber  = Get-SafeString $_.SerialNumber
                InterfaceType = Get-SafeString $_.InterfaceType
                MediaType     = Get-SafeString $_.MediaType
                Firmware      = Get-SafeString $_.FirmwareRevision
                SizeGB        = Convert-BytesToGB $_.Size
                Partitions    = $_.Partitions
                Status        = Get-SafeString $_.Status
            }
        }
    )

    $logical = @(
        $logicalRaw | ForEach-Object {
            $freePercent = if ($null -ne $_.Size -and [double]$_.Size -gt 0) {
                [math]::Round(([double]$_.FreeSpace / [double]$_.Size) * 100, 2)
            } else { $null }

            [ordered]@{
                Drive       = Get-SafeString $_.DeviceID
                VolumeName  = Get-SafeString $_.VolumeName
                FileSystem  = Get-SafeString $_.FileSystem
                SizeGB      = Convert-BytesToGB $_.Size
                FreeSpaceGB = Convert-BytesToGB $_.FreeSpace
                FreePercent = $freePercent
            }
        }
    )

    $detailed = @()
    if (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        try {
            $detailed = @(
                Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                    [ordered]@{
                        FriendlyName      = Get-SafeString $_.FriendlyName
                        SerialNumber      = Get-SafeString $_.SerialNumber
                        MediaType         = Get-SafeString $_.MediaType
                        BusType           = Get-SafeString $_.BusType
                        SizeGB            = Convert-BytesToGB $_.Size
                        HealthStatus      = Get-SafeString $_.HealthStatus
                        OperationalStatus = @($_.OperationalStatus)
                    }
                }
            )
        }
        catch {
            Write-Warning ("No se pudo consultar Get-PhysicalDisk: {0}" -f $_.Exception.Message)
        }
    }

    return [ordered]@{
        Physical = $physical
        Detailed = $detailed
        Logical = $logical
        Upgrade = [ordered]@{
            InstalledPhysicalDisks = $physicalRaw.Count
            InstalledNVMeDisks = @($detailed | Where-Object { $_.BusType -eq "NVMe" }).Count
            InstalledSATADisks = @($detailed | Where-Object { $_.BusType -eq "SATA" }).Count
            FreeM2Slots = $null
            FreeSataPorts = $null
            RequiresPhysicalVerification = $true
        }
    }
}
