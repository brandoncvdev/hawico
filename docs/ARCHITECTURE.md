# Architecture

Launcher -\> Bootstrap -\> Start-Inventory -\> Collector -\> Modules -\>
JSON + HTML Export

Peripheral collection is isolated in `Modules/Get-PeripheralInfo.ps1`. It
returns a normalized `Peripherals` object so Windows-specific PnP discovery and
HTML presentation remain separate concerns.
