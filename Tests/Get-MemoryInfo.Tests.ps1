BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-MemoryInfo.ps1"
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
    }
}

Describe 'Get-MemoryInventory' {
    Context 'when Win32_PhysicalMemoryArray reports an implausible MaxCapacityEx' {
        BeforeEach {
            # Real-world case (AIODELL188, 2026-08-17): a corrupted SMBIOS table made
            # Windows report a MaxCapacityEx so large that, after KB->GB conversion,
            # the "potential additional GB" delta exceeded Int32's range. That blew up
            # `[math]::Max(0, $delta)` — PowerShell 5.1 tries the Max(Int32, Int32)
            # overload first because of the untyped `0` literal, and converting the
            # oversized delta to Int32 throws, killing the entire hardware inventory
            # (ErrorActionPreference = Stop). 2e16 KB converts to ~19 billion GB —
            # past both Int32's range and the 64 TB sanity ceiling, same shape as
            # the real corrupted reading.
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_PhysicalMemoryArray') {
                    [pscustomobject]@{ MemoryDevices = 4; MaxCapacityEx = 20000000000000000; MaxCapacity = 0 }
                }
                else {
                    [pscustomobject]@{ Capacity = 8589934592 } # 8 GB installed
                }
            }
        }

        It 'does not throw' {
            { Get-MemoryInventory } | Should -Not -Throw
        }

        It 'reports the max/potential-upgrade figures as unreliable instead of a nonsense value' {
            $result = Get-MemoryInventory

            $result.Upgrade.MaximumReportedGB | Should -BeNullOrEmpty
            $result.Upgrade.PotentialAdditionalGB | Should -BeNullOrEmpty
            $result.Upgrade.RequiresVerification | Should -BeTrue
        }

        It 'still reports what it does know: installed memory and slot counts' {
            $result = Get-MemoryInventory

            $result.Upgrade.InstalledMemoryGB | Should -Be 8
            $result.Upgrade.TotalSlots | Should -Be 4
            $result.Upgrade.OccupiedSlots | Should -Be 1
        }
    }

    Context 'when Win32_PhysicalMemoryArray reports a plausible MaxCapacityEx' {
        BeforeEach {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_PhysicalMemoryArray') {
                    [pscustomobject]@{ MemoryDevices = 4; MaxCapacityEx = 134217728; MaxCapacity = 0 } # 128 GB
                }
                else {
                    [pscustomobject]@{ Capacity = 17179869184 } # 16 GB installed
                }
            }
        }

        It 'computes the real potential-upgrade headroom and does not flag verification' {
            $result = Get-MemoryInventory

            $result.Upgrade.MaximumReportedGB | Should -Be 128
            $result.Upgrade.InstalledMemoryGB | Should -Be 16
            $result.Upgrade.PotentialAdditionalGB | Should -Be 112
            $result.Upgrade.RequiresVerification | Should -BeFalse
        }
    }

    Context 'when more modules are installed than the array reports slots for' {
        BeforeEach {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_PhysicalMemoryArray') {
                    [pscustomobject]@{ MemoryDevices = 2; MaxCapacityEx = 0; MaxCapacity = 0 }
                }
                else {
                    @(
                        [pscustomobject]@{ Capacity = 8589934592 }
                        [pscustomobject]@{ Capacity = 8589934592 }
                        [pscustomobject]@{ Capacity = 8589934592 }
                    )
                }
            }
        }

        It 'clamps AvailableSlots to 0 instead of going negative or throwing' {
            { Get-MemoryInventory } | Should -Not -Throw
            (Get-MemoryInventory).Upgrade.AvailableSlots | Should -Be 0
        }
    }
}
