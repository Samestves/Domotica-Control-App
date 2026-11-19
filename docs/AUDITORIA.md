# Auditoría de Control Domótica — 18 de noviembre de 2026

Revisión de la app (Flutter), la parte nativa de Android y los dos firmwares (casa y carrito), versión **Alpha 0.8.8**.
Cinco revisores trabajaron en paralelo, uno por área. Después se comprobó cada hallazgo en el código; los que dicen
**(verificado)** se reprodujeron o se confirmaron leyendo el código, y los que dicen **(según el revisor)** son
razonables pero no se probaron a mano. Nada se probó en la maqueta ni en el carrito.

## Resumen

| | |
|---|---|
| Análisis estático (`flutter analyze`) | Sin advertencias |
| Tests | 43 de 43 pasan |
| Cobertura | 72 % con las pruebas de pantallas (41 % solo con los tests) |
| Secretos en git | Ninguno: no hay tokens ni contraseñas personales |
| Dependencias | Solo versiones menores pendientes |
| Trabajo sin guardar en git | **Más de 100 archivos desde ayer** |

**Veredicto:** la base está sana. El código está ordenado, el sistema de diseño es coherente, los recursos se liberan
casi siempre y la conexión tiene latido, reintentos y confirmación. Pero hay bugs reales, y cuatro de ellos conviene
arreglarlos antes de presentar porque mueven cosas que nadie pidió mover.

---

## Prioridad 1 — Arreglar antes de presentar

### 1. El carrito arranca solo al reconectarse, y sigue andando si sales de la app (verificado)
`lib/ui/carro_panel.dart:43-53` y `firmware/carro_esp32/carro_esp32.ino:284`
- El acelerador de la app se queda fijo y la app lo reenvía cada 200 ms mientras la sesión esté conectada.
- **Si el carrito sale de alcance:** frena bien. Pero cuando la app se reconecta sola, vuelve a mandar el acelerador y
  el carrito arranca sin que nadie toque nada.
- **Si se pulsa Inicio, entra una llamada o se apaga la pantalla:** el temporizador sigue mandando órdenes, el freno
  automático de la placa nunca salta y no hay pantalla para frenar.
- **Arreglo:** en la app, poner el acelerador y el joystick en 0 al desconectarse y frenar cuando la app pasa a
  segundo plano. En el firmware, después de conectar o de un freno automático, ignorar órdenes de movimiento hasta
  recibir «neutro».

### 2. La voz abre puertas cuando le pides una luz, y no entiende el «no» (verificado con el intérprete real)
`lib/voice/voice_commands.dart:117-151, 196-200, 330`

| Frase | Lo que hace hoy | Lo que debería hacer |
|---|---|---|
| enciende la luz de la entrada | **abre la puerta principal** | decir que en la entrada no hay luz |
| enciende la luz del portón | **abre el portón** | luz del garaje |
| abre la puerta del cuarto principal | abre la puerta principal | puerta del cuarto |
| no abra la puerta principal | **la abre** | nada |
| abre todas las puertas menos la principal | abre solo la principal | todas menos esa |
| apaga la luz de la sala, no la de la cocina | apaga sala y cocina | solo la sala |
| me voy a bañar, prende la luz del baño | **modo noche: cierra todo y arma la alarma** | solo la luz del baño |
| arma la alarma para la noche | **desarma** | arma |
| sube todo | abre persianas y también puertas y portón | solo persianas |
| enciende las dos luces de la sala | solo la luz 2 | las dos |
| apaga la luz de la sala y la alarma | no hace nada | las dos cosas |
| abre el garaje | pregunta qué mover | abre el portón |

**Arreglo:** buscar las palabras de luz antes que las de puerta, que encender o apagar nunca muevan puertas, detectar
«no», «menos», «excepto» y no mandar nada en ese caso, y que las frases de ambiente sean la orden completa. Pasar esta
tabla a tests.

