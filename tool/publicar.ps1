<#
.SYNOPSIS
  Prepara una versión nueva de la app para publicarla en GitHub. Los teléfonos del equipo la encuentran solos
  (Ajustes → Buscar actualización, o el aviso que aparece en el inicio).

.DESCRIPTION
  1. Lee la versión de pubspec.yaml (por ejemplo 0.9.1+21) y revisa que lib\version.dart diga lo mismo.
  2. Compila los APK para teléfonos de 64 bits (arm64) y de 32 bits (armeabi).
  3. Los copia a entregas\ con nombres que la app reconoce.
  4. Con -Publicar, y si está instalada la herramienta de GitHub (gh), crea la Release.
     Si no, muestra exactamente qué poner en github.com.

.EXAMPLE
  .\tool\publicar.ps1

.EXAMPLE
  .\tool\publicar.ps1 -Notas "- Actualizar la app desde la app" -Publicar
#>
param(
  [string] $Notas = '',
  [switch] $Publicar
)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))

# El repositorio es el mismo que usa la app para buscar (lib\core\updater.dart).
$repo = [regex]::Match((Get-Content 'lib\core\updater.dart' -Raw), "repo = '([^']+)'").Groups[1].Value
if (-not $repo) { throw 'No encontré el repositorio en lib\core\updater.dart.' }

$m = [regex]::Match((Get-Content 'pubspec.yaml' -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)')
if (-not $m.Success) { throw 'No encontré la versión en pubspec.yaml (debe verse como 0.9.1+21).' }
$version = $m.Groups[1].Value
$build = $m.Groups[2].Value
$dart = Get-Content 'lib\version.dart' -Raw
if ($dart -notmatch "Alpha $([regex]::Escape($version))'" -or $dart -notmatch "appBuild = $build;") {
  throw "lib\version.dart no coincide con pubspec.yaml ($version+$build). Cambien los dos juntos."
}
$tag = "v$version+$build"

# Los avisos que flutter y gh escriben en la salida de errores no son fallas: vale su código de salida.
function Run-Native([scriptblock] $command) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & $command } finally { $ErrorActionPreference = $previous }
  return $LASTEXITCODE
}

Write-Host "Compilando Alpha $version (compilación $build)..."
$code = Run-Native { flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 | Out-Host }
if ($code -ne 0) { throw 'La compilación falló.' }

New-Item -ItemType Directory -Force 'entregas' | Out-Null
$arm64 = "entregas\Control-Domotica-Alpha-$version-arm64.apk"
$arm = "entregas\Control-Domotica-Alpha-$version-armeabi.apk"
Copy-Item 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk' $arm64 -Force
Copy-Item 'build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk' $arm -Force
Write-Host ''
Write-Host "Listos:"
Write-Host "  $arm64   (teléfonos de 64 bits, casi todos)"
Write-Host "  $arm   (teléfonos viejos de 32 bits)"
Write-Host ''

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($Publicar -and $gh) {
  $code = Run-Native { gh release create $tag $arm64 $arm --repo $repo --title "Alpha $version" --notes $Notas | Out-Host }
  if ($code -ne 0) { throw 'GitHub no aceptó la Release. Revisa que hayas iniciado sesión con: gh auth login' }
  Write-Host "Publicada: https://github.com/$repo/releases/tag/$tag"
  return
}

Write-Host "Para publicarla en la página de GitHub:"
Write-Host "  1. Abre https://github.com/$repo/releases/new"
Write-Host "  2. En «Choose a tag» escribe exactamente:  $tag   y elige «Create new tag»."
Write-Host "  3. Título:  Alpha $version"
Write-Host "  4. En la descripción, qué trae de nuevo (la app la muestra al actualizar)."
Write-Host "  5. Arrastra los dos APK de arriba a la zona de archivos y espera a que suban."
Write-Host "  6. Deja sin marcar «Set as a pre-release» y toca «Publish release»."
Write-Host ''
Write-Host "Desde ese momento, los teléfonos con la app la ven en Ajustes → Buscar actualización."
