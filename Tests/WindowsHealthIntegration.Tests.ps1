$isWindowsTarget = $PSVersionTable.PSVersion.Major -le 5 -or $PSVersionTable.Platform -eq 'Win32NT' -or $env:OS -eq 'Windows_NT'

Describe 'Windows health collector integration' -Tag 'Integration' -Skip:(-not $isWindowsTarget) {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $collectorPath = Join-Path $projectRoot 'Collector_Windows_HealthCheck.ps1'
        $script:result = & $collectorPath -Mode Diagnostic -SampleDurationSeconds 10
    }

    It 'produces every configured delivery-one artifact' {
        $result.Success | Should -BeTrue
        Test-Path -LiteralPath $result.JsonPath | Should -BeTrue
        Test-Path -LiteralPath $result.HtmlPath | Should -BeTrue
        Test-Path -LiteralPath $result.LogPath | Should -BeTrue
    }

    It 'emits the compatible and explainable JSON contract' {
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        $report.SchemaVersion | Should -Be '2.0'
        $report.Collection.Type | Should -Be 'WindowsHealthCheck'
        $report.HealthCheck.ContractVersion | Should -Be '1.1'
        $report.HealthCheck.Status | Should -BeIn @('Completed', 'Partial')
        $report.HealthCheck.Sections.Name | Should -Contain 'Performance'
        $report.HealthCheck.Sections.Name | Should -Contain 'Storage'
        $report.HealthCheck.Sections.Name | Should -Contain 'Events'
    }
}
