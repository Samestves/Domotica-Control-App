/*
  Auto Robot · programa para el ESP32 del robot que escribe · versión carro-0.7
  -----------------------------------------------------------------------------
  Dos ruedas con motores paso a paso 28BYJ-48 (cada uno con su plaquita ULN2003), un marcador en el centro
  que sube y baja con un motor amarillo (TT) por un L298N, y una pantalla OLED para cada ojo. Se maneja desde
  la app (panel «Auto Robot») por Bluetooth LE o por Wi-Fi, y escribe lo que le mandan desde la app.

  Wi-Fi propio: el ESP32 crea la red «Carrito 4x4» (contraseña: carrito4x4); es el nombre de siempre, así la
  app lo sigue encontrando. La app se une a esa red y se conecta a la IP 192.168.4.1, puerto 3333.
  Bluetooth y Wi-Fi funcionan a la vez: un teléfono por cada uno. Por Wi-Fi, si ya hay un teléfono
  con clave conectado, otro que llegue recibe «ERR:ya hay otro telefono conectado por Wi-Fi» y se
  corta (salvo que el primero lleve 6 s mudo). Un teléfono por Wi-Fi que pasa 6 s sin mandar nada
  se desconecta (la app manda PING cada 3 s).

  Pines virtuales (los mismos del panel en la app):
    V20  joystick «x,y», cada uno de -100 a 100 (y positivo = adelante, x positivo = derecha)
    V24  acelerador: 0..100 (hacia adelante, o hacia atrás con la reversa)
    V25  reversa: 1 / 0 (cambia el sentido del acelerador; el joystick no se ve afectado)
    V27  invertir: tres 0/1 en orden rueda izquierda, rueda derecha, lápiz. Ej.: V27:010 invierte la derecha
    V28  lápiz: 1 = abajo (marca) · 0 = arriba. La placa lo dice cada vez que cambia
    V29  trabajo: «3/5» = escribiendo, va en la letra 3 de 5 · «ir» = yendo a un punto · «0» = nada
    V30  medidas «rueda,eje,letra,lapiz»: diámetro de las ruedas en mm, distancia entre ellas (de centro a
         centro) en mm, alto de las letras en mm y cuánto tarda el lápiz en subir o bajar en ms.
         Ej.: V30:65,120,30,1000. Se guardan en la placa.
    V31  dónde está (de la placa a la app): «x,y,a» en mm y grados desde el 0,0 · «-» = sin 0,0
    V32  la hoja: «ancho,alto» en mm (ej.: V32:279,216, una carta acostada) · «0,0» = sin hoja. Se guarda.
    V33  la cara, para verla en la app (de la placa a la app, solo a quien la pidió con CARA:1; ver cara.h)
    V34  el mensaje de la cara: «número,ms,TEXTO»

  La hoja (desde carro-0.7). El robot sabe dónde está contando los pasos de cada rueda, sin sensores:
    CERO            el 0,0 es donde está el marcador ahora, mirando hacia +x. Se pone el robot en la esquina
                    de abajo a la izquierda de la hoja, mirando a lo largo de ella, y se toca 0,0 en la app.
    IR:150,80       va a ese punto (mm) con el marcador arriba y queda mirando hacia +x: el texto sale derecho.
                    Responde OK:IR 150,80, avisa V29:ir y al llegar dice OK:LLEGO.
    ALINEAR         gira en el lugar hasta mirar hacia +x.
  Con la hoja y el 0,0, el joystick y el acelerador no dejan que el marcador salga de la hoja (girar en el
  lugar sí: el marcador no se mueve) y ESCRIBIR revisa que el texto quepa antes de empezar. Si las ruedas
  patinan o alguien levanta el robot, se pierde la cuenta: hay que volver a poner el 0,0. TEST la borra.
    CARA:1 / CARA:0 la app empieza o deja de mirar la cara (V33 y V34 mientras tanto).

  Escribir (letras de un solo trazo: letras.h y escritura.h):
    ESCRIBIR:HOLA   dibuja el texto: A-Z, Ñ, 0-9 y . , ! ? - + : (minúsculas y tildes valen), hasta 24 letras.
                    Responde OK:ESCRIBIENDO HOLA, avisa cada letra con V29 y al final dice OK:ESCRITO.
                    Empieza donde está el robot: ahí va la esquina de abajo a la izquierda de la primera letra,
                    y las letras salen paradas hacia su izquierda mientras avanza.
    PARAR           detiene todo: la escritura (sube el marcador), ir a un punto, las ruedas y la prueba.
  Mientras escribe (o va a un punto) no obedece el joystick (avisa que hay que tocar Parar). Si se desconecta
  el teléfono que lo pidió, se detiene. Con el lápiz abajo y el joystick también dibuja: a mano alzada.

  Clave del robot (de 4 a 8 números; el mismo protocolo que la casa). Por Bluetooth y Wi-Fi el
  robot no obedece hasta recibirla, y cada conexión la entrega por su cuenta:
    AUTH:123456     la app entrega la clave. Respuestas:
                      AUTH:OK          correcta
                      AUTH:MAL:2       incorrecta; quedan 2 intentos
                      AUTH:ESPERA:30   demasiados intentos; hay que esperar 30 s
                      AUTH:NUEVA       el robot todavía no tiene clave: hay que crearla
                      AUTH:PIDE        falta la clave (se envió una orden sin entregarla)
    CLAVE:123456    crea la clave, o la cambia si ya se entregó la actual. Responde AUTH:OK.
    Sin clave solo se contesta PING; cualquier otra orden responde AUTH:PIDE (o AUTH:NUEVA).
    El Monitor Serie (cable USB) no necesita clave. Ahí, CLAVE:BORRAR deja el robot sin clave.
    Sin computadora: mantener presionado BOOT 5 s con la placa encendida también la borra
    (los ojos lo muestran pidiendo la clave).

  Seguridad:
    - Un solo conductor: el primero (Bluetooth, Wi-Fi o Monitor Serie) que manda joystick o acelerador
      distinto de cero (o pide escribir) maneja; a los demás se les responde «ERR:otro telefono esta
      manejando el carrito». Deja de serlo si se desconecta o pasa 1 segundo sin mandar joystick ni
      acelerador (escribiendo, hasta que termina). Parar (V24:0, V20:0,0, PARAR) vale desde cualquiera.
    - Si se corta el Bluetooth o el Wi-Fi del que maneja, las ruedas se detienen al instante.
    - Si el conductor deja de enviar joystick o acelerador por 1 segundo mientras el robot anda,
      se detiene solo. PING y las demás órdenes no cuentan como señal.
    - Seguro de manejo: después de conectarse, desconectarse o frenar por falta de señal, no obedece
      movimientos hasta que el joystick (V20:0,0) y el acelerador (V24:0) lleguen en cero.
    - Arranque suave: las ruedas no saltan de golpe a toda velocidad (un motor paso a paso que arranca
      muy rápido se traba).
    - Quietas, las bobinas de los motores se apagan: no se calientan ni gastan las pilas.
    - Si el programa se traba más de 5 s, la placa se reinicia sola (watchdog) y las ruedas quedan quietas.

  Pines de fábrica (los de la guía de armado):
    rueda izquierda   ULN2003   IN1 32 · IN2 33 · IN3 25 · IN4 26
    rueda derecha     ULN2003   IN1 19 · IN2 18 · IN3 17 · IN4 16
    lápiz             L298N     IN1 27 · IN2 14 (el puente de ENA queda puesto)
    ojos (cara.h)     izquierdo SDA 21 · SCL 22 · derecho SDA 23 · SCL 4
  Energía: 12 V al L298N; 5 V (el Mini360, medido antes) al VIN del ESP32 y a las dos ULN2003; todas las
  tierras (GND) unidas. Ningún motor va a los pines 5V o 3V3 del ESP32.

  Actualización por Wi-Fi (desde carro-0.5): la app le manda la versión nueva por la red del robot
  (ver ota.h). Mientras llega, el robot queda quieto y no acepta manejo ni escritura.

  Otros mensajes (por la app o el Monitor Serie a 115200; todos piden la clave menos PING):
    SYNC                  la placa responde con su versión (VER:carro-0.7) y el estado actual
    OTA:<tamaño>:<md5>    recibe una versión nueva por Wi-Fi (ver ota.h)
    TEST                  la rueda izquierda y después la derecha dan un cuarto de vuelta hacia ADELANTE, y el
                          lápiz baja y sube: OK:PRUEBA <qué se mueve> por cada parte y al final
                          OK:PRUEBA terminada. Se cancela con «ERR:prueba cancelada: ...» si llega joystick,
                          acelerador o PARAR, otro TEST, o se desconecta el teléfono que la pidió.
    PINES                 muestra los pines y las medidas que está usando
    PING                  responde PONG
    MOTOR:I:32,33,25,26   cambia los pines de la rueda izquierda (IN1 a IN4 de su ULN2003); MOTOR:D:... la derecha
    LAPIZ:27,14           cambia los pines del lápiz (IN1 e IN2 del L298N)
    FABRICA               vuelve a los pines y medidas de fábrica (la clave no se borra)
  Los cambios se guardan en la placa. Los números se revisan (MOTOR:I:abc da ERR en vez de usar 0), los
  GPIO 1 y 3 (Monitor Serie), 6 a 11 (memoria) y 21, 22, 23 y 4 (las pantallas) no se aceptan, y una línea
  de más de 120 letras se descarta entera.

  Cambios de carro-0.7 (respecto de carro-0.6):
    - Sabe dónde está en la hoja (V31) contando los pasos, con el 0,0 que se pone desde la app (CERO).
    - La hoja (V32) hace de cerca: el joystick no saca el marcador del papel y ESCRIBIR revisa que el texto quepa.
    - IR y ALINEAR: va a un punto de la hoja y queda derecho para escribir.
    - La app puede ver la cara en vivo (CARA:1, V33 y V34). La cara tiene las letras que le faltaban
      (PARADO y RUEDA IZQ salían incompletos) y se anima aunque no haya pantallas.

  Cambios de carro-0.6 (respecto de carro-0.5):
    - Es el programa del robot que escribe: dos motores paso a paso en vez de cuatro motores con L298N,
      el lápiz, la escritura y un ojo en cada pantalla. Sin luces, bocina, torreta ni sensor de distancia.
    - Los pines guardados por carro-0.5 (los de cuatro ruedas) no sirven para el robot: arranca con los de
      fábrica. La clave se conserva.

  Placa: "ESP32 Dev Module" con Partition Scheme "Minimal SPIFFS (1.9MB APP with OTA)". Sin librerías extra.
    .\tool\compilar_firmware.ps1 -Placa carro
*/

