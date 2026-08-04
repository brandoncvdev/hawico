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

    $roots = if ($childrenByParent.ContainsKey('')) { $childrenByParent[''] } else { @() }
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

        $children = if ($childrenByParent.ContainsKey($id)) { $childrenByParent[$id] } else { @() }
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
            return $menu[$selectedIndex - 1].Name
        }

        Write-Host "Opción inválida." -ForegroundColor Yellow
    }
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
        [AllowNull()][object[]]$OrganizationUnits = @()
    )

    $manualFields = @()
    $hasOrganizationUnits = @($OrganizationUnits).Count -gt 0

    foreach ($key in $FieldKeys) {
        # doc07-Catalog-System.md: when an organization unit catalog is
        # configured, the technician picks from it instead of typing free
        # text — but only for this one field, and only when a catalog was
        # actually supplied (backward-compatible free text otherwise).
        $rawValue = if ($key -eq 'assignment.organizationUnitId' -and $hasOrganizationUnits) {
            Read-InventoryOrganizationUnitSelection -Units $OrganizationUnits -Prompter $Prompter
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
