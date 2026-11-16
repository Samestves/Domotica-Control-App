<#
.SYNOPSIS
  Carga en el ESP32 una versión guardada del programa de la casa, o le devuelve su respaldo de Blynk.

.EXAMPLE
  # Cargar la versión probada (la de firmware\versiones\alpha-0.3-probada)
  .\tool\cargar_esp32.ps1 -Version alpha-0.3-probada -Puerto COM3

.EXAMPLE
  # Devolver el ESP32 exactamente como estaba con Blynk (respaldo completo de 4 MB)
  .\tool\cargar_esp32.ps1 -RespaldoBlynk "C:\Users\Sam\Downloads\Data\backup_blynk_2026-11-16.bin" -Puerto COM3

.NOTES
  No hace falta presionar BOOT ni EN: la placa entra sola en modo carga.
  Si se queda en «Connecting...», mantén presionado BOOT hasta que empiece a escribir.
#>
param(
  [Parameter(ParameterSetName = 'Version', Mandatory)] [string] $Version,
  [Parameter(ParameterSetName = 'Blynk', Mandatory)] [string] $RespaldoBlynk,
  [string] $Puerto = 'COM3'
)
$ErrorActionPreference = 'Stop'

$esptool = Get-ChildItem "$env:LOCALAPPDATA\Arduino15\packages\esp32\tools\esptool_py" -Recurse -Filter esptool.exe |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $esptool) { throw 'No encuentro esptool. Instala el soporte para ESP32 de Arduino.' }

$common = @('--chip', 'esp32', '-p', $Puerto, '-b', '921600', '--before', 'default_reset', '--after', 'hard_reset',
            'write_flash', '-z', '--flash_mode', 'dio', '--flash_freq', '80m', '--flash_size', '4MB')

if ($PSCmdlet.ParameterSetName -eq 'Version') {
  $dir = Join-Path $PSScriptRoot "..\firmware\versiones\$Version"
  foreach ($f in 'bootloader.bin', 'partitions.bin', 'boot_app0.bin', 'app.bin') {
    if (-not (Test-Path "$dir\$f")) { throw "Falta $f en $dir" }
  }
  Write-Host "Cargando la versión '$Version' en $Puerto..."
  & $esptool @common 0x1000 "$dir\bootloader.bin" 0x8000 "$dir\partitions.bin" 0xe000 "$dir\boot_app0.bin" 0x10000 "$dir\app.bin"
} else {
  if ((Get-Item $RespaldoBlynk).Length -ne 4MB) { throw 'El respaldo debe ser la memoria completa de 4 MB.' }
  Write-Host "Restaurando el respaldo de Blynk en $Puerto..."
  & $esptool @common 0x0 $RespaldoBlynk
}
if ($LASTEXITCODE -ne 0) { throw "La carga falló (código $LASTEXITCODE)." }
Write-Host 'Listo. La placa se reinició con el programa nuevo.'
