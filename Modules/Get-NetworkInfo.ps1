function Get-NetworkInventory {
    param(
        [bool]$IncludeIPv6 = $true,
        [bool]$IncludeDisconnectedAdapters = $false
    )

    $result = @()

    if (Get-Command -Name Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
        try {
            $configs = Get-NetIPConfiguration -ErrorAction Stop

            if (-not $IncludeDisconnectedAdapters) {
                $configs = $configs | Where-Object {
                    $null -ne $_.NetAdapter -and $_.NetAdapter.Status -eq "Up"
                }
            }

            $result = @(
                $configs | Where-Object { $null -ne $_.NetAdapter } | ForEach-Object {
                    $cfg = $_
                    $ipv4 = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress } | Where-Object { $_ })
                    $ipv6 = if ($IncludeIPv6) {
                        @($cfg.IPv6Address | ForEach-Object { $_.IPAddress } | Where-Object { $_ })
                    } else { @() }

                    [ordered]@{
                        InterfaceAlias = Get-SafeString $cfg.InterfaceAlias
                        InterfaceIndex = $cfg.InterfaceIndex
                        Description    = Get-SafeString $cfg.NetAdapter.InterfaceDescription
                        Status         = Get-SafeString $cfg.NetAdapter.Status
                        MACAddress     = Get-SafeString $cfg.NetAdapter.MacAddress
                        LinkSpeed      = Get-SafeString $cfg.NetAdapter.LinkSpeed
                        IPv4Addresses  = $ipv4
                        IPv6Addresses  = $ipv6
                        IPv4Gateways   = @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop } | Where-Object { $_ })
                        IPv6Gateways   = if ($IncludeIPv6) {
                            @($cfg.IPv6DefaultGateway | ForEach-Object { $_.NextHop } | Where-Object { $_ })
                        } else { @() }
                        DNSServers     = @($cfg.DNSServer | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
                    }
                }
            )
        }
        catch {
            Write-Warning ("No se pudo consultar la red con Get-NetIPConfiguration: {0}" -f $_.Exception.Message)
        }
    }

    return $result
}
