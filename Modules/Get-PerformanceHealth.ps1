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
    $memoryAt70 = @($memory | Where-Object { $_ -ge 70 }).Count
    $memoryAt85 = @($memory | Where-Object { $_ -ge 85 }).Count
    $memoryAt95 = @($memory | Where-Object { $_ -ge 95 }).Count
    $memoryBelow1024 = @($available | Where-Object { $_ -lt 1024 }).Count
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
            SamplesAtOrAbove70Percent=[math]::Round(($memoryAt70/$valid.Count)*100,2)
            SamplesAtOrAbove85Percent=[math]::Round(($memoryAt85/$valid.Count)*100,2)
            SamplesAtOrAbove95Percent=[math]::Round(($memoryAt95/$valid.Count)*100,2)
            SamplesBelow1024MB=[math]::Round(($memoryBelow1024/$valid.Count)*100,2)
        }
    }
}
function Get-PerformanceSample {
 try {
  $result=Get-Counter -Counter @('\Processor(_Total)\% Processor Time','\Memory\% Committed Bytes In Use','\Memory\Available MBytes') -ErrorAction Stop
  $cpu=$result.CounterSamples|Where-Object Path -like '*processor time'|Select-Object -First 1
  $usage=$result.CounterSamples|Where-Object Path -like '*committed bytes in use'|Select-Object -First 1
  $available=$result.CounterSamples|Where-Object Path -like '*available mbytes'|Select-Object -First 1
  if($null-eq$cpu-or$null-eq$usage-or$null-eq$available){return $null}
  return [pscustomobject][ordered]@{CPUPercent=[math]::Round($cpu.CookedValue,2);MemoryUsagePercent=[math]::Round($usage.CookedValue,2);AvailableMemoryMB=[math]::Round($available.CookedValue,2)}
 }catch{return $null}
}
