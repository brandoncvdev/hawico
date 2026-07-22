function Invoke-HealthCollectorSection {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Operation,
        [Parameter(Mandatory)][AllowNull()][object]$DefaultData
    )
    $startedAt = [datetimeoffset]::Now
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $data = & $Operation
        $hasStatus = $null -ne $data -and (($data -is [System.Collections.IDictionary] -and $data.Contains('Status')) -or $data.PSObject.Properties.Name -contains 'Status')
        $status = if ($hasStatus) { [string]$data.Status } else { 'Collected' }
        if ($status -notin @('Collected', 'Partial', 'Skipped', 'Failed')) { $status = 'Collected' }
        $hasErrorCode = $null -ne $data -and (($data -is [System.Collections.IDictionary] -and $data.Contains('ErrorCode')) -or $data.PSObject.Properties.Name -contains 'ErrorCode')
        $hasErrorMessage = $null -ne $data -and (($data -is [System.Collections.IDictionary] -and $data.Contains('ErrorMessage')) -or $data.PSObject.Properties.Name -contains 'ErrorMessage')
        $errorCode = if ($hasErrorCode) { $data.ErrorCode } else { $null }
        $errorMessage = if ($hasErrorMessage) { $data.ErrorMessage } else { $null }
    }
    catch {
        $data = $DefaultData
        $status = 'Failed'
        $errorCode = $Name.ToUpperInvariant() + '-COLLECTION-FAILED'
        $errorMessage = $Name + ' collection failed; review the local log for diagnostic details.'
    }
    finally {
        $timer.Stop()
    }
    return [ordered]@{
        Data = $data
        Section = [pscustomobject][ordered]@{
            Name = $Name
            Status = $status
            StartedAt = $startedAt
            DurationMilliseconds = $timer.ElapsedMilliseconds
            SampleCount = $null
            ErrorCode = $errorCode
            ErrorMessage = $errorMessage
        }
    }
}