#include <Arduino.h>
#include <Preferences.h>
#include <soc/gpio_struct.h>
#include "ota.h"
#include "cara.h"
#include "escritura.h"

// ============ CONFIGURACIÓN ============
#define FW_VERSION  "carro-0.7"
#define DEVICE_NAME "Carrito 4x4"              // la red y el Bluetooth de siempre: la app lo sigue encontrando
#define USE_WIFI    1                          // 1 = crear también la red Wi-Fi propia del robot
#if USE_WIFI
#include <WiFi.h>                              // aquí arriba: el IDE declara rawSend(WiFiClient&...) al principio
#include <lwip/sockets.h>
#endif
const char*    AP_PASS = "carrito4x4";         // mínimo 8 letras
const uint16_t TCP_PORT = 3333;
const uint32_t SIGNAL_TIMEOUT_MS = 1000;       // sin joystick ni acelerador del conductor este tiempo => se detiene
const uint32_t TCP_IDLE_MS = 6000;             // un teléfono por Wi-Fi que no manda nada este tiempo se desconecta
const uint16_t TEST_PAUSE_MS = 500;            // TEST: pausa entre una parte y la siguiente
const int32_t  TEST_STEPS = 1024;              // TEST: un cuarto de vuelta
const unsigned MAX_LINE = 120;                 // una línea más larga se descarta entera

// Motores paso a paso. Una interrupción cada STEP_TICK_US da los pasos, aunque loop() esté ocupado (la
// pantalla, el Wi-Fi): así el robot avanza parejo. Medio paso: 4096 por vuelta de la rueda (PASOS_VUELTA).
const uint32_t STEP_TICK_US = 100;             // 10 000 revisiones por segundo
const uint32_t TICK_HZ = 1000000 / STEP_TICK_US;
const int32_t  DRIVE_MAX_RATE = 800;           // medios pasos por segundo con el joystick a fondo (~12 vueltas por minuto)
const int32_t  DRIVE_RAMP = 20;                // cuánto puede cambiar la velocidad cada 5 ms (arranque suave)
const int32_t  WRITE_MAX_RATE = 600, WRITE_MIN_RATE = 150;   // escribiendo: más lento y parejo
const int32_t  WRITE_RAMP_STEPS = 120;         // pasos para llegar a la velocidad (y para frenar al final del trazo)
const uint32_t COILS_OFF_MS = 300;             // quieto este tiempo: las bobinas se apagan
const uint32_t POSE_REPORT_MS = 150;           // moviéndose, dice dónde está como mucho cada este tiempo
const uint32_t FACE_REPORT_MS = 80;            // la cara para la app, como mucho cada este tiempo

// Clave del robot (igual que la casa)
const uint8_t  MAX_FAILS = 3;
const uint32_t LOCK_MS = 30000;                // espera tras 3 claves incorrectas
const uint32_t RESET_HOLD_MS = 5000;           // BOOT presionado este tiempo borra la clave
const int      BOOT_PIN = 0;

enum : uint8_t { VPIN_JOY = 20, VPIN_THROTTLE = 24, VPIN_REVERSE = 25, VPIN_INVERT = 27,
                 VPIN_PEN = 28, VPIN_JOB = 29, VPIN_MEASURES = 30, VPIN_POSE = 31, VPIN_PAPER = 32,
                 VPIN_FACE = 33, VPIN_FACE_LABEL = 34 };

// De dónde llegó una línea. Cada conexión entrega la clave por su cuenta (igual que la casa).
enum Src : uint8_t { SRC_SERIAL, SRC_BLE, SRC_TCP, SRC_NONE };

// Un trabajo que mueve las ruedas solo (ver TRABAJOS). Aquí arriba: el IDE declara las funciones al principio.
enum Job : uint8_t { JOB_NONE, JOB_WRITE, JOB_GOTO };

// ============ AJUSTES GUARDADOS ============
struct Config {
  uint8_t  version;
  int8_t   motor[2][4];     // IN1..IN4 de cada ULN2003: 0 = rueda izquierda, 1 = derecha
  int8_t   pen[2];          // IN1 e IN2 del L298N
  uint8_t  invertMask;      // bit 0 = rueda izquierda, 1 = rueda derecha, 2 = lápiz
  uint16_t wheelMm, trackMm, letterMm, penMs;   // V30: rueda, eje, letra y lápiz
};
const uint8_t CONFIG_VERSION = 2;              // 1 = carro-0.5 (cuatro ruedas): no sirve, se usan los de fábrica
const Config DEFAULTS = {
  CONFIG_VERSION,
  { {32, 33, 25, 26}, {19, 18, 17, 16} },
  {27, 14},
  0b010,                    // los motores van en espejo: la rueda derecha gira al revés para ir adelante
  65, 120, 30, 1000,
};
Config cfg;
Preferences prefs;

const char* WHEEL_CODE[2] = {"I", "D"};
const char* WHEEL_NAME[2] = {"rueda izquierda", "rueda derecha"};

// ============ ESTADO ============
int joyX = 0, joyY = 0, throttle = 0;
bool reverseGear = false;
int32_t driveTarget[2] = {0, 0};     // medios pasos por segundo que piden el joystick y el acelerador
int32_t driveRate[2] = {0, 0};       // los que se están dando (se acercan a driveTarget de a poco)
uint32_t lastRx = 0;                 // última orden de joystick o acelerador del conductor (watchdog de señal)
String lastPrinted;

// Un solo conductor: solo el origen que está manejando puede mover el robot (parar puede cualquiera).
Src driver = SRC_NONE;
uint8_t waitNeutral = 0;     // orígenes (bit 1 << Src) que quisieron manejar mientras otro manejaba: deben soltar los controles antes de tomarlo
uint8_t warnedSrc = 0;       // a quién ya se le avisó que no puede manejar (un aviso, no uno cada 90 ms)

// Prueba (TEST), atendida desde loop() sin bloquear: 0 rueda izquierda, 1 derecha, 2 lápiz abajo, 3 arriba.
int8_t testPart = -1;        // -1 = sin prueba
bool testPaused = false;     // true = en la pausa después de una parte
uint32_t testUntil = 0;
Src testSrc = SRC_SERIAL;    // quién la pidió: si se desconecta, se cancela

bool testRunning() { return testPart >= 0; }

// Un trabajo que mueve las ruedas solo: escribir (ESCRIBIR) o ir a un punto de la hoja (IR, ALINEAR).
// Mientras dura, el joystick no lo mueve. Ver TRABAJOS.
Job job = JOB_NONE;
bool jobStepBusy = false;    // el paso actual (un trazo, un giro o el lápiz) todavía se está haciendo
Src jobSrc = SRC_NONE;       // quién lo pidió: si se desconecta, se detiene
Escritor writer;
Conversor wheels;
int writeLetter = 0, writeTotal = 0;
Paso gotoPlan[4];            // ir a un punto: subir el lápiz, girar, avanzar y alinearse
uint8_t gotoLen = 0, gotoAt = 0;

bool busy() { return job != JOB_NONE; }

// Clave del robot
volatile bool authed[3] = {true, false, false};   // el cable USB no necesita clave
String carKey;                                    // "" = el robot todavía no tiene clave
uint8_t failCount = 0;
uint32_t lockStart = 0;

// Seguro de manejo: después de conectarse, desconectarse o frenar por falta de señal, el robot
// no obedece movimientos hasta que el joystick (V20:0,0) y el acelerador (V24:0) lleguen en cero.
// Así no arranca solo si un teléfono reconecta con el acelerador puesto.
bool driveLocked = true, lockJoyNeutral = false, lockThrottleNeutral = false, lockWarned = false;

void lockDriving() {
  driveLocked = true;
  lockJoyNeutral = lockThrottleNeutral = lockWarned = false;
}

volatile bool bleConnected = false;

// Línea que se va juntando, una por origen (Serie, BLE, TCP).
struct LineIn { String buf; bool tooLong = false; };
LineIn lineIn[3];

void clearLine(Src s) { lineIn[s].buf = ""; lineIn[s].tooLong = false; }

void sendLine(const String& line);
void sendQuiet(const String& line);
void reply(Src src, const String& line);
void watchFace(Src src, bool on);
int parseList(const String& s, int* out, int maxN);

// ============ PINES ============
// Mismas reglas que la app, y además los GPIO 1 y 3 (el cable USB del Monitor Serie).
const char* gpioProblem(int gpio, bool output = true) {
  if (gpio < 0 || gpio > 39) return "el ESP32 tiene GPIO del 0 al 39";
  if (gpio == 1 || gpio == 3) return "los GPIO 1 y 3 los usa el Monitor Serie (cable USB)";
  if (gpio >= 6 && gpio <= 11) return "los GPIO 6 a 11 los usa la memoria de la placa";
  if (gpio == OLED_SDA || gpio == OLED_SCL || gpio == OLED2_SDA || gpio == OLED2_SCL)
    return "los GPIO 21, 22, 23 y 4 son de las pantallas de los ojos (SDA y SCL)";
  if (gpio == 20 || gpio == 24 || (gpio >= 28 && gpio <= 31)) return "ese GPIO no existe en el ESP32";
  if (output && gpio >= 34) return "los GPIO 34 a 39 solo sirven como entrada";
  return nullptr;
}

bool isInverted(int i) { return cfg.invertMask & (1 << i); }

