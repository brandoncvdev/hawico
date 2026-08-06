function Get-SmartctlPropertyValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-SmartctlAtaAttributeRawValue {
    param([AllowNull()][object[]]$Table, [Parameter(Mandatory)][int]$Id)
    $match = @($Table) | Where-Object { [int](Get-SmartctlPropertyValue -Object $_ -Name 'id') -eq $Id } | Select-Object -First 1
    if ($null -eq $match) { return $null }
    $raw = Get-SmartctlPropertyValue -Object $match -Name 'raw'
    return Get-SmartctlPropertyValue -Object $raw -Name 'value'
}

function ConvertFrom-SmartctlJson {
    param([Parameter(Mandatory)][AllowNull()][object]$SmartctlOutput)

    $result = [ordered]@{
        Supported = $false
        Source = 'Unavailable'
        OverallHealth = $null
        TemperatureCelsius = $null
        PowerOnHours = $null
        PowerCycleCount = $null
        ReallocatedSectorCount = $null
        PendingSectorCount = $null
        UncorrectableSectorCount = $null
        AvailableSparePercent = $null
        PercentageUsed = $null
        MediaErrorCount = $null
        CriticalWarningFlags = $null
        ErrorCode = $null
        ErrorMessage = $null
    }

    $isParsedObject = $SmartctlOutput -is [System.Management.Automation.PSCustomObject] -or $SmartctlOutput -is [System.Collections.IDictionary]
    if (-not $isParsedObject) {
        $result.ErrorCode = 'SMARTCTL-PARSE-ERROR'
        $result.ErrorMessage = 'smartctl output could not be parsed as JSON.'
        return $result
    }

    $device = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'device'
    $protocol = Get-SmartctlPropertyValue -Object $device -Name 'protocol'
    $source = switch ($protocol) {
        'ATA' { 'ATA' }
        'NVMe' { 'NVMe' }
        default { 'Unavailable' }
    }

    if ($source -eq 'Unavailable') {
        $result.ErrorCode = 'SMARTCTL-UNKNOWN-PROTOCOL'
        $result.ErrorMessage = 'smartctl output did not identify a supported ATA or NVMe protocol.'
        return $result
    }

    $result.Supported = $true
    $result.Source = $source

    $smartStatus = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'smart_status'
    $passed = Get-SmartctlPropertyValue -Object $smartStatus -Name 'passed'
    $result.OverallHealth = if ($null -eq $passed) { $null } elseif ($passed) { 'PASSED' } else { 'FAILED' }

    $temperature = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'temperature'
    $result.TemperatureCelsius = Get-SmartctlPropertyValue -Object $temperature -Name 'current'

    $powerOnTime = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'power_on_time'
    $result.PowerOnHours = Get-SmartctlPropertyValue -Object $powerOnTime -Name 'hours'

    $result.PowerCycleCount = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'power_cycle_count'

    if ($source -eq 'ATA') {
        $ataAttributes = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'ata_smart_attributes'
        $table = @(Get-SmartctlPropertyValue -Object $ataAttributes -Name 'table')
        $result.ReallocatedSectorCount = Get-SmartctlAtaAttributeRawValue -Table $table -Id 5
        $result.PendingSectorCount = Get-SmartctlAtaAttributeRawValue -Table $table -Id 197
        $result.UncorrectableSectorCount = Get-SmartctlAtaAttributeRawValue -Table $table -Id 198
    }
    else {
        $nvmeLog = Get-SmartctlPropertyValue -Object $SmartctlOutput -Name 'nvme_smart_health_information_log'
        $result.AvailableSparePercent = Get-SmartctlPropertyValue -Object $nvmeLog -Name 'available_spare'
        $result.PercentageUsed = Get-SmartctlPropertyValue -Object $nvmeLog -Name 'percentage_used'
        $result.MediaErrorCount = Get-SmartctlPropertyValue -Object $nvmeLog -Name 'media_errors'
        $result.CriticalWarningFlags = Get-SmartctlPropertyValue -Object $nvmeLog -Name 'critical_warning'
    }

    return $result
}

