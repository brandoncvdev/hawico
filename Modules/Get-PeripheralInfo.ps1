function Get-PeripheralPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($PropertyName)) {
            return $Object[$PropertyName]
        }

        return $null
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-PeripheralCategory {
    param(
        [AllowNull()][object]$Device
    )

    $className = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'Class')
    if ([string]::IsNullOrWhiteSpace($className)) {
        $className = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'PNPClass')
    }

    $instanceId = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'InstanceId')
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        $instanceId = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'PNPDeviceID')
    }

    if ($instanceId -match '(?i)^BTH') {
        return 'Bluetooth'
    }

    switch -Regex ($className) {
        '(?i)^(Camera|Image)$' { return 'Cámaras' }
        '(?i)^(AudioEndpoint|MEDIA)$' { return 'Audio' }
        '(?i)^(Keyboard|Mouse|HIDClass)$' { return 'Entrada y controles' }
        '(?i)^(Monitor|Display)$' { return 'Pantallas' }
        '(?i)^(Printer|PrintQueue)$' { return 'Impresoras' }
        '(?i)^(DiskDrive|WPD|Volume)$' { return 'Almacenamiento removible' }
        '(?i)^Ports$' { return 'Puertos serie y comunicación' }
        '(?i)^Biometric$' { return 'Biometría' }
        '(?i)^(SmartCardReader|SmartCard)$' { return 'Tarjetas inteligentes' }
        '(?i)^Sensor$' { return 'Sensores' }
        '(?i)^Bluetooth$' { return 'Bluetooth' }
        '(?i)^USB$' { return 'USB y docks' }
    }

    if ($instanceId -match '(?i)^USB') {
        return 'USB y docks'
    }

    return 'Otros periféricos'
}

function Get-PeripheralConnectionType {
    param(
        [AllowNull()][object]$Device
    )

    $instanceId = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'InstanceId')
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        $instanceId = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'PNPDeviceID')
    }

    $className = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'Class')

    switch -Regex ($instanceId) {
        '(?i)^USBSTOR' { return 'USB (almacenamiento)' }
        '(?i)^USB' { return 'USB' }
        '(?i)^BTH' { return 'Bluetooth' }
        '(?i)^HID' { return 'HID' }
        '(?i)^DISPLAY' { return 'Video' }
        '(?i)^HDAUDIO' { return 'Audio integrado' }
        '(?i)^SWD\\PRINTENUM' { return 'Impresora' }
        '(?i)^(ROOT|SWD)' { return 'Virtual o sistema' }
        '(?i)^(PCI|ACPI)' { return 'Interno o integrado' }
    }

    if ($className -match '(?i)^(Printer|PrintQueue)$') {
        return 'Impresora'
    }

    return 'No determinado'
}

function Test-PeripheralCandidate {
    param(
        [AllowNull()][object]$Device
    )

    $className = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'Class')
    if ([string]::IsNullOrWhiteSpace($className)) {
        $className = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'PNPClass')
    }

    $instanceId = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'InstanceId')
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        $instanceId = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'PNPDeviceID')
    }

    $friendlyName = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'FriendlyName')
    if ([string]::IsNullOrWhiteSpace($friendlyName)) {
        $friendlyName = [string](Get-PeripheralPropertyValue -Object $Device -PropertyName 'Name')
    }

    if ($friendlyName -match '(?i)Remote Desktop|VirtualBox|VMware|Hyper-V|Virtual HID') {
        return $false
    }

    if (
        $friendlyName -match '(?i)USB.*Host Controller|USB Root Hub' -or
        $instanceId -match '(?i)^USB\\ROOT_HUB'
    ) {
        return $false
    }

    $peripheralClasses = @(
        'AudioEndpoint', 'Biometric', 'Bluetooth', 'Camera', 'DiskDrive',
        'Display', 'HIDClass', 'Image', 'Keyboard', 'MEDIA', 'Monitor', 'Mouse',
        'Ports', 'Printer', 'PrintQueue', 'Sensor', 'SmartCard',
        'SmartCardReader', 'USB', 'Volume', 'WPD'
    )

    if ($peripheralClasses -contains $className) {
        return $true
    }

    return ($instanceId -match '(?i)^(USB|BTH)')
}

