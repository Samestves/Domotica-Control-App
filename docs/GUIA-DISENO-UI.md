# Guía de diseño · estilo Control Domótica

Todo lo que define cómo se ve, se mueve y habla esta app, para usarlo igual en otros proyectos.
Está escrito para Flutter, pero cada sección trae lo necesario para llevarlo a la web (al final hay
un bloque de variables CSS listo para copiar).

La fuente de verdad en el código es:

| Archivo | Qué tiene |
|---|---|
| `lib/ui/theme.dart` | Colores (`Palette`), tipografía (`T`), radios (`R`) y el `ThemeData` |
| `lib/ui/widgets/kit.dart` | Iconos (`Ic`) y todos los componentes base |
| `lib/ui/widgets/app_scaffold.dart` | La pantalla con título grande que se encoge al bajar |
| `assets/fonts/` | D-DIN (licencia OFL) y Phosphor (licencia MIT), con sus licencias |

---

## 1. La idea en una frase

**Una consola de misión espacial: negro puro, letra técnica, un solo color fuerte (el texto) y nada que no sirva.**

Inspirado en la interfaz de Starlink y SpaceX. Cinco reglas lo sostienen:

1. **El contenido es el color.** El fondo es negro (o casi blanco) y el único color fuerte es el del texto.
   Un botón principal es «texto invertido»: blanco sobre negro en oscuro, negro sobre blanco en claro.
2. **Superficies planas con borde fino.** Tarjetas de 1 px de borde, sin sombras. La única sombra
   permitida es un resplandor suave que dice algo físico (una luz encendida).
3. **El color significa algo.** Verde, ámbar y rojo solo aparecen para estados reales: conectado,
   esperando, error o alarma. Nunca como decoración.
4. **Letra DIN, dos pesos.** Etiquetas y botones en MAYÚSCULAS espaciadas; todo lo demás, normal.
5. **La app nunca miente.** Si mandó una orden, muestra que espera; si la placa confirmó, lo dice;
   si no respondió, lo marca en rojo. El estado real va antes que la acción.

---

## 2. Color

Dos paletas afinadas a mano. El modo claro **no** es el oscuro invertido: cada tono está ajustado para
su fondo. Se leen siempre con `context.c.<nombre>`.

| Token | Oscuro | Claro | Para qué |
|---|---|---|---|
| `bg` | `#000000` | `#F3F3F4` | Fondo de pantalla y de las hojas |
| `surface` | `#0C0D0F` | `#FFFFFF` | Tarjetas (`Panel`) |
| `surface2` | `#15171A` | `#F4F5F7` | Controles y tarjetas dentro de tarjetas |
| `line` | `#1F2125` | `#E3E4E8` | Borde fino de tarjetas, separadores |
| `line2` | `#30333A` | `#CDD0D6` | Borde de botones y de lo que está activo |
| `text` | `#F0F0FA` | `#0A0B0D` | Texto principal y el «color fuerte» |
| `text2` | `#9AA0A9` | `#5F646C` | Texto secundario, explicaciones |
| `text3` | `#6E737C` | `#767B83` | Lo apagado: pistas, estados inactivos (≈4:1 de contraste) |
| `inverse` | `#F0F0FA` | `#0A0B0D` | Relleno de lo principal o encendido |
| `onInverse` | `#000000` | `#FFFFFF` | Texto sobre `inverse` |
| `green` | `#3DDC97` | `#119A4F` | Conectado, armado, listo |
| `amber` | `#F5B841` | `#B97F00` | Conectando, esperando, reversa |
| `red` | `#FF5A5F` | `#DB3439` | Error, sin respuesta, alarma, borrar |
| `blue` | `#5AA2FF` | `#1F6FEB` | Semilla del tema de Material (casi no se ve) |
| `glow` | `#FFCF70` | `#DB9600` | Tono cálido de luz encendida |

**Reglas de uso**

- Jerarquía de texto con tres niveles: `text` para lo importante, `text2` para explicar y `text3` para lo apagado.
- Lo encendido o elegido va **relleno** con `inverse` y su texto con `onInverse` (una luz encendida, la opción
  marcada de un selector, el botón principal).
