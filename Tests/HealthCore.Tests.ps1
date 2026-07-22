BeforeAll {
    . "$PSScriptRoot/../Modules/Get-HealthConfig.ps1"
    . "$PSScriptRoot/../Modules/Get-HealthFindings.ps1"
}

Describe 'Get-HealthCheckConfig' {
    It 'returns the documented defaults when HealthCheck is absent' {
        $result = Get-HealthCheckConfig -Config ([pscustomobject]@{
            GenerateJSON = $true
            GenerateHTML = $false
        })

        $result.SampleDurationSeconds | Should -Be 60
        $result.SampleIntervalSeconds | Should -Be 1
        $result.EventLookbackDays | Should -Be 7
        $result.MinimumFreeDiskPercent | Should -Be 20
        $result.CriticalFreeDiskPercent | Should -Be 10
        $result.MemoryWarningPercent | Should -Be 70
        $result.MemoryHighPercent | Should -Be 85
        $result.MemoryCriticalPercent | Should -Be 95
        $result.MinimumAvailableMemoryMB | Should -Be 1024
        $result.IncludePersonallyIdentifiableInformation | Should -BeFalse
        $result.GenerateJSON | Should -BeTrue
        $result.GenerateHTML | Should -BeFalse
    }

    It 'merges valid HealthCheck overrides' {
        $result = Get-HealthCheckConfig -Config ([pscustomobject]@{
            GenerateJSON = $true
            GenerateHTML = $true
            HealthCheck = [pscustomobject]@{
                SampleDurationSeconds = 120
                EventLookbackDays = 14
            }
        })

        $result.SampleDurationSeconds | Should -Be 120
        $result.EventLookbackDays | Should -Be 14
        $result.SampleIntervalSeconds | Should -Be 1
    }

    It 'rejects an invalid sample duration' {
        {
            Get-HealthCheckConfig -Config ([pscustomobject]@{
                HealthCheck = [pscustomobject]@{ SampleDurationSeconds = 9 }
            })
        } | Should -Throw '*SampleDurationSeconds*'
    }

    It 'rejects unordered memory thresholds' {
        {
            Get-HealthCheckConfig -Config ([pscustomobject]@{
                HealthCheck = [pscustomobject]@{
                    MemoryWarningPercent = 85
                    MemoryHighPercent = 85
                    MemoryCriticalPercent = 95
                }
            })
        } | Should -Throw '*MemoryWarningPercent*'
    }
}

Describe 'Get-HealthScore' {
    It 'calculates a fully evaluated score' {
        $result = Get-HealthScore -Categories @(
            [pscustomobject]@{ Name = 'Storage'; Weight = 35; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'Memory'; Weight = 25; Available = $true; Deduction = 8; HighestSeverity = 'Medium' }
            [pscustomobject]@{ Name = 'CPU'; Weight = 20; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'Events'; Weight = 20; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
        )

        $result.Value | Should -Be 92
        $result.Status | Should -Be 'Healthy'
        $result.ConfidencePercent | Should -Be 100
        $result.PrimaryBottleneck | Should -Be 'Memory'
    }

    It 'caps deductions at each category weight' {
        $result = Get-HealthScore -Categories @(
            [pscustomobject]@{ Name = 'Storage'; Weight = 35; Available = $true; Deduction = 80; HighestSeverity = 'Critical' }
            [pscustomobject]@{ Name = 'Memory'; Weight = 25; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'CPU'; Weight = 20; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'Events'; Weight = 20; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
        )

        $result.TotalDeduction | Should -Be 35
        $result.Value | Should -Be 65
    }

    It 'normalizes by evaluated weight and reports confidence' {
        $result = Get-HealthScore -Categories @(
            [pscustomobject]@{ Name = 'Storage'; Weight = 35; Available = $true; Deduction = 10; HighestSeverity = 'High' }
            [pscustomobject]@{ Name = 'Memory'; Weight = 25; Available = $false; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'CPU'; Weight = 20; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'Events'; Weight = 20; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
        )

        $result.EvaluatedWeight | Should -Be 75
        $result.ConfidencePercent | Should -Be 75
        $result.Value | Should -Be 87
    }

    It 'returns insufficient data below sixty percent coverage' {
        $result = Get-HealthScore -Categories @(
            [pscustomobject]@{ Name = 'Storage'; Weight = 35; Available = $true; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'Memory'; Weight = 25; Available = $false; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'CPU'; Weight = 20; Available = $false; Deduction = 0; HighestSeverity = 'Info' }
            [pscustomobject]@{ Name = 'Events'; Weight = 20; Available = $false; Deduction = 0; HighestSeverity = 'Info' }
        )

        $result.Value | Should -BeNullOrEmpty
        $result.Status | Should -Be 'InsufficientData'
    }
}
