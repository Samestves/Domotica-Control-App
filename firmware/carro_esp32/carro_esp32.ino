/*
  Carrito 4x4 · programa para el ESP32 del carrito
  ------------------------------------------------
  Cuatro motores TT con dos puentes H L298N. Se maneja desde la misma app de la casa
  (panel «Auto Robot») por Bluetooth LE o por Wi-Fi. Gira como un tanque: para doblar,
  las ruedas de un lado van más lento o hacia atrás.

  Wi-Fi propio: el ESP32 crea la red «Carrito 4x4» (contraseña: carrito4x4).
  La app se une a esa red y se conecta a la IP 192.168.4.1, puerto 3333.
  Bluetooth y Wi-Fi funcionan a la vez: un teléfono por cada uno.

  Pines virtuales (los mismos del panel del carrito en la app):
    V20  joystick «x,y», cada uno de -100 a 100 (y positivo = adelante, x positivo = derecha)
    V21  torreta (servo, opcional): 0..359
    V22  distancia al obstáculo en cm (de la placa a la app; solo con sensor HC-SR04)
    V23  luces: 1 / 0
    V24  acelerador: 0..100 (velocidad fija hacia adelante, o hacia atrás con la reversa)
    V25  reversa: 1 / 0 (cambia el sentido del acelerador; el joystick no se ve afectado)
    V26  bocina: 1 = pitar un momento
    V27  invertir ruedas: cuatro 0/1 en orden DI, TI, DD, TD. Ej.: V27:0100 invierte la trasera izquierda

  Seguridad:
    - Si se corta el Bluetooth o el Wi-Fi, los motores se detienen al instante.
    - Si la app deja de enviar señal por 1 segundo mientras el carrito anda, se detiene solo.
      (La app 0.7.2 o más nueva repite la orden mientras mantienes el joystick.)
    - Arranque suave: los motores no saltan de golpe a toda velocidad.
    - Con sensor de distancia: no avanza si hay un obstáculo a menos de 15 cm (sí puede girar o retroceder).

  Ruedas: DI delantera izquierda · TI trasera izquierda · DD delantera derecha · TD trasera derecha
  Pines de fábrica (los de la guía de armado):
            L298N   velocidad (EN)  sentido (IN)   sentido (IN)
    DI      A       32              33             25
    TI      A       26              27             14
    DD      B       13               4             16
    TD      B       17              18             19
    Luces 23 · Bocina 5 · Torreta y sensor: sin conectar

  Otros mensajes (por la app o el Monitor Serie a 115200):
    SYNC                  la placa responde con el estado actual
    TEST                  mueve cada rueda hacia adelante, una por una, para ver cuál es cuál
                          (las órdenes que lleguen mientras tanto se descartan)
    PINES                 muestra los pines que está usando
    PING                  responde PONG
    RUEDA:DI:32,33,25     cambia los pines de una rueda (EN, IN1, IN2)
    CFG:V23:23:0:1        luces en el GPIO 23, sin invertir (0), activadas (1). Igual V26 (bocina) y V21 (torreta)
    SENSOR:21,34          sensor HC-SR04: TRIG en 21 y ECHO en 34 (¡ECHO con divisor de voltaje a 3,3 V!)
    SENSOR:NO             quita el sensor
    MINIMO:35             potencia mínima (%) con la que las ruedas empiezan a girar
    FABRICA               vuelve a los pines de fábrica
  Los cambios se guardan en la placa.

  Placa: "ESP32 Dev Module" con Partition Scheme "Huge APP". Sin librerías extra.
*/

#include <Arduino.h>
#include <Preferences.h>

// ============ CONFIGURACIÓN ============
#define DEVICE_NAME "Carrito 4x4"
#define USE_WIFI    1                      // 1 = crear también la red Wi-Fi propia del carrito
const char*    AP_PASS = "carrito4x4";     // mínimo 8 letras
const uint16_t TCP_PORT = 3333;
const uint32_t SIGNAL_TIMEOUT_MS = 1000;   // sin señal este tiempo => se detiene
const uint8_t  RAMP_STEP = 12;             // cuánto cambia la potencia cada 10 ms (arranque suave)
const int      STOP_CM = 15;               // con sensor: no avanza si hay algo más cerca
const uint16_t HORN_MS = 350;
const uint32_t MOTOR_FREQ = 1000;          // Hz del PWM de los motores (el L298N es lento)

