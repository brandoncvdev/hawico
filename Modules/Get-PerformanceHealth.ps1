function Get-PerformanceThreshold {
    param([AllowNull()][object]$Thresholds, [string]$Name, [double]$DefaultValue)
    if ($null -eq $Thresholds) { return $DefaultValue }
    if ($Thresholds -is [System.Collections.IDictionary] -and $Thresholds.Contains($Name)) { return [double]$Thresholds[$Name] }
    if ($Thresholds.PSObject.Properties.Name -contains $Name) { return [double]$Thresholds.$Name }
    return $DefaultValue
}

function Measure-PerformanceHealth {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Samples,
        [AllowNull()][object]$Thresholds
    )
    $valid = @($Samples | Where-Object { $null -ne $_ -and $null -ne $_.CPUPercent -and $null -ne $_.MemoryUsagePercent -and $null -ne $_.AvailableMemoryMB })
    if ($valid.Count -eq 0) {
        return [ordered]@{ Status="Failed";ValidSampleCount=0;CPU=@{};Memory=@{};ErrorCode='PERFORMANCE-NO-VALID-SAMPLES';ErrorMessage='No valid CPU and memory samples were collected.' }
    }
    $cpu = @($valid | ForEach-Object { [double]$_.CPUPercent })
    $memory = @($valid | ForEach-Object { [double]$_.MemoryUsagePercent })
    $available = @($valid | ForEach-Object { [double]$_.AvailableMemoryMB })
    $cpuMeasure = $cpu | Measure-Object -Average -Maximum
    $memoryMeasure = $memory | Measure-Object -Average -Maximum
    $availableMeasure = $available | Measure-Object -Average -Minimum
    $highCpu = @($cpu | Where-Object { $_ -ge 90 }).Count
    $warningThreshold = Get-PerformanceThreshold -Thresholds $Thresholds -Name 'MemoryWarningPercent' -DefaultValue 70
    $highThreshold = Get-PerformanceThreshold -Thresholds $Thresholds -Name 'MemoryHighPercent' -DefaultValue 85
    $criticalThreshold = Get-PerformanceThreshold -Thresholds $Thresholds -Name 'MemoryCriticalPercent' -DefaultValue 95
    $availableThreshold = Get-PerformanceThreshold -Thresholds $Thresholds -Name 'MinimumAvailableMemoryMB' -DefaultValue 1024
    $memoryAt70 = @($memory | Where-Object { $_ -ge 70 }).Count
    $memoryAt85 = @($memory | Where-Object { $_ -ge 85 }).Count
    $memoryAt95 = @($memory | Where-Object { $_ -ge 95 }).Count
    $memoryBelow1024 = @($available | Where-Object { $_ -lt 1024 }).Count
    $memoryWarning = @($memory | Where-Object { $_ -ge $warningThreshold }).Count
    $memoryHigh = @($memory | Where-Object { $_ -ge $highThreshold }).Count
    $memoryCritical = @($memory | Where-Object { $_ -ge $criticalThreshold }).Count
    $memoryLowAvailable = @($available | Where-Object { $_ -lt $availableThreshold }).Count
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
            WarningMatchingSamplePercent=[math]::Round(($memoryWarning/$valid.Count)*100,2)
            HighMatchingSamplePercent=[math]::Round(($memoryHigh/$valid.Count)*100,2)
            CriticalMatchingSamplePercent=[math]::Round(($memoryCritical/$valid.Count)*100,2)
            LowAvailableMatchingSamplePercent=[math]::Round(($memoryLowAvailable/$valid.Count)*100,2)
        }
    }
}
function Get-PerformanceSample {
 try {
  $result=Get-Counter -Counter @('\Processor(_Total)\% Processor Time','\Memory\% Committed Bytes In Use','\Memory\Available MBytes') -ErrorAction Stop
  $cpu=$result.CounterSamples|Where-Object Path -like '*processor time'|Select-Object -First 1
  $usage=$result.CounterSamples|Where-Object Path -like '*committed bytes in use'|Select-Object -First 1
  $available=$result.CounterSamples|Where-Object Path -like '*available mbytes'|Select-Object -First 1
  if($null-ne$cpu-and$null-ne$usage-and$null-ne$available){
   return [pscustomobject][ordered]@{CPUPercent=[math]::Round($cpu.CookedValue,2);MemoryUsagePercent=[math]::Round($usage.CookedValue,2);AvailableMemoryMB=[math]::Round($available.CookedValue,2)}
  }
 }catch{Write-Verbose 'Localized performance counters are unavailable; trying CIM performance classes.'}
 try{
  $processor=Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction Stop|Where-Object Name -eq '_Total'|Select-Object -First 1
  $memory=Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Memory' -ErrorAction Stop|Select-Object -First 1
  if($null-eq$processor-or$null-eq$memory){return $null}
  return [pscustomobject][ordered]@{CPUPercent=[math]::Round([double]$processor.PercentProcessorTime,2);MemoryUsagePercent=[math]::Round([double]$memory.PercentCommittedBytesInUse,2);AvailableMemoryMB=[math]::Round([double]$memory.AvailableMBytes,2)}
 }catch{return $null}
}
