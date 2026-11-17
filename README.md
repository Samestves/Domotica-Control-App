# Control Domótica · MVP

App Android (Flutter) para controlar varias placas ESP32 o Arduino a la vez, por Bluetooth LE o Wi‑Fi. Cada placa abre su propio panel: **Casa Domótica** o **Auto Robot**.

**Casa del grupo:** cómo probarla, cargar el ESP32 y volver atrás está en [docs/GUIA-REUNION.md](docs/GUIA-REUNION.md).

## Qué hay en esta carpeta

| Carpeta | Qué es |
|---|---|
| `lib/` | La app |
| `firmware/casa_esp32/` | El programa para el ESP32 de la maqueta |
| `firmware/versiones/` | Programas ya compilados y probados, listos para volver a cargar |
| `tool/placa_falsa.dart` | Una placa simulada en la PC para probar el Wi‑Fi sin hardware |
| `tool/cargar_esp32.ps1` | Carga una versión guardada en el ESP32, o le devuelve su Blynk |
| `test/` | Pruebas automáticas |
| `capturas/` | Dibuja las pantallas en PNG para revisar el diseño: `flutter test capturas --update-goldens` |
| `tool/generar_icono.py` | Genera el icono de la app en todos los tamaños de Android |

## Probar sin hardware

1. **Modo demo:** la app trae dos placas demo (Casa y Auto Robot). Abre cualquiera y prueba los controles.
2. **Placa falsa por Wi‑Fi:** en la PC ejecuta `dart run tool/placa_falsa.dart`. En la app ve a *Agregar dispositivo → Wi‑Fi*, escribe la IP que muestra la PC y el puerto 3333. El teléfono y la PC deben estar en la misma red. Pide la clave de la casa como la placa real: la primera vez se crea.

## Instalar en el teléfono

- Conecta el teléfono con depuración USB y ejecuta `flutter run`.
- También puedes copiar `build/app/outputs/flutter-apk/app-release.apk` al teléfono e instalarlo.

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

Una línea por mensaje. Por ejemplo, `V1:1` enciende la luz de la sala, `V3:90` mueve la puerta a 90°, `V10:24.1` es la temperatura que envía la placa, y `CFG:V1:23:1` cambia el pin de un control. Antes de obedecer, la placa pide la clave de la casa (`AUTH:`, `CLAVE:`). Los detalles están en `lib/core/protocol.dart`.
