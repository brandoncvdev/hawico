BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
    }
}

Describe 'Get-CimDataSafe' {
    It 'returns a real array, not a bare object, when exactly one instance is found (no filter)' {
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'Win32_OperatingSystem' } }

        $result = Get-CimDataSafe -ClassName 'Win32_OperatingSystem'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'returns a real array, not a bare object, when exactly one instance is found (with a filter)' {
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'C:' } }

        $result = Get-CimDataSafe -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3'

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'returns an empty array instead of throwing when the query fails' {
        Mock Get-CimInstance { throw 'access denied' }

        $result = Get-CimDataSafe -ClassName 'Win32_Processor' -WarningAction SilentlyContinue

        @($result).Count | Should -Be 0
    }
}

Describe 'Resolve-InventoryManualFieldKeys' {
    It 'returns a real array, not a bare scalar, when exactly one key is passed in directly' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys @('assignment.user.fullName') -ConfigManualFields @('fallback.one', 'fallback.two')

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'assignment.user.fullName'
    }

    It 'returns a real array, not a bare scalar, when falling back to exactly one config manual field' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys $null -ConfigManualFields @('assignment.organizationUnitId')

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'assignment.organizationUnitId'
    }

    It 'returns a real empty array when there is nothing to fall back to' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys $null -ConfigManualFields $null

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'prefers the passed-in keys over the config fallback when both are present' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys @('from.launcher') -ConfigManualFields @('from.config')

        $result.Count | Should -Be 1
        $result[0] | Should -Be 'from.launcher'
    }

    It 'returns every passed-in key when there is more than one' {
        $result = Resolve-InventoryManualFieldKeys -PassedKeys @('field.one', 'field.two') -ConfigManualFields $null

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 2
    }
}

Describe 'Resolve-InventoryOrganizationUnits' {
    It 'returns a real array, not a bare scalar, when exactly one unit is passed in' {
        $unit = [PSCustomObject]@{ id = 'site-center'; name = 'Sede Centro'; parentId = $null; sortOrder = 10 }

        $result = Resolve-InventoryOrganizationUnits -PassedUnits @($unit)

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].id | Should -Be 'site-center'
    }

    It 'returns a real empty array when nothing was passed' {
        $result = Resolve-InventoryOrganizationUnits -PassedUnits $null

        $result.GetType().IsArray | Should -BeTrue
        $result.Count | Should -Be 0
    }
}