- Un color de estado se usa en tres intensidades: texto o icono al 100 %, borde al 50–60 % y fondo al 8–14 %.
  Ejemplo: alarma sonando = icono y título `red`, borde `red` al 50 %, fondo `red` al 8 %.
- Un estado de conexión siempre lleva **punto + palabra** (● CONECTADO), nunca solo el color.

---

## 3. Tipografía

**D-DIN** (de la familia DIN, la que usa SpaceX), en dos pesos: 400 y 700. Nada más.

| Estilo | Tamaño | Peso | Espaciado | Alto | Uso |
|---|---|---|---|---|---|
| `T.display` | 34 | 700 | 0.3 | 1.05 | Título grande de cada pantalla |
| `T.title` | 26 | 700 | 0.3 | 1.10 | Título de hojas y de tarjetas grandes |
| `T.heading` | 19 | 700 | 0.3 | 1.15 | Encabezado dentro de una tarjeta |
| `T.body` | 16 | 400 | 0.2 | 1.35 | Texto normal, filas de lista |
| `T.callout` | 15 | 700 | 0.3 | 1.20 | Nombre de un control («Luz 1») |
| `T.small` | 13.5 | 400 | 0.2 | 1.35 | Explicaciones, detalles, pies |
| `T.eyebrow` | 11.5 | 700 | 1.8 | 1.20 | ETIQUETAS en mayúsculas |
| `T.button` | 13 | 700 | 1.5 | 1.00 | TEXTO DE BOTONES en mayúsculas |
| `T.stat` | 28 | 700 | 0.2 | 1.00 | Cifras grandes, con números tabulares |

**Reglas**

- **Mayúsculas espaciadas solo en etiquetas y botones** (`Eyebrow`, `PillButton`, `Segmented`).
  Títulos, nombres y textos largos van en minúscula normal.
- Los números que cambian (porcentajes, conteos, distancias) usan **cifras tabulares**
  (`FontFeature.tabularFigures()`), para que no bailen al cambiar.
- Un botón nunca corta su texto con «…»: si no cabe, se achica (`FittedBox(fit: BoxFit.scaleDown)`).
- Unidades con espacio: `67 %`, `75 cm`. Citas con comillas latinas: «Enciende la luz».

---

## 4. Iconos

**Phosphor**, en tres familias de la misma fuente:

| Familia | Cuándo |
|---|---|
| `PhosphorLight` | Normal: todo icono en reposo |
| `PhosphorFill` | Encendido o activo: la luz prendida, la puerta abierta, el escudo armado |
| `PhosphorBold` | Casi nunca; solo si un icono fino se pierde |

- Se declaran como constantes en la clase `Ic` (`Ic.light`, `Ic.lightOn`…) con su `codePoint`, para que
  Flutter recorte la fuente y solo guarde los iconos usados (de 500 KB a 15 KB).
- Tamaños: 14–16 junto a una etiqueta, 18–22 en filas y botones, 24–26 en tarjetas de control, 30 en
  encabezados de tarjeta, 40–44 en estados vacíos.
- Al cambiar de estado, el icono pasa de Light a Fill con un salto pequeño (ver Movimiento).

---

## 5. Forma y espacio

**Radios** (`R`):

| Token | Valor | Dónde |
|---|---|---|
| `R.card` | 16 | Tarjetas |
| `R.tile` | 14 | Tarjetas dentro de tarjetas (una luz, una persiana) |
| `R.control` | 12 | Campos, menús emergentes, avisos flotantes |
| `R.sheet` | 22 | Esquinas de arriba de las hojas |
| cápsula | 999 | Botones, selectores, interruptores |

**Bordes:** siempre 1 px. `line` en reposo, `line2` cuando algo está activo o es un botón secundario.

**Espacio** (en puntos lógicos):

- Margen lateral de pantalla: 16 (listas) o 20 (títulos).
- Entre tarjetas: 12. Entre tarjetas de una misma lista larga (habitaciones): 10.
- Relleno de tarjeta: 16; filas de lista 16 × 14; tarjetas de control 14.
- Antes de un encabezado de sección: 28; después: 10.
- Escala usada: 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 28.

