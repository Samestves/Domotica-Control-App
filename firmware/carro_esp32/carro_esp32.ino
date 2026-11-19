/*
  Carrito 4x4 · programa para el ESP32 del carrito · versión carro-0.4
  --------------------------------------------------------------------
  Cuatro motores TT con dos puentes H L298N. Se maneja desde la misma app de la casa
  (panel «Auto Robot») por Bluetooth LE o por Wi-Fi. Gira como un tanque: para doblar,
  las ruedas de un lado van más lento o hacia atrás.

  Wi-Fi propio: el ESP32 crea la red «Carrito 4x4» (contraseña: carrito4x4).
  La app se une a esa red y se conecta a la IP 192.168.4.1, puerto 3333.
  Bluetooth y Wi-Fi funcionan a la vez: un teléfono por cada uno. Por Wi-Fi, si ya hay un teléfono
  con clave conectado, otro que llegue recibe «ERR:ya hay otro telefono conectado por Wi-Fi» y se
  corta (salvo que el primero lleve 6 s mudo). Un teléfono por Wi-Fi que pasa 6 s sin mandar nada
  se desconecta (la app manda PING cada 3 s).

  Pines virtuales (los mismos del panel del carrito en la app):
    V20  joystick «x,y», cada uno de -100 a 100 (y positivo = adelante, x positivo = derecha)
    V21  torreta (servo, opcional): 0..359
    V22  distancia al obstáculo en cm (de la placa a la app; solo con sensor HC-SR04)
    V23  luces: 1 / 0
    V24  acelerador: 0..100 (velocidad fija hacia adelante, o hacia atrás con la reversa)
    V25  reversa: 1 / 0 (cambia el sentido del acelerador; el joystick no se ve afectado)
    V26  bocina: 1 = pitar un momento
    V27  invertir ruedas: cuatro 0/1 en orden DI, TI, DD, TD. Ej.: V27:0100 invierte la trasera izquierda

  Clave del carrito (de 4 a 8 números; el mismo protocolo que la casa). Por Bluetooth y Wi-Fi el
  carrito no obedece hasta recibirla, y cada conexión la entrega por su cuenta:
    AUTH:123456     la app entrega la clave. Respuestas:
                      AUTH:OK          correcta
                      AUTH:MAL:2       incorrecta; quedan 2 intentos
                      AUTH:ESPERA:30   demasiados intentos; hay que esperar 30 s
                      AUTH:NUEVA       el carrito todavía no tiene clave: hay que crearla
                      AUTH:PIDE        falta la clave (se envió una orden sin entregarla)
    CLAVE:123456    crea la clave, o la cambia si ya se entregó la actual. Responde AUTH:OK.
    Sin clave solo se contesta PING; cualquier otra orden responde AUTH:PIDE (o AUTH:NUEVA).
    El Monitor Serie (cable USB) no necesita clave. Ahí, CLAVE:BORRAR deja el carrito sin clave.
    Sin computadora: mantener presionado BOOT 5 s con la placa encendida también la borra
    (las luces parpadean 3 veces para confirmarlo).

  Seguridad:
    - Un solo conductor: el primero (Bluetooth, Wi-Fi o Monitor Serie) que manda joystick o acelerador
      distinto de cero maneja; a los demás se les responde «ERR:otro telefono esta manejando el carrito».
      Deja de ser el conductor si se desconecta o pasa 1 segundo sin mandar joystick ni acelerador.
      Parar (V24:0, V20:0,0, el freno de la app) vale desde cualquiera.
    - Si se corta el Bluetooth o el Wi-Fi del que maneja, los motores se detienen al instante.
    - Si el conductor deja de enviar joystick o acelerador por 1 segundo mientras el carrito anda,
      se detiene solo. PING y las demás órdenes no cuentan como señal.
      (La app 0.7.2 o más nueva repite la orden mientras mantienes el joystick.)
    - Seguro de manejo: después de conectarse, desconectarse o frenar por falta de señal, no obedece
      movimientos hasta que el joystick (V20:0,0) y el acelerador (V24:0) lleguen en cero.
    - Arranque suave: los motores no saltan de golpe a toda velocidad.
    - Con sensor de distancia: no avanza si hay un obstáculo a menos de 15 cm (sí puede girar o retroceder)
      y, si aparece uno mientras avanza, frena al instante. Si el sensor deja de contestar avisa con un
      ERR (y con un OK cuando vuelve).
    - Si el programa se traba más de 5 s, la placa se reinicia sola (watchdog) y los motores quedan quietos.

  Ruedas: DI delantera izquierda · TI trasera izquierda · DD delantera derecha · TD trasera derecha
  Pines de fábrica (los de la guía de armado):
            L298N   velocidad (EN)  sentido (IN)   sentido (IN)
    DI      A       32              33             25
    TI      A       26              27             14
    DD      B       13               4             16
    TD      B       17              18             19
    Luces 23 · Bocina 5 · Torreta y sensor: sin conectar

  Otros mensajes (por la app o el Monitor Serie a 115200; todos piden la clave menos PING):
    SYNC                  la placa responde con el estado actual
    TEST                  mueve cada rueda hacia adelante, una por una, para ver cuál es cuál:
                          OK:PRUEBA rueda <nombre> por cada una y al final OK:PRUEBA terminada.
                          Se cancela con «ERR:prueba cancelada: ...» si llega joystick, acelerador o freno,
                          otro TEST, o se desconecta el teléfono que la pidió.
    PINES                 muestra los pines que está usando
    PING                  responde PONG
    RUEDA:DI:32,33,25     cambia los pines de una rueda (EN, IN1, IN2)
    CFG:V23:23:0:1        luces en el GPIO 23, sin invertir (0), activadas (1). Igual V26 (bocina) y V21 (torreta)
    SENSOR:21,34          sensor HC-SR04: TRIG en 21 y ECHO en 34 (¡ECHO con divisor de voltaje a 3,3 V!)
    SENSOR:NO             quita el sensor
    MINIMO:35             potencia mínima (%) con la que las ruedas empiezan a girar
    FABRICA               vuelve a los pines de fábrica (la clave no se borra)
  Los cambios se guardan en la placa. Los números se revisan (CFG:V23:abc da ERR en vez de usar 0),
  los GPIO 1 y 3 (Monitor Serie) y 6 a 11 (memoria) no se aceptan, y una línea de más de 120 letras
  se descarta entera.

  Placa: "ESP32 Dev Module" con Partition Scheme "Huge APP". Sin librerías extra.
*/