void loadConfig() {
  prefs.begin("carro", true);
  size_t n = prefs.getBytes("cfg", &cfg, sizeof(cfg));
  prefs.end();
  if (n != sizeof(cfg) || cfg.version != CONFIG_VERSION) cfg = DEFAULTS;
}

void saveConfig() {
  prefs.begin("carro", false);
  prefs.putBytes("cfg", &cfg, sizeof(cfg));
  prefs.end();
}

// ¿Lo usa otra pieza? Devuelve su nombre, o "".
String pinOwner(int gpio) {
  for (int i = 0; i < 2; i++)
    for (int j = 0; j < 4; j++)
      if (cfg.motor[i][j] == gpio) return WHEEL_NAME[i];
  if (cfg.pen[0] == gpio || cfg.pen[1] == gpio) return "lapiz";
  return "";
}

bool pinInUse(int gpio) { return pinOwner(gpio).length() > 0; }

// Suelta un pin que deja de usarse sin dejarlo flotando: una entrada del ULN2003 o del L298N al aire puede
// mover un motor sola. Queda como salida en LOW; el GPIO 0 vuelve a ser el botón BOOT (en el DevKit ya tiene
// resistencia a 3,3 V; en LOW borraría la clave).
void releasePin(int gpio) {
  if (gpio < 0) return;
  if (gpio == BOOT_PIN) { pinMode(gpio, INPUT_PULLUP); return; }
  pinMode(gpio, OUTPUT);
  digitalWrite(gpio, LOW);
}

// ============ MOTORES PASO A PASO (28BYJ-48 con ULN2003) ============
// Medio paso: 8 combinaciones de las 4 bobinas por ciclo. Bit 0 = IN1. En DRAM: la interrupción la lee
// incluso mientras se escribe la memoria de programa (los ajustes, una versión nueva).
DRAM_ATTR const uint8_t HALF_STEP[8] = {0b0001, 0b0011, 0b0010, 0b0110, 0b0100, 0b1100, 0b1000, 0b1001};

struct Stepper {
  // Qué GPIO prender y cuáles apagar en cada fase, listos para la interrupción (GPIO 0-31 y 32-39).
  uint32_t onLo[8], offLo[8], onHi[8], offHi[8];
  uint32_t allLo, allHi;                 // las cuatro bobinas, para apagarlas
  volatile int32_t rate;                 // medios pasos por segundo; + = hacia adelante del robot
  volatile int32_t left;                 // pasos que faltan de un movimiento contado; -1 = sin límite (joystick)
  volatile int32_t pos;                  // pasos dados desde que arrancó, + = hacia adelante (para saber dónde está)
  volatile bool inverted, energized;
  uint32_t acc;
  uint8_t phase;
};
Stepper motor[2];
portMUX_TYPE stepMux = portMUX_INITIALIZER_UNLOCKED;
hw_timer_t* stepTimer = nullptr;
uint32_t idleSince[2] = {0, 0};          // desde cuándo está quieta cada rueda (para apagar sus bobinas)
int32_t moveTotal = 0;                   // pasos del movimiento contado más largo (para la rampa)

void IRAM_ATTR onStepTick() {
  portENTER_CRITICAL_ISR(&stepMux);
  for (int i = 0; i < 2; i++) {
    Stepper& m = motor[i];
    const int32_t r = m.rate;
    if (r == 0) continue;
    m.acc += r > 0 ? r : -r;
    if (m.acc < TICK_HZ) continue;
    m.acc -= TICK_HZ;
    m.phase = (m.phase + ((r > 0) != m.inverted ? 1 : 7)) & 7;
    GPIO.out_w1tc = m.offLo[m.phase];
    GPIO.out1_w1tc.val = m.offHi[m.phase];
    GPIO.out_w1ts = m.onLo[m.phase];
    GPIO.out1_w1ts.val = m.onHi[m.phase];
    m.energized = true;
    m.pos += r > 0 ? 1 : -1;
    if (m.left > 0 && --m.left == 0) { m.rate = 0; m.acc = 0; }
  }
  portEXIT_CRITICAL_ISR(&stepMux);
}

// Apaga las bobinas de la rueda [i]. Llamar con stepMux tomado. (Recibe el número y no la rueda: el IDE
// declara las funciones al principio del archivo, antes de que exista Stepper.)
void coilsOff(int i) {
  GPIO.out_w1tc = motor[i].allLo;
  GPIO.out1_w1tc.val = motor[i].allHi;
  motor[i].energized = false;
}

// Prepara los pines de una rueda: salidas en LOW y las máscaras de cada fase.
void setupWheel(int i) {
  Stepper& m = motor[i];
  for (int k = 0; k < 4; k++) { pinMode(cfg.motor[i][k], OUTPUT); digitalWrite(cfg.motor[i][k], LOW); }
  portENTER_CRITICAL(&stepMux);
  m.rate = 0; m.left = -1; m.acc = 0;
  m.allLo = m.allHi = 0;
  for (int ph = 0; ph < 8; ph++) {
    m.onLo[ph] = m.offLo[ph] = m.onHi[ph] = m.offHi[ph] = 0;
    for (int k = 0; k < 4; k++) {
      const int g = cfg.motor[i][k];
      const bool on = HALF_STEP[ph] & (1 << k);
      uint32_t& slot = g < 32 ? (on ? m.onLo[ph] : m.offLo[ph]) : (on ? m.onHi[ph] : m.offHi[ph]);
      slot |= 1UL << (g & 31);
      (g < 32 ? m.allLo : m.allHi) |= 1UL << (g & 31);
    }
  }
  m.inverted = isInverted(i);
  coilsOff(i);
  portEXIT_CRITICAL(&stepMux);
}

void setupSteppers() {
  stepTimer = timerBegin(0, 80, true);             // 80 MHz / 80 = una cuenta por µs
  timerAttachInterrupt(stepTimer, &onStepTick, true);
  timerAlarmWrite(stepTimer, STEP_TICK_US, true);
  timerAlarmEnable(stepTimer);
}

// Velocidad de una rueda: [count] pasos y se detiene sola, o -1 = sin límite (manejo).
void setMotor(int i, int32_t rate, int32_t count) {
  portENTER_CRITICAL(&stepMux);
  motor[i].left = count;
  motor[i].rate = count == 0 ? 0 : rate;
  portEXIT_CRITICAL(&stepMux);
}

// Un movimiento contado (un trazo, un giro o la prueba): pasos de cada rueda, + = adelante. Las dos van a la
// misma velocidad, así un giro en el lugar no corre el marcador. La rampa la lleva loopMotion().
void startMove(int32_t l, int32_t r) {
  moveTotal = max(abs(l), abs(r));
  setMotor(0, l > 0 ? WRITE_MIN_RATE : -WRITE_MIN_RATE, abs(l));
  setMotor(1, r > 0 ? WRITE_MIN_RATE : -WRITE_MIN_RATE, abs(r));
}

bool moveDone() { return motor[0].left <= 0 && motor[1].left <= 0; }

void haltWheels() {
  for (int i = 0; i < 2; i++) { driveTarget[i] = driveRate[i] = 0; setMotor(i, 0, -1); }
}

int deadzone(int v, int dz) { return abs(v) < dz ? 0 : v; }

// Joystick + acelerador => velocidad de cada rueda (gira como un tanque).
void computeTargets() {
  int y = deadzone(constrain(joyY, -100, 100), 10);
  int x = deadzone(constrain(joyX, -100, 100), 10);
  int th = deadzone(constrain(throttle, 0, 100), 5);

  int forward = abs(y) >= th ? y : (reverseGear ? -th : th);
  int left = forward + x, right = forward - x;
  int biggest = max(abs(left), abs(right));
  if (biggest > 100) { left = left * 100 / biggest; right = right * 100 / biggest; }

  driveTarget[0] = left * DRIVE_MAX_RATE / 100;
  driveTarget[1] = right * DRIVE_MAX_RATE / 100;

  String now = "Ruedas: izquierda " + String(left) + " % · derecha " + String(right) + " %";
  if (now != lastPrinted) { Serial.println(now); lastPrinted = now; caraDrive(left, right); }
}

bool moving() {
  for (int i = 0; i < 2; i++) if (driveTarget[i] || driveRate[i] || motor[i].rate) return true;
  return false;
}

// Detiene las ruedas al instante (sin rampa: a la velocidad de estos motores no hace falta). También termina
// la prueba, si estaba corriendo. Los trabajos (escribir, ir a un punto) los detiene stopJob().
void stopNow(const char* why) {
  bool was = moving();
  testPart = -1;
  joyX = joyY = throttle = 0;
  haltWheels();
  lastPrinted = "";
  caraDrive(0, 0);
  if (was && why) sendLine(String("ERR:") + why);
}

// Cancela la prueba (si está corriendo): ruedas quietas y un ERR que dice por qué.
void abortTest(const char* why) {
  if (!testRunning()) return;
  stopNow(nullptr);
  caraTest(-1);
  sendLine(String("ERR:prueba cancelada: ") + why);
}

// ============ POSICIÓN EN LA HOJA (X-Y) ============
// El robot sabe dónde está contando los pasos de cada rueda: cada medio paso es una fracción de milímetro.
// CERO pone el 0,0 donde está el marcador, mirando hacia +x (la esquina de abajo a la izquierda de la hoja,
// mirando a lo largo de ella). Si las ruedas patinan o alguien lo levanta, hay que poner el 0,0 otra vez.
double poseX = 0, poseY = 0, poseTh = 0;   // mm, mm y radianes (+ = hacia la izquierda)
bool originSet = false;                    // sin 0,0 no se sabe dónde está: no hay cerca ni IR
int32_t poseL = 0, poseR = 0;              // los pasos de cada rueda que ya se contaron
bool poseDirty = false;
uint32_t poseSentAt = 0;
uint16_t paperW = 0, paperH = 0;           // la hoja, en mm (0 = sin hoja: no hay cerca)
bool fenceWarned = false;                  // ya avisó que llegó al borde (una vez, hasta que se aleje)

bool paperSet() { return paperW > 0 && paperH > 0; }
bool fenceOn() { return originSet && paperSet(); }

