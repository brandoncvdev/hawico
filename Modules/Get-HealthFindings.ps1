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

function Get-HealthMetricValue {
    param([AllowNull()][object]$Object,[string]$Name)
    if($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name){return $null}
    return $Object.$Name
}
function ConvertTo-HealthFindingRecord {
    param([string]$Id,[string]$Category,[string]$Severity,[int]$Impact)
    return [pscustomobject][ordered]@{Id=$Id;Category=$Category;Severity=$Severity;ScoreImpact=-$Impact}
}
function Get-HealthFinding {
    param([Parameter(Mandatory)][object]$Metrics)
    $findings=@()
    $memory=Get-HealthMetricValue -Object $Metrics -Name 'Memory'
    if($null-ne $memory){
        $usage=Get-HealthMetricValue -Object $memory -Name 'UsagePercent';$matching=Get-HealthMetricValue -Object $memory -Name 'MatchingSamplePercent'
        if($null-ne $usage -and $matching -ge 80){
            if($usage-ge 95){$findings+=ConvertTo-HealthFindingRecord -Id 'MEM-001' -Category 'Memory' -Severity 'Critical' -Impact 25}
            elseif($usage-ge 85){$findings+=ConvertTo-HealthFindingRecord -Id 'MEM-002' -Category 'Memory' -Severity 'High' -Impact 15}
            elseif($usage-ge 70){$findings+=ConvertTo-HealthFindingRecord -Id 'MEM-003' -Category 'Memory' -Severity 'Medium' -Impact 8}
        }
        $available=Get-HealthMetricValue -Object $memory -Name 'AvailableMemoryMB'
        if($null-ne $available -and $available-lt 1024 -and $matching-ge 80){$findings+=ConvertTo-HealthFindingRecord -Id 'MEM-004' -Category 'Memory' -Severity 'High' -Impact 10}
    }
    $storage=Get-HealthMetricValue -Object $Metrics -Name 'Storage'
    if($null-ne $storage){
        $health=Get-HealthMetricValue -Object $storage -Name 'HealthStatus';$free=Get-HealthMetricValue -Object $storage -Name 'SystemFreePercent'
        if($null-ne $health -and $health-ne 'Unknown' -and $health-ne 'Healthy'){$findings+=ConvertTo-HealthFindingRecord -Id 'STO-001' -Category 'Storage' -Severity 'Critical' -Impact 35}
        if($null-ne $free){if($free-lt 10){$findings+=ConvertTo-HealthFindingRecord -Id 'STO-002' -Category 'Storage' -Severity 'Critical' -Impact 20}elseif($free-lt 20){$findings+=ConvertTo-HealthFindingRecord -Id 'STO-003' -Category 'Storage' -Severity 'High' -Impact 10}}
        if((Get-HealthMetricValue -Object $storage -Name 'SystemMediaType')-eq 'HDD'){$findings+=ConvertTo-HealthFindingRecord -Id 'STO-004' -Category 'Storage' -Severity 'Medium' -Impact 5}
        if((Get-HealthMetricValue -Object $storage -Name 'DiskEventCount')-ge 3){$findings+=ConvertTo-HealthFindingRecord -Id 'STO-005' -Category 'Storage' -Severity 'High' -Impact 15}
    }
    $cpu=Get-HealthMetricValue -Object $Metrics -Name 'CPU'
    if($null-ne $cpu){$average=Get-HealthMetricValue -Object $cpu -Name 'AverageUsagePercent';$high=Get-HealthMetricValue -Object $cpu -Name 'SamplesAtOrAbove90Percent';if($high-ge 80){$findings+=ConvertTo-HealthFindingRecord -Id 'CPU-001' -Category 'CPU' -Severity 'High' -Impact 20}elseif($average-ge 80){$findings+=ConvertTo-HealthFindingRecord -Id 'CPU-002' -Category 'CPU' -Severity 'Medium' -Impact 10}}
    return $findings
}
