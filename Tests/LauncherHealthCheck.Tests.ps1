Describe 'Start-Inventory health-check integration' {
 BeforeAll { $script=Get-Content "$PSScriptRoot/../Start-Inventory.ps1" -Raw }
 It 'references the health collector' { $script|Should -Match 'Collector_Windows_HealthCheck\.ps1' }
 It 'offers a health diagnostic menu action' { $script|Should -Match 'diagnóstico de salud';$script|Should -Match '\-Mode Diagnostic' }
 It 'opens only health reports for the health action' { $script|Should -Match '\*-health\.html' }
 It 'does not pass a disabled HTML path to Test-Path' { $script|Should -Match 'IsNullOrWhiteSpace\(\$result\.HtmlPath\)' }
}