double angleNorm(double a) {               // a (−π, π]
  while (a > PI) a -= 2 * PI;
  while (a <= -PI) a += 2 * PI;
  return a;
}

String poseString() {
  if (!originSet) return "-";
  return String(lround(poseX)) + "," + String(lround(poseY)) + "," + String(lround(poseTh * 180 / PI));
}

// Dónde está, para la app. Sin eco en el Monitor Serie: moviéndose sale varias veces por segundo.
void reportPose() {
  sendQuiet("V" + String(VPIN_POSE) + ":" + poseString());
  poseDirty = false;
  poseSentAt = millis();
}

void loadPaper() {
  prefs.begin("carro", true);
  paperW = prefs.getUShort("hojaW", 0);
  paperH = prefs.getUShort("hojaH", 0);
  prefs.end();
}

void reportPaper() { sendLine("V" + String(VPIN_PAPER) + ":" + String(paperW) + "," + String(paperH)); }

// CERO: el 0,0 es aquí, mirando hacia +x.
void setOrigin() {
  portENTER_CRITICAL(&stepMux);
  poseL = motor[0].pos;
  poseR = motor[1].pos;
  portEXIT_CRITICAL(&stepMux);
  poseX = poseY = poseTh = 0;
  originSet = true;
  fenceWarned = false;
  reportPose();
}

// Se perdió la cuenta (la prueba gira las ruedas en el aire): hay que poner el 0,0 otra vez.
void forgetOrigin() {
  if (!originSet) return;
  originSet = false;
  reportPose();
}

// Suma lo que avanzó cada rueda desde la última vez: un robot de dos ruedas que recorre un arco.
void loopPose(uint32_t now) {
  portENTER_CRITICAL(&stepMux);
  const int32_t l = motor[0].pos, r = motor[1].pos;
  portEXIT_CRITICAL(&stepMux);
  const int32_t dl = l - poseL, dr = r - poseR;
  if (dl || dr) {
    poseL = l;
    poseR = r;
    const double porMm = PASOS_VUELTA / (PI * cfg.wheelMm);
    const double sl = dl / porMm, sr = dr / porMm, ds = (sl + sr) / 2, dth = (sr - sl) / cfg.trackMm;
    poseX += ds * cos(poseTh + dth / 2);
    poseY += ds * sin(poseTh + dth / 2);
    poseTh = angleNorm(poseTh + dth);
    poseDirty = true;
  }
  if (poseDirty && originSet && now - poseSentAt >= POSE_REPORT_MS) reportPose();
}

// Cerca (con la hoja y el 0,0): si el marcador está en el borde y la orden lo sacaría de la hoja, se deja solo
// el giro en el lugar (el marcador, en el centro, no se mueve). Así se puede girar y volver a entrar.
void fence(int32_t& l, int32_t& r) {
  if (!fenceOn()) return;
  const int32_t twice = l + r;   // el doble de la velocidad hacia adelante
  if (twice == 0) return;
  const double dir = poseTh + (twice < 0 ? PI : 0), cx = cos(dir), cy = sin(dir);
  const bool out = (poseX <= 0 && cx < -.02) || (poseX >= paperW && cx > .02) || (poseY <= 0 && cy < -.02) ||
                   (poseY >= paperH && cy > .02);
  if (!out) { fenceWarned = false; return; }
  const int32_t v = twice / 2;
  l -= v;
  r -= v;
  if (!fenceWarned) { fenceWarned = true; sendLine("ERR:borde de la hoja: el robot no sale del papel"); }
}

// Cada 5 ms: la rampa de los movimientos contados (arranca y frena suave en cada trazo) o la del manejo.
// Y las ruedas que quedaron quietas apagan sus bobinas.
void loopMotion(uint32_t now) {
  static uint32_t last = 0;
  if (now - last < 5) return;
  last = now;
  if (busy() || testRunning()) {
    int32_t remaining = max((int32_t)motor[0].left, (int32_t)motor[1].left);
    if (remaining > 0) {
      int32_t edge = min(moveTotal - remaining, remaining);
      int32_t v = WRITE_MIN_RATE + (WRITE_MAX_RATE - WRITE_MIN_RATE) * min(edge, WRITE_RAMP_STEPS) / WRITE_RAMP_STEPS;
      portENTER_CRITICAL(&stepMux);
      for (Stepper& m : motor) if (m.left > 0) m.rate = m.rate > 0 ? v : -v;
      portEXIT_CRITICAL(&stepMux);
    }
  } else {
    for (int i = 0; i < 2; i++) driveRate[i] += constrain(driveTarget[i] - driveRate[i], -DRIVE_RAMP, DRIVE_RAMP);
    int32_t l = driveRate[0], r = driveRate[1];
    fence(l, r);
    if (motor[0].rate != l) setMotor(0, l, -1);
    if (motor[1].rate != r) setMotor(1, r, -1);
  }
  for (int i = 0; i < 2; i++) {
    if (motor[i].rate != 0) { idleSince[i] = now; continue; }
    if (!motor[i].energized || now - idleSince[i] < COILS_OFF_MS) continue;
    portENTER_CRITICAL(&stepMux);
    if (motor[i].rate == 0) coilsOff(i);
    portEXIT_CRITICAL(&stepMux);
  }
}

// ============ LÁPIZ (motor amarillo con el L298N) ============
// Sube o baja andando cfg.penMs y se detiene. No tiene sensor: la placa recuerda dónde quedó (también al
// apagarse), y si se le pide lo contrario a mitad de camino vuelve solo lo que ya anduvo.
bool penDown = false;        // dónde está, o hacia dónde va
int8_t penDir = 0;           // +1 bajando, -1 subiendo, 0 quieto
uint32_t penStart = 0, penFor = 0;

void writePen(int8_t dir) {
  if (isInverted(2)) dir = -dir;
  digitalWrite(cfg.pen[0], dir > 0 ? HIGH : LOW);
  digitalWrite(cfg.pen[1], dir < 0 ? HIGH : LOW);
}

void setupPen() {
  for (int k = 0; k < 2; k++) pinMode(cfg.pen[k], OUTPUT);
  writePen(0);
}

void reportPen() { sendLine("V" + String(VPIN_PEN) + ":" + String(penDown ? 1 : 0)); }

void loadPen() {
  prefs.begin("carro", true);
  penDown = prefs.getBool("lapiz", false);
  prefs.end();
}

void savePen() {
  prefs.begin("carro", false);
  if (prefs.getBool("lapiz", false) != penDown) prefs.putBool("lapiz", penDown);   // solo si cambió
  prefs.end();
}

void movePen(bool down) {
  if (down == penDown) return;
  uint32_t now = millis();
  penFor = penDir ? min(now - penStart, penFor) : cfg.penMs;
  penDown = down;
  penDir = down ? 1 : -1;
  penStart = now;
  writePen(penDir);
  reportPen();
  caraPen(down);
}

bool penBusy() { return penDir != 0; }

void loopPen(uint32_t now) {
  if (!penDir || now - penStart < penFor) return;
  penDir = 0;
  writePen(0);
  if (!busy()) savePen();    // escribiendo se guarda al final: cada trazo sería una escritura en la memoria
}

void setupAll() {
  for (int i = 0; i < 2; i++) setupWheel(i);
  setupPen();
}

void releaseAll() {
  haltWheels();
  for (int i = 0; i < 2; i++) for (int k = 0; k < 4; k++) releasePin(cfg.motor[i][k]);
  writePen(0);
  penDir = 0;
  for (int k = 0; k < 2; k++) releasePin(cfg.pen[k]);
}

// ============ TRABAJOS: ESCRIBIR O IR A UN PUNTO ============
void releaseDriver() { driver = SRC_NONE; warnedSrc = 0; }

// V29: la letra que escribe («3/5»), «ir» o «0».
String jobProgress() {
  if (job == JOB_WRITE) return String(writeLetter) + "/" + String(writeTotal);
  return job == JOB_GOTO ? String("ir") : String("0");
}
void reportJob() { sendLine("V" + String(VPIN_JOB) + ":" + jobProgress()); }

// Qué está haciendo, para los avisos: «el robot esta escribiendo».
const char* jobText() { return job == JOB_WRITE ? "el robot esta escribiendo" : "el robot va hacia un punto"; }

// Un trabajo nuevo: lo pide [src], que queda como conductor hasta que termina. false si no se puede empezar.
bool canStartJob(Src src) {
  if (busy()) { reply(src, String("ERR:") + jobText() + ": toca Parar primero"); return false; }
  if (driver != SRC_NONE && driver != src) { reply(src, "ERR:otro telefono esta manejando el carrito"); return false; }
  return true;
}

void beginJob(Src src, Job kind) {
  stopNow(nullptr);
  wheels.reiniciar();
  job = kind;
  jobStepBusy = false;
  jobSrc = driver = src;
  reportJob();
}

// ESCRIBIR:<texto>. Con la hoja y el 0,0, primero revisa que el texto quepa desde donde está el robot.
void startWriting(Src src, const String& text) {
  if (!canStartJob(src)) return;
  int n = writer.empezar(text.c_str(), cfg.letterMm, penDown);
  if (n == 0) { reply(src, "ERR:no hay letras para escribir: usa A-Z, N, 0-9 y . , ! ? - + :"); return; }
  if (fenceOn() && !cabeEnHoja(writer.caja(), poseX, poseY, poseTh, paperW, paperH)) {
    reply(src, "ERR:no cabe en la hoja: mueve el robot o achica las letras");
    return;
  }
  abortTest("llego un texto para escribir");
  writeLetter = 0;
  writeTotal = n;
  beginJob(src, JOB_WRITE);
  sendLine("OK:ESCRIBIENDO " + text);
}

