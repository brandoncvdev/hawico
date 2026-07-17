function Get-ComputerInventory {
    $computerSystem = @(Get-CimDataSafe -ClassName "Win32_ComputerSystem") | Select-Object -First 1
    $computerProduct = @(Get-CimDataSafe -ClassName "Win32_ComputerSystemProduct") | Select-Object -First 1
    $operatingSystem = @(Get-CimDataSafe -ClassName "Win32_OperatingSystem") | Select-Object -First 1
    $bios = @(Get-CimDataSafe -ClassName "Win32_BIOS") | Select-Object -First 1
    $baseBoard = @(Get-CimDataSafe -ClassName "Win32_BaseBoard") | Select-Object -First 1

    return [ordered]@{
        Computer = [ordered]@{
            Hostname          = $env:COMPUTERNAME
            Manufacturer      = Get-SafeString $computerSystem.Manufacturer
            Model             = Get-SafeString $computerSystem.Model
            SystemType        = Get-SafeString $computerSystem.SystemType
            UUID              = Get-SafeString $computerProduct.UUID
            IdentifyingNumber = Get-SafeString $computerProduct.IdentifyingNumber
            Domain            = Get-SafeString $computerSystem.Domain
            PartOfDomain      = $computerSystem.PartOfDomain
            TotalMemoryGB     = Convert-BytesToGB $computerSystem.TotalPhysicalMemory
        }
        OperatingSystem = [ordered]@{
            Caption          = Get-SafeString $operatingSystem.Caption
            Version          = Get-SafeString $operatingSystem.Version
            BuildNumber      = Get-SafeString $operatingSystem.BuildNumber
            Architecture     = Get-SafeString $operatingSystem.OSArchitecture
            InstallDate      = Convert-CimDate $operatingSystem.InstallDate
            LastBootUpTime   = Convert-CimDate $operatingSystem.LastBootUpTime
        }
        BIOS = [ordered]@{
            Manufacturer = Get-SafeString $bios.Manufacturer
            Version      = Get-SafeString $bios.SMBIOSBIOSVersion
            SerialNumber = Get-SafeString $bios.SerialNumber
            ReleaseDate  = Convert-CimDate $bios.ReleaseDate
        }
        Motherboard = [ordered]@{
            Manufacturer = Get-SafeString $baseBoard.Manufacturer
            Product      = Get-SafeString $baseBoard.Product
            Version      = Get-SafeString $baseBoard.Version
            SerialNumber = Get-SafeString $baseBoard.SerialNumber
        }
    }
}
