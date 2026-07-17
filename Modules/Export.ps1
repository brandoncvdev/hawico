function ConvertTo-HtmlSafe {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Value.ToString())
}

function New-InventoryHtml {
    param(
        [Parameter(Mandatory)][hashtable]$Inventory,
        [Parameter(Mandatory)][string]$Path
    )

    $computer = $Inventory.Computer
    $memory = $Inventory.Memory.Upgrade
    $networkRows = ""

    foreach ($adapter in @($Inventory.NetworkAdapters)) {
        $networkRows += @"
<tr>
<td>$(ConvertTo-HtmlSafe $adapter.InterfaceAlias)</td>
<td>$(ConvertTo-HtmlSafe (($adapter.IPv4Addresses -join ", ")))</td>
<td>$(ConvertTo-HtmlSafe (($adapter.IPv4Gateways -join ", ")))</td>
<td>$(ConvertTo-HtmlSafe (($adapter.DNSServers -join ", ")))</td>
</tr>
"@
    }

    $diskRows = ""
    foreach ($disk in @($Inventory.Storage.Physical)) {
        $diskRows += @"
<tr>
<td>$(ConvertTo-HtmlSafe $disk.Model)</td>
<td>$(ConvertTo-HtmlSafe $disk.InterfaceType)</td>
<td>$(ConvertTo-HtmlSafe $disk.SizeGB) GB</td>
<td>$(ConvertTo-HtmlSafe $disk.Status)</td>
</tr>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Inventario - $(ConvertTo-HtmlSafe $computer.Hostname)</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 30px; background: #f4f6f8; color: #222; }
h1 { margin-bottom: 5px; }
h2 { margin-top: 28px; border-bottom: 2px solid #ccd3da; padding-bottom: 6px; }
.card { background: white; border-radius: 10px; padding: 18px; margin: 12px 0; box-shadow: 0 2px 7px rgba(0,0,0,.08); }
.grid { display: grid; grid-template-columns: repeat(auto-fit,minmax(220px,1fr)); gap: 12px; }
.item { background: #f9fafb; padding: 12px; border-radius: 8px; }
.label { font-size: 12px; color: #667; text-transform: uppercase; }
.value { font-size: 18px; font-weight: 600; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; background: white; }
th, td { border-bottom: 1px solid #ddd; padding: 10px; text-align: left; }
th { background: #eef2f5; }
.note { font-size: 13px; color: #667; }
</style>
</head>
<body>
<h1>Inventario de hardware</h1>
<div class="note">Generado: $(ConvertTo-HtmlSafe $Inventory.Collection.CollectedAt)</div>

<h2>Equipo</h2>
<div class="card grid">
<div class="item"><div class="label">Nombre</div><div class="value">$(ConvertTo-HtmlSafe $computer.Hostname)</div></div>
<div class="item"><div class="label">Fabricante</div><div class="value">$(ConvertTo-HtmlSafe $computer.Manufacturer)</div></div>
<div class="item"><div class="label">Modelo</div><div class="value">$(ConvertTo-HtmlSafe $computer.Model)</div></div>
<div class="item"><div class="label">Serie BIOS</div><div class="value">$(ConvertTo-HtmlSafe $Inventory.BIOS.SerialNumber)</div></div>
</div>

<h2>Memoria</h2>
<div class="card grid">
<div class="item"><div class="label">Instalada</div><div class="value">$(ConvertTo-HtmlSafe $memory.InstalledMemoryGB) GB</div></div>
<div class="item"><div class="label">Máxima reportada</div><div class="value">$(ConvertTo-HtmlSafe $memory.MaximumReportedGB) GB</div></div>
<div class="item"><div class="label">Slots ocupados</div><div class="value">$(ConvertTo-HtmlSafe $memory.OccupiedSlots)</div></div>
<div class="item"><div class="label">Slots disponibles</div><div class="value">$(ConvertTo-HtmlSafe $memory.AvailableSlots)</div></div>
</div>

<h2>Red</h2>
<table>
<tr><th>Adaptador</th><th>IPv4</th><th>Gateway</th><th>DNS</th></tr>
$networkRows
</table>

<h2>Almacenamiento</h2>
<table>
<tr><th>Modelo</th><th>Interfaz</th><th>Capacidad</th><th>Estado</th></tr>
$diskRows
</table>
</body>
</html>
"@

    Set-Content -LiteralPath $Path -Value $html -Encoding UTF8
}
