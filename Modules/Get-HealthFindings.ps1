function Get-HealthScoreStatus {
    param([int]$Value)
    if ($Value -ge 90) { return "Healthy" }
    if ($Value -ge 75) { return "Attention" }
    if ($Value -ge 50) { return "Degraded" }
    return "Critical"
}

function Get-HealthSeverityRank {
    param([AllowNull()][string]$Severity)
    $ranks = @{ Info = 0; Low = 1; Medium = 2; High = 3; Critical = 4 }
    if ($null -ne $Severity -and $ranks.ContainsKey($Severity)) { return $ranks[$Severity] }
    return 0
}

function Get-HealthScore {
    param([Parameter(Mandatory)][object[]]$Categories)

    $evaluatedWeight = 0
    $totalDeduction = 0
    $normalized = @()

    foreach ($category in $Categories) {
        $weight = [int]$category.Weight
        $available = [bool]$category.Available
        $deduction = if ($available) {
            [math]::Max(0, [math]::Min($weight, [int]$category.Deduction))
        }
        else { 0 }

        if ($available) {
            $evaluatedWeight += $weight
            $totalDeduction += $deduction
        }

        $normalized += [pscustomobject][ordered]@{
            Name = [string]$category.Name
            Weight = $weight
            Available = $available
            Deduction = $deduction
            HighestSeverity = [string]$category.HighestSeverity
        }
    }

    $primary = "None"
    $candidates = @($normalized | Where-Object { $_.Available -and $_.Deduction -gt 0 })
    if ($candidates.Count -gt 0) {
        $order = @{ Storage = 0; Memory = 1; CPU = 2; Events = 3 }
        $primary = ($candidates | Sort-Object `
            @{ Expression = { -([double]$_.Deduction / [double]$_.Weight) } }, `
            @{ Expression = { -(Get-HealthSeverityRank $_.HighestSeverity) } }, `
            @{ Expression = { if ($order.ContainsKey($_.Name)) { $order[$_.Name] } else { 99 } } } |
            Select-Object -First 1).Name
    }

    $value = $null
    $status = "InsufficientData"
    if ($evaluatedWeight -ge 60) {
        $value = [int][math]::Round(100 * (1 - ([double]$totalDeduction / [double]$evaluatedWeight)))
        $status = Get-HealthScoreStatus -Value $value
    }

    return [ordered]@{
        Value = $value
        Status = $status
        ConfidencePercent = $evaluatedWeight
        ScoringVersion = "1.0"
        EvaluatedWeight = $evaluatedWeight
        TotalDeduction = $totalDeduction
        Categories = $normalized
        PrimaryBottleneck = $primary
    }
}
