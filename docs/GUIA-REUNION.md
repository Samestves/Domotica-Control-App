# Guía de la casa domótica · Alpha 0.9

## Dónde estamos

- **App:** Alpha 0.9.0. Pasó una auditoría completa del código (ver [AUDITORIA.md](AUDITORIA.md)) y 71 pruebas automáticas.
- **Casa:** el ESP32 del grupo tiene nuestro programa, con el cableado de su documento «Conexiones GPIO».
  Está **probado por Bluetooth con el Redmi** con la versión `alpha-0.6`: luces, puertas, persianas y alarma responden.
  En la placa suelta solo se ve «Luz Sala 1», porque es el LED azul del propio ESP32 (GPIO 2).
- **Versión nueva de la casa, `casa-0.7`:** compilada y revisada, **todavía sin cargar ni probar en la placa**.
- **Carrito:** tiene `carro-0.2`. La versión nueva, `carro-0.4`, está compilada y revisada, **todavía sin cargar**.
  Ojo: `carro-0.4` **pide clave**, así que necesita la app 0.9.0 o más nueva (las anteriores no saben pedirla).
- Falta probar todo **conectado a la maqueta** y al carrito con sus motores.

| Pieza | Pin virtual | GPIO |
|---|---|---|
| Portón garaje · Puerta principal · Puerta salón · Puerta baño · Puerta cuarto | V0 · V1 · V2 · V3 · V4 | 13 · 14 · 15 · 16 · 17 |
| Persiana sala · Persiana cuarto · Persiana cocina 1 · Persiana cocina 2 | V5 · V6 · V7 · V8 | 18 · 19 · 21 · 22 |
| Sirena (buzzer activo) | V9 | 27 |
| Luz sala 1 · Luz sala 2 · Luz cocina · Luz baño · Luz cuarto · Luz garaje | V10 a V15 | 2 · 4 · 5 · 12 · 25 · 26 |
| Todas las luces · Seguridad armada · Avisos | V16 · V17 · V18 | — |

Son los mismos números que usaban en Blynk.

**Aviso sobre el GPIO 12 (luz del baño):** el ESP32 lee ese pin al encenderse. Si el módulo de relé lo deja en 3,3 V
al arrancar, la placa no enciende. Si les pasa, en la app mantengan presionada la luz del baño y cámbienla al GPIO 23,
32 o 33 (y muevan el cable).

## Mostrar la app sin la maqueta

1. Abre **Casa (demo)**. Prende luces, abre puertas y mueve persianas.
2. **Arma la seguridad** y abre el **portón del garaje** o la **puerta principal**. A los pocos segundos suena la alarma: el teléfono vibra y el panel se pone en rojo. En la placa real espera 20 s, como en su versión de Blynk.
3. Enseña la **consola de mensajes**: ahí se ve lo que la app le dice a la placa (`V10:1`, `V1:1`…).
4. Mantén presionado un control: se puede cambiar su **pin**, **invertirlo** o marcarlo como **no conectado**.

## Clave de la casa (y del carrito)

Solo quien sepa la clave puede controlar la casa, por Bluetooth o por Wi‑Fi. Con `carro-0.4`, el carrito funciona igual.

- **La primera vez** que un teléfono se conecta, la app pide **crear la clave**: de 4 a 8 números. Anótenla.
  **Usen 6 a 8 números:** cuesta mucho más adivinarla.
- Cada teléfono la escribe **una sola vez**; después entra solo.
- **Cambiarla:** en la casa, menú ⋮ → **Cambiar la clave**. En el carrito, botón de ajustes → **Cambiar la clave**.
- **Tres claves incorrectas** bloquean los intentos durante 30 segundos: en la casa, solo los de esa conexión (así nadie
  bloquea al dueño desde afuera); en el carrito, los de todos.
- En la casa, con la clave ya creada, un teléfono que se conecta por Bluetooth y **no la entrega en 15 segundos** se
  desconecta solo (así nadie ocupa la conexión sin saber la clave).
- **¿La olvidaron?** Con la placa encendida, mantengan presionado **BOOT** 5 segundos. En la casa las luces parpadean 3 veces y queda sin clave. Por cable USB también se puede: escribir `CLAVE:BORRAR` en el Monitor Serie.

