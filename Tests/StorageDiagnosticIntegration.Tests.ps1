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

    It 'never crashes and never falsely reports SMARTCTL-NOT-FOUND on a non-NVMe disk when Tools\smartctl.exe is absent (PR2/PR7 ships no binary — see Tools/README.md)' {
        # This is the intended, already-tested fallback behavior, not a gap:
        # PR7 deliberately ships Tools\ with only a README, never a fake
        # binary. IMPORTANT (Real-World Amendment, PR9): this can NOT assert
        # every disk comes back Supported=$false anymore. WMI
        # FailurePredictData is now tried FIRST for every non-NVMe bus and
        # needs no external binary at all — on real hardware where WMI has
        # data (like the Dell this was validated against), a disk legitimately
        # comes back Supported=$true even with smartctl completely absent.
        # SMARTCTL-NOT-FOUND is reachable ONLY on the NVMe branch, which is
        # unaffected by the WMI amendment and stays fully smartctl-dependent.
        Test-Path -LiteralPath $smartctlPath | Should -BeFalse

        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        $physicalDisks = @($report.Storage.Physical)
        $detailedDisks = @($report.Storage.Detailed)
        if ($physicalDisks.Count -gt 0) {
            foreach ($disk in $physicalDisks) {
                # BusType (the field that actually distinguishes NVMe) only
                # exists on Storage.Detailed[] (Get-PhysicalDisk), not on
                # Storage.Physical[] (Win32_DiskDrive) — correlate by
                # SerialNumber the same way Get-StorageInventory itself does.
                $matchingDetailed = $detailedDisks | Where-Object { $_.SerialNumber -eq $disk.SerialNumber } | Select-Object -First 1
                $isNvme = $null -ne $matchingDetailed -and $matchingDetailed.BusType -eq 'NVMe'

                $disk.Smart.Supported | Should -BeOfType [bool]
                if ($disk.Smart.Supported) {
                    $disk.Smart.Source | Should -BeIn @('ATA', 'NVMe')
                }
                else {
                    $disk.Smart.Source | Should -Be 'Unavailable'
                    if ($isNvme) {
                        $disk.Smart.ErrorCode | Should -Be 'SMARTCTL-NOT-FOUND'
                    }
                    else {
                        # Non-NVMe: WMI was tried first and had nothing —
                        # never the smartctl-specific error, since smartctl
                        # is never even reached in this case.
                        $disk.Smart.ErrorCode | Should -Match '^WMI-'
                    }
                }
            }
        }
    }
}
