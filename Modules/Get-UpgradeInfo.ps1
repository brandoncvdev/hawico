function Get-ExpansionSlotInventory {
    $raw = Get-CimDataSafe -ClassName "Win32_SystemSlot"
    $slots = @(
        $raw | ForEach-Object {
            [ordered]@{
                SlotDesignation = Get-SafeString $_.SlotDesignation
                Description     = Get-SafeString $_.Description
                Status          = Get-SafeString $_.Status
                CurrentUsage    = Get-SystemSlotUsageName $_.CurrentUsage
                MaxDataWidth    = $_.MaxDataWidth
                Purpose         = Get-SafeString $_.Purpose
                SupportsHotPlug = $_.SupportsHotPlug
            }
        }
    )

    return [ordered]@{
        Slots = $slots
        Summary = [ordered]@{
            TotalReported = $raw.Count
            AvailableReported = @($raw | Where-Object { $_.CurrentUsage -eq 3 }).Count
            OccupiedReported = @($raw | Where-Object { $_.CurrentUsage -eq 4 }).Count
            Reliability = "ManufacturerReported"
            RequiresPhysicalVerification = $true
        }
    }
}
