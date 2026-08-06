BeforeAll {
 . "$PSScriptRoot/../Modules/Common.ps1"
 . "$PSScriptRoot/../Modules/Get-StorageInfo.ps1"
 if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
  function Get-CimInstance { param($Namespace, $ClassName, $Filter) }
 }
}
Describe 'ConvertFrom-SmartctlJson' {
 It 'parses a successful ATA disk report' {
  $json = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true},"temperature":{"current":34},"power_on_time":{"hours":12000},"power_cycle_count":450,"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":0}},{"id":197,"name":"Current_Pending_Sector","raw":{"value":0}},{"id":198,"name":"Offline_Uncorrectable","raw":{"value":0}}]}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.OverallHealth | Should -Be 'PASSED'
  $r.TemperatureCelsius | Should -Be 34
  $r.PowerOnHours | Should -Be 12000
  $r.PowerCycleCount | Should -Be 450
  $r.ReallocatedSectorCount | Should -Be 0
  $r.PendingSectorCount | Should -Be 0
  $r.UncorrectableSectorCount | Should -Be 0
  $r.AvailableSparePercent | Should -BeNullOrEmpty
  $r.PercentageUsed | Should -BeNullOrEmpty
  $r.MediaErrorCount | Should -BeNullOrEmpty
  $r.CriticalWarningFlags | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
  $r.ErrorMessage | Should -BeNullOrEmpty
 }
 It 'parses a successful NVMe disk report' {
  $json = '{"device":{"protocol":"NVMe"},"smart_status":{"passed":true},"temperature":{"current":40},"power_on_time":{"hours":500},"power_cycle_count":50,"nvme_smart_health_information_log":{"critical_warning":0,"available_spare":100,"percentage_used":5,"media_errors":0}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'NVMe'
  $r.OverallHealth | Should -Be 'PASSED'
  $r.TemperatureCelsius | Should -Be 40
  $r.PowerOnHours | Should -Be 500
  $r.PowerCycleCount | Should -Be 50
  $r.AvailableSparePercent | Should -Be 100
  $r.PercentageUsed | Should -Be 5
  $r.MediaErrorCount | Should -Be 0
  $r.CriticalWarningFlags | Should -Be 0
  $r.ReallocatedSectorCount | Should -BeNullOrEmpty
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
  $r.ErrorMessage | Should -BeNullOrEmpty
 }
 It 'reports a FAILED self-assessment without inventing a passing status' {
  $json = '{"device":{"protocol":"ATA"},"smart_status":{"passed":false}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.OverallHealth | Should -Be 'FAILED'
 }
 It 'never throws and degrades gracefully on truncated JSON text' {
  $truncated = '{"device":{"protocol":"ATA","name":"/dev/sda"'
  { ConvertFrom-SmartctlJson -SmartctlOutput $truncated } | Should -Not -Throw
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $truncated
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'SMARTCTL-PARSE-ERROR'
  $r.ErrorMessage | Should -Not -BeNullOrEmpty
 }
 It 'never throws and degrades gracefully on null output' {
  { ConvertFrom-SmartctlJson -SmartctlOutput $null } | Should -Not -Throw
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $null
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'SMARTCTL-PARSE-ERROR'
 }
 It 'degrades gracefully when the protocol cannot be identified' {
  $json = '{"device":{"protocol":"SCSI"},"smart_status":{"passed":true}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'SMARTCTL-UNKNOWN-PROTOCOL'
  $r.ErrorMessage | Should -Not -BeNullOrEmpty
 }
 It 'leaves individual fields null when the ATA report is missing sub-sections, without failing the whole disk' {
  $json = '{"device":{"protocol":"ATA"}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.OverallHealth | Should -BeNullOrEmpty
  $r.TemperatureCelsius | Should -BeNullOrEmpty
  $r.PowerOnHours | Should -BeNullOrEmpty
  $r.PowerCycleCount | Should -BeNullOrEmpty
  $r.ReallocatedSectorCount | Should -BeNullOrEmpty
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
 }
 It 'leaves individual fields null when the NVMe report is missing sub-sections, without failing the whole disk' {
  $json = '{"device":{"protocol":"NVMe"}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'NVMe'
  $r.AvailableSparePercent | Should -BeNullOrEmpty
  $r.PercentageUsed | Should -BeNullOrEmpty
  $r.MediaErrorCount | Should -BeNullOrEmpty
  $r.CriticalWarningFlags | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
 }
 It 'reads a single ATA attribute correctly despite the single-element-array collapse risk' {
  $json = '{"device":{"protocol":"ATA"},"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":3}}]}}' | ConvertFrom-Json
  $r = ConvertFrom-SmartctlJson -SmartctlOutput $json
  $r.ReallocatedSectorCount | Should -Be 3
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
 }
}

