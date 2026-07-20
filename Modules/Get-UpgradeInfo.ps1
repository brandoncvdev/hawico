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
                Purpose = if ($_.PSObject.Properties.Name -contains "Purpose") {
                    Get-SafeString $_.Purpose
                }
                else {
                    $null
                }

                SupportsHotPlug = if (
                    $_.PSObject.Properties.Name -contains "SupportsHotPlug"
                ) {
                    $_.SupportsHotPlug
                }
                else {
                    $null
                }
            }
        }
    )

    return [ordered]@{
        Slots = $slots
        Summary = [ordered]@{
            TotalReported = (
                $raw | Measure-Object
            ).Count

            AvailableReported = (
                $raw |
                Where-Object {
                    $_.CurrentUsage -eq 3
                } |
                Measure-Object
            ).Count

            OccupiedReported = (
                $raw |
                Where-Object {
                    $_.CurrentUsage -eq 4
                } |
                Measure-Object
            ).Count
            Reliability = "ManufacturerReported"
            RequiresPhysicalVerification = $true
        }
    }
}
