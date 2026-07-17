function Get-DeviceErrorInventory {
    $result = @()
    if (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue) {
        try {
            $result = @(
                Get-PnpDevice -ErrorAction Stop |
                    Where-Object { $_.Status -ne "OK" -and $_.Status -ne "Unknown" } |
                    ForEach-Object {
                        [ordered]@{
                            Class = Get-SafeString $_.Class
                            FriendlyName = Get-SafeString $_.FriendlyName
                            InstanceId = Get-SafeString $_.InstanceId
                            Status = Get-SafeString $_.Status
                            Problem = $_.Problem
                        }
                    }
            )
        } catch {
            Write-Warning ("No se pudieron consultar dispositivos PnP: {0}" -f $_.Exception.Message)
        }
    }
    return $result
}
