function New-InventoryCollectionSession {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory session value without changing system state.'
    )]
    param(
        [AllowNull()][string]$SessionId,
        [AllowNull()][string]$OrganizationId,
        [string]$ProfileId = 'basic-inventory',
        [AllowNull()][string]$Technician,
        [datetimeoffset]$StartedAt = [datetimeoffset]::Now,
        [int]$EquipmentCount = 0,
        [int]$PendingCount = 0
    )

    $normalizedSessionId = Get-SafeString $SessionId
    $isUnassigned = ($null -eq $normalizedSessionId) -or ($normalizedSessionId -eq 'SES-UNASSIGNED')

    if ($isUnassigned) {
        Write-Warning ('Ejecutando sin sesión de recolección asignada — esta captura debe ' +
            'revisarse antes de la consolidación institucional.')
    }

    return [ordered]@{
        SessionId = if ($null -ne $normalizedSessionId) { $normalizedSessionId } else { 'SES-UNASSIGNED' }
        OrganizationId = $OrganizationId
        ProfileId = $ProfileId
        Technician = $Technician
        StartedAt = $StartedAt.ToString('o')
        EndedAt = $null
        EquipmentCount = $EquipmentCount
        PendingCount = $PendingCount
        Status = if ($isUnassigned) { 'Unassigned' } else { 'Active' }
    }
}
