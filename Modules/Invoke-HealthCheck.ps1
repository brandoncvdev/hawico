function Get-HealthInputValue {
    param([AllowNull()][object]$Object, [string]$Name, [AllowNull()][object]$DefaultValue = $null)
    if ($null -eq $Object) { return $DefaultValue }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $DefaultValue
}

function ConvertTo-HealthSectionRecord {
    param([string]$Name, [string]$Status, [AllowNull()][object]$Source, [AllowNull()][object]$SampleCount)
    $startedAt = Get-HealthInputValue -Object $Source -Name 'StartedAt'
    if ($startedAt -is [datetime] -or $startedAt -is [datetimeoffset]) { $startedAt = $startedAt.ToString('o') }
    return [pscustomobject][ordered]@{
        Name = $Name
        Status = $Status
        StartedAt = $startedAt
        DurationMilliseconds = Get-HealthInputValue -Object $Source -Name 'DurationMilliseconds'
        SampleCount = $SampleCount
        ErrorCode = Get-HealthInputValue -Object $Source -Name 'ErrorCode'
        ErrorMessage = Get-HealthInputValue -Object $Source -Name 'ErrorMessage'
    }
}

function Get-HighestHealthSeverity {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings)
    if ($Findings.Count -eq 0) { return 'Info' }
    return ($Findings | Sort-Object @{ Expression = { -(Get-HealthSeverityRank $_.Severity) } } | Select-Object -First 1).Severity
}

