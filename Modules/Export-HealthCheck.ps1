function New-HealthCheckHtml {
 [CmdletBinding(SupportsShouldProcess)]
 param([Parameter(Mandatory)][object]$Report,[Parameter(Mandatory)][string]$Path)
 function Encode([object]$Value){return [System.Net.WebUtility]::HtmlEncode([string]$Value)}
 $findings=@($Report.HealthCheck.Findings|ForEach-Object{"<tr><td>$(Encode $_.Id)</td><td>$(Encode $_.Category)</td><td>$(Encode $_.Severity)</td></tr>"})-join''
 $html=@"
<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Windows Health Check</title><style>body{font-family:Segoe UI,Arial;margin:2rem;color:#172033}.cards{display:flex;gap:1rem}.card{padding:1rem;border:1px solid #d8deea;border-radius:.7rem}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border-bottom:1px solid #ddd}</style></head><body>
<h1>Windows Performance Health Check</h1><p>Equipo: $(Encode $Report.Computer.Hostname)</p>
<div class="cards"><div class="card"><strong>Health Score</strong><div>$(Encode $Report.HealthCheck.Score.Value)</div></div><div class="card"><strong>Status</strong><div>$(Encode $Report.HealthCheck.Score.Status)</div></div><div class="card"><strong>Confidence</strong><div>$(Encode $Report.HealthCheck.Score.ConfidencePercent)%</div></div><div class="card"><strong>Primary Bottleneck</strong><div>$(Encode $Report.HealthCheck.PrimaryBottleneck)</div></div></div>
<h2>Hallazgos</h2><table><thead><tr><th>ID</th><th>Categoría</th><th>Severidad</th></tr></thead><tbody>$findings</tbody></table>
<h2>Métricas</h2><p>CPU promedio: $(Encode $Report.HealthCheck.Metrics.CPU.AverageUsagePercent)%</p><p>Memoria promedio: $(Encode $Report.HealthCheck.Metrics.Memory.AverageUsagePercent)%</p>
</body></html>
"@
 if($PSCmdlet.ShouldProcess($Path,'Write health-check HTML report')){$html|Set-Content -LiteralPath $Path -Encoding UTF8}
}
