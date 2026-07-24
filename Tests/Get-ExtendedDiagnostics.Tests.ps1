BeforeAll {
    . "$PSScriptRoot/../Modules/Get-ExtendedDiagnostics.ps1"
}

Describe 'Extended diagnostic normalization' {
    It 'returns bounded process rankings without idle or total instances' {
        $samples = @(
            [pscustomobject]@{ Name = '_Total'; IDProcess = 0; PercentProcessorTime = 100; WorkingSetPrivate = 0; IODataBytesPersec = 0 }
            [pscustomobject]@{ Name = 'Idle'; IDProcess = 0; PercentProcessorTime = 90; WorkingSetPrivate = 0; IODataBytesPersec = 0 }
            [pscustomobject]@{ Name = 'app-a'; IDProcess = 10; PercentProcessorTime = 170; WorkingSetPrivate = 104857600; IODataBytesPersec = 2048 }
            [pscustomobject]@{ Name = 'app-b'; IDProcess = 11; PercentProcessorTime = 20; WorkingSetPrivate = 314572800; IODataBytesPersec = 1024 }
            [pscustomobject]@{ Name = 'app-c'; IDProcess = 12; PercentProcessorTime = 10; WorkingSetPrivate = 52428800; IODataBytesPersec = 512 }
        )

        $result = ConvertTo-ProcessDiagnostic -Samples $samples -TopCount 2

        $result.Status | Should -Be 'Collected'
        $result.CapturedCount | Should -Be 3
        $result.TopByCpu.Count | Should -Be 2
        $result.TopByCpu[0].Name | Should -Be 'app-a'
        $result.TopByCpu[0].CpuUsagePercent | Should -Be 100
        $result.TopByMemory[0].Name | Should -Be 'app-b'
        $result.TopByMemory[0].WorkingSetMB | Should -Be 300
    }

    It 'redacts startup commands and users from the normalized contract' {
        $result = ConvertTo-StartupDiagnostic -Items @(
            [pscustomobject]@{ Name = 'Contoso Sync'; Command = 'C:\Users\alice\sync.exe'; Location = 'HKU\S-1-5-21-123\Software\Microsoft\Windows\CurrentVersion\Run'; User = 'DOMAIN\alice' }
            [pscustomobject]@{ Name = 'Machine Agent'; Command = 'C:\agent.exe'; Location = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Run'; User = 'Public' }
        )

        $result.Status | Should -Be 'Collected'
        ($result.Items|Where-Object Name -eq 'Contoso Sync').Scope | Should -Be 'User'
        ($result.Items|Where-Object Name -eq 'Contoso Sync').Location | Should -Be 'RegistryUser'
        ($result.Items|Where-Object Name -eq 'Machine Agent').Scope | Should -Be 'Machine'
        ($result.Items|Where-Object Name -eq 'Machine Agent').Location | Should -Be 'RegistryMachine'
        $result.Items[0].Enabled | Should -BeNullOrEmpty
        $result.Items[0].PSObject.Properties.Name | Should -Not -Contain 'Command'
        $result.Items[0].PSObject.Properties.Name | Should -Not -Contain 'User'
        ($result.Items|ConvertTo-Json -Depth 4) | Should -Not -Match 'S-1-5-21|alice|sync\.exe'
    }

    It 'deduplicates installed software and excludes hidden system components' {
        $items = @(
            [pscustomobject]@{ DisplayName = 'Contoso App'; DisplayVersion = '1.0'; Publisher = 'Contoso'; SystemComponent = 0; Scope = 'Machine'; Architecture = 'x64' }
            [pscustomobject]@{ DisplayName = 'Contoso App'; DisplayVersion = '1.0'; Publisher = 'Contoso'; SystemComponent = 0; Scope = 'Machine'; Architecture = 'x86' }
            [pscustomobject]@{ DisplayName = 'Hidden Runtime'; DisplayVersion = '2.0'; Publisher = 'Contoso'; SystemComponent = 1; Scope = 'Machine'; Architecture = 'x64' }
            [pscustomobject]@{ DisplayName = ''; DisplayVersion = '3.0'; Publisher = 'Unknown'; SystemComponent = 0; Scope = 'User'; Architecture = 'x64' }
        )

        $result = ConvertTo-InstalledSoftwareDiagnostic -Items $items

        $result.Status | Should -Be 'Collected'
        $result.Items.Count | Should -Be 1
        $result.Items[0].Name | Should -Be 'Contoso App'
        $result.Items[0].Architecture | Should -Be 'Mixed'
    }
}