Describe 'Install-InventoryImportExcelIfNeeded' {
    It 'returns true immediately when already available, without prompting or installing' {
        $calls = [ordered]@{ Confirm = 0; Installer = 0 }
        $isAvailable = { $true }
        $confirm = { param($Prompt) $calls.Confirm++; 'S' }
        $installer = { $calls.Installer++ }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeTrue
        $calls.Confirm | Should -Be 0
        $calls.Installer | Should -Be 0
    }

    It 'returns false and never installs when the user declines' {
        $calls = [ordered]@{ Installer = 0 }
        $isAvailable = { $false }
        $confirm = { param($Prompt) 'N' }
        $installer = { $calls.Installer++ }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeFalse
        $calls.Installer | Should -Be 0
    }

    It 'treats an empty answer (Enter) as declining, without installing' {
        $calls = [ordered]@{ Installer = 0 }
        $isAvailable = { $false }
        $confirm = { param($Prompt) '' }
        $installer = { $calls.Installer++ }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeFalse
        $calls.Installer | Should -Be 0
    }

    It 'passes a prompt describing what will be installed to Confirm' {
        $script:capturedPrompt = $null
        $isAvailable = { $false }
        $confirm = { param($Prompt) $script:capturedPrompt = $Prompt; 'N' }
        $installer = { }

        Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer | Out-Null

        $script:capturedPrompt | Should -Match 'ImportExcel'
    }

    It 'installs and returns true when the user accepts (uppercase S) and the install succeeds' {
        $state = [ordered]@{ Installed = $false; InstallerCalls = 0 }
        $isAvailable = { $state.Installed }
        $confirm = { param($Prompt) 'S' }
        $installer = { $state.InstallerCalls++; $state.Installed = $true }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeTrue
        $state.InstallerCalls | Should -Be 1
    }

    It 'accepts a lowercase s answer too' {
        $state = [ordered]@{ Installed = $false }
        $isAvailable = { $state.Installed }
        $confirm = { param($Prompt) 's' }
        $installer = { $state.Installed = $true }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer

        $result | Should -BeTrue
    }

    It 'returns false and prints the error when the install throws' {
        $isAvailable = { $false }
        $confirm = { param($Prompt) 'S' }
        $installer = { throw 'network unreachable' }

        $result = Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer `
            -InformationVariable infoOutput -InformationAction SilentlyContinue

        $result | Should -BeFalse
        ($infoOutput | Out-String) | Should -Match 'network unreachable'
    }

    It 'does not re-check availability a second time when the user declines' {
        $calls = [ordered]@{ IsAvailable = 0 }
        $isAvailable = { $calls.IsAvailable++; $false }
        $confirm = { param($Prompt) 'N' }
        $installer = { }

        Install-InventoryImportExcelIfNeeded -IsAvailable $isAvailable -Confirm $confirm -Installer $installer | Out-Null

        $calls.IsAvailable | Should -Be 1
    }
}

Describe 'Get-InventorySanitizedDisplayName' {
    It 'returns $null for $null' {
        Get-InventorySanitizedDisplayName -DisplayName $null | Should -BeNullOrEmpty
    }

    It 'returns $null for an empty/whitespace-only string' {
        Get-InventorySanitizedDisplayName -DisplayName '   ' | Should -BeNullOrEmpty
    }

    It 'trims leading/trailing whitespace' {
        Get-InventorySanitizedDisplayName -DisplayName '  Juan Perez  ' | Should -Be 'Juan Perez'
    }

    It 'collapses internal whitespace runs into a single space' {
        Get-InventorySanitizedDisplayName -DisplayName "Juan   Perez`t`tGarcia" | Should -Be 'Juan Perez Garcia'
    }

    It 'strips characters invalid in Windows paths' {
        Get-InventorySanitizedDisplayName -DisplayName 'Juan\Perez/Garcia:Test*Case?"<Extra>|End' |
            Should -Be 'JuanPerezGarciaTestCaseExtraEnd'
    }

    It 'returns $null when the value becomes empty after sanitizing' {
        Get-InventorySanitizedDisplayName -DisplayName ' :*?" ' | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-InventoryHostOutputDirectory' {
    BeforeEach {
        $script:base = Join-Path $TestDrive ('base-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:base | Out-Null
    }

    It 'returns $null when the base output directory does not exist' {
        $missingBase = Join-Path $TestDrive 'does-not-exist'
        Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $missingBase -Hostname 'RH-PC-04' |
            Should -BeNullOrEmpty
    }

    It 'returns $null when no folder for this hostname exists yet' {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:base 'OTHER-PC') | Out-Null

        Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $script:base -Hostname 'RH-PC-04' |
            Should -BeNullOrEmpty
    }

    It 'finds an exact hostname-only folder (pre-existing, hostname-only collection)' {
        $expected = Join-Path $script:base 'RH-PC-04'
        New-Item -ItemType Directory -Force -Path $expected | Out-Null

        Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $script:base -Hostname 'RH-PC-04' |
            Should -Be $expected
    }

    It 'finds a "Hostname - DisplayName" folder' {
        $expected = Join-Path $script:base 'RH-PC-04 - Juan Perez'
        New-Item -ItemType Directory -Force -Path $expected | Out-Null

        Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $script:base -Hostname 'RH-PC-04' |
            Should -Be $expected
    }

    It 'never lets a hostname match another hostname it is only a numeric prefix of (PC1 must not match "PC10 - Someone")' {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:base 'PC10 - Someone') | Out-Null

        Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $script:base -Hostname 'PC1' |
            Should -BeNullOrEmpty
    }

    It 'never matches a folder that only starts with the hostname as a plain string prefix (no separator)' {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:base 'RH-PC-04EXTRA') | Out-Null

        Resolve-InventoryHostOutputDirectory -BaseOutputDirectory $script:base -Hostname 'RH-PC-04' |
            Should -BeNullOrEmpty
    }
}

Describe 'Get-InventoryHostOutputDirectory' {
    It 'joins the base output directory with the (already-sanitized) hostname when no -DisplayName is given' {
        # Both collectors already sanitize $env:COMPUTERNAME
        # (-replace '[^a-zA-Z0-9_-]', '_') before calling this, so this stays
        # a pure Join-Path wrapper instead of duplicating that sanitization.
        Get-InventoryHostOutputDirectory -BaseOutputDirectory 'C:\Output' -Hostname 'RH-PC-04' |
            Should -Be (Join-Path 'C:\Output' 'RH-PC-04')
    }

    It 'groups every artifact for the same hostname under the same subfolder regardless of collection timestamp' {
        $first = Get-InventoryHostOutputDirectory -BaseOutputDirectory 'C:\Output' -Hostname 'RH-PC-04'
        $second = Get-InventoryHostOutputDirectory -BaseOutputDirectory 'C:\Output' -Hostname 'RH-PC-04'

        $first | Should -Be $second
    }

    It 'appends the assigned user''s display name to a brand-new host folder' {
        $base = Join-Path $TestDrive ('new-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $base | Out-Null

        Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName 'Juan Perez' |
            Should -Be (Join-Path $base 'DESKTOP-A93JX - Juan Perez')
    }

    It 'sanitizes the display name before appending it to a brand-new host folder' {
        $base = Join-Path $TestDrive ('new-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $base | Out-Null

        Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName '  Juan   "Perez"  ' |
            Should -Be (Join-Path $base 'DESKTOP-A93JX - Juan Perez')
    }

    It 'falls back to hostname-only for a brand-new folder when -DisplayName is $null' {
        $base = Join-Path $TestDrive ('new-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $base | Out-Null

        Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName $null |
            Should -Be (Join-Path $base 'DESKTOP-A93JX')
    }

    It 'falls back to hostname-only for a brand-new folder when -DisplayName is empty/whitespace' {
        $base = Join-Path $TestDrive ('new-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $base | Out-Null

        Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName '   ' |
            Should -Be (Join-Path $base 'DESKTOP-A93JX')
    }

    It 'renames an already-named existing folder in place when a different, non-empty -DisplayName is captured (machine reassigned)' {
        # Safe because every lookup is hostname-prefix-based (Resolve-
        # InventoryHostOutputDirectory), not exact-name-based, and this is a
        # rename (Move-Item/Rename-Item), never a copy — no files or history
        # are lost, the same folder just gets relabeled.
        $base = Join-Path $TestDrive ('existing-' + [guid]::NewGuid().ToString('N'))
        $existing = Join-Path $base 'DESKTOP-A93JX - Juan Perez'
        New-Item -ItemType Directory -Force -Path $existing | Out-Null
        'evidence' | Set-Content -LiteralPath (Join-Path $existing 'record.json')

        $expected = Join-Path $base 'DESKTOP-A93JX - Maria Lopez'
        $result = Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName 'Maria Lopez'

        $result | Should -Be $expected
        Test-Path -LiteralPath $expected | Should -BeTrue
        Test-Path -LiteralPath $existing | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $expected 'record.json') | Should -BeTrue
    }

    It 'renames an already-existing hostname-only folder in place to add the suffix when a -DisplayName is now captured' {
        $base = Join-Path $TestDrive ('existing-' + [guid]::NewGuid().ToString('N'))
        $existing = Join-Path $base 'DESKTOP-A93JX'
        New-Item -ItemType Directory -Force -Path $existing | Out-Null
        'evidence' | Set-Content -LiteralPath (Join-Path $existing 'record.json')

        $expected = Join-Path $base 'DESKTOP-A93JX - Juan Perez'
        $result = Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName 'Juan Perez'

        $result | Should -Be $expected
        Test-Path -LiteralPath $expected | Should -BeTrue
        Test-Path -LiteralPath $existing | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $expected 'record.json') | Should -BeTrue
    }

    It 'does not rename (no-op) when the captured -DisplayName already matches the folder''s current suffix' {
        $base = Join-Path $TestDrive ('existing-' + [guid]::NewGuid().ToString('N'))
        $existing = Join-Path $base 'DESKTOP-A93JX - Juan Perez'
        New-Item -ItemType Directory -Force -Path $existing | Out-Null

        Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName 'Juan Perez' |
            Should -Be $existing
        Test-Path -LiteralPath $existing | Should -BeTrue
    }

    It 'returns an already-named existing folder as-is even when -DisplayName is now $null/blank (a skipped field never strips the suffix)' {
        $base = Join-Path $TestDrive ('existing-' + [guid]::NewGuid().ToString('N'))
        $existing = Join-Path $base 'DESKTOP-A93JX - Juan Perez'
        New-Item -ItemType Directory -Force -Path $existing | Out-Null

        Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName $null |
            Should -Be $existing
        Test-Path -LiteralPath $existing | Should -BeTrue
    }

    It 'walks the full reassignment/skip lifecycle: create named, rename on reassignment, stay put on a later skip' {
        # Get-InventoryHostOutputDirectory only computes/renames a path — it
        # never creates the folder itself (that is always the caller's own
        # New-Item -Force, as every real collector does). Each "visit" below
        # does the same, so this test's -BaseOutputDirectory reflects reality
        # for the next visit's Resolve-InventoryHostOutputDirectory lookup.
        $base = Join-Path $TestDrive ('lifecycle-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $base | Out-Null

        # Visit 1: brand-new folder, captures "Juan Perez".
        $visit1 = Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName 'Juan Perez'
        $visit1 | Should -Be (Join-Path $base 'DESKTOP-A93JX - Juan Perez')
        New-Item -ItemType Directory -Force -Path $visit1 | Out-Null

        # Visit 2: machine reassigned, captures "Maria Lopez" — renamed in place.
        $visit2 = Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName 'Maria Lopez'
        $visit2 | Should -Be (Join-Path $base 'DESKTOP-A93JX - Maria Lopez')
        Test-Path -LiteralPath (Join-Path $base 'DESKTOP-A93JX - Juan Perez') | Should -BeFalse
        New-Item -ItemType Directory -Force -Path $visit2 | Out-Null

        # Visit 3: field skipped (blank) — folder stays exactly as visit 2 left it.
        $visit3 = Get-InventoryHostOutputDirectory -BaseOutputDirectory $base -Hostname 'DESKTOP-A93JX' -DisplayName $null
        $visit3 | Should -Be (Join-Path $base 'DESKTOP-A93JX - Maria Lopez')
    }
}
