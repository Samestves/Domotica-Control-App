# Guía para la primera reunión · Alpha 0.1

## Qué mostrar (con o sin maqueta)

1. Abre la app: aparecen **Casa (demo)** y **Auto Robot (demo)**.
2. **Casa:** prende luces, abre la puerta, mueve la ventana y escribe en la LCD. Luego **arma la alarma**: unos segundos después se dispara, el teléfono vibra y el panel se pone en rojo.
3. **Auto Robot:** el teléfono gira a horizontal. Mueve el joystick, el acelerador y el dial de 360°.
4. Enseña la **consola de mensajes**: ahí se ve lo que la app le dice a la placa (`V1:1`, `V3:90`…).
5. Mantén presionado un control: así se cambia el **pin** o se **invierte**. Esto arregla lo que les pasó con Blynk.

## Antes de tocar su maqueta: pide estos datos

- [ ] El código que usaron con Blynk (ahí vienen los pines)
- [ ] Fotos de los cables que llegan al ESP32
- [ ] Qué hay conectado: luces, servos, buzzer, LCD, sensores
- [ ] El modelo del módulo de relés

## Para probar con su maqueta

**Qué llevar:** la laptop con el Arduino IDE listo (soporte ESP32 y la librería ESP32Servo), un **cable USB que sirva para datos** (no solo para cargar) y el teléfono con la app.

1. **Pide permiso** para cargar nuestro programa. Su ESP32 perderá el programa que tiene ahora. Si quieren conservarlo, que guarden una copia de su código.
2. Abre `firmware/casa_esp32/casa_esp32.ino`. En la tabla `ch[]`, pon los GPIO de **su** circuito.
3. Deja `USE_BLE 1` para conectar por Bluetooth. Es lo más simple porque no necesita red Wi‑Fi.
4. Carga el programa y abre el **Monitor Serie a 115200**. Escribe `V1:1`: si la luz de la sala se prende, el circuito y el programa están bien, incluso sin teléfono.
5. En la app: **Agregar dispositivo → Casa Domótica → ESP32 → Bluetooth → Buscar** y elige **«Casa Domotica»**.
6. Si algo no coincide:
   - **Se activa otra cosa:** mantén presionado el control y cambia el GPIO.
   - **Funciona al revés:** activa **Invertir**.
   - **No saben qué hay en cada pin:** menú ⋮ → **Probar salidas una por una** y miren el Monitor Serie.

## Qué decir si algo falla

Esto es una **alpha**: sirve para validar la idea y descubrir cómo está armada su maqueta. Si algo no responde, anota qué control falló y qué pasó, y se ajusta para la siguiente versión.

## Límites conocidos de la alpha

- Panel Casa con 4 interruptores, 2 servos, timbre, LCD, alarma y 2 sensores. Si tienen más cosas, o cosas distintas, hay que agregarlas al programa y a la app.
- Los pines se cambian desde la app, pero **el tipo de cada control no**: un interruptor no se puede convertir en servo.
- El perfil Auto Robot todavía no tiene programa para la placa: por ahora funciona en modo demo.
- Solo Android.
