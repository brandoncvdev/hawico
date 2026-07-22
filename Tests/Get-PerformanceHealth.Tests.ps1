BeforeAll { . "$PSScriptRoot/../Modules/Get-PerformanceHealth.ps1" }

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
}
