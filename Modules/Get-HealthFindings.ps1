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
    if($null -eq $Object){return $null}
    if($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)){return $Object[$Name]}
    if($Object.PSObject.Properties.Name -notcontains $Name){return $null}
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
    param([Parameter(Mandatory)][object]$Metrics, [AllowNull()][object]$Thresholds)
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $memoryWarning = Get-HealthMetricValue -Object $Thresholds -Name 'MemoryWarningPercent'
    $memoryHigh = Get-HealthMetricValue -Object $Thresholds -Name 'MemoryHighPercent'
    $memoryCritical = Get-HealthMetricValue -Object $Thresholds -Name 'MemoryCriticalPercent'
    $minimumAvailable = Get-HealthMetricValue -Object $Thresholds -Name 'MinimumAvailableMemoryMB'
    $criticalFree = Get-HealthMetricValue -Object $Thresholds -Name 'CriticalFreeDiskPercent'
    $minimumFree = Get-HealthMetricValue -Object $Thresholds -Name 'MinimumFreeDiskPercent'
    if ($null -eq $memoryWarning) { $memoryWarning = 70 }
    if ($null -eq $memoryHigh) { $memoryHigh = 85 }
    if ($null -eq $memoryCritical) { $memoryCritical = 95 }
    if ($null -eq $minimumAvailable) { $minimumAvailable = 1024 }
    if ($null -eq $criticalFree) { $criticalFree = 10 }
    if ($null -eq $minimumFree) { $minimumFree = 20 }
    $memory = Get-HealthMetricValue -Object $Metrics -Name 'Memory'
    if ($null -ne $memory) {
        $usage = Get-HealthMetricValue -Object $memory -Name 'UsagePercent'
        $legacyMatching = Get-HealthMetricValue -Object $memory -Name 'MatchingSamplePercent'
        if ($null -ne $usage) {
            $memoryRule = $null
            if ($usage -ge $memoryCritical) { $memoryRule = @('MEM-001', 'Critical', 25, 'CriticalMatchingSamplePercent', 'SamplesAtOrAbove95Percent', 'Critical sustained memory utilization') }
            elseif ($usage -ge $memoryHigh) { $memoryRule = @('MEM-002', 'High', 15, 'HighMatchingSamplePercent', 'SamplesAtOrAbove85Percent', 'High sustained memory utilization') }
            elseif ($usage -ge $memoryWarning) { $memoryRule = @('MEM-003', 'Medium', 8, 'WarningMatchingSamplePercent', 'SamplesAtOrAbove70Percent', 'Elevated sustained memory utilization') }
            if ($null -ne $memoryRule) {
                $matching = Get-HealthMetricValue -Object $memory -Name $memoryRule[3]
                if ($null -eq $matching) { $matching = Get-HealthMetricValue -Object $memory -Name $memoryRule[4] }
                if ($null -eq $matching) { $matching = $legacyMatching }
                if ($matching -ge 80) {
                    $evidence = [ordered]@{ AverageUsagePercent = $usage; PeakUsagePercent = Get-HealthMetricValue -Object $memory -Name 'PeakUsagePercent'; MatchingSamplePercent = $matching }
                    Add-HealthFinding -List $findings -Id $memoryRule[0] -Category 'Memory' -Severity $memoryRule[1] -Title $memoryRule[5] -Description 'Memory utilization met the configured rule threshold during at least 80 percent of valid samples.' -Evidence $evidence -RecommendationId 'REC-MEM-001' -Impact $memoryRule[2]
                }
            }
        }
        $available = Get-HealthMetricValue -Object $memory -Name 'AvailableMemoryMB'
        $availableMatching = Get-HealthMetricValue -Object $memory -Name 'LowAvailableMatchingSamplePercent'
        if ($null -eq $availableMatching) { $availableMatching = Get-HealthMetricValue -Object $memory -Name 'SamplesBelow1024MB' }
        if ($null -eq $availableMatching) { $availableMatching = $legacyMatching }
        if ($null -ne $available -and $available -lt $minimumAvailable -and $availableMatching -ge 80) {
            Add-HealthFinding -List $findings -Id 'MEM-004' -Category 'Memory' -Severity 'High' -Title 'Sustained low available memory' -Description 'Available memory remained below the configured minimum during at least 80 percent of valid samples.' -Evidence ([ordered]@{ MinimumAvailableMB = $available; MatchingSamplePercent = $availableMatching; ConfiguredMinimumAvailableMB = $minimumAvailable }) -RecommendationId 'REC-MEM-001' -Impact 10
        }
    }
    $storage = Get-HealthMetricValue -Object $Metrics -Name 'Storage'
    if ($null -ne $storage) {
        $health = Get-HealthMetricValue -Object $storage -Name 'HealthStatus'
        $free = Get-HealthMetricValue -Object $storage -Name 'SystemFreePercent'
        if ($null -ne $health -and $health -ne 'Unknown' -and $health -ne 'Healthy') {
            Add-HealthFinding -List $findings -Id 'STO-001' -Category 'Storage' -Severity 'Critical' -Title 'Storage health is degraded' -Description 'Windows reported an explicit non-healthy state for a physical disk.' -Evidence ([ordered]@{ HealthStatus = $health }) -RecommendationId 'REC-STO-001' -Impact 35
        }
        if ($null -ne $free -and $free -lt $criticalFree) {
            Add-HealthFinding -List $findings -Id 'STO-002' -Category 'Storage' -Severity 'Critical' -Title 'Critical system volume free space' -Description 'The operating-system volume is below the configured critical free-space threshold.' -Evidence ([ordered]@{ SystemFreePercent = $free; ConfiguredCriticalPercent = $criticalFree }) -RecommendationId 'REC-STO-002' -Impact 20
        }
        elseif ($null -ne $free -and $free -lt $minimumFree) {
            Add-HealthFinding -List $findings -Id 'STO-003' -Category 'Storage' -Severity 'High' -Title 'Low system volume free space' -Description 'The operating-system volume is below the configured minimum free-space threshold.' -Evidence ([ordered]@{ SystemFreePercent = $free; ConfiguredMinimumPercent = $minimumFree }) -RecommendationId 'REC-STO-002' -Impact 10
        }
        if ((Get-HealthMetricValue -Object $storage -Name 'SystemMediaType') -eq 'HDD') {
            Add-HealthFinding -List $findings -Id 'STO-004' -Category 'Storage' -Severity 'Medium' -Title 'System volume uses rotational storage' -Description 'The operating-system disk was identified as an HDD.' -Evidence ([ordered]@{ SystemMediaType = 'HDD' }) -RecommendationId 'REC-STO-003' -Impact 5
        }
        $diskEventCount = Get-HealthMetricValue -Object $storage -Name 'DiskEventCount'
        if ($diskEventCount -ge 3) {
            Add-HealthFinding -List $findings -Id 'STO-005' -Category 'Storage' -Severity 'High' -Title 'Repeated storage events' -Description 'At least three storage-provider events occurred in the configured period.' -Evidence ([ordered]@{ DiskEventCount = $diskEventCount }) -RecommendationId 'REC-STO-004' -Impact 15
        }
        $smart = Get-HealthMetricValue -Object $storage -Name 'Smart'
        if ($null -ne $smart) {
            $pendingSectorCritical = Get-HealthMetricValue -Object $Thresholds -Name 'StoragePendingSectorCriticalCount'
            $spareCritical = Get-HealthMetricValue -Object $Thresholds -Name 'StorageAvailableSpareCriticalPercent'
            $reallocatedWarning = Get-HealthMetricValue -Object $Thresholds -Name 'StorageReallocatedSectorWarningCount'
            $wearWarning = Get-HealthMetricValue -Object $Thresholds -Name 'StorageWearWarningPercent'
            $wearHigh = Get-HealthMetricValue -Object $Thresholds -Name 'StorageWearHighPercent'
            $temperatureWarning = Get-HealthMetricValue -Object $Thresholds -Name 'StorageTemperatureWarningC'
            $temperatureHigh = Get-HealthMetricValue -Object $Thresholds -Name 'StorageTemperatureHighC'
            $hddServiceLifeWarningHours = Get-HealthMetricValue -Object $Thresholds -Name 'StorageHddServiceLifeWarningHours'
            if ($null -eq $pendingSectorCritical) { $pendingSectorCritical = 1 }
            if ($null -eq $spareCritical) { $spareCritical = 10 }
            if ($null -eq $reallocatedWarning) { $reallocatedWarning = 1 }
            if ($null -eq $wearWarning) { $wearWarning = 70 }
            if ($null -eq $wearHigh) { $wearHigh = 90 }
            if ($null -eq $temperatureWarning) { $temperatureWarning = 55 }
            if ($null -eq $temperatureHigh) { $temperatureHigh = 65 }
            if ($null -eq $hddServiceLifeWarningHours) { $hddServiceLifeWarningHours = 26280 }

            if ((Get-HealthMetricValue -Object $smart -Name 'OverallHealth') -eq 'FAILED') {
                Add-HealthFinding -List $findings -Id 'STO-006' -Category 'Storage' -Severity 'Critical' -Title 'Storage device failed SMART self-assessment' -Description "A disk's SMART overall-health self-assessment reported FAILED." -Evidence ([ordered]@{ OverallHealth = 'FAILED' }) -RecommendationId 'REC-STO-001' -Impact 40
            }

            $pendingSectors = Get-HealthMetricValue -Object $smart -Name 'PendingSectorCount'
            if ($null -ne $pendingSectors -and $pendingSectors -ge $pendingSectorCritical) {
                Add-HealthFinding -List $findings -Id 'STO-007' -Category 'Storage' -Severity 'Critical' -Title 'Pending sectors detected' -Description 'A disk reported pending (unstable) sectors at or above the configured critical threshold.' -Evidence ([ordered]@{ PendingSectorCount = $pendingSectors; ConfiguredCriticalCount = $pendingSectorCritical }) -RecommendationId 'REC-STO-001' -Impact 35
            }

            $availableSpare = Get-HealthMetricValue -Object $smart -Name 'AvailableSparePercent'
            if ($null -ne $availableSpare -and $availableSpare -lt $spareCritical) {
                Add-HealthFinding -List $findings -Id 'STO-008' -Category 'Storage' -Severity 'Critical' -Title 'NVMe available spare capacity critically low' -Description "An NVMe disk's available spare percentage is below the configured critical threshold." -Evidence ([ordered]@{ AvailableSparePercent = $availableSpare; ConfiguredCriticalPercent = $spareCritical }) -RecommendationId 'REC-STO-001' -Impact 35
            }

            $reallocatedSectors = Get-HealthMetricValue -Object $smart -Name 'ReallocatedSectorCount'
            if ($null -ne $reallocatedSectors -and $reallocatedSectors -ge $reallocatedWarning) {
                Add-HealthFinding -List $findings -Id 'STO-009' -Category 'Storage' -Severity 'Medium' -Title 'Reallocated sectors detected' -Description 'A disk reported reallocated sectors at or above the configured warning threshold.' -Evidence ([ordered]@{ ReallocatedSectorCount = $reallocatedSectors; ConfiguredWarningCount = $reallocatedWarning }) -RecommendationId 'REC-STO-005' -Impact 10
            }

            $wearPercentUsed = Get-HealthMetricValue -Object $smart -Name 'PercentageUsed'
            if ($null -ne $wearPercentUsed) {
                if ($wearPercentUsed -ge $wearHigh) {
                    Add-HealthFinding -List $findings -Id 'STO-010' -Category 'Storage' -Severity 'High' -Title 'High storage wear level' -Description 'The disk reported a wear percentage used at or above the configured high threshold.' -Evidence ([ordered]@{ PercentageUsed = $wearPercentUsed; ConfiguredWarningPercent = $wearWarning; ConfiguredHighPercent = $wearHigh }) -RecommendationId 'REC-STO-006' -Impact 18
                }
                elseif ($wearPercentUsed -ge $wearWarning) {
                    Add-HealthFinding -List $findings -Id 'STO-010' -Category 'Storage' -Severity 'Medium' -Title 'Elevated storage wear level' -Description 'The disk reported a wear percentage used at or above the configured warning threshold.' -Evidence ([ordered]@{ PercentageUsed = $wearPercentUsed; ConfiguredWarningPercent = $wearWarning; ConfiguredHighPercent = $wearHigh }) -RecommendationId 'REC-STO-006' -Impact 10
                }
            }

            $smartTemperature = Get-HealthMetricValue -Object $smart -Name 'TemperatureCelsius'
            if ($null -ne $smartTemperature) {
                if ($smartTemperature -ge $temperatureHigh) {
                    Add-HealthFinding -List $findings -Id 'STO-011' -Category 'Storage' -Severity 'High' -Title 'High storage temperature' -Description 'The disk reported a SMART temperature at or above the configured high threshold.' -Evidence ([ordered]@{ TemperatureCelsius = $smartTemperature; ConfiguredWarningC = $temperatureWarning; ConfiguredHighC = $temperatureHigh }) -RecommendationId 'REC-STO-007' -Impact 15
                }
                elseif ($smartTemperature -ge $temperatureWarning) {
                    Add-HealthFinding -List $findings -Id 'STO-011' -Category 'Storage' -Severity 'Medium' -Title 'Elevated storage temperature' -Description 'The disk reported a SMART temperature at or above the configured warning threshold.' -Evidence ([ordered]@{ TemperatureCelsius = $smartTemperature; ConfiguredWarningC = $temperatureWarning; ConfiguredHighC = $temperatureHigh }) -RecommendationId 'REC-STO-007' -Impact 8
                }
            }

            $powerOnHours = Get-HealthMetricValue -Object $smart -Name 'PowerOnHours'
            $systemMediaType = Get-HealthMetricValue -Object $storage -Name 'SystemMediaType'
            if ($null -ne $powerOnHours -and $powerOnHours -ge $hddServiceLifeWarningHours -and $systemMediaType -eq 'HDD') {
                Add-HealthFinding -List $findings -Id 'STO-012' -Category 'Storage' -Severity 'Medium' -Title 'HDD approaching typical service-life hours' -Description 'The system HDD has accumulated power-on hours at or above the configured service-life warning threshold.' -Evidence ([ordered]@{ PowerOnHours = $powerOnHours; ConfiguredWarningHours = $hddServiceLifeWarningHours }) -RecommendationId 'REC-STO-006' -Impact 10
            }
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
    return ,@($findings | ForEach-Object { $_ })
}

function Get-HealthRecommendation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings)
    $catalog = @{
        'REC-MEM-001' = @('Review memory pressure', 'Identify sustained memory consumers and validate whether installed capacity matches the workload.')
        'REC-STO-001' = @('Validate degraded storage', 'Back up important data and run the manufacturer diagnostic before considering disk replacement.')
        'REC-STO-002' = @('Recover system volume space', 'Remove or archive nonessential data after validating retention requirements.')
        'REC-STO-003' = @('Evaluate solid-state storage', 'Consider SSD storage when workload latency is constrained by the system HDD.')
        'REC-STO-004' = @('Investigate storage events', 'Review the correlated storage events and vendor diagnostics before changing hardware.')
        'REC-STO-005' = @('Monitor reallocated sectors', 'Track the reallocated-sector trend over time and back up important data as a precaution.')
        'REC-STO-006' = @('Plan storage replacement', 'Schedule replacement of the disk based on its wear level or accumulated service-life hours.')
        'REC-STO-007' = @('Improve thermal conditions', 'Review airflow, dust buildup, and enclosure placement to reduce sustained disk temperature.')
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
