function ConvertTo-HtmlSafe {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-InventoryDisplayValue {
    param(
        [AllowNull()][object]$Value,
        [string]$Suffix = ""
    )

    if ($null -eq $Value) {
        return '<span class="muted">No disponible</span>'
    }

    if ($Value -is [bool]) {
        if ($Value) {
            return '<span class="status status-ok">Sí</span>'
        }

        return '<span class="status status-neutral">No</span>'
    }

    if (
        $Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string])
    ) {
        $items = @(
            $Value |
                ForEach-Object {
                    if ($null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_)) {
                        ConvertTo-HtmlSafe $_
                    }
                }
        )

        if (($items | Measure-Object).Count -eq 0) {
            return '<span class="muted">No disponible</span>'
        }

        return ($items -join '<br>')
    }

    $text = [string]$Value

    if ([string]::IsNullOrWhiteSpace($text)) {
        return '<span class="muted">No disponible</span>'
    }

    return "{0}{1}" -f (ConvertTo-HtmlSafe $text), (ConvertTo-HtmlSafe $Suffix)
}

function Get-InventoryPropertyValue {
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

    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }

    return $null
}

function New-InventoryMetric {
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowNull()][object]$Value,
        [string]$Suffix = ""
    )

    return @"
<div class="item">
    <div class="label">$(ConvertTo-HtmlSafe $Label)</div>
    <div class="value">$(Get-InventoryDisplayValue -Value $Value -Suffix $Suffix)</div>
</div>
"@
}

function New-InventoryPropertyGrid {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fields
    )

    $content = ""

    foreach ($entry in $Fields.GetEnumerator()) {
        $propertyValue = Get-InventoryPropertyValue `
            -Object $Object `
            -PropertyName ([string]$entry.Value)

        $content += New-InventoryMetric `
            -Label ([string]$entry.Key) `
            -Value $propertyValue
    }

    return $content
}

function New-InventoryTable {
    param(
        [AllowNull()][object[]]$Rows,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Columns,
        [string]$EmptyMessage = "No se encontraron registros."
    )

    $safeRows = @($Rows)

    if (($safeRows | Measure-Object).Count -eq 0) {
        return @"
<div class="empty-state">$(ConvertTo-HtmlSafe $EmptyMessage)</div>
"@
    }

    $header = ""
    foreach ($column in $Columns.GetEnumerator()) {
        $header += "<th>$(ConvertTo-HtmlSafe $column.Key)</th>"
    }

    $body = ""

    foreach ($row in $safeRows) {
        $body += "<tr>"

        foreach ($column in $Columns.GetEnumerator()) {
            $value = Get-InventoryPropertyValue `
                -Object $row `
                -PropertyName ([string]$column.Value)

            $body += "<td>$(Get-InventoryDisplayValue -Value $value)</td>"
        }

        $body += "</tr>"
    }

    return @"
<div class="table-wrap">
<table>
    <thead>
        <tr>$header</tr>
    </thead>
    <tbody>
        $body
    </tbody>
</table>
</div>
"@
}

function New-InventorySection {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Content,
        [string]$Subtitle = "",
        [bool]$Open = $true,
        [string]$Badge = ""
    )

    $openAttribute = if ($Open) { " open" } else { "" }

    $subtitleHtml = if ([string]::IsNullOrWhiteSpace($Subtitle)) {
        ""
    }
    else {
        "<div class=`"section-subtitle`">$(ConvertTo-HtmlSafe $Subtitle)</div>"
    }

    $badgeHtml = if ([string]::IsNullOrWhiteSpace($Badge)) {
        ""
    }
    else {
        "<span class=`"badge`">$(ConvertTo-HtmlSafe $Badge)</span>"
    }

    return @"
<details class="section"$openAttribute>
    <summary>
        <div>
            <div class="section-title">$(ConvertTo-HtmlSafe $Title) $badgeHtml</div>
            $subtitleHtml
        </div>
        <span class="chevron">⌄</span>
    </summary>
    <div class="section-content">
        $Content
    </div>
</details>
"@
}


