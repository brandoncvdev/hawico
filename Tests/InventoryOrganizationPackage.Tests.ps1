BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/InventoryOrganizationPackage.ps1"

    function New-FixtureOrganizationPackage {
        param(
            [Parameter(Mandatory)][string]$BasePath,
            [string]$OrganizationId = 'org-fixture',
            [string]$ProfileId = 'basic-inventory',
            [string[]]$ManualFields = @('assignment.user.fullName', 'asset.assetTag'),
            [switch]$IncludeCatalog,
            [switch]$IncludeCustomFields
        )

        $orgDir = Join-Path $BasePath $OrganizationId
        $profilesDir = Join-Path $orgDir 'profiles'
        New-Item -ItemType Directory -Force -Path $profilesDir | Out-Null

        $organization = [ordered]@{
            schemaVersion = '1.0'
            packageVersion = '0.1.0'
            organizationId = $OrganizationId
            name = 'Organización de prueba'
            defaultProfileId = $ProfileId
            organizationUnitLabels = @('Sede', 'Dirección', 'Departamento', 'Área')
            updatedAt = ([datetimeoffset]::Now).ToString('o')
        }
        $organization | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $orgDir 'organization.json') -Encoding UTF8

        $profileDefinition = [ordered]@{
            profileId = $ProfileId
            name = 'Perfil de prueba'
            manualFields = @($ManualFields)
            exports = [ordered]@{ json = $true; html = $true; xlsx = $true; log = $true }
            interactionMode = 'compact'
        }
        $profileDefinition | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $profilesDir "$ProfileId.json") -Encoding UTF8

        if ($IncludeCatalog) {
            $catalogsDir = Join-Path $orgDir 'catalogs'
            New-Item -ItemType Directory -Force -Path $catalogsDir | Out-Null
            $catalog = [ordered]@{
                units = @(
                    [ordered]@{ id = 'site-center'; name = 'Sede Centro'; type = 'site'; parentId = $null; sortOrder = 10 }
                    [ordered]@{ id = 'dir-admin'; name = 'Dirección Administrativa'; type = 'direction'; parentId = 'site-center'; sortOrder = 20 }
                )
            }
            $catalog | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $catalogsDir 'organization-units.json') -Encoding UTF8
        }

        if ($IncludeCustomFields) {
            $customFields = [ordered]@{
                fields = @(
                    [ordered]@{
                        key = 'assignment.user.fullName'
                        label = 'Nombre completo del usuario'
                        type = 'text'
                        required = $false
                        allowSkip = $true
                        askDuringCollection = $true
                        reusePreviousValue = $true
                    }
                )
            }
            $customFields | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $orgDir 'custom-fields.json') -Encoding UTF8
        }

        return $orgDir
    }
}

Describe 'Get-InventoryOrganizationPackagePath' {
    It 'builds every path under BasePath/OrganizationId' {
        $basePath = Join-Path $TestDrive 'orgs'

        $paths = Get-InventoryOrganizationPackagePath -BasePath $basePath -OrganizationId 'org-example'

        $paths.OrganizationDirectory | Should -Be (Join-Path $basePath 'org-example')
        $paths.OrganizationFile | Should -Be (Join-Path (Join-Path $basePath 'org-example') 'organization.json')
        $paths.ProfilesDirectory | Should -Be (Join-Path (Join-Path $basePath 'org-example') 'profiles')
        $paths.CatalogsDirectory | Should -Be (Join-Path (Join-Path $basePath 'org-example') 'catalogs')
        $paths.CustomFieldsFile | Should -Be (Join-Path (Join-Path $basePath 'org-example') 'custom-fields.json')
    }
}

Describe 'Get-InventoryOrganizationDefinition' {
    BeforeEach {
        $script:orgsRoot = Join-Path $TestDrive ('orgs-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:orgsRoot | Out-Null
    }

    It 'returns null without throwing when the organization does not exist' {
        { $script:result = Get-InventoryOrganizationDefinition -BasePath $script:orgsRoot -OrganizationId 'does-not-exist' } |
            Should -Not -Throw
        $script:result | Should -BeNullOrEmpty
    }

    It 'returns null when OrganizationId is null or empty' {
        Get-InventoryOrganizationDefinition -BasePath $script:orgsRoot -OrganizationId $null | Should -BeNullOrEmpty
        Get-InventoryOrganizationDefinition -BasePath $script:orgsRoot -OrganizationId '' | Should -BeNullOrEmpty
    }

    It 'returns the parsed organization definition when it exists' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' | Out-Null

        $definition = Get-InventoryOrganizationDefinition -BasePath $script:orgsRoot -OrganizationId 'org-fixture'

        $definition.organizationId | Should -Be 'org-fixture'
        $definition.schemaVersion | Should -Be '1.0'
        $definition.defaultProfileId | Should -Be 'basic-inventory'
    }
}

