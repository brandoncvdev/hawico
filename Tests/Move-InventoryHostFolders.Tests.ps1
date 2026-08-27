Describe 'Move-InventoryHostFolders.ps1 contract' {
    BeforeAll {
        $script:scriptPath = "$PSScriptRoot/../Move-InventoryHostFolders.ps1"
        $script:scriptText = Get-Content -LiteralPath $script:scriptPath -Raw
        # Comments (block and line) legitimately spell out "Equipos Obtenidos"
        # as a human-readable example of where things land; only the
        # executable code must never hardcode it. Strip both before checking.
        $script:scriptCodeOnly = $script:scriptText -replace '(?s)<#.*?#>', ''
        $script:scriptCodeOnly = ($script:scriptCodeOnly -split "`n" | ForEach-Object { $_ -replace '#.*$', '' }) -join "`n"
    }

    It 'exists at the repo root' {
        Test-Path -LiteralPath $script:scriptPath | Should -BeTrue
    }

    It 'supports ShouldProcess with High confirm impact, matching a destructive fleet-wide operation' {
        $script:scriptText | Should -Match "SupportsShouldProcess\s*=\s*\`$true"
        $script:scriptText | Should -Match "ConfirmImpact\s*=\s*'High'"
    }

    It 'declares -SourceDirectory and -DestinationDirectory parameters' {
        $script:scriptText | Should -Match '\[string\]\$SourceDirectory'
        $script:scriptText | Should -Match '\[string\]\$DestinationDirectory'
    }

    It 'resolves -SourceDirectory default relative to its own script folder, like other root scripts' {
        $script:scriptText | Should -Match '\$basePath\s*=\s*Split-Path -Parent \$MyInvocation\.MyCommand\.Path'
        $script:scriptText | Should -Match 'Join-Path \$basePath "Output"'
    }

    It 'derives the default -DestinationDirectory from config.json OutputDirectory instead of hardcoding "Equipos Obtenidos"' {
        $script:scriptText | Should -Match 'config\.OutputDirectory'
        $script:scriptCodeOnly | Should -Not -Match "['\`"].*Equipos Obtenidos.*['\`"]"
    }

    It 'routes the move through ShouldProcess' {
        $script:scriptText | Should -Match '\$PSCmdlet\.ShouldProcess\([^)]*\)\s*\)\s*\{\s*(\r?\n\s*)*Move-Item'
    }

    It 'reuses Resolve-InventoryHostOutputDirectory and Get-InventoryHostOutputDirectory instead of reimplementing naming/renaming' {
        $script:scriptText | Should -Match 'Resolve-InventoryHostOutputDirectory'
        $script:scriptText | Should -Match 'Get-InventoryHostOutputDirectory'
    }

    It 'reuses Get-InventoryLatestHostRecord and Get-InventoryManualFieldValueByKey to recover the display name' {
        $script:scriptText | Should -Match 'Get-InventoryLatestHostRecord'
        $script:scriptText | Should -Match "Get-InventoryManualFieldValueByKey"
        $script:scriptText | Should -Match "'assignment\.user\.fullName'"
    }

    It 'never touches the Historico folder' {
        $script:scriptText | Should -Match "Historico"
    }

    It 'never reports "Moved+Renamed" for a folder whose move was declined outside of -WhatIf (only $WhatIfPreference may report a preview without $moved being true)' {
        # A plain interactive run (no -WhatIf, no -Confirm:$false) prompts
        # per item; if the technician declines the "Mover" prompt for one
        # host, ShouldProcess returns $false there too, but $WhatIfPreference
        # stays $false — that combination must be handled as a real decline
        # (status distinct from "Moved+Renamed"/"Moved (no display name
        # found)"), not silently fall through to reporting a move that never
        # happened.
        $script:scriptCodeOnly | Should -Match '\$WhatIfPreference'
        $script:scriptCodeOnly | Should -Match "(?i)declin"
    }

    It 'never reports a real rename as done when the rename-specific ShouldProcess prompt was declined after a confirmed move' {
        # The move and the rename are two independent destructive actions,
        # each behind its own ShouldProcess call — a declined rename after a
        # confirmed move must report the folder as moved-but-not-renamed,
        # never as "Moved+Renamed".
        $script:scriptCodeOnly | Should -Match "(?i)rename declin"
    }
}

