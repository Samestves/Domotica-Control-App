<#
.SYNOPSIS
  Compila el programa de una placa y guarda sus cuatro archivos en firmware\versiones\<versión>\.

.DESCRIPTION
  La versión sale de FW_VERSION en el .ino. Una versión que ya existe no se pisa: lo publicado no cambia
  nunca, así que para un cambio se sube el número. Compila con «Minimal SPIFFS» (dos espacios de programa,
  para la actualización por Wi-Fi) y antes revisa que ota.h sea idéntico en la casa y en el carrito.
  Necesita arduino-cli con el soporte para ESP32 2.0.9 (con el que se probaron las versiones anteriores).

.EXAMPLE
  .\tool\compilar_firmware.ps1 -Placa casa            # firmware\casa_esp32  -> firmware\versiones\casa-0.9\

.EXAMPLE
  .\tool\compilar_firmware.ps1 -Placa carro -SoloCompilar   # revisa que compile, sin guardar nada
#>
param(
  [Parameter(Mandatory)] [ValidateSet('casa', 'carro')] [string] $Placa,
  [switch] $SoloCompilar
)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))

$fqbn = 'esp32:esp32:esp32:PartitionScheme=min_spiffs'
$espacio = 0x1E0000   # cada espacio de programa en Minimal SPIFFS
$core = "$env:LOCALAPPDATA\Arduino15\packages\esp32\hardware\esp32\2.0.9"
$sketch = "firmware\${Placa}_esp32"
$nombre = "${Placa}_esp32"

$cli = (Get-Command arduino-cli -ErrorAction SilentlyContinue).Source
if (-not $cli) { $cli = "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" }
if (-not (Test-Path $cli)) { throw 'No encuentro arduino-cli. Instálalo o agrégalo al PATH.' }

# ota.h es el mismo en las dos placas: si alguien corrigió uno solo, se avisa antes de compilar.
$ota = 'firmware\casa_esp32\ota.h', 'firmware\carro_esp32\ota.h'
if ((Test-Path $ota[0]) -and (Test-Path $ota[1]) -and
    (Get-FileHash $ota[0]).Hash -ne (Get-FileHash $ota[1]).Hash) {
  throw 'ota.h no es igual en casa_esp32 y carro_esp32: copia el que corregiste al otro y vuelve a compilar.'
}

$version = [regex]::Match((Get-Content "$sketch\$nombre.ino" -Raw), '#define\s+FW_VERSION\s+"([^"]+)"').Groups[1].Value
if (-not $version) { throw "$nombre.ino no tiene #define FW_VERSION." }
$destino = "firmware\versiones\$version"
if ((Test-Path $destino) -and -not $SoloCompilar) {
  throw "$destino ya existe. Sube FW_VERSION en $nombre.ino para guardar otra versión."
}

$salida = Join-Path ([IO.Path]::GetTempPath()) "compilar-$nombre-$PID"
New-Item -ItemType Directory -Force $salida | Out-Null
try {
  Write-Host "Compilando $nombre ($version)..."
  # arduino-cli avisa por stderr que no pudo bajar índices de internet: no impide compilar. En Windows
  # PowerShell, con 'Stop' esos avisos cortarían el script, así que aquí se lee solo el código de salida.
  $ErrorActionPreference = 'Continue'
  $log = & $cli compile --fqbn $fqbn --warnings default --output-dir $salida $sketch 2>$null
  $codigo = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($codigo -ne 0) { $log | Select-Object -Last 40 | Write-Host; throw 'No compiló.' }
  $log | Where-Object { $_ -match 'Sketch|variables' } | ForEach-Object { Write-Host "  $_" }

  $archivos = [ordered]@{
    'bootloader.bin' = "$salida\$nombre.ino.bootloader.bin"
    'partitions.bin' = "$salida\$nombre.ino.partitions.bin"
    'boot_app0.bin'  = "$core\tools\partitions\boot_app0.bin"
    'app.bin'        = "$salida\$nombre.ino.bin"
  }
  foreach ($a in $archivos.GetEnumerator()) { if (-not (Test-Path $a.Value)) { throw "Falta $($a.Key) de la compilación." } }

  $tam = (Get-Item $archivos['app.bin']).Length
  Write-Host ("  Programa de {0:N0} bytes ({1} % de su espacio)" -f $tam, [math]::Floor($tam * 100 / $espacio))
  if ($tam -gt $espacio) { throw 'El programa no cabe en su espacio de Minimal SPIFFS.' }
  $boot = [IO.File]::ReadAllBytes($archivos['bootloader.bin'])
  if ($boot[0] -ne 0xE9 -or $boot[2] -ne 2 -or $boot[3] -ne 0x2F) { throw 'bootloader.bin no tiene el encabezado esperado (DIO, 80 MHz, 4 MB).' }

  if ($SoloCompilar) { Write-Host 'Compila bien. No se guardó nada.'; return }
  New-Item -ItemType Directory $destino | Out-Null
  foreach ($a in $archivos.GetEnumerator()) { Copy-Item $a.Value "$destino\$($a.Key)" }
  Write-Host "Guardada en $destino. Para que la página la instale, cámbiala en web\instalador\placas.fuente.json."
} finally {
  Remove-Item -Recurse -Force $salida -ErrorAction SilentlyContinue
}
