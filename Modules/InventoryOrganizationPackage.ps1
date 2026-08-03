function Get-InventoryOrganizationPackagePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$OrganizationId
    )

    $organizationDirectory = Join-Path $BasePath $OrganizationId
    $profilesDirectory = Join-Path $organizationDirectory 'profiles'
    $catalogsDirectory = Join-Path $organizationDirectory 'catalogs'

    return [ordered]@{
        OrganizationDirectory = $organizationDirectory
        OrganizationFile = Join-Path $organizationDirectory 'organization.json'
        ProfilesDirectory = $profilesDirectory
        CatalogsDirectory = $catalogsDirectory
        CustomFieldsFile = Join-Path $organizationDirectory 'custom-fields.json'
    }
}

function Get-InventoryOrganizationDefinition {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads an existing organization package without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string]$OrganizationId
    )

    $normalizedOrganizationId = Get-SafeString $OrganizationId
    if ($null -eq $normalizedOrganizationId) {
        return $null
    }

    $paths = Get-InventoryOrganizationPackagePath -BasePath $BasePath -OrganizationId $normalizedOrganizationId

    # No package configured yet is the normal case, not an error: degrade
    # gracefully instead of throwing.
    if (-not (Test-Path -LiteralPath $paths.OrganizationFile)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $paths.OrganizationFile -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer organization.json de '{0}': {1}" -f $normalizedOrganizationId, $_.Exception.Message)
        return $null
    }
}

function Get-InventoryProfileDefinition {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads an existing profile definition without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string]$OrganizationId,
        [AllowNull()][string]$ProfileId
    )

    $normalizedOrganizationId = Get-SafeString $OrganizationId
    $normalizedProfileId = Get-SafeString $ProfileId
    if ($null -eq $normalizedOrganizationId -or $null -eq $normalizedProfileId) {
        return $null
    }

    $paths = Get-InventoryOrganizationPackagePath -BasePath $BasePath -OrganizationId $normalizedOrganizationId
    $profileFile = Join-Path $paths.ProfilesDirectory "$normalizedProfileId.json"

    if (-not (Test-Path -LiteralPath $profileFile)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer el perfil '{0}' de '{1}': {2}" -f $normalizedProfileId, $normalizedOrganizationId, $_.Exception.Message)
        return $null
    }
}

function Get-InventoryProfileManualFields {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Resolves the active manual field list without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string]$OrganizationId,
        [AllowNull()][string]$ProfileId,
        [AllowNull()][object[]]$FallbackFields = @()
    )

    # The comma-unary guard on every `return` below preserves an exact array
    # regardless of element count: without it, a one-element result would
    # collapse into a bare scalar for the caller (the same pipeline-unwrap
    # bug already found and fixed in Read-InventoryManualCapture and
    # New-InventoryConsolidatedWorkbook.ps1).
    $normalizedOrganizationId = Get-SafeString $OrganizationId
    if ($null -eq $normalizedOrganizationId) {
        return ,@($FallbackFields)
    }

    $organization = Get-InventoryOrganizationDefinition -BasePath $BasePath -OrganizationId $normalizedOrganizationId
    if ($null -eq $organization) {
        return ,@($FallbackFields)
    }

    $profileDefinition = Get-InventoryProfileDefinition -BasePath $BasePath `
        -OrganizationId $normalizedOrganizationId -ProfileId $ProfileId
    if ($null -eq $profileDefinition) {
        return ,@($FallbackFields)
    }

    return ,@(@($profileDefinition.manualFields) | Where-Object { $null -ne $_ })
}

function Get-InventoryOrganizationUnitCatalog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads an existing catalog file without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string]$OrganizationId
    )

    $normalizedOrganizationId = Get-SafeString $OrganizationId
    if ($null -eq $normalizedOrganizationId) {
        return ,@()
    }

    $paths = Get-InventoryOrganizationPackagePath -BasePath $BasePath -OrganizationId $normalizedOrganizationId
    $catalogFile = Join-Path $paths.CatalogsDirectory 'organization-units.json'

    if (-not (Test-Path -LiteralPath $catalogFile)) {
        return ,@()
    }

    try {
        $parsed = Get-Content -LiteralPath $catalogFile -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer el catálogo de unidades organizacionales de '{0}': {1}" -f $normalizedOrganizationId, $_.Exception.Message)
        return ,@()
    }

    return ,@(@($parsed.units) | Where-Object { $null -ne $_ })
}

function Get-InventoryCustomFieldDefinitions {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads an existing custom field definitions file without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string]$OrganizationId
    )

    $normalizedOrganizationId = Get-SafeString $OrganizationId
    if ($null -eq $normalizedOrganizationId) {
        return ,@()
    }

    $paths = Get-InventoryOrganizationPackagePath -BasePath $BasePath -OrganizationId $normalizedOrganizationId

    if (-not (Test-Path -LiteralPath $paths.CustomFieldsFile)) {
        return ,@()
    }

    try {
        $parsed = Get-Content -LiteralPath $paths.CustomFieldsFile -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer custom-fields.json de '{0}': {1}" -f $normalizedOrganizationId, $_.Exception.Message)
        return ,@()
    }

    return ,@(@($parsed.fields) | Where-Object { $null -ne $_ })
}