function Invoke-SmartctlCommand {
    param(
        [Parameter(Mandatory)][string]$SmartctlPath,
        [Parameter(Mandatory)][int]$DiskIndex,
        [AllowNull()][string]$DeviceTypeFlag,
        [int]$TimeoutMs = 15000
    )

    $result = [ordered]@{
        Success = $false
        StdOut = $null
        ExitCode = $null
        ErrorCode = $null
        ErrorMessage = $null
    }

    $devicePath = "\\.\PhysicalDrive$DiskIndex"
    $argumentParts = @('-a', '-j')
    if (-not [string]::IsNullOrWhiteSpace($DeviceTypeFlag) -and $DeviceTypeFlag -ne 'auto') {
        $argumentParts += @('-d', $DeviceTypeFlag)
    }
    $argumentParts += $devicePath

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SmartctlPath
    $psi.Arguments = (($argumentParts | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }) -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    try {
        [void]$process.Start()
    }
    catch {
        $result.ErrorCode = 'SMARTCTL-PROCESS-ERROR'
        $result.ErrorMessage = $_.Exception.Message
        return $result
    }

    try {
        # Read stdout asynchronously before WaitForExit — smartctl's JSON
        # payload can exceed the OS pipe buffer, and reading only after exit
        # would deadlock a process still blocked writing to a full pipe.
        $stdOutTask = $process.StandardOutput.ReadToEndAsync()
        $exited = $process.WaitForExit($TimeoutMs)

        if (-not $exited) {
            try { $process.Kill() } catch { }
            $result.ErrorCode = 'SMARTCTL-TIMEOUT'
            $result.ErrorMessage = "smartctl no respondió en $TimeoutMs ms para el disco $DiskIndex."
            return $result
        }

        $result.ExitCode = $process.ExitCode
        $result.StdOut = $stdOutTask.GetAwaiter().GetResult()
        $result.Success = $true
        return $result
    }
    finally {
        $process.Dispose()
    }
}

function Resolve-SmartctlInvocationResult {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Invocation)

    if (-not $Invocation.Success) {
        $result = ConvertFrom-SmartctlJson -SmartctlOutput $null
        $result.ErrorCode = $Invocation.ErrorCode
        $result.ErrorMessage = $Invocation.ErrorMessage
        return $result
    }

    try {
        $parsed = $Invocation.StdOut | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return ConvertFrom-SmartctlJson -SmartctlOutput $null
    }

    return ConvertFrom-SmartctlJson -SmartctlOutput $parsed
}

function Get-DiskSmartData {
    param(
        [Parameter(Mandatory)][string]$SmartctlPath,
        [Parameter(Mandatory)][int]$DiskIndex,
        [AllowNull()][string]$BusType
    )

    $isNvme = [string]$BusType -eq 'NVMe'
    $primaryFlag = if ($isNvme) { 'nvme' } else { 'sat' }

    $invocation = Invoke-SmartctlCommand -SmartctlPath $SmartctlPath -DiskIndex $DiskIndex -DeviceTypeFlag $primaryFlag
    $result = Resolve-SmartctlInvocationResult -Invocation $invocation

    # Any non-NVMe bus (including 'RAID'/'SCSI'/unrecognized/$null — common
    # on Dell/Lenovo/Acer/HP/Gateway and other OEM desktops that ship Intel
    # RST configured in RAID mode even for a single passthrough disk) tries
    # -d sat first, then falls back to bare auto-detect: the same
    # retry-then-degrade contract already established for USB, now applied
    # uniformly instead of USB-only. A genuine SMARTCTL-TIMEOUT is never
    # retried here — retrying would double the wait to 30s for a disk that
    # is simply not responding. Any other invocation-level hard failure
    # (e.g. a rejected -d sat flag) IS retried, matching the pre-existing
    # USB contract. An invocation that ran fine but could not identify a
    # supported protocol through the sat translation (the RAID/SCSI
    # passthrough case) is also retried with bare auto-detect.
    $needsRetry = (-not $isNvme) -and (
        (-not $invocation.Success -and $invocation.ErrorCode -ne 'SMARTCTL-TIMEOUT') -or
        ($invocation.Success -and $result.ErrorCode -eq 'SMARTCTL-UNKNOWN-PROTOCOL')
    )

    if ($needsRetry) {
        $invocation = Invoke-SmartctlCommand -SmartctlPath $SmartctlPath -DiskIndex $DiskIndex -DeviceTypeFlag $null
        $result = Resolve-SmartctlInvocationResult -Invocation $invocation
    }

    return $result
}