// IR:x,y (y ALINEAR, que es ir a donde ya está): con el marcador arriba, hasta ese punto, mirando hacia +x.
void startGoto(Src src, double hx, double hy) {
  if (!canStartJob(src)) return;
  if (!originSet) { reply(src, "ERR:primero pon el robot en la esquina de la hoja y toca 0,0 (CERO)"); return; }
  if (paperSet() && (hx < -.5 || hy < -.5 || hx > paperW + .5 || hy > paperH + .5)) {
    reply(src, "ERR:ese punto queda fuera de la hoja");
    return;
  }
  abortTest("el robot va hacia un punto");
  gotoLen = gotoAt = 0;
  if (penDown) gotoPlan[gotoLen++] = {PASO_LAPIZ, 0};
  gotoLen += planIr(poseX, poseY, poseTh, hx, hy, gotoPlan + gotoLen);
  beginJob(src, JOB_GOTO);
  sendLine("OK:IR " + String(lround(hx)) + "," + String(lround(hy)));
}

void handleGoto(Src src, const String& arg) {   // 150,80
  int xy[2];
  if (parseList(arg, xy, 2) != 2) { reply(src, "ERR:usa IR:x,y en mm desde el 0,0, por ejemplo IR:150,80"); return; }
  startGoto(src, xy[0], xy[1]);
}

// Detiene el trabajo y sube el marcador. [why] = el motivo para el ERR, o nullptr si se pidió parar.
void stopJob(const char* why) {
  if (!busy()) return;
  const bool wasWriting = job == JOB_WRITE;
  job = JOB_NONE;
  jobStepBusy = false;
  haltWheels();
  movePen(false);
  reportJob();
  if (wasWriting) caraWrite(-1, 0);
  const char* what = wasWriting ? "escritura cancelada" : "camino cancelado";
  sendLine(why ? String("ERR:") + what + ": " + why : String("OK:") + what);
  releaseDriver();
}

bool nextJobStep(Paso& p) {
  if (job == JOB_WRITE) return writer.siguiente(p);
  if (gotoAt >= gotoLen) return false;
  p = gotoPlan[gotoAt++];
  return true;
}

void finishJob() {
  const bool wasWriting = job == JOB_WRITE;
  job = JOB_NONE;
  reportJob();
  savePen();
  if (wasWriting) caraWrite(0, writeTotal);
  sendLine(wasWriting ? "OK:ESCRITO" : "OK:LLEGO");
  releaseDriver();
}

// Paso a paso: espera a que termine el trazo, el giro o el lápiz, y pide el siguiente.
void loopJob() {
  if (!busy()) return;
  if (jobStepBusy) {
    if (!moveDone() || penBusy()) return;
    jobStepBusy = false;
  }
  Paso p;
  if (!nextJobStep(p)) { finishJob(); return; }
  switch (p.tipo) {
    case PASO_LETRA:
      writeLetter = (int)p.valor;
      reportJob();
      caraWrite(writeLetter, writeTotal);
      return;
    case PASO_LAPIZ:
      movePen(p.valor > .5f);
      jobStepBusy = true;
      return;
    case PASO_GIRO:
    case PASO_AVANCE: {
      int32_t l, r;
      wheels.pasos(p, Medidas{(float)cfg.wheelMm, (float)cfg.trackMm}, l, r);
      startMove(l, r);
      jobStepBusy = true;
      return;
    }
  }
}

// ============ CONDUCTOR ============
// Avisa una sola vez a un origen que su orden de manejo no se aplica.
void warnOnce(Src src, const char* text) {
  if (warnedSrc & (1 << src)) return;
  warnedSrc |= 1 << src;
  reply(src, text);
}

// Llegó joystick o acelerador. Parar vale desde cualquier origen; moverse, solo desde el conductor
// (el primero que se mueve cuando no hay otro). Solo el conductor renueva el watchdog de señal.
// Con un trabajo (escribir, ir a un punto), el joystick no cuenta (ni para parar: la app manda «quieto» al abrir
// el panel). Devuelve false si la orden se ignora.
bool acceptDrive(Src src, bool stop) {
  if (busy()) {
    if (!stop) warnOnce(src, (String("ERR:") + jobText() + ": toca Parar para manejar").c_str());
    return false;
  }
  abortTest(stop ? "llego una orden de parar" : "llego una orden de manejo");
  uint8_t bit = 1 << src;
  if (stop) {
    waitNeutral &= ~bit;
    warnedSrc &= ~bit;
    if (src == driver) lastRx = millis();
    return true;
  }
  if (driver != SRC_NONE && driver != src) {
    waitNeutral |= bit;
    warnOnce(src, "ERR:otro telefono esta manejando el carrito");
    return false;
  }
  if (waitNeutral & bit) {   // quiso manejar mientras otro manejaba: primero tiene que soltar los controles
    warnOnce(src, "ERR:suelta el joystick y el acelerador para volver a manejar");
    return false;
  }
  driver = src;
  lastRx = millis();
  return true;
}

// Un teléfono se conectó, se desconectó o perdió la clave: se olvida lo que mandó a medias y, si
// era el que manejaba (o nadie manejaba), el robot se detiene con el seguro puesto.
void sourceChanged(Src s) {
  clearLine(s);
  waitNeutral &= ~(1 << s);
  warnedSrc &= ~(1 << s);
  watchFace(s, false);
  if (busy() && s == jobSrc) stopJob("se desconecto el telefono que lo pidio");
  if (busy()) return;    // trabaja para otro teléfono: sigue
  if (testRunning()) {
    if (s == testSrc) abortTest("se desconecto el telefono que la pidio");
    return;
  }
  if (driver == s || driver == SRC_NONE) {
    stopNow(nullptr);
    lockDriving();
    releaseDriver();
  }
}

// Watchdog de señal: solo lo renuevan el joystick y el acelerador del conductor (no PING ni otras
// órdenes, así un teléfono en segundo plano que solo manda PING no deja el robot andando).
void loopSafety(uint32_t now) {
  if (busy() || testRunning() || now - lastRx <= SIGNAL_TIMEOUT_MS) return;   // los trabajos y la prueba no necesitan señal
  if (moving() || joyX || joyY || throttle) { stopNow("sin señal: el carrito se detuvo"); lockDriving(); }
  if (driver != SRC_NONE) releaseDriver();
}

// ============ CLAVE (igual que la casa) ============
void loadKey() {
  prefs.begin("carro", true);
  carKey = prefs.getString("clave", "");
  prefs.end();
}

// Un origen pierde la clave (el Monitor Serie nunca la pierde).
void deauth(Src s) {
  if (s == SRC_SERIAL || !authed[s]) return;
  authed[s] = false;
  sourceChanged(s);
}

// Guarda la clave nueva ("" = sin clave). Las otras conexiones tendrán que entregarla otra vez.
void storeKey(const String& key, Src keep) {
  carKey = key;
  prefs.begin("carro", false);
  prefs.putString("clave", key);
  prefs.end();
  for (int s = SRC_BLE; s <= SRC_TCP; s++) if (s != keep) deauth((Src)s);
}

bool validKey(const String& k) {
  if (k.length() < 4 || k.length() > 8) return false;
  for (size_t i = 0; i < k.length(); i++) if (!isDigit(k[i])) return false;
  return true;
}

// Segundos que faltan del bloqueo por intentos fallidos (0 = sin bloqueo).
uint32_t lockLeft(uint32_t now) {
  if (lockStart == 0) return 0;
  uint32_t elapsed = now - lockStart;
  if (elapsed >= LOCK_MS) { lockStart = 0; return 0; }
  return (LOCK_MS - elapsed + 999) / 1000;
}

// Respuesta de clave para un teléfono, y la cara reacciona (pide, acepta o rechaza).
void replyAuth(Src src, const String& answer, CaraKey face) {
  reply(src, answer);
  if (src != SRC_SERIAL) caraKey(face);
}

// AUTH:<clave>
void handleAuth(Src src, const String& given) {
  if (carKey.length() == 0) { replyAuth(src, "AUTH:NUEVA", CARA_KEY_ASK); return; }
  uint32_t wait = lockLeft(millis());
  if (wait) { replyAuth(src, "AUTH:ESPERA:" + String(wait), CARA_KEY_BAD); return; }
  if (given == carKey) {
    failCount = 0;
    authed[src] = true;
    replyAuth(src, "AUTH:OK", CARA_KEY_OK);
    return;
  }
  deauth(src);
  if (given.length() == 0) { replyAuth(src, "AUTH:PIDE", CARA_KEY_ASK); return; }   // la app aún no la conoce: no cuenta como intento
  if (++failCount >= MAX_FAILS) {
    failCount = 0;
    lockStart = millis() | 1;   // nunca 0, que significa «sin bloqueo»
    replyAuth(src, "AUTH:ESPERA:" + String(LOCK_MS / 1000), CARA_KEY_BAD);
  } else {
    replyAuth(src, "AUTH:MAL:" + String(MAX_FAILS - failCount), CARA_KEY_BAD);
  }
}

// CLAVE:<nueva>. Crear la primera no pide nada; cambiarla exige haber entregado la actual.
void handleNewKey(Src src, const String& key) {
  if (src == SRC_SERIAL && key.equalsIgnoreCase("BORRAR")) {
    storeKey("", SRC_SERIAL);
    reply(src, "OK:el robot quedo sin clave");
    return;
  }
  if (carKey.length() && !authed[src]) { reply(src, "AUTH:PIDE"); return; }
  if (!validKey(key)) { reply(src, "ERR:la clave debe tener de 4 a 8 numeros"); return; }
  storeKey(key, src);
  authed[src] = true;
  replyAuth(src, "AUTH:OK", CARA_KEY_OK);
  Serial.println("Clave del robot guardada");
}

// Mantener BOOT presionado 5 s borra la clave, por si se olvida y no hay computadora a mano.
// Los ojos lo muestran pidiendo la clave.
void loopResetButton(uint32_t now) {
  static uint32_t pressStart = 0;
  static bool done = false;
  if (pinInUse(BOOT_PIN)) { pressStart = 0; return; }   // el GPIO 0 se usa para otra cosa
  if (digitalRead(BOOT_PIN) == HIGH) { pressStart = 0; done = false; return; }
  if (pressStart == 0) pressStart = now | 1;
  if (done || now - pressStart < RESET_HOLD_MS) return;
  done = true;
  storeKey("", SRC_SERIAL);
  Serial.println("Clave borrada con el boton BOOT");
  caraKey(CARA_KEY_ASK);
}