#include <Arduino.h>
#include <Preferences.h>

// ============ CONFIGURACIÓN ============
#define FW_VERSION  "carro-0.4"
#define DEVICE_NAME "Carrito 4x4"
#define USE_WIFI    1                      // 1 = crear también la red Wi-Fi propia del carrito
#if USE_WIFI
#include <WiFi.h>                          // aquí arriba: el IDE declara rawSend(WiFiClient&...) al principio
#include <lwip/sockets.h>
#endif
const char*    AP_PASS = "carrito4x4";     // mínimo 8 letras
const uint16_t TCP_PORT = 3333;
const uint32_t SIGNAL_TIMEOUT_MS = 1000;   // sin joystick ni acelerador del conductor este tiempo => se detiene
const uint32_t TCP_IDLE_MS = 6000;         // un teléfono por Wi-Fi que no manda nada este tiempo se desconecta
const uint8_t  RAMP_STEP = 12;             // cuánto cambia la potencia cada 10 ms (arranque suave)
const int      STOP_CM = 15;               // con sensor: no avanza si hay algo más cerca
const uint8_t  SENSOR_FAILS = 10;          // lecturas seguidas sin respuesta => avisa que el sensor no responde
const uint16_t HORN_MS = 350;
const uint32_t MOTOR_FREQ = 1000;          // Hz del PWM de los motores (el L298N es lento)
const uint16_t TEST_SPIN_MS = 1200, TEST_PAUSE_MS = 500;   // TEST: cuánto gira cada rueda y la pausa entre ruedas
const unsigned MAX_LINE = 120;             // una línea más larga se descarta entera

// Clave del carrito (igual que la casa)
const uint8_t  MAX_FAILS = 3;
const uint32_t LOCK_MS = 30000;            // espera tras 3 claves incorrectas
const uint32_t RESET_HOLD_MS = 5000;       // BOOT presionado este tiempo borra la clave
const int      BOOT_PIN = 0;

enum : uint8_t { VPIN_JOY = 20, VPIN_TURRET = 21, VPIN_DIST = 22, VPIN_LIGHTS = 23,
                 VPIN_THROTTLE = 24, VPIN_REVERSE = 25, VPIN_HORN = 26, VPIN_INVERT = 27 };

// De dónde llegó una línea. Cada conexión entrega la clave por su cuenta (igual que la casa).
enum Src : uint8_t { SRC_SERIAL, SRC_BLE, SRC_TCP, SRC_NONE };

// ============ AJUSTES GUARDADOS ============
struct Config {
  uint8_t version;
  int8_t  wheel[4][3];      // EN, IN1, IN2
  uint8_t invertMask;       // bit 0 = DI, 1 = TI, 2 = DD, 3 = TD
  int8_t  lights, horn, turret, trig, echo;   // -1 = sin conectar
  uint8_t lightsInv, hornInv, turretInv;
  uint8_t minPower;         // % con el que la rueda empieza a moverse
};
const uint8_t CONFIG_VERSION = 1;
const Config DEFAULTS = {
  CONFIG_VERSION,
  { {32, 33, 25}, {26, 27, 14}, {13, 4, 16}, {17, 18, 19} },
  0,
  23, 5, -1, -1, -1,
  0, 0, 0,
  35,
};
Config cfg;
Preferences prefs;

const char* WHEEL_CODE[4] = {"DI", "TI", "DD", "TD"};
const char* WHEEL_NAME[4] = {"delantera izquierda", "trasera izquierda", "delantera derecha", "trasera derecha"};

// ============ ESTADO ============
int joyX = 0, joyY = 0, throttle = 0, turretAngle = 0;
bool reverseGear = false, lightsOn = false;
int16_t target[4] = {0, 0, 0, 0};    // -255..255
int16_t current[4] = {0, 0, 0, 0};
int distanceCm = -1;
uint32_t lastRx = 0;                 // última orden de joystick o acelerador del conductor (watchdog de señal)
uint32_t lastRamp = 0, hornUntil = 0, lastSensor = 0, lastDistReport = 0;
int lastDistSent = -100;
bool lastObstacle = false;
uint8_t sensorFails = 0;             // lecturas seguidas en que el sensor no contestó
bool turretWarned = false;   // el aviso de «sin torreta» se da una vez por conexión

