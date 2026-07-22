function New-HealthCheckHtml {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][object]$Report, [Parameter(Mandatory)][string]$Path)

    function ConvertTo-EncodedHtmlValue {
        param([AllowNull()][object]$Value)
        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }

    $findingRows = @($Report.HealthCheck.Findings | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><strong>{3}</strong><br>{4}</td></tr>' -f (
            ConvertTo-EncodedHtmlValue $_.Id), (ConvertTo-EncodedHtmlValue $_.Category), (ConvertTo-EncodedHtmlValue $_.Severity), (
            ConvertTo-EncodedHtmlValue $_.Title), (ConvertTo-EncodedHtmlValue $_.Description)
    }) -join ''
    $recommendationRows = @($Report.HealthCheck.Recommendations | ForEach-Object {
        '<tr><td>{0}</td><td><strong>{1}</strong><br>{2}</td><td>{3}</td></tr>' -f (
            ConvertTo-EncodedHtmlValue $_.Id), (ConvertTo-EncodedHtmlValue $_.Title), (ConvertTo-EncodedHtmlValue $_.Description), (
            ConvertTo-EncodedHtmlValue (@($_.FindingIds) -join ', '))
    }) -join ''
    $diskRows = @($Report.HealthCheck.Metrics.Storage.PhysicalDisks | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue $_.Name), (
            ConvertTo-EncodedHtmlValue $_.MediaType), (ConvertTo-EncodedHtmlValue $_.HealthStatus)
    }) -join ''
    $volumeRows = @($Report.HealthCheck.Metrics.Storage.Volumes | ForEach-Object {
        '<tr><td>{0}</td><td>{1}%</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue $_.Drive), (
            ConvertTo-EncodedHtmlValue $_.FreePercent), (ConvertTo-EncodedHtmlValue $_.IsSystemVolume)
    }) -join ''
    $eventRows = @($Report.HealthCheck.Metrics.Events | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue $_.Provider), (
            ConvertTo-EncodedHtmlValue $_.Id), (ConvertTo-EncodedHtmlValue $_.OccurrenceCount)
    }) -join ''
    $sectionRows = @($Report.HealthCheck.Sections | Where-Object Status -ne 'Collected' | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-EncodedHtmlValue $_.Name), (
            ConvertTo-EncodedHtmlValue $_.Status), (ConvertTo-EncodedHtmlValue $_.ErrorMessage)
    }) -join ''

    $html = @"
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Windows Health Check</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:2rem;color:#172033;background:#f6f8fb}main{max-width:1100px;margin:auto}.cards{display:flex;flex-wrap:wrap;gap:1rem}.card{padding:1rem;background:white;border:1px solid #d8deea;border-radius:.7rem;min-width:150px}section{margin-top:1.5rem;padding:1rem;background:white;border-radius:.7rem}table{border-collapse:collapse;width:100%}td,th{padding:.55rem;text-align:left;border-bottom:1px solid #ddd}.muted{color:#596579}</style></head>
<body><main>
<h1>Windows Performance Health Check</h1>
<p>Equipo: $(ConvertTo-EncodedHtmlValue $Report.Computer.Hostname) · Fecha: $(ConvertTo-EncodedHtmlValue $Report.Collection.CollectedAt)</p>
<div class="cards"><div class="card"><strong>Health Score</strong><div>$(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Score.Value)</div></div><div class="card"><strong>Estado</strong><div>$(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Status)</div></div><div class="card"><strong>Clasificación</strong><div>$(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Score.Status)</div></div><div class="card"><strong>Confianza</strong><div>$(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Score.ConfidencePercent)%</div></div><div class="card"><strong>Cuello de botella</strong><div>$(ConvertTo-EncodedHtmlValue $Report.HealthCheck.PrimaryBottleneck)</div></div></div>
<section><h2>Hallazgos</h2><table><thead><tr><th>ID</th><th>Categoría</th><th>Severidad</th><th>Detalle</th></tr></thead><tbody>$findingRows</tbody></table></section>
<section><h2>CPU y memoria</h2><p>CPU promedio: $(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Metrics.CPU.AverageUsagePercent)% · CPU máximo: $(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Metrics.CPU.PeakUsagePercent)%</p><p>Memoria promedio: $(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Metrics.Memory.AverageUsagePercent)% · Memoria mínima disponible: $(ConvertTo-EncodedHtmlValue $Report.HealthCheck.Metrics.Memory.MinimumAvailableMB) MB</p></section>
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
