BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-GraphicsInfo.ps1"
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
    }
}

Describe 'Get-GraphicsInventory' {
    It 'returns a real array, not a bare object, when exactly one graphics adapter is detected' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name                          = 'Intel(R) UHD Graphics'
                VideoProcessor                = 'Intel(R) UHD Graphics Family'
                AdapterRAM                    = 1073741824
                DriverVersion                 = '27.20.100.9316'
                DriverDate                    = [datetime]'2026-01-01'
                CurrentHorizontalResolution   = 1920
                CurrentVerticalResolution     = 1080
                Status                        = 'OK'
            }
        }

        $result = Get-GraphicsInventory

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Intel(R) UHD Graphics'
        $result[0].Resolution | Should -Be '1920x1080'
    }

    It 'returns every adapter when more than one graphics adapter is detected' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ Name = 'GPU 0' }
                [pscustomobject]@{ Name = 'GPU 1' }
            )
        }

        $result = Get-GraphicsInventory

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 2
    }
}