function Invoke-HealthCheck {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$InputData,
        [datetimeoffset]$CollectedAt,
        [long]$DurationMilliseconds = 0
    )

    $performance = $InputData.Performance
    $storage = $InputData.Storage
    $events = @($InputData.Events)
    $eventStatus = [string](Get-HealthInputValue -Object $InputData -Name 'EventStatus' -DefaultValue 'Collected')
    $capabilities = $InputData.Capabilities
    $healthConfig = Get-HealthInputValue -Object $InputData -Name 'HealthConfig'

    $diskProviders = @('Disk', 'Ntfs', 'StorPort', 'stornvme')
    $diskEventCount = [int](($events | Where-Object { $_.Provider -in $diskProviders } | Measure-Object -Property OccurrenceCount -Sum).Sum)
    $wheaCount = [int](($events | Where-Object Provider -eq 'WHEA-Logger' | Measure-Object -Property OccurrenceCount -Sum).Sum)
    $kernelPowerCount = [int](($events | Where-Object Provider -eq 'Kernel-Power' | Measure-Object -Property OccurrenceCount -Sum).Sum)
    $applicationFailureCount = [int](($events | Where-Object { $_.Provider -in @('Application Error', 'Application Hang') } | Measure-Object -Property OccurrenceCount -Sum).Sum)

    $physicalDisks = @($storage.PhysicalDisks)
    $explicitDegraded = @($physicalDisks | Where-Object { $_.HealthStatus -notin @($null, '', 'Unknown', 'Healthy') } | Select-Object -First 1)
    $storageHealth = if ($explicitDegraded.Count -gt 0) { $explicitDegraded[0].HealthStatus }
        elseif (@($physicalDisks | Where-Object HealthStatus -eq 'Healthy').Count -gt 0) { 'Healthy' }
        else { 'Unknown' }
    $systemVolumes = @($storage.Volumes | Where-Object IsSystemVolume)
    $systemFreePercent = if ($systemVolumes.Count -gt 0) { ($systemVolumes | Measure-Object -Property FreePercent -Minimum).Minimum } else { $null }
    $systemDisks = @($physicalDisks | Where-Object { $_.IsSystemDisk -eq $true })
    if ($systemDisks.Count -eq 0 -and $physicalDisks.Count -eq 1) { $systemDisks = @($physicalDisks[0]) }
    $systemMediaType = if ($systemDisks.Count -gt 0) { $systemDisks[0].MediaType } else { 'Unknown' }

    $metrics = [pscustomobject][ordered]@{
        CPU = [pscustomobject][ordered]@{
            AverageUsagePercent = Get-HealthInputValue -Object $performance.CPU -Name 'AverageUsagePercent'
            PeakUsagePercent = Get-HealthInputValue -Object $performance.CPU -Name 'PeakUsagePercent'
            SamplesAtOrAbove90Percent = Get-HealthInputValue -Object $performance.CPU -Name 'SamplesAtOrAbove90Percent'
        }
        Memory = [pscustomobject][ordered]@{
            UsagePercent = Get-HealthInputValue -Object $performance.Memory -Name 'AverageUsagePercent'
            PeakUsagePercent = Get-HealthInputValue -Object $performance.Memory -Name 'PeakUsagePercent'
            AvailableMemoryMB = Get-HealthInputValue -Object $performance.Memory -Name 'MinimumAvailableMB'
            SamplesAtOrAbove70Percent = Get-HealthInputValue -Object $performance.Memory -Name 'SamplesAtOrAbove70Percent'
            SamplesAtOrAbove85Percent = Get-HealthInputValue -Object $performance.Memory -Name 'SamplesAtOrAbove85Percent'
            SamplesAtOrAbove95Percent = Get-HealthInputValue -Object $performance.Memory -Name 'SamplesAtOrAbove95Percent'
            SamplesBelow1024MB = Get-HealthInputValue -Object $performance.Memory -Name 'SamplesBelow1024MB'
            WarningMatchingSamplePercent = Get-HealthInputValue -Object $performance.Memory -Name 'WarningMatchingSamplePercent'
            HighMatchingSamplePercent = Get-HealthInputValue -Object $performance.Memory -Name 'HighMatchingSamplePercent'
            CriticalMatchingSamplePercent = Get-HealthInputValue -Object $performance.Memory -Name 'CriticalMatchingSamplePercent'
            LowAvailableMatchingSamplePercent = Get-HealthInputValue -Object $performance.Memory -Name 'LowAvailableMatchingSamplePercent'
        }
        Storage = [pscustomobject][ordered]@{
            HealthStatus = $storageHealth
            SystemFreePercent = $systemFreePercent
            SystemMediaType = $systemMediaType
            DiskEventCount = $diskEventCount
        }
        Events = [pscustomobject][ordered]@{
            WHEACount = $wheaCount
            KernelPowerCount = $kernelPowerCount
            ApplicationFailureCount = $applicationFailureCount
        }
    }

    $findings = @(Get-HealthFinding -Metrics $metrics -Thresholds $healthConfig)
    $recommendations = @(Get-HealthRecommendation -Findings $findings)
    $performanceAvailable = $performance.Status -in @('Collected', 'Partial') -and [int]$performance.ValidSampleCount -gt 0
    $storageAvailable = $storage.Status -in @('Collected', 'Partial')
    $eventsAvailable = $eventStatus -in @('Collected', 'Partial')
    $categories = @()
    foreach ($definition in @(@('Storage', 35), @('Memory', 25), @('CPU', 20), @('Events', 20))) {
        $name = $definition[0]
        $available = if ($name -in @('CPU', 'Memory')) { $performanceAvailable } elseif ($name -eq 'Storage') { $storageAvailable } else { $eventsAvailable }
        $items = @($findings | Where-Object Category -eq $name)
        $sum = ($items | Measure-Object -Property ScoreImpact -Sum).Sum
        if ($null -eq $sum) { $sum = 0 }
        $categories += [pscustomobject][ordered]@{
            Name = $name
            Weight = [int]$definition[1]
            Available = $available
            Deduction = -[int]$sum
            HighestSeverity = Get-HighestHealthSeverity -Findings $items
        }
    }
    $score = Get-HealthScore -Categories $categories

    $providedSections = @(Get-HealthInputValue -Object $InputData -Name 'Sections' -DefaultValue @())
    $performanceSection = @($providedSections | Where-Object Name -eq 'Performance' | Select-Object -First 1)
    $storageSection = @($providedSections | Where-Object Name -eq 'Storage' | Select-Object -First 1)
    $eventSection = @($providedSections | Where-Object Name -eq 'Events' | Select-Object -First 1)
    $sections = @(
        ConvertTo-HealthSectionRecord -Name 'Performance' -Status $performance.Status -Source $performanceSection -SampleCount $performance.ValidSampleCount
        ConvertTo-HealthSectionRecord -Name 'Storage' -Status $storage.Status -Source $storageSection -SampleCount $null
        ConvertTo-HealthSectionRecord -Name 'Events' -Status $eventStatus -Source $eventSection -SampleCount $events.Count
    )
    $sections += @($providedSections | Where-Object { $_.Name -notin @('Performance', 'Storage', 'Events') })

    $errors = @()
    $isAdministrator = [bool](Get-HealthInputValue -Object $capabilities -Name 'IsAdministrator' -DefaultValue $false)
    if (-not $isAdministrator) {
        $errors += [pscustomobject][ordered]@{ Code = 'CAP-ADMIN-DENIED'; Section = 'Capabilities'; Message = 'Administrative privileges are not available; privileged evidence may be incomplete.' }
    }
    foreach ($section in $sections | Where-Object Status -in @('Partial', 'Skipped', 'Failed')) {
        $errors += [pscustomobject][ordered]@{
            Code = if ([string]::IsNullOrWhiteSpace($section.ErrorCode)) { 'SECTION-' + $section.Status.ToUpperInvariant() } else { $section.ErrorCode }
            Section = $section.Name
            Message = if ([string]::IsNullOrWhiteSpace($section.ErrorMessage)) { $section.Name + ' collection status is ' + $section.Status + '.' } else { $section.ErrorMessage }
        }
    }

    $allUnavailable = @($categories | Where-Object Available).Count -eq 0
    $hasIncompleteSection = @($sections | Where-Object Status -ne 'Collected').Count -gt 0
    $status = if ($allUnavailable) { 'Failed' } elseif ($hasIncompleteSection -or -not $isAdministrator) { 'Partial' } else { 'Completed' }
    $sample = Get-HealthInputValue -Object $InputData -Name 'Sample' -DefaultValue ([ordered]@{
        RequestedDurationSeconds = $null
        ActualDurationSeconds = $null
        IntervalSeconds = $null
        ValidSampleCount = [int]$performance.ValidSampleCount
    })
    $health = [ordered]@{
        Status = $status
        IsAdministrator = $isAdministrator
        Capabilities = $capabilities.Items
        Sections = $sections
        Sample = $sample
        Metrics = [ordered]@{ CPU = $performance.CPU; Memory = $performance.Memory; Storage = $storage; Events = $events }
        Score = $score
        PrimaryBottleneck = $score.PrimaryBottleneck
        Findings = $findings
        Recommendations = $recommendations
        Errors = $errors
    }
    return ConvertTo-HealthCheckReport -BaseInventory $InputData.BaseInventory -HealthCheck $health -CollectedAt $CollectedAt -DurationMilliseconds $DurationMilliseconds
}
