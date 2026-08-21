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
    if (($arraysRaw | Measure-Object).Count -gt 0) {
        $m = $arraysRaw | Measure-Object -Property MemoryDevices -Sum
        if ($null -ne $m.Sum) { $totalSlots = [int]$m.Sum }
    }

    $occupiedSlots = (
        $modulesRaw |
        Where-Object {
            $null -ne $_.Capacity -and [double]$_.Capacity -gt 0
        } |
        Measure-Object
    ).Count
    # A plain PowerShell comparison, not [math]::Max(0, ...): an untyped `0`
    # literal makes PowerShell 5.1 try the Max(Int32, Int32) .NET overload
    # first, which throws if the other operand doesn't fit Int32. Slot counts
    # are always small here, but the pattern is the same landmine fixed below
    # for the capacity math, where it's a real, reproduced crash.
    $slotDelta = $totalSlots - $occupiedSlots
    $availableSlots = if ($slotDelta -lt 0) { 0 } else { $slotDelta }

    $installedBytes = 0
    if (($modulesRaw | Measure-Object).Count -gt 0) {
        $m = $modulesRaw | Measure-Object -Property Capacity -Sum
        if ($null -ne $m.Sum) { $installedBytes = [double]$m.Sum }
    }

    $maximumKB = 0
    if (($arraysRaw | Measure-Object).Count -gt 0) {
        $m = $arraysRaw | Measure-Object -Property MaxCapacityEx -Sum
        if ($null -ne $m.Sum -and [double]$m.Sum -gt 0) {
            $maximumKB = [double]$m.Sum
        } else {
            $m = $arraysRaw | Measure-Object -Property MaxCapacity -Sum
            if ($null -ne $m.Sum) { $maximumKB = [double]$m.Sum }
        }
    }

    # Win32_PhysicalMemoryArray.MaxCapacity(Ex) is manufacturer-reported and, on
    # real hardware with an incomplete/corrupted SMBIOS table, can come back as
    # garbage several orders of magnitude too large (confirmed on a real
    # machine: ~9.9 billion "GB" of max capacity). 64 TB is comfortably above
    # any real workstation/server RAM ceiling, so anything past it is treated
    # as unreliable rather than surfaced as a nonsense number.
    $maxSaneCapacityKB = 64TB / 1KB
    $maximumReliable = $maximumKB -gt 0 -and $maximumKB -le $maxSaneCapacityKB

    $installedGB = Convert-BytesToGB $installedBytes
    $maximumGB = if ($maximumReliable) { Convert-KBToGB $maximumKB } else { $null }
    $possibleGB = if ($null -ne $maximumGB) {
        # Plain comparison instead of [math]::Max(0, ...): see the AvailableSlots
        # comment above — an untyped `0` literal makes PowerShell 5.1 try the
        # Max(Int32, Int32) overload first, which throws when the delta doesn't
        # fit Int32. This is the exact crash reproduced in
        # Tests/Get-MemoryInfo.Tests.ps1 and reported from a real machine.
        $delta = [math]::Round(([double]$maximumGB - [double]$installedGB), 2)
        if ($delta -lt 0) { 0 } else { $delta }
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