Describe 'ConvertFrom-AtaSmartAttributeTable' {
 BeforeAll {
  # Real, hand-verified fixture bytes (Dell OptiPlex 3050, Seagate
  # ST500DM005) from openspec/changes/storage-diagnostics/tasks.md, Phase
  # 2c — copied literally, not paraphrased or regenerated. 2-byte header
  # then 22 x 12-byte attribute records, zero-padded to the full 512-byte
  # block (the remaining unused table slots plus the trailing status
  # region are both zero either way).
  $script:AtaFixtureExplicitBytes = @(
   16,0,1,47,0,100,100,0,5,0,0,0,0,0,2,38,0,252,252,0,0,0,0,0,0,0,3,35,0,83,74,198,20,0,0,0,0,0,4,50,0,99,99,91,7,0,0,0,0,0,5,51,0,252,252,0,0,0,0,0,0,0,7,46,0,252,252,0,0,0,0,0,0,0,8,36,0,252,252,0,0,0,0,0,0,0,9,50,0,100,100,121,86,0,0,0,0,0,10,50,0,252,252,0,0,0,0,0,0,0,11,50,0,252,252,0,0,0,0,0,0,0,12,50,0,99,99,250,6,0,0,0,0,0,191,34,0,100,100,29,0,0,0,0,0,0,192,34,0,252,252,0,0,0,0,0,0,0,194,2,0,59,44,41,0,11,0,56,0,0,195,58,0,100,100,0,0,0,0,0,0,0,196,50,0,252,252,0,0,0,0,0,0,0,197,50,0,252,100,0,0,0,0,0,0,0,198,48,0,252,252,0,0,0,0,0,0,0,199,54,0,92,92,160,16,0,0,0,0,0,200,42,0,100,100,24,37,0,0,0,0,0,223,50,0,252,252,0,0,0,0,0,0,0,225,50,0,84,84,116,138,2,0,0,0,0,0
  )
  $padding = @(0) * (512 - $script:AtaFixtureExplicitBytes.Count)
  $script:AtaFixtureBytes = [byte[]]($script:AtaFixtureExplicitBytes + $padding)
 }

 It 'decodes the real hand-verified 512-byte fixture with the exact expected attribute values' {
  $r = ConvertFrom-AtaSmartAttributeTable -RawBytes $script:AtaFixtureBytes
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.PowerOnHours | Should -Be 22137
  $r.TemperatureCelsius | Should -Be 41
  $r.ReallocatedSectorCount | Should -Be 0
  $r.PendingSectorCount | Should -Be 0
  $r.UncorrectableSectorCount | Should -Be 0
  $r.PowerCycleCount | Should -Be 1786
  $r.ErrorCode | Should -BeNullOrEmpty
  $r.ErrorMessage | Should -BeNullOrEmpty
  $r.AvailableSparePercent | Should -BeNullOrEmpty
  $r.PercentageUsed | Should -BeNullOrEmpty
  $r.MediaErrorCount | Should -BeNullOrEmpty
  $r.CriticalWarningFlags | Should -BeNullOrEmpty
 }
 It 'never throws and degrades gracefully when the byte array is shorter than 512 bytes' {
  $short = [byte[]](1..10)
  { ConvertFrom-AtaSmartAttributeTable -RawBytes $short } | Should -Not -Throw
  $r = ConvertFrom-AtaSmartAttributeTable -RawBytes $short
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'WMI-SMART-MALFORMED'
  $r.ErrorMessage | Should -Not -BeNullOrEmpty
 }
 It 'never throws and degrades gracefully on a null byte array' {
  { ConvertFrom-AtaSmartAttributeTable -RawBytes $null } | Should -Not -Throw
  $r = ConvertFrom-AtaSmartAttributeTable -RawBytes $null
  $r.Supported | Should -BeFalse
  $r.ErrorCode | Should -Be 'WMI-SMART-MALFORMED'
 }
 It 'reports Supported with every attribute field null when the table has no populated attribute slots' {
  $allZero = [byte[]](, 0 * 512)
  $r = ConvertFrom-AtaSmartAttributeTable -RawBytes $allZero
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.PowerOnHours | Should -BeNullOrEmpty
  $r.TemperatureCelsius | Should -BeNullOrEmpty
  $r.ReallocatedSectorCount | Should -BeNullOrEmpty
  $r.PendingSectorCount | Should -BeNullOrEmpty
  $r.UncorrectableSectorCount | Should -BeNullOrEmpty
  $r.ErrorCode | Should -BeNullOrEmpty
 }
 It 'skips unrecognized attribute IDs gracefully without throwing or affecting known attributes' {
  $bytes = [byte[]](, 0 * 512)
  # Slot 0 (offset 2): an attribute Id (250) this parser does not map to
  # any output field.
  $bytes[2] = 250
  $bytes[7] = 99
  # Slot 1 (offset 14): a recognized Id (5, ReallocatedSectorCount) with a
  # non-zero raw value, to prove the unrecognized slot didn't derail
  # parsing of the rest of the table.
  $bytes[14] = 5
  $bytes[19] = 7
  { ConvertFrom-AtaSmartAttributeTable -RawBytes $bytes } | Should -Not -Throw
  $r = ConvertFrom-AtaSmartAttributeTable -RawBytes $bytes
  $r.Supported | Should -BeTrue
  $r.ReallocatedSectorCount | Should -Be 7
 }
}

