function New-InventoryManualFieldValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory field value without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][string]$RawValue,
        [AllowNull()][string]$Technician,
        [datetimeoffset]$CapturedAt = [datetimeoffset]::Now,
        [string]$Source = 'VisitCapture',
        [string]$Confidence = 'Unconfirmed'
    )

    $value = Get-SafeString $RawValue
    if ($null -eq $value) {
        return $null
    }

    return [ordered]@{
        Key = $Key
        Value = $value
        Source = $Source
        CapturedAt = $CapturedAt.ToString('o')
        CapturedBy = $Technician
        Confidence = $Confidence
        Status = 'Present'
    }
}

function Get-InventoryDefaultFieldLabel {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Looks up a hardcoded label without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$Key
    )

    # Same 6 field keys config.json/org packages already ask about
    # (docs/07-Catalog-System.md, docs/INSTITUTIONAL_EXCEL_MAPPING.md); text
    # kept consistent with labels already used elsewhere in the project
    # (custom-fields.json's "label" for these same two keys, for instance).
    $defaultLabels = @{
        'assignment.user.fullName' = 'Nombre completo del usuario'
        'assignment.organizationUnitId' = 'Dirección'
        'assignment.departmentUnitId' = 'Departamento'
        'assignment.locationId' = 'Ubicación'
        'asset.assetTag' = 'Número patrimonial'
        'collection.observations' = 'Observaciones'
    }

    if ($defaultLabels.ContainsKey($Key)) {
        return $defaultLabels[$Key]
    }

    return $null
}

function Get-InventoryFieldLabel {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Resolves a display label without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][hashtable]$FieldLabels = @{}
    )

    # Priority: an organization's own custom-fields.json label (loaded by
    # Get-InventoryCustomFieldDefinitions) wins over the hardcoded default,
    # which wins over showing the raw dotted key as a last resort — should
    # only happen for a custom field the organization never labeled.
    if ($null -ne $FieldLabels -and $FieldLabels.ContainsKey($Key)) {
        return $FieldLabels[$Key]
    }

    $defaultLabel = Get-InventoryDefaultFieldLabel -Key $Key
    if ($null -ne $defaultLabel) {
        return $defaultLabel
    }

    return $Key
}

function ConvertTo-InventoryOrganizationUnitMenuEntries {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Formats an in-memory menu into display strings without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Menu
    )

    # Extracted out of the `for` loop that used to Write-Host each line
    # directly inside Read-InventoryOrganizationUnitSelection, so the exact
    # print format (number + Depth-based indent + Name) is directly testable
    # and reusable by the multi-column layout below.
    $safeMenu = @(@($Menu) | Where-Object { $null -ne $_ })

    $entries = @()
    for ($i = 0; $i -lt $safeMenu.Count; $i++) {
        $indent = '  ' * $safeMenu[$i].Depth
        $entries += "{0,2}. {1}{2}" -f ($i + 1), $indent, $safeMenu[$i].Name
    }

    return ,@($entries)
}

function Get-InventoryMenuColumnCount {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Computes a layout number without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][int]$MaxEntryWidth,
        [AllowNull()][object]$ConsoleWidth
    )

    # Console width unknown/non-positive (piped output, redirected host,
    # etc.): 2 fixed columns is the safe default the user asked for.
    if ($null -eq $ConsoleWidth -or [int]$ConsoleWidth -le 0) {
        return 2
    }

    $cellWidth = $MaxEntryWidth + 4
    $columnsThatFit = [Math]::Floor([int]$ConsoleWidth / $cellWidth)

    if ($columnsThatFit -ge 3) {
        return 3
    }

    return 2
}

