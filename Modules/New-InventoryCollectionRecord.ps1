function Get-InventoryRecordPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($PropertyName)) {
            return $Object[$PropertyName]
        }

        return $null
    }

    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }

    return $null
}

function Get-NormalizedInventoryIdentifier {
    param([AllowNull()][object]$Value)

    $identifier = Get-SafeString $Value
    if ($null -eq $identifier) {
        return $null
    }

    $normalized = $identifier.ToUpperInvariant()
    $placeholder = $normalized -replace '[^A-Z0-9]', ''
    $invalidValues = @(
        'DEFAULTSTRING',
        'TOBEFILLEDBYOEM',
        'UNKNOWN',
        'NONE',
        'NOTSPECIFIED',
        'SYSTEMSERIALNUMBER',
        'INVALID',
        'NA'
    )

    if ($invalidValues -contains $placeholder) {
        return $null
    }

    if ($placeholder -match '^0+$' -or $placeholder -match '^F+$') {
        return $null
    }

    return $normalized
}

function New-InventoryAssetIdentity {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory identity value without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][object]$Computer,
        [Parameter(Mandatory)][object]$BIOS
    )

    $serialNumber = Get-NormalizedInventoryIdentifier `
        (Get-InventoryRecordPropertyValue -Object $BIOS -PropertyName 'SerialNumber')
    $systemUuid = Get-NormalizedInventoryIdentifier `
        (Get-InventoryRecordPropertyValue -Object $Computer -PropertyName 'UUID')

    $preferredIdentifier = $null
    if ($null -ne $serialNumber) {
        $preferredIdentifier = [ordered]@{
            Type = 'SerialNumber'
            Value = $serialNumber
        }
    }
    elseif ($null -ne $systemUuid) {
        $preferredIdentifier = [ordered]@{
            Type = 'SystemUuid'
            Value = $systemUuid
        }
    }

    return [ordered]@{
        AssetId = $null
        SerialNumber = $serialNumber
        SystemUuid = $systemUuid
        Manufacturer = Get-SafeString (
            Get-InventoryRecordPropertyValue -Object $Computer -PropertyName 'Manufacturer'
        )
        Model = Get-SafeString (
            Get-InventoryRecordPropertyValue -Object $Computer -PropertyName 'Model'
        )
        ComputerName = Get-SafeString (
            Get-InventoryRecordPropertyValue -Object $Computer -PropertyName 'Hostname'
        )
        PreferredIdentifier = $preferredIdentifier
        Status = if ($null -eq $preferredIdentifier) { 'NeedsReview' } else { 'Identified' }
    }
}

function Get-InventoryCollectionIdSuffix {
    param([AllowNull()][object]$PreferredIdentifier)

    if ($null -ne $PreferredIdentifier) {
        $value = Get-SafeString $PreferredIdentifier.Value
        if ($null -ne $value) {
            return $value.Substring(0, [Math]::Min(8, $value.Length))
        }
    }

    return 'UNK' + ([guid]::NewGuid().ToString('N').Substring(0, 5).ToUpperInvariant())
}

function New-InventoryCollectionRecord {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory record value without changing system state.'
    )]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Inventory,
        [string]$CollectionId,
        [string]$SessionId = 'SES-UNASSIGNED',
        [string]$CollectorVersion = (Get-CollectorVersion -BasePath (Split-Path -Parent $PSScriptRoot)),
        [datetimeoffset]$CollectedAt = [datetimeoffset]::Now,
        [AllowNull()][object[]]$ManualFields = @(),
        [AllowNull()][object[]]$Errors = @()
    )

    $assetIdentity = New-InventoryAssetIdentity `
        -Computer $Inventory.Computer `
        -BIOS $Inventory.BIOS

    if ([string]::IsNullOrWhiteSpace($CollectionId)) {
        $suffix = Get-InventoryCollectionIdSuffix -PreferredIdentifier $assetIdentity.PreferredIdentifier
        $CollectionId = 'COL-{0}-{1}' -f `
            $CollectedAt.ToString('yyyyMMdd-HHmmssfff'), `
            $suffix
    }

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId = 'SES-UNASSIGNED'
    }

    return [ordered]@{
        ContractVersion = '1.0'
        CollectionId = $CollectionId
        Asset = $assetIdentity
        SessionId = $SessionId
        CollectedAt = $CollectedAt.ToString('o')
        CollectorVersion = $CollectorVersion
        ComputerName = $assetIdentity.ComputerName
        TechnicalData = $Inventory
        ManualFields = @($ManualFields)
        Assessments = @()
        Errors = @($Errors)
    }
}