function Get-PeripheralInventory {
    $devices = @()
    $collectionMethod = 'No disponible'
    $pnpDevices = @()
    $cimDevices = @()

    if (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue) {
        try {
            $pnpDevices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
            $collectionMethod = 'Get-PnpDevice -PresentOnly'
        }
        catch {
            Write-Warning ("No se pudieron consultar periféricos con Get-PnpDevice: {0}" -f $_.Exception.Message)
        }
    }

    try {
        $cimDevices = @(Get-CimDataSafe -ClassName 'Win32_PnPEntity' -Filter 'Present = TRUE')
    }
    catch {
        Write-Warning ("No se pudieron enriquecer los periféricos con Win32_PnPEntity: {0}" -f $_.Exception.Message)
    }

    if (($pnpDevices | Measure-Object).Count -eq 0) {
        $pnpDevices = @($cimDevices)
        if (($pnpDevices | Measure-Object).Count -gt 0) {
            $collectionMethod = 'Win32_PnPEntity'
        }
    }

    $cimByInstanceId = @{}
    foreach ($cimDevice in $cimDevices) {
        $cimInstanceId = [string](Get-PeripheralPropertyValue -Object $cimDevice -PropertyName 'PNPDeviceID')
        if (-not [string]::IsNullOrWhiteSpace($cimInstanceId)) {
            $cimByInstanceId[$cimInstanceId] = $cimDevice
        }
    }

    $devices = @(
        $pnpDevices |
            Where-Object { Test-PeripheralCandidate -Device $_ } |
            ForEach-Object {
                $device = $_
                $instanceId = [string](Get-PeripheralPropertyValue -Object $device -PropertyName 'InstanceId')
                if ([string]::IsNullOrWhiteSpace($instanceId)) {
                    $instanceId = [string](Get-PeripheralPropertyValue -Object $device -PropertyName 'PNPDeviceID')
                }

                $cimDevice = $null
                if (-not [string]::IsNullOrWhiteSpace($instanceId) -and $cimByInstanceId.ContainsKey($instanceId)) {
                    $cimDevice = $cimByInstanceId[$instanceId]
                }

                $friendlyName = Get-PeripheralPropertyValue -Object $device -PropertyName 'FriendlyName'
                if ([string]::IsNullOrWhiteSpace([string]$friendlyName)) {
                    $friendlyName = Get-PeripheralPropertyValue -Object $device -PropertyName 'Name'
                }
                if ([string]::IsNullOrWhiteSpace([string]$friendlyName)) {
                    $friendlyName = Get-PeripheralPropertyValue -Object $cimDevice -PropertyName 'Name'
                }

                $className = Get-PeripheralPropertyValue -Object $device -PropertyName 'Class'
                if ([string]::IsNullOrWhiteSpace([string]$className)) {
                    $className = Get-PeripheralPropertyValue -Object $device -PropertyName 'PNPClass'
                }

                $problemCode = Get-PeripheralPropertyValue -Object $device -PropertyName 'Problem'
                if ($null -eq $problemCode) {
                    $problemCode = Get-PeripheralPropertyValue -Object $cimDevice -PropertyName 'ConfigManagerErrorCode'
                }

                $status = Get-PeripheralPropertyValue -Object $device -PropertyName 'Status'
                if ([string]::IsNullOrWhiteSpace([string]$status)) {
                    $status = Get-PeripheralPropertyValue -Object $cimDevice -PropertyName 'Status'
                }

                $connectionType = Get-PeripheralConnectionType -Device $device

                [ordered]@{
                    Category       = Get-PeripheralCategory -Device $device
                    FriendlyName   = Get-SafeString $friendlyName
                    Manufacturer   = Get-SafeString (Get-PeripheralPropertyValue -Object $cimDevice -PropertyName 'Manufacturer')
                    Class          = Get-SafeString $className
                    ConnectionType = $connectionType
                    IsExternal     = ($connectionType -match '(?i)^(USB|Bluetooth|Impresora)')
                    Status         = Get-SafeString $status
                    ProblemCode    = $problemCode
                    Service        = Get-SafeString (Get-PeripheralPropertyValue -Object $cimDevice -PropertyName 'Service')
                    InstanceId     = Get-SafeString $instanceId
                }
            } |
            Sort-Object Category, FriendlyName, InstanceId -Unique
    )

    $categories = @($devices | Group-Object Category)
    $problemDevices = @($devices | Where-Object {
        $statusText = [string]$_.Status
        $problemText = [string]$_.ProblemCode
        $hasStatusProblem = (
            -not [string]::IsNullOrWhiteSpace($statusText) -and
            $statusText -notin @('OK', 'Unknown')
        )
        $hasProblemCode = (
            -not [string]::IsNullOrWhiteSpace($problemText) -and
            $problemText -notin @('0', 'CM_PROB_NONE', 'None')
        )

        $hasStatusProblem -or $hasProblemCode
    })

    return [ordered]@{
        CollectionMethod = $collectionMethod
        Devices = $devices
        Summary = [ordered]@{
            Total = $devices.Count
            Categories = $categories.Count
            External = @($devices | Where-Object { $_.IsExternal }).Count
            USB = @($devices | Where-Object { $_.ConnectionType -match '^USB' }).Count
            Bluetooth = @($devices | Where-Object { $_.ConnectionType -eq 'Bluetooth' }).Count
            WithProblems = $problemDevices.Count
        }
    }
}