function Format-InventoryMenuColumns {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Formats in-memory strings into printable lines without changing system state.'
    )]
    param(
        [AllowNull()][string[]]$Entries,
        [Parameter(Mandatory)][int]$Columns
    )

    $safeEntries = @(@($Entries) | Where-Object { $null -ne $_ })

    if ($safeEntries.Count -eq 0) {
        return ,@()
    }

    $cellWidth = (($safeEntries | Measure-Object -Property Length -Maximum).Maximum) + 4
    $rowCount = [Math]::Ceiling($safeEntries.Count / $Columns)

    $lines = @()
    for ($row = 0; $row -lt $rowCount; $row++) {
        $lineParts = @()
        for ($col = 0; $col -lt $Columns; $col++) {
            $index = $row * $Columns + $col
            if ($index -ge $safeEntries.Count) {
                break
            }

            # Row-major fill (item 1 top-left, item 2 to its right, ...): no
            # padding on the last cell of a row — either the row is full
            # (last column) or the catalog ran out of items (last overall
            # entry) — so no trailing spaces are ever printed.
            $isLastCellInRow = ($col -eq $Columns - 1) -or ($index -eq $safeEntries.Count - 1)
            if ($isLastCellInRow) {
                $lineParts += $safeEntries[$index]
            }
            else {
                $lineParts += $safeEntries[$index].PadRight($cellWidth)
            }
        }
        $lines += ($lineParts -join '')
    }

    return ,@($lines)
}

function Get-InventoryConsoleWidth {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads the host console width without changing system state.'
    )]
    param()

    # Thin, deliberately non-pure wrapper around $Host.UI.RawUI: behaves
    # differently in a real Windows console vs. a non-interactive host (like
    # Pester's), so the only thing worth guaranteeing here is "never throws,
    # never returns a bogus non-positive width" — Get-InventoryMenuColumnCount
    # already treats $null the same as "could not be determined".
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        if ($width -gt 0) {
            return $width
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-InventoryOrganizationUnitMenuChildren {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Looks up an in-memory child list without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][hashtable]$ChildrenByParent,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ParentKey
    )

    # Extracted out of what used to be an inline
    # `$roots = if ($childrenByParent.ContainsKey($k)) { $childrenByParent[$k] } else { @() }`
    # so the array-collapse fix is directly testable: that inline form
    # routes the ContainsKey-branch's value (an array, possibly with one
    # element) through the same output-stream boundary a `return` does, and
    # PowerShell 7 (used to run this suite) silently tolerates the resulting
    # collapsed scalar's .Count/[0] indexing in a way Windows PowerShell 5.1
    # does not — the exact blind spot that broke the collector for real
    # elsewhere in this codebase. Named "...MenuChildren" (not just
    # "...Children") to stay distinct from Get-InventoryOrganizationUnitChildren
    # below, which filters the raw catalog by parentId for the
    # Dirección→Departamento cascade — same-sounding purpose, different
    # signature and caller.
    if ($ChildrenByParent.ContainsKey($ParentKey)) {
        return ,@($ChildrenByParent[$ParentKey])
    }

    return ,@()
}

