BeforeAll {
    . "$PSScriptRoot/../Modules/Get-PeripheralInfo.ps1"
}

Describe 'Get-PeripheralCategory' {
    It 'clasifica dispositivos Bluetooth por su identificador PnP' {
        $device = [pscustomobject]@{
            Class = 'HIDClass'
            InstanceId = 'BTHENUM\DEV_001122334455'
            FriendlyName = 'Bluetooth Mouse'
        }

        Get-PeripheralCategory -Device $device | Should -Be 'Bluetooth'
    }

    It 'clasifica cámaras usando la clase PnP' {
        $device = [pscustomobject]@{
            Class = 'Camera'
            InstanceId = 'USB\VID_0001&PID_0002'
            FriendlyName = 'USB Camera'
        }

        Get-PeripheralCategory -Device $device | Should -Be 'Cámaras'
    }
}

Describe 'Test-PeripheralCandidate' {
    It 'incluye periféricos USB aunque su clase no esté catalogada' {
        $device = [pscustomobject]@{
            Class = 'VendorSpecific'
            InstanceId = 'USB\VID_1234&PID_5678'
            FriendlyName = 'Custom USB Controller'
        }

        Test-PeripheralCandidate -Device $device | Should -BeTrue
    }

    It 'excluye controladores host USB internos' {
        $device = [pscustomobject]@{
            Class = 'USB'
            InstanceId = 'PCI\VEN_8086&DEV_0001'
            FriendlyName = 'USB xHCI Compliant Host Controller'
        }

        Test-PeripheralCandidate -Device $device | Should -BeFalse
    }

    It 'excluye dispositivos virtuales de escritorio remoto' {
        $device = [pscustomobject]@{
            Class = 'Mouse'
            InstanceId = 'TERMINPUT_BUS\UMB\1'
            FriendlyName = 'Remote Desktop Mouse Device'
        }

        Test-PeripheralCandidate -Device $device | Should -BeFalse
    }
}
