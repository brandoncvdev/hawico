function Convert-BytesToGB {
    param([AllowNull()][object]$Bytes)
    if ($null -eq $Bytes) { return $null }
    try { return [math]::Round(([double]$Bytes / 1GB), 2) } catch { return $null }
}

function Convert-KBToGB {
    param([AllowNull()][object]$Kilobytes)
    if ($null -eq $Kilobytes) { return $null }
    try { return [math]::Round(([double]$Kilobytes / 1MB), 2) } catch { return $null }
}

function Convert-CimDate {
    param([AllowNull()][object]$Date)
    if ($null -eq $Date) { return $null }
    try { return ([datetime]$Date).ToString("o") }
    catch {
        try { return $Date.ToString() } catch { return $null }
    }
}

function Get-SafeString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Get-CollectorVersion {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [string]$DefaultVersion = '0.0.0'
    )

    $manifestPath = Join-Path $BasePath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return $DefaultVersion
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning ("No se pudo leer manifest.json: {0}" -f $_.Exception.Message)
        return $DefaultVersion
    }

    $version = Get-SafeString $manifest.CollectorVersion
    if ($null -eq $version) {
        return $DefaultVersion
    }

    return $version
}

function Resolve-InventoryManualFieldKeys {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Resolves an in-memory field-key list without changing system state.'
    )]
    param(
        [AllowNull()][string[]]$PassedKeys,
        [AllowNull()][object[]]$ConfigManualFields
    )

    # Every branch below is reached through `return`, so every array value
    # must cross the output stream through a leading unary comma — the same
    # guard `return @(...)` needed elsewhere, here applied explicitly per
    # branch instead of via `$var = if (...) {...} else {...}` (that
    # assignment-from-a-statement-block form has the identical hazard and is
    # what broke the collector on real Windows PowerShell 5.1: each branch's
    # trailing value crosses the same output stream a `return` does).
    if ($null -ne $PassedKeys) {
        return ,@($PassedKeys)
    }

    $fallbackManualFieldKeys = @()
    if ($null -ne $ConfigManualFields) {
        $fallbackManualFieldKeys = @($ConfigManualFields)
    }

    return ,$fallbackManualFieldKeys
}

function Resolve-InventoryOrganizationUnits {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Resolves an in-memory organization-unit list without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$PassedUnits
    )

    if ($null -ne $PassedUnits) {
        return ,@($PassedUnits)
    }

    return ,@()
}

function Install-InventoryImportExcelIfNeeded {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Installing a PowerShell module on user consent is this function''s explicit purpose.'
    )]
    param(
        [scriptblock]$IsAvailable = { [bool](Get-Module -ListAvailable -Name ImportExcel) },
        [scriptblock]$Confirm = { param($Prompt) Read-Host $Prompt },
        [scriptblock]$Installer = { Install-Module ImportExcel -Scope CurrentUser -Force -ErrorAction Stop }
    )

    if (& $IsAvailable) {
        return $true
    }

    $answer = & $Confirm 'El módulo ImportExcel no está instalado. ¿Instalarlo ahora? (S/N)'
    $normalizedAnswer = Get-SafeString $answer

    if ($null -eq $normalizedAnswer -or $normalizedAnswer -notmatch '^[sS]') {
        return $false
    }

    try {
        & $Installer | Out-Null
    }
    catch {
        Write-Host ("No se pudo instalar ImportExcel: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }

    # Re-check instead of assuming success just because no exception was
    # thrown — Install-Module can silently no-op in some environments.
    return [bool](& $IsAvailable)
}

function Get-CimDataSafe {
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Filter,
        [string]$Namespace = "root/cimv2"
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Filter)) {
            return ,@(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop)
        }

        return ,@(
            Get-CimInstance -Namespace $Namespace -ClassName $ClassName `
                -Filter $Filter -ErrorAction Stop
        )
    }
    catch {
        Write-Warning ("No se pudo consultar {0}: {1}" -f $ClassName, $_.Exception.Message)
        return ,@()
    }
}

function Get-MemoryTypeName {
    param([AllowNull()][object]$SMBIOSMemoryType)

    $types = @{
        20 = "DDR"; 21 = "DDR2"; 22 = "DDR2 FB-DIMM"; 24 = "DDR3"
        26 = "DDR4"; 27 = "LPDDR"; 28 = "LPDDR2"; 29 = "LPDDR3"
        30 = "LPDDR4"; 34 = "DDR5"; 35 = "LPDDR5"
    }

    if ($null -eq $SMBIOSMemoryType) { return "Desconocido" }
    $value = [int]$SMBIOSMemoryType
    if ($types.ContainsKey($value)) { return $types[$value] }
    return "Desconocido ($value)"
}

function Get-SystemSlotUsageName {
    param([AllowNull()][object]$CurrentUsage)

    $values = @{
        1 = "Otro"
        2 = "Desconocido"
        3 = "Disponible"
        4 = "En uso"
        5 = "No disponible"
    }

    if ($null -eq $CurrentUsage) { return "Desconocido" }
    $value = [int]$CurrentUsage
    if ($values.ContainsKey($value)) { return $values[$value] }
    return "Desconocido ($value)"
}

function Get-InventoryHostOutputDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Computes an in-memory path without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BaseOutputDirectory,
        [Parameter(Mandatory)][string]$Hostname
    )

    # Every artifact for one computer (inventory JSON/HTML, record.json,
    # health-check JSON/HTML) lands under the same per-hostname subfolder
    # instead of flat in OutputDirectory — grouping a machine's whole history
    # together and cutting the clutter of one giant folder with every
    # machine's files interleaved. Both collectors already sanitize the
    # hostname before calling this, so it stays a pure Join-Path wrapper
    # instead of duplicating that sanitization here.
    return Join-Path $BaseOutputDirectory $Hostname
}
