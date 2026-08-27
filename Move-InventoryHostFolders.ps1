<#
.SYNOPSIS
    One-time migration: moves existing host folders from the old flat
    Output\<Hostname>\ location into the new nested OutputDirectory
    (Output\Equipos Obtenidos\<Hostname>\), renaming into the
    "Hostname - DisplayName" form when a display name can be recovered
    from that machine's own collection history.

.DESCRIPTION
    Before this feature, every host folder lived flat under -SourceDirectory,
    sibling to Historico\ and Consolidado.xlsx. config.json's OutputDirectory
    now points new collections at a nested folder instead, which orphans every
    already-collected machine: repeat-visit detection and consolidation only
    ever look at the new location. This script migrates the old folders over,
    one time, safely.

    This is destructive and hard to reverse on a real, already-collected
    fleet (potentially hundreds of machines) — it is built with
    SupportsShouldProcess. Run it with -WhatIf first to preview every move
    and rename with zero side effects. Without -WhatIf, each move and each
    rename asks for confirmation individually (ConfirmImpact High); pass
    -Confirm:$false to run unattended once you have reviewed the -WhatIf
    output.

.PARAMETER SourceDirectory
    The old, flat folder that host folders currently sit in. Defaults to
    .\Output next to this script.

.PARAMETER DestinationDirectory
    The new nested folder host folders should end up in. Defaults to
    config.json's OutputDirectory, resolved the same way every other root
    script resolves it.

.EXAMPLE
    .\Move-InventoryHostFolders.ps1 -WhatIf
    Previews every move/rename this run would perform without touching disk.

.EXAMPLE
    .\Move-InventoryHostFolders.ps1 -Confirm:$false
    Runs the migration for real without a confirmation prompt per item.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$SourceDirectory,
    [string]$DestinationDirectory
)

$ErrorActionPreference = "Stop"

$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $basePath "config.json"

. (Join-Path $basePath "Modules\Common.ps1")
. (Join-Path $basePath "Modules\New-InventoryConsolidatedWorkbook.ps1")

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $basePath "Output"
}

if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "No se encontró config.json"
    }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # config.json is the single source of truth for where NEW collections
    # land — this deliberately reads OutputDirectory from it instead of
    # hardcoding "Equipos Obtenidos", so the migration keeps matching
    # reality if that setting is ever changed again.
    $outputDirectoryConfigValue = ".\Output"
    if ($config.PSObject.Properties.Name -contains "OutputDirectory" -and
        -not [string]::IsNullOrWhiteSpace($config.OutputDirectory)) {
        $outputDirectoryConfigValue = $config.OutputDirectory
    }

    $DestinationDirectory = Join-Path $basePath ($outputDirectoryConfigValue -replace '^[.][\\/]', '')
}

function Format-InventoryMigrationSummaryLine {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$Status
    )

    return "  {0,-30} {1}" -f $Hostname, $Status
}