function New-NetworkAdapterCards {
    param(
        [AllowNull()][object[]]$Adapters
    )

    $safeAdapters = @($Adapters)

    if (($safeAdapters | Measure-Object).Count -eq 0) {
        return '<div class="empty-state">No se encontraron adaptadores de red físicos.</div>'
    }

    $content = '<div class="network-grid">'

    foreach ($adapter in $safeAdapters) {
        $name = Get-InventoryPropertyValue -Object $adapter -PropertyName "InterfaceAlias"
        $type = Get-InventoryPropertyValue -Object $adapter -PropertyName "AdapterType"
        $status = Get-InventoryPropertyValue -Object $adapter -PropertyName "Status"
        $isActive = Get-InventoryPropertyValue -Object $adapter -PropertyName "IsActive"
        $description = Get-InventoryPropertyValue -Object $adapter -PropertyName "Description"

        $statusClass = if ($isActive -eq $true -or $status -eq "Up") { "network-active" } else { "network-inactive" }
        $statusText = if ($isActive -eq $true -or $status -eq "Up") { "Activa" } else { "Inactiva" }
        $icon = if ($type -eq "Wi-Fi") { "Wi-Fi" } elseif ($type -eq "Ethernet") { "LAN" } else { "NIC" }

        $content += @"
<div class="network-card $statusClass">
    <div class="network-card-head">
        <div>
            <div class="network-type">$(ConvertTo-HtmlSafe $icon)</div>
            <div class="network-name">$(Get-InventoryDisplayValue -Value $name)</div>
            <div class="network-description">$(Get-InventoryDisplayValue -Value $description)</div>
        </div>
        <span class="network-state">$(ConvertTo-HtmlSafe $statusText)</span>
    </div>
    <div class="network-details">
$(New-InventoryMetric -Label "Tipo" -Value $type)
$(New-InventoryMetric -Label "Estado del medio" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "MediaState"))
$(New-InventoryMetric -Label "Dirección MAC" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "MACAddress"))
$(New-InventoryMetric -Label "Velocidad de enlace" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "LinkSpeed"))
$(New-InventoryMetric -Label "IPv4" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "IPv4Addresses"))
$(New-InventoryMetric -Label "Gateway IPv4" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "IPv4Gateways"))
$(New-InventoryMetric -Label "IPv6" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "IPv6Addresses"))
$(New-InventoryMetric -Label "DNS" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "DNSServers"))
$(New-InventoryMetric -Label "Controlador" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "DriverName"))
$(New-InventoryMetric -Label "Versión del controlador" -Value (Get-InventoryPropertyValue -Object $adapter -PropertyName "DriverVersion"))
    </div>
</div>
"@
    }

    $content += '</div>'
    return $content
}

