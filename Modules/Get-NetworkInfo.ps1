function Get-NetworkAdapterType {
    param(
        [AllowNull()][object]$Adapter
    )

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
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace($value.ToString())) {
                $values += $value
            }
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
        # contenedores y adaptadores virtuales. Si el proveedor no reporta HardwareInterface,
        # se conserva el adaptador para no perder hardware real.
        $adapters = @(
            $adapters | Where-Object {
                $_.HardwareInterface -eq $true -or $null -eq $_.HardwareInterface
            }
        )

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
                            $ipv6Gateways = @(Get-NetworkPropertyValues -InputObject $ipv6GatewayObjects -PropertyName 'NextHop')
                        }

                        $ipv4GatewayObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'IPv4DefaultGateway')
                        $dnsServerObjects = @(Get-NetworkPropertyValues -InputObject $cfg -PropertyName 'DNSServer')
                        $ipv4Gateways = @(Get-NetworkPropertyValues -InputObject $ipv4GatewayObjects -PropertyName 'NextHop')
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

    return $result
}
