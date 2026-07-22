# JSON Schema

Schema version: `2.1`

Top-level areas:

- `Collection`
- `Computer`
- `OperatingSystem`
- `BIOS`
- `Motherboard`
- `Processors`
- `Memory`
- `Storage`
- `GraphicsAdapters`
- `NetworkAdapters`
- `Security`
- `Expansion`
- `Peripherals`
- `DevicesWithErrors`

`Peripherals` contains:

- `CollectionMethod`: primary Windows source used by the collector.
- `Devices`: connected devices grouped in the HTML by `Category`.
- `Summary`: totals for categories, external devices, USB, Bluetooth and devices with problems.

Each peripheral includes its friendly name, manufacturer, PnP class, inferred connection type, status, problem code, backing service and instance identifier when Windows exposes them.