function ConvertTo-InventoryOrganizationUnitMenu {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Projects a catalog into an in-memory menu without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Units
    )

    $allUnits = @(@($Units) | Where-Object { $null -ne $_ })

    $childrenByParent = @{}
    foreach ($unit in $allUnits) {
        $parentKey = if ($null -eq $unit.parentId) { '' } else { [string]$unit.parentId }
        if (-not $childrenByParent.ContainsKey($parentKey)) {
            $childrenByParent[$parentKey] = @()
        }
        $childrenByParent[$parentKey] += $unit
    }

    foreach ($parentKey in @($childrenByParent.Keys)) {
        $childrenByParent[$parentKey] = @(
            $childrenByParent[$parentKey] | Sort-Object { [double]$_.sortOrder }
        )
    }

    $menu = @()
    $visitedIds = @{}

    # Explicit stack instead of recursion: a nested function here would need
    # to mutate $menu/$visitedIds through a closure, and (as found earlier
    # in this codebase) plain variable reassignment inside a nested
    # PowerShell scope does not reliably write back to the enclosing scope.
    # Pushing children in reverse sortOrder makes them pop back out in
    # ascending order, giving parent-then-children (pre-order) traversal.
    $stack = [System.Collections.Generic.Stack[object]]::new()

    $roots = Get-InventoryOrganizationUnitMenuChildren -ChildrenByParent $childrenByParent -ParentKey ''
    for ($i = $roots.Count - 1; $i -ge 0; $i--) {
        $stack.Push([PSCustomObject]@{ Unit = $roots[$i]; Depth = 0 })
    }

    while ($stack.Count -gt 0) {
        $frame = $stack.Pop()
        $unit = $frame.Unit
        $id = [string]$unit.id

        if ($visitedIds.ContainsKey($id)) {
            # Cycle guard: this id already appeared once. A malformed
            # catalog (duplicate id, self-referential parentId) could
            # otherwise re-discover the same node forever; cut this branch
            # instead of hanging the collector.
            continue
        }
        $visitedIds[$id] = $true

        $menu += [PSCustomObject][ordered]@{
            Id = $id
            Name = [string]$unit.name
            Depth = $frame.Depth
        }

        $children = Get-InventoryOrganizationUnitMenuChildren -ChildrenByParent $childrenByParent -ParentKey $id
        for ($i = $children.Count - 1; $i -ge 0; $i--) {
            $stack.Push([PSCustomObject]@{ Unit = $children[$i]; Depth = $frame.Depth + 1 })
        }
    }

    return ,@($menu)
}

function Read-InventoryOrganizationUnitSelection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads a catalog selection from the technician without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Units,
        [scriptblock]$Prompter = { param($Key) Read-Host "  $Key" },
        [AllowNull()][string]$Label = $null
    )

    # No extra @() around this call: ConvertTo-InventoryOrganizationUnitMenu
    # already returns a correctly-flat array via its own `,@()` return
    # guard, and wrapping an already-comma-guarded call in another @()
    # re-nests it into a 1-element array whose sole element is the real
    # array — a distinct variant of the single-element array-unwrap bug
    # already documented elsewhere in this codebase (confirmed empirically
    # while fixing this).
    $menu = ConvertTo-InventoryOrganizationUnitMenu -Units $Units

    if ($menu.Count -eq 0) {
        # No catalog configured: nothing to choose from, show nothing.
        return $null
    }

    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($Label)) {
        # "Labels legibles" task: identifies which field this catalog menu
        # is for (e.g. "Dirección"), since none of the prompts below it ever
        # print the field key/label on their own.
        Write-Host "  ${Label}:"
    }

    # 2-or-3-column layout instead of one item per line: with real catalogs
    # (48 departments in institucion-principal, for instance) a single
    # column means a lot of vertical scroll. Console width detection is
    # isolated in Get-InventoryConsoleWidth (thin, non-pure) so the actual
    # layout math (these three calls) stays pure and testable.
    $entries = ConvertTo-InventoryOrganizationUnitMenuEntries -Menu $menu
    $maxEntryWidth = ($entries | Measure-Object -Property Length -Maximum).Maximum
    $consoleWidth = Get-InventoryConsoleWidth
    $columns = Get-InventoryMenuColumnCount -MaxEntryWidth $maxEntryWidth -ConsoleWidth $consoleWidth
    $lines = Format-InventoryMenuColumns -Entries $entries -Columns $columns

    foreach ($line in $lines) {
        Write-Host "  $line"
    }

    while ($true) {
        $answer = Get-SafeString (& $Prompter 'Seleccione un número (Enter para omitir)')

        if ($null -eq $answer) {
            return $null
        }

        $selectedIndex = 0
        $isNumeric = [int]::TryParse($answer, [ref]$selectedIndex)

        if ($isNumeric -and $selectedIndex -ge 1 -and $selectedIndex -le $menu.Count) {
            $selected = $menu[$selectedIndex - 1]
            return [PSCustomObject]@{ Id = $selected.Id; Name = $selected.Name }
        }

        Write-Host "Opción inválida." -ForegroundColor Yellow
    }
}

