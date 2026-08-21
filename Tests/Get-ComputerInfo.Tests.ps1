BeforeAll {
    # Collector_Hardware_Inventory.ps1 runs under Set-StrictMode -Version
    # Latest (its own line 15) — matched here so a property-access bug like
    # the real one reported in the field (Manufacturer missing when every
    # base CIM class fails) actually reproduces in this test file instead of
    # silently returning $null the way it would under the Pester default.
    Set-StrictMode -Version Latest
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-ComputerInfo.ps1"
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
    }
}

Describe 'Get-ComputerInventory' {
    Context 'when every base CIM class is unavailable (real case: 196JURIDICO, 2026-08-19, broken WMI repository)' {
        BeforeEach {
            # On this real machine, Get-CimInstance failed with "Not Found" for
            # Win32_ComputerSystem, Win32_ComputerSystemProduct, Win32_OperatingSystem,
            # Win32_BIOS and Win32_BaseBoard alike. Get-CimDataSafe's catch block
            # correctly swallows each of those and Select-Object -First 1 on the
            # (empty) result correctly ends up $null — but Get-ComputerInfo.ps1
            # then read properties straight off that $null (e.g.
            # `$computerSystem.Manufacturer`). Under this project's
            # Set-StrictMode -Version Latest, even a property access on $null
            # itself throws "The property 'X' cannot be found on this object" -
            # not just a missing property on a real object - which killed the
            # entire hardware inventory, exactly as in the real transcript.
            Mock Get-CimInstance { throw 'Not Found' }
        }

        It 'does not throw' {
            { Get-ComputerInventory } | Should -Not -Throw
        }

        It 'degrades every section to safe empty/null values instead of crashing' {
            $result = Get-ComputerInventory

            $result.Computer.Manufacturer | Should -BeNullOrEmpty
            $result.Computer.Model | Should -BeNullOrEmpty
            $result.BIOS.Manufacturer | Should -BeNullOrEmpty
            $result.Motherboard.Manufacturer | Should -BeNullOrEmpty
            $result.OperatingSystem.Caption | Should -BeNullOrEmpty
        }

        It 'still reports the one thing that never depends on CIM: the hostname' {
            (Get-ComputerInventory).Computer.Hostname | Should -Be $env:COMPUTERNAME
        }
    }

    Context 'when the base CIM classes are available' {
        BeforeEach {
            Mock Get-CimInstance {
                switch ($ClassName) {
                    'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'OptiPlex 3050'; SystemType = 'x64-based PC'; Domain = 'WORKGROUP'; PartOfDomain = $false; TotalPhysicalMemory = 17179869184 } }
                    'Win32_ComputerSystemProduct' { [pscustomobject]@{ UUID = 'abc-123'; IdentifyingNumber = 'SN123' } }
                    'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Pro'; Version = '10.0.19044'; BuildNumber = '19044'; OSArchitecture = '64-bit'; InstallDate = $null; LastBootUpTime = $null } }
                    'Win32_BIOS' { [pscustomobject]@{ Manufacturer = 'Dell Inc.'; SMBIOSBIOSVersion = '2.1.0'; SerialNumber = 'BIOS123'; ReleaseDate = $null } }
                    'Win32_BaseBoard' { [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Product = '0ABC1D'; Version = 'A00'; SerialNumber = 'BOARD123' } }
                }
            }
        }

        It 'reports the real values from each class' {
            $result = Get-ComputerInventory

            $result.Computer.Manufacturer | Should -Be 'Dell Inc.'
            $result.Computer.Model | Should -Be 'OptiPlex 3050'
            $result.BIOS.SerialNumber | Should -Be 'BIOS123'
            $result.Motherboard.Product | Should -Be '0ABC1D'
            $result.OperatingSystem.Caption | Should -Be 'Microsoft Windows 10 Pro'
        }
    }
}