function New-InventoryHtml {
    param(
        [Parameter(Mandatory)][hashtable]$Inventory,
        [Parameter(Mandatory)][string]$Path
    )

    $computer = $Inventory.Computer
    $operatingSystem = $Inventory.OperatingSystem
    $bios = $Inventory.BIOS
    $motherboard = $Inventory.Motherboard
    $memory = $Inventory.Memory
    $memoryUpgrade = $memory.Upgrade
    $storage = $Inventory.Storage
    $expansion = $Inventory.Expansion
    $security = $Inventory.Security

    $sections = ""

    $overviewContent = @"
<div class="grid overview-grid">
$(New-InventoryMetric -Label "Nombre del equipo" -Value $computer.Hostname)
$(New-InventoryMetric -Label "Fabricante" -Value $computer.Manufacturer)
$(New-InventoryMetric -Label "Modelo" -Value $computer.Model)
$(New-InventoryMetric -Label "Número de serie" -Value $bios.SerialNumber)
$(New-InventoryMetric -Label "Sistema operativo" -Value $operatingSystem.Caption)
$(New-InventoryMetric -Label "Arquitectura" -Value $operatingSystem.Architecture)
$(New-InventoryMetric -Label "Memoria instalada" -Value $memoryUpgrade.InstalledMemoryGB -Suffix " GB")
$(New-InventoryMetric -Label "Discos físicos" -Value $storage.Upgrade.InstalledPhysicalDisks)
</div>
"@

    $sections += New-InventorySection `
        -Title "Resumen del equipo" `
        -Subtitle "Identificación y datos principales" `
        -Content $overviewContent `
        -Open $true

    $computerContent = @"
<div class="subsection">
    <h3>Equipo</h3>
    <div class="grid">
$(New-InventoryPropertyGrid -Object $computer -Fields ([ordered]@{
    "Nombre" = "Hostname"
    "Fabricante" = "Manufacturer"
    "Modelo" = "Model"
    "Tipo de sistema" = "SystemType"
    "UUID" = "UUID"
    "Identificador" = "IdentifyingNumber"
    "Dominio o grupo" = "Domain"
    "Pertenece a dominio" = "PartOfDomain"
    "Memoria reportada" = "TotalMemoryGB"
}))
    </div>
</div>

<div class="subsection">
    <h3>Sistema operativo</h3>
    <div class="grid">
$(New-InventoryPropertyGrid -Object $operatingSystem -Fields ([ordered]@{
    "Nombre" = "Caption"
    "Versión" = "Version"
    "Compilación" = "BuildNumber"
    "Arquitectura" = "Architecture"
    "Fecha de instalación" = "InstallDate"
    "Último arranque" = "LastBootUpTime"
}))
    </div>
</div>
"@

    $sections += New-InventorySection `
        -Title "Sistema" `
        -Subtitle "Equipo y sistema operativo" `
        -Content $computerContent `
        -Open $true

    $firmwareContent = @"
<div class="subsection">
    <h3>BIOS</h3>
    <div class="grid">
$(New-InventoryPropertyGrid -Object $bios -Fields ([ordered]@{
    "Fabricante" = "Manufacturer"
    "Versión" = "Version"
    "Número de serie" = "SerialNumber"
    "Fecha de publicación" = "ReleaseDate"
}))
    </div>
</div>

<div class="subsection">
    <h3>Tarjeta madre</h3>
    <div class="grid">
$(New-InventoryPropertyGrid -Object $motherboard -Fields ([ordered]@{
    "Fabricante" = "Manufacturer"
    "Producto" = "Product"
    "Versión" = "Version"
    "Número de serie" = "SerialNumber"
}))
    </div>
</div>
"@

    $sections += New-InventorySection `
        -Title "Firmware y tarjeta madre" `
        -Subtitle "BIOS y placa base" `
        -Content $firmwareContent `
        -Open $false

    $processorTable = New-InventoryTable `
        -Rows @($Inventory.Processors) `
        -Columns ([ordered]@{
            "Procesador" = "Name"
            "Fabricante" = "Manufacturer"
            "Socket" = "Socket"
            "Núcleos" = "NumberOfCores"
            "Procesadores lógicos" = "NumberOfLogicalProcessors"
            "Frecuencia máxima MHz" = "MaxClockSpeedMHz"
            "Frecuencia actual MHz" = "CurrentClockSpeedMHz"
            "Estado" = "Status"
        }) `
        -EmptyMessage "No se encontró información del procesador."

    $sections += New-InventorySection `
        -Title "Procesador" `
        -Content $processorTable `
        -Badge "$(@($Inventory.Processors).Count)"

    $memorySummary = @"
<div class="grid">
$(New-InventoryMetric -Label "Memoria instalada" -Value $memoryUpgrade.InstalledMemoryGB -Suffix " GB")
$(New-InventoryMetric -Label "Máxima reportada" -Value $memoryUpgrade.MaximumReportedGB -Suffix " GB")
$(New-InventoryMetric -Label "Expansión potencial" -Value $memoryUpgrade.PotentialAdditionalGB -Suffix " GB")
$(New-InventoryMetric -Label "Slots totales" -Value $memoryUpgrade.TotalSlots)
$(New-InventoryMetric -Label "Slots ocupados" -Value $memoryUpgrade.OccupiedSlots)
$(New-InventoryMetric -Label "Slots disponibles" -Value $memoryUpgrade.AvailableSlots)
$(New-InventoryMetric -Label "Confiabilidad" -Value $memoryUpgrade.Reliability)
$(New-InventoryMetric -Label "Requiere verificación" -Value $memoryUpgrade.RequiresVerification)
</div>
"@

    $memoryTable = New-InventoryTable `
        -Rows @($memory.Modules) `
        -Columns ([ordered]@{
            "Ubicación" = "DeviceLocator"
            "Banco" = "BankLabel"
            "Fabricante" = "Manufacturer"
            "Número de parte" = "PartNumber"
            "Número de serie" = "SerialNumber"
            "Capacidad GB" = "CapacityGB"
            "Tipo" = "MemoryTypeName"
            "Velocidad MHz" = "SpeedMHz"
            "Configurada MHz" = "ConfiguredSpeedMHz"
        }) `
        -EmptyMessage "No se encontraron módulos de memoria."

    $memoryContent = @"
$memorySummary
<div class="subsection">
    <h3>Módulos instalados</h3>
    $memoryTable
</div>
"@

    $sections += New-InventorySection `
        -Title "Memoria" `
        -Subtitle "Capacidad, expansión y módulos instalados" `
        -Content $memoryContent `
        -Badge "$(@($memory.Modules).Count)"

    $physicalDiskTable = New-InventoryTable `
        -Rows @($storage.Physical) `
        -Columns ([ordered]@{
            "Índice" = "Index"
            "Modelo" = "Model"
            "Fabricante" = "Manufacturer"
            "Número de serie" = "SerialNumber"
            "Interfaz" = "InterfaceType"
            "Tipo de medio" = "MediaType"
            "Firmware" = "Firmware"
            "Capacidad GB" = "SizeGB"
            "Particiones" = "Partitions"
            "Estado" = "Status"
        }) `
        -EmptyMessage "No se encontraron discos físicos."

    $detailedDiskTable = New-InventoryTable `
        -Rows @($storage.Detailed) `
        -Columns ([ordered]@{
            "Nombre" = "FriendlyName"
            "Número de serie" = "SerialNumber"
            "Tipo de medio" = "MediaType"
            "Bus" = "BusType"
            "Capacidad GB" = "SizeGB"
            "Salud" = "HealthStatus"
            "Estado operativo" = "OperationalStatus"
        }) `
        -EmptyMessage "El sistema no devolvió información avanzada de almacenamiento."

    $logicalDiskTable = New-InventoryTable `
        -Rows @($storage.Logical) `
        -Columns ([ordered]@{
            "Unidad" = "Drive"
            "Nombre" = "VolumeName"
            "Sistema de archivos" = "FileSystem"
            "Capacidad GB" = "SizeGB"
            "Espacio libre GB" = "FreeSpaceGB"
            "Libre %" = "FreePercent"
        }) `
        -EmptyMessage "No se encontraron volúmenes locales."

    $storageContent = @"
<div class="grid">
$(New-InventoryMetric -Label "Discos físicos instalados" -Value $storage.Upgrade.InstalledPhysicalDisks)
$(New-InventoryMetric -Label "Discos NVMe" -Value $storage.Upgrade.InstalledNVMeDisks)
$(New-InventoryMetric -Label "Discos SATA" -Value $storage.Upgrade.InstalledSATADisks)
$(New-InventoryMetric -Label "Slots M.2 libres" -Value $storage.Upgrade.FreeM2Slots)
$(New-InventoryMetric -Label "Puertos SATA libres" -Value $storage.Upgrade.FreeSataPorts)
$(New-InventoryMetric -Label "Requiere verificación física" -Value $storage.Upgrade.RequiresPhysicalVerification)
</div>

<div class="subsection">
    <h3>Discos físicos</h3>
    $physicalDiskTable
</div>

<div class="subsection">
    <h3>Información avanzada</h3>
    $detailedDiskTable
</div>

<div class="subsection">
    <h3>Unidades y volúmenes</h3>
    $logicalDiskTable
</div>
"@

    $sections += New-InventorySection `
        -Title "Almacenamiento" `
        -Subtitle "Discos físicos, salud y volúmenes" `
        -Content $storageContent `
        -Badge "$(@($storage.Physical).Count)"

    $networkAdapters = @($Inventory.NetworkAdapters)
    $activeNetworkAdapters = @($networkAdapters | Where-Object {
        (Get-InventoryPropertyValue -Object $_ -PropertyName "IsActive") -eq $true -or
        (Get-InventoryPropertyValue -Object $_ -PropertyName "Status") -eq "Up"
    })
    $inactiveNetworkAdapters = @($networkAdapters | Where-Object {
        -not (
            (Get-InventoryPropertyValue -Object $_ -PropertyName "IsActive") -eq $true -or
            (Get-InventoryPropertyValue -Object $_ -PropertyName "Status") -eq "Up"
        )
    })

    $networkSummary = @"
<div class="grid dashboard-grid">
$(New-InventoryMetric -Label "Adaptadores detectados" -Value $networkAdapters.Count)
$(New-InventoryMetric -Label "Interfaces activas" -Value $activeNetworkAdapters.Count)
$(New-InventoryMetric -Label "Interfaces inactivas" -Value $inactiveNetworkAdapters.Count)
$(New-InventoryMetric -Label "Ethernet" -Value @($networkAdapters | Where-Object { (Get-InventoryPropertyValue -Object $_ -PropertyName "AdapterType") -eq "Ethernet" }).Count)
$(New-InventoryMetric -Label "Wi-Fi" -Value @($networkAdapters | Where-Object { (Get-InventoryPropertyValue -Object $_ -PropertyName "AdapterType") -eq "Wi-Fi" }).Count)
</div>
"@

    $networkCards = New-NetworkAdapterCards -Adapters $networkAdapters
    $networkContent = @"
$networkSummary
<div class="subsection">
    <h3>Interfaces físicas detectadas</h3>
    $networkCards
</div>
"@

    $sections += New-InventorySection `
        -Title "Red" `
        -Subtitle "Todas las interfaces físicas, activas e inactivas" `
        -Content $networkContent `
        -Badge "$($networkAdapters.Count)"

    $graphicsTable = New-InventoryTable `
        -Rows @($Inventory.GraphicsAdapters) `
        -Columns ([ordered]@{
            "Adaptador" = "Name"
            "Procesador gráfico" = "VideoProcessor"
            "Memoria GB" = "AdapterRAMGB"
            "Controlador" = "DriverVersion"
            "Fecha del controlador" = "DriverDate"
            "Resolución" = "Resolution"
            "Estado" = "Status"
        }) `
        -EmptyMessage "No se recopiló información gráfica en este modo."

    $sections += New-InventorySection `
        -Title "Gráficos" `
        -Content $graphicsTable `
        -Open $false `
        -Badge "$(@($Inventory.GraphicsAdapters).Count)"

    $expansionSummary = Get-InventoryPropertyValue -Object $expansion -PropertyName "Summary"
    $expansionSlots = Get-InventoryPropertyValue -Object $expansion -PropertyName "Slots"

    $expansionTable = New-InventoryTable `
        -Rows @($expansionSlots) `
        -Columns ([ordered]@{
            "Ranura" = "SlotDesignation"
            "Descripción" = "Description"
            "Uso actual" = "CurrentUsage"
            "Ancho máximo" = "MaxDataWidth"
            "Propósito" = "Purpose"
            "Hot-plug" = "SupportsHotPlug"
            "Estado" = "Status"
        }) `
        -EmptyMessage "No se recopiló información de ranuras de expansión."

    $expansionContent = @"
<div class="grid">
$(New-InventoryMetric -Label "Ranuras reportadas" -Value (Get-InventoryPropertyValue -Object $expansionSummary -PropertyName "TotalReported"))
$(New-InventoryMetric -Label "Disponibles reportadas" -Value (Get-InventoryPropertyValue -Object $expansionSummary -PropertyName "AvailableReported"))
$(New-InventoryMetric -Label "Ocupadas reportadas" -Value (Get-InventoryPropertyValue -Object $expansionSummary -PropertyName "OccupiedReported"))
$(New-InventoryMetric -Label "Confiabilidad" -Value (Get-InventoryPropertyValue -Object $expansionSummary -PropertyName "Reliability"))
$(New-InventoryMetric -Label "Requiere verificación física" -Value (Get-InventoryPropertyValue -Object $expansionSummary -PropertyName "RequiresPhysicalVerification"))
</div>

<div class="subsection">
    <h3>Ranuras detectadas</h3>
    $expansionTable
</div>
"@

    $sections += New-InventorySection `
        -Title "Expansión" `
        -Subtitle "Ranuras PCI y PCIe reportadas por el fabricante" `
        -Content $expansionContent `
        -Open $false `
        -Badge "$(@($expansionSlots).Count)"

    $tpm = Get-InventoryPropertyValue -Object $security -PropertyName "TPM"
    $secureBoot = Get-InventoryPropertyValue -Object $security -PropertyName "SecureBoot"
    $bitLocker = Get-InventoryPropertyValue -Object $security -PropertyName "BitLocker"

    $bitLockerTable = New-InventoryTable `
        -Rows @($bitLocker) `
        -Columns ([ordered]@{
            "Unidad" = "MountPoint"
            "Tipo de volumen" = "VolumeType"
            "Estado" = "VolumeStatus"
            "Protección" = "ProtectionStatus"
            "Cifrado %" = "EncryptionPercentage"
            "Método" = "EncryptionMethod"
        }) `
        -EmptyMessage "No se encontró información de BitLocker."

    $securityContent = @"
<div class="subsection">
    <h3>TPM</h3>
    <div class="grid">
$(New-InventoryPropertyGrid -Object $tpm -Fields ([ordered]@{
    "Presente" = "Present"
    "Preparado" = "Ready"
    "Habilitado" = "Enabled"
    "Activado" = "Activated"
    "Propiedad del sistema" = "Owned"
    "Versión de especificación" = "SpecVersion"
    "Fabricante" = "ManufacturerIdTxt"
    "Versión del fabricante" = "ManufacturerVersion"
}))
    </div>
</div>

<div class="subsection">
    <h3>Secure Boot</h3>
    <div class="grid">
$(New-InventoryPropertyGrid -Object $secureBoot -Fields ([ordered]@{
    "Compatible" = "Supported"
    "Habilitado" = "Enabled"
    "Error" = "Error"
}))
    </div>
</div>

<div class="subsection">
    <h3>BitLocker</h3>
    $bitLockerTable
</div>
"@

    $sections += New-InventorySection `
        -Title "Seguridad" `
        -Subtitle "TPM, Secure Boot y BitLocker" `
        -Content $securityContent `
        -Open $false

    $peripherals = Get-InventoryPropertyValue -Object $Inventory -PropertyName "Peripherals"
    $peripheralSummary = Get-InventoryPropertyValue -Object $peripherals -PropertyName "Summary"
    $peripheralDevices = @(Get-InventoryPropertyValue -Object $peripherals -PropertyName "Devices")
    $peripheralGroups = @($peripheralDevices | Group-Object Category | Sort-Object Name)

    $peripheralTables = ""
    foreach ($group in $peripheralGroups) {
        $categoryTable = New-InventoryTable `
            -Rows @($group.Group) `
            -Columns ([ordered]@{
                "Dispositivo" = "FriendlyName"
                "Fabricante" = "Manufacturer"
                "Conexión" = "ConnectionType"
                "Estado" = "Status"
                "Clase PnP" = "Class"
                "Código de problema" = "ProblemCode"
                "Identificador" = "InstanceId"
            }) `
            -EmptyMessage "No se encontraron dispositivos en esta categoría."

        $peripheralTables += @"
<div class="subsection">
    <h3>$(ConvertTo-HtmlSafe $group.Name) <span class="badge">$($group.Count)</span></h3>
    $categoryTable
</div>
"@
    }

    if ([string]::IsNullOrWhiteSpace($peripheralTables)) {
        $peripheralTables = '<div class="empty-state">No se recopilaron periféricos en este modo.</div>'
    }

    $peripheralContent = @"
<div class="grid dashboard-grid">
$(New-InventoryMetric -Label "Periféricos detectados" -Value (Get-InventoryPropertyValue -Object $peripheralSummary -PropertyName "Total"))
$(New-InventoryMetric -Label "Categorías" -Value (Get-InventoryPropertyValue -Object $peripheralSummary -PropertyName "Categories"))
$(New-InventoryMetric -Label "Externos identificados" -Value (Get-InventoryPropertyValue -Object $peripheralSummary -PropertyName "External"))
$(New-InventoryMetric -Label "USB" -Value (Get-InventoryPropertyValue -Object $peripheralSummary -PropertyName "USB"))
$(New-InventoryMetric -Label "Bluetooth" -Value (Get-InventoryPropertyValue -Object $peripheralSummary -PropertyName "Bluetooth"))
$(New-InventoryMetric -Label "Con problemas" -Value (Get-InventoryPropertyValue -Object $peripheralSummary -PropertyName "WithProblems"))
$(New-InventoryMetric -Label "Método de recopilación" -Value (Get-InventoryPropertyValue -Object $peripherals -PropertyName "CollectionMethod"))
</div>
$peripheralTables
"@

    $sections += New-InventorySection `
        -Title "Periféricos conectados" `
        -Subtitle "USB, Bluetooth, audio, cámaras, entrada, pantallas, impresoras y dispositivos especializados" `
        -Content $peripheralContent `
        -Open $false `
        -Badge "$($peripheralDevices.Count)"

    $deviceErrorTable = New-InventoryTable `
        -Rows @($Inventory.DevicesWithErrors) `
        -Columns ([ordered]@{
            "Clase" = "Class"
            "Dispositivo" = "FriendlyName"
            "Estado" = "Status"
            "Problema" = "Problem"
            "Identificador" = "InstanceId"
        }) `
        -EmptyMessage "No se detectaron dispositivos con errores."

    $errorCount = @($Inventory.DevicesWithErrors).Count
    $errorBadge = if ($errorCount -gt 0) {
        "$errorCount detectados"
    }
    else {
        "Sin errores"
    }

    $sections += New-InventorySection `
        -Title "Dispositivos con errores" `
        -Subtitle "Elementos PnP con estado distinto de OK" `
        -Content $deviceErrorTable `
        -Open ($errorCount -gt 0) `
        -Badge $errorBadge

    $collectionContent = @"
<div class="grid">
$(New-InventoryMetric -Label "Versión de esquema" -Value $Inventory.SchemaVersion)
$(New-InventoryMetric -Label "Fecha de recopilación" -Value $Inventory.Collection.CollectedAt)
$(New-InventoryMetric -Label "Modo" -Value $Inventory.Collection.Mode)
$(New-InventoryMetric -Label "Usuario de ejecución" -Value $Inventory.Collection.ScriptUser)
</div>
"@

    $sections += New-InventorySection `
        -Title "Metadatos de recopilación" `
        -Content $collectionContent `
        -Open $false

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Inventario - $(ConvertTo-HtmlSafe $computer.Hostname)</title>
<style>
:root {
    --background: #f4f6f8;
    --surface: #ffffff;
    --surface-soft: #f8fafc;
    --border: #dce3e9;
    --border-soft: #e8edf1;
    --text: #20262d;
    --muted: #66717d;
    --accent: #2f6f9f;
    --accent-soft: #eaf3f9;
    --success: #287a4d;
    --success-soft: #eaf6ef;
    --neutral-soft: #eef1f4;
    --shadow: 0 2px 8px rgba(32, 38, 45, .07);
}

* {
    box-sizing: border-box;
}

html {
    scroll-behavior: smooth;
}

body {
    margin: 0;
    background: var(--background);
    color: var(--text);
    font-family: "Segoe UI", Arial, sans-serif;
    font-size: 14px;
    line-height: 1.45;
}

.container {
    width: min(1500px, calc(100% - 32px));
    margin: 24px auto 48px;
}

.hero {
    background: var(--surface);
    border: 1px solid var(--border-soft);
    border-radius: 12px;
    box-shadow: var(--shadow);
    padding: 22px 24px;
    margin-bottom: 14px;
}

.hero-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 20px;
}

h1 {
    font-size: 28px;
    line-height: 1.15;
    margin: 0 0 6px;
    font-weight: 650;
}

.hero-subtitle {
    color: var(--muted);
    font-size: 13px;
}

.hero-host {
    text-align: right;
}

.hero-host .hostname {
    font-size: 19px;
    font-weight: 650;
}

.hero-host .model {
    color: var(--muted);
    margin-top: 2px;
}

.toolbar {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-top: 18px;
}

button {
    border: 1px solid var(--border);
    background: var(--surface-soft);
    color: var(--text);
    border-radius: 7px;
    padding: 7px 11px;
    font: inherit;
    cursor: pointer;
}

button:hover {
    background: var(--accent-soft);
    border-color: #bdd3e3;
}

.section {
    background: var(--surface);
    border: 1px solid var(--border-soft);
    border-radius: 10px;
    box-shadow: var(--shadow);
    margin: 10px 0;
    overflow: hidden;
}

.section summary {
    list-style: none;
    cursor: pointer;
    padding: 14px 18px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    user-select: none;
}

.section summary::-webkit-details-marker {
    display: none;
}

.section[open] summary {
    border-bottom: 1px solid var(--border-soft);
}

.section-title {
    font-size: 16px;
    font-weight: 650;
}

.section-subtitle {
    color: var(--muted);
    font-size: 12px;
    margin-top: 2px;
}

.section-content {
    padding: 16px 18px 18px;
}

.chevron {
    color: var(--muted);
    font-size: 18px;
    transition: transform .15s ease;
}

.section[open] .chevron {
    transform: rotate(180deg);
}

.badge {
    display: inline-block;
    margin-left: 7px;
    padding: 2px 7px;
    border-radius: 999px;
    background: var(--accent-soft);
    color: var(--accent);
    font-size: 11px;
    font-weight: 650;
    vertical-align: middle;
}

.grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(185px, 1fr));
    gap: 8px;
}

.overview-grid {
    grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
}

.dashboard-grid {
    margin-bottom: 14px;
}

.network-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(330px, 1fr));
    gap: 12px;
}

.network-card {
    border: 1px solid var(--border-soft);
    border-left-width: 4px;
    border-radius: 10px;
    background: var(--surface);
    overflow: hidden;
}

.network-card.network-active {
    border-left-color: var(--success);
}

.network-card.network-inactive {
    border-left-color: #8a949e;
}

.network-card-head {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    padding: 14px;
    background: var(--surface-soft);
    border-bottom: 1px solid var(--border-soft);
}

.network-type {
    color: var(--accent);
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: .06em;
}

.network-name {
    font-size: 16px;
    font-weight: 650;
    margin-top: 2px;
}

.network-description {
    color: var(--muted);
    font-size: 11px;
    margin-top: 3px;
    max-width: 520px;
}

.network-state {
    height: fit-content;
    padding: 3px 8px;
    border-radius: 999px;
    background: var(--neutral-soft);
    color: #59636d;
    font-size: 11px;
    font-weight: 700;
}

.network-active .network-state {
    background: var(--success-soft);
    color: var(--success);
}

.network-details {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
    padding: 12px;
}

.item {
    background: var(--surface-soft);
    border: 1px solid var(--border-soft);
    border-radius: 8px;
    padding: 9px 11px;
    min-width: 0;
}

.label {
    color: var(--muted);
    font-size: 10px;
    font-weight: 650;
    letter-spacing: .04em;
    text-transform: uppercase;
}

.value {
    font-size: 14px;
    font-weight: 600;
    margin-top: 3px;
    overflow-wrap: anywhere;
}

.subsection + .subsection {
    margin-top: 20px;
}

h3 {
    font-size: 13px;
    margin: 0 0 8px;
    color: #3a4651;
}

.table-wrap {
    width: 100%;
    overflow-x: auto;
    border: 1px solid var(--border-soft);
    border-radius: 8px;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: var(--surface);
    font-size: 12px;
}

th,
td {
    padding: 8px 9px;
    text-align: left;
    vertical-align: top;
    border-bottom: 1px solid var(--border-soft);
    white-space: normal;
    overflow-wrap: anywhere;
}

th {
    position: sticky;
    top: 0;
    background: #eef2f5;
    color: #46515c;
    font-size: 10px;
    letter-spacing: .035em;
    text-transform: uppercase;
}

tbody tr:last-child td {
    border-bottom: 0;
}

tbody tr:hover {
    background: #fafcfd;
}

.muted {
    color: var(--muted);
    font-weight: 400;
}

.status {
    display: inline-block;
    border-radius: 999px;
    padding: 2px 7px;
    font-size: 11px;
    font-weight: 650;
}

.status-ok {
    color: var(--success);
    background: var(--success-soft);
}

.status-neutral {
    color: #59636d;
    background: var(--neutral-soft);
}

.empty-state {
    border: 1px dashed var(--border);
    border-radius: 8px;
    padding: 18px;
    text-align: center;
    color: var(--muted);
    background: var(--surface-soft);
}

.footer {
    color: var(--muted);
    font-size: 11px;
    text-align: center;
    margin-top: 18px;
}

@media (max-width: 720px) {
    .container {
        width: min(100% - 18px, 1500px);
        margin-top: 10px;
    }

    .hero {
        padding: 18px;
    }

    .hero-top {
        display: block;
    }

    .hero-host {
        text-align: left;
        margin-top: 14px;
    }

    .section-content {
        padding: 12px;
    }

    .grid {
        grid-template-columns: 1fr 1fr;
    }

    .network-grid {
        grid-template-columns: 1fr;
    }
}

@media (max-width: 480px) {
    .grid,
    .network-details {
        grid-template-columns: 1fr;
    }
}

@media print {
    body {
        background: #fff;
    }

    .container {
        width: 100%;
        margin: 0;
    }

    .toolbar {
        display: none;
    }

    .hero,
    .section {
        box-shadow: none;
        break-inside: avoid;
    }

    .section {
        margin: 8px 0;
    }

    details:not([open]) > .section-content {
        display: block;
    }

    .table-wrap {
        overflow: visible;
    }

    th {
        position: static;
    }
}
</style>
</head>
<body>
<div class="container">
    <header class="hero">
        <div class="hero-top">
            <div>
                <h1>Inventario de hardware</h1>
                <div class="hero-subtitle">
                    Generado: $(ConvertTo-HtmlSafe $Inventory.Collection.CollectedAt)
                    · Modo: $(ConvertTo-HtmlSafe $Inventory.Collection.Mode)
                </div>
            </div>
            <div class="hero-host">
                <div class="hostname">$(ConvertTo-HtmlSafe $computer.Hostname)</div>
                <div class="model">
                    $(ConvertTo-HtmlSafe $computer.Manufacturer)
                    $(ConvertTo-HtmlSafe $computer.Model)
                </div>
            </div>
        </div>

        <div class="toolbar">
            <button type="button" onclick="setAllSections(true)">Expandir todo</button>
            <button type="button" onclick="setAllSections(false)">Contraer todo</button>
            <button type="button" onclick="window.print()">Imprimir</button>
        </div>
    </header>

    <main>
        $sections
    </main>

    <div class="footer">
        Esquema $(ConvertTo-HtmlSafe $Inventory.SchemaVersion)
        · Ejecutado por $(ConvertTo-HtmlSafe $Inventory.Collection.ScriptUser)
    </div>
</div>

<script>
function setAllSections(openState) {
    document.querySelectorAll("details.section").forEach(function(section) {
        section.open = openState;
    });
}
</script>
</body>
</html>
"@

    Set-Content -LiteralPath $Path -Value $html -Encoding UTF8
}