Describe 'Get-DiskSmartDataFromWmi' {
 BeforeAll {
  $explicit = @(
   16,0,1,47,0,100,100,0,5,0,0,0,0,0,2,38,0,252,252,0,0,0,0,0,0,0,3,35,0,83,74,198,20,0,0,0,0,0,4,50,0,99,99,91,7,0,0,0,0,0,5,51,0,252,252,0,0,0,0,0,0,0,7,46,0,252,252,0,0,0,0,0,0,0,8,36,0,252,252,0,0,0,0,0,0,0,9,50,0,100,100,121,86,0,0,0,0,0,10,50,0,252,252,0,0,0,0,0,0,0,11,50,0,252,252,0,0,0,0,0,0,0,12,50,0,99,99,250,6,0,0,0,0,0,191,34,0,100,100,29,0,0,0,0,0,0,192,34,0,252,252,0,0,0,0,0,0,0,194,2,0,59,44,41,0,11,0,56,0,0,195,58,0,100,100,0,0,0,0,0,0,0,196,50,0,252,252,0,0,0,0,0,0,0,197,50,0,252,100,0,0,0,0,0,0,0,198,48,0,252,252,0,0,0,0,0,0,0,199,54,0,92,92,160,16,0,0,0,0,0,200,42,0,100,100,24,37,0,0,0,0,0,223,50,0,252,252,0,0,0,0,0,0,0,225,50,0,84,84,116,138,2,0,0,0,0,0
  )
  $script:WmiFixtureBytes = [byte[]]($explicit + (@(0) * (512 - $explicit.Count)))
  $script:WmiPnpDeviceId = 'SCSI\DISK&VEN_ST500DM0&PROD_05\4&3714EEF5&0&000000'
  $script:WmiInstanceName = 'SCSI\Disk&Ven_ST500DM0&Prod_05\4&3714eef5&0&000000_0'
 }

 It 'correlates InstanceName to PnpDeviceId case-insensitively despite the trailing _N suffix, and decodes the real fixture' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'MSStorageDriver_FailurePredictData') {
    @([pscustomobject]@{ InstanceName = $script:WmiInstanceName; Active = $true; VendorSpecific = $script:WmiFixtureBytes })
   }
   elseif ($ClassName -eq 'MSStorageDriver_FailurePredictStatus') {
    @([pscustomobject]@{ InstanceName = $script:WmiInstanceName; PredictFailure = $false })
   }
   else { @() }
  }

  $r = Get-DiskSmartDataFromWmi -PnpDeviceId $script:WmiPnpDeviceId
  $r.Supported | Should -BeTrue
  $r.Source | Should -Be 'ATA'
  $r.OverallHealth | Should -Be 'PASSED'
  $r.PowerOnHours | Should -Be 22137
  $r.TemperatureCelsius | Should -Be 41
  $r.ReallocatedSectorCount | Should -Be 0
  $r.PendingSectorCount | Should -Be 0
  $r.UncorrectableSectorCount | Should -Be 0
 }
 It 'sets OverallHealth to FAILED when FailurePredictStatus reports PredictFailure true' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'MSStorageDriver_FailurePredictData') {
    @([pscustomobject]@{ InstanceName = $script:WmiInstanceName; Active = $true; VendorSpecific = $script:WmiFixtureBytes })
   }
   elseif ($ClassName -eq 'MSStorageDriver_FailurePredictStatus') {
    @([pscustomobject]@{ InstanceName = $script:WmiInstanceName; PredictFailure = $true })
   }
   else { @() }
  }
  $r = Get-DiskSmartDataFromWmi -PnpDeviceId $script:WmiPnpDeviceId
  $r.OverallHealth | Should -Be 'FAILED'
 }
 It 'degrades gracefully to Supported=$false when no InstanceName matches the PnpDeviceId' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'MSStorageDriver_FailurePredictData') {
    @([pscustomobject]@{ InstanceName = 'SCSI\Disk&Ven_OTHER&Prod_00\9&aaaaaaaa&0&000000_0'; Active = $true; VendorSpecific = $script:WmiFixtureBytes })
   }
   else { @() }
  }
  $r = Get-DiskSmartDataFromWmi -PnpDeviceId $script:WmiPnpDeviceId
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
  $r.ErrorCode | Should -Be 'WMI-SMART-NOT-FOUND'
 }
 It 'degrades gracefully to Supported=$false when the matched instance is not Active' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'MSStorageDriver_FailurePredictData') {
    @([pscustomobject]@{ InstanceName = $script:WmiInstanceName; Active = $false; VendorSpecific = $script:WmiFixtureBytes })
   }
   else { @() }
  }
  $r = Get-DiskSmartDataFromWmi -PnpDeviceId $script:WmiPnpDeviceId
  $r.Supported | Should -BeFalse
  $r.ErrorCode | Should -Be 'WMI-SMART-INACTIVE'
 }
 It 'never throws and degrades gracefully when the WMI namespace/class is entirely unavailable' {
  Mock Get-CimInstance { throw 'root\wmi provider not present on this Windows version' }
  { Get-DiskSmartDataFromWmi -PnpDeviceId $script:WmiPnpDeviceId } | Should -Not -Throw
  $r = Get-DiskSmartDataFromWmi -PnpDeviceId $script:WmiPnpDeviceId
  $r.Supported | Should -BeFalse
  $r.Source | Should -Be 'Unavailable'
 }
 It 'returns a not-found result without querying WMI when PnpDeviceId is null or empty' {
  Mock Get-CimInstance { throw 'should never be called' }
  { Get-DiskSmartDataFromWmi -PnpDeviceId $null } | Should -Not -Throw
  $r = Get-DiskSmartDataFromWmi -PnpDeviceId $null
  $r.Supported | Should -BeFalse
  $r.ErrorCode | Should -Be 'WMI-SMART-NOT-FOUND'
  Should -Invoke Get-CimInstance -Times 0
 }
}