enum : uint8_t { VPIN_JOY = 20, VPIN_TURRET = 21, VPIN_DIST = 22, VPIN_LIGHTS = 23,
                 VPIN_THROTTLE = 24, VPIN_REVERSE = 25, VPIN_HORN = 26, VPIN_INVERT = 27 };

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
uint32_t lastRx = 0, lastRamp = 0, hornUntil = 0, lastSensor = 0, lastDistReport = 0;
int lastDistSent = -100;
bool lastObstacle = false;
bool turretWarned = false;   // el aviso de «sin torreta» se da una vez por conexión
String lastPrinted;

volatile bool bleConnected = false;
volatile bool bleJustDisconnected = false;
volatile bool bleJustConnected = false;

void sendLine(const String& line);
void discardPendingInput();

// ============ PINES ============
// Mismas reglas que la app.
const char* gpioProblem(int gpio, bool output = true) {
  if (gpio < 0 || gpio > 39) return "el ESP32 tiene GPIO del 0 al 39";
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

void releasePin(int gpio) {
  if (gpio < 0) return;
  ledcDetachPin(gpio);
  pinMode(gpio, INPUT);
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
  for (int i = 0; i < 4; i++) for (int j = 0; j < 3; j++) releasePin(cfg.wheel[i][j]);
  releasePin(cfg.lights);
  releasePin(cfg.horn);
  releasePin(cfg.turret);
  releasePin(cfg.trig);
  releasePin(cfg.echo);
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

// Detiene todo al instante (sin rampa).
void stopNow(const char* why) {
  bool was = moving();
  joyX = joyY = throttle = 0;
  for (int i = 0; i < 4; i++) { target[i] = current[i] = 0; applyWheel(i); }
  lastPrinted = "";
  if (was && why) sendLine(String("ERR:") + why);
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

void loopSafety(uint32_t now) {
  if (bleJustDisconnected) { bleJustDisconnected = false; stopNow(nullptr); Serial.println("Bluetooth desconectado: carrito detenido"); }
  if (bleJustConnected) { bleJustConnected = false; stopNow(nullptr); lastRx = now; turretWarned = false; }
  if (moving() && now - lastRx > SIGNAL_TIMEOUT_MS) stopNow("sin señal: el carrito se detuvo");
}

// ============ LUCES, BOCINA, SENSOR ============
void setLights(bool on) {
  lightsOn = on;
  if (cfg.lights >= 0) digitalWrite(cfg.lights, (on != (bool)cfg.lightsInv) ? HIGH : LOW);
}

void setHorn(bool on) {
  if (cfg.horn >= 0) digitalWrite(cfg.horn, (on != (bool)cfg.hornInv) ? HIGH : LOW);
}

void loopHorn(uint32_t now) {
  if (hornUntil && (int32_t)(now - hornUntil) >= 0) { hornUntil = 0; setHorn(false); }
}

void loopSensor(uint32_t now) {
  if (cfg.trig < 0 || cfg.echo < 0 || now - lastSensor < 80) return;
  lastSensor = now;
  digitalWrite(cfg.trig, HIGH);
  delayMicroseconds(10);
  digitalWrite(cfg.trig, LOW);
  unsigned long us = pulseIn(cfg.echo, HIGH, 25000);   // hasta ~4 m
  distanceCm = us ? (int)(us / 58) : 400;
  bool obstacle = obstacleAhead();
  if (obstacle != lastObstacle) { lastObstacle = obstacle; computeTargets(); }
  bool changed = abs(distanceCm - lastDistSent) >= 2;
  if ((changed && now - lastDistReport > 300) || now - lastDistReport > 2000) {
    lastDistReport = now;
    lastDistSent = distanceCm;
    sendLine("V" + String(VPIN_DIST) + ":" + String(distanceCm));
  }
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
}

String pinText(int8_t g) { return g < 0 ? String("-") : String((int)g); }

void showPins() {
  for (int i = 0; i < 4; i++)
    sendLine(String("OK:") + WHEEL_CODE[i] + " EN " + pinText(cfg.wheel[i][0]) + " IN " + pinText(cfg.wheel[i][1]) + "," + pinText(cfg.wheel[i][2]) +
             (isInverted(i) ? " invertida" : ""));
  sendLine("OK:luces " + pinText(cfg.lights) + " · bocina " + pinText(cfg.horn) + " · torreta " + pinText(cfg.turret) +
           " · sensor " + pinText(cfg.trig) + "," + pinText(cfg.echo) + " · minimo " + String(cfg.minPower) + " %");
}

// Mueve cada rueda hacia adelante, una por una. Detiene todo antes y después.
void wheelTest() {
  stopNow(nullptr);
  sendLine("OK:PRUEBA cada rueda debe girar hacia ADELANTE");
  for (int i = 0; i < 4; i++) {
    sendLine(String("OK:PRUEBA rueda ") + WHEEL_NAME[i]);
    current[i] = toPower(60);
    applyWheel(i);
    delay(1200);
    current[i] = 0;
    applyWheel(i);
    delay(500);
  }
  discardPendingInput();   // por ejemplo, otros TEST tocados mientras giraban las ruedas
  lastRx = millis();
  sendLine("OK:PRUEBA terminada. Si una rueda giro hacia atras, activa Invertir en esa rueda");
}

// Lista de tres números separados por coma.
int parseList(const String& s, int* out, int maxN) {
  int n = 0, start = 0;
  while (n < maxN) {
    int comma = s.indexOf(',', start);
    String part = comma < 0 ? s.substring(start) : s.substring(start, comma);
    part.trim();
    if (!part.length()) return -1;
    for (unsigned k = 0; k < part.length(); k++) if (!isDigit(part[k])) return -1;
    out[n++] = part.toInt();
    if (comma < 0) break;
    start = comma + 1;
  }
  return n;
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
  stopNow(nullptr);
  for (int j = 0; j < 3; j++) releasePin(cfg.wheel[w][j]);
  for (int j = 0; j < 3; j++) cfg.wheel[w][j] = pins[j];
  setupWheel(w);
  saveConfig();
  sendLine(String("OK:rueda ") + WHEEL_CODE[w] + " EN " + pins[0] + " IN " + pins[1] + "," + pins[2]);
}

void handleCfg(const String& arg) {         // V23:23:0:1
  int vpin, gpio, inv, en;
  if (sscanf(arg.c_str(), "V%d:%d:%d:%d", &vpin, &gpio, &inv, &en) != 4) { sendLine("ERR:CFG " + arg); return; }
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
  releasePin(*slot);
  *slot = en ? gpio : -1;
  *slotInv = inv ? 1 : 0;
  if (vpin == VPIN_TURRET) setupTurret(); else setupOutput(*slot, *slotInv);
  if (vpin == VPIN_LIGHTS) setLights(lightsOn);
  saveConfig();
  sendLine(String("OK:") + name + (en ? " GPIO " + String(gpio) + (inv ? " inv" : "") : String(" sin conectar")));
}

void handleSensor(String arg) {             // 21,34  o  NO
  arg.toUpperCase();
  releasePin(cfg.trig);
  releasePin(cfg.echo);
  if (arg == "NO") {
    cfg.trig = cfg.echo = -1;
    distanceCm = -1;
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
  stopNow(nullptr);
  cfg.invertMask = mask;
  saveConfig();
  sendLine("V" + String(VPIN_INVERT) + ":" + invertString());
}

void handleLine(String line) {
  line.trim();
  if (!line.length()) return;
  lastRx = millis();
  String up = line;
  up.toUpperCase();

  if (up == "PING") { sendLine("PONG"); return; }
  if (up == "SYNC") { sync(); return; }
  if (up == "TEST") { wheelTest(); return; }
  if (up == "PINES") { showPins(); return; }
  if (up == "FABRICA") { stopNow(nullptr); releaseAll(); cfg = DEFAULTS; saveConfig(); setupAll(); sendLine("OK:pines de fabrica"); showPins(); return; }
  if (up.startsWith("AUTH:")) { sendLine("ERR:AUTH no se usa en el carrito"); return; }   // la app entiende: placa sin clave
  if (up.startsWith("RUEDA:")) { handleWheelPins(line.substring(6)); return; }
  if (up.startsWith("CFG:")) { handleCfg(line.substring(4)); return; }
  if (up.startsWith("SENSOR:")) { handleSensor(line.substring(7)); return; }
  if (up.startsWith("MINIMO:")) {
    int m = line.substring(7).toInt();
    if (m < 0 || m > 90) { sendLine("ERR:MINIMO va de 0 a 90"); return; }
    cfg.minPower = m;
    saveConfig();
    computeTargets();
    sendLine("OK:minimo " + String(m) + " %");
    return;
  }

  int colon = line.indexOf(':');
  if (line[0] != 'V' || colon < 2) { sendLine("ERR:no entiendo " + line); return; }
  int vpin = line.substring(1, colon).toInt();
  String v = line.substring(colon + 1);

  switch (vpin) {
    case VPIN_JOY: {
      int comma = v.indexOf(',');
      if (comma < 0) { sendLine("ERR:V20 necesita x,y"); return; }
      joyX = v.substring(0, comma).toInt();
      joyY = v.substring(comma + 1).toInt();
      computeTargets();
      return;   // sin respuesta: llegan muchos por segundo
    }
    case VPIN_THROTTLE: throttle = constrain(v.toInt(), 0, 100); computeTargets(); return;
    case VPIN_REVERSE:  reverseGear = v.toInt() != 0; computeTargets(); sendLine("V" + String(VPIN_REVERSE) + ":" + String(reverseGear ? 1 : 0)); return;
    case VPIN_LIGHTS:   setLights(v.toInt() != 0); sendLine("V" + String(VPIN_LIGHTS) + ":" + String(lightsOn ? 1 : 0)); return;
    case VPIN_HORN:
      if (v.toInt()) { setHorn(true); hornUntil = millis() + HORN_MS; } else { setHorn(false); hornUntil = 0; }
      return;
    case VPIN_TURRET:
      if (cfg.turret < 0) {
        if (!turretWarned) sendLine("ERR:la torreta no esta conectada (CFG:V21:<gpio>:0:1)");
        turretWarned = true;
        return;
      }
      turretAngle = constrain(v.toInt(), 0, 359);
      writeTurret();
      return;
    case VPIN_INVERT: handleInvert(v); return;
    default: sendLine("ERR:V" + String(vpin) + " no existe en el carrito"); return;
  }
}

void feedChar(String& buf, char k) {
  if (k == '\n' || k == '\r') {
    if (buf.length()) { String l = buf; buf = ""; handleLine(l); }
  } else if (buf.length() < 120) {
    buf += k;
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
QueueHandle_t bleRxQueue;
String bleBuffer;

class ServerCb : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConnected = true; bleJustConnected = true; }
  void onDisconnect(BLEServer* s) override { bleConnected = false; bleJustDisconnected = true; s->getAdvertising()->start(); }
};
class RxCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    const uint8_t* data = c->getData();
    for (size_t i = 0; i < c->getLength(); i++) xQueueSend(bleRxQueue, &data[i], 0);
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
  while (xQueueReceive(bleRxQueue, &k, 0) == pdTRUE) feedChar(bleBuffer, (char)k);
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
#include <WiFi.h>
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;
String tcpBuffer;
bool tcpWasConnected = false;

void setupWifi() {
  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(DEVICE_NAME, AP_PASS)) { Serial.println("No se pudo crear la red Wi-Fi"); return; }
  tcpServer.begin();
  tcpServer.setNoDelay(true);
  Serial.println("Wi-Fi propio listo: red \"" DEVICE_NAME "\", IP " + WiFi.softAPIP().toString() + ", puerto " + String(TCP_PORT));
}

void loopWifi() {
  if (tcpServer.hasClient()) {
    if (tcpClient && tcpClient.connected()) tcpClient.stop();   // un teléfono a la vez por Wi-Fi
    tcpClient = tcpServer.accept();
    tcpClient.setNoDelay(true);
    tcpBuffer = "";
    tcpWasConnected = true;
    stopNow(nullptr);
    lastRx = millis();
    sendLine("HELLO:" DEVICE_NAME);
  }
  if (tcpWasConnected && !(tcpClient && tcpClient.connected())) {
    tcpWasConnected = false;
    stopNow(nullptr);
    Serial.println("Wi-Fi desconectado: carrito detenido");
  }
  while (tcpClient && tcpClient.connected() && tcpClient.available()) feedChar(tcpBuffer, tcpClient.read());
}
#endif

void sendLine(const String& line) {
  Serial.println("-> " + line);
  bleSend(line + "\n");
#if USE_WIFI
  if (tcpClient && tcpClient.connected()) tcpClient.print(line + "\n");
#endif
}

// ============ PROGRAMA PRINCIPAL ============
String serialBuffer;

// Borra lo que llegó y todavía no se leyó (por Bluetooth, Wi-Fi o cable).
void discardPendingInput() {
  xQueueReset(bleRxQueue);
  bleBuffer = "";
  while (Serial.available()) Serial.read();
  serialBuffer = "";
#if USE_WIFI
  while (tcpClient && tcpClient.available()) tcpClient.read();
  tcpBuffer = "";
#endif
}

void setup() {
  loadConfig();
  setupAll();            // motores quietos lo antes posible
  setLights(false);
  setHorn(false);

  Serial.begin(115200);
  delay(200);
  Serial.println("\n== " DEVICE_NAME " ==");
  setupBle();
#if USE_WIFI
  setupWifi();
#endif
  showPins();
  Serial.println("Escribe mensajes aqui mismo para probar, por ejemplo: V20:0,60 (adelante) o TEST");
}

void loop() {
  while (Serial.available()) feedChar(serialBuffer, Serial.read());
  loopBle();
#if USE_WIFI
  loopWifi();
#endif
  uint32_t now = millis();
  loopSafety(now);
  loopSensor(now);
  loopRamp(now);
  loopHorn(now);
}
