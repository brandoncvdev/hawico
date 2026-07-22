function New-HealthCheckHtml {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][object]$Report, [Parameter(Mandatory)][string]$Path)

    function ConvertTo-EncodedHtmlValue {
        param([AllowNull()][object]$Value)
        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }

    function Get-HealthHtmlProperty {
        param([AllowNull()][object]$Object, [string]$Name, [AllowNull()][object]$DefaultValue = $null)
        if ($null -eq $Object) { return $DefaultValue }
        if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
        if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
        return $DefaultValue
    }

    function ConvertTo-HealthDisplayValue {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'No disponible' }
        return [string]$Value
    }

    $computer = Get-HealthHtmlProperty -Object $Report -Name 'Computer' -DefaultValue @{}
    $collection = Get-HealthHtmlProperty -Object $Report -Name 'Collection' -DefaultValue @{}
    $health = Get-HealthHtmlProperty -Object $Report -Name 'HealthCheck' -DefaultValue @{}
    $score = Get-HealthHtmlProperty -Object $health -Name 'Score' -DefaultValue @{}
    $metrics = Get-HealthHtmlProperty -Object $health -Name 'Metrics' -DefaultValue @{}
    $cpu = Get-HealthHtmlProperty -Object $metrics -Name 'CPU' -DefaultValue @{}
    $memory = Get-HealthHtmlProperty -Object $metrics -Name 'Memory' -DefaultValue @{}
    $storage = Get-HealthHtmlProperty -Object $metrics -Name 'Storage' -DefaultValue @{}
    $events = @(Get-HealthHtmlProperty -Object $metrics -Name 'Events' -DefaultValue @())

    $findingRows = @(Get-HealthHtmlProperty -Object $health -Name 'Findings' -DefaultValue @() | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><strong>{3}</strong><br>{4}</td></tr>' -f (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Id')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Category')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Severity')), (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Title')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Description'))
    }) -join ''
    $recommendationRows = @(Get-HealthHtmlProperty -Object $health -Name 'Recommendations' -DefaultValue @() | ForEach-Object {
        '<tr><td>{0}</td><td><strong>{1}</strong><br>{2}</td><td>{3}</td></tr>' -f (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Id')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Title')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Description')), (
            ConvertTo-EncodedHtmlValue (@(Get-HealthHtmlProperty -Object $_ -Name 'FindingIds' -DefaultValue @()) -join ', '))
    }) -join ''
    $diskRows = @(Get-HealthHtmlProperty -Object $storage -Name 'PhysicalDisks' -DefaultValue @() | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Name')), (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'MediaType')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'HealthStatus'))
    }) -join ''
    $volumeRows = @(Get-HealthHtmlProperty -Object $storage -Name 'Volumes' -DefaultValue @() | ForEach-Object {
        '<tr><td>{0}</td><td>{1}%</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Drive')), (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'FreePercent')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'IsSystemVolume'))
    }) -join ''
    $eventRows = @($events | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Provider')), (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Id')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'OccurrenceCount'))
    }) -join ''
    $sectionRows = @(Get-HealthHtmlProperty -Object $health -Name 'Sections' -DefaultValue @() | Where-Object { (Get-HealthHtmlProperty -Object $_ -Name 'Status') -ne 'Collected' } | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Name')), (
            ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'Status')), (ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $_ -Name 'ErrorMessage'))
    }) -join ''

    $html = @"
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Windows Health Check</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:2rem;color:#172033;background:#f6f8fb}main{max-width:1100px;margin:auto}.cards{display:flex;flex-wrap:wrap;gap:1rem}.card{padding:1rem;background:white;border:1px solid #d8deea;border-radius:.7rem;min-width:150px}section{margin-top:1.5rem;padding:1rem;background:white;border-radius:.7rem}table{border-collapse:collapse;width:100%}td,th{padding:.55rem;text-align:left;border-bottom:1px solid #ddd}.muted{color:#596579}</style></head>
<body><main>
<h1>Windows Performance Health Check</h1>
<p>Equipo: $(ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $computer -Name 'Hostname' -DefaultValue 'No disponible')) · Fecha: $(ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $collection -Name 'CollectedAt' -DefaultValue 'No disponible'))</p>
<div class="cards"><div class="card"><strong>Health Score</strong><div>$(ConvertTo-EncodedHtmlValue (ConvertTo-HealthDisplayValue (Get-HealthHtmlProperty -Object $score -Name 'Value')))</div></div><div class="card"><strong>Estado</strong><div>$(ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $health -Name 'Status' -DefaultValue 'Failed'))</div></div><div class="card"><strong>Clasificación</strong><div>$(ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $score -Name 'Status' -DefaultValue 'InsufficientData'))</div></div><div class="card"><strong>Confianza</strong><div>$(ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $score -Name 'ConfidencePercent' -DefaultValue 0))%</div></div><div class="card"><strong>Cuello de botella</strong><div>$(ConvertTo-EncodedHtmlValue (Get-HealthHtmlProperty -Object $health -Name 'PrimaryBottleneck' -DefaultValue 'Unknown'))</div></div></div>
<section><h2>Hallazgos</h2><table><thead><tr><th>ID</th><th>Categoría</th><th>Severidad</th><th>Detalle</th></tr></thead><tbody>$findingRows</tbody></table></section>
<section><h2>CPU y memoria</h2><p>CPU promedio: $(ConvertTo-EncodedHtmlValue (ConvertTo-HealthDisplayValue (Get-HealthHtmlProperty -Object $cpu -Name 'AverageUsagePercent')))% · CPU máximo: $(ConvertTo-EncodedHtmlValue (ConvertTo-HealthDisplayValue (Get-HealthHtmlProperty -Object $cpu -Name 'PeakUsagePercent')))%</p><p>Memoria promedio: $(ConvertTo-EncodedHtmlValue (ConvertTo-HealthDisplayValue (Get-HealthHtmlProperty -Object $memory -Name 'AverageUsagePercent')))% · Memoria mínima disponible: $(ConvertTo-EncodedHtmlValue (ConvertTo-HealthDisplayValue (Get-HealthHtmlProperty -Object $memory -Name 'MinimumAvailableMB'))) MB</p></section>
<section><h2>Discos físicos</h2><table><thead><tr><th>Disco</th><th>Medio</th><th>Salud</th></tr></thead><tbody>$diskRows</tbody></table><h3>Volúmenes</h3><table><thead><tr><th>Volumen</th><th>Libre</th><th>Sistema</th></tr></thead><tbody>$volumeRows</tbody></table></section>
<section><h2>Eventos</h2><table><thead><tr><th>Proveedor</th><th>ID</th><th>Ocurrencias</th></tr></thead><tbody>$eventRows</tbody></table></section>
<section><h2>Recomendaciones</h2><table><thead><tr><th>ID</th><th>Acción</th><th>Hallazgos</th></tr></thead><tbody>$recommendationRows</tbody></table></section>
<section><h2>Secciones omitidas o incompletas</h2><table><thead><tr><th>Sección</th><th>Estado</th><th>Detalle</th></tr></thead><tbody>$sectionRows</tbody></table></section>
</main></body></html>
"@
    if ($PSCmdlet.ShouldProcess($Path, 'Write health-check HTML report')) {
        $html | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}