**Tamaños táctiles:** botón normal 46 de alto, botón pequeño 34, botón redondo 40–42,
interruptor 46 × 28 (grande 60 × 34). Nada tocable por debajo de 34.

---

## 6. Componentes

Todos están en `kit.dart`. Cada uno resuelve una sola cosa.

### `Tap`: lo que se puede tocar

Envoltorio de cualquier cosa tocable: al presionar se atenúa al 72 % y se encoge apenas
(`scale` 0.98 por defecto, 0.92 en botones redondos, 0.88 en botones chicos), en 120 ms. Acepta
`onTap` y `onLongPress`. Sin efecto de onda de Material (`NoSplash`).

### `Panel`: la tarjeta

Superficie `surface`, borde `line` de 1 px, radio 16. Parámetros para `color`, `border`, `radius`
y `glow` (resplandor). Anima sus cambios de color y borde en 220 ms.

### `Eyebrow` y `SectionHeader`: las etiquetas

`Eyebrow('Seguridad')` dibuja la etiqueta en MAYÚSCULAS espaciadas, en `text2`. `SectionHeader`
la usa como título de sección con un `trailing` opcional a la derecha (por ejemplo «VER TODAS»).

### `PillButton`: el botón

Cápsula con el texto en mayúsculas. Cinco tipos y cuatro estados:

| `PillKind` | Aspecto | Uso |
|---|---|---|
| `primary` | Relleno `inverse` | La acción principal; una sola por vista |
| `secondary` | Transparente con borde `line2` | Acciones secundarias |
| `danger` | Texto y borde rojos | Peligro sin confirmar (la sirena) |
| `dangerFilled` | Relleno rojo | Confirmar algo destructivo o apagar una alarma |
| `ghost` | Relleno `surface2` | Acción discreta dentro de una tarjeta |

| `PillState` | Muestra a la izquierda |
|---|---|
| `idle` | El icono, si tiene |
| `busy` | Un círculo girando: se mandó y se espera respuesta |
| `done` | ✓: confirmado |
| `failed` | ⚠: no respondió |

Desactivado = opacidad 0.38. `small: true` = 34 de alto. Vibra con `selectionClick` al tocarlo.

### `RoundButton`: el botón redondo

Círculo de 40–42 con un icono al 48 % de su tamaño y un `tooltip` obligatorio (es su nombre para
el lector de pantalla). `filled: true` lo rellena con `inverse`. Para volver, agregar, ajustes y menús.

### `Toggle`: el interruptor

Pista que se rellena con `inverse` al encender; la perilla salta con un pequeño rebote
(`easeOutBack`, 320 ms). Extras: `busy` (gira dentro de la perilla mientras espera a la placa),
`icon` (un dibujo dentro de la perilla, por ejemplo un bombillo), `large` y `onFilled` (para usarlo
sobre una tarjeta encendida).

### `Segmented`: elegir una opción

Cápsula con las opciones; la elegida va rellena con `inverse`. Texto en mayúsculas, icono opcional.
Para 2–3 opciones cortas (tema claro/oscuro, Bluetooth / Wi‑Fi / Demo).

### `ListRow` y `RowGroup`: las listas

`ListRow`: icono, título, detalle debajo y algo a la derecha (un interruptor o una flecha).
`RowGroup` mete varias filas en una sola tarjeta, separadas por líneas finas que empiezan después
del margen, con un `footer` explicativo debajo. Así se arman Ajustes y las opciones de un dispositivo.

### `StatStrip`: las cifras

Columnas con una cifra grande (`T.stat`) y su etiqueta, separadas por líneas verticales finas.
Una cifra en cero va en `text3`. `footer` agrega debajo, en la misma tarjeta, un control relacionado
(en la casa: las cifras de luces, puertas y persianas, y debajo el interruptor de todas las luces).

### `DashedPanel`: un lugar para agregar

