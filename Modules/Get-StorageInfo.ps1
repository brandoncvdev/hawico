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

function Get-StorageInventory {
    $physicalRaw = Get-CimDataSafe -ClassName "Win32_DiskDrive"
    $logicalRaw = Get-CimDataSafe -ClassName "Win32_LogicalDisk" -Filter "DriveType = 3"

    $physical = @(
        $physicalRaw | ForEach-Object {
            [ordered]@{
                Index         = $_.Index
                Model         = Get-SafeString $_.Model
                Manufacturer  = Get-SafeString $_.Manufacturer
                SerialNumber  = Get-SafeString $_.SerialNumber
                InterfaceType = Get-SafeString $_.InterfaceType
                MediaType     = Get-SafeString $_.MediaType
                Firmware      = Get-SafeString $_.FirmwareRevision
                SizeGB        = Convert-BytesToGB $_.Size
                Partitions    = $_.Partitions
                Status        = Get-SafeString $_.Status
            }
        }
    )

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
