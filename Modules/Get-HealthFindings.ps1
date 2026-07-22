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
    param(
        [string]$Id,
        [string]$Category,
        [string]$Severity,
        [string]$Title,
        [string]$Description,
        [object]$Evidence,
        [string]$RecommendationId,
        [int]$Impact
    )
    return [pscustomobject][ordered]@{
        Id = $Id
        Category = $Category
        Severity = $Severity
        Title = $Title
        Description = $Description
        Evidence = $Evidence
        RecommendationId = $RecommendationId
        ScoreImpact = -$Impact
    }
}

function Add-HealthFinding {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Id,
        [string]$Category,
        [string]$Severity,
        [string]$Title,
        [string]$Description,
        [object]$Evidence,
        [string]$RecommendationId,
        [int]$Impact
    )
    $List.Add((ConvertTo-HealthFindingRecord -Id $Id -Category $Category -Severity $Severity -Title $Title -Description $Description -Evidence $Evidence -RecommendationId $RecommendationId -Impact $Impact))
}

function Get-HealthFinding {
    param([Parameter(Mandatory)][object]$Metrics)
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $memory = Get-HealthMetricValue -Object $Metrics -Name 'Memory'
    if ($null -ne $memory) {
        $usage = Get-HealthMetricValue -Object $memory -Name 'UsagePercent'
        $legacyMatching = Get-HealthMetricValue -Object $memory -Name 'MatchingSamplePercent'
        if ($null -ne $usage) {
            $memoryRule = $null
            if ($usage -ge 95) { $memoryRule = @('MEM-001', 'Critical', 25, 'SamplesAtOrAbove95Percent', 'Critical sustained memory utilization') }
            elseif ($usage -ge 85) { $memoryRule = @('MEM-002', 'High', 15, 'SamplesAtOrAbove85Percent', 'High sustained memory utilization') }
            elseif ($usage -ge 70) { $memoryRule = @('MEM-003', 'Medium', 8, 'SamplesAtOrAbove70Percent', 'Elevated sustained memory utilization') }
            if ($null -ne $memoryRule) {
                $matching = Get-HealthMetricValue -Object $memory -Name $memoryRule[3]
                if ($null -eq $matching) { $matching = $legacyMatching }
                if ($matching -ge 80) {
                    $evidence = [ordered]@{ AverageUsagePercent = $usage; PeakUsagePercent = Get-HealthMetricValue -Object $memory -Name 'PeakUsagePercent'; MatchingSamplePercent = $matching }
                    Add-HealthFinding -List $findings -Id $memoryRule[0] -Category 'Memory' -Severity $memoryRule[1] -Title $memoryRule[4] -Description 'Memory utilization met the rule threshold during at least 80 percent of valid samples.' -Evidence $evidence -RecommendationId 'REC-MEM-001' -Impact $memoryRule[2]
                }
            }
        }
        $available = Get-HealthMetricValue -Object $memory -Name 'AvailableMemoryMB'
        $availableMatching = Get-HealthMetricValue -Object $memory -Name 'SamplesBelow1024MB'
        if ($null -eq $availableMatching) { $availableMatching = $legacyMatching }
        if ($null -ne $available -and $available -lt 1024 -and $availableMatching -ge 80) {
            Add-HealthFinding -List $findings -Id 'MEM-004' -Category 'Memory' -Severity 'High' -Title 'Sustained low available memory' -Description 'Available memory remained below 1024 MB during at least 80 percent of valid samples.' -Evidence ([ordered]@{ MinimumAvailableMB = $available; MatchingSamplePercent = $availableMatching }) -RecommendationId 'REC-MEM-001' -Impact 10
        }
    }
    $storage = Get-HealthMetricValue -Object $Metrics -Name 'Storage'
    if ($null -ne $storage) {
        $health = Get-HealthMetricValue -Object $storage -Name 'HealthStatus'
        $free = Get-HealthMetricValue -Object $storage -Name 'SystemFreePercent'
        if ($null -ne $health -and $health -ne 'Unknown' -and $health -ne 'Healthy') {
            Add-HealthFinding -List $findings -Id 'STO-001' -Category 'Storage' -Severity 'Critical' -Title 'Storage health is degraded' -Description 'Windows reported an explicit non-healthy state for a physical disk.' -Evidence ([ordered]@{ HealthStatus = $health }) -RecommendationId 'REC-STO-001' -Impact 35
        }
        if ($null -ne $free -and $free -lt 10) {
            Add-HealthFinding -List $findings -Id 'STO-002' -Category 'Storage' -Severity 'Critical' -Title 'Critical system volume free space' -Description 'The operating-system volume has less than 10 percent free space.' -Evidence ([ordered]@{ SystemFreePercent = $free }) -RecommendationId 'REC-STO-002' -Impact 20
        }
        elseif ($null -ne $free -and $free -lt 20) {
            Add-HealthFinding -List $findings -Id 'STO-003' -Category 'Storage' -Severity 'High' -Title 'Low system volume free space' -Description 'The operating-system volume has between 10 and 20 percent free space.' -Evidence ([ordered]@{ SystemFreePercent = $free }) -RecommendationId 'REC-STO-002' -Impact 10
        }
        if ((Get-HealthMetricValue -Object $storage -Name 'SystemMediaType') -eq 'HDD') {
            Add-HealthFinding -List $findings -Id 'STO-004' -Category 'Storage' -Severity 'Medium' -Title 'System volume uses rotational storage' -Description 'The operating-system disk was identified as an HDD.' -Evidence ([ordered]@{ SystemMediaType = 'HDD' }) -RecommendationId 'REC-STO-003' -Impact 5
        }
        $diskEventCount = Get-HealthMetricValue -Object $storage -Name 'DiskEventCount'
        if ($diskEventCount -ge 3) {
            Add-HealthFinding -List $findings -Id 'STO-005' -Category 'Storage' -Severity 'High' -Title 'Repeated storage events' -Description 'At least three storage-provider events occurred in the configured period.' -Evidence ([ordered]@{ DiskEventCount = $diskEventCount }) -RecommendationId 'REC-STO-004' -Impact 15
        }
    }
    $cpu = Get-HealthMetricValue -Object $Metrics -Name 'CPU'
    if ($null -ne $cpu) {
        $average = Get-HealthMetricValue -Object $cpu -Name 'AverageUsagePercent'
        $high = Get-HealthMetricValue -Object $cpu -Name 'SamplesAtOrAbove90Percent'
        $cpuEvidence = [ordered]@{ AverageUsagePercent = $average; PeakUsagePercent = Get-HealthMetricValue -Object $cpu -Name 'PeakUsagePercent'; MatchingSamplePercent = $high }
        if ($high -ge 80) {
            Add-HealthFinding -List $findings -Id 'CPU-001' -Category 'CPU' -Severity 'High' -Title 'Sustained CPU saturation' -Description 'CPU usage reached at least 90 percent during at least 80 percent of valid samples.' -Evidence $cpuEvidence -RecommendationId 'REC-CPU-001' -Impact 20
        }
        elseif ($average -ge 80) {
            Add-HealthFinding -List $findings -Id 'CPU-002' -Category 'CPU' -Severity 'Medium' -Title 'Elevated average CPU usage' -Description 'Average CPU usage remained between 80 and 90 percent.' -Evidence $cpuEvidence -RecommendationId 'REC-CPU-001' -Impact 10
        }
    }
    $events = Get-HealthMetricValue -Object $Metrics -Name 'Events'
    if ($null -ne $events) {
        $wheaCount = Get-HealthMetricValue -Object $events -Name 'WHEACount'
        $kernelPowerCount = Get-HealthMetricValue -Object $events -Name 'KernelPowerCount'
        $applicationFailureCount = Get-HealthMetricValue -Object $events -Name 'ApplicationFailureCount'
        if ($wheaCount -ge 1) {
            Add-HealthFinding -List $findings -Id 'EVT-001' -Category 'Events' -Severity 'Critical' -Title 'Hardware error events detected' -Description 'One or more WHEA-Logger events occurred in the configured period.' -Evidence ([ordered]@{ WHEACount = $wheaCount }) -RecommendationId 'REC-EVT-001' -Impact 20
        }
        if ($kernelPowerCount -ge 2) {
            Add-HealthFinding -List $findings -Id 'EVT-002' -Category 'Events' -Severity 'High' -Title 'Repeated unexpected shutdowns' -Description 'At least two Kernel-Power events occurred in the configured period.' -Evidence ([ordered]@{ KernelPowerCount = $kernelPowerCount }) -RecommendationId 'REC-EVT-002' -Impact 12
        }
        if ($applicationFailureCount -ge 5) {
            Add-HealthFinding -List $findings -Id 'EVT-003' -Category 'Events' -Severity 'Medium' -Title 'Repeated application failures' -Description 'At least five application error or hang events occurred in the configured period.' -Evidence ([ordered]@{ ApplicationFailureCount = $applicationFailureCount }) -RecommendationId 'REC-EVT-003' -Impact 8
        }
    }
    return @($findings | ForEach-Object { $_ })
}

