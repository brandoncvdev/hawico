function Get-ExtendedDiagnosticProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$DefaultValue = $null
    )
    if ($null -eq $Object) { return $DefaultValue }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $DefaultValue
}

function ConvertTo-ProcessDiagnostic {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Samples,
        [ValidateRange(1, 50)][int]$TopCount = 10
    )
    $items = @($Samples | ForEach-Object {
        $processId = [int](Get-ExtendedDiagnosticProperty -Object $_ -Name 'IDProcess' -DefaultValue 0)
        $name = [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Name')
        if ($processId -gt 0 -and $name -notin @('Idle', '_Total')) {
            [pscustomobject][ordered]@{
                Name = $name
                ProcessId = $processId
                CpuUsagePercent = [math]::Round([math]::Min(100, [math]::Max(0, [double](Get-ExtendedDiagnosticProperty -Object $_ -Name 'PercentProcessorTime' -DefaultValue 0))), 2)
                WorkingSetMB = [math]::Round([double](Get-ExtendedDiagnosticProperty -Object $_ -Name 'WorkingSetPrivate' -DefaultValue 0) / 1MB, 2)
                IoBytesPerSecond = [long](Get-ExtendedDiagnosticProperty -Object $_ -Name 'IODataBytesPersec' -DefaultValue 0)
            }
        }
    })
    return [ordered]@{
        Status = 'Collected'
        Source = 'Win32_PerfFormattedData_PerfProc_Process'
        CapturedCount = $items.Count
        TopByCpu = @($items | Sort-Object -Property @{ Expression = 'CpuUsagePercent'; Descending = $true }, @{ Expression = 'WorkingSetMB'; Descending = $true } | Select-Object -First $TopCount)
        TopByMemory = @($items | Sort-Object -Property @{ Expression = 'WorkingSetMB'; Descending = $true }, @{ Expression = 'CpuUsagePercent'; Descending = $true } | Select-Object -First $TopCount)
    }
}

function Get-ProcessDiagnostic {
    param([ValidateRange(1, 50)][int]$TopCount = 10)
    try {
        $samples = @(Get-CimInstance -Namespace 'root/cimv2' -ClassName 'Win32_PerfFormattedData_PerfProc_Process' -ErrorAction Stop)
        return ConvertTo-ProcessDiagnostic -Samples $samples -TopCount $TopCount
    }
    catch {
        return [ordered]@{
            Status = 'Failed'
            Source = 'Win32_PerfFormattedData_PerfProc_Process'
            CapturedCount = 0
            TopByCpu = @()
            TopByMemory = @()
            ErrorCode = 'PROCESS-DIAGNOSTICS-FAILED'
            ErrorMessage = 'Process performance data could not be collected.'
        }
    }
}

function ConvertTo-StartupDiagnostic {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items)
    $normalized = @($Items | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Name'))
    } | ForEach-Object {
        $location = [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Location')
        $user = [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'User')
        $scope = if ($location -match '(?i)^HKLM') { 'Machine' }
            elseif ($location -match '(?i)^HKCU|^HKU\\' -or ($user -and $user -notmatch '(?i)SYSTEM|All Users|Public')) { 'User' }
            else { 'Machine' }
        $locationType = if ($location -match '(?i)^HKLM') { 'RegistryMachine' }
            elseif ($location -match '(?i)^HKCU|^HKU\\') { 'RegistryUser' }
            elseif ($location -match '(?i)Startup') { 'StartupFolder' }
            else { 'Other' }
        [pscustomobject][ordered]@{
            Name = [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Name')
            Location = $locationType
            Scope = $scope
            Enabled = $null
        }
    } | Sort-Object Name, Location)
    return [ordered]@{
        Status = 'Collected'
        Source = 'Win32_StartupCommand'
        Items = $normalized
    }
}

function Get-StartupDiagnostic {
    try {
        $items = @(Get-CimInstance -Namespace 'root/cimv2' -ClassName 'Win32_StartupCommand' -ErrorAction Stop)
        return ConvertTo-StartupDiagnostic -Items $items
    }
    catch {
        return [ordered]@{
            Status = 'Failed'
            Source = 'Win32_StartupCommand'
            Items = @()
            ErrorCode = 'STARTUP-DIAGNOSTICS-FAILED'
            ErrorMessage = 'Startup program data could not be collected.'
        }
    }
}

function ConvertTo-InstalledSoftwareDiagnostic {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items)
    $visible = @($Items | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'DisplayName')) -and
        [int](Get-ExtendedDiagnosticProperty -Object $_ -Name 'SystemComponent' -DefaultValue 0) -ne 1
    })
    $normalized = @($visible | Group-Object {
        @(
            [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'DisplayName'),
            [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'DisplayVersion'),
            [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Publisher')
        ) -join '|'
    } | ForEach-Object {
        $group = @($_.Group)
        $architectures = @($group | ForEach-Object { [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Architecture') } | Where-Object { $_ } | Select-Object -Unique)
        $scopes = @($group | ForEach-Object { [string](Get-ExtendedDiagnosticProperty -Object $_ -Name 'Scope') } | Where-Object { $_ } | Select-Object -Unique)
        [pscustomobject][ordered]@{
            Name = [string](Get-ExtendedDiagnosticProperty -Object $group[0] -Name 'DisplayName')
            Version = Get-ExtendedDiagnosticProperty -Object $group[0] -Name 'DisplayVersion'
            Publisher = Get-ExtendedDiagnosticProperty -Object $group[0] -Name 'Publisher'
            Scope = if ($scopes.Count -gt 1) { 'Mixed' } elseif ($scopes.Count -eq 1) { $scopes[0] } else { 'Unknown' }
            Architecture = if ($architectures.Count -gt 1) { 'Mixed' } elseif ($architectures.Count -eq 1) { $architectures[0] } else { 'Unknown' }
        }
    } | Sort-Object Name, Version)
    return [ordered]@{
        Status = 'Collected'
        Source = 'RegistryUninstallKeys'
        Items = $normalized
    }
}

function Get-InstalledSoftwareDiagnostic {
    $definitions = @(
        [pscustomobject]@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Machine'; Architecture = 'x64' }
        [pscustomobject]@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Machine'; Architecture = 'x86' }
        [pscustomobject]@{ Path = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'User'; Architecture = 'Unknown' }
    )
    $items = @()
    $failedSources = 0
    foreach ($definition in $definitions) {
        try {
            if (-not (Test-Path -Path $definition.Path)) { continue }
            $items += @(Get-ItemProperty -Path (Join-Path $definition.Path '*') -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    DisplayName = $_.DisplayName
                    DisplayVersion = $_.DisplayVersion
                    Publisher = $_.Publisher
                    SystemComponent = $_.SystemComponent
                    Scope = $definition.Scope
                    Architecture = $definition.Architecture
                }
            })
        }
        catch {
            $failedSources++
        }
    }
    $result = ConvertTo-InstalledSoftwareDiagnostic -Items $items
    if ($failedSources -eq 0) { return $result }
    $result.Status = if ($items.Count -gt 0) { 'Partial' } else { 'Failed' }
    $result.ErrorCode = if ($result.Status -eq 'Partial') { 'SOFTWARE-DIAGNOSTICS-PARTIAL' } else { 'SOFTWARE-DIAGNOSTICS-FAILED' }
    $result.ErrorMessage = 'One or more installed software registry sources could not be queried.'
    return $result
}
