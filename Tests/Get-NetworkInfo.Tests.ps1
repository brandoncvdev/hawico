BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-NetworkInfo.ps1"
    if (-not (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        function Get-NetIPConfiguration { param() }
    }

    function New-FixtureNetIPConfiguration {
        param(
            [string[]]$IPv4Addresses = @('192.168.1.10'),
            [string[]]$IPv6Addresses = @('fe80::1'),
            [string[]]$IPv4Gateways = @('192.168.1.1'),
            [string[]]$IPv6Gateways = @('fe80::fffe'),
            [string[]]$DnsServers = @('8.8.8.8')
        )

        return [PSCustomObject]@{
            InterfaceAlias = 'Ethernet'
            InterfaceIndex = 5
            NetAdapter = [PSCustomObject]@{
                InterfaceDescription = 'Intel(R) Ethernet Connection'
                Status = 'Up'
                MacAddress = '00-11-22-33-44-55'
                LinkSpeed = '1 Gbps'
            }
            IPv4Address = @($IPv4Addresses | ForEach-Object { [PSCustomObject]@{ IPAddress = $_ } })
            IPv6Address = @($IPv6Addresses | ForEach-Object { [PSCustomObject]@{ IPAddress = $_ } })
            IPv4DefaultGateway = @($IPv4Gateways | ForEach-Object { [PSCustomObject]@{ NextHop = $_ } })
            IPv6DefaultGateway = @($IPv6Gateways | ForEach-Object { [PSCustomObject]@{ NextHop = $_ } })
            DNSServer = @([PSCustomObject]@{ ServerAddresses = $DnsServers })
        }
    }
}

Describe 'Get-NetworkInventory' {
    It 'returns a real array, not a bare scalar, for IPv6Addresses when exactly one IPv6 address is present' {
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -IPv6Addresses @('fe80::1') }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result.Count | Should -Be 1
        $result[0].IPv6Addresses.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Addresses.Count | Should -Be 1
        $result[0].IPv6Addresses[0] | Should -Be 'fe80::1'
    }

    It 'returns a real array, not a bare scalar, for IPv6Gateways when exactly one IPv6 gateway is present' {
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -IPv6Gateways @('fe80::fffe') }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result[0].IPv6Gateways.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Gateways.Count | Should -Be 1
        $result[0].IPv6Gateways[0] | Should -Be 'fe80::fffe'
    }

    It 'returns a real empty array (not null) for IPv6Addresses and IPv6Gateways when IPv6 is excluded' {
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration }

        $result = Get-NetworkInventory -IncludeIPv6 $false

        $result[0].IPv6Addresses.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Addresses.Count | Should -Be 0
        $result[0].IPv6Gateways.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Gateways.Count | Should -Be 0
    }

    It 'still reports every IPv6 address when there is more than one' {
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -IPv6Addresses @('fe80::1', 'fe80::2') }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result[0].IPv6Addresses.Count | Should -Be 2
    }
}
