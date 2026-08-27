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
            [AllowNull()]$Virtual = $null,
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
            Virtual              = $Virtual
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

Describe 'Get-NetworkInventory virtual adapter filtering (real-world Hyper-V vEthernet bug)' {
    # Real reported bug: a machine with Hyper-V enabled has both
    # "vEthernet (Default Switch)" (Hyper-V's built-in NAT virtual switch,
    # Status = 'Up', IP address present) and a real physical NIC. The
    # consolidated Excel ended up showing the virtual adapter's IP/MAC. On
    # the reporting machine, HardwareInterface came back unreported ($null)
    # for the virtual adapter, so the old HardwareInterface-only filter kept
    # it — this is reproduced here with HardwareInterface = $null, exactly
    # matching the traced root cause.
    It 'excludes the Hyper-V vEthernet adapter when a physical adapter is also present, regardless of array order' {
        foreach ($order in @('virtual-first', 'virtual-last')) {
            $virtualAdapter = New-FixtureNetAdapter -Name 'vEthernet (Default Switch)' `
                -InterfaceDescription 'Hyper-V Virtual Ethernet Adapter' -IfIndex 20 -Status 'Up' `
                -MacAddress '00-15-5D-01-02-03' -HardwareInterface $null
            $physicalAdapter = New-FixtureNetAdapter -Name 'Ethernet' `
                -InterfaceDescription 'Intel(R) Ethernet Connection I219-V' -IfIndex 5 -Status 'Up' `
                -MacAddress '00-11-22-33-44-55'

            $adapters = if ($order -eq 'virtual-first') { @($virtualAdapter, $physicalAdapter) } else { @($physicalAdapter, $virtualAdapter) }

            Mock Get-NetAdapter { $adapters }
            Mock Get-NetIPConfiguration {
                @(
                    [PSCustomObject]@{
                        InterfaceIndex     = 20
                        IPv4Address        = @([PSCustomObject]@{ IPAddress = '172.28.240.1' })
                        IPv6Address        = @()
                        IPv4DefaultGateway = @()
                        IPv6DefaultGateway = @()
                        DNSServer          = @()
                    }
                    [PSCustomObject]@{
                        InterfaceIndex     = 5
                        IPv4Address        = @([PSCustomObject]@{ IPAddress = '192.168.1.50' })
                        IPv6Address        = @()
                        IPv4DefaultGateway = @()
                        IPv6DefaultGateway = @()
                        DNSServer          = @()
                    }
                )
            }

            $result = Get-NetworkInventory -IncludeIPv6 $true

            $result.Count | Should -Be 1 -Because "order was $order"
            $result[0].InterfaceAlias | Should -Be 'Ethernet' -Because "order was $order"
        }
    }

    It 'keeps every adapter instead of returning zero results when the virtual filter would eliminate all of them (e.g. a VM being inventoried on purpose)' {
        Mock Get-NetAdapter {
            New-FixtureNetAdapter -Name 'vEthernet (Default Switch)' `
                -InterfaceDescription 'Hyper-V Virtual Ethernet Adapter' -IfIndex 20 -HardwareInterface $null
        }
        Mock Get-NetIPConfiguration { New-FixtureNetIPConfiguration -InterfaceIndex 20 }

        $result = Get-NetworkInventory -IncludeIPv6 $true

        $result.Count | Should -Be 1
        $result[0].InterfaceAlias | Should -Be 'vEthernet (Default Switch)'
    }
}

Describe 'Get-NetworkAdapterType' {
    It 'classifies a real physical Ethernet adapter as Ethernet' {
        $adapter = New-FixtureNetAdapter -Name 'Ethernet' -InterfaceDescription 'Intel(R) Ethernet Connection I219-V'
        Get-NetworkAdapterType -Adapter $adapter | Should -Be 'Ethernet'
    }

    It 'classifies a real Wi-Fi adapter as Wi-Fi' {
        $adapter = New-FixtureNetAdapter -Name 'Wi-Fi' -InterfaceDescription 'Intel(R) Wireless-AC 9560'
        Get-NetworkAdapterType -Adapter $adapter | Should -Be 'Wi-Fi'
    }

    It 'classifies the Hyper-V vEthernet adapter as Virtual instead of falling through to the Ethernet regex' {
        # Root cause: "Hyper-V Virtual Ethernet Adapter" literally contains
        # the word "Ethernet", so the Ethernet regex alone would misclassify
        # it. Test-InventoryNetworkAdapterIsVirtual must be checked first.
        $adapter = New-FixtureNetAdapter -Name 'vEthernet (Default Switch)' `
            -InterfaceDescription 'Hyper-V Virtual Ethernet Adapter' -HardwareInterface $null
        Get-NetworkAdapterType -Adapter $adapter | Should -Be 'Virtual'
    }
}

Describe 'Test-InventoryNetworkAdapterIsVirtual' {
    It 'returns $true when Virtual is explicitly $true (primary signal), even if the name looks unremarkable' {
        $adapter = [PSCustomObject]@{
            Name                 = 'Ethernet 3'
            InterfaceDescription = 'Some Adapter'
            Virtual              = $true
            HardwareInterface    = $null
        }

        Test-InventoryNetworkAdapterIsVirtual -Adapter $adapter | Should -BeTrue
    }

    It 'returns $true when HardwareInterface is explicitly $false and Virtual is unreported (secondary signal)' {
        $adapter = [PSCustomObject]@{
            Name                 = 'Ethernet 4'
            InterfaceDescription = 'Some Adapter'
            HardwareInterface    = $false
        }

        Test-InventoryNetworkAdapterIsVirtual -Adapter $adapter | Should -BeTrue
    }

    It 'falls back to the name/description pattern when both Virtual and HardwareInterface are absent, and matches known virtual markers' {
        $adapter = [PSCustomObject]@{
            Name                 = 'vEthernet (Default Switch)'
            InterfaceDescription = 'Hyper-V Virtual Ethernet Adapter'
        }

        Test-InventoryNetworkAdapterIsVirtual -Adapter $adapter | Should -BeTrue
    }

    It 'returns $false for a real adapter with an unusual name when both Virtual and HardwareInterface are absent (does not over-trigger)' {
        $adapter = [PSCustomObject]@{
            Name                 = 'NIC-Principal-07'
            InterfaceDescription = 'Acme Corp Custom Network Controller'
        }

        Test-InventoryNetworkAdapterIsVirtual -Adapter $adapter | Should -BeFalse
    }

    It 'trusts an explicit HardwareInterface $true over the name/description guess (explicit provider signal wins)' {
        $adapter = [PSCustomObject]@{
            Name                 = 'vEthernet (Custom NAT)'
            InterfaceDescription = 'Hyper-V Virtual Ethernet Adapter'
            HardwareInterface    = $true
        }

        Test-InventoryNetworkAdapterIsVirtual -Adapter $adapter | Should -BeFalse
    }

    It 'returns $false for a $null adapter' {
        Test-InventoryNetworkAdapterIsVirtual -Adapter $null | Should -BeFalse
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