function Get-StorageInventory {
    param(
        # Defaults to the bundled Tools\smartctl.exe next to this repo's
        # Modules folder, so both existing call sites (Collector_Hardware_
        # Inventory.ps1, Collector_Windows_HealthCheck.ps1) need zero changes.
        [string]$SmartctlPath = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools') 'smartctl.exe')
    )

    $physicalRaw = Get-CimDataSafe -ClassName "Win32_DiskDrive"
    $logicalRaw = Get-CimDataSafe -ClassName "Win32_LogicalDisk" -Filter "DriveType = 3"

    $logical = @(
        $logicalRaw | ForEach-Object {
            $freePercent = if ($null -ne $_.Size -and [double]$_.Size -gt 0) {
                [math]::Round(([double]$_.FreeSpace / [double]$_.Size) * 100, 2)
            } else { $null }

            [ordered]@{
                Drive       = Get-SafeString $_.DeviceID
                VolumeName  = Get-SafeString $_.VolumeName
                FileSystem  = Get-SafeString $_.FileSystem
                SizeGB      = Convert-BytesToGB $_.Size
                FreeSpaceGB = Convert-BytesToGB $_.FreeSpace
                FreePercent = $freePercent
            }
        }
    )

    $detailed = @()
    if (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        try {
            $detailed = @(
                Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                    [ordered]@{
                        FriendlyName      = Get-SafeString $_.FriendlyName
                        SerialNumber      = Get-SafeString $_.SerialNumber
                        MediaType         = Get-SafeString $_.MediaType
                        BusType           = Get-SafeString $_.BusType
                        SizeGB            = Convert-BytesToGB $_.Size
                        HealthStatus      = Get-SafeString $_.HealthStatus
                        OperationalStatus = @($_.OperationalStatus)
                    }
                }
            )
        }
        catch {
            Write-Warning ("No se pudo consultar Get-PhysicalDisk: {0}" -f $_.Exception.Message)
        }
    }

    # Single explicit Test-Path pre-check (not per-disk): avoids N failed
    # process spawns when the binary is simply absent, matching the
    # Get-PhysicalDisk degradation convention already used above.
    $smartctlAvailable = (-not [string]::IsNullOrWhiteSpace($SmartctlPath)) -and (Test-Path -LiteralPath $SmartctlPath -PathType Leaf)

    $physical = @(
        $physicalRaw | ForEach-Object {
            $diskIndex = $_.Index
            $serialNumber = Get-SafeString $_.SerialNumber
            $model = Get-SafeString $_.Model
            $manufacturer = Get-SafeString $_.Manufacturer
            $interfaceType = Get-SafeString $_.InterfaceType
            $mediaType = Get-SafeString $_.MediaType
            $firmware = Get-SafeString $_.FirmwareRevision
            $sizeGB = Convert-BytesToGB $_.Size
            $partitions = $_.Partitions
            $status = Get-SafeString $_.Status

            $busType = $null
            if ($null -ne $serialNumber) {
                $matchedDetail = @($detailed | Where-Object { $_.SerialNumber -eq $serialNumber })
                if ($matchedDetail.Count -gt 0) { $busType = $matchedDetail[0].BusType }
            }

            $smart = $null
            if ($smartctlAvailable) {
                try {
                    $smart = Get-DiskSmartData -SmartctlPath $SmartctlPath -DiskIndex $diskIndex -BusType $busType
                }
                catch {
                    Write-Warning ("No se pudo obtener datos SMART del disco {0}: {1}" -f $diskIndex, $_.Exception.Message)
                    $smart = ConvertFrom-SmartctlJson -SmartctlOutput $null
                    $smart.ErrorCode = 'SMARTCTL-PROCESS-ERROR'
                    $smart.ErrorMessage = $_.Exception.Message
                }
            }
            else {
                $smart = ConvertFrom-SmartctlJson -SmartctlOutput $null
                $smart.ErrorCode = 'SMARTCTL-NOT-FOUND'
                $smart.ErrorMessage = 'smartctl.exe no está disponible en la ruta configurada.'
            }

            [ordered]@{
                Index         = $diskIndex
                Model         = $model
                Manufacturer  = $manufacturer
                SerialNumber  = $serialNumber
                InterfaceType = $interfaceType
                MediaType     = $mediaType
                Firmware      = $firmware
                SizeGB        = $sizeGB
                Partitions    = $partitions
                Status        = $status
                Smart         = $smart
            }
        }
    )

    return [ordered]@{
        Physical = $physical
        Detailed = $detailed
        Logical = $logical
        Upgrade = [ordered]@{
            InstalledPhysicalDisks = (
                $physicalRaw | Measure-Object
            ).Count

            InstalledNVMeDisks = (
                $detailed |
                Where-Object {
                    $_.BusType -eq "NVMe"
                } |
                Measure-Object
            ).Count

            InstalledSATADisks = (
                $detailed |
                Where-Object {
                    $_.BusType -eq "SATA"
                } |
                Measure-Object
            ).Count
            FreeM2Slots = $null
            FreeSataPorts = $null
            RequiresPhysicalVerification = $true
        }
    }
}
