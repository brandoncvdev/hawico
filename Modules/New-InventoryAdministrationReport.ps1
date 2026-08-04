function New-InventoryAdministrationReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Writing the administration report to disk is this function''s purpose.'
    )]
    param(
        [Parameter(Mandatory)][object]$ImportResult,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $nuevosEquipos = @($ImportResult.NuevosEquipos)
    $equiposActualizados = @($ImportResult.EquiposActualizados)
    $posiblesDuplicados = @($ImportResult.PosiblesDuplicados)
    $conflictos = @($ImportResult.Conflictos)
    $erroresRecoleccion = @($ImportResult.ErroresRecoleccion)
    $skippedFiles = @($ImportResult.SkippedFiles)

    $sections = ""

    $sections += New-InventorySection `
        -Title "Nuevos equipos" `
        -Subtitle "Activos con identidad fuerte que no existían en la administración" `
        -Content (New-InventoryTable -Rows $nuevosEquipos -Columns ([ordered]@{
            "AssetId" = "AssetId"
            "CollectionId" = "CollectionId"
            "Equipo" = "ComputerName"
            "Sesión" = "SessionId"
        }) -EmptyMessage "Sin elementos") `
        -Badge "$($nuevosEquipos.Count)" `
        -Open $true

    $sections += New-InventorySection `
        -Title "Equipos actualizados" `
        -Subtitle "Activos existentes que recibieron una nueva captura" `
        -Content (New-InventoryTable -Rows $equiposActualizados -Columns ([ordered]@{
            "AssetId" = "AssetId"
            "CollectionId" = "CollectionId"
            "Equipo" = "ComputerName"
            "Sesión" = "SessionId"
        }) -EmptyMessage "Sin elementos") `
        -Badge "$($equiposActualizados.Count)" `
        -Open $true

    $sections += New-InventorySection `
        -Title "Posibles duplicados" `
        -Subtitle "Sin identidad fuerte (serie o UUID); requieren revisión manual antes de crear un activo" `
        -Content (New-InventoryTable -Rows $posiblesDuplicados -Columns ([ordered]@{
            "CollectionId" = "CollectionId"
            "Equipo" = "ComputerName"
            "Sesión" = "SessionId"
        }) -EmptyMessage "Sin elementos") `
        -Badge "$($posiblesDuplicados.Count)" `
        -Open ($posiblesDuplicados.Count -gt 0)

    $sections += New-InventorySection `
        -Title "Conflictos" `
        -Subtitle "Un campo manual ya tenía un valor distinto; el valor existente no se sobrescribió" `
        -Content (New-InventoryTable -Rows $conflictos -Columns ([ordered]@{
            "AssetId" = "AssetId"
            "Campo" = "Key"
            "Valor actual" = "ValorActual"
            "Valor nuevo" = "ValorNuevo"
            "CollectionId" = "CollectionId"
        }) -EmptyMessage "Sin elementos") `
        -Badge "$($conflictos.Count)" `
        -Open ($conflictos.Count -gt 0)

    $sections += New-InventorySection `
        -Title "Errores de recolección" `
        -Subtitle "Registros con errores reportados por el recolector" `
        -Content (New-InventoryTable -Rows $erroresRecoleccion -Columns ([ordered]@{
            "CollectionId" = "CollectionId"
            "Equipo" = "ComputerName"
            "Errores" = "Errors"
        }) -EmptyMessage "Sin elementos") `
        -Badge "$($erroresRecoleccion.Count)" `
        -Open ($erroresRecoleccion.Count -gt 0)

    $sections += New-InventorySection `
        -Title "Archivos omitidos" `
        -Subtitle "Archivos *-record.json que no se pudieron interpretar como JSON válido" `
        -Content (New-InventoryTable -Rows $skippedFiles -Columns ([ordered]@{
            "Ruta" = "Path"
            "Error" = "Error"
        }) -EmptyMessage "Sin elementos") `
        -Badge "$($skippedFiles.Count)" `
        -Open ($skippedFiles.Count -gt 0)

    $generatedAt = [datetimeoffset]::Now

    # Same style system as Modules/Export.ps1's New-InventoryHtml (CSS
    # variables, .hero/.section/.table-wrap/.badge/.empty-state classes) so
    # this report feels like part of the same product instead of a new
    # design.
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Administración de inventario - Importación</title>
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

    .section-content {
        padding: 12px;
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
                <h1>Administración de inventario</h1>
                <div class="hero-subtitle">
                    Reporte de importación · Generado: $(ConvertTo-HtmlSafe ($generatedAt.ToString('o')))
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
        Reporte de administración local · Hardware Inventory Collector
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

    Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8

    return $OutputPath
}