try {
    if (-not (Test-Path -LiteralPath $SourceDirectory)) {
        throw "No se encontró la carpeta de origen: $SourceDirectory"
    }

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        if ($PSCmdlet.ShouldProcess($DestinationDirectory, "Crear carpeta de destino")) {
            New-Item -ItemType Directory -Force -Path $DestinationDirectory -ErrorAction Stop | Out-Null
        }
    }

    # Normalize for exact-path comparisons below (Get-ChildItem never
    # returns a trailing separator on .FullName; -DestinationDirectory might
    # carry one depending on how the caller built it).
    $normalizedDestination = $DestinationDirectory.TrimEnd('\', '/')

    $candidates = @(
        Get-ChildItem -LiteralPath $SourceDirectory -Directory -ErrorAction Stop
    )

    Write-Host ""
    Write-Host "Migrando carpetas de equipos a la nueva ubicación..." -ForegroundColor Cyan
    Write-Host "Origen:  $SourceDirectory"
    Write-Host "Destino: $DestinationDirectory"
    Write-Host ""

    $results = @()
    $errorCount = 0

    foreach ($candidate in $candidates) {
        $hostname = $candidate.Name

        # Never touch Historico\ (consolidation history, not a host folder),
        # nor the destination folder itself when it happens to live directly
        # inside -SourceDirectory — this is what makes re-running the script
        # after a partial migration safe instead of double-processing folders
        # that already moved.
        if ($hostname -eq 'Historico') {
            continue
        }

        if ($candidate.FullName.TrimEnd('\', '/') -eq $normalizedDestination) {
            continue
        }

        try {
            $existingAtDestination = Resolve-InventoryHostOutputDirectory `
                -BaseOutputDirectory $DestinationDirectory -Hostname $hostname

            if ($null -ne $existingAtDestination) {
                $results += [ordered]@{
                    Hostname = $hostname
                    Status = 'Skipped (already migrated)'
                }
                continue
            }

            $moveTargetPath = Join-Path $DestinationDirectory $hostname
            $moved = $false

            if ($PSCmdlet.ShouldProcess($candidate.FullName, "Mover a '$moveTargetPath'")) {
                Move-Item -LiteralPath $candidate.FullName -Destination $DestinationDirectory -ErrorAction Stop
                $moved = $true
            }
            elseif (-not $WhatIfPreference) {
                # A real (non -WhatIf) run where the technician declined THIS
                # host's "Mover" prompt specifically — nothing happened, and
                # asking to rename a folder that was never moved makes no
                # sense. Report the decline honestly and move on to the next
                # candidate instead of falling through into the "Moved..."
                # branches below, which would otherwise misreport this folder
                # as migrated.
                $results += [ordered]@{
                    Hostname = $hostname
                    Status = 'Skipped (move declined)'
                }
                continue
            }

            # Read-only: works whether the folder just moved (real run) or is
            # still sitting at its original location (-WhatIf preview — a
            # plain decline was already handled and skipped above) — the
            # record files are identical either way, so this doubles as the
            # accurate preview source under -WhatIf.
            $recordLookupPath = if ($moved) { $moveTargetPath } else { $candidate.FullName }
            $latestRecord = Get-InventoryLatestHostRecord -HostOutputDirectory $recordLookupPath

            $displayName = $null
            if ($null -ne $latestRecord) {
                $displayName = Get-InventoryManualFieldValueByKey `
                    -ManualFields $latestRecord.ManualFields -Key 'assignment.user.fullName'
            }

            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $results += [ordered]@{
                    Hostname = $hostname
                    Status = 'Moved (no display name found)'
                    Path = $moveTargetPath
                }
                continue
            }

            $sanitizedPreviewName = Get-InventorySanitizedDisplayName -DisplayName $displayName
            $previewFolderName = "$hostname - $sanitizedPreviewName"

            if (-not $moved) {
                # Only reachable via -WhatIf now (a plain decline of the move
                # itself was already handled above) — report the full
                # move+rename plan as a preview without touching disk.
                $results += [ordered]@{
                    Hostname = $hostname
                    Status = "Moved+Renamed to `"$previewFolderName`""
                    Path = $moveTargetPath
                }
                continue
            }

            # The rename is a second, independent destructive step — it must
            # never run just because the move happened, and a decline here
            # must never be reported as a completed rename.
            if ($PSCmdlet.ShouldProcess($moveTargetPath, "Renombrar para incluir '$sanitizedPreviewName'")) {
                $finalPath = Get-InventoryHostOutputDirectory `
                    -BaseOutputDirectory $DestinationDirectory -Hostname $hostname -DisplayName $displayName
                $finalName = Split-Path -Leaf $finalPath

                $results += [ordered]@{
                    Hostname = $hostname
                    Status = "Moved+Renamed to `"$finalName`""
                    Path = $finalPath
                }
            }
            else {
                # Real run, move confirmed, rename declined for this host
                # specifically — the folder stays hostname-only at the new
                # location; say so instead of claiming it was renamed.
                $results += [ordered]@{
                    Hostname = $hostname
                    Status = "Moved (rename declined, kept as `"$hostname`")"
                    Path = $moveTargetPath
                }
            }
        }
        catch {
            $errorCount++
            $results += [ordered]@{
                Hostname = $hostname
                Status = "Error: $($_.Exception.Message)"
            }
        }
    }

    foreach ($entry in $results) {
        Write-Host (Format-InventoryMigrationSummaryLine -Hostname $entry.Hostname -Status $entry.Status)
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " MIGRACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Carpetas procesadas: $($results.Count)"
    Write-Host "Errores:             $errorCount"
    Write-Host ""

    return [ordered]@{
        Success = ($errorCount -eq 0)
        Results = $results
        ErrorCount = $errorCount
    }
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " ERROR AL MIGRAR LAS CARPETAS DE EQUIPOS" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    return [ordered]@{
        Success = $false
        ErrorMessage = $_.Exception.Message
    }
}
