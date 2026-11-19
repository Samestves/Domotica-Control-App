# Guía de la casa domótica · Alpha 0.7

## Dónde estamos

- El ESP32 del grupo tiene nuestro programa, con el cableado de su documento «Conexiones GPIO».
- Se conecta por **Bluetooth** o por **su propia red Wi‑Fi**, y pide la **clave de la casa**.
- Está **probado por Bluetooth con el Redmi**: luces, puertas, persianas y alarma responden.
  En la placa suelta solo se ve «Luz Sala 1», porque es el LED azul del propio ESP32 (GPIO 2).
- Falta probarlo **conectado a la maqueta**.

| Pieza | Pin virtual | GPIO |
|---|---|---|
| Portón garaje · Puerta principal · Puerta salón · Puerta baño · Puerta cuarto | V0 · V1 · V2 · V3 · V4 | 13 · 14 · 15 · 16 · 17 |
| Persiana sala · Persiana cuarto · Persiana cocina 1 · Persiana cocina 2 | V5 · V6 · V7 · V8 | 18 · 19 · 21 · 22 |
| Sirena (buzzer activo) | V9 | 27 |
| Luz sala 1 · Luz sala 2 · Luz cocina · Luz baño · Luz cuarto · Luz garaje | V10 a V15 | 2 · 4 · 5 · 12 · 25 · 26 |
| Todas las luces · Seguridad armada · Avisos | V16 · V17 · V18 | — |

Son los mismos números que usaban en Blynk.

## Mostrar la app sin la maqueta

1. Abre **Casa (demo)**. Prende luces, abre puertas y mueve persianas.
2. **Arma la seguridad** y abre el **portón del garaje** o la **puerta principal**. A los pocos segundos suena la alarma: el teléfono vibra y el panel se pone en rojo. En la placa real espera 20 s, como en su versión de Blynk.
3. Enseña la **consola de mensajes**: ahí se ve lo que la app le dice a la placa (`V10:1`, `V1:1`…).
4. Mantén presionado un control: se puede cambiar su **pin**, **invertirlo** o marcarlo como **no conectado**.

## Clave de la casa

Solo quien sepa la clave puede controlar la casa, por Bluetooth o por Wi‑Fi.

- **La primera vez** que un teléfono se conecta, la app pide **crear la clave**: de 4 a 8 números. Anótenla.
- Cada teléfono la escribe **una sola vez**; después entra solo.
- **Cambiarla:** en el panel, menú ⋮ → **Cambiar la clave**.
- **Tres claves incorrectas** bloquean los intentos durante 30 segundos.
- **¿La olvidaron?** Con la placa encendida, mantengan presionado **BOOT** 5 segundos. Las luces parpadean 3 veces y la casa queda sin clave. Por cable USB también se puede: escribir `CLAVE:BORRAR` en el Monitor Serie.

La clave viaja sin cifrar por Bluetooth. Para una feria es suficiente; no es seguridad bancaria.

## Conectar por Wi‑Fi

El ESP32 crea su propia red. No hace falta router, internet ni datos móviles.

1. En **Ajustes → Wi‑Fi** del teléfono, conéctate a **Casa Domotica** (contraseña: `casadomotica`). Si Android avisa que la red no tiene internet, elige **seguir conectado**.
2. En la app: **Agregar dispositivo → Wi‑Fi → Usar** (IP `192.168.4.1`, puerto `3333`).

La contraseña de la red se cambia en `AP_PASS`, al inicio del programa. Para que el ESP32 se una a otra red, pongan `WIFI_PROPIA` en 0 y escriban esa red en `WIFI_SSID` y `WIFI_PASS`.

## Órdenes por voz

En el panel de la casa, toca el **micrófono** de abajo y habla. Ejemplos:

- «abre la puerta principal» · «cierra el portón»
- «prende la luz de la cocina» · «apaga todas las luces»
- «pon la persiana de la sala a la mitad» · «sube la persiana del cuarto al 30 por ciento»
- «arma la alarma» · «desactiva la seguridad»

El aviso dice si la orden **de verdad llegó**: verde cuando el ESP32 la confirma (y lo dice en voz alta), rojo si no respondió, naranja si no entendió la frase (y entonces no mueve nada). Lo que no puede saber es si la pieza se movió en la maqueta: si un servo está desconectado, el ESP32 igual cree que lo movió.

Usa el reconocimiento de voz de Google del teléfono: normalmente necesita internet, o el paquete de voz en español descargado.

## Probar con la maqueta

1. Conecta el ESP32 a la maqueta. Los servos van a una **fuente externa de 5 V y al menos 3 A**, con la tierra unida a un GND del ESP32.
2. Abre **Casa Domotica** en la app y escribe la clave. Arriba debe decir **Conectado**.
3. Menú ⋮ → **Probar salidas una por una**. Cada luz, puerta y persiana se mueve en orden.
4. Si algo no coincide:
   - **Se activa otra cosa:** mantén presionado el control y cambia el GPIO.
   - **Una luz funciona al revés:** activa **Invertir**.
   - **Una puerta o persiana gira hacia el lado contrario:** activa **Invertir** en ella.
   - **Una pieza no existe:** apaga **Conectado en la maqueta**.
   - **El ESP32 se reinicia al mover servos:** les falta su propia fuente de 5 V.

Los ajustes que hagas desde la app quedan guardados en la placa y en el teléfono.

