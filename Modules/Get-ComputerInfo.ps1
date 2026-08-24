function Get-ComputerCimProperty {
    # Same shape as Get-StorageProperty (Modules/Get-StorageHealth.ps1): checks
    # for $null first, via a comparison rather than a property access, so it
    # never trips Set-StrictMode. Needed here because $computerSystem/$bios/
    # etc. are legitimately $null when their CIM class is unavailable, and
    # under this project's Set-StrictMode -Version Latest, even `$null.Foo` -
    # not just a missing property on a real object - throws "The property
    # 'Foo' cannot be found on this object" (confirmed in the field:
    # 196JURIDICO, 2026-08-19, every base CIM class unavailable; every direct
    # `$computerSystem.Manufacturer`-style access below used to crash the
    # whole hardware inventory on that case).
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-ComputerInventory {
    # Get-CimDataSafe already comma-guards its return (`return ,@(...)`).
    # Plain `(...)` grouping - not `@(...)` - around the call lets that guard
    # resolve correctly across the pipe into Select-Object: `@(...)` would
    # re-nest an already-guarded multi-item result and make "-First 1" return
    # every item mashed together instead of just the first one.
    $computerSystem = (Get-CimDataSafe -ClassName "Win32_ComputerSystem") | Select-Object -First 1
    $computerProduct = (Get-CimDataSafe -ClassName "Win32_ComputerSystemProduct") | Select-Object -First 1
    $operatingSystem = (Get-CimDataSafe -ClassName "Win32_OperatingSystem") | Select-Object -First 1
    $bios = (Get-CimDataSafe -ClassName "Win32_BIOS") | Select-Object -First 1
    $baseBoard = (Get-CimDataSafe -ClassName "Win32_BaseBoard") | Select-Object -First 1

    return [ordered]@{
        Computer = [ordered]@{
            Hostname          = $env:COMPUTERNAME
            Manufacturer      = Get-SafeString (Get-ComputerCimProperty $computerSystem 'Manufacturer')
            Model             = Get-SafeString (Get-ComputerCimProperty $computerSystem 'Model')
            SystemType        = Get-SafeString (Get-ComputerCimProperty $computerSystem 'SystemType')
            UUID              = Get-SafeString (Get-ComputerCimProperty $computerProduct 'UUID')
            IdentifyingNumber = Get-SafeString (Get-ComputerCimProperty $computerProduct 'IdentifyingNumber')
            Domain            = Get-SafeString (Get-ComputerCimProperty $computerSystem 'Domain')
            PartOfDomain      = Get-ComputerCimProperty $computerSystem 'PartOfDomain'
            TotalMemoryGB     = Convert-BytesToGB (Get-ComputerCimProperty $computerSystem 'TotalPhysicalMemory')
        }
        OperatingSystem = [ordered]@{
            Caption          = Get-SafeString (Get-ComputerCimProperty $operatingSystem 'Caption')
            Version          = Get-SafeString (Get-ComputerCimProperty $operatingSystem 'Version')
            BuildNumber      = Get-SafeString (Get-ComputerCimProperty $operatingSystem 'BuildNumber')
            Architecture     = Get-SafeString (Get-ComputerCimProperty $operatingSystem 'OSArchitecture')
            InstallDate      = Convert-CimDate (Get-ComputerCimProperty $operatingSystem 'InstallDate')
            LastBootUpTime   = Convert-CimDate (Get-ComputerCimProperty $operatingSystem 'LastBootUpTime')
        }
        BIOS = [ordered]@{
            Manufacturer = Get-SafeString (Get-ComputerCimProperty $bios 'Manufacturer')
            Version      = Get-SafeString (Get-ComputerCimProperty $bios 'SMBIOSBIOSVersion')
            SerialNumber = Get-SafeString (Get-ComputerCimProperty $bios 'SerialNumber')
            ReleaseDate  = Convert-CimDate (Get-ComputerCimProperty $bios 'ReleaseDate')
        }
        Motherboard = [ordered]@{
            Manufacturer = Get-SafeString (Get-ComputerCimProperty $baseBoard 'Manufacturer')
            Product      = Get-SafeString (Get-ComputerCimProperty $baseBoard 'Product')
            Version      = Get-SafeString (Get-ComputerCimProperty $baseBoard 'Version')
            SerialNumber = Get-SafeString (Get-ComputerCimProperty $baseBoard 'SerialNumber')
        }
    }
}
