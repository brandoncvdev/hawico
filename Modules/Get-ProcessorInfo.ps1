function Get-ProcessorInventory {
    $processorsRaw = Get-CimDataSafe -ClassName "Win32_Processor"
    return @(
        $processorsRaw | ForEach-Object {
            [ordered]@{
                Name                      = Get-SafeString $_.Name
                Manufacturer              = Get-SafeString $_.Manufacturer
                ProcessorId               = Get-SafeString $_.ProcessorId
                Socket                    = Get-SafeString $_.SocketDesignation
                NumberOfCores             = $_.NumberOfCores
                NumberOfLogicalProcessors = $_.NumberOfLogicalProcessors
                MaxClockSpeedMHz          = $_.MaxClockSpeed
                CurrentClockSpeedMHz      = $_.CurrentClockSpeed
                Status                    = Get-SafeString $_.Status
            }
        }
    )
}