La clave viaja sin cifrar por Bluetooth. Para una feria es suficiente; no es seguridad bancaria.

## Conectar por Wi‑Fi

El ESP32 crea su propia red. No hace falta router, internet ni datos móviles.

1. En la app: **Agregar dispositivo → Wi‑Fi**. La app busca las redes cercanas y pone primero la de la placa
   (**Casa Domotica** o **Carrito 4x4**).
2. Toca **Unirse**: la contraseña de fábrica ya viene escrita. Android pide confirmar una vez.
3. **Probar conexión** y después **Guardar dispositivo**.

Si sales de «Agregar» sin guardar, el teléfono vuelve solo a su Wi‑Fi de siempre. Android deja unirse a **una sola red de
placa a la vez**: para usar la casa y el carrito por Wi‑Fi al mismo tiempo, uno de los dos tiene que ir por Bluetooth.

Por Wi‑Fi se conecta **un teléfono a la vez**: si llega otro, la placa le responde que ya hay uno conectado (si el primero
se fue de alcance, a los 6 segundos le deja el lugar al nuevo).

La contraseña de la red se cambia en `AP_PASS`, al inicio del programa. Para que el ESP32 de la casa se una a otra red, pongan `WIFI_PROPIA` en 0 y escriban esa red en `WIFI_SSID` y `WIFI_PASS`.

## Órdenes por voz

En el panel de la casa, toca el **micrófono** de abajo y habla. Ejemplos:

- «abre la puerta principal» · «cierra el portón» · «abre el garaje»
- «prende la luz de la cocina» · «apaga todas las luces» · «enciende las dos luces de la sala»
- «pon la persiana de la sala a la mitad» · «sube la persiana del cuarto al 30 por ciento» · «sube todo»
- «arma la alarma» · «desactiva la seguridad» · «apaga la luz de la sala y la alarma»
- Frases de ambiente, **dichas solas**: «buenas noches» o «me voy» (cierra todo, apaga las luces y arma la alarma), «ya llegué» (desarma y prende la sala).

Por seguridad, **una frase con «no», «menos» o «excepto» no hace nada** y la app pide decirlo de otra forma
(«no abras la puerta principal» antes la abría). Pedir una luz nunca mueve una puerta.

El aviso dice si la orden **de verdad llegó**: verde cuando el ESP32 la confirma (y lo dice en voz alta), rojo si no respondió, naranja si no entendió la frase (y entonces no mueve nada). Lo que no puede saber es si la pieza se movió en la maqueta: si un servo está desconectado, el ESP32 igual cree que lo movió.

Usa el reconocimiento de voz de Google del teléfono: normalmente necesita internet, o el paquete de voz en español descargado.

## Probar con la maqueta

1. Conecta el ESP32 a la maqueta. Los servos van a una **fuente externa de 5 V y al menos 3 A**, con la tierra unida a un GND del ESP32.
2. Abre **Casa Domotica** en la app y escribe la clave. Arriba debe decir **Conectado**.
3. Menú ⋮ → **Probar salidas una por una**. Cada luz, puerta y persiana se mueve en orden (con `casa-0.7` la alarma y los
   mensajes siguen funcionando mientras tanto).
4. Si algo no coincide:
   - **Se activa otra cosa:** mantén presionado el control y cambia el GPIO.
   - **Una luz funciona al revés:** activa **Invertir**.
   - **Una puerta o persiana gira hacia el lado contrario:** activa **Invertir** en ella.
   - **Una pieza no existe:** apaga **Conectado en la maqueta** (desde `casa-0.7`, una puerta desconectada ya no dispara la alarma).
   - **El ESP32 se reinicia al mover servos:** les falta su propia fuente de 5 V.

Los ajustes que hagas desde la app quedan guardados en la placa y en el teléfono. Desde `casa-0.7` la placa no deja poner dos
piezas en el mismo GPIO, y si se reinicia recuerda si la alarma estaba armada.

## Carrito 4x4

El carrito usa **la misma app**. Lo que cambia es el programa de su ESP32: `firmware/carro_esp32`, cargado en el DevKitC v4
(versión cargada hoy: `carro-0.2`; nueva: `carro-0.4`).

