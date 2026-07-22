BeforeAll {
    . "$PSScriptRoot/../Modules/Get-NetworkInfo.ps1"
}

Describe 'Get-NetworkPropertyValues' {
    It 'ignora objetos que no exponen la propiedad solicitada' {
        $gatewayWithoutNextHop = [pscustomobject]@{ InterfaceIndex = 7 }

        $result = @(Get-NetworkPropertyValues `
            -InputObject $gatewayWithoutNextHop `
            -PropertyName 'NextHop')

        @($result).Count | Should -Be 0
    }

    It 'devuelve y aplana los valores disponibles' {
        $dns = [pscustomobject]@{
            ServerAddresses = @('1.1.1.1', '8.8.8.8')
        }

        $result = @(Get-NetworkPropertyValues `
            -InputObject $dns `
            -PropertyName 'ServerAddresses')

        $result | Should -HaveCount 2
        $result[0] | Should -Be '1.1.1.1'
        $result[1] | Should -Be '8.8.8.8'
    }
}
