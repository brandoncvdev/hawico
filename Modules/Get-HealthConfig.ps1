function Get-HealthConfigProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$DefaultValue
    )

    if ($null -eq $Object) { return $DefaultValue }
    if ($Object.PSObject.Properties.Name -notcontains $Name) { return $DefaultValue }
    if ($null -eq $Object.$Name) { return $DefaultValue }
    return $Object.$Name
}

function Get-HealthCheckConfig {
    param([Parameter(Mandatory)][object]$Config)

    $health = Get-HealthConfigProperty -Object $Config -Name "HealthCheck" -DefaultValue $null
    $result = [ordered]@{
        SampleDurationSeconds = [int](Get-HealthConfigProperty -Object $health -Name "SampleDurationSeconds" -DefaultValue 60)
        SampleIntervalSeconds = [int](Get-HealthConfigProperty -Object $health -Name "SampleIntervalSeconds" -DefaultValue 1)
        EventLookbackDays = [int](Get-HealthConfigProperty -Object $health -Name "EventLookbackDays" -DefaultValue 7)
        MinimumFreeDiskPercent = [double](Get-HealthConfigProperty -Object $health -Name "MinimumFreeDiskPercent" -DefaultValue 20)
        CriticalFreeDiskPercent = [double](Get-HealthConfigProperty -Object $health -Name "CriticalFreeDiskPercent" -DefaultValue 10)
        MemoryWarningPercent = [double](Get-HealthConfigProperty -Object $health -Name "MemoryWarningPercent" -DefaultValue 70)
        MemoryHighPercent = [double](Get-HealthConfigProperty -Object $health -Name "MemoryHighPercent" -DefaultValue 85)
        MemoryCriticalPercent = [double](Get-HealthConfigProperty -Object $health -Name "MemoryCriticalPercent" -DefaultValue 95)
        MinimumAvailableMemoryMB = [int](Get-HealthConfigProperty -Object $health -Name "MinimumAvailableMemoryMB" -DefaultValue 1024)
        IncludePersonallyIdentifiableInformation = [bool](Get-HealthConfigProperty -Object $health -Name "IncludePersonallyIdentifiableInformation" -DefaultValue $false)
        GenerateJSON = [bool](Get-HealthConfigProperty -Object $Config -Name "GenerateJSON" -DefaultValue $true)
        GenerateHTML = [bool](Get-HealthConfigProperty -Object $Config -Name "GenerateHTML" -DefaultValue $true)
    }

    if ($result.SampleDurationSeconds -lt 10 -or $result.SampleDurationSeconds -gt 300) {
        throw "HealthCheck.SampleDurationSeconds debe estar entre 10 y 300."
    }
    if ($result.SampleIntervalSeconds -lt 1 -or $result.SampleIntervalSeconds -gt 10 -or $result.SampleIntervalSeconds -ge $result.SampleDurationSeconds) {
        throw "HealthCheck.SampleIntervalSeconds debe estar entre 1 y 10 y ser menor que SampleDurationSeconds."
    }
    if ($result.EventLookbackDays -lt 1 -or $result.EventLookbackDays -gt 30) {
        throw "HealthCheck.EventLookbackDays debe estar entre 1 y 30."
    }
    if (-not ($result.MemoryWarningPercent -lt $result.MemoryHighPercent -and $result.MemoryHighPercent -lt $result.MemoryCriticalPercent)) {
        throw "HealthCheck.MemoryWarningPercent, MemoryHighPercent y MemoryCriticalPercent deben estar ordenados."
    }
    if ($result.CriticalFreeDiskPercent -ge $result.MinimumFreeDiskPercent) {
        throw "HealthCheck.CriticalFreeDiskPercent debe ser menor que MinimumFreeDiskPercent."
    }

    return $result
}
