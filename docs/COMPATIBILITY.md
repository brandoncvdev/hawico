# Compatibility

-   Windows 10
-   Windows 11
-   Windows PowerShell 5.1

Optional properties are validated before use.

Peripheral inventory prefers the Windows `PnpDevice` module. If it is not
available or returns no devices, the collector falls back to
`Win32_PnPEntity`; manufacturer and service metadata may then vary by driver.
