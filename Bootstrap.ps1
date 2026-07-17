$ErrorActionPreference = "Stop"

$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$logsPath = Join-Path $basePath "Logs"
$startupLog = Join-Path $logsPath "startup-error.txt"
$menuScript = Join-Path $basePath "Start-Inventory.ps1"

New-Item -ItemType Directory -Force -Path $logsPath | Out-Null

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

try {
    if (-not (Test-IsAdministrator)) {
        Write-Host ""
        Write-Host "Se requieren permisos de administrador." -ForegroundColor Yellow
        Write-Host "Acepte la ventana de Control de cuentas de usuario." -ForegroundColor Yellow
        Write-Host ""

        $arguments = @(
            "-NoLogo"
            "-NoProfile"
            "-ExecutionPolicy"
            "Bypass"
            "-NoExit"
            "-File"
            ('"{0}"' -f $MyInvocation.MyCommand.Path)
        )

        Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList ($arguments -join " ") `
            -WorkingDirectory $basePath `
            -Verb RunAs

        Write-Host "La ventana con permisos se abrió por separado."
        Write-Host "Esta ventana puede cerrarse."
        return
    }

    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " INICIANDO RECOLECTOR DE INVENTARIO TI" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Ruta: $basePath"
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host ""

    if (-not (Test-Path -LiteralPath $menuScript)) {
        throw "No se encontró Start-Inventory.ps1 en: $menuScript"
    }

    & $menuScript
}
catch {
    $details = @"
Fecha: $(Get-Date -Format o)
Mensaje: $($_.Exception.Message)
Tipo: $($_.Exception.GetType().FullName)
Archivo: $($_.InvocationInfo.ScriptName)
Línea: $($_.InvocationInfo.ScriptLineNumber)
Comando: $($_.InvocationInfo.Line)
PowerShell: $($PSVersionTable.PSVersion)
Ruta base: $basePath

Error completo:
$($_ | Out-String)
"@

    $details | Set-Content -LiteralPath $startupLog -Encoding UTF8

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " ERROR AL INICIAR EL RECOLECTOR" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "El detalle se guardó en:"
    Write-Host $startupLog -ForegroundColor Yellow
    Write-Host ""
    Write-Host "La ventana permanecerá abierta." -ForegroundColor Yellow
}
