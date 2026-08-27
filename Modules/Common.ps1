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

function Get-InventorySanitizedDisplayName {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Sanitizes an in-memory string without changing system state.'
    )]
    param(
        [AllowNull()][string]$DisplayName
    )

    $trimmed = Get-SafeString $DisplayName
    if ($null -eq $trimmed) {
        return $null
    }

    # Strip characters invalid in Windows paths (\ / : * ? " < > |) and
    # collapse internal whitespace runs, so a captured "Juan   Perez" (or one
    # containing a stray path separator) never produces an unreadable or
    # accidentally-nested folder name.
    $stripped = $trimmed -replace '[\\/:*?"<>|]', ''
    $collapsed = ($stripped -replace '\s+', ' ').Trim()

    if ([string]::IsNullOrWhiteSpace($collapsed)) {
        return $null
    }

    return $collapsed
}

function Resolve-InventoryHostOutputDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads existing directory names without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BaseOutputDirectory,
        [Parameter(Mandatory)][string]$Hostname
    )

    # Read-only lookup for a host folder already on disk under
    # $BaseOutputDirectory — either the legacy hostname-only name, or a
    # "$Hostname - DisplayName" folder (Get-InventoryHostOutputDirectory
    # below). Anchored on the FULL hostname followed by either end-of-string
    # or a literal " - " separator, so e.g. hostname "PC1" can never match a
    # folder named "PC10 - Someone".
    if (-not (Test-Path -LiteralPath $BaseOutputDirectory)) {
        return $null
    }

    try {
        $candidates = @(
            Get-ChildItem -LiteralPath $BaseOutputDirectory -Directory -ErrorAction Stop
        )
    }
    catch {
        Write-Warning ("No se pudo leer la carpeta de salida: {0}" -f $_.Exception.Message)
        return $null
    }

    $displayNamePrefix = "$Hostname - "
    $match = $candidates | Where-Object {
        $_.Name -eq $Hostname -or $_.Name.StartsWith($displayNamePrefix, [StringComparison]::Ordinal)
    } | Select-Object -First 1

    if ($null -eq $match) {
        return $null
    }

    return $match.FullName
}

function Get-InventoryHostOutputDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Renaming an existing host folder to keep its display-name suffix in sync is the whole point of this function; it is not exposed as a general-purpose destructive operation.'
    )]
    param(
        [Parameter(Mandatory)][string]$BaseOutputDirectory,
        [Parameter(Mandatory)][string]$Hostname,
        [AllowNull()][string]$DisplayName = $null
    )

    # Every artifact for one computer (inventory JSON/HTML, record.json,
    # health-check JSON/HTML) lands under the same per-hostname subfolder
    # instead of flat in OutputDirectory — grouping a machine's whole history
    # together and cutting the clutter of one giant folder with every
    # machine's files interleaved. Both collectors already sanitize the
    # hostname before calling this, so it stays a pure Join-Path wrapper
    # instead of duplicating that sanitization here.
    $sanitizedDisplayName = Get-InventorySanitizedDisplayName -DisplayName $DisplayName
    $existingDirectory = Resolve-InventoryHostOutputDirectory `
        -BaseOutputDirectory $BaseOutputDirectory -Hostname $Hostname

    if ($null -ne $existingDirectory) {
        # -DisplayName $null/empty/whitespace (the field was skipped this
        # visit) never strips an existing suffix back off — the folder is
        # returned exactly as it is.
        if ($null -eq $sanitizedDisplayName) {
            return $existingDirectory
        }

        $desiredDirectory = Join-Path $BaseOutputDirectory "$Hostname - $sanitizedDisplayName"
        if ($existingDirectory -eq $desiredDirectory) {
            # Already carries this exact name — nothing to do.
            return $existingDirectory
        }

        # A different, non-empty display name was captured (hostname-only
        # folder gaining its first suffix, or a machine reassigned to a new
        # person): rename the SAME folder in place instead of minting a
        # second one. Safe because every lookup
        # (Resolve-InventoryHostOutputDirectory) matches by hostname prefix,
        # not exact name, and this is a rename — not a copy — so no files or
        # history are ever lost, the folder is just relabeled.
        try {
            Rename-Item -LiteralPath $existingDirectory `
                -NewName (Split-Path -Leaf $desiredDirectory) -ErrorAction Stop
            return $desiredDirectory
        }
        catch {
            Write-Warning ("No se pudo renombrar la carpeta del equipo: {0}" -f $_.Exception.Message)
            return $existingDirectory
        }
    }

    if ($null -ne $sanitizedDisplayName) {
        return Join-Path $BaseOutputDirectory "$Hostname - $sanitizedDisplayName"
    }

    return Join-Path $BaseOutputDirectory $Hostname
}