### 3. Doble toque deshace la orden (verificado)
`lib/ui/widgets/casa_tiles.dart:219-232` (también luces y puertas)
- Mientras la orden espera respuesta, el botón sigue activo y su texto ya cambió.
- Doble toque en **Armar** arma y desarma. Doble toque en **Sirena** la hace sonar y la apaga. En puertas, el servo
  abre y cierra.
- **Arreglo:** no aceptar toques mientras ese pin está «enviando» (como ya hace «Todas las luces»).

### 4. El carrito muestra mal la reversa y las luces al volver a entrar (verificado)
`lib/ui/carro_panel.dart:27`
- La reversa y las luces solo viven en la pantalla y empiezan apagadas. La placa sí recuerda la reversa.
- Si sales con la reversa puesta y vuelves, la pantalla dice «adelante» y el carrito retrocede.
- **Arreglo:** leer las dos cosas de lo que informa la placa (ya las manda en cada cambio y en SYNC).

---

## Prioridad 2 — Importantes

### Conexión y datos
5. **Una caída por Bluetooth gasta los 3 reintentos de golpe (verificado).** `lib/state/app_state.dart:192-195`,
   `lib/core/ble_link.dart:124-126`. Cada escritura fallida cuenta como un error nuevo y suma un reintento. Arreglo: no
   repetir estados iguales y no programar otro reintento si ya hay uno.
6. **Se puede perder la lista de dispositivos guardados (verificado).** `lib/state/app_state.dart:464-479`. Si un
   dispositivo guardado no se puede leer (por ejemplo, al volver a una versión vieja después de agregar el robot), la
   app vuelve a las demos y sobrescribe todo, con claves incluidas. Arreglo: leer cada dispositivo por separado y no
   guardar si hubo errores.
7. **«Cancelar» no detiene una conexión Wi-Fi a medias (según el revisor).** `lib/core/wifi_link.dart:33-57`. La
   conexión vieja termina de abrirse después y la placa, que acepta una sola app, echa a la nueva.
8. **La app no suelta la red de la placa (verificado).** `lib/ui/add_device_screen.dart:53-60`. Si te unes a la red de
   la placa en «Agregar» y sales sin guardar, el teléfono puede quedarse fuera del Wi-Fi de tu casa hasta cerrar la app.
9. **Dos placas por Wi-Fi a la vez se pisan (según el revisor).** `MainActivity.kt:182, 227-239`. Una petición queda
   sin respuesta y esa placa se queda en «Conectando…».

### Voz
10. **Salir de la Casa mientras escucha puede mandar una orden (según el revisor, revisó el código del plugin).**
    `lib/voice/voice_controller.dart:37, 83, 213-242`. El reconocedor de voz es uno solo para toda la app y sus avisos
    quedan atados a la primera pantalla que lo usó. En visitas siguientes los errores no llegan y la barra se queda en
    «Escuchando».
11. **El micrófono se puede tocar mientras dice «Enviando» (dos revisores coinciden).** La orden nueva se pierde y la
    voz de la app habla encima. Arreglo: desactivar el botón mientras envía.
12. **Sin reconocedor de voz o con dos inicios a la vez, tocar el micrófono no hace nada y no avisa.**

### Android
13. **«No volver a preguntar» deja al usuario en un bucle.** El botón «Dar permiso» no hace nada y no hay camino a los
    ajustes de la app. Igual con Bluetooth.
14. **Android 7 a 11 con la ubicación apagada:** el Bluetooth da un mensaje equivocado y no ofrece encenderla.

### Firmware
15. **TEST bloquea la placa:** 7 s en el carrito y 16 s en la casa, sin atender la desconexión, el sensor ni la alarma.
16. **Carrito: Bluetooth y Wi-Fi manejan a la vez sin dueño.** Un teléfono frena y el otro lo vuelve a arrancar.
17. **El carrito no pide clave.** Cualquiera cerca puede manejarlo o cambiar su configuración (RUEDA, CFG, FABRICA).
18. **Casa: alguien cerca puede bloquear al dueño** mandando 3 claves malas cada 30 s, o quedándose conectado por
    Bluetooth sin clave.
