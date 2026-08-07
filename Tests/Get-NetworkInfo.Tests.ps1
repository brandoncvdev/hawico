BeforeAll {
    # Collector_Hardware_Inventory.ps1 runs under Set-StrictMode -Version
    # Latest (its own line 15) — matched here so a property-access bug like
    # the real one reported in the field (NextHop missing on some adapters'
    # gateway objects) actually reproduces in this test file instead of
    # silently returning $null the way it would under the Pester default.
    Set-StrictMode -Version Latest
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

    It 'still reports every other field when a NIC has no default gateway ($null IPv4DefaultGateway)' {
        $fixture = New-FixtureNetIPConfiguration
        $fixture.IPv4DefaultGateway = $null
        Mock Get-NetIPConfiguration { $fixture }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result.Count | Should -Be 1
        $result[0].MACAddress | Should -Be '00-11-22-33-44-55'
        $result[0].IPv4Addresses.Count | Should -Be 1
        $result[0].IPv4Gateways.GetType().IsArray | Should -BeTrue
        $result[0].IPv4Gateways.Count | Should -Be 0
    }

    It 'still reports every other field when the gateway route object has no NextHop property at all (older NetTCPIP builds)' {
        # Real-world report: on older Windows, Get-NetIPConfiguration can hand
        # back a gateway entry that genuinely lacks NextHop — under strict
        # mode a direct $_.NextHop access throws "property cannot be found",
        # and since the whole adapter was previously built in one expression,
        # that used to wipe out every adapter's data for the entire run.
        $fixture = New-FixtureNetIPConfiguration
        $fixture.IPv4DefaultGateway = @([PSCustomObject]@{ DestinationPrefix = '0.0.0.0/0' })
        Mock Get-NetIPConfiguration { $fixture }

        { Get-NetworkInventory -IncludeIPv6 $true } | Should -Not -Throw

        $result = Get-NetworkInventory -IncludeIPv6 $true
        $result.Count | Should -Be 1
        $result[0].MACAddress | Should -Be '00-11-22-33-44-55'
        $result[0].IPv4Addresses.Count | Should -Be 1
        $result[0].IPv4Gateways.Count | Should -Be 0
    }
}

Describe 'Get-InventoryNetRouteNextHop' {
    It 'returns $null for a $null route' {
        Get-InventoryNetRouteNextHop -Route $null | Should -BeNullOrEmpty
    }

    It 'returns $null when the route object has no NextHop property' {
        $route = [PSCustomObject]@{ DestinationPrefix = '0.0.0.0/0' }
        Get-InventoryNetRouteNextHop -Route $route | Should -BeNullOrEmpty
    }

    It 'returns the NextHop value when present' {
        $route = [PSCustomObject]@{ NextHop = '192.168.1.1' }
        Get-InventoryNetRouteNextHop -Route $route | Should -Be '192.168.1.1'
    }
}
