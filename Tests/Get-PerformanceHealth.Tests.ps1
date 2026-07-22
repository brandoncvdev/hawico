BeforeAll {
 . "$PSScriptRoot/../Modules/Get-PerformanceHealth.ps1"
 if(-not(Get-Command Get-Counter -ErrorAction SilentlyContinue)){function Get-Counter { param([string[]]$Counter) }}
}

Describe 'Measure-PerformanceHealth' {
    It 'summarizes valid CPU and memory samples' {
        $r = Measure-PerformanceHealth -Samples @(
            [pscustomobject]@{ CPUPercent=80; MemoryUsagePercent=70; AvailableMemoryMB=2000 }
            [pscustomobject]@{ CPUPercent=100; MemoryUsagePercent=90; AvailableMemoryMB=500 }
        )
        $r.ValidSampleCount | Should -Be 2
        $r.CPU.AverageUsagePercent | Should -Be 90
        $r.CPU.PeakUsagePercent | Should -Be 100
        $r.CPU.SamplesAtOrAbove90Percent | Should -Be 50
        $r.Memory.AverageUsagePercent | Should -Be 80
        $r.Memory.MinimumAvailableMB | Should -Be 500
        $r.Memory.SamplesAtOrAbove70Percent | Should -Be 100
        $r.Memory.SamplesAtOrAbove85Percent | Should -Be 50
        $r.Memory.SamplesAtOrAbove95Percent | Should -Be 0
        $r.Memory.SamplesBelow1024MB | Should -Be 50
    }

    It 'ignores invalid samples' {
        $r = Measure-PerformanceHealth -Samples @($null,[pscustomobject]@{ CPUPercent=$null; MemoryUsagePercent=$null; AvailableMemoryMB=$null })
        $r.ValidSampleCount | Should -Be 0
        $r.Status | Should -Be 'Failed'
    }

    It 'marks mixed valid and invalid input partial' {
        $r = Measure-PerformanceHealth -Samples @($null,[pscustomobject]@{ CPUPercent=10; MemoryUsagePercent=20; AvailableMemoryMB=3000 })
        $r.Status | Should -Be 'Partial'
    }
    It 'calculates persistence against configured memory thresholds' {
        $thresholds = [pscustomobject]@{MemoryWarningPercent=60;MemoryHighPercent=75;MemoryCriticalPercent=90;MinimumAvailableMemoryMB=1500}
        $r = Measure-PerformanceHealth -Samples @(
            [pscustomobject]@{CPUPercent=10;MemoryUsagePercent=76;AvailableMemoryMB=1400},
            [pscustomobject]@{CPUPercent=20;MemoryUsagePercent=92;AvailableMemoryMB=2000}
        ) -Thresholds $thresholds
        $r.Memory.WarningMatchingSamplePercent | Should -Be 100
        $r.Memory.HighMatchingSamplePercent | Should -Be 100
        $r.Memory.CriticalMatchingSamplePercent | Should -Be 50
        $r.Memory.LowAvailableMatchingSamplePercent | Should -Be 50
    }
}
Describe 'Get-PerformanceSample' {
 It 'maps Windows counter values into a sample' {
  Mock Get-Counter { [pscustomobject]@{CounterSamples=@([pscustomobject]@{Path='\\pc\\processor(_total)\\% processor time';CookedValue=40},[pscustomobject]@{Path='\\pc\\memory\\% committed bytes in use';CookedValue=75},[pscustomobject]@{Path='\\pc\\memory\\available mbytes';CookedValue=2048})} }
  $r=Get-PerformanceSample
  $r.CPUPercent|Should -Be 40
  $r.MemoryUsagePercent|Should -Be 75
  $r.AvailableMemoryMB|Should -Be 2048
 }
 It 'returns null when counters fail' { Mock Get-Counter { throw 'unavailable' }; Get-PerformanceSample|Should -BeNullOrEmpty }
}