// ============ MENSAJES ============
String invertString() {
  String s;
  for (int i = 0; i < 3; i++) s += isInverted(i) ? '1' : '0';
  return s;
}

String measuresString() {
  return String(cfg.wheelMm) + "," + String(cfg.trackMm) + "," + String(cfg.letterMm) + "," + String(cfg.penMs);
}

void sync() {
  sendLine("VER:" FW_VERSION);
  sendLine("V" + String(VPIN_REVERSE) + ":" + String(reverseGear ? 1 : 0));
  sendLine("V" + String(VPIN_THROTTLE) + ":" + String(throttle));
  sendLine("V" + String(VPIN_INVERT) + ":" + invertString());
  sendLine("V" + String(VPIN_MEASURES) + ":" + measuresString());
  reportPen();       // la app muestra el lápiz y la escritura porque la placa los dice
  reportJob();
  reportPaper();
  reportPose();
}

String pinList(const int8_t* pins, int n) {
  String s;
  for (int k = 0; k < n; k++) s += (k ? "," : "") + String((int)pins[k]);
  return s;
}

void showPins() {
  for (int i = 0; i < 2; i++)
    sendLine(String("OK:") + WHEEL_NAME[i] + " IN " + pinList(cfg.motor[i], 4) + (isInverted(i) ? " invertida" : ""));
  sendLine("OK:lapiz IN " + pinList(cfg.pen, 2) + (isInverted(2) ? " invertido" : ""));
  sendLine("OK:medidas rueda " + String(cfg.wheelMm) + " mm · eje " + String(cfg.trackMm) + " mm · letra " +
           String(cfg.letterMm) + " mm · lapiz " + String(cfg.penMs) + " ms");
}

// Prueba: cada parte se mueve sola y hay una pausa entre una y otra. La sigue loopTest() sin bloquear, así
// el loop sigue atendiendo PARAR, las conexiones y la clave.
const char* TEST_NAME[4] = {"rueda izquierda", "rueda derecha", "lapiz abajo", "lapiz arriba"};

void startTestPart(int k) {
  testPart = k;
  testPaused = false;
  caraTest(k);
  sendLine(String("OK:PRUEBA ") + TEST_NAME[k]);
  if (k == 0) startMove(TEST_STEPS, 0);
  else if (k == 1) startMove(0, TEST_STEPS);
  else movePen(k == 2);
}

void startTest(Src src) {
  if (busy()) { reply(src, String("ERR:") + jobText() + ": espera a que termine (o toca Parar)"); return; }
  if (testRunning()) { abortTest("se pidio TEST otra vez mientras corria"); return; }
  stopNow(nullptr);
  releaseDriver();
  forgetOrigin();   // las ruedas giran en el aire: la cuenta de dónde está deja de valer
  testSrc = src;
  sendLine("OK:PRUEBA cada rueda debe girar hacia ADELANTE y el lapiz bajar y subir");
  startTestPart(0);
}

void loopTest(uint32_t now) {
  if (!testRunning()) return;
  if (!testPaused) {                      // terminó de moverse: empieza la pausa
    if (!moveDone() || penBusy()) return;
    testPaused = true;
    testUntil = now + TEST_PAUSE_MS;
    return;
  }
  if ((int32_t)(now - testUntil) < 0) return;
  if (testPart < 3) { startTestPart(testPart + 1); return; }
  testPart = -1;
  caraTest(-1);
  sendLine("OK:PRUEBA terminada. Si una rueda giro hacia atras o el lapiz subio al bajar, activa Invertir");
}

// Número entero estricto: solo dígitos, con un «-» delante si hace falta. "abc", "" o "12x" no valen
// (toInt() los convertía en 0 o en 12 sin avisar).
bool parseIntStrict(String s, int& out) {
  s.trim();
  unsigned i = (s.length() && s[0] == '-') ? 1 : 0;
  if (s.length() == i || s.length() - i > 6) return false;   // vacío o demasiado largo
  long v = 0;
  for (unsigned k = i; k < s.length(); k++) {
    if (!isDigit(s[k])) return false;
    v = v * 10 + (s[k] - '0');
  }
  out = i ? -v : v;
  return true;
}

// Lista de números separados por coma. Devuelve cuántos leyó, o -1 si alguno no es número o sobran.
int parseList(const String& s, int* out, int maxN) {
  int n = 0, start = 0;
  while (true) {
    int comma = s.indexOf(',', start);
    String part = comma < 0 ? s.substring(start) : s.substring(start, comma);
    if (n >= maxN || !parseIntStrict(part, out[n])) return -1;
    n++;
    if (comma < 0) return n;
    start = comma + 1;
  }
}

// Revisa una lista de pines nuevos para una pieza. Devuelve el problema, o "" si están bien.
String checkPins(const int* pins, int n, const String& self) {
  for (int k = 0; k < n; k++) {
    const char* p = gpioProblem(pins[k]);
    if (p) return "GPIO " + String(pins[k]) + ": " + p;
    String owner = pinOwner(pins[k]);
    if (owner.length() && owner != self) return "el GPIO " + String(pins[k]) + " ya lo usa " + owner;
    for (int j = 0; j < k; j++) if (pins[j] == pins[k]) return "el GPIO " + String(pins[k]) + " esta repetido";
  }
  return "";
}

// Antes de cambiar pines: nada se mueve con los viejos.
void stopEverything(const char* why) {
  stopJob(why);
  abortTest(why ? why : "se pidio parar");
  stopNow(nullptr);
}

void handleMotorPins(const String& arg) {   // I:32,33,25,26
  int colon = arg.indexOf(':');
  String code = arg.substring(0, colon);
  code.toUpperCase();
  int w = code == WHEEL_CODE[0] ? 0 : (code == WHEEL_CODE[1] ? 1 : -1);
  int pins[4];
  if (w < 0 || colon < 0 || parseList(arg.substring(colon + 1), pins, 4) != 4) { sendLine("ERR:usa MOTOR:I:32,33,25,26 (o MOTOR:D:...)"); return; }
  String problem = checkPins(pins, 4, WHEEL_NAME[w]);
  if (problem.length()) { sendLine("ERR:" + problem); return; }
  stopEverything("cambiaron los pines de una rueda");
  for (int k = 0; k < 4; k++) releasePin(cfg.motor[w][k]);
  for (int k = 0; k < 4; k++) cfg.motor[w][k] = pins[k];
  setupWheel(w);
  saveConfig();
  sendLine(String("OK:") + WHEEL_NAME[w] + " IN " + pinList(cfg.motor[w], 4));
}

void handlePenPins(const String& arg) {     // 27,14
  int pins[2];
  if (parseList(arg, pins, 2) != 2) { sendLine("ERR:usa LAPIZ:27,14"); return; }
  String problem = checkPins(pins, 2, "lapiz");
  if (problem.length()) { sendLine("ERR:" + problem); return; }
  stopEverything("cambiaron los pines del lapiz");
  writePen(0);
  penDir = 0;
  for (int k = 0; k < 2; k++) releasePin(cfg.pen[k]);
  for (int k = 0; k < 2; k++) cfg.pen[k] = pins[k];
  setupPen();
  saveConfig();
  sendLine("OK:lapiz IN " + pinList(cfg.pen, 2));
}

void handleInvert(String v) {               // 010
  v.trim();
  uint8_t mask = 0;
  bool ok = v.length() == 3;
  for (unsigned i = 0; ok && i < 3; i++) {
    ok = v[i] == '0' || v[i] == '1';
    if (v[i] == '1') mask |= 1 << i;
  }
  if (!ok) { sendLine("ERR:V27 necesita tres 0/1 (rueda izquierda, rueda derecha, lapiz), por ejemplo 010"); return; }
  if (mask != cfg.invertMask) {   // solo se graba si cambió (cada escritura gasta la memoria de la placa)
    stopEverything("cambio el sentido de una rueda o del lapiz");
    cfg.invertMask = mask;
    for (int i = 0; i < 2; i++) motor[i].inverted = isInverted(i);
    saveConfig();
  }
  sendLine("V" + String(VPIN_INVERT) + ":" + invertString());
}

void handleMeasures(const String& v) {      // 65,120,30,1000
  int m[4];
  if (parseList(v, m, 4) != 4 || m[0] < 20 || m[0] > 150 || m[1] < 40 || m[1] > 400 || m[2] < 10 || m[2] > 200 ||
      m[3] < 100 || m[3] > 5000) {
    sendLine("ERR:V30 es rueda,eje,letra,lapiz en mm, mm, mm y ms: por ejemplo 65,120,30,1000");
    return;
  }
  if (busy()) {
    sendLine("ERR:espera a que el robot termine para cambiar las medidas");
  } else if (m[0] != cfg.wheelMm || m[1] != cfg.trackMm || m[2] != cfg.letterMm || m[3] != cfg.penMs) {
    cfg.wheelMm = m[0]; cfg.trackMm = m[1]; cfg.letterMm = m[2]; cfg.penMs = m[3];
    saveConfig();
  }
  sendLine("V" + String(VPIN_MEASURES) + ":" + measuresString());
}

void handlePaper(const String& v) {         // 279,216  o  0,0
  int wh[2];
  const bool none = parseList(v, wh, 2) == 2 && wh[0] == 0 && wh[1] == 0;
  if (!none && (parseList(v, wh, 2) != 2 || wh[0] < 50 || wh[0] > 2000 || wh[1] < 50 || wh[1] > 2000)) {
    sendLine("ERR:V32 es ancho,alto de la hoja en mm (de 50 a 2000), por ejemplo 279,216; o 0,0 para quitarla");
    return;
  }
  if (wh[0] != paperW || wh[1] != paperH) {
    paperW = wh[0];
    paperH = wh[1];
    fenceWarned = false;
    prefs.begin("carro", false);
    prefs.putUShort("hojaW", paperW);
    prefs.putUShort("hojaH", paperH);
    prefs.end();
  }
  reportPaper();
}