Describe 'Get-DiskSmartData' {
 It 'uses the nvme device-type flag for an NVMe bus' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"NVMe"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'NVMe' | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'nvme' }
 }
 It 'tries the sat device-type flag first for a SATA bus, and succeeds without retrying when it works' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'sat' }
 }
 It 'tries the sat device-type flag first when the bus is unknown ($null), and succeeds without retrying when it works' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType $null | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'sat' }
 }
 It 'tries the sat device-type flag first for a USB bus, and retries once with auto-detect when it fails' {
  $script:usbCallCount = 0
  Mock Invoke-SmartctlCommand {
   $script:usbCallCount++
   if ($script:usbCallCount -eq 1) {
    return [ordered]@{ Success = $false; StdOut = $null; ExitCode = 1; ErrorCode = 'SMARTCTL-PROCESS-ERROR'; ErrorMessage = 'unsupported device' }
   }
   return [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'USB'
  Should -Invoke Invoke-SmartctlCommand -Times 2
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'sat' }
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($DeviceTypeFlag) }
  $result.Supported | Should -BeTrue
 }
 It 'tries the sat device-type flag first for a RAID bus (OEM RAID/passthrough, e.g. Intel RST), and retries once with auto-detect when smartctl cannot identify the protocol through it' {
  $script:raidCallCount = 0
  Mock Invoke-SmartctlCommand {
   $script:raidCallCount++
   if ($script:raidCallCount -eq 1) {
    return [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"RAID"}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
   }
   return [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'RAID'
  Should -Invoke Invoke-SmartctlCommand -Times 2
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'sat' }
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($DeviceTypeFlag) }
  $result.Supported | Should -BeTrue
  $result.Source | Should -Be 'ATA'
 }
 It 'tries the sat device-type flag first for an unrecognized ($null) bus, and retries once with auto-detect when smartctl cannot identify the protocol through it' {
  $script:unknownCallCount = 0
  Mock Invoke-SmartctlCommand {
   $script:unknownCallCount++
   if ($script:unknownCallCount -eq 1) {
    return [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"SCSI"}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
   }
   return [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType $null
  Should -Invoke Invoke-SmartctlCommand -Times 2
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'sat' }
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($DeviceTypeFlag) }
  $result.Supported | Should -BeTrue
 }
 It 'retries a non-USB bus with auto-detect after a hard invocation failure too, same as USB' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $false; StdOut = $null; ExitCode = 1; ErrorCode = 'SMARTCTL-PROCESS-ERROR'; ErrorMessage = 'error' }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 2
 }
 It 'propagates a SMARTCTL-TIMEOUT error code from the invocation without throwing, using the 15s default timeout, and does not retry (would double the wait to 30s)' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $false; StdOut = $null; ExitCode = $null; ErrorCode = 'SMARTCTL-TIMEOUT'; ErrorMessage = 'smartctl no respondió en 15000 ms para el disco 0.' }
  }
  { Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' } | Should -Not -Throw
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA'
  $result.Supported | Should -BeFalse
  $result.Source | Should -Be 'Unavailable'
  $result.ErrorCode | Should -Be 'SMARTCTL-TIMEOUT'
  Should -Invoke Invoke-SmartctlCommand -Times 1
 }
 It 'degrades gracefully when the invocation succeeds but the stdout is not valid JSON' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = 'not json'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA'
  $result.Supported | Should -BeFalse
  $result.Source | Should -Be 'Unavailable'
  $result.ErrorCode | Should -Be 'SMARTCTL-PARSE-ERROR'
 }
 It 'tries WMI FailurePredictData first for a non-NVMe disk and never invokes smartctl when WMI succeeds' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'MSStorageDriver_FailurePredictData') {
    @([pscustomobject]@{ InstanceName = 'SCSI\Disk&Ven_ST500DM0&Prod_05\4&3714eef5&0&000000_0'; Active = $true; VendorSpecific = [byte[]](, 0 * 512) })
   } else { @() }
  }
  Mock Invoke-SmartctlCommand { throw 'should never be called' }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' -PnpDeviceId 'SCSI\DISK&VEN_ST500DM0&PROD_05\4&3714EEF5&0&000000' -SmartctlAvailable $true
  $result.Supported | Should -BeTrue
  $result.Source | Should -Be 'ATA'
  Should -Invoke Invoke-SmartctlCommand -Times 0
 }
 It 'falls back to the smartctl ladder for a non-NVMe disk when WMI has no data and smartctl is available' {
  Mock Get-CimInstance { @() }
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' -PnpDeviceId 'SCSI\DISK&VEN_X' -SmartctlAvailable $true
  $result.Supported | Should -BeTrue
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'sat' }
 }
 It 'does not fall back to smartctl for a non-NVMe disk when WMI has no data and smartctl is unavailable' {
  Mock Get-CimInstance { @() }
  Mock Invoke-SmartctlCommand { throw 'should never be called' }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' -PnpDeviceId 'SCSI\DISK&VEN_X' -SmartctlAvailable $false
  $result.Supported | Should -BeFalse
  $result.ErrorCode | Should -Be 'WMI-SMART-NOT-FOUND'
  Should -Invoke Invoke-SmartctlCommand -Times 0
 }
 It 'leaves the NVMe path unchanged: still uses smartctl directly with no WMI lookup when available' {
  Mock Get-CimInstance { throw 'should never be called for NVMe' }
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"NVMe"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'NVMe' -SmartctlAvailable $true
  $result.Supported | Should -BeTrue
  $result.Source | Should -Be 'NVMe'
  Should -Invoke Get-CimInstance -Times 0
 }
 It 'leaves the NVMe path unchanged: returns SMARTCTL-NOT-FOUND without invoking smartctl when unavailable' {
  Mock Invoke-SmartctlCommand { throw 'should never be called' }
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'NVMe' -SmartctlAvailable $false
  $result.Supported | Should -BeFalse
  $result.ErrorCode | Should -Be 'SMARTCTL-NOT-FOUND'
  Should -Invoke Invoke-SmartctlCommand -Times 0
 }
}

