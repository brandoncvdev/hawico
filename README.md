# Hardware Inventory Collector v2

## Uso rápido

1. Descomprime la carpeta completa.
2. Haz doble clic en `Ejecutar_Inventario.bat`.
3. Acepta la solicitud de permisos de administrador.
4. Selecciona inventario completo o rápido.
5. El reporte HTML se abrirá automáticamente.

## Carpetas

- `Output`: archivos JSON y HTML.
- `Logs`: registros de ejecución.
- `Modules`: módulos internos de PowerShell.

## Modos

- **Rápido:** equipo, Windows, CPU, RAM, red y almacenamiento.
- **Completo:** agrega gráficos, expansión, TPM, Secure Boot, BitLocker, periféricos conectados y dispositivos con errores.

## Configuración

El archivo `config.json` permite activar o desactivar formatos y secciones sin modificar el código.

## Compatibilidad

- Windows 10
- Windows 11
- Windows PowerShell 5.1 o superior

Ejecutar preferentemente como administrador.


## Versión 2.0.1

Se corrigió el inicio elevado para evitar que la ventana se cierre sin mostrar errores.

Use `Ejecutar_Inventario.bat`. Si existe un error de inicio, la ventana permanecerá abierta y mostrará el archivo y la línea afectada.

También se incluye `Diagnostico.ps1` para comprobar rutas, versión de PowerShell y archivos esenciales.


## Versión 2.0.2

El arranque ahora usa `Bootstrap.ps1` y PowerShell con `-NoExit`.

Esto garantiza que la consola elevada permanezca abierta aunque ocurra un error antes de cargar el menú.

Los errores de arranque se guardan automáticamente en:

`Logs\startup-error.txt`

Para diagnóstico adicional puede ejecutarse:

`Ejecutar_Modo_Diagnostico.bat`


## Versión 2.0.3

Se corrigió el error:

`El término '.\Bootstrap.ps1' no se reconoce...`

Los lanzadores ahora usan la ruta absoluta obtenida desde `%~dp0`, por lo que funcionan aunque Windows o UAC cambien la carpeta de trabajo.

Se recomienda extraer el ZIP completo antes de ejecutarlo.


## Versión 2.0.4

Se corrigió la excepción `No se encuentra la propiedad Count en este objeto`.

PowerShell puede convertir automáticamente una colección de un solo elemento en un objeto individual. Los módulos de memoria, almacenamiento, procesador, gráficos y expansión ahora fuerzan explícitamente sus resultados a arreglos mediante `@(...)`.

También se mejoró el reporte de errores para mostrar el archivo y la línea reales del módulo que falla, en lugar de señalar únicamente la llamada desde `Start-Inventory.ps1`.

## Network inventory

The collector maps physical Ethernet and Wi-Fi adapters, including disconnected interfaces when `IncludeDisconnectedAdapters` is enabled. The HTML dashboard renders one card per adapter and distinguishes active and inactive interfaces.

## Inventario de periféricos

El modo completo recopila los dispositivos PnP presentes y genera áreas separadas para USB y docks, Bluetooth, audio, cámaras, teclados, mouse, controles HID, pantallas, impresoras, almacenamiento removible, puertos, biometría, tarjetas inteligentes y sensores.

La opción `IncludePeripherals` de `config.json` permite desactivar esta recopilación. El collector excluye controladores host, hubs raíz y dispositivos virtuales conocidos para reducir duplicados y ruido, pero conserva el identificador PnP para diagnóstico.