## Carrito 4x4

El carrito usa **la misma app**. Lo que cambia es el programa de su ESP32: `firmware/carro_esp32`, ya cargado en el DevKitC v4 (versión guardada: `carro-0.1`).

1. En la app: **Agregar dispositivo → Bluetooth** y elige **Carrito 4x4**. El panel **Auto Robot** se elige solo. El carrito no usa clave.
2. Panel en horizontal: **joystick** para manejar (como un tanque), **acelerador** para ir a velocidad fija, **Reversa** cambia el sentido del acelerador, **Freno** detiene todo.
3. **Con las ruedas en el aire**, botón de ajustes (arriba, junto al nombre) → **Probar ruedas**. Cada rueda gira hacia adelante, una por una: delantera izquierda, trasera izquierda, delantera derecha, trasera derecha. La que gire hacia atrás se **invierte** ahí mismo, sin recablear.

Seguridad incluida:

- Si se corta el Bluetooth, o la app deja de enviar señal por 1 segundo, **el carrito se detiene solo**. Hace falta la app **0.7.2** o más nueva: las anteriores no repiten la orden y el carrito se detendría al mantener el joystick quieto.
- Arranque y frenado suaves, para que no salte ni reinicie el ESP32.

Pines (los mismos de la guía de armado):

| Rueda | L298N | Velocidad (EN) | Sentido (IN) | Sentido (IN) |
|---|---|---|---|---|
| Delantera izquierda | A · ENA, IN1, IN2 | 32 | 33 | 25 |
| Trasera izquierda | A · ENB, IN3, IN4 | 26 | 27 | 14 |
| Delantera derecha | B · ENA, IN1, IN2 | 13 | 4 | 16 |
| Trasera derecha | B · ENB, IN3, IN4 | 17 | 18 | 19 |
| Luces | — | 23 | | |
| Bocina (buzzer activo) | — | 5 | | |

Si lo cablean distinto, los pines se cambian por el monitor serie sin cargar nada de nuevo, por ejemplo `RUEDA:DI:32,33,25`, `CFG:V23:23:0:1` o `SENSOR:21,34` para un sensor de distancia HC‑SR04 (su ECHO necesita un divisor de voltaje a 3,3 V). `PINES` muestra lo que está usando y `FABRICA` vuelve a los de la tabla. Todo está explicado al inicio de `carro_esp32.ino`.

Para cargarlo de nuevo, esta placa **no entra sola en modo carga**: mantén presionado **BOOT** mientras dice «Connecting…».

```powershell
.\tool\cargar_esp32.ps1 -Version carro-0.1 -Puerto COM3
```

## Cargar un programa nuevo en el ESP32

Conecta el ESP32 por USB. En el Administrador de dispositivos aparece como **Silicon Labs CP210x (COM3)**.
No hace falta presionar BOOT ni EN: la placa entra sola en modo carga. Si se queda en «Connecting…», mantén presionado **BOOT** hasta que empiece a escribir.

Para compilar y cargar el programa de `firmware/casa_esp32`:

Bluetooth y Wi‑Fi juntos necesitan el esquema de memoria **Huge APP** (en el Arduino IDE: *Herramientas → Partition Scheme → Huge APP*).

```powershell
& "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" compile --upload -p COM3 --fqbn esp32:esp32:esp32:PartitionScheme=huge_app firmware\casa_esp32
```

Para probar sin teléfono, escribe mensajes como `V10:1` en el monitor serie:

```powershell
& "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" monitor -p COM3 -c baudrate=115200
```

## Volver atrás

Si algo deja de funcionar después de un cambio, el ESP32 se puede devolver a un estado conocido:

- **A la versión actual (clave y Wi‑Fi propio):**

  ```powershell
  .\tool\cargar_esp32.ps1 -Version alpha-0.6 -Puerto COM3
  ```

- **A la versión anterior, sin clave y solo Bluetooth:**

  ```powershell
  .\tool\cargar_esp32.ps1 -Version alpha-0.4 -Puerto COM3
  ```

- **A la primera versión probada con el Redmi:**

  ```powershell
  .\tool\cargar_esp32.ps1 -Version alpha-0.3-probada -Puerto COM3
  ```

- **A su programa de Blynk, tal como lo tenían:**

  ```powershell
  .\tool\cargar_esp32.ps1 -RespaldoBlynk "C:\Users\Sam\Downloads\Data\backup_blynk_2026-11-16.bin" -Puerto COM3
  ```

El respaldo de Blynk no está en el proyecto porque contiene sus claves de Wi‑Fi y de Blynk. Guárdalo en un lugar seguro.

## Límites conocidos de la alpha

- El panel está hecho para esta maqueta. Si agregan piezas, hay que sumarlas al programa y a la app.
- Los pines se cambian desde la app, pero **el tipo de cada control no**: una luz no se puede convertir en servo.
- La fotorresistencia (LDR) y las luces exteriores están en la maqueta, pero no tienen pin asignado todavía.
- El carrito todavía no se ha probado con sus motores: primero con las ruedas en el aire.
- Por Bluetooth se conecta un teléfono a la vez, y por Wi‑Fi otro. Pueden controlar la casa los dos a la vez.
- La app usa Bluetooth LE. Un módulo **HC‑05** (Bluetooth clásico) todavía no es compatible.
- Solo Android.