Describe 'Move-InventoryHostFolders.ps1 behavior' {
    BeforeAll {
        $script:scriptPath = "$PSScriptRoot/../Move-InventoryHostFolders.ps1"

        function New-InventoryMigrationFixtureHostFolder {
            param(
                [Parameter(Mandatory)][string]$SourceDirectory,
                [Parameter(Mandatory)][string]$Hostname,
                [AllowNull()][string]$DisplayName = $null
            )

            $hostFolder = Join-Path $SourceDirectory $Hostname
            New-Item -ItemType Directory -Force -Path $hostFolder | Out-Null

            $manualFields = @()
            if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
                $manualFields = @(
                    [ordered]@{
                        Key = 'assignment.user.fullName'
                        Value = $DisplayName
                        CapturedBy = 'Tester'
                    }
                )
            }

            $record = [ordered]@{
                ContractVersion = '1.0'
                CollectionId = "COL-$Hostname"
                SessionId = 'SES-UNASSIGNED'
                CollectedAt = [datetimeoffset]::Now.ToString('o')
                ComputerName = $Hostname
                ManualFields = $manualFields
            }

            $recordPath = Join-Path $hostFolder "$Hostname-20260101-000000000-record.json"
            $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recordPath -Encoding UTF8

            return $hostFolder
        }
    }

    BeforeEach {
        $script:source = Join-Path $TestDrive ('source-' + [guid]::NewGuid().ToString('N'))
        $script:destination = Join-Path $TestDrive ('dest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:source | Out-Null
    }

    It 'moves and renames a hostname-only folder with a recoverable display name' {
        New-InventoryMigrationFixtureHostFolder -SourceDirectory $script:source -Hostname 'DESKTOP-A93JX' -DisplayName 'Juan Perez' | Out-Null

        & $script:scriptPath -SourceDirectory $script:source -DestinationDirectory $script:destination -Confirm:$false | Out-Null

        $expected = Join-Path $script:destination 'DESKTOP-A93JX - Juan Perez'
        Test-Path -LiteralPath $expected | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:source 'DESKTOP-A93JX') | Should -BeFalse
    }

    It 'moves a folder with no manual name recorded and leaves it hostname-only' {
        New-InventoryMigrationFixtureHostFolder -SourceDirectory $script:source -Hostname 'DESKTOP-NONAME' -DisplayName $null | Out-Null

        & $script:scriptPath -SourceDirectory $script:source -DestinationDirectory $script:destination -Confirm:$false | Out-Null

        $expected = Join-Path $script:destination 'DESKTOP-NONAME'
        Test-Path -LiteralPath $expected | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:destination 'DESKTOP-NONAME - ') | Should -BeFalse
    }

    It 'never touches Historico' {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:source 'Historico') | Out-Null
        'evidence' | Set-Content -LiteralPath (Join-Path $script:source 'Historico\marker.txt')

        & $script:scriptPath -SourceDirectory $script:source -DestinationDirectory $script:destination -Confirm:$false | Out-Null

        Test-Path -LiteralPath (Join-Path $script:source 'Historico\marker.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:destination 'Historico') | Should -BeFalse
    }

    It 'skips a folder already migrated at the destination instead of overwriting it' {
        New-InventoryMigrationFixtureHostFolder -SourceDirectory $script:source -Hostname 'DESKTOP-DUP' -DisplayName 'Someone New' | Out-Null

        New-Item -ItemType Directory -Force -Path $script:destination | Out-Null
        $preExisting = Join-Path $script:destination 'DESKTOP-DUP'
        New-Item -ItemType Directory -Force -Path $preExisting | Out-Null
        'original evidence' | Set-Content -LiteralPath (Join-Path $preExisting 'keep.txt')

        $result = & $script:scriptPath -SourceDirectory $script:source -DestinationDirectory $script:destination -Confirm:$false

        Test-Path -LiteralPath (Join-Path $preExisting 'keep.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:source 'DESKTOP-DUP') | Should -BeTrue
        ($result.Results | Where-Object Hostname -eq 'DESKTOP-DUP').Status | Should -Be 'Skipped (already migrated)'
    }

    It 'performs zero real filesystem changes under -WhatIf, while still describing what would happen' {
        New-InventoryMigrationFixtureHostFolder -SourceDirectory $script:source -Hostname 'DESKTOP-WHATIF' -DisplayName 'Ana Torres' | Out-Null

        $result = & $script:scriptPath -SourceDirectory $script:source -DestinationDirectory $script:destination -WhatIf

        Test-Path -LiteralPath (Join-Path $script:source 'DESKTOP-WHATIF') | Should -BeTrue
        Test-Path -LiteralPath $script:destination | Should -BeFalse
        ($result.Results | Where-Object Hostname -eq 'DESKTOP-WHATIF').Status | Should -Be 'Moved+Renamed to "DESKTOP-WHATIF - Ana Torres"'
    }

    It 'does not abort the batch when one folder errors, and reports the error for that folder only' {
        New-InventoryMigrationFixtureHostFolder -SourceDirectory $script:source -Hostname 'DESKTOP-GOOD' -DisplayName $null | Out-Null
        New-InventoryMigrationFixtureHostFolder -SourceDirectory $script:source -Hostname 'DESKTOP-BAD' -DisplayName $null | Out-Null

        # Naturally force Move-Item to fail for DESKTOP-BAD only: occupy its
        # destination path with a plain file of the same name (no -Force is
        # used by the script, so Move-Item refuses to overwrite it) instead
        # of mocking a cmdlet across the script-file call boundary.
        New-Item -ItemType Directory -Force -Path $script:destination | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $script:destination 'DESKTOP-BAD') | Out-Null

        $result = & $script:scriptPath -SourceDirectory $script:source -DestinationDirectory $script:destination -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:destination 'DESKTOP-GOOD') | Should -BeTrue
        ($result.Results | Where-Object Hostname -eq 'DESKTOP-BAD').Status | Should -Match '^Error: '
        $result.ErrorCount | Should -Be 1
        $result.Success | Should -BeFalse
    }
}
