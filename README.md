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
- **Completo:** agrega gráficos, expansión, TPM, Secure Boot, BitLocker y dispositivos con errores.

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
