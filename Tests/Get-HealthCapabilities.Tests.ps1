BeforeAll {
    . "$PSScriptRoot/../Modules/Get-HealthCapabilities.ps1"
}

Describe 'Get-HealthCapability' {
    BeforeEach {
        Mock Test-HealthAdministrator { $true }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
    }

    It 'reports available Windows providers' {
        $result = Get-HealthCapability

        $result.IsAdministrator | Should -BeTrue
        @($result.Items | Where-Object { $_.Name -ne 'Administrator' -and $_.Status -eq 'Available' }).Count | Should -Be 4
        $result.Items.Name | Should -Contain 'PerformanceCounters'
    }

    It 'reports a missing provider as not supported' {
        Mock Get-Command {
            if ($Name -eq 'Get-Counter') { return $null }
            return [pscustomobject]@{ Name = $Name }
        }

        $result = Get-HealthCapability
        $counter = $result.Items | Where-Object Name -eq 'PerformanceCounters'

        $counter.Status | Should -Be 'NotSupported'
    }

    It 'reports denied administrator capability without failing' {
        Mock Test-HealthAdministrator { $false }

        $result = Get-HealthCapability
        $administrator = $result.Items | Where-Object Name -eq 'Administrator'

        $result.IsAdministrator | Should -BeFalse
        $administrator.Status | Should -Be 'Denied'
    }
}
