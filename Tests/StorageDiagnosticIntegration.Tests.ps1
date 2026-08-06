$isWindowsTarget = $PSVersionTable.PSVersion.Major -le 5 -or $PSVersionTable.Platform -eq 'Win32NT' -or $env:OS -eq 'Windows_NT'

Describe 'Storage diagnostic collector integration' -Tag 'Integration' -Skip:(-not $isWindowsTarget) {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $collectorPath = Join-Path $projectRoot 'Collector_Storage_Diagnostic.ps1'
        $script:smartctlPath = Join-Path $projectRoot 'Tools\smartctl.exe'
        $script:result = & $collectorPath -Mode Diagnostic
    }

    It 'produces every configured storage-diagnostic artifact' {
        $result.Success | Should -BeTrue
        Test-Path -LiteralPath $result.JsonPath | Should -BeTrue
        Test-Path -LiteralPath $result.HtmlPath | Should -BeTrue
        Test-Path -LiteralPath $result.LogPath | Should -BeTrue
    }

    It 'emits a Storage-only report: Storage evaluated, Performance/Events skipped' {
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        $report.SchemaVersion | Should -Be '2.0'
        $report.HealthCheck.Sections.Name | Should -Contain 'Storage'
        ($report.HealthCheck.Sections | Where-Object Name -eq 'Performance').Status | Should -Be 'Skipped'
        ($report.HealthCheck.Sections | Where-Object Name -eq 'Events').Status | Should -Be 'Skipped'
        $report.HealthCheck.Score.Categories | Where-Object Name -eq 'Storage' | ForEach-Object { $_.Available } | Should -Contain $true
        @('CPU', 'Memory', 'Events') | ForEach-Object {
            ($report.HealthCheck.Score.Categories | Where-Object Name -eq $_).Available | Should -Be $false
        }
    }

    It 'exercises the already-built graceful-degradation path when Tools\smartctl.exe is absent (PR2, PR7 ships no binary — see Tools/README.md)' {
        # This is the intended, already-tested fallback behavior (Get-StorageInventory's
        # single Test-Path pre-check), not a gap: PR7 deliberately ships Tools\ with only
        # a README explaining what to place there, never a fake/placeholder binary.
        Test-Path -LiteralPath $smartctlPath | Should -BeFalse

        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        $physicalDisks = @($report.Storage.Physical)
        if ($physicalDisks.Count -gt 0) {
            foreach ($disk in $physicalDisks) {
                $disk.Smart.Supported | Should -BeFalse
                $disk.Smart.Source | Should -Be 'Unavailable'
                $disk.Smart.ErrorCode | Should -Be 'SMARTCTL-NOT-FOUND'
            }
        }
    }
}
