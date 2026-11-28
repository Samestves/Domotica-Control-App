# Guía de la casa domótica · Alpha 0.9

## Dónde estamos

- **App:** Alpha 0.9.6. Pasó una auditoría completa del código (ver [AUDITORIA.md](AUDITORIA.md)) y 97 pruebas automáticas.
  Se actualiza sola desde GitHub (ver [ACTUALIZACIONES.md](ACTUALIZACIONES.md)), **actualiza las placas por Wi‑Fi**
  (desde `casa-0.9` y `carro-0.5`) y **avisa con una notificación** cuando hay versiones nuevas.
- **Página para instalar el programa en el ESP32:** <https://samestves.github.io/Domotica-Control-App/>
  (Chrome o Edge en una computadora, sin Arduino). Ver [Cargar un programa nuevo](#cargar-un-programa-nuevo-en-el-esp32).
- **Casa:** el ESP32 del grupo tiene nuestro programa, con el cableado de su documento «Conexiones GPIO».
  Está **probado por Bluetooth con el Redmi** con la versión `alpha-0.6`: luces, puertas, persianas y alarma responden.
  En la placa suelta solo se ve «Luz Sala 1», porque es el LED azul del propio ESP32 (GPIO 2).
- **`casa-0.7`** (servos en un pin cada uno): **todavía sin probar en la placa**.
- **`casa-0.8`** (servos por el **módulo PCA9685**, como pidieron): compilada y revisada, **todavía sin probar**.
  Sin el módulo conectado, las puertas y persianas no se mueven (las luces y la alarma sí); en cuanto lo conectan, la placa
  lo encuentra sola en 2 segundos, sin volver a instalar.
- **`casa-0.9`** = `casa-0.8` + **actualización por Wi‑Fi** desde la app, y dice su versión. **Instalada por el equipo
  en la maqueta:** luces, sirena y seguridad responden. Las puertas abren, pero después de cerrar una ya no se movía
  ninguna: los servos comían de la fuentecita de la protoboard (da para uno) y el que cerraba contra la pared se
  quedaba empujando para siempre.
- **`casa-1.0`** = `casa-0.9` + cada servo **se suelta 1 s después de moverse** (ya no se queda empujando ni gastando) y
  la placa **prepara de nuevo el módulo PCA9685 si se reinicia**. Probada en la PC con su código real contra un PCA9685
  simulado; **todavía sin probar en la maqueta**. Los servos necesitan su propia fuente de 5 V y 2 A o más en la bornera
  verde del módulo (un cargador de celular sirve), con el GND unido al del ESP32.
- **`casa-1.1`** = `casa-1.0` + **invertir una puerta cambia abrir por cerrar** en su mismo recorrido (abre en 0° y cierra en
  90°). Antes invertir reflejaba el ángulo: abría igual y cerraba en 180°, así que la puerta seguía diciendo lo contrario de lo
  que hacía y al cerrar empujaba contra la pared (le pasó al salón). Con `casa-1.1`, dejen **Invertir** activado en esa puerta.
- **Carrito:** tiene `carro-0.4`, instalada con la página; conecta por Bluetooth y pide clave (necesita la app 0.9.0 o más nueva).
- **`carro-0.5`** = `carro-0.4` + **cara en una pantalla OLED** (opcional) + actualización por Wi‑Fi. Compilada y revisada,
  **todavía sin probar**. Es la que instala la página.
- Falta probar todo **conectado a la maqueta** y al carrito con sus motores.

Pines de la casa desde `casa-0.8` (hasta `casa-1.1`):

| Pieza | Pin virtual | Dónde va |
|---|---|---|
| Portón garaje · Puerta principal · Puerta salón · Puerta baño · Puerta cuarto | V0 · V1 · V2 · V3 · V4 | PCA9685, canales 0 · 1 · 2 · 3 · 4 |
| Persiana sala · Persiana cuarto · Persiana cocina 1 · Persiana cocina 2 | V5 · V6 · V7 · V8 | PCA9685, canales 5 · 6 · 7 · 8 |
| Módulo PCA9685 (SDA · SCL) | — | GPIO 21 · 22 |
| Sirena (buzzer activo) | V9 | GPIO 27 |
| Luz sala 1 · Luz sala 2 · Luz cocina · Luz baño · Luz cuarto · Luz garaje | V10 a V15 | GPIO 2 · 4 · 5 · 12 · 25 · 26 |
| Todas las luces · Seguridad armada · Avisos | V16 · V17 · V18 | — |

Son los mismos pines virtuales que usaban en Blynk: cada servo va en el canal **con su mismo número**. Los canales 9 a 15
y los GPIO 13 a 19 quedan libres.

Con `casa-0.7` (sin el módulo), los servos van directo a los GPIO 13 · 14 · 15 · 16 · 17 (puertas) y 18 · 19 · 21 · 22 (persianas).

## Módulo PCA9685 (desde `casa-0.8`)

Es una placa que genera los pulsos de hasta 16 servos. El ESP32 le habla con **dos cables** y el módulo hace el resto.

| Módulo | Va a |
|---|---|
| VCC | 3V3 del ESP32 |
| GND | GND del ESP32 |
| SDA | GPIO 21 |
| SCL | GPIO 22 |
| Bornera verde (V+ y GND) | Fuente de 5 V para los servos (**nunca** el 5 V del ESP32) |

Cada servo se enchufa en su canal (fila de 3 pines: GND, V+ y señal), con el cable marrón o negro hacia el borde
marcado GND. Una sola fuente alcanza: la placa mueve **los servos de a uno**, con 150 ms entre uno y otro, así que nunca
tiran corriente todos a la vez.

Si el módulo no responde (cable suelto, sin VCC), la app muestra error al mover una puerta o persiana, y la placa lo vuelve
a buscar cada 2 segundos. Las luces y la alarma siguen funcionando. Al conectarlo bien, el Monitor Serie (o «Detalles
técnicos» en la página de instalación) dice **«Modulo PCA9685 listo (SDA 21, SCL 22)»**.

Al pasar de `casa-0.7` a `casa-0.8` **no se pierde nada**: la clave, la seguridad, las luces y lo que tenían en Invertir o
No conectado se conservan. Solo cada servo pasa a su canal.

**Aviso sobre el GPIO 12 (luz del baño):** el ESP32 lee ese pin al encenderse. Si el módulo de relé lo deja en 3,3 V
al arrancar, la placa no enciende. Si les pasa, en la app mantengan presionada la luz del baño y cámbienla al GPIO 23,
32 o 33 (y muevan el cable).

## Actualizar las placas por Wi‑Fi (desde `casa-0.9` y `carro-0.5`)

La primera vez se instala por cable con la página. Desde ahí, **el teléfono le manda las versiones nuevas a la placa**:

1. Al abrir la app con internet, si hay una versión nueva para una placa guardada, aparece el aviso **Versión nueva para…**
   en el inicio (y la app ya la deja bajada en el teléfono). También se ve en las opciones de la placa (mantener presionada su
   tarjeta → **Programa de la placa**).
2. Tocar el aviso → **Instalar**. La app se une un momento a la red de la placa (**Casa Domotica** o **Carrito 4x4**), aunque
   la placa esté guardada por Bluetooth. Si Android pregunta, toquen **Conectar**.
3. La barra muestra lo que **la placa confirma que recibió**. La placa revisa la huella del archivo y recién entonces se reinicia.
4. La app se vuelve a conectar y comprueba que la placa dice la versión nueva: **Listo**. Desde la app 0.9.9, si la placa tarda en
   volver (Android pregunta otra vez por su red), la app sigue intentando; si pasa minuto y medio queda **Instalada** (no
   «fallida»: la placa ya revisó el programa) y se confirma sola en cuanto la placa vuelve a decir su versión.

Desde la app 0.9.9 la lista de versiones **se guarda en el teléfono**: el aviso sigue apareciendo aunque el teléfono esté en la red
de la placa (sin internet). Si la app nunca pudo leerla, la placa dice **sin revisar** (no «al día») y su hoja ofrece **Revisar ahora**.

Si algo falla (se corta el Wi‑Fi, el archivo llegó dañado, la clave guardada no sirve), **la placa sigue con su versión**.
Si la versión nueva se colgara al arrancar, la placa **vuelve sola a la anterior**. Mientras llega, la casa no mueve puertas ni
persianas y el carrito queda quieto (su cara muestra «ACTUALIZANDO 45%»).

**Avisos:** la app revisa cada 12 horas, aunque esté cerrada, si hay versiones nuevas de la app o de las placas, y avisa una
vez por versión. Se apagan en **Ajustes → Avisos**. En teléfonos Xiaomi conviene permitir el «Inicio automático» de la app.

## Mostrar la app sin la maqueta

1. Abre **Casa (demo)**. Prende luces, abre puertas y mueve persianas.
2. **Arma la seguridad** y abre el **portón del garaje** o la **puerta principal**. A los pocos segundos suena la alarma: el teléfono vibra y el panel se pone en rojo. En la placa real espera 20 s, como en su versión de Blynk.
3. Enseña la **consola de mensajes**: ahí se ve lo que la app le dice a la placa (`V10:1`, `V1:1`…).
4. Mantén presionado un control: se puede cambiar su **pin**, **invertirlo** o marcarlo como **no conectado**.

## Clave de la casa (y del carrito)

Solo quien sepa la clave puede controlar la casa, por Bluetooth o por Wi‑Fi. Desde `carro-0.4`, el carrito funciona igual.
También hace falta para **actualizar una placa**: nadie sin la clave puede cambiarle el programa.

- **La primera vez** que un teléfono se conecta, la app pide **crear la clave**: de 4 a 8 números. Anótenla.
  **Usen 6 a 8 números:** cuesta mucho más adivinarla.
- Cada teléfono la escribe **una sola vez**; después entra solo.
- **Cambiarla:** solo desde un teléfono **conectado que ya entró con la clave actual**. En el inicio, mantengan
  presionado el dispositivo → **Cambiar la clave** (desde la 0.9.2). También en el panel de la casa, menú ⋮, y en
  los ajustes del carrito. La app espera a que la placa confirme y avisa «Clave cambiada»; los demás teléfonos
  tendrán que escribir la nueva la próxima vez que se conecten.
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

1. Conecta el ESP32 a la maqueta. Los servos van a una **fuente externa de 5 V y al menos 3 A** (con `casa-0.8`, en la
   bornera verde del PCA9685), con la tierra unida a un GND del ESP32.
2. Abre **Casa Domotica** en la app y escribe la clave. Arriba debe decir **Conectado**.
3. Menú ⋮ → **Probar salidas una por una**. Cada luz, puerta y persiana se mueve en orden (con `casa-0.7` la alarma y los
   mensajes siguen funcionando mientras tanto).
4. Si algo no coincide:
   - **Se activa otra cosa:** mantén presionado el control y cambia el GPIO (en puertas y persianas, desde `casa-0.8` y la
     app 0.9.5, el **canal del PCA9685**; o muevan el servo de canal).
   - **Una luz funciona al revés:** activa **Invertir**.
   - **Una puerta o persiana gira hacia el lado contrario:** activa **Invertir** en ella.
   - **Una pieza no existe:** apaga **Conectado en la maqueta** (desde `casa-0.7`, una puerta desconectada ya no dispara la alarma).
   - **El ESP32 se reinicia al mover servos:** les falta su propia fuente de 5 V.
   - **Ninguna puerta ni persiana se mueve (con `casa-0.8`):** revisen los 4 cables del módulo y la fuente de la bornera verde.

Los ajustes que hagas desde la app quedan guardados en la placa y en el teléfono. Desde `casa-0.7` la placa no deja poner dos
piezas en el mismo GPIO, y si se reinicia recuerda si la alarma estaba armada.

## Robot que escribe (`carro-0.6`, app 0.9.9)

El robot es el panel **Auto Robot** de siempre, con otro programa: dos ruedas con motores paso a paso **28BYJ‑48** (cada uno con
su plaquita **ULN2003**), un **marcador en el centro** que sube y baja con el motor amarillo por el **L298N**, y **un ojo en cada
pantalla**. La red y el Bluetooth siguen llamándose **Carrito 4x4**, así la app lo encuentra igual. La app sabe que es el robot
porque la placa dice su lápiz al conectarse, y muestra su tablero: **Manejar** (joystick), **Escribir**, **Lápiz** y **Parar**.

**Escribir:** se teclea la palabra, la tarjeta muestra **cómo la va a dibujar** (con las mismas letras del robot) y **Escribir**. El
robot empieza donde está: ahí va la esquina de abajo a la izquierda de la primera letra, **mirando hacia donde sigue el texto**
(el punto verde de la vista previa). Las letras salen paradas hacia su izquierda. La tarjeta dice «Letra 3 de 5» y **Parar**
lo detiene y sube el marcador. Letras: A‑Z, Ñ, 0‑9 y `. , ! ? - + :`, hasta 24 (minúsculas y tildes valen). «HOLA» con letras
de 3 cm tarda poco más de un minuto.

**Antes de escribir, una vez:** botón de ajustes (junto al nombre) → **Probar**, con el robot en el aire. La rueda izquierda y
después la derecha dan un cuarto de vuelta **hacia adelante**, y el lápiz baja y sube. Lo que vaya al revés se **invierte** ahí.
En la misma hoja van las **medidas**: diámetro de la rueda, distancia entre el centro de las dos ruedas (mm, con una regla), alto
de las letras y cuánto tarda el lápiz en subir o bajar (de fábrica 65 mm, 120 mm, 30 mm y 1000 ms). Con medidas malas las letras
salen deformes; con buenas, del tamaño justo.

| Pieza | Va a |
|---|---|
| Rueda izquierda (ULN2003 IN1 a IN4) | GPIO 32, 33, 25, 26 |
| Rueda derecha (ULN2003 IN1 a IN4) | GPIO 19, 18, 17, 16 |
| Lápiz (L298N IN1, IN2; el puente de ENA puesto) | GPIO 27, 14 |
| Ojo izquierdo (SDA · SCL) | GPIO 21 · 22 |
| Ojo derecho (SDA · SCL) | GPIO 23 · 4 |
| Energía | 12 V al L298N · 5 V (Mini360, medido antes) al VIN del ESP32 y a las dos ULN2003 · **todas las tierras unidas** |

Seguridad: mientras escribe no obedece el joystick (hay que tocar **Parar**), y si se desconecta el teléfono que pidió escribir,
se detiene. Con el lápiz abajo y el joystick también dibuja a mano alzada. Quietos, los motores apagan sus bobinas.

### La hoja (`carro-0.7`, app 0.9.11)

Arriba del panel se elige **Manejar** (joystick, acelerador, reversa, velocidad lenta, lápiz, parar, la hoja y la cara en vivo) o
**Escribir** (el texto con su vista previa, la hoja, el lápiz y parar). Para escribir en el papel:

1. En los ajustes del robot, la **hoja**: Carta, A4, Oficio u otra medida (acostada: el robot escribe a lo largo).
2. Se pone el robot con el **marcador en la esquina de abajo a la izquierda**, mirando a lo largo de la hoja, y se toca **0,0**.
3. Desde ahí el robot sabe dónde está contando los pasos de las ruedas (no tiene sensores): la app lo muestra en la hoja, con
   la tinta de lo que dibuja. El joystick **no saca el marcador del papel** (girar en el lugar sí se puede).
4. Un toque en la hoja e **Ir aquí**: el robot va a ese punto y queda derecho. **Alinear** lo endereza donde está.
5. **Escribir** muestra en la hoja dónde caerá el texto: verde si cabe, rojo si no. Si no cabe, no deja empezar (las letras se
   achican con un toque: 2, 3, 4 o 5 cm).

Si las ruedas patinan o alguien levanta el robot, se pierde la cuenta: hay que poner el 0,0 otra vez. La prueba de las ruedas
(Probar) también lo borra, porque giran en el aire. Con **Velocidad lenta** el joystick vale un tercio: sirve para ubicarlo.

Probado en la computadora con el programa real y un ESP32 simulado: 68 comprobaciones del programa del robot (28 nuevas: dónde
está, la cerca, ir a un punto, si cabe el texto y la cara) y 18 de las cuentas de la hoja. **Todavía no probado en el robot de
verdad.**

Probado en la computadora con el programa real y un ESP32 simulado (39 comprobaciones: dibuja cada raya en su lugar, nunca se
mueve con el lápiz a medio camino, PARAR, la prueba y el corte de señal). **Todavía no probado en el robot de verdad.**

## Carrito 4x4 (`carro-0.5`)

El carrito usa **la misma app**. Lo que cambia es el programa de su ESP32: `firmware/carro_esp32`, cargado en el DevKitC v4
(versión cargada hoy: `carro-0.4`; nueva: `carro-0.5`, con cara y actualización por Wi‑Fi).

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
| Pantalla de la cara (SDA · SCL), desde `carro-0.5` | — | 21 · 22 | | |

Si lo cablean distinto, los pines se cambian por el monitor serie sin cargar nada de nuevo, por ejemplo `RUEDA:DI:32,33,25`, `CFG:V23:23:0:1` o `SENSOR:15,34` para un sensor de distancia HC‑SR04 (su ECHO necesita un divisor de voltaje a 3,3 V). `PINES` muestra lo que está usando y `FABRICA` vuelve a los de la tabla. Todo está explicado al inicio de `carro_esp32.ino`.

### La cara del carrito (desde `carro-0.5`)

Una pantalla **OLED de 0,96" (128×64, I2C, chip SSD1306)** hace de cara: ojos que parpadean, miran hacia donde gira, se
asustan con un obstáculo, guiñan con la bocina, se duermen después de un minuto sin uso y muestran el avance al actualizar.
Al encender dibuja el logo de Control Domótica.

| Pantalla | Va a |
|---|---|
| VCC | 3V3 del ESP32 |
| GND | GND del ESP32 |
| SDA | GPIO 21 |
| SCL | GPIO 22 |

Es opcional: **sin pantalla el carrito funciona igual**, y si se conecta después la encuentra sola en 3 segundos. Por eso
los GPIO 21 y 22 quedan reservados: si el sensor estaba en el 21, muévanlo con `SENSOR:15,34` (el Monitor Serie lo avisa).
Una de 1,3" (chip SH1106) también sirve cambiando `OLED_SH1106` a 1 en `cara.h`.

Para cargarlo de nuevo, lo más fácil es la [página de instalación](#cargar-un-programa-nuevo-en-el-esp32) (botón **Auto Robot**).
Esta placa **no entra sola en modo carga**: mantén presionado **BOOT** cuando la página lo pida (o mientras dice «Connecting…»).
**Para actualizar por Wi‑Fi después, instalen la app 0.9.6 en los teléfonos.**

```powershell
.\tool\cargar_esp32.ps1 -Version carro-0.5 -Puerto COM3
```

Para volver atrás: `-Version carro-0.4` (sin cara ni actualización por Wi‑Fi) o `-Version carro-0.2` (sin clave).

## Cargar un programa nuevo en el ESP32

**La forma más fácil, sin instalar nada:** la página <https://samestves.github.io/Domotica-Control-App/>.

1. Desenchufen la fuente y conecten **solo el cable USB** del ESP32 a la computadora.
2. Abran la página en **Chrome o Edge** (Firefox y Safari no sirven) y toquen **Casa domótica** o **Auto Robot**.
3. Elijan la placa en la lista que abre Chrome (solo aparecen las placas ESP32) y toquen **Conectar**.
4. Esperen a que el círculo llegue al 100 %. La página comprueba lo que escribió y, al final, que la placa arranca y responde.

Si la placa no aparece en la lista, la página explica qué hacer: probar otro cable (muchos cables solo cargan, no pasan datos)
o instalar el driver del chip USB. Los botones **CP2102**, **CH340** y **CH9102** bajan el driver oficial directo, y debajo dice
cómo instalarlo. El chip es el pequeño junto al USB: CP2102 y CH9102 son cuadrados, CH340 es alargado.
Si se queda esperando la placa (pasa con el carrito), la página pide mantener **BOOT** presionado y volver a intentar.
**Ojo con la casa:** mantener BOOT 5 segundos **mientras el programa corre** borra la clave. Presiónenlo solo cuando la página lo pida.

Desde la computadora del proyecto también se puede cargar una versión ya compilada. En el Administrador de dispositivos el
ESP32 aparece como **Silicon Labs CP210x (COM3)**:

```powershell
.\tool\cargar_esp32.ps1 -Version casa-0.9 -Puerto COM3
```

Para compilar una versión nueva desde el código (las dos placas usan el esquema de memoria **Minimal SPIFFS**, con dos
espacios de programa para actualizar por Wi‑Fi; en el Arduino IDE: *Herramientas → Partition Scheme → Minimal SPIFFS*).
La herramienta lee la versión de `FW_VERSION`, revisa que `ota.h` sea igual en las dos placas y la guarda en
`firmware/versiones`. Para que la página la instale, cámbienla en `web/instalador/placas.fuente.json`:

```powershell
.\tool\compilar_firmware.ps1 -Placa casa
```

Para probar sin teléfono, escribe mensajes como `V10:1` en el monitor serie (el cable USB no necesita clave):

```powershell
& "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" monitor -p COM3 -c baudrate=115200
```

## Volver atrás

Si algo deja de funcionar después de un cambio, el ESP32 de la casa se puede devolver a un estado conocido:

- **A `casa-0.8`, sin actualización por Wi‑Fi:**

  ```powershell
  .\tool\cargar_esp32.ps1 -Version casa-0.8 -Puerto COM3
  ```

- **A `casa-0.7`, con los servos directo en sus pines (sin el módulo PCA9685):**

  ```powershell
  .\tool\cargar_esp32.ps1 -Version casa-0.7 -Puerto COM3
  ```

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
- Para **intercambiar** los GPIO (o canales) de dos piezas, pasen primero una de ellas a uno libre (la placa no deja dos piezas en el mismo).
- La fotorresistencia (LDR) y las luces exteriores están en la maqueta, pero no tienen pin asignado todavía.
- El carrito todavía no se ha probado con sus motores: primero con las ruedas en el aire.
- La casa acepta un teléfono por Bluetooth y otro por Wi‑Fi, y los dos pueden controlarla a la vez. El carrito, uno manejando.
- Los intentos de clave se cuentan por conexión: quien insista puede reconectarse para probar más. Por eso conviene una clave larga.
- La app usa Bluetooth LE. Un módulo **HC‑05** (Bluetooth clásico) todavía no es compatible.
- Las placas se actualizan **por Wi‑Fi**, no por Bluetooth (tardaría minutos). Las versiones anteriores a `casa-0.9` y
  `carro-0.5` no saben recibirlas: esa primera vez es por cable, con la página.
- Solo Android.