// Con el seguro puesto: anota si este control llegó en cero y quita el seguro cuando los dos lo hicieron.
// Devuelve true si la orden se puede aplicar.
bool unlockWith(bool neutral, bool& seen) {
  if (neutral) seen = true;
  if (lockJoyNeutral && lockThrottleNeutral) {
    driveLocked = false;
    return true;
  }
  if (!neutral && !lockWarned) {
    lockWarned = true;
    sendLine("ERR:suelta el joystick y el acelerador para volver a manejar");
  }
  return false;
}

// Con el seguro puesto solo cuenta lo que manda el conductor (o cualquiera, si nadie maneja).
// Mientras hay seguro el robot ya está detenido, así que ignorar el «parar» de otro no cambia nada.
bool lockedFor(Src src, bool neutral, bool& seen) {
  if (!driveLocked) return false;
  if (driver != SRC_NONE && driver != src) return true;
  return !unlockWith(neutral, seen);
}

// ============ ACTUALIZACIÓN POR WI-FI (ver ota.h) ============
const char* OTA_BUSY = "ERR:el carrito se esta actualizando; espera unos segundos";

// Contesta al teléfono y la cara muestra cómo va: 0 % al empezar, el avance, listo o no se pudo.
void otaReply(const String& answer) {
  reply(SRC_TCP, answer);
  if (answer == "OTA:LISTO") caraUpdate(0);
  else if (answer.startsWith("OTA:AVANCE:")) caraUpdate(answer.substring(11).toInt());
  else if (answer == "OTA:OK") caraUpdate(100);
  else if (answer.startsWith("OTA:ERR:")) caraUpdate(-1);
}

// OTA:<tamaño>:<md5>. Solo por Wi-Fi (por Bluetooth tardaría minutos), y el robot se detiene antes.
void handleOta(Src src, const String& arg) {
  if (src != SRC_TCP) { reply(src, "OTA:ERR:se actualiza por Wi-Fi"); return; }
  stopEverything("llego una version nueva");
  if (penBusy()) { writePen(0); penDir = 0; }   // el marcador queda donde está
  lockDriving();
  releaseDriver();
  otaReply(otaBegin(arg));
}

// Órdenes que mueven algo: mientras llega una versión nueva no se aceptan.
bool movesSomething(const String& up) {
  return up == "TEST" || up == "FABRICA" || up.startsWith("MOTOR:") || up.startsWith("LAPIZ:") ||
         up.startsWith("ESCRIBIR:") || up.startsWith("IR:") || up == "ALINEAR" || up.startsWith("V" + String(VPIN_JOY) + ":") ||
         up.startsWith("V" + String(VPIN_THROTTLE) + ":") || up.startsWith("V" + String(VPIN_PEN) + ":");
}

void handleLine(Src src, String line) {
  line.trim();
  if (!line.length()) return;
  String up = line;
  up.toUpperCase();

  if (up == "PING") { reply(src, "PONG"); return; }   // sin clave también; no cuenta como señal de manejo
  if (up.startsWith("AUTH:")) { handleAuth(src, line.substring(5)); return; }
  if (up.startsWith("CLAVE:")) { handleNewKey(src, line.substring(6)); return; }
  if (!authed[src]) { replyAuth(src, carKey.length() ? "AUTH:PIDE" : "AUTH:NUEVA", CARA_KEY_ASK); return; }
  caraWake();   // una orden de verdad (PING no cuenta): si la cara dormía, se despierta

  if (up == "SYNC") { sync(); return; }
  if (up.startsWith("OTA:")) { handleOta(src, line.substring(4)); return; }
  if (otaActive() && movesSomething(up)) { warnOnce(src, OTA_BUSY); return; }   // quieto mientras llega la versión nueva
  if (up == "PARAR") { stopEverything(nullptr); reply(src, "OK:PARADO"); return; }
  if (up.startsWith("ESCRIBIR:")) { startWriting(src, line.substring(9)); return; }
  if (up.startsWith("IR:")) { handleGoto(src, line.substring(3)); return; }
  if (up == "ALINEAR") { startGoto(src, poseX, poseY); return; }
  if (up == "CERO") {
    if (busy()) { reply(src, String("ERR:") + jobText() + ": espera a que termine (o toca Parar)"); return; }
    setOrigin();
    return;
  }
  if (up == "CARA:1" || up == "CARA:0") { watchFace(src, up == "CARA:1"); return; }
  if (up == "TEST") { startTest(src); return; }
  if (up == "PINES") { showPins(); return; }
  if (up == "FABRICA") {
    stopEverything("cambiaron los pines");
    releaseAll(); cfg = DEFAULTS; saveConfig(); setupAll();
    sendLine("OK:pines y medidas de fabrica"); showPins();
    sync();
    return;
  }
  if (up.startsWith("MOTOR:")) { handleMotorPins(line.substring(6)); return; }
  if (up.startsWith("LAPIZ:")) { handlePenPins(line.substring(6)); return; }

  int colon = line.indexOf(':');
  int vpin;
  if (up[0] != 'V' || colon < 2 || !parseIntStrict(line.substring(1, colon), vpin)) { sendLine("ERR:no entiendo " + line); return; }
  String v = line.substring(colon + 1);
  int n = 0;   // valor de los pines que llevan un solo número
  bool single = vpin == VPIN_THROTTLE || vpin == VPIN_REVERSE || vpin == VPIN_PEN;
  if (single && !parseIntStrict(v, n)) { sendLine("ERR:V" + String(vpin) + " necesita un numero"); return; }

  switch (vpin) {
    case VPIN_JOY: {
      int comma = v.indexOf(',');
      int x, y;
      if (comma < 0 || !parseIntStrict(v.substring(0, comma), x) || !parseIntStrict(v.substring(comma + 1), y)) {
        sendLine("ERR:V20 necesita x,y");
        return;
      }
      bool stop = x == 0 && y == 0;
      if (!acceptDrive(src, stop) || lockedFor(src, stop, lockJoyNeutral)) return;
      joyX = x;
      joyY = y;
      computeTargets();
      return;   // sin respuesta: llegan muchos por segundo
    }
    case VPIN_THROTTLE: {
      int t = constrain(n, 0, 100);
      if (!acceptDrive(src, t == 0) || lockedFor(src, t == 0, lockThrottleNeutral)) return;
      throttle = t;
      computeTargets();
      return;
    }
    case VPIN_REVERSE:
      if (driver != SRC_NONE && driver != src) {   // la reversa cambia el sentido del que maneja: solo él la toca
        warnOnce(src, "ERR:otro telefono esta manejando el carrito");
        reply(src, "V" + String(VPIN_REVERSE) + ":" + String(reverseGear ? 1 : 0));
        return;
      }
      reverseGear = n != 0; computeTargets(); sendLine("V" + String(VPIN_REVERSE) + ":" + String(reverseGear ? 1 : 0)); return;
    case VPIN_PEN:
      if (busy()) { reply(src, String("ERR:") + jobText() + ": el lapiz lo maneja el"); reportPen(); return; }
      if (driver != SRC_NONE && driver != src) { warnOnce(src, "ERR:otro telefono esta manejando el carrito"); reportPen(); return; }
      abortTest("se movio el lapiz");
      if ((n != 0) == penDown) reportPen();   // ya estaba así: igual se confirma
      movePen(n != 0);
      return;
    case VPIN_INVERT: handleInvert(v); return;
    case VPIN_MEASURES: handleMeasures(v); return;
    case VPIN_PAPER: handlePaper(v); return;
    default: sendLine("ERR:V" + String(vpin) + " no existe en el robot"); return;
  }
}

// Junta caracteres hasta completar una línea. Una línea de más de MAX_LINE letras se descarta entera
// (antes se cortaba y se ejecutaba el pedazo).
void feedChar(Src src, char k) {
  LineIn& in = lineIn[src];
  if (k == '\n' || k == '\r') {
    if (in.tooLong) { clearLine(src); reply(src, "ERR:linea demasiado larga (mas de 120 letras): se descarto"); return; }
    if (in.buf.length()) { String l = in.buf; in.buf = ""; handleLine(src, l); }
  } else if (in.tooLong) {
    // se ignora hasta el fin de la línea
  } else if (in.buf.length() >= MAX_LINE) {
    in.buf = "";
    in.tooLong = true;
  } else {
    in.buf += k;
  }
}

// ============ BLUETOOTH LE (servicio Nordic UART, igual que la casa) ============
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#define NUS_SERVICE "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
const size_t BLE_CHUNK = 20;
BLECharacteristic* txChar = nullptr;
QueueHandle_t bleRxQueue;             // bytes recibidos; el Bluetooth corre en otra tarea

// Marcas que el Bluetooth mete en la cola al conectarse o desconectarse un teléfono. loop() las lee
// en orden con los bytes, así lo que quedó del teléfono anterior (una línea a medias, un AUTH viejo)
// nunca se aplica al nuevo. Son bytes que la app no usa; si un teléfono los manda, se descartan.
const uint8_t BLE_MARK_ON = 0x01, BLE_MARK_OFF = 0x02;

void bleMark(uint8_t mark) {
  authed[SRC_BLE] = false;            // ya mismo: no enviarle nada al teléfono nuevo antes de su clave
  xQueueReset(bleRxQueue);            // bytes viejos fuera
  xQueueSend(bleRxQueue, &mark, 0);   // la cola quedó vacía: siempre cabe
}

class ServerCb : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleMark(BLE_MARK_ON); bleConnected = true; }
  void onDisconnect(BLEServer* s) override { bleConnected = false; bleMark(BLE_MARK_OFF); s->getAdvertising()->start(); }
};
class RxCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    const uint8_t* data = c->getData();
    for (size_t i = 0; i < c->getLength(); i++)
      if (data[i] != BLE_MARK_ON && data[i] != BLE_MARK_OFF) xQueueSend(bleRxQueue, &data[i], 0);
  }
};

