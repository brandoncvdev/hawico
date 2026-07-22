# Hardware Inventory Collector

## Overview

Hardware Inventory Collector is a standalone Windows hardware inventory
agent that collects reliable information from Windows computers and
exports it as JSON and HTML. It feeds an inventory platform rather than
replacing it.

## Windows health diagnostic

The first delivery of the read-only Windows Performance Health Check is available
from option **3** of `Start-Inventory.ps1` or directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Collector_Windows_HealthCheck.ps1 `
  -Mode Diagnostic
```

For a shorter provider smoke test, override the sample duration with the minimum
validated value:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Collector_Windows_HealthCheck.ps1 `
  -Mode Diagnostic `
  -SampleDurationSeconds 10
```

The collector writes differentiated `*-health.json`, `*-health.html`, and
`*-health.log` artifacts. It never runs repair or optimization commands. A provider
failure is reported as partial evidence instead of being treated as a healthy value.

Run the Windows-only integration acceptance test on a Windows 10 and a Windows 11
target after installing Pester:

```powershell
Invoke-Pester -Path .\Tests\WindowsHealthIntegration.Tests.ps1 -Output Detailed
```

The architecture, contract, scoring rules, privacy policy, and phased roadmap are
defined in [`docs/HEALTH_CHECK.md`](docs/HEALTH_CHECK.md).
