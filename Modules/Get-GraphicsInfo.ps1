function Get-GraphicsInventory {
    # Get-CimDataSafe already comma-guards its own return (`return ,@(...)`),
    # so re-wrapping the call itself in `@(...)` here would re-enumerate that
    # already-guarded single output-stream item and nest the real array one
    # level too deep (confirmed empirically: it silently collapsed the
    # multi-adapter test to Count 1). Assign the call result directly and
    # rely on the outer `,@(...)` return guard below — without that guard, a
    # single-video-controller machine (the common case) would return a bare
    # scalar instead of a one-element array (same output-stream-boundary
    # hazard as Get-NetworkInventory's return).
    $raw = Get-CimDataSafe -ClassName "Win32_VideoController"
    return ,@(
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