1. En la app: **Agregar dispositivo → Bluetooth** y elige **Carrito 4x4** (o por Wi‑Fi, red **Carrito 4x4**). El panel **Auto Robot** se elige solo.
2. Con `carro-0.4`, la primera vez la app pide **crear la clave del carrito**, igual que en la casa.
3. Panel en horizontal: **joystick** para manejar (como un tanque), **acelerador** para ir a velocidad fija, **Reversa** cambia el sentido del acelerador, **Freno** detiene todo.
4. **Con las ruedas en el aire**, botón de ajustes (arriba, junto al nombre) → **Probar ruedas**. Cada rueda gira hacia adelante, una por una: delantera izquierda, trasera izquierda, delantera derecha, trasera derecha. La que gire hacia atrás se **invierte** ahí mismo, sin recablear. Cualquier orden de manejo cancela la prueba.

Seguridad incluida:

- Si se corta la conexión, o la app deja de enviar señal por 1 segundo, **el carrito se detiene solo**.
- **No arranca solo:** después de un corte, la app pone el acelerador y el joystick en cero. Con `carro-0.4`, además, la placa
  no obedece movimientos hasta recibir los controles sueltos («suelta el joystick y el acelerador para volver a manejar»).
- Si la app pasa a segundo plano (Inicio, una llamada, pantalla apagada), el carrito frena.
- Con `carro-0.4` **maneja un solo teléfono a la vez**: si otro intenta, la placa le avisa que ya hay alguien manejando.
  Frenar sí vale desde cualquiera.
- Arranque y frenado suaves, para que no salte ni reinicie el ESP32. Ante un obstáculo (con sensor), frena al instante.

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
**Antes de cargar `carro-0.4`, actualicen la app a 0.9.0 en todos los teléfonos** (si no, no podrán crear la clave).

```powershell
.\tool\cargar_esp32.ps1 -Version carro-0.4 -Puerto COM3
```

Para volver a la versión anterior, sin clave: `-Version carro-0.2`.

## Cargar un programa nuevo en el ESP32

Conecta el ESP32 por USB. En el Administrador de dispositivos aparece como **Silicon Labs CP210x (COM3)**.
La placa de la casa entra sola en modo carga; si se queda en «Connecting…», mantén presionado **BOOT** hasta que empiece a escribir.
**Ojo con la casa:** mantener BOOT 5 segundos **mientras el programa corre** borra la clave. Para cargar, presiónenlo solo
cuando diga «Connecting…».

La forma más fácil es cargar una versión ya compilada:

```powershell
.\tool\cargar_esp32.ps1 -Version casa-0.7 -Puerto COM3
```

Para compilar y cargar el programa de `firmware/casa_esp32` desde el código (Bluetooth y Wi‑Fi juntos necesitan el esquema de memoria **Huge APP**; en el Arduino IDE: *Herramientas → Partition Scheme → Huge APP*):

```powershell
& "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" compile --upload -p COM3 --fqbn esp32:esp32:esp32:PartitionScheme=huge_app firmware\casa_esp32
```

Para probar sin teléfono, escribe mensajes como `V10:1` en el monitor serie (el cable USB no necesita clave):

```powershell
& "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" monitor -p COM3 -c baudrate=115200
```

## Volver atrás

Si algo deja de funcionar después de un cambio, el ESP32 de la casa se puede devolver a un estado conocido:

- **A la versión probada con clave y Wi‑Fi propio (antes de la auditoría):**

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
- Para **intercambiar** los GPIO de dos piezas, pasen primero una de ellas a un GPIO libre (la placa no deja dos piezas en el mismo pin).
- La fotorresistencia (LDR) y las luces exteriores están en la maqueta, pero no tienen pin asignado todavía.
- El carrito todavía no se ha probado con sus motores: primero con las ruedas en el aire.
- La casa acepta un teléfono por Bluetooth y otro por Wi‑Fi, y los dos pueden controlarla a la vez. El carrito, uno manejando.
- Los intentos de clave se cuentan por conexión: quien insista puede reconectarse para probar más. Por eso conviene una clave larga.
- La app usa Bluetooth LE. Un módulo **HC‑05** (Bluetooth clásico) todavía no es compatible.
- Solo Android.
