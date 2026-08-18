BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-ProcessorInfo.ps1"
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
    }
}

Describe 'Get-ProcessorInventory' {
    It 'returns a real array, not a bare object, when exactly one processor is detected' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name                      = 'Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz'
                Manufacturer              = 'GenuineIntel'
                ProcessorId               = 'BFEBFBFF000A0652'
                SocketDesignation         = 'U3E1'
                NumberOfCores             = 6
                NumberOfLogicalProcessors = 12
                MaxClockSpeed             = 3100
                CurrentClockSpeed         = 3100
                Status                    = 'OK'
            }
        }

        $result = Get-ProcessorInventory

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz'
    }

    It 'returns every processor when more than one is detected' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ Name = 'CPU 0'; NumberOfCores = 4 }
                [pscustomobject]@{ Name = 'CPU 1'; NumberOfCores = 4 }
            )
        }

        $result = Get-ProcessorInventory

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 2
    }
}