function Get-InventoryOrganizationUnitChildren {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Filters an in-memory catalog without changing system state.'
    )]
    param(
        [AllowNull()][object[]]$Units,
        [AllowNull()][string]$ParentId
    )

    $allUnits = @(@($Units) | Where-Object { $null -ne $_ })
    $children = @(
        $allUnits |
            Where-Object { [string]$_.parentId -eq [string]$ParentId } |
            Sort-Object { [double]$_.sortOrder }
    )

    # ConvertTo-InventoryOrganizationUnitMenu only treats a unit as a root
    # when its own parentId is null: it has no notion that $ParentId was
    # excluded from this subset, so without this, every child here would
    # still point at its real (now-absent) parent and the DFS would find
    # zero roots — an empty, silently-skipped menu instead of a flat
    # department list. Nulling parentId on a clone (the caller's original
    # catalog objects are never mutated) turns "the children of X" into
    # "the roots of this standalone sub-menu", which is exactly what
    # feeding this straight into Read-InventoryOrganizationUnitSelection
    # needs; every other property is preserved as-is.
    return ,@(
        $children | ForEach-Object {
            [PSCustomObject]@{
                id = $_.id
                name = $_.name
                type = $_.type
                parentId = $null
                sortOrder = $_.sortOrder
            }
        }
    )
}