19. **Casa: la luz del baño está en GPIO 12 (posible).** Es un pin de arranque: según el módulo de relé, el ESP32 podría
    no encender. Sale del documento de conexiones del grupo; vale la pena moverla a 23, 32 o 33.

---

## Prioridad 3 — Distribución y protección de datos

20. **El APK de release se firma con la clave de depuración (verificado).** `android/app/build.gradle.kts:36`. Google
    Play lo rechazaría, y un APK compilado en otra PC no actualiza la app instalada (hay que desinstalar y se pierden
    los dispositivos).
21. **Las claves viajan al respaldo de Google (verificado).** No hay `allowBackup="false"` en el manifiesto, y la clave
    de la casa y la contraseña Wi-Fi se guardan en texto plano.
22. **Todo el trabajo desde ayer está fuera de git (verificado).** Más de 100 archivos, incluidos archivos nuevos como
    `kit.dart`, `wifi_net.dart`, `credits_screen.dart` y el firmware del carrito. Es el mayor riesgo práctico: un borrado
    o un fallo del disco y se pierde.
23. **El README manda instalar el APK universal viejo.** Tiene otro número de versión y quien tenga el APK nuevo ve «App
    no instalada».

---

## Menores
- Letras con tilde o «·» pueden verse como «��» si un mensaje llega partido por Bluetooth; un byte raro por Wi-Fi corta
  la conexión.
- Las demos reaparecen si borras todos los dispositivos.
- Una respuesta de clave desconocida deja «Conectando» para siempre.
- Rendimiento: cada mensaje de la placa redibuja todas las pantallas (unas 16 veces por segundo con el carrito).
- Animación de iconos que acumula escuchas mientras suena la sirena (`casa_tiles.dart:47-54`).
- Carrito en un teléfono pequeño en horizontal (640×360): la torreta se desborda unos 40 px.
- Accesibilidad: varios botones miden menos de 48 px, y el gris claro del modo claro tiene poco contraste.
- `capturas/failures/` no está en `.gitignore`, y las capturas incluyen el número de versión, así que cada versión
  nueva las marca como distintas.

---

## Clean Code y refactor

No hace falta un refactor grande antes de presentar: primero los bugs. Para después, en este orden:
1. **`Session`** (`app_state.dart`, unas 380 líneas) mezcla conexión, reintentos, latido, clave, pines y registro.
   Separarla en tres piezas.
2. **Intérprete de voz:** tablas con prioridad explícita, detección de negaciones y la tabla de frases como tests.
3. **Archivos grandes:** dividir `kit.dart` (733 líneas), `add_device_screen.dart` (618) y `casa_tiles.dart` (554).
4. **Firmware:** unas 150 líneas repetidas entre casa y carrito (Bluetooth, Wi-Fi, lectura de líneas) pueden ir a una
   librería común; TEST como máquina de estados.
5. **Avisos por sesión** en vez de redibujar toda la app con cada mensaje.
6. **Wi-Fi nativo** fuera de `MainActivity` a una clase propia.

## Lo que está bien hecho
- Sin advertencias del analizador y 43 tests, con pruebas de reintentos, latido, cancelación y clave.
- Ciclo de vida casi impecable: controladores, suscripciones y temporizadores se liberan.
- Sistema de diseño coherente (paleta, estilos, colores que cambian de tema en vivo).
- Confirmación real de cada orden (enviando / sin respuesta) y latido que detecta conexiones muertas.
- Firmware: los callbacks de Bluetooth solo encolan bytes, las líneas tienen tope, el carrito frena solo sin señal y
  revisa que dos piezas no compartan pin.
- Manifiesto de Android cuidado y sin secretos en el repositorio.