Contorno punteado (trazos de 5, huecos de 4, 1.2 px en `line2`) con el mismo radio que una tarjeta.
Dice «aquí cabe uno más» sin competir con las tarjetas llenas. Va al final de una lista, con un `+`
y el texto en `text2` («Agregar dispositivo»), en lugar de un botón `+` suelto en la barra de arriba.

### `StatusDot` y `ThinProgress`: el estado

`StatusDot`: punto de 7 px con un halo de su color; con `pulse: true` late despacio (conectando).
`ThinProgress`: línea de 2 px que corre de lado a lado bajo una tarjeta mientras conecta.

### `showAppSheet` y `SheetHeader`: las hojas

En vez de diálogos, todo sube desde abajo: fondo `bg`, esquinas de 22, tirador de 36 × 4 y borde
superior `line2`. `SheetHeader` pone etiqueta, título y una explicación corta. Una confirmación
destructiva es una hoja con dos botones: `dangerFilled` arriba y `secondary` («Cancelar») abajo.

### `AppScaffold`: la pantalla

Título grande (`T.display`) con etiqueta arriba y una línea de estado debajo. Al bajar 20–60 px,
el título se desvanece y aparece una barra fina con el título pequeño en mayúsculas y un borde
inferior. A la izquierda va «Volver» (o la marca en el inicio); a la derecha, hasta dos botones
redondos. La barra de abajo (voz, Guardar) va **debajo** del contenido, nunca encima, para no
tapar el teclado ni el final de la lista.

### `Brand`, `AppMark` y `AppGlyph`: la marca

`AppMark` es una casa de línea fina con una señal inalámbrica dentro, dibujada con `CustomPainter`
(se ve nítida a cualquier tamaño y toma el color del tema). `Brand` = marca + nombre en mayúsculas
muy espaciadas (2.6). `AppGlyph` = la marca dentro de un círculo relleno, para «Acerca de».

### Patrones armados con estos componentes

- **Tarjeta de control** (una luz, una puerta): toda la tarjeta es el interruptor. Apagada en
  `surface2` con borde `line`; encendida rellena de `inverse` con texto `onInverse` y, en oscuro,
  un resplandor. Arriba el icono, abajo el nombre y el estado en etiqueta. En la esquina, un
  indicador solo mientras espera (girando) o si falló (⚠ rojo).
- **Tarjeta de dispositivo**: arriba qué es (icono + etiqueta + nombre grande + flecha discreta);
  línea fina; abajo el estado (● + palabra + detalle) y **un** botón para la acción que toca
  (Conectar, Cancelar, Reintentar o Desconectar). Mantener presionado abre sus opciones.
- **Aviso** (alarma, versión nueva): un `Panel` con icono, etiqueta de color, una línea y una
  flecha o una X para descartar. Va arriba de todo en la lista.
- **Estado vacío**: icono de 44 en `text3`, un título, una línea de explicación y un botón principal.

---

## 7. Movimiento

Corto, con propósito y sin rebotes exagerados.

| Qué | Duración | Curva |
|---|---|---|
| Presionar algo (`Tap`) | 120 ms | lineal |
| Aparecer o cambiar texto, iconos, opacidad | 160–200 ms | `easeOut` |
| Colores, bordes, tamaños de tarjetas | 220–240 ms | `easeOut` / `easeOutCubic` |
| Perilla del interruptor | 320 ms | `easeOutBack` (pequeño rebote) |
| Icono que cambia de estado | 220 ms | escala 0.6 → 1 con `easeOutBack` + aparece |
| Punto que late (conectando) | 900 ms ida y vuelta | lineal |
| Alarma sonando (borde y fondo rojos) | 700 ms ida y vuelta | lineal |
| Entre pantallas | `FadeForwardsPageTransitionsBuilder` (Android) | — |

- Una flecha que gira 180° indica desplegar y plegar (200 ms).
- Lo que entra o sale de una lista crece con `AnimatedSize`, no aparece de golpe.
- Respetar «reducir movimiento» del sistema en animaciones largas o decorativas.

---

## 8. Vibración