Describe 'Get-StorageInventory (SMART capture)' {
 It 'still tries WMI (needs no binary) but never spawns a smartctl process when smartctl.exe is absent, and degrades gracefully when WMI has no data either' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'Win32_DiskDrive') {
    @([pscustomobject]@{ Index = 0; Model = 'Disk A'; Manufacturer = 'Acme'; SerialNumber = 'SN-A'; InterfaceType = 'SCSI'; MediaType = 'Fixed hard disk'; FirmwareRevision = '1.0'; Size = 500GB; Partitions = 1; Status = 'OK'; PNPDeviceID = 'SCSI\DISK&VEN_ACME&PROD_A\1&aaaaaaaa&0&000000' })
   } else { @() }
  }
  Mock Invoke-SmartctlCommand { throw 'should never be called' }

  $missingPath = Join-Path $TestDrive 'does-not-exist-smartctl.exe'
  $result = Get-StorageInventory -SmartctlPath $missingPath

  $result.Physical.Count | Should -Be 1
  $result.Physical[0].PNPDeviceID | Should -Be 'SCSI\DISK&VEN_ACME&PROD_A\1&aaaaaaaa&0&000000'
  $result.Physical[0].Smart.Supported | Should -BeFalse
  $result.Physical[0].Smart.Source | Should -Be 'Unavailable'
  $result.Physical[0].Smart.ErrorCode | Should -Be 'WMI-SMART-NOT-FOUND'
  Should -Invoke Invoke-SmartctlCommand -Times 0
 }

 It 'kills a hanging smartctl invocation via its 15s timeout and marks the disk SMARTCTL-TIMEOUT' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'Win32_DiskDrive') {
    @([pscustomobject]@{ Index = 0; Model = 'Disk A'; Manufacturer = 'Acme'; SerialNumber = 'SN-A'; InterfaceType = 'SCSI'; MediaType = 'Fixed hard disk'; FirmwareRevision = '1.0'; Size = 500GB; Partitions = 1; Status = 'OK' })
   } else { @() }
  }
  $smartctlPath = Join-Path $TestDrive 'smartctl.exe'
  New-Item -Path $smartctlPath -ItemType File -Force | Out-Null

  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $false; StdOut = $null; ExitCode = $null; ErrorCode = 'SMARTCTL-TIMEOUT'; ErrorMessage = 'smartctl no respondió en 15000 ms para el disco 0.' }
  }

  $result = Get-StorageInventory -SmartctlPath $smartctlPath

  $result.Physical[0].Smart.Supported | Should -BeFalse
  $result.Physical[0].Smart.ErrorCode | Should -Be 'SMARTCTL-TIMEOUT'
  Should -Invoke Invoke-SmartctlCommand -Times 1
 }

 It 'keeps every disk in the result and isolates a per-disk SMART failure without dropping other disks' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'Win32_DiskDrive') {
    @(
     [pscustomobject]@{ Index = 0; Model = 'Disk0'; Manufacturer = 'Acme'; SerialNumber = 'SN-0'; InterfaceType = 'SCSI'; MediaType = 'Fixed hard disk'; FirmwareRevision = '1.0'; Size = 500GB; Partitions = 1; Status = 'OK' }
     [pscustomobject]@{ Index = 1; Model = 'Disk1'; Manufacturer = 'Acme'; SerialNumber = 'SN-1'; InterfaceType = 'SCSI'; MediaType = 'Fixed hard disk'; FirmwareRevision = '1.0'; Size = 500GB; Partitions = 1; Status = 'OK' }
    )
   } else { @() }
  }
  $smartctlPath = Join-Path $TestDrive 'smartctl.exe'
  New-Item -Path $smartctlPath -ItemType File -Force | Out-Null

  Mock Get-DiskSmartData {
   param($SmartctlPath, $DiskIndex, $BusType)
   if ($DiskIndex -eq 1) { throw 'smartctl process error on disk 1' }
   return [ordered]@{ Supported = $true; Source = 'ATA'; OverallHealth = 'PASSED'; ErrorCode = $null; ErrorMessage = $null }
  }

  $result = Get-StorageInventory -SmartctlPath $smartctlPath

  $result.Physical.Count | Should -Be 2
  $result.Physical[0].Smart.Supported | Should -BeTrue
  $result.Physical[1].Smart.Supported | Should -BeFalse
  $result.Physical[1].Smart.ErrorCode | Should -Be 'SMARTCTL-PROCESS-ERROR'
 }
}
