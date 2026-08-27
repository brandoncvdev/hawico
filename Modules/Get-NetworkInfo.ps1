function Get-InventoryNetRouteNextHop {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads a route property defensively without changing system state.'
    )]
    param(
        [AllowNull()]$Route
    )

    # On older Windows (confirmed: real machines in the field), a NIC with no
    # default gateway configured — or an older NetTCPIP module build whose
    # MSFT_NetRoute-shaped object differs — can hand back a gateway entry
    # that either is $null or genuinely lacks a NextHop property at all.
    # Under this project's Set-StrictMode, accessing .NextHop directly on
    # that throws "property 'NextHop' cannot be found on this object" and,
    # since the whole adapter loop shares one try/catch, wipes out every
    # adapter's data for the run, not just the gateway field — confirmed by
    # a real user report ("no me da datos de la tarjeta de red").
    if ($null -eq $Route) {
        return $null
    }
    if ($Route.PSObject.Properties.Name -notcontains 'NextHop') {
        return $null
    }
    return Get-SafeString $Route.NextHop
}

function Test-InventoryNetworkAdapterIsVirtual {
    param(
        [AllowNull()][object]$Adapter
    )

    # Defense-in-depth virtual-adapter detector — real-world bug: a Hyper-V
    # host reports "vEthernet (Default Switch)" (Hyper-V's built-in NAT
    # virtual switch, present by default since Windows 10 1809+ when Hyper-V
    # is enabled) alongside the real physical NIC. That adapter's
    # HardwareInterface came back unreported ($null) on the reporting
    # machine, which the previous HardwareInterface-only filter treated as
    # "keep it" (a deliberate safety net for genuinely ambiguous hardware).
    # Checked in priority order, trusting an explicit provider value over a
    # guess, but guessing when the provider reports nothing at all:
    #   1. Virtual -eq $true            — Get-NetAdapter's own documented
    #      boolean for exactly this purpose (NetAdapter module, Windows 8 /
    #      Server 2012+); the most reliable signal, checked first.
    #   2. HardwareInterface -eq $false — the existing signal, still useful.
    #   3. Name/InterfaceDescription pattern fallback — ONLY consulted when
    #      both properties above are absent or unreported ($null), matching
    #      known virtual/software adapter markers (Hyper-V, other common
    #      hypervisors, VPN/tunnel adapters, loopback, Bluetooth PAN, etc.).
    # A pure function over a property bag on purpose, so it is independently
    # unit-testable with fixture objects — no real Get-NetAdapter call.
    if ($null -eq $Adapter) {
        return $false
    }

    if ($Adapter.PSObject.Properties.Name -contains 'Virtual' -and $null -ne $Adapter.Virtual) {
        return ($Adapter.Virtual -eq $true)
    }

    if ($Adapter.PSObject.Properties.Name -contains 'HardwareInterface' -and $null -ne $Adapter.HardwareInterface) {
        return ($Adapter.HardwareInterface -eq $false)
    }

    $name = "{0} {1}" -f $Adapter.Name, $Adapter.InterfaceDescription
    return ($name -match '(?i)hyper-v|vethernet|virtual\s*(ethernet|switch|adapter|network)|vmware|virtualbox|vbox|tap-windows|tap adapter|loopback|wan miniport|teredo|isatap|bluetooth')
}

function Get-NetworkAdapterType {
    param(
        [AllowNull()][object]$Adapter
    )

    # Checked BEFORE the Wi-Fi/Ethernet regexes: "Hyper-V Virtual Ethernet
    # Adapter" literally contains the word "Ethernet", so the Ethernet regex
    # alone would misclassify it — a distinct 'Virtual' label is needed so
    # downstream adapter-selection logic can tell physical and virtual
    # adapters apart even after this classification step.
    if (Test-InventoryNetworkAdapterIsVirtual -Adapter $Adapter) {
        return 'Virtual'
    }

    $name = "{0} {1}" -f $Adapter.Name, $Adapter.InterfaceDescription

    if ($name -match '(?i)wi-?fi|wireless|wlan|802\.11') {
        return 'Wi-Fi'
    }

    if ($name -match '(?i)ethernet|gigabit|gbe|lan|802\.3') {
        return 'Ethernet'
    }

    return 'Otro'
}

function Get-NetworkPropertyValues {
    param(
        [AllowNull()][object[]]$InputObject,
        [Parameter(Mandatory)][string]$PropertyName
    )

    $values = @()

    foreach ($item in @($InputObject)) {
        if ($null -eq $item) {
            continue
        }

        $property = $item.PSObject.Properties[$PropertyName]
        if ($null -eq $property) {
            continue
        }

        foreach ($value in @($property.Value)) {
            if ($null -eq $value) {
                continue
            }
            # This helper flattens both scalar leaf values (e.g. DNS server
            # strings) and intermediate CIM/PSCustomObject values (e.g. the
            # IPv4Address/IPv4DefaultGateway objects on a NetIPConfiguration
            # result). A blanket `$value.ToString()` emptiness check — as
            # originally written — silently drops every non-string object,
            # because PSCustomObject.ToString() returns "" by default; that
            # made every address/gateway/DNS lookup in Get-NetworkInventory
            # come back empty. Only apply the blank-string filter to actual
            # strings; let any other value through as long as it isn't null.
            if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
                continue
            }
            $values += $value
        }
    }

    return @($values)
}

