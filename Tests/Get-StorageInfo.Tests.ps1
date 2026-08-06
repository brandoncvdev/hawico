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

Describe 'Get-DiskSmartData' {
 It 'uses the nvme device-type flag for an NVMe bus' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"NVMe"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'NVMe' | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { $DeviceTypeFlag -eq 'nvme' }
 }
 It 'omits the device-type flag (auto-detect) for a SATA bus' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($DeviceTypeFlag) }
 }
 It 'omits the device-type flag (auto-detect) when the bus is unknown' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $true; StdOut = '{"device":{"protocol":"ATA"},"smart_status":{"passed":true}}'; ExitCode = 0; ErrorCode = $null; ErrorMessage = $null }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType $null | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($DeviceTypeFlag) }
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
 It 'does not retry a non-USB bus after a failed invocation' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $false; StdOut = $null; ExitCode = 1; ErrorCode = 'SMARTCTL-PROCESS-ERROR'; ErrorMessage = 'error' }
  }
  Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' | Out-Null
  Should -Invoke Invoke-SmartctlCommand -Times 1
 }
 It 'propagates a SMARTCTL-TIMEOUT error code from the invocation without throwing, using the 15s default timeout' {
  Mock Invoke-SmartctlCommand {
   [ordered]@{ Success = $false; StdOut = $null; ExitCode = $null; ErrorCode = 'SMARTCTL-TIMEOUT'; ErrorMessage = 'smartctl no respondió en 15000 ms para el disco 0.' }
  }
  { Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA' } | Should -Not -Throw
  $result = Get-DiskSmartData -SmartctlPath 'C:\Tools\smartctl.exe' -DiskIndex 0 -BusType 'SATA'
  $result.Supported | Should -BeFalse
  $result.Source | Should -Be 'Unavailable'
  $result.ErrorCode | Should -Be 'SMARTCTL-TIMEOUT'
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
}

Describe 'Get-StorageInventory (SMART capture)' {
 It 'marks every disk Unavailable and never spawns a process when smartctl.exe is absent' {
  Mock Get-CimInstance {
   param($Namespace, $ClassName, $Filter)
   if ($ClassName -eq 'Win32_DiskDrive') {
    @([pscustomobject]@{ Index = 0; Model = 'Disk A'; Manufacturer = 'Acme'; SerialNumber = 'SN-A'; InterfaceType = 'SCSI'; MediaType = 'Fixed hard disk'; FirmwareRevision = '1.0'; Size = 500GB; Partitions = 1; Status = 'OK' })
   } else { @() }
  }
  Mock Invoke-SmartctlCommand { throw 'should never be called' }
  Mock Get-DiskSmartData { throw 'should never be called' }

  $missingPath = Join-Path $TestDrive 'does-not-exist-smartctl.exe'
  $result = Get-StorageInventory -SmartctlPath $missingPath

  $result.Physical.Count | Should -Be 1
  $result.Physical[0].Smart.Supported | Should -BeFalse
  $result.Physical[0].Smart.Source | Should -Be 'Unavailable'
  $result.Physical[0].Smart.ErrorCode | Should -Be 'SMARTCTL-NOT-FOUND'
  Should -Invoke Get-DiskSmartData -Times 0
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
