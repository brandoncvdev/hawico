$ErrorActionPreference = "Continue"

$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$report = Join-Path $basePath "Logs\diagnostico-inicio.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $report -Parent) | Out-Null

"Diagnóstico del recolector" | Set-Content $report -Encoding UTF8
"Fecha: $(Get-Date -Format o)" | Add-Content $report
"PowerShell: $($PSVersionTable.PSVersion)" | Add-Content $report
"Sistema: $([Environment]::OSVersion.VersionString)" | Add-Content $report
"Ruta base: $basePath" | Add-Content $report
"" | Add-Content $report

$files = @(
    "config.json",
    "Start-Inventory.ps1",
    "Collector_Hardware_Inventory.ps1",
    "Modules\Common.ps1"
)

foreach ($file in $files) {
    $path = Join-Path $basePath $file
    "{0}: {1}" -f $file, (Test-Path -LiteralPath $path) | Add-Content $report
}

Write-Host "Diagnóstico generado:"
Write-Host $report
Read-Host "Presione Enter para cerrar"
