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
        [scriptblock]$Prompter = { param($Key) Read-Host "  $Key" }
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
    for ($i = 0; $i -lt $menu.Count; $i++) {
        $indent = '  ' * $menu[$i].Depth
        Write-Host ("  {0,2}. {1}{2}" -f ($i + 1), $indent, $menu[$i].Name)
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
        [AllowNull()][object[]]$DepartmentUnits = @()
    )

    $manualFields = @()
    $hasOrganizationUnits = @($OrganizationUnits).Count -gt 0
    $hasDepartmentUnits = @($DepartmentUnits).Count -gt 0
    # Set only while walking assignment.organizationUnitId, and read right
    # after by assignment.departmentUnitId (which must come later in
    # -FieldKeys for the cascade to work): the Id of whatever direction the
    # technician just picked, so the next field's menu can be filtered down
    # to that direction's own children instead of the whole catalog again.
    $selectedOrganizationUnitId = $null

    foreach ($key in $FieldKeys) {
        # doc07-Catalog-System.md: when an organization unit catalog is
        # configured, the technician picks from it instead of typing free
        # text — but only for this one field, and only when a catalog was
        # actually supplied (backward-compatible free text otherwise).
        $rawValue = if ($key -eq 'assignment.organizationUnitId' -and $hasOrganizationUnits) {
            $selection = Read-InventoryOrganizationUnitSelection -Units $OrganizationUnits -Prompter $Prompter
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
            $selection = Read-InventoryOrganizationUnitSelection -Units $DepartmentUnits -Prompter $Prompter
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
                $selection = Read-InventoryOrganizationUnitSelection -Units $childUnits -Prompter $Prompter
                if ($null -ne $selection) { $selection.Name } else { $null }
            }
            else {
                $null
            }
        }
        else {
            & $Prompter $key
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
