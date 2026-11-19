# Control Domótica · Alpha 0.9

App Android (Flutter) para controlar varias placas ESP32 o Arduino a la vez, por Bluetooth LE o Wi‑Fi. Cada placa abre su propio panel: **Casa Domótica** o **Auto Robot**.

**Casa del grupo:** cómo probarla, cargar el ESP32 y volver atrás está en [docs/GUIA-REUNION.md](docs/GUIA-REUNION.md).
**Revisión del código:** qué se revisó, qué se arregló y qué falta, en [docs/AUDITORIA.md](docs/AUDITORIA.md).
**Actualizaciones:** la app se actualiza sola desde GitHub; cómo publicar una versión nueva, en [docs/ACTUALIZACIONES.md](docs/ACTUALIZACIONES.md).

## Qué hay en esta carpeta

| Carpeta | Qué es |
|---|---|
| `lib/` | La app |
| `firmware/casa_esp32/` | El programa para el ESP32 de la maqueta |
| `firmware/carro_esp32/` | El programa para el ESP32 del carrito 4x4 (dos L298N, sin librerías extra) |
| `firmware/versiones/` | Programas ya compilados, listos para cargar: `casa-0.7` y `carro-0.4` son los más nuevos |
| `docs/` | Guía del grupo, auditoría del código y cómo firmar la app ([FIRMA.md](docs/FIRMA.md)) |
| `entregas/` | Los APK para pasar a los teléfonos (no se sube a git) |
| `tool/placa_falsa.dart` | Una placa simulada en la PC para probar el Wi‑Fi sin hardware |
| `tool/cargar_esp32.ps1` | Carga una versión guardada en el ESP32, o le devuelve su Blynk |
| `tool/publicar.ps1` | Compila los APK de una versión nueva y dice cómo publicarla en GitHub |
| `test/` | Pruebas automáticas |
| `capturas/` | Dibuja las pantallas en PNG para revisar el diseño: `flutter test capturas --update-goldens` |
| `tool/generar_icono.py` | Genera el icono de la app en todos los tamaños de Android |

## Probar sin hardware

1. **Modo demo:** la app trae dos placas demo (Casa y Auto Robot). Abre cualquiera y prueba los controles.
2. **Placa falsa por Wi‑Fi:** en la PC ejecuta `dart run tool/placa_falsa.dart`. En la app ve a *Agregar dispositivo → Wi‑Fi*, escribe la IP que muestra la PC y el puerto 3333. El teléfono y la PC deben estar en la misma red. Pide la clave de la casa como la placa real: la primera vez se crea.

## Instalar en el teléfono

- Conecta el teléfono con depuración USB y ejecuta `flutter run`.
- O pasa al teléfono el APK más nuevo de `entregas/`, por ejemplo `Control-Domotica-Alpha-0.9.0-arm64.apk` (unos 18 MB).
  Se compila con `flutter build apk --release --split-per-abi --target-platform android-arm64`.
- Ese APK es para teléfonos de 64 bits (casi todos los de los últimos años). Para un teléfono viejo de 32 bits hay que
  compilar el APK universal con `flutter build apk --release` (unos 50 MB). **No mezclen los dos en un mismo teléfono:**
  tienen distinto número de versión y Android responde «App no instalada»; para cambiar de uno al otro hay que desinstalar.
- Antes de cargar `carro-0.4` en el carrito, todos los teléfonos necesitan la app 0.9.0 o más nueva (el carrito ahora pide clave).

## Cargar el programa en el ESP32

1. Instala el Arduino IDE, el soporte para placas ESP32 y la librería **ESP32Servo**.
2. Abre `firmware/casa_esp32/casa_esp32.ino` y revisa la sección **CONFIGURACIÓN**: Bluetooth, Wi‑Fi propio del ESP32 o la red de la casa.
3. Revisa la tabla `ch[]`: cada fila es una salida de la maqueta con su GPIO. **Tiene que coincidir con los cables reales.**
4. Placa: *ESP32 Dev Module* con *Partition Scheme → Huge APP* (Bluetooth y Wi‑Fi juntos no caben en la normal).
5. Abre el Monitor Serie a 115200. Puedes escribir `V1:1` ahí mismo para probar sin teléfono.

## Si algo no responde bien

- **Se activa otra cosa:** el GPIO no coincide con el cable. Mantén presionado el control en la app y cambia el GPIO.
- **Funciona al revés:** activa **Invertir** en ese mismo ajuste. Pasa con la mayoría de los módulos de relé.
- **No sé qué hay en cada pin:** menú ⋮ → *Probar salidas una por una*. El Monitor Serie dice qué pin se está probando.

## Protocolo

Una línea por mensaje. Por ejemplo, `V10:1` enciende la luz 1 de la sala, `V1:1` abre la puerta principal, `V5:90` deja la persiana de la sala a la mitad, y `CFG:V10:23:0:1` cambia el pin de un control. Antes de obedecer, la placa pide su clave (`AUTH:`, `CLAVE:`): la casa siempre, y el carrito desde `carro-0.4`. `PING` → `PONG` es el latido que usa la app para notar si la placa se apagó. Los detalles están en `lib/core/protocol.dart` y al inicio de cada `.ino`.
