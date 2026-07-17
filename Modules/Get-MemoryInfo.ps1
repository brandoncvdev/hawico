function Get-MemoryInventory {
    $modulesRaw = Get-CimDataSafe -ClassName "Win32_PhysicalMemory"
    $arraysRaw = Get-CimDataSafe -ClassName "Win32_PhysicalMemoryArray"

    $modules = @(
        $modulesRaw | ForEach-Object {
            [ordered]@{
                BankLabel          = Get-SafeString $_.BankLabel
                DeviceLocator      = Get-SafeString $_.DeviceLocator
                Manufacturer       = Get-SafeString $_.Manufacturer
                PartNumber         = Get-SafeString $_.PartNumber
                SerialNumber       = Get-SafeString $_.SerialNumber
                CapacityGB         = Convert-BytesToGB $_.Capacity
                SpeedMHz           = $_.Speed
                ConfiguredSpeedMHz = $_.ConfiguredClockSpeed
                MemoryTypeName     = Get-MemoryTypeName $_.SMBIOSMemoryType
            }
        }
    )

    $totalSlots = 0
    if ($arraysRaw.Count -gt 0) {
        $m = $arraysRaw | Measure-Object -Property MemoryDevices -Sum
        if ($null -ne $m.Sum) { $totalSlots = [int]$m.Sum }
    }

    $occupiedSlots = @($modulesRaw | Where-Object { $null -ne $_.Capacity -and [double]$_.Capacity -gt 0 }).Count
    $availableSlots = [math]::Max(0, $totalSlots - $occupiedSlots)

    $installedBytes = 0
    if ($modulesRaw.Count -gt 0) {
        $m = $modulesRaw | Measure-Object -Property Capacity -Sum
        if ($null -ne $m.Sum) { $installedBytes = [double]$m.Sum }
    }

    $maximumKB = 0
    if ($arraysRaw.Count -gt 0) {
        $m = $arraysRaw | Measure-Object -Property MaxCapacityEx -Sum
        if ($null -ne $m.Sum -and [double]$m.Sum -gt 0) {
            $maximumKB = [double]$m.Sum
        } else {
            $m = $arraysRaw | Measure-Object -Property MaxCapacity -Sum
            if ($null -ne $m.Sum) { $maximumKB = [double]$m.Sum }
        }
    }

    $installedGB = Convert-BytesToGB $installedBytes
    $maximumGB = if ($maximumKB -gt 0) { Convert-KBToGB $maximumKB } else { $null }
    $possibleGB = if ($null -ne $maximumGB) {
        [math]::Max(0, [math]::Round(([double]$maximumGB - [double]$installedGB), 2))
    } else { $null }

    return [ordered]@{
        Modules = $modules
        Upgrade = [ordered]@{
            TotalSlots            = $totalSlots
            OccupiedSlots         = $occupiedSlots
            AvailableSlots        = $availableSlots
            InstalledMemoryGB     = $installedGB
            MaximumReportedGB     = $maximumGB
            PotentialAdditionalGB = $possibleGB
            Reliability           = "ManufacturerReported"
            RequiresVerification  = ($totalSlots -eq 0 -or $null -eq $maximumGB)
        }
    }
}