function Read-InventoryManualCapture {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads manual field values from the technician without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string[]]$FieldKeys,
        [AllowNull()][string]$Technician,
        [scriptblock]$Prompter = { param($Key) Read-Host "  $Key" },
        [AllowNull()][object[]]$OrganizationUnits = @(),
        [AllowNull()][object[]]$DepartmentUnits = @(),
        [AllowNull()][hashtable]$PresetValues = @{},
        [AllowNull()][hashtable]$DefaultValues = @{},
        [AllowNull()][hashtable]$FieldLabels = @{}
    )

    $manualFields = @()
    $hasOrganizationUnits = @($OrganizationUnits).Count -gt 0
    $hasDepartmentUnits = @($DepartmentUnits).Count -gt 0
    $hasPresetValues = $null -ne $PresetValues
    $hasDefaultValues = $null -ne $DefaultValues
    # Set only while walking assignment.organizationUnitId, and read right
    # after by assignment.departmentUnitId (which must come later in
    # -FieldKeys for the cascade to work): the Id of whatever direction the
    # technician just picked, so the next field's menu can be filtered down
    # to that direction's own children instead of the whole catalog again.
    $selectedOrganizationUnitId = $null

    foreach ($key in $FieldKeys) {
        # doc07-Catalog-System.md "Reutilización durante visita": a value
        # already decided for the current visit (e.g. Dirección/Departamento
        # picked once for a batch of machines by the launcher) is used as-is
        # — no prompt, no menu — ahead of every other resolution strategy
        # below. Generic by design: not specific to any one field key.
        $rawValue = if ($hasPresetValues -and $PresetValues.ContainsKey($key)) {
            $PresetValues[$key]
        }
        # Host-history reuse: a value captured for this same computer on a
        # prior collection is offered back as a visible, editable default —
        # unlike -PresetValues above, the prompt is still shown, it is only
        # pre-filled. Checked after -PresetValues (an already-resolved
        # visit-level value always wins over old host history) and before
        # the catalog/cascade/free-text prompt below, so a default replaces
        # the catalog picker with a simple "Enter para mantener" prompt
        # instead of forcing the technician back through the whole menu.
        elseif ($hasDefaultValues -and $DefaultValues.ContainsKey($key)) {
            $fieldLabel = Get-InventoryFieldLabel -Key $key -FieldLabels $FieldLabels
            $previousValue = $DefaultValues[$key]
            $answer = Get-SafeString (& $Prompter "$fieldLabel (Enter para mantener '$previousValue')")
            if ($null -ne $answer) { $answer } else { $previousValue }
        }
        # doc07-Catalog-System.md: when an organization unit catalog is
        # configured, the technician picks from it instead of typing free
        # text — but only for this one field, and only when a catalog was
        # actually supplied (backward-compatible free text otherwise).
        elseif ($key -eq 'assignment.organizationUnitId' -and $hasOrganizationUnits) {
            # ConvertTo-InventoryOrganizationUnitMenu renders the FULL tree of
            # whatever -Units it gets, children included — passing the whole
            # catalog here would show every Departamento nested inside this
            # "Dirección" prompt too, letting the technician pick a leaf
            # (department-level) entry by mistake at the direction step. Only
            # root-level units (parentId = null) belong in this first prompt;
            # the cascade further below already narrows to the selected
            # direction's own children for the Departamento field.
            $fieldLabel = Get-InventoryFieldLabel -Key $key -FieldLabels $FieldLabels
            $rootOrganizationUnits = Get-InventoryOrganizationUnitChildren -Units $OrganizationUnits -ParentId $null
            $selection = Read-InventoryOrganizationUnitSelection -Units $rootOrganizationUnits -Prompter $Prompter -Label $fieldLabel
            $selectedOrganizationUnitId = if ($null -ne $selection) { $selection.Id } else { $null }
            if ($null -ne $selection) { $selection.Name } else { $null }
        }
        elseif ($key -eq 'assignment.departmentUnitId' -and $hasDepartmentUnits) {
            # doc07-Catalog-System.md, flat/independent mode: some
            # institutions' Dirección and Departamento have no reliable
            # parent-child relationship to derive a cascade from (rows don't
            # line up between the two lists). When -DepartmentUnits is
            # supplied it is a second, wholly independent catalog picked the
            # same way as assignment.organizationUnitId itself — never
            # filtered by $selectedOrganizationUnitId. This takes priority
            # over the cascade below even if -OrganizationUnits also happens
            # to carry a real hierarchy, since supplying -DepartmentUnits is
            # the explicit signal that this organization's Departamento is
            # not actually a child of Dirección.
            $fieldLabel = Get-InventoryFieldLabel -Key $key -FieldLabels $FieldLabels
            $selection = Read-InventoryOrganizationUnitSelection -Units $DepartmentUnits -Prompter $Prompter -Label $fieldLabel
            if ($null -ne $selection) { $selection.Name } else { $null }
        }
        elseif ($key -eq 'assignment.departmentUnitId') {
            # Cascade, not a second free catalog pick: this field only ever
            # offers the direct children of whatever direction was just
            # selected above. No direction selected (skipped, no catalog) or
            # a direction with no children both mean there is nothing
            # meaningful to ask, so the technician is never prompted at all
            # — this never falls back to free text.
            $childUnits = if ($null -ne $selectedOrganizationUnitId) {
                Get-InventoryOrganizationUnitChildren -Units $OrganizationUnits -ParentId $selectedOrganizationUnitId
            }
            else {
                ,@()
            }

            if (@($childUnits).Count -gt 0) {
                $fieldLabel = Get-InventoryFieldLabel -Key $key -FieldLabels $FieldLabels
                $selection = Read-InventoryOrganizationUnitSelection -Units $childUnits -Prompter $Prompter -Label $fieldLabel
                if ($null -ne $selection) { $selection.Name } else { $null }
            }
            else {
                $null
            }
        }
        else {
            $fieldLabel = Get-InventoryFieldLabel -Key $key -FieldLabels $FieldLabels
            & $Prompter $fieldLabel
        }

        $fieldValue = New-InventoryManualFieldValue -Key $key -RawValue $rawValue -Technician $Technician
        if ($null -ne $fieldValue) {
            $manualFields += $fieldValue
        }
    }

    # The unary comma forces PowerShell to emit the array itself as a single
    # pipeline object; without it, an array with exactly one element gets
    # unrolled and the caller receives the bare FieldValue instead of a
    # one-element array.
    return ,@($manualFields)
}