| Momento | Vibración |
|---|---|
| Tocar un botón, un interruptor, un selector | `HapticFeedback.selectionClick()` |
| Enviar algo importante (clave, guardar) | `lightImpact()` |
| Armar, desarmar, mantener presionado | `mediumImpact()` |
| Alarma | `heavyImpact()` + sonido de alerta del sistema |

---

## 9. Patrones de experiencia

1. **Una acción principal por tarjeta y por pantalla.** El resto, secundario o en un menú.
2. **Toda la tarjeta se toca.** Nada de un botón «abrir» además de la tarjeta.
3. **Mantener presionado = opciones.** Y se dice una vez en pantalla, como pista discreta.
4. **Primero el estado, después la acción.** «● CONECTADO · 2 luces encendidas» y al lado «Desconectar».
5. **Siempre hay salida.** Mientras algo conecta, el botón dice «Cancelar»; si falló, «Reintentar».
6. **Confirmación real.** Enviando → girando; confirmado → ✓ o el estado nuevo; sin respuesta → ⚠ rojo.
   Mientras espera, un segundo toque no hace nada (así un doble toque no prende y apaga).
7. **Lo técnico, escondido.** Pines, GPIO y el registro de mensajes aparecen solo con «Modo técnico».
8. **Nada repetido.** Si una cifra ya está a la vista, no se escribe otra vez debajo. Si el título
   dice «Alarma sonando», la explicación dice solo la causa; si dice «Desarmada», no se repite
   «Seguridad desarmada».
9. **Valores por defecto sensatos.** Un campo opcional muestra en gris lo que se usará si se deja vacío.
10. **Hojas, no diálogos.** Y una hoja destructiva siempre tiene «Cancelar».
11. **Cada dato donde se usa.** En vez de un resumen de cifras («1/5 puertas»), cada cosa se dice donde
    se actúa: cuántas luces hay encendidas junto a «Todas las luces», la puerta abierta en la tarjeta de
    seguridad (antes de armar) y el resto dentro de cada habitación.
12. **Lo que se hace pocas veces, al final.** Agregar una placa vive al final de la lista; arriba
    solo queda lo que se usa siempre.

---

## 10. Textos

- Español neutro, de tú, frases cortas. El usuario es el protagonista: «Conecta la casa para usar la voz».
- Botones con verbo y en 1–3 palabras: «Conectar», «Guardar clave nueva», «Apagar alarma».
- Estados con una palabra: Conectado, Reconectando, Sin conexión, Encendida, Abierta.
- Los errores dicen qué pasó y qué hacer: «La placa no respondió. Revisa la conexión e intenta otra vez.»
- Nada de «por favor», «exitosamente», «¡!» ni «haz clic aquí».
- Ejemplos reales en los campos, y en comillas latinas: «Enciende la luz de la cocina».

---

## 11. Accesibilidad

- Contraste: `text` y `text2` pasan AA sobre su fondo; `text3` ronda 4:1 (solo para lo secundario).
- Cada botón con icono tiene nombre (`tooltip` o `Semantics(label:)`); los interruptores dicen si
  están encendidos (`Semantics(toggled:)`); las habitaciones dicen si están desplegadas.
- El estado nunca depende solo del color: punto + palabra, icono Light/Fill + texto.
- Con letra grande del sistema nada se sale: los botones se achican y los textos largos bajan de línea.

---

## 12. Llevarlo a otro proyecto

### Flutter

1. Copiar `assets/fonts/` (con sus dos licencias) y declarar las fuentes en `pubspec.yaml`:

   ```yaml
   flutter:
     fonts:
       - family: DDIN
         fonts:
           - asset: assets/fonts/D-DIN.otf
             weight: 400
           - asset: assets/fonts/D-DIN-Bold.otf
             weight: 700
       - family: PhosphorLight
         fonts: [{ asset: assets/fonts/Phosphor-Light.ttf }]
       - family: PhosphorFill
         fonts: [{ asset: assets/fonts/Phosphor-Fill.ttf }]
       - family: PhosphorBold
         fonts: [{ asset: assets/fonts/Phosphor-Bold.ttf }]
   ```

