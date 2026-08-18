# Data Collection

Computer: Win32_ComputerSystem BIOS: Win32_BIOS Motherboard:
Win32_BaseBoard CPU: Win32_Processor Memory: Win32_PhysicalMemory +
Win32_PhysicalMemoryArray Storage: Win32_DiskDrive + Get-PhysicalDisk +
Win32_LogicalDisk Network: Get-NetAdapter + Get-NetIPConfiguration
Security: Get-Tpm + Confirm-SecureBootUEFI + Get-BitLockerVolume
Expansion: Win32_SystemSlot Devices: Get-PnpDevice

Peripherals: Get-PnpDevice -PresentOnly enriched with Win32_PnPEntity. The
collector keeps user-relevant PnP classes and attached USB/Bluetooth devices,
then filters common virtual devices, USB host controllers and root hubs.
