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
        return Get-Content -LiteralPath $paths.OrganizationFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
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
        return Get-Content -LiteralPath $profileFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
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
        $parsed = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer el catálogo de unidades organizacionales de '{0}': {1}" -f $normalizedOrganizationId, $_.Exception.Message)
        return ,@()
    }

    return ,@(@($parsed.units) | Where-Object { $null -ne $_ })
}

function Get-InventoryDepartmentUnitCatalog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads an existing catalog file without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string]$OrganizationId
    )

    # Same shape and degrade-without-throwing behavior as
    # Get-InventoryOrganizationUnitCatalog above, but reading
    # catalogs/departments.json: an institution whose Dirección/Departamento
    # data has no reliable parent-child relationship (rows don't line up,
    # nothing to derive a real hierarchy from without inventing it) ships a
    # second, independent flat catalog instead of forcing a fake cascade.
    $normalizedOrganizationId = Get-SafeString $OrganizationId
    if ($null -eq $normalizedOrganizationId) {
        return ,@()
    }

    $paths = Get-InventoryOrganizationPackagePath -BasePath $BasePath -OrganizationId $normalizedOrganizationId
    $catalogFile = Join-Path $paths.CatalogsDirectory 'departments.json'

    if (-not (Test-Path -LiteralPath $catalogFile)) {
        return ,@()
    }

    try {
        $parsed = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer el catálogo de departamentos de '{0}': {1}" -f $normalizedOrganizationId, $_.Exception.Message)
        return ,@()
    }

    return ,@(@($parsed.units) | Where-Object { $null -ne $_ })
}

function Get-InventoryAutoDetectedOrganizationId {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads existing organization folders without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [AllowNull()][string[]]$ExcludeOrganizationIds = @('org-example')
    )

    # config.json's CollectionSession.OrganizationId being unset used to mean
    # "no catalog, free text only" even when a real organization package was
    # already sitting on disk — the technician had to hand-edit JSON before
    # the catalog they just copied over would ever be used. When exactly one
    # real candidate folder exists (org-example is never a candidate: it is
    # the reference format, not a real institution), use it automatically.
    # Zero or more than one candidate is intentionally left unresolved rather
    # than guessing which one is "the" institution.
    if (-not (Test-Path -LiteralPath $BasePath)) {
        return $null
    }

    $excluded = @(@($ExcludeOrganizationIds) | Where-Object { $null -ne $_ } | ForEach-Object { $_.ToLowerInvariant() })

    $candidates = @(
        Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $excluded -notcontains $_.Name.ToLowerInvariant() } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'organization.json') }
    )

    if ($candidates.Count -ne 1) {
        return $null
    }

    return $candidates[0].Name
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
        $parsed = Get-Content -LiteralPath $paths.CustomFieldsFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("No se pudo leer custom-fields.json de '{0}': {1}" -f $normalizedOrganizationId, $_.Exception.Message)
        return ,@()
    }

    return ,@(@($parsed.fields) | Where-Object { $null -ne $_ })
}