void setupBle() {
  bleRxQueue = xQueueCreate(512, sizeof(uint8_t));
  BLEDevice::init(DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCb());
  BLEService* svc = server->createService(NUS_SERVICE);
  txChar = svc->createCharacteristic(NUS_TX, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());
  BLECharacteristic* rx = svc->createCharacteristic(NUS_RX, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCb());
  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(NUS_SERVICE);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("Bluetooth listo: busca \"" DEVICE_NAME "\" en la app");
}

void loopBle() {
  uint8_t k;
  while (xQueueReceive(bleRxQueue, &k, 0) == pdTRUE) {
    if (k == BLE_MARK_ON || k == BLE_MARK_OFF) {
      authed[SRC_BLE] = false;   // otra vez, en orden: un AUTH viejo procesado recién no autentica al nuevo
      sourceChanged(SRC_BLE);
      showLinks();
      Serial.println(k == BLE_MARK_ON ? "Bluetooth conectado" : "Bluetooth desconectado");
    } else {
      feedChar(SRC_BLE, (char)k);
    }
  }
}

void bleSend(const String& out) {
  if (!bleConnected || !txChar) return;
  const uint8_t* data = (const uint8_t*)out.c_str();
  for (size_t i = 0; i < out.length(); i += BLE_CHUNK) {
    size_t len = min(BLE_CHUNK, (size_t)out.length() - i);
    txChar->setValue((uint8_t*)(data + i), len);
    txChar->notify();
    delay(6);
  }
}

// ============ WI-FI (red propia, TCP) ============
#if USE_WIFI
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;
bool tcpWasConnected = false;
uint32_t tcpLastRx = 0;               // último byte recibido del teléfono por Wi-Fi

// Escribe sin esperar. WiFiClient::print puede trabar el loop hasta 10 s si el teléfono no recibe
// (salió de alcance) y se llenó lo pendiente; aquí, si no cabe, se corta esa conexión.
bool rawSend(WiFiClient& c, const String& text) {
  int fd = c.fd();
  if (fd < 0 || !c.connected()) return false;
  int sent = lwip_send(fd, text.c_str(), text.length(), MSG_DONTWAIT);
  if (sent == (int)text.length()) return true;
  Serial.println("Wi-Fi: el telefono no recibe; se corta la conexion");
  c.stop();
  return false;
}

void setupWifi() {
  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(DEVICE_NAME, AP_PASS)) { Serial.println("No se pudo crear la red Wi-Fi"); return; }
  tcpServer.begin();
  tcpServer.setNoDelay(true);
  Serial.println("Wi-Fi propio listo: red \"" DEVICE_NAME "\", IP " + WiFi.softAPIP().toString() + ", puerto " + String(TCP_PORT));
}

// Recibe la versión nueva (ver ota.h). Como mucho unos 4 KB por vuelta: el loop sigue atendiendo lo demás.
void loopOtaRx() {
  static uint8_t buf[1436];
  for (int k = 0; k < 3 && otaActive() && tcpClient.connected(); k++) {
    size_t want = min(min((size_t)tcpClient.available(), sizeof(buf)), otaWant());
    if (want == 0) return;
    int got = tcpClient.read(buf, want);
    if (got <= 0) return;
    tcpLastRx = millis();
    String answer = otaReceive(buf, got);
    if (answer.length()) otaReply(answer);
  }
}

void loopWifi(uint32_t now) {
  bool active = tcpClient.connected();
  if (active && now - tcpLastRx > TCP_IDLE_MS) {   // conexión medio abierta: el teléfono no da señales
    tcpClient.stop();
    active = false;
    Serial.println("Wi-Fi: el telefono no da senales hace 6 s; se corta la conexion");
  }
  if (tcpServer.hasClient()) {
    WiFiClient incoming = tcpServer.accept();
    if (active && authed[SRC_TCP]) {   // no se expulsa a un teléfono con clave que sigue activo
      while (incoming.available()) incoming.read();   // si quedan datos sin leer, el cierre borraría el aviso
      rawSend(incoming, "ERR:ya hay otro telefono conectado por Wi-Fi\n");
      incoming.stop();
      Serial.println("Wi-Fi: se rechazo otro telefono (ya hay uno conectado)");
    } else {
      if (active) tcpClient.stop();   // el anterior todavía no entregaba la clave: se reemplaza
      tcpClient = incoming;
      tcpClient.setNoDelay(true);
      tcpLastRx = now;
      tcpWasConnected = true;
      authed[SRC_TCP] = false;   // cada teléfono que se conecta entrega la clave de nuevo
      sourceChanged(SRC_TCP);
      showLinks();
      Serial.println("Wi-Fi: telefono conectado");
      reply(SRC_TCP, "HELLO:" DEVICE_NAME);
    }
  }
  if (tcpWasConnected && !tcpClient.connected()) {
    tcpWasConnected = false;
    authed[SRC_TCP] = false;
    if (otaActive()) { otaAbort(); caraUpdate(-1); }   // lo recibido a medias se descarta
    sourceChanged(SRC_TCP);
    showLinks();
    Serial.println("Wi-Fi desconectado");
  }
  if (otaActive()) { loopOtaRx(); return; }
  // Como mucho 512 bytes por vuelta, para que un teléfono que manda sin parar no trabe el loop.
  // Después de OTA:LISTO llega el programa, no texto: se deja de leer letras en ese momento.
  for (int n = 0; n < 512 && !otaActive() && tcpClient.connected() && tcpClient.available(); n++) {
    tcpLastRx = millis();
    feedChar(SRC_TCP, (char)tcpClient.read());
  }
}
#endif

// La cara muestra qué teléfonos están conectados (con la clave o todavía sin ella).
void showLinks() {
#if USE_WIFI
  caraLink(bleConnected, tcpWasConnected);
#else
  caraLink(bleConnected, false);
#endif
}

// Respuesta solo para quien preguntó (por ejemplo, el resultado de la clave).
void reply(Src src, const String& line) {
  Serial.println("-> " + line);
  if (src == SRC_BLE) bleSend(line + "\n");
#if USE_WIFI
  if (src == SRC_TCP && tcpClient.connected()) rawSend(tcpClient, line + "\n");
#endif
}

// Aviso para cada teléfono que ya entregó la clave, sin eco en el Monitor Serie (lo que sale muy seguido).
void sendQuiet(const String& line) {
  if (authed[SRC_BLE]) bleSend(line + "\n");
#if USE_WIFI
  if (authed[SRC_TCP] && tcpClient.connected()) rawSend(tcpClient, line + "\n");
#endif
}

// Aviso para todos: el Monitor Serie y cada teléfono que ya entregó la clave.
void sendLine(const String& line) {
  Serial.println("-> " + line);
  sendQuiet(line);
}

// ============ LA CARA EN LA APP ============
// La app pide verla con CARA:1 y deja de verla con CARA:0 (o al desconectarse). Mientras tanto le llegan los
// cambios de la cara (V33) y de su mensaje (V34), sin eco en el Monitor Serie (salen varias veces por segundo).
uint8_t faceWatch = 0;       // quién la mira: bit 1 << Src
String faceSent, labelSent;
uint32_t faceSentAt = 0;

void faceSend(const String& line) {
  const String out = line + "\n";
  if ((faceWatch & (1 << SRC_BLE)) && authed[SRC_BLE]) bleSend(out);
#if USE_WIFI
  if ((faceWatch & (1 << SRC_TCP)) && authed[SRC_TCP] && tcpClient.connected()) rawSend(tcpClient, out);
#endif
  if (faceWatch & (1 << SRC_SERIAL)) Serial.println(line);
}

void watchFace(Src src, bool on) {
  const uint8_t bit = 1 << src;
  if (on == ((faceWatch & bit) != 0)) return;
  faceWatch = on ? faceWatch | bit : faceWatch & ~bit;
  faceSent = labelSent = "";   // quien empieza a mirar recibe todo de nuevo
  faceSentAt = 0;
}

void loopFace(uint32_t now) {
  if (!faceWatch || now - faceSentAt < FACE_REPORT_MS) return;
  faceSentAt = now;
  const String label = caraLabel();
  if (label != labelSent) { labelSent = label; faceSend("V" + String(VPIN_FACE_LABEL) + ":" + label); }
  const String state = caraState();
  if (state != faceSent) { faceSent = state; faceSend("V" + String(VPIN_FACE) + ":" + state); }
}

// ============ PROGRAMA PRINCIPAL ============
void setup() {
  loadConfig();
  setupAll();            // ruedas quietas y lápiz detenido lo antes posible
  loadPen();
  loadPaper();
  if (!pinInUse(BOOT_PIN)) pinMode(BOOT_PIN, INPUT_PULLUP);   // botón BOOT: 5 s presionado borra la clave
  loadKey();

  Serial.begin(115200);
  delay(200);
  Serial.println("\n== Auto Robot (" FW_VERSION ") ==");
  caraBegin();           // antes que el Bluetooth: el logo aparece enseguida
  setupSteppers();
  setupBle();
#if USE_WIFI
  setupWifi();
#endif
  showPins();
  Serial.println(penDown ? "El lapiz quedo abajo la ultima vez." : "El lapiz esta arriba.");
  Serial.println(carKey.length() ? "El robot tiene clave." : "El robot no tiene clave: el primer telefono que se conecte la crea.");
  Serial.println("Escribe mensajes aqui mismo para probar, por ejemplo: V20:0,60 (adelante), TEST o ESCRIBIR:HOLA");
  enableLoopWDT();       // si loop() se traba más de 5 s, la placa se reinicia (las ruedas quedan quietas)
}

void loop() {
  while (Serial.available()) feedChar(SRC_SERIAL, Serial.read());
  loopBle();
#if USE_WIFI
  loopWifi(millis());
#endif
  uint32_t now = millis();   // después de leer: lastRx nunca queda «en el futuro»
  loopSafety(now);
  loopTest(now);
  loopJob();
  loopMotion(now);
  loopPose(now);
  loopPen(now);
  loopResetButton(now);
  String otaNews = otaLoop(now);
  if (otaNews.length()) otaReply(otaNews);
  caraLoop(now);
  loopFace(now);
}
