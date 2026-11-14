# Guía de trabajo con el equipo · Alpha 0.2

El trabajo va en dos tiempos: en la **reunión** solo llevas el teléfono, y en **casa** programas el ESP32 que te presten.

## 1. En la reunión (solo con el teléfono)

### Mostrar la app
1. Abre la app: aparecen **Casa (demo)** y **Auto Robot (demo)**.
2. **Casa:** prende luces, abre la puerta, mueve la ventana y escribe en la LCD. Luego **arma la alarma**: unos segundos después se dispara, el teléfono vibra y el panel se pone en rojo.
3. **Auto Robot:** el teléfono gira a horizontal. Mueve el joystick, el acelerador y el dial de 360°.
4. Enseña la **consola de mensajes**: ahí se ve lo que la app le dice a la placa (`V1:1`, `V3:90`…).
5. Mantén presionado un control: así se cambia el **pin**, se **invierte** o se marca como **no conectado**. Esto arregla lo que les pasó con Blynk.

### Levantar los datos de la maqueta
Toma **fotos claras** de los cables que llegan al ESP32 y anota:

- [ ] Cada pieza y el número de pin del ESP32 al que va (luces, servos, buzzer, sensores)
- [ ] ¿Las luces van con módulo de relés o son LEDs directos?
- [ ] ¿Hay sensor de movimiento? ¿Pantalla LCD? ¿Sensor de temperatura?
- [ ] ¿De dónde sale la corriente de los servos: del ESP32 o de una fuente aparte?
- [ ] El código que usaron con Blynk (ahí vienen los pines)
- [ ] **Carrito:** qué placa usa, qué módulo Bluetooth (HC‑05, HM‑10 o ninguno) y qué controlador de motores
- [ ] ¿El ESP32 usa cable micro‑USB o USB‑C? Llévate uno que sirva para **datos**

### Antes de llevarte el ESP32
- Avisa que al cargar nuestro programa **se borra el que tiene ahora**. Si quieren conservarlo, que guarden su código.
- Si puedes, marca con cinta cada cable antes de desconectarlo, o toma una foto de cerca.

## 2. En casa (con el ESP32 y la PC)

1. En `firmware/casa_esp32/casa_esp32.ino`, pon en la tabla `ch[]` los pines que anotaste. Marca con `false` en la columna «activado» lo que la maqueta no tenga.
2. Conecta el ESP32 por USB y mira qué puerto aparece (por ejemplo `COM5`) en el Administrador de dispositivos. Si no aparece ninguno, falta el driver del chip USB de la placa (CP210x o CH340).
3. Compila y carga, cambiando `COM5` por tu puerto:
   ```
   & "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" compile --upload -p COM5 --fqbn esp32:esp32:esp32 firmware\casa_esp32
   ```
   Si la carga se queda en «Connecting…», mantén presionado el botón **BOOT** de la placa.
4. Abre el monitor serie y escribe `V1:1`. Debe responder, aunque no haya nada conectado:
   ```
   & "$env:LOCALAPPDATA\Programs\arduino-cli\arduino-cli.exe" monitor -p COM5 -c baudrate=115200
   ```
5. En la app: **Agregar dispositivo → Casa Domótica → ESP32 → Bluetooth → Buscar** y elige **«Casa Domotica»**. Con el ESP32 suelto ya puedes comprobar que conecta y que los mensajes llegan.

## 3. En la siguiente reunión (ESP32 de vuelta en la maqueta)

- **Se activa otra cosa:** mantén presionado el control y cambia el GPIO.
- **Funciona al revés:** activa **Invertir**.
- **La alarma se dispara sola o un sensor marca cosas raras:** apaga **Conectado en la maqueta** en ese control.
- **No saben qué hay en cada pin:** menú ⋮ → **Probar salidas una por una**.
- **El ESP32 se reinicia cuando se mueve un servo:** el servo le está quitando corriente. Necesita su propia fuente de 5 V, con la tierra unida a la del ESP32.

Los ajustes que hagas desde la app quedan guardados en la placa.

## Límites conocidos de la alpha

- Panel Casa con 4 interruptores, 2 servos, timbre, LCD, alarma y 2 sensores. Si tienen más cosas, o cosas distintas, hay que agregarlas al programa y a la app.
- Los pines se cambian desde la app, pero **el tipo de cada control no**: un interruptor no se puede convertir en servo.
- El perfil Auto Robot todavía no tiene programa para la placa: por ahora funciona en modo demo.
- La app usa Bluetooth LE. Un módulo **HC‑05** (Bluetooth clásico) todavía no es compatible.
- El timbre asume un buzzer **activo** (el que suena con solo darle corriente).
- Solo Android.