function Get-HealthRecommendation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings)
    $catalog = @{
        'REC-MEM-001' = @('Review memory pressure', 'Identify sustained memory consumers and validate whether installed capacity matches the workload.')
        'REC-STO-001' = @('Validate degraded storage', 'Back up important data and run the manufacturer diagnostic before considering disk replacement.')
        'REC-STO-002' = @('Recover system volume space', 'Remove or archive nonessential data after validating retention requirements.')
        'REC-STO-003' = @('Evaluate solid-state storage', 'Consider SSD storage when workload latency is constrained by the system HDD.')
        'REC-STO-004' = @('Investigate storage events', 'Review the correlated storage events and vendor diagnostics before changing hardware.')
        'REC-CPU-001' = @('Review sustained CPU workload', 'Identify consistently CPU-intensive processes and validate workload sizing.')
        'REC-EVT-001' = @('Investigate hardware errors', 'Correlate WHEA events with vendor diagnostics and recent hardware changes.')
        'REC-EVT-002' = @('Investigate unexpected shutdowns', 'Validate power delivery, thermal conditions, drivers, and shutdown history.')
        'REC-EVT-003' = @('Investigate repeated application failures', 'Correlate failing applications with updates, dependencies, and available vendor fixes.')
    }
    $recommendations = @()
    foreach ($group in @($Findings | Where-Object { -not [string]::IsNullOrWhiteSpace($_.RecommendationId) } | Group-Object RecommendationId)) {
        if (-not $catalog.ContainsKey($group.Name)) { continue }
        $recommendations += [pscustomobject][ordered]@{
            Id = $group.Name
            Title = $catalog[$group.Name][0]
            Description = $catalog[$group.Name][1]
            FindingIds = @($group.Group.Id)
        }
    }
    return $recommendations
}
