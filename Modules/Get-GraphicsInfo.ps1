function Get-GraphicsInventory {
    $raw = Get-CimDataSafe -ClassName "Win32_VideoController"
    return @(
        $raw | ForEach-Object {
            [ordered]@{
                Name          = Get-SafeString $_.Name
                VideoProcessor = Get-SafeString $_.VideoProcessor
                AdapterRAMGB  = Convert-BytesToGB $_.AdapterRAM
                DriverVersion = Get-SafeString $_.DriverVersion
                DriverDate    = Convert-CimDate $_.DriverDate
                Resolution    = if ($_.CurrentHorizontalResolution -and $_.CurrentVerticalResolution) {
                    "{0}x{1}" -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution
                } else { $null }
                Status        = Get-SafeString $_.Status
            }
        }
    )
}
