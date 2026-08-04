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

function Read-InventoryManualCapture {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Reads manual field values from the technician without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][string[]]$FieldKeys,
        [AllowNull()][string]$Technician,
        [scriptblock]$Prompter = { param($Key) Read-Host "  $Key" }
    )

    $manualFields = @()

    foreach ($key in $FieldKeys) {
        $rawValue = & $Prompter $key
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
