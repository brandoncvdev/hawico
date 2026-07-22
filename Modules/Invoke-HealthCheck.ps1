function Invoke-HealthCheck {
 param([Parameter(Mandatory)][System.Collections.IDictionary]$InputData,[datetimeoffset]$CollectedAt)
 $performance=$InputData.Performance;$storage=$InputData.Storage;$events=@($InputData.Events)
 $metrics=[pscustomobject]@{
  CPU=[pscustomobject]@{AverageUsagePercent=$performance.CPU.AverageUsagePercent;SamplesAtOrAbove90Percent=$performance.CPU.SamplesAtOrAbove90Percent}
  Memory=[pscustomobject]@{UsagePercent=$performance.Memory.AverageUsagePercent;MatchingSamplePercent=100}
  Storage=[pscustomobject]@{}
 }
 $findings=@(Get-HealthFinding -Metrics $metrics)
 $categories=@()
 foreach($definition in @(@('Storage',35),@('Memory',25),@('CPU',20),@('Events',20))){
  $name=$definition[0];$available=if($name-in @('CPU','Memory')){$performance.Status-ne'Failed'}elseif($name-eq'Storage'){$storage.Status-ne'Failed'}else{$true}
  $items=@($findings|Where-Object Category -eq $name)
  $categories+=[pscustomobject]@{Name=$name;Weight=[int]$definition[1];Available=$available;Deduction=($items|Measure-Object -Property ScoreImpact -Sum).Sum*-1;HighestSeverity=if($items){$items[0].Severity}else{'Info'}}
 }
 $score=Get-HealthScore -Categories $categories
 $status=if($performance.Status-eq'Failed' -or $storage.Status-eq'Failed'){'Partial'}else{'Completed'}
 $health=[ordered]@{Status=$status;Capabilities=$InputData.Capabilities;Metrics=[ordered]@{CPU=$performance.CPU;Memory=$performance.Memory;Storage=$storage;Events=$events};Score=$score;PrimaryBottleneck=$score.PrimaryBottleneck;Findings=$findings;Recommendations=@();Errors=@()}
 return ConvertTo-HealthCheckReport -BaseInventory $InputData.BaseInventory -HealthCheck $health -CollectedAt $CollectedAt -DurationMilliseconds 0
}