// Un solo conductor: solo el origen que está manejando puede mover el carrito (parar puede cualquiera).
Src driver = SRC_NONE;
uint8_t waitNeutral = 0;     // orígenes (bit 1 << Src) que quisieron manejar mientras otro manejaba: deben soltar los controles antes de tomarlo
uint8_t warnedSrc = 0;       // a quién ya se le avisó que no puede manejar (un aviso, no uno cada 90 ms)

// Prueba de ruedas (TEST), atendida desde loop() sin bloquear.
int8_t testWheel = -1;       // rueda que está en prueba (-1 = sin prueba)
bool testPaused = false;     // true = en la pausa después de girar
uint32_t testUntil = 0;
Src testSrc = SRC_SERIAL;    // quién la pidió: si se desconecta, se cancela

bool testRunning() { return testWheel >= 0; }

// Clave del carrito
volatile bool authed[3] = {true, false, false};   // el cable USB no necesita clave
String carKey;                                    // "" = el carrito todavía no tiene clave
uint8_t failCount = 0;
uint32_t lockStart = 0;

// Seguro de manejo: después de conectarse, desconectarse o frenar por falta de señal, el carrito
// no obedece movimientos hasta que el joystick (V20:0,0) y el acelerador (V24:0) lleguen en cero.
// Así no arranca solo si un teléfono reconecta con el acelerador puesto.
bool driveLocked = true, lockJoyNeutral = false, lockThrottleNeutral = false, lockWarned = false;

void lockDriving() {
  driveLocked = true;
  lockJoyNeutral = lockThrottleNeutral = lockWarned = false;
}
String lastPrinted;

volatile bool bleConnected = false;

// Línea que se va juntando, una por origen (Serie, BLE, TCP).
struct LineIn { String buf; bool tooLong = false; };
LineIn lineIn[3];

void clearLine(Src s) { lineIn[s].buf = ""; lineIn[s].tooLong = false; }

void sendLine(const String& line);
void reply(Src src, const String& line);

