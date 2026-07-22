function Test-HealthAdministrator {
    if ($PSVersionTable.Platform -ne "Win32NT" -and $env:OS -ne "Windows_NT") {
        return $false
    }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-HealthCapability {
    $isAdministrator = Test-HealthAdministrator
    $definitions = @(
        [pscustomobject]@{ Name = "Cim"; Command = "Get-CimInstance" }
        [pscustomobject]@{ Name = "PerformanceCounters"; Command = "Get-Counter" }
        [pscustomobject]@{ Name = "EventLog"; Command = "Get-WinEvent" }
        [pscustomobject]@{ Name = "PhysicalDisk"; Command = "Get-PhysicalDisk" }
    )

    $items = @(
        [pscustomobject][ordered]@{
            Name = "Administrator"
            Status = if ($isAdministrator) { "Available" } else { "Denied" }
            Command = $null
        }
    )

    foreach ($definition in $definitions) {
        $command = Get-Command -Name $definition.Command -ErrorAction SilentlyContinue
        $items += [pscustomobject][ordered]@{
            Name = $definition.Name
            Status = if ($null -ne $command) { "Available" } else { "NotSupported" }
            Command = $definition.Command
        }
    }

    return [ordered]@{
        IsAdministrator = $isAdministrator
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        Platform = if ($null -ne $PSVersionTable.Platform) { $PSVersionTable.Platform } else { "Win32NT" }
        Items = $items
    }
}