function Get-NetworkInventory {
    param(
        [bool]$IncludeIPv6 = $true,
        [bool]$IncludeDisconnectedAdapters = $true
    )

    $result = @()

    if (-not (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue)) {
        Write-Warning "Get-NetAdapter no está disponible en este sistema."
        return $result
    }

    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop)

        # Se priorizan adaptadores físicos para evitar interfaces de VPN, Hyper-V,
        # contenedores y adaptadores virtuales, usando la detección multi-señal de
        # Test-InventoryNetworkAdapterIsVirtual (Virtual, luego HardwareInterface,
        # luego el patrón de nombre/descripción como último recurso).
        #
        # Defensivo: si ese filtro eliminaría TODOS los adaptadores reportados (p.ej.
        # una VM inventariada a propósito, donde el único adaptador es virtual), se
        # conserva la lista original sin filtrar en lugar de devolver cero adaptadores
        # y ocultar por completo la información de red — mismo espíritu que el
        # comentario original ("no perder hardware real" cuando el proveedor es
        # ambiguo), extendido para no perder TODA la red cuando es lo único que hay.
        $nonVirtualAdapters = @($adapters | Where-Object { -not (Test-InventoryNetworkAdapterIsVirtual -Adapter $_) })

        if ($nonVirtualAdapters.Count -gt 0) {
            $adapters = $nonVirtualAdapters
        }
        elseif ($adapters.Count -gt 0) {
            Write-Warning "Todos los adaptadores de red detectados parecen virtuales; se conservan para no ocultar la información de red."
        }

        if (-not $IncludeDisconnectedAdapters) {
            $adapters = @($adapters | Where-Object { $_.Status -eq 'Up' })
        }

        $ipConfigurations = @()
        if (Get-Command -Name Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
            try {
                $ipConfigurations = @(Get-NetIPConfiguration -All -ErrorAction Stop)
            }
            catch {
                try {
                    $ipConfigurations = @(Get-NetIPConfiguration -ErrorAction Stop)
                }
                catch {
                    Write-Warning ("No se pudo consultar la configuración IP: {0}" -f $_.Exception.Message)
                }
            }
        }

        $result = @(
            $adapters |
                Sort-Object @{ Expression = { if ($_.Status -eq 'Up') { 0 } else { 1 } } }, Name |
                ForEach-Object {
                    $adapter = $_
                    $cfg = @($ipConfigurations | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }) | Select-Object -First 1

                    $ipv4 = @()
                    $ipv6 = @()
                    $ipv4Gateways = @()
                    $ipv6Gateways = @()
                    $dnsServers = @()

                    if ($null -ne $cfg) {
                        $ipv4AddressObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'IPv4Address')
                        $ipv4 = @(Get-NetworkPropertyValues -InputObject $ipv4AddressObjects -PropertyName 'IPAddress')

                        if ($IncludeIPv6) {
                            $ipv6AddressObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'IPv6Address')
                            $ipv6GatewayObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'IPv6DefaultGateway')
                            $ipv6 = @(Get-NetworkPropertyValues -InputObject $ipv6AddressObjects -PropertyName 'IPAddress')
                            # NextHop is read through the dedicated defensive helper (not the
                            # generic property reader) so the real-world fix stays traceable:
                            # some gateway route objects genuinely lack a NextHop property.
                            $ipv6Gateways = @($ipv6GatewayObjects | ForEach-Object { Get-InventoryNetRouteNextHop -Route $_ } | Where-Object { $_ })
                        }

                        $ipv4GatewayObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'IPv4DefaultGateway')
                        $dnsServerObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'DNSServer')
                        $ipv4Gateways = @($ipv4GatewayObjects | ForEach-Object { Get-InventoryNetRouteNextHop -Route $_ } | Where-Object { $_ })
                        $dnsServers = @(Get-NetworkPropertyValues -InputObject $dnsServerObjects -PropertyName 'ServerAddresses')
                    }

                    [ordered]@{
                        InterfaceAlias = Get-SafeString $adapter.Name
                        InterfaceIndex = $adapter.ifIndex
                        AdapterType     = Get-NetworkAdapterType -Adapter $adapter
                        Description     = Get-SafeString $adapter.InterfaceDescription
                        Status          = Get-SafeString $adapter.Status
                        IsActive        = ($adapter.Status -eq 'Up')
                        MediaState      = Get-SafeString $adapter.MediaConnectionState
                        MACAddress      = Get-SafeString $adapter.MacAddress
                        LinkSpeed       = Get-SafeString $adapter.LinkSpeed
                        DriverName      = Get-SafeString $adapter.DriverDescription
                        DriverVersion   = Get-SafeString $adapter.DriverVersion
                        IPv4Addresses   = $ipv4
                        IPv6Addresses   = $ipv6
                        IPv4Gateways    = $ipv4Gateways
                        IPv6Gateways    = $ipv6Gateways
                        DNSServers      = $dnsServers
                    }
                }
        )
    }
    catch {
        Write-Warning ("No se pudo recopilar la información de red: {0}" -f $_.Exception.Message)
    }

    # Same output-stream-boundary hazard fixed elsewhere in this project
    # (see Get-GraphicsInventory): a bare `return $result` collapses to a
    # scalar when the adapter list has exactly one element — the common
    # case on most machines (one NIC, or only Wi-Fi enabled). The comma
    # operator guards the array across the return's output-stream boundary.
    return ,$result
}