// ============ PINES ============
// Mismas reglas que la app, y además los GPIO 1 y 3 (el cable USB del Monitor Serie).
const char* gpioProblem(int gpio, bool output = true) {
  if (gpio < 0 || gpio > 39) return "el ESP32 tiene GPIO del 0 al 39";
  if (gpio == 1 || gpio == 3) return "los GPIO 1 y 3 los usa el Monitor Serie (cable USB)";
  if (gpio >= 6 && gpio <= 11) return "los GPIO 6 a 11 los usa la memoria de la placa";
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

// ¿Lo usa otra pieza? Devuelve su nombre, o nullptr.
String pinOwner(int gpio) {
  for (int i = 0; i < 4; i++)
    for (int j = 0; j < 3; j++)
      if (cfg.wheel[i][j] == gpio) return String("rueda ") + WHEEL_CODE[i];
  if (cfg.lights == gpio) return "luces";
  if (cfg.horn == gpio) return "bocina";
  if (cfg.turret == gpio) return "torreta";
  if (cfg.trig == gpio) return "TRIG del sensor";
  if (cfg.echo == gpio) return "ECHO del sensor";
  return "";
}

// Igual que pinOwner, pero sin armar textos (se llama en cada vuelta del loop).
bool pinInUse(int gpio) {
  for (int i = 0; i < 4; i++)
    for (int j = 0; j < 3; j++)
      if (cfg.wheel[i][j] == gpio) return true;
  return cfg.lights == gpio || cfg.horn == gpio || cfg.turret == gpio || cfg.trig == gpio || cfg.echo == gpio;
}

// Suelta un pin que deja de usarse sin dejarlo flotando: una entrada del L298N al aire puede mover
// un motor sola. Queda como salida en su nivel «apagado» (LOW; HIGH para luces o bocina invertidas).
// ECHO y los GPIO 34-39 quedan como entrada (no deben o no pueden ser salida), y el GPIO 0 vuelve
// a ser el botón BOOT (en el DevKit ya tiene resistencia a 3,3 V; en LOW borraría la clave).
void releasePin(int gpio, bool offLevel, bool input) {
  if (gpio < 0) return;
  ledcDetachPin(gpio);
  if (gpio == BOOT_PIN) { pinMode(gpio, INPUT_PULLUP); return; }
  if (input || gpio >= 34) { pinMode(gpio, INPUT); return; }
  pinMode(gpio, OUTPUT);
  digitalWrite(gpio, offLevel ? HIGH : LOW);
}

void setupWheel(int i) {
  int en = cfg.wheel[i][0], a = cfg.wheel[i][1], b = cfg.wheel[i][2];
  pinMode(a, OUTPUT); digitalWrite(a, LOW);
  pinMode(b, OUTPUT); digitalWrite(b, LOW);
  ledcSetup(i, MOTOR_FREQ, 8);          // canales 0..3: un canal por rueda
  ledcAttachPin(en, i);
  ledcWrite(i, 0);
}

void setupOutput(int8_t gpio, bool inverted) {
  if (gpio < 0) return;
  pinMode(gpio, OUTPUT);
  digitalWrite(gpio, inverted ? HIGH : LOW);
}

// Torreta: servo normal (180°) en el canal 6, a 50 Hz.
const int SERVO_CH = 6;
void writeTurret() {
  if (cfg.turret < 0) return;
  int a = constrain(turretAngle, 0, 359) * 180 / 359;
  if (cfg.turretInv) a = 180 - a;
  uint32_t us = 500 + (uint32_t)a * 1900 / 180;
  ledcWrite(SERVO_CH, us * 65535 / 20000);
}
void setupTurret() {
  if (cfg.turret < 0) return;
  ledcSetup(SERVO_CH, 50, 16);
  ledcAttachPin(cfg.turret, SERVO_CH);
  writeTurret();
}

void setupSensor() {
  sensorFails = 0;
  if (cfg.trig < 0 || cfg.echo < 0) { distanceCm = -1; return; }
  pinMode(cfg.trig, OUTPUT);
  digitalWrite(cfg.trig, LOW);
  pinMode(cfg.echo, INPUT);
}

void setupAll() {
  for (int i = 0; i < 4; i++) setupWheel(i);
  setupOutput(cfg.lights, cfg.lightsInv);
  setupOutput(cfg.horn, cfg.hornInv);
  setupTurret();
  setupSensor();
}

void releaseAll() {
  for (int i = 0; i < 4; i++) for (int j = 0; j < 3; j++) releasePin(cfg.wheel[i][j], LOW, false);
  releasePin(cfg.lights, cfg.lightsInv, false);
  releasePin(cfg.horn, cfg.hornInv, false);
  releasePin(cfg.turret, LOW, false);
  releasePin(cfg.trig, LOW, false);
  releasePin(cfg.echo, LOW, true);
}

// ============ MOTORES ============
// Aplica la potencia actual a una rueda: signo = sentido, valor = velocidad.
void applyWheel(int i) {
  int v = current[i];
  if (isInverted(i)) v = -v;
  digitalWrite(cfg.wheel[i][1], v > 0 ? HIGH : LOW);
  digitalWrite(cfg.wheel[i][2], v < 0 ? HIGH : LOW);
  ledcWrite(i, abs(v));
}

// De porcentaje (-100..100) a potencia (-255..255), saltando la zona en que el motor no alcanza a moverse.
int16_t toPower(int pct) {
  if (pct == 0) return 0;
  int minPwm = cfg.minPower * 255 / 100;
  int p = map(abs(pct), 1, 100, minPwm, 255);
  return pct > 0 ? p : -p;
}

int deadzone(int v, int dz) { return abs(v) < dz ? 0 : v; }

bool obstacleAhead() { return distanceCm > 0 && distanceCm < STOP_CM; }

// Joystick + acelerador => potencia de cada lado (manejo tipo tanque).
void computeTargets() {
  int y = deadzone(constrain(joyY, -100, 100), 10);
  int x = deadzone(constrain(joyX, -100, 100), 10);
  int th = deadzone(constrain(throttle, 0, 100), 5);

  int forward = abs(y) >= th ? y : (reverseGear ? -th : th);
  if (forward > 0 && obstacleAhead()) forward = 0;   // puede girar o retroceder, pero no avanzar

  int left = forward + x, right = forward - x;
  int biggest = max(abs(left), abs(right));
  if (biggest > 100) { left = left * 100 / biggest; right = right * 100 / biggest; }

  target[0] = target[1] = toPower(left);
  target[2] = target[3] = toPower(right);

  String now = "Ruedas: izquierda " + String(left) + " % · derecha " + String(right) + " %";
  if (now != lastPrinted) { Serial.println(now); lastPrinted = now; }
}

bool moving() {
  for (int i = 0; i < 4; i++) if (target[i] != 0 || current[i] != 0) return true;
  return false;
}

// Detiene todo al instante (sin rampa). También termina la prueba de ruedas, si estaba corriendo.
void stopNow(const char* why) {
  bool was = moving();
  testWheel = -1;
  joyX = joyY = throttle = 0;
  for (int i = 0; i < 4; i++) { target[i] = current[i] = 0; applyWheel(i); }
  lastPrinted = "";
  if (was && why) sendLine(String("ERR:") + why);
}

// Cancela la prueba de ruedas (si está corriendo): motores quietos y un ERR que dice por qué.
void abortTest(const char* why) {
  if (!testRunning()) return;
  stopNow(nullptr);
  sendLine(String("ERR:prueba cancelada: ") + why);
}

// Arranque y frenado suaves: la potencia se acerca a la pedida poco a poco.
void loopRamp(uint32_t now) {
  if (now - lastRamp < 10) return;
  lastRamp = now;
  for (int i = 0; i < 4; i++) {
    int d = target[i] - current[i];
    if (d == 0) continue;
    current[i] += constrain(d, -(int)RAMP_STEP, (int)RAMP_STEP);
    applyWheel(i);
  }
}

// ============ CONDUCTOR ============
void releaseDriver() { driver = SRC_NONE; warnedSrc = 0; }

// Avisa una sola vez a un origen que su orden de manejo no se aplica.
void warnOnce(Src src, const char* text) {
  if (warnedSrc & (1 << src)) return;
  warnedSrc |= 1 << src;
  reply(src, text);
}

// Llegó joystick o acelerador. Parar vale desde cualquier origen; moverse, solo desde el conductor
// (el primero que se mueve cuando no hay otro). Solo el conductor renueva el watchdog de señal.
// Devuelve false si la orden se ignora.
bool acceptDrive(Src src, bool stop) {
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
// era el que manejaba (o nadie manejaba), el carrito se detiene con el seguro puesto.
void sourceChanged(Src s) {
  clearLine(s);
  waitNeutral &= ~(1 << s);
  warnedSrc &= ~(1 << s);
  turretWarned = false;
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
// órdenes, así un teléfono en segundo plano que solo manda PING no deja el carrito andando).
void loopSafety(uint32_t now) {
  if (testRunning() || now - lastRx <= SIGNAL_TIMEOUT_MS) return;   // la prueba de ruedas no necesita señal
  // También si quedó algo pedido sin moverse (por ejemplo, el acelerador puesto frente a un obstáculo).
  if (moving() || joyX || joyY || throttle) { stopNow("sin señal: el carrito se detuvo"); lockDriving(); }
  if (driver != SRC_NONE) releaseDriver();
}

// ============ LUCES, BOCINA, SENSOR ============
void writeLights(bool on) {
  if (cfg.lights >= 0) digitalWrite(cfg.lights, (on != (bool)cfg.lightsInv) ? HIGH : LOW);
}

void setLights(bool on) {
  lightsOn = on;
  writeLights(on);
}

void setHorn(bool on) {
  if (cfg.horn >= 0) digitalWrite(cfg.horn, (on != (bool)cfg.hornInv) ? HIGH : LOW);
}

void loopHorn(uint32_t now) {
  if (hornUntil && (int32_t)(now - hornUntil) >= 0) { hornUntil = 0; setHorn(false); }
}

const char* SENSOR_ERR = "ERR:el sensor de distancia no responde: revisa TRIG, ECHO y sus 5 V";

// Dispara el HC-SR04 y mide el eco (como mucho ~35 ms). Devuelve los µs del eco, 0 si no volvió eco
// dentro de ~4 m (nada adelante) o -1 si el sensor no contestó: el ECHO nunca subió o sigue arriba.
// (pulseIn daba 0 en los dos casos y no permitía saber si el sensor estaba desconectado.)
long echoMicros() {
  if (digitalRead(cfg.echo) == HIGH) return -1;
  digitalWrite(cfg.trig, HIGH);
  delayMicroseconds(10);
  digitalWrite(cfg.trig, LOW);
  uint32_t t0 = micros();
  while (digitalRead(cfg.echo) == LOW) if (micros() - t0 > 10000) return -1;
  uint32_t t1 = micros();
  while (digitalRead(cfg.echo) == HIGH) if (micros() - t1 > 25000) return 0;
  return (long)(micros() - t1);
}

void loopSensor(uint32_t now) {
  if (cfg.trig < 0 || cfg.echo < 0 || now - lastSensor < 80) return;
  lastSensor = now;
  long us = echoMicros();
  if (us >= 0) {
    if (sensorFails >= SENSOR_FAILS) sendLine("OK:el sensor de distancia volvio a responder");
    sensorFails = 0;
  } else if (sensorFails < SENSOR_FAILS && ++sensorFails == SENSOR_FAILS) {
    sendLine(SENSOR_ERR);   // una sola vez, hasta que vuelva a responder
  }
  distanceCm = us > 0 ? (int)(us / 58) : 400;
  bool obstacle = obstacleAhead();
  if (obstacle != lastObstacle && !testRunning()) {
    lastObstacle = obstacle;
    computeTargets();
    // Obstáculo adelante: el avance se corta al instante, sin rampa (girar o retroceder sigue con rampa).
    if (obstacle)
      for (int i = 0; i < 4; i++)
        if (current[i] > 0 && current[i] > target[i]) { current[i] = target[i] > 0 ? target[i] : 0; applyWheel(i); }
  }
  bool changed = abs(distanceCm - lastDistSent) >= 2;
  if ((changed && now - lastDistReport > 300) || now - lastDistReport > 2000) {
    lastDistReport = now;
    lastDistSent = distanceCm;
    sendLine("V" + String(VPIN_DIST) + ":" + String(distanceCm));
  }
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

// AUTH:<clave>
void handleAuth(Src src, const String& given) {
  if (carKey.length() == 0) { reply(src, "AUTH:NUEVA"); return; }
  uint32_t wait = lockLeft(millis());
  if (wait) { reply(src, "AUTH:ESPERA:" + String(wait)); return; }
  if (given == carKey) {
    failCount = 0;
    authed[src] = true;
    reply(src, "AUTH:OK");
    return;
  }
  deauth(src);
  if (given.length() == 0) { reply(src, "AUTH:PIDE"); return; }   // la app aún no la conoce: no cuenta como intento
  if (++failCount >= MAX_FAILS) {
    failCount = 0;
    lockStart = millis() | 1;   // nunca 0, que significa «sin bloqueo»
    reply(src, "AUTH:ESPERA:" + String(LOCK_MS / 1000));
  } else {
    reply(src, "AUTH:MAL:" + String(MAX_FAILS - failCount));
  }
}

// CLAVE:<nueva>. Crear la primera no pide nada; cambiarla exige haber entregado la actual.
void handleNewKey(Src src, const String& key) {
  if (src == SRC_SERIAL && key.equalsIgnoreCase("BORRAR")) {
    storeKey("", SRC_SERIAL);
    reply(src, "OK:el carrito quedo sin clave");
    return;
  }
  if (carKey.length() && !authed[src]) { reply(src, "AUTH:PIDE"); return; }
  if (!validKey(key)) { reply(src, "ERR:la clave debe tener de 4 a 8 numeros"); return; }
  storeKey(key, src);
  authed[src] = true;
  reply(src, "AUTH:OK");
  Serial.println("Clave del carrito guardada");
}

// Mantener BOOT presionado 5 s borra la clave, por si se olvida y no hay computadora a mano.
// Las luces parpadean 3 veces para confirmarlo, sin delay(): el loop sigue atendiendo los motores.
uint8_t blinkLeft = 0;
uint32_t blinkNext = 0;

void loopResetButton(uint32_t now) {
  static uint32_t pressStart = 0;
  static bool done = false;
  if (blinkLeft && (int32_t)(now - blinkNext) >= 0) {
    blinkLeft--;
    blinkNext = now + 250;
    if (blinkLeft) writeLights(blinkLeft % 2 == 0);   // 6 prendidas, 5 apagadas, ... 1 apagadas
    else setLights(lightsOn);                         // 0: como estaban
  }
  if (pinInUse(BOOT_PIN)) { pressStart = 0; return; }   // el GPIO 0 se usa para otra cosa
  if (digitalRead(BOOT_PIN) == HIGH) { pressStart = 0; done = false; return; }
  if (pressStart == 0) pressStart = now | 1;
  if (done || now - pressStart < RESET_HOLD_MS) return;
  done = true;
  storeKey("", SRC_SERIAL);
  Serial.println("Clave borrada con el boton BOOT");
  blinkLeft = 7;
  blinkNext = now;
}

// ============ MENSAJES ============
String invertString() {
  String s;
  for (int i = 0; i < 4; i++) s += isInverted(i) ? '1' : '0';
  return s;
}

void sync() {
  sendLine("V" + String(VPIN_LIGHTS) + ":" + String(lightsOn ? 1 : 0));
  sendLine("V" + String(VPIN_REVERSE) + ":" + String(reverseGear ? 1 : 0));
  sendLine("V" + String(VPIN_THROTTLE) + ":" + String(throttle));
  sendLine("V" + String(VPIN_INVERT) + ":" + invertString());
  if (cfg.turret >= 0) sendLine("V" + String(VPIN_TURRET) + ":" + String(turretAngle));   // la app muestra la torreta solo si existe
  if (distanceCm >= 0) sendLine("V" + String(VPIN_DIST) + ":" + String(distanceCm));
  if (cfg.trig >= 0 && sensorFails >= SENSOR_FAILS) sendLine(SENSOR_ERR);   // para el teléfono que recién llega
}

String pinText(int8_t g) { return g < 0 ? String("-") : String((int)g); }

void showPins() {
  for (int i = 0; i < 4; i++)
    sendLine(String("OK:") + WHEEL_CODE[i] + " EN " + pinText(cfg.wheel[i][0]) + " IN " + pinText(cfg.wheel[i][1]) + "," + pinText(cfg.wheel[i][2]) +
             (isInverted(i) ? " invertida" : ""));
  sendLine("OK:luces " + pinText(cfg.lights) + " · bocina " + pinText(cfg.horn) + " · torreta " + pinText(cfg.turret) +
           " · sensor " + pinText(cfg.trig) + "," + pinText(cfg.echo) + " · minimo " + String(cfg.minPower) + " %");
}

// Prueba de ruedas: cada rueda gira hacia adelante TEST_SPIN_MS y queda quieta TEST_PAUSE_MS, una por
// una. La sigue loopTest() sin bloquear, así el loop sigue atendiendo el freno, las conexiones y la clave.
// (Antes se borraba lo que llegaba durante la prueba; ya no hace falta: ahora cada orden se atiende
// en el momento, y borrar la cola de Bluetooth perdería los avisos de conexión.)
void spinTestWheel(int w) {
  testWheel = w;
  testPaused = false;
  sendLine(String("OK:PRUEBA rueda ") + WHEEL_NAME[w]);
  current[w] = toPower(60);
  applyWheel(w);
  testUntil = millis() + TEST_SPIN_MS;
}

void startTest(Src src) {
  if (testRunning()) { abortTest("se pidio TEST otra vez mientras corria"); return; }
  stopNow(nullptr);
  releaseDriver();
  testSrc = src;
  sendLine("OK:PRUEBA cada rueda debe girar hacia ADELANTE");
  spinTestWheel(0);
}

void loopTest(uint32_t now) {
  if (!testRunning() || (int32_t)(now - testUntil) < 0) return;
  int w = testWheel;
  if (!testPaused) {          // terminó de girar: la rueda se detiene y empieza la pausa
    current[w] = 0;
    applyWheel(w);
    testPaused = true;
    testUntil = now + TEST_PAUSE_MS;
  } else if (w < 3) {
    spinTestWheel(w + 1);
  } else {
    testWheel = -1;
    sendLine("OK:PRUEBA terminada. Si una rueda giro hacia atras, activa Invertir en esa rueda");
  }
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
String checkPins(const int* pins, int n, const bool* output, const String& self) {
  for (int k = 0; k < n; k++) {
    const char* p = gpioProblem(pins[k], output[k]);
    if (p) return "GPIO " + String(pins[k]) + ": " + p;
    String owner = pinOwner(pins[k]);
    if (owner.length() && owner != self) return "el GPIO " + String(pins[k]) + " ya lo usa " + owner;
    for (int j = 0; j < k; j++) if (pins[j] == pins[k]) return "el GPIO " + String(pins[k]) + " esta repetido";
  }
  return "";
}

void handleWheelPins(const String& arg) {   // DI:32,33,25
  int colon = arg.indexOf(':');
  String code = arg.substring(0, colon);
  code.toUpperCase();
  int w = -1;
  for (int i = 0; i < 4; i++) if (code == WHEEL_CODE[i]) w = i;
  int pins[3];
  if (w < 0 || colon < 0 || parseList(arg.substring(colon + 1), pins, 3) != 3) { sendLine("ERR:usa RUEDA:DI:32,33,25"); return; }
  const bool out[3] = {true, true, true};
  String problem = checkPins(pins, 3, out, String("rueda ") + WHEEL_CODE[w]);
  if (problem.length()) { sendLine("ERR:" + problem); return; }
  abortTest("cambiaron los pines de una rueda");
  stopNow(nullptr);
  for (int j = 0; j < 3; j++) releasePin(cfg.wheel[w][j], LOW, false);
  for (int j = 0; j < 3; j++) cfg.wheel[w][j] = pins[j];
  setupWheel(w);
  saveConfig();
  sendLine(String("OK:rueda ") + WHEEL_CODE[w] + " EN " + pins[0] + " IN " + pins[1] + "," + pins[2]);
}

void handleCfg(const String& arg) {         // V23:23:0:1
  int vpin, gpio, inv, en;
  int a = arg.indexOf(':'), b = arg.indexOf(':', a + 1), c = arg.indexOf(':', b + 1);
  if (a < 0 || b < 0 || c < 0 || (arg[0] != 'V' && arg[0] != 'v') ||
      !parseIntStrict(arg.substring(1, a), vpin) || !parseIntStrict(arg.substring(a + 1, b), gpio) ||
      !parseIntStrict(arg.substring(b + 1, c), inv) || !parseIntStrict(arg.substring(c + 1), en) ||
      inv < 0 || inv > 1 || en < 0 || en > 1) { sendLine("ERR:CFG " + arg); return; }
  int8_t* slot; uint8_t* slotInv; const char* name;
  if (vpin == VPIN_LIGHTS) { slot = &cfg.lights; slotInv = &cfg.lightsInv; name = "luces"; }
  else if (vpin == VPIN_HORN) { slot = &cfg.horn; slotInv = &cfg.hornInv; name = "bocina"; }
  else if (vpin == VPIN_TURRET) { slot = &cfg.turret; slotInv = &cfg.turretInv; name = "torreta"; }
  else { sendLine("ERR:CFG V" + String(vpin) + " no se configura asi"); return; }
  if (en) {
    const bool out[1] = {true};
    String problem = checkPins(&gpio, 1, out, name);
    if (problem.length()) { sendLine("ERR:" + problem); return; }
  }
  int8_t pin = en ? gpio : -1;
  if (*slot != pin || *slotInv != inv) {   // solo se toca y se graba si cambió (la app lo reenvía al conectar)
    releasePin(*slot, vpin == VPIN_TURRET ? LOW : *slotInv, false);
    *slot = pin;
    *slotInv = inv;
    if (vpin == VPIN_TURRET) setupTurret(); else setupOutput(*slot, *slotInv);
    if (vpin == VPIN_LIGHTS) setLights(lightsOn);
    saveConfig();
  }
  sendLine(String("OK:") + name + (en ? " GPIO " + String(gpio) + (inv ? " inv" : "") : String(" sin conectar")));
}

void handleSensor(String arg) {             // 21,34  o  NO
  arg.trim();
  arg.toUpperCase();
  releasePin(cfg.trig, LOW, false);
  releasePin(cfg.echo, LOW, true);
  if (arg == "NO") {
    cfg.trig = cfg.echo = -1;
    distanceCm = -1;
    sensorFails = 0;
    saveConfig();
    sendLine("OK:sensor quitado");
    return;
  }
  int pins[2];
  int8_t oldTrig = cfg.trig, oldEcho = cfg.echo;
  cfg.trig = cfg.echo = -1;   // para que no choquen consigo mismos
  const bool out[2] = {true, false};
  String problem = parseList(arg, pins, 2) == 2 ? checkPins(pins, 2, out, "sensor") : String("usa SENSOR:21,34");
  if (problem.length()) {
    cfg.trig = oldTrig; cfg.echo = oldEcho;
    setupSensor();
    sendLine("ERR:" + problem);
    return;
  }
  cfg.trig = pins[0];
  cfg.echo = pins[1];
  setupSensor();
  saveConfig();
  sendLine("OK:sensor TRIG " + String(pins[0]) + " ECHO " + String(pins[1]));
}

void handleInvert(String v) {               // 0100
  v.trim();
  if (v.length() != 4) { sendLine("ERR:V27 necesita cuatro 0/1, por ejemplo 0100"); return; }
  uint8_t mask = 0;
  for (int i = 0; i < 4; i++) {
    if (v[i] != '0' && v[i] != '1') { sendLine("ERR:V27 necesita cuatro 0/1, por ejemplo 0100"); return; }
    if (v[i] == '1') mask |= 1 << i;
  }
  if (mask != cfg.invertMask) {   // solo se graba si cambió (cada escritura gasta la memoria de la placa)
    abortTest("cambio el sentido de una rueda");
    stopNow(nullptr);
    cfg.invertMask = mask;
    saveConfig();
  }
  sendLine("V" + String(VPIN_INVERT) + ":" + invertString());
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
// Mientras hay seguro el carrito ya está detenido, así que ignorar el «parar» de otro no cambia nada.
bool lockedFor(Src src, bool neutral, bool& seen) {
  if (!driveLocked) return false;
  if (driver != SRC_NONE && driver != src) return true;
  return !unlockWith(neutral, seen);
}

void handleLine(Src src, String line) {
  line.trim();
  if (!line.length()) return;
  String up = line;
  up.toUpperCase();

  if (up == "PING") { reply(src, "PONG"); return; }   // sin clave también; no cuenta como señal de manejo
  if (up.startsWith("AUTH:")) { handleAuth(src, line.substring(5)); return; }
  if (up.startsWith("CLAVE:")) { handleNewKey(src, line.substring(6)); return; }
  if (!authed[src]) { reply(src, carKey.length() ? "AUTH:PIDE" : "AUTH:NUEVA"); return; }

  if (up == "SYNC") { sync(); return; }
  if (up == "TEST") { startTest(src); return; }
  if (up == "PINES") { showPins(); return; }
  if (up == "FABRICA") {
    abortTest("cambiaron los pines");
    stopNow(nullptr); releaseAll(); cfg = DEFAULTS; saveConfig(); setupAll();
    sendLine("OK:pines de fabrica"); showPins();
    return;
  }
  if (up.startsWith("RUEDA:")) { handleWheelPins(line.substring(6)); return; }
  if (up.startsWith("CFG:")) { handleCfg(line.substring(4)); return; }
  if (up.startsWith("SENSOR:")) { handleSensor(line.substring(7)); return; }
  if (up.startsWith("MINIMO:")) {
    int m;
    if (!parseIntStrict(line.substring(7), m) || m < 0 || m > 90) { sendLine("ERR:MINIMO va de 0 a 90"); return; }
    if (m != cfg.minPower) { cfg.minPower = m; saveConfig(); }
    computeTargets();
    sendLine("OK:minimo " + String(m) + " %");
    return;
  }

  int colon = line.indexOf(':');
  int vpin;
  if (line[0] != 'V' || colon < 2 || !parseIntStrict(line.substring(1, colon), vpin)) { sendLine("ERR:no entiendo " + line); return; }
  String v = line.substring(colon + 1);
  int n = 0;   // valor de los pines que llevan un solo número
  bool single = vpin == VPIN_TURRET || vpin == VPIN_LIGHTS || vpin == VPIN_THROTTLE || vpin == VPIN_REVERSE || vpin == VPIN_HORN;
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
    case VPIN_LIGHTS:   setLights(n != 0); sendLine("V" + String(VPIN_LIGHTS) + ":" + String(lightsOn ? 1 : 0)); return;
    case VPIN_HORN:
      if (n) { setHorn(true); hornUntil = millis() + HORN_MS; } else { setHorn(false); hornUntil = 0; }
      return;
    case VPIN_TURRET:
      if (cfg.turret < 0) {
        if (!turretWarned) sendLine("ERR:la torreta no esta conectada (CFG:V21:<gpio>:0:1)");
        turretWarned = true;
        return;
      }
      turretAngle = constrain(n, 0, 359);
      writeTurret();
      return;
    case VPIN_INVERT: handleInvert(v); return;
    default: sendLine("ERR:V" + String(vpin) + " no existe en el carrito"); return;
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
      Serial.println("Wi-Fi: telefono conectado");
      reply(SRC_TCP, "HELLO:" DEVICE_NAME);
    }
  }
  if (tcpWasConnected && !tcpClient.connected()) {
    tcpWasConnected = false;
    authed[SRC_TCP] = false;
    sourceChanged(SRC_TCP);
    Serial.println("Wi-Fi desconectado");
  }
  // Como mucho 512 bytes por vuelta, para que un teléfono que manda sin parar no trabe el loop.
  for (int n = 0; n < 512 && tcpClient.connected() && tcpClient.available(); n++) {
    tcpLastRx = millis();
    feedChar(SRC_TCP, (char)tcpClient.read());
  }
}
#endif

// Respuesta solo para quien preguntó (por ejemplo, el resultado de la clave).
void reply(Src src, const String& line) {
  Serial.println("-> " + line);
  if (src == SRC_BLE) bleSend(line + "\n");
#if USE_WIFI
  if (src == SRC_TCP && tcpClient.connected()) rawSend(tcpClient, line + "\n");
#endif
}

// Aviso para todos: el Monitor Serie y cada teléfono que ya entregó la clave.
void sendLine(const String& line) {
  Serial.println("-> " + line);
  if (authed[SRC_BLE]) bleSend(line + "\n");
#if USE_WIFI
  if (authed[SRC_TCP] && tcpClient.connected()) rawSend(tcpClient, line + "\n");
#endif
}

// ============ PROGRAMA PRINCIPAL ============
void setup() {
  loadConfig();
  setupAll();            // motores quietos lo antes posible
  setLights(false);
  setHorn(false);
  if (!pinInUse(BOOT_PIN)) pinMode(BOOT_PIN, INPUT_PULLUP);   // botón BOOT: 5 s presionado borra la clave
  loadKey();

  Serial.begin(115200);
  delay(200);
  Serial.println("\n== " DEVICE_NAME " (" FW_VERSION ") ==");
  setupBle();
#if USE_WIFI
  setupWifi();
#endif
  showPins();
  Serial.println(carKey.length() ? "El carrito tiene clave." : "El carrito no tiene clave: el primer telefono que se conecte la crea.");
  Serial.println("Escribe mensajes aqui mismo para probar, por ejemplo: V20:0,60 (adelante) o TEST");
  enableLoopWDT();       // si loop() se traba más de 5 s, la placa se reinicia (los motores quedan quietos)
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
  loopSensor(now);
  if (!testRunning()) loopRamp(now);   // durante la prueba las ruedas las maneja loopTest
  loopHorn(now);
  loopResetButton(now);
}