2. Copiar `lib/ui/theme.dart`, `lib/ui/widgets/kit.dart` y `lib/ui/widgets/app_scaffold.dart`.
   Cambiar en `kit.dart` lo propio de esta app: los iconos de `Ic` que no se usen, `AppMark`
   (el dibujo de la marca) y el texto de `Brand`.
3. En `MaterialApp`: `theme: buildTheme(Brightness.light)`, `darkTheme: buildTheme(Brightness.dark)`.
4. Leer los colores siempre con `context.c` y los estilos con `T.*`. Nunca un color escrito a mano.

### Web (CSS)

```css
:root {
  /* Claro */
  --bg: #F3F3F4; --surface: #FFFFFF; --surface-2: #F4F5F7;
  --line: #E3E4E8; --line-2: #CDD0D6;
  --text: #0A0B0D; --text-2: #5F646C; --text-3: #767B83;
  --inverse: #0A0B0D; --on-inverse: #FFFFFF;
  --green: #119A4F; --amber: #B97F00; --red: #DB3439; --glow: #DB9600;
  --r-card: 16px; --r-tile: 14px; --r-control: 12px; --r-sheet: 22px;
  --font: "D-DIN", "DIN Alternate", "Barlow", system-ui, sans-serif;
  color-scheme: light;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #000000; --surface: #0C0D0F; --surface-2: #15171A;
    --line: #1F2125; --line-2: #30333A;
    --text: #F0F0FA; --text-2: #9AA0A9; --text-3: #6E737C;
    --inverse: #F0F0FA; --on-inverse: #000000;
    --green: #3DDC97; --amber: #F5B841; --red: #FF5A5F; --glow: #FFCF70;
    color-scheme: dark;
  }
}
body { background: var(--bg); color: var(--text); font: 400 16px/1.35 var(--font); letter-spacing: .2px; }
.eyebrow { font: 700 11.5px/1.2 var(--font); letter-spacing: 1.8px; text-transform: uppercase; color: var(--text-2); }
.display { font: 700 34px/1.05 var(--font); letter-spacing: .3px; }
.stat    { font: 700 28px/1 var(--font); font-variant-numeric: tabular-nums; }
.panel   { background: var(--surface); border: 1px solid var(--line); border-radius: var(--r-card); padding: 16px; }
.pill    { height: 46px; padding: 0 20px; border-radius: 999px; font: 700 13px/1 var(--font);
           letter-spacing: 1.5px; text-transform: uppercase; border: 1px solid var(--line-2);
           background: transparent; color: var(--text); transition: transform .12s, opacity .12s; }
.pill.primary { background: var(--inverse); color: var(--on-inverse); border-color: var(--inverse); }
.pill:active  { transform: scale(.98); opacity: .72; }
.pill:disabled { opacity: .38; }
```

D-DIN se incluye con `@font-face` desde los mismos `.otf` (su licencia OFL lo permite); los iconos,
con el paquete web de Phosphor (`@phosphor-icons/web`), clases `ph-light` y `ph-fill`.

### Lista para revisar una pantalla nueva

- [ ] ¿Hay una sola acción principal (relleno `inverse`)?
- [ ] ¿El color aparece solo donde dice algo (estado, alarma, error)?
- [ ] ¿Etiquetas y botones en mayúsculas espaciadas, y el resto en minúscula normal?
- [ ] ¿Algún dato aparece dos veces? Quitar uno.
- [ ] ¿Todo lo tocable mide 34 o más y tiene nombre para el lector de pantalla?
- [ ] ¿Se ve bien en claro **y** en oscuro, con letra grande y en un teléfono angosto?
- [ ] ¿Lo que espera a otro (red, placa) muestra que espera, y qué pasó al final?

## 13. Lo que no se hace

- Sombras, degradados, fondos con textura, emojis como iconos.
- Más de dos pesos de letra, o mayúsculas en textos largos.
- Un color de estado como decoración (un botón verde «porque se ve bien»).
- Diálogos centrados de Material; efecto de onda al tocar.
- Dos caminos a la misma acción en la misma tarjeta.
- Mostrar «listo» antes de que el otro lado confirme.
