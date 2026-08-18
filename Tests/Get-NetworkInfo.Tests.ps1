BeforeAll {
    # Collector_Hardware_Inventory.ps1 runs under Set-StrictMode -Version
    # Latest (its own line 15) — matched here so a property-access bug like
    # the real one reported in the field (NextHop missing on some adapters'
    # gateway objects) actually reproduces in this test file instead of
    # silently returning $null the way it would under the Pester default.
    Set-StrictMode -Version Latest
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-NetworkInfo.ps1"

    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
        function Get-NetAdapter { param() }
    }
    if (-not (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        function Get-NetIPConfiguration { param() }
    }

    function New-FixtureNetAdapter {
        param(
            [string]$Name = 'Ethernet',
            [int]$IfIndex = 5,
            [string]$InterfaceDescription = 'Intel(R) Ethernet Connection',
            [string]$Status = 'Up',
            [string]$MacAddress = '00-11-22-33-44-55',
            [string]$LinkSpeed = '1 Gbps',
            [AllowNull()]$HardwareInterface = $true,
            [string]$MediaConnectionState = 'Connected',
            [string]$DriverDescription = 'Intel(R) Ethernet Driver',
            [string]$DriverVersion = '12.19.1.3'
        )

        return [PSCustomObject]@{
            Name                 = $Name
            ifIndex              = $IfIndex
            InterfaceDescription = $InterfaceDescription
            Status               = $Status
            MacAddress           = $MacAddress
            LinkSpeed            = $LinkSpeed
            HardwareInterface    = $HardwareInterface
            MediaConnectionState = $MediaConnectionState
            DriverDescription    = $DriverDescription
            DriverVersion        = $DriverVersion
        }
    }

    function New-FixtureNetIPConfiguration {
        param(
            [int]$InterfaceIndex = 5,
            [string[]]$IPv4Addresses = @('192.168.1.10'),
            [string[]]$IPv6Addresses = @('fe80::1'),
            [string[]]$IPv4Gateways = @('192.168.1.1'),
            [string[]]$IPv6Gateways = @('fe80::fffe'),
            [string[]]$DnsServers = @('8.8.8.8')
        )

        return [PSCustomObject]@{
            InterfaceIndex     = $InterfaceIndex
            IPv4Address        = @($IPv4Addresses | ForEach-Object { [PSCustomObject]@{ IPAddress = $_ } })
            IPv6Address        = @($IPv6Addresses | ForEach-Object { [PSCustomObject]@{ IPAddress = $_ } })
            IPv4DefaultGateway = @($IPv4Gateways | ForEach-Object { [PSCustomObject]@{ NextHop = $_ } })
            IPv6DefaultGateway = @($IPv6Gateways | ForEach-Object { [PSCustomObject]@{ NextHop = $_ } })
            DNSServer          = @([PSCustomObject]@{ ServerAddresses = $DnsServers })
        }
    }
}

Describe 'Get-NetworkInventory' {
    It 'returns a real array, not a bare scalar, for IPv6Addresses when exactly one IPv6 address is present' {
        Mock Get-NetAdapter { New-FixtureNetAdapter }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -IPv6Addresses @('fe80::1') }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].IPv6Addresses.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Addresses.Count | Should -Be 1
        $result[0].IPv6Addresses[0] | Should -Be 'fe80::1'
    }

    It 'returns a real array, not a bare scalar, for the adapter list itself when exactly one adapter is present' {
        # Same output-stream-boundary hazard as Get-GraphicsInventory (a
        # single-element array collapses to a scalar through `return`
        # unless comma-guarded) — this is the common single-NIC case.
        Mock Get-NetAdapter { New-FixtureNetAdapter }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'returns a real array, not a bare scalar, for IPv6Gateways when exactly one IPv6 gateway is present' {
        Mock Get-NetAdapter { New-FixtureNetAdapter }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -IPv6Gateways @('fe80::fffe') }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result[0].IPv6Gateways.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Gateways.Count | Should -Be 1
        $result[0].IPv6Gateways[0] | Should -Be 'fe80::fffe'
    }

    It 'returns a real empty array (not null) for IPv6Addresses and IPv6Gateways when IPv6 is excluded' {
        Mock Get-NetAdapter { New-FixtureNetAdapter }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration }

        $result = Get-NetworkInventory -IncludeIPv6 $false

        $result[0].IPv6Addresses.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Addresses.Count | Should -Be 0
        $result[0].IPv6Gateways.GetType().IsArray | Should -BeTrue
        $result[0].IPv6Gateways.Count | Should -Be 0
    }

    It 'still reports every IPv6 address when there is more than one' {
        Mock Get-NetAdapter { New-FixtureNetAdapter }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -IPv6Addresses @('fe80::1', 'fe80::2') }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result[0].IPv6Addresses.Count | Should -Be 2
    }

    It 'still reports every other field when a NIC has no default gateway ($null IPv4DefaultGateway)' {
        Mock Get-NetAdapter { New-FixtureNetAdapter }
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
        Mock Get-NetAdapter { New-FixtureNetAdapter }
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

    It 'reports AdapterType and the dashboard fields added for network detection' {
        Mock Get-NetAdapter { New-FixtureNetAdapter -Name 'Wi-Fi' -InterfaceDescription 'Intel(R) Wireless-AC 9560' }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result[0].AdapterType | Should -Be 'Wi-Fi'
        $result[0].IsActive | Should -BeTrue
        $result[0].MediaState | Should -Be 'Connected'
        $result[0].DriverName | Should -Be 'Intel(R) Ethernet Driver'
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

    It 'preserva objetos (no solo strings) al extraer una propiedad anidada' {
        # Regression: PSCustomObject.ToString() returns "" by default, so a
        # blanket "-not [string]::IsNullOrWhiteSpace($value.ToString())"
        # filter used to silently drop every nested address/gateway object,
        # making Get-NetworkInventory always report empty IPv4/IPv6
        # addresses, gateways and DNS servers. Only string values should be
        # blank-filtered; other objects must pass through untouched.
        $cfg = [pscustomobject]@{
            IPv4Address = @([pscustomobject]@{ IPAddress = '192.168.1.10' })
        }

        $result = @(Get-NetworkPropertyValues `
            -InputObject $cfg `
            -PropertyName 'IPv4Address')

        $result | Should -HaveCount 1
        $result[0].IPAddress | Should -Be '192.168.1.10'
    }
}