Describe 'Get-InventoryProfileDefinition' {
    BeforeEach {
        $script:orgsRoot = Join-Path $TestDrive ('orgs-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:orgsRoot | Out-Null
    }

    It 'returns null without throwing when the profile does not exist' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' | Out-Null

        { $script:result = Get-InventoryProfileDefinition -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -ProfileId 'does-not-exist' } |
            Should -Not -Throw
        $script:result | Should -BeNullOrEmpty
    }

    It 'returns the parsed profile definition when it exists' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -ProfileId 'basic-inventory' `
            -ManualFields @('assignment.user.fullName', 'asset.assetTag') | Out-Null

        $definition = Get-InventoryProfileDefinition -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -ProfileId 'basic-inventory'

        $definition.profileId | Should -Be 'basic-inventory'
        @($definition.manualFields) | Should -Be @('assignment.user.fullName', 'asset.assetTag')
        $definition.interactionMode | Should -Be 'compact'
    }
}

Describe 'Get-InventoryProfileManualFields' {
    BeforeEach {
        $script:orgsRoot = Join-Path $TestDrive ('orgs-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:orgsRoot | Out-Null
        $script:fallback = @('fallback.field.one', 'fallback.field.two')
    }

    It 'falls back when OrganizationId is null or empty' {
        $resultNull = Get-InventoryProfileManualFields -BasePath $script:orgsRoot -OrganizationId $null `
            -ProfileId 'basic-inventory' -FallbackFields $script:fallback
        $resultEmpty = Get-InventoryProfileManualFields -BasePath $script:orgsRoot -OrganizationId '' `
            -ProfileId 'basic-inventory' -FallbackFields $script:fallback

        @($resultNull) | Should -Be $script:fallback
        @($resultEmpty) | Should -Be $script:fallback
    }

    It 'falls back when the organization does not exist' {
        $result = Get-InventoryProfileManualFields -BasePath $script:orgsRoot -OrganizationId 'does-not-exist' `
            -ProfileId 'basic-inventory' -FallbackFields $script:fallback

        @($result) | Should -Be $script:fallback
    }

    It 'falls back when the organization exists but the profile does not' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -ProfileId 'basic-inventory' | Out-Null

        $result = Get-InventoryProfileManualFields -BasePath $script:orgsRoot -OrganizationId 'org-fixture' `
            -ProfileId 'audit-completa' -FallbackFields $script:fallback

        @($result) | Should -Be $script:fallback
    }

    It 'uses the profile manual fields instead of the fallback when the profile exists' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -ProfileId 'basic-inventory' `
            -ManualFields @('assignment.user.fullName', 'assignment.organizationUnitId') | Out-Null

        $result = Get-InventoryProfileManualFields -BasePath $script:orgsRoot -OrganizationId 'org-fixture' `
            -ProfileId 'basic-inventory' -FallbackFields $script:fallback

        @($result) | Should -Be @('assignment.user.fullName', 'assignment.organizationUnitId')
    }

    It 'returns an array even when the profile has exactly one manual field (single-element array bug)' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -ProfileId 'basic-inventory' `
            -ManualFields @('assignment.user.fullName') | Out-Null

        $result = Get-InventoryProfileManualFields -BasePath $script:orgsRoot -OrganizationId 'org-fixture' `
            -ProfileId 'basic-inventory' -FallbackFields $script:fallback

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'assignment.user.fullName'
    }
}

Describe 'Get-InventoryOrganizationUnitCatalog' {
    BeforeEach {
        $script:orgsRoot = Join-Path $TestDrive ('orgs-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:orgsRoot | Out-Null
    }

    It 'returns an empty array when there is no organization package' {
        $result = Get-InventoryOrganizationUnitCatalog -BasePath $script:orgsRoot -OrganizationId 'does-not-exist'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'returns an empty array when the organization exists but has no catalog file' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' | Out-Null

        $result = Get-InventoryOrganizationUnitCatalog -BasePath $script:orgsRoot -OrganizationId 'org-fixture'

        @($result).Count | Should -Be 0
    }

    It 'returns the parsed units array when the catalog exists' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -IncludeCatalog | Out-Null

        $result = Get-InventoryOrganizationUnitCatalog -BasePath $script:orgsRoot -OrganizationId 'org-fixture'

        @($result).Count | Should -Be 2
        $result[0].id | Should -Be 'site-center'
        $result[1].parentId | Should -Be 'site-center'
    }
}

Describe 'Get-InventoryCustomFieldDefinitions' {
    BeforeEach {
        $script:orgsRoot = Join-Path $TestDrive ('orgs-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:orgsRoot | Out-Null
    }

    It 'returns an empty array when there is no organization package' {
        $result = Get-InventoryCustomFieldDefinitions -BasePath $script:orgsRoot -OrganizationId 'does-not-exist'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'returns the parsed fields array when custom-fields.json exists (single-element array bug)' {
        New-FixtureOrganizationPackage -BasePath $script:orgsRoot -OrganizationId 'org-fixture' -IncludeCustomFields | Out-Null

        $result = Get-InventoryCustomFieldDefinitions -BasePath $script:orgsRoot -OrganizationId 'org-fixture'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].key | Should -Be 'assignment.user.fullName'
    }
}

Describe 'The real Config/Organizations/org-example package shipped in this repo' {
    It 'resolves the same 5 manual fields already configured as the config.json fallback' {
        $repoOrganizationsRoot = Resolve-Path "$PSScriptRoot/../Config/Organizations"

        $result = Get-InventoryProfileManualFields -BasePath $repoOrganizationsRoot -OrganizationId 'org-example' `
            -ProfileId 'basic-inventory' -FallbackFields @('should-not-be-used')

        @($result) | Should -Be @(
            'assignment.user.fullName',
            'assignment.organizationUnitId',
            'assignment.locationId',
            'asset.assetTag',
            'collection.observations'
        )
    }

    It 'exposes a loadable organization-units catalog and custom-fields definitions' {
        $repoOrganizationsRoot = Resolve-Path "$PSScriptRoot/../Config/Organizations"

        $units = Get-InventoryOrganizationUnitCatalog -BasePath $repoOrganizationsRoot -OrganizationId 'org-example'
        $customFields = Get-InventoryCustomFieldDefinitions -BasePath $repoOrganizationsRoot -OrganizationId 'org-example'

        @($units).Count | Should -BeGreaterThan 0
        @($customFields).Count | Should -BeGreaterThan 0
    }
}
