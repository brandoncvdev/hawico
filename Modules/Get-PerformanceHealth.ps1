function Measure-PerformanceHealth {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Samples)
    $valid = @($Samples | Where-Object { $null -ne $_ -and $null -ne $_.CPUPercent -and $null -ne $_.MemoryUsagePercent -and $null -ne $_.AvailableMemoryMB })
    if ($valid.Count -eq 0) {
        return [ordered]@{ Status="Failed"; ValidSampleCount=0; CPU=@{}; Memory=@{} }
    }
    $cpu = @($valid | ForEach-Object { [double]$_.CPUPercent })
    $memory = @($valid | ForEach-Object { [double]$_.MemoryUsagePercent })
    $available = @($valid | ForEach-Object { [double]$_.AvailableMemoryMB })
    $cpuMeasure = $cpu | Measure-Object -Average -Maximum
    $memoryMeasure = $memory | Measure-Object -Average -Maximum
    $availableMeasure = $available | Measure-Object -Average -Minimum
    $highCpu = @($cpu | Where-Object { $_ -ge 90 }).Count
    return [ordered]@{
        Status = if ($valid.Count -eq $Samples.Count) { "Collected" } else { "Partial" }
        ValidSampleCount = $valid.Count
        CPU = [ordered]@{
            AverageUsagePercent=[math]::Round($cpuMeasure.Average,2)
            PeakUsagePercent=[math]::Round($cpuMeasure.Maximum,2)
            SamplesAtOrAbove90Percent=[math]::Round(($highCpu/$valid.Count)*100,2)
        }
        Memory = [ordered]@{
            AverageUsagePercent=[math]::Round($memoryMeasure.Average,2)
            PeakUsagePercent=[math]::Round($memoryMeasure.Maximum,2)
            AverageAvailableMB=[math]::Round($availableMeasure.Average,2)
            MinimumAvailableMB=[math]::Round($availableMeasure.Minimum,2)
        }
    }
}
