/*
  Casa Domótica · programa para el ESP32 de la maqueta · versión casa-0.7
  ----------------------------------------------------------------------
  Recibe mensajes de la app (por Bluetooth LE, Wi-Fi o el Monitor Serie) y mueve
  las salidas de la maqueta. También avisa a la app de cada cambio y de la alarma.

  Los pines virtuales son LOS MISMOS que usaba el grupo en Blynk, así que su
  documento «Conexiones GPIO» sigue valiendo:

    V0..V4    puertas (servo): 1 = abrir (90°), 0 = cerrar (0°)
              V0 garaje · V1 principal · V2 salón · V3 baño · V4 cuarto
    V5..V8    persianas (servo): 0..180
              V5 sala · V6 cuarto · V7 cocina 1 · V8 cocina 2
    V9        sirena: 1 = sonar a mano, 0 = apagar y desarmar
    V10..V15  luces: 1 / 0
              V10 sala 1 · V11 sala 2 · V12 cocina · V13 baño · V14 cuarto · V15 garaje
    V16       todas las luces: 1 / 0
    V17       seguridad: 1 = armada, 0 = desarmada (se recuerda aunque la placa se reinicie)
    V18       avisos de texto (de la placa a la app)

  Seguridad (igual que en su versión de Blynk): con la seguridad armada, si el garaje
  o la puerta principal quedan abiertos 20 s, suena la sirena y las luces parpadean.
  Una puerta marcada como «no conectada» (desactivada) cuenta como cerrada.

  Otros mensajes:
    CFG:V10:2:0:1   V10 pasa al GPIO 2, sin invertir (0) y activado (1). Se guarda en la placa.
                    En puertas y persianas, invertir = el servo gira al lado contrario.
                    Se rechazan los GPIO 1 y 3 (Monitor Serie), 6 a 11 (memoria) y uno que ya
                    use otro canal activo. El GPIO que se deja queda apagado o con el servo suelto.
    SYNC            la placa responde con el estado actual de todo
    TEST            mueve cada salida una por una para ver qué es cada cosa (ERR si ya hay una en curso)
    PING            la placa responde PONG
  Los números tienen que ser números: «V:1», «Vx:1» o «V10:abc» responden ERR y no mueven nada.
  Una línea de más de 120 letras se descarta entera.

  Clave de la casa (de 4 a 8 números). Por Bluetooth y Wi-Fi, la placa no obedece hasta recibirla:
    AUTH:123456     la app entrega la clave. Respuestas:
                      AUTH:OK          correcta
                      AUTH:MAL:2       incorrecta; quedan 2 intentos
                      AUTH:ESPERA:30   demasiados intentos; hay que esperar 30 s
                      AUTH:NUEVA       la casa todavía no tiene clave: hay que crearla
                      AUTH:PIDE        falta la clave (se envió una orden sin entregarla)
    CLAVE:123456    crea la clave, o la cambia si ya se entregó la actual. Responde AUTH:OK.
    Los intentos y la espera son de cada conexión (Bluetooth y Wi-Fi por separado) y se borran
    al desconectarse: un extraño no puede dejar afuera al dueño gastando los intentos.
    Por Bluetooth, si la casa ya tiene clave, un teléfono que no la entrega en 15 s se desconecta,
    para que no ocupe la única conexión.
    El Monitor Serie (cable USB) no necesita clave. Ahí, CLAVE:BORRAR deja la casa sin clave.
    Sin computadora: mantener presionado BOOT 5 s con la placa encendida también la borra
    (las luces parpadean 3 veces para confirmarlo).

  Wi-Fi: un teléfono a la vez. Si llega otro mientras el actual sigue usando la casa, el nuevo
  recibe «ERR:ya hay otro telefono conectado por Wi-Fi» y se cierra. Si el actual lleva más
  de 6 s sin mandar nada (la app manda PING cada 3 s), se cierra el actual y entra el nuevo.

  Cambios de casa-0.7 (respecto de alpha-0.6):
    - Intentos de clave por conexión (antes eran de toda la placa) y corte a los 15 s por Bluetooth.
    - Por Wi-Fi ya no se expulsa al teléfono conectado, y escribirle nunca frena la placa.
    - TEST ya no congela la placa: la alarma y el parpadeo siguen funcionando mientras corre.
    - Lo que quedó a medias de un teléfono (o un AUTH viejo) no pasa al siguiente.
    - Si se pierden letras de una orden (cola llena), se descarta la orden entera.
    - Números estrictos en las órdenes V y en CFG; CFG revisa GPIO repetidos y del Monitor Serie.
    - La seguridad armada se guarda y vuelve a quedar armada después de un reinicio.
    - Watchdog: si el programa se queda colgado 5 s, la placa se reinicia sola.

  Pines de arranque: la luz del baño (V13) está en el GPIO 12, que el ESP32 lee al encender.
  Si lo que tiene conectado lo sube a 3,3 V en ese momento, el ESP32 no arranca. Se deja así
  porque es el cableado del grupo; si pasa eso, muévanla al GPIO 23, 32 o 33 desde la app
  (mantener presionado el control) o con CFG:V13:23:0:1. La placa también lo avisa por Serie.

  Librerías: ESP32Servo (Kevin Harrington).
  Placa: "ESP32 Dev Module" con Partition Scheme "Huge APP" (Bluetooth y Wi-Fi juntos no caben en la normal).
*/

#include <Arduino.h>
#include <Preferences.h>
#include <ESP32Servo.h>

// ============ CONFIGURACIÓN ============
#define DEVICE_NAME  "Casa Domotica"
#define FW_VERSION   "casa-0.7"
#define USE_BLE      1        // 1 = conectar por Bluetooth LE
#define USE_WIFI     1        // 1 = conectar también por Wi-Fi
#define WIFI_PROPIA  1        // 1 = el ESP32 crea su propia red · 0 = se une a la red de abajo
// Red propia: el teléfono se conecta a «Casa Domotica» y la app usa la IP 192.168.4.1.
// La contraseña solo evita que cualquiera entre a la red; la clave de la casa es la que protege.
const char* AP_PASS   = "casadomotica";   // mínimo 8 letras
// Red de la casa o del colegio (solo si WIFI_PROPIA es 0)
const char* WIFI_SSID = "TuRed";
const char* WIFI_PASS = "TuClave";
const uint16_t TCP_PORT = 3333;
// =======================================

enum Kind { K_DOOR, K_BLIND, K_SIREN, K_LIGHT };

struct Channel {
  uint8_t vpin;      // pin virtual (el mismo número que en Blynk)
  int8_t  gpio;      // pin físico del ESP32
  Kind    kind;
  bool    inverted;  // luces y sirena: se activan con señal baja (relés). Servos: giran al lado contrario
  bool    enabled;   // false = no está conectado en la maqueta
  const char* name;
  int16_t value;     // puertas 0/1, persianas 0..180, luces y sirena 0/1
};

// Cableado de la maqueta, según «Conexiones GPIO - Casa Domótica con ESP32».
// Se puede corregir desde la app sin volver a cargar el programa.
Channel ch[] = {
  {0,  13, K_DOOR,  false, true, "Porton garaje",     0},
  {1,  14, K_DOOR,  false, true, "Puerta principal",  0},
  {2,  15, K_DOOR,  false, true, "Puerta salon",      0},
  {3,  16, K_DOOR,  false, true, "Puerta bano",       0},
  {4,  17, K_DOOR,  false, true, "Puerta cuarto",     0},
  {5,  18, K_BLIND, false, true, "Persiana sala",     0},
  {6,  19, K_BLIND, false, true, "Persiana cuarto",   0},
  {7,  21, K_BLIND, false, true, "Persiana cocina 1", 0},
  {8,  22, K_BLIND, false, true, "Persiana cocina 2", 0},
  {9,  27, K_SIREN, false, true, "Sirena",            0},
  {10,  2, K_LIGHT, false, true, "Luz sala 1",        0},   // GPIO 2 = LED azul de la placa
  {11,  4, K_LIGHT, false, true, "Luz sala 2",        0},
  {12,  5, K_LIGHT, false, true, "Luz cocina",        0},
  {13, 12, K_LIGHT, false, true, "Luz bano",          0},   // GPIO 12 = pin de arranque (ver arriba)
  {14, 25, K_LIGHT, false, true, "Luz cuarto",        0},
  {15, 26, K_LIGHT, false, true, "Luz garaje",        0},
};
const int N = sizeof(ch) / sizeof(ch[0]);

const uint8_t VPIN_GARAGE = 0, VPIN_MAIN_DOOR = 1, VPIN_SIREN = 9;
const uint8_t VPIN_ALL_LIGHTS = 16, VPIN_ARMED = 17, VPIN_NOTICE = 18;
const int DOOR_OPEN = 90, DOOR_CLOSED = 0;
const unsigned long GRACE_MS = 20000;   // tiempo para desarmar antes de que suene
const unsigned long FLASH_MS = 200;     // parpadeo de las luces con la alarma
const char* PREFS_NS = "casa2";

Servo servos[N];
Preferences prefs;

bool armed = false, sounding = false, flashOn = false;
bool savedArmed = false;                // lo guardado en la placa: se escribe solo cuando cambia
unsigned long graceStart = 0, lastFlash = 0;

// De dónde llegó un mensaje. Cada conexión entrega la clave por su cuenta.
enum Src : uint8_t { SRC_SERIAL, SRC_BLE, SRC_TCP };
volatile bool authed[3] = {true, false, false};   // el cable USB no necesita clave
String houseKey;                                  // "" = la casa todavía no tiene clave
const uint8_t MAX_FAILS = 3;
const unsigned long LOCK_MS = 30000;              // espera tras 3 claves incorrectas
const unsigned long RESET_HOLD_MS = 5000;         // BOOT presionado este tiempo borra la clave
const int BOOT_PIN = 0;
// Intentos fallidos y espera de cada conexión (no de toda la placa): así un extraño que
// gasta sus intentos por Bluetooth no bloquea al dueño, ni el del Bluetooth al del Wi-Fi.
uint8_t failCount[3] = {0, 0, 0};
unsigned long lockStart[3] = {0, 0, 0};           // 0 = sin bloqueo

// Línea que se está recibiendo de cada origen.
const unsigned int MAX_LINE = 120;
struct LineIn {
  String buf;
  bool skip = false;   // descartando hasta el próximo salto de línea (muy larga o incompleta)
};
LineIn inbox[3];

void sendLine(const String& line);
void reply(Src src, const String& line);

// ---------- Utilidades ----------
Channel* findCh(int vpin) {
  for (int i = 0; i < N; i++) if (ch[i].vpin == vpin) return &ch[i];
  return nullptr;
}
int indexOf(Channel* c) { return c - ch; }
bool isServo(const Channel& c) { return c.kind == K_DOOR || c.kind == K_BLIND; }

// Canal activo que ya usa este GPIO (sin contar a `except`), o nullptr.
Channel* gpioOwner(int gpio, const Channel* except) {
  for (int i = 0; i < N; i++) if (&ch[i] != except && ch[i].enabled && ch[i].gpio == gpio) return &ch[i];
  return nullptr;
}

// Número entero sin signo. A diferencia de toInt(), rechaza "", "abc", "1x" o "1:2" en vez de dar 0.
bool parseIntStrict(const String& s, int& out) {
  if (s.length() == 0 || s.length() > 6) return false;
  long v = 0;
  for (size_t i = 0; i < s.length(); i++) {
    if (!isDigit(s[i])) return false;
    v = v * 10 + (s[i] - '0');
  }
  out = (int)v;
  return true;
}

// Una conexión que empieza o termina: sin clave, sin intentos gastados y sin línea a medias.
void resetConn(Src src) {
  authed[src] = false;
  failCount[src] = 0;
  lockStart[src] = 0;
  inbox[src] = LineIn();
}

void notice(const String& text) { sendLine("V" + String(VPIN_NOTICE) + ":" + text); }
void report(const Channel& c) { sendLine("V" + String(c.vpin) + ":" + String(c.value)); }

// Mismas reglas que gpioProblem() en la app, más los GPIO 1 y 3. Devuelve el problema, o nullptr si el GPIO sirve.
const char* gpioProblem(int gpio, bool output) {
  if (gpio < 0 || gpio > 39) return "no existe (0 a 39)";
  if (gpio == 1 || gpio == 3) return "lo usa el Monitor Serie (cable USB)";
  if (gpio >= 6 && gpio <= 11) return "lo usa la memoria de la placa";
  if (gpio == 20 || gpio == 24 || (gpio >= 28 && gpio <= 31)) return "no existe en el ESP32";
  if (output && gpio >= 34) return "solo sirve como entrada";
  return nullptr;
}

// ---------- Salidas ----------
void writeDigital(const Channel& c, bool on) {
  if (c.enabled) digitalWrite(c.gpio, (on != c.inverted) ? HIGH : LOW);
}

// Ángulo real del servo. Invertido = montado al revés: usa el ángulo opuesto (180 - ángulo).
int servoAngle(const Channel& c) {
  int angle = c.kind == K_DOOR ? (c.value ? DOOR_OPEN : DOOR_CLOSED) : c.value;
  return c.inverted ? 180 - angle : angle;
}

// Lleva una salida a su valor guardado. Con la alarma sonando, las luces las maneja el parpadeo.
void applyOutput(Channel& c) {
  if (!c.enabled) return;
  if (isServo(c)) { servos[indexOf(&c)].write(servoAngle(c)); return; }
  if (c.kind == K_LIGHT && sounding) return;
  writeDigital(c, c.value == 1);
}

// Prepara el pin de un canal y lo deja en su valor actual.
void setupChannel(Channel& c) {
  int i = indexOf(&c);
  if (isServo(c) && servos[i].attached()) servos[i].detach();
  if (!c.enabled) return;
  if (isServo(c)) {
    servos[i].setPeriodHertz(50);
    servos[i].attach(c.gpio, 500, 2400);
  } else {
    pinMode(c.gpio, OUTPUT);
  }
  applyOutput(c);
}

// Deja en reposo el GPIO que este canal deja de usar (con su configuración de antes), si ningún
// otro canal activo lo usa. Luces y sirena: apagadas, LOW (HIGH si el canal era invertido, porque
// en un relé activo en bajo LOW lo encendería). Servos: soltados y sin pulsos, no hacen fuerza.
void releaseGpio(Channel& c) {
  if (gpioOwner(c.gpio, &c)) return;
  int i = indexOf(&c);
  if (isServo(c) && servos[i].attached()) servos[i].detach();
  pinMode(c.gpio, OUTPUT);
  digitalWrite(c.gpio, (!isServo(c) && c.inverted) ? HIGH : LOW);
}

void setValue(Channel& c, int value) {
  switch (c.kind) {
    case K_DOOR:  c.value = value > 0 ? 1 : 0; break;
    case K_BLIND: c.value = constrain(value, 0, 180); break;
    default:      c.value = value == 1 ? 1 : 0; break;
  }
  applyOutput(c);
  report(c);
}

void restoreLights() {
  for (int i = 0; i < N; i++) if (ch[i].kind == K_LIGHT) writeDigital(ch[i], ch[i].value == 1);
}

// ---------- Seguridad ----------
// Guarda si la seguridad está armada, solo cuando cambia (para no gastar la memoria de la placa).
void saveArmed() {
  if (armed == savedArmed) return;
  prefs.begin(PREFS_NS, false);
  prefs.putBool("armada", armed);
  prefs.end();
  savedArmed = armed;
}

void setSiren(bool on) {
  Channel* s = findCh(VPIN_SIREN);
  if (!s) return;
  s->value = on;
  writeDigital(*s, on);
}

void startAlarm(const String& reason) {
  sounding = true;
  armed = true;
  saveArmed();
  graceStart = 0;
  lastFlash = 0;
  setSiren(true);
  sendLine("V" + String(VPIN_SIREN) + ":1");
  sendLine("V" + String(VPIN_ARMED) + ":1");
  notice(reason);
}

void stopAlarm() {
  if (!sounding) return;
  sounding = false;
  setSiren(false);
  restoreLights();
  sendLine("V" + String(VPIN_SIREN) + ":0");
}

void setArmed(bool on) {
  armed = on;
  saveArmed();
  graceStart = 0;
  if (!on) stopAlarm();
  sendLine("V" + String(VPIN_ARMED) + ":" + String(on ? 1 : 0));
  notice(on ? "Seguridad armada" : "Seguridad desarmada");
}

// Una puerta desactivada («no conectada») no cuenta como abierta.
bool entranceOpen() {
  Channel* garage = findCh(VPIN_GARAGE);
  Channel* front = findCh(VPIN_MAIN_DOOR);
  return (garage && garage->enabled && garage->value) || (front && front->enabled && front->value);
}

void loopSecurity(unsigned long now) {
  if (!armed || sounding) return;
  if (entranceOpen()) {
    if (graceStart == 0) {
      graceStart = now | 1;   // nunca 0, que significa «sin contar»
      notice("Acceso detectado: " + String(GRACE_MS / 1000) + " s para desarmar");
    } else if (now - graceStart >= GRACE_MS) {
      startAlarm("Alarma sonando: entrada abierta");
    }
  } else if (graceStart != 0) {
    graceStart = 0;
    notice("Entradas cerradas");
  }
}

void loopFlash(unsigned long now) {
  if (!sounding || now - lastFlash < FLASH_MS) return;
  lastFlash = now;
  flashOn = !flashOn;
  for (int i = 0; i < N; i++) if (ch[i].kind == K_LIGHT) writeDigital(ch[i], flashOn);
}

// ---------- Configuración guardada ----------
void loadConfig() {
  prefs.begin(PREFS_NS, true);
  for (int i = 0; i < N; i++) {
    String k = "v" + String(ch[i].vpin);
    ch[i].gpio = prefs.getChar((k + "g").c_str(), ch[i].gpio);
    ch[i].inverted = prefs.getBool((k + "i").c_str(), ch[i].inverted);
    ch[i].enabled = prefs.getBool((k + "e").c_str(), ch[i].enabled);
  }
  prefs.end();
}

void saveConfig(const Channel& c) {
  prefs.begin(PREFS_NS, false);
  String k = "v" + String(c.vpin);
  prefs.putChar((k + "g").c_str(), c.gpio);
  prefs.putBool((k + "i").c_str(), c.inverted);
  prefs.putBool((k + "e").c_str(), c.enabled);
  prefs.end();
}

// La seguridad queda como estaba antes de apagarse o reiniciarse la placa.
void loadArmed() {
  prefs.begin(PREFS_NS, true);
  armed = savedArmed = prefs.getBool("armada", false);
  prefs.end();
}

// Avisos por Serie sobre pines delicados del cableado actual.
void warnPins() {
  for (int i = 0; i < N; i++) {
    Channel& c = ch[i];
    if (!c.enabled) continue;
    String who = "Aviso: V" + String(c.vpin) + " " + c.name + " usa el GPIO " + String(c.gpio);
    if (c.gpio == 12)
      Serial.println(who + ", un pin de arranque: si lo que tiene conectado lo sube a 3,3 V al encender, "
                     "el ESP32 no arranca. Si pasa eso, muevelo al GPIO 23, 32 o 33 desde la app (CFG:V"
                     + String(c.vpin) + ":23:" + String(c.inverted ? 1 : 0) + ":1).");
    const char* problem = gpioProblem(c.gpio, true);
    if (problem) Serial.println(who + ": " + problem + ". Cambialo desde la app.");
    Channel* other = gpioOwner(c.gpio, &c);
    if (other && other > &c) Serial.println(who + ", igual que V" + String(other->vpin) + " " + other->name + ". Cambia uno desde la app.");
  }
}

// ---------- Clave de la casa ----------
void loadKey() {
  prefs.begin(PREFS_NS, true);
  houseKey = prefs.getString("clave", "");
  prefs.end();
}

// Guarda la clave nueva ("" = sin clave). Las conexiones abiertas tendrán que entregarla otra vez.
void storeKey(const String& key, Src keep) {
  houseKey = key;
  prefs.begin(PREFS_NS, false);
  prefs.putString("clave", key);
  prefs.end();
  for (int s = SRC_BLE; s <= SRC_TCP; s++) if (s != keep) authed[s] = false;
}

bool validKey(const String& k) {
  if (k.length() < 4 || k.length() > 8) return false;
  for (size_t i = 0; i < k.length(); i++) if (!isDigit(k[i])) return false;
  return true;
}

// Segundos que faltan del bloqueo de esta conexión por intentos fallidos (0 = sin bloqueo).
unsigned long lockLeft(Src src, unsigned long now) {
  if (lockStart[src] == 0) return 0;
  unsigned long elapsed = now - lockStart[src];
  if (elapsed >= LOCK_MS) { lockStart[src] = 0; return 0; }
  return (LOCK_MS - elapsed + 999) / 1000;
}

// AUTH:<clave>
void handleAuth(Src src, const String& given) {
  if (houseKey.length() == 0) { reply(src, "AUTH:NUEVA"); return; }
  unsigned long wait = lockLeft(src, millis());
  if (wait) { reply(src, "AUTH:ESPERA:" + String(wait)); return; }
  if (given == houseKey) {
    failCount[src] = 0;
    authed[src] = true;
    reply(src, "AUTH:OK");
    return;
  }
  authed[src] = false;
  if (given.length() == 0) { reply(src, "AUTH:PIDE"); return; }   // la app aún no la conoce: no cuenta como intento
  if (++failCount[src] >= MAX_FAILS) {
    failCount[src] = 0;
    lockStart[src] = millis() | 1;   // nunca 0, que significa «sin bloqueo»
    reply(src, "AUTH:ESPERA:" + String(LOCK_MS / 1000));
  } else {
    reply(src, "AUTH:MAL:" + String(MAX_FAILS - failCount[src]));
  }
}

// CLAVE:<nueva>. Crear la primera no pide nada; cambiarla exige haber entregado la actual.
void handleNewKey(Src src, const String& key) {
  if (src == SRC_SERIAL && key == "BORRAR") {
    storeKey("", SRC_SERIAL);
    reply(src, "OK:la casa quedo sin clave");
    return;
  }
  if (houseKey.length() && !authed[src]) { reply(src, "AUTH:PIDE"); return; }
  if (!validKey(key)) { reply(src, "ERR:la clave debe tener de 4 a 8 numeros"); return; }
  storeKey(key, src);
  authed[src] = true;
  reply(src, "AUTH:OK");
  notice("Clave de la casa guardada");
}

// Mantener BOOT presionado 5 s borra la clave, por si se olvida y no hay computadora a mano.
// Las luces parpadean 3 veces para confirmarlo, sin frenar el resto del programa (antes eran delay()).
void loopResetButton(unsigned long now) {
  static unsigned long pressStart = 0, blinkAt = 0;
  static bool done = false;
  static int8_t blinkStep = -1;   // -1 = sin parpadeo · 0 a 5 = encendidas en los pasos pares
  if (blinkStep >= 0 && now - blinkAt >= 250) {
    blinkAt = now;
    if (++blinkStep >= 6) { blinkStep = -1; restoreLights(); }
    else for (int i = 0; i < N; i++) if (ch[i].kind == K_LIGHT) writeDigital(ch[i], blinkStep % 2 == 0);
  }
  for (int i = 0; i < N; i++) if (ch[i].enabled && ch[i].gpio == BOOT_PIN) return;   // el pin se usa para otra cosa
  if (digitalRead(BOOT_PIN) == HIGH) { pressStart = 0; done = false; return; }
  if (pressStart == 0) pressStart = now | 1;
  if (done || now - pressStart < RESET_HOLD_MS) return;
  done = true;
  storeKey("", SRC_SERIAL);
  Serial.println("Clave borrada con el boton BOOT");
  blinkStep = 0;
  blinkAt = now;
  for (int i = 0; i < N; i++) if (ch[i].kind == K_LIGHT) writeDigital(ch[i], true);
}

// ---------- Mensajes de la app ----------
// Envía el estado real de la casa, para que la app muestre lo que hay y no lo que recuerda.
void sendState() {
  for (int i = 0; i < N; i++) if (ch[i].enabled) report(ch[i]);
  sendLine("V" + String(VPIN_ARMED) + ":" + String(armed ? 1 : 0));
}

// Prueba de salidas (TEST): mueve cada salida un momento para identificar qué hay en cada pin.
// Mismos pasos y tiempos que antes, pero atendida desde loop(): la alarma, el parpadeo y los
// mensajes siguen funcionando mientras tanto. Cada salida vuelve a su valor al terminar su paso.
int testIndex = -1;            // canal que se está probando (-1 = no hay prueba)
uint8_t testPhase = 0;         // 0 = empezar el siguiente canal · 1 = encendido · 2 = pausa
unsigned long testAt = 0, testWait = 0;

void startTest(Src src) {
  if (testIndex >= 0) { reply(src, "ERR:ya hay una prueba de salidas en curso; espera a que termine"); return; }
  testIndex = 0;
  testPhase = 0;
}

void loopTest(unsigned long now) {
  if (testIndex < 0) return;
  if (testPhase != 0 && now - testAt < testWait) return;
  if (testPhase == 0) {
    while (testIndex < N && !ch[testIndex].enabled) testIndex++;
    if (testIndex >= N) { testIndex = -1; sendLine("OK:TEST terminado"); return; }
    Channel& c = ch[testIndex];
    sendLine("OK:TEST V" + String(c.vpin) + " " + c.name + " GPIO " + String(c.gpio));
    if (isServo(c)) {
      servos[testIndex].write(90); testWait = 700;
    } else {
      writeDigital(c, true); testWait = c.kind == K_SIREN ? 200 : 700;
    }
    testPhase = 1;
  } else if (testPhase == 1) {
    Channel& c = ch[testIndex];
    applyOutput(c);
    if (c.kind == K_SIREN) writeDigital(c, sounding);
    testWait = 300;
    testPhase = 2;
  } else {
    testIndex++;
    testPhase = 0;
    return;   // el siguiente canal empieza en la próxima vuelta
  }
  testAt = now;
}

// CFG:V<pin>:<gpio>:<invertido>[:<activado>]
void handleConfig(const String& line) {
  int a = line.indexOf(':', 5);
  int b = a < 0 ? -1 : line.indexOf(':', a + 1);
  if (a < 0 || b < 0) { sendLine("ERR:CFG " + line); return; }
  int e = line.indexOf(':', b + 1);

  // Todo tiene que ser número (antes «abc» valía 0, es decir, GPIO 0). Invertir y activar: 0 o 1.
  int vpin, gpio, inv, on = 1;
  bool ok = parseIntStrict(line.substring(5, a), vpin) && parseIntStrict(line.substring(a + 1, b), gpio) &&
            parseIntStrict(line.substring(b + 1, e < 0 ? line.length() : e), inv) && inv <= 1 &&
            (e < 0 || (parseIntStrict(line.substring(e + 1), on) && on <= 1));
  Channel* c = ok ? findCh(vpin) : nullptr;
  if (!c) { sendLine("ERR:CFG " + line); return; }
  bool inverted = inv == 1, enabled = on == 1;

  const char* problem = gpioProblem(gpio, true);
  if (problem) { sendLine("ERR:GPIO " + String(gpio) + " " + problem); return; }
  // Dos salidas activas en el mismo GPIO se pisarían: se rechaza y se dice cuál lo tiene.
  Channel* other = enabled ? gpioOwner(gpio, c) : nullptr;
  if (other) { sendLine("ERR:GPIO " + String(gpio) + " ya lo usa V" + String(other->vpin) + " " + other->name); return; }

  bool changed = c->gpio != gpio || c->inverted != inverted || c->enabled != enabled;
  if (changed) {
    if (c->enabled && (c->gpio != gpio || !enabled)) releaseGpio(*c);   // el pin anterior queda en reposo
    bool wasOn = c->value != 0;
    c->gpio = gpio; c->inverted = inverted; c->enabled = enabled;
    // Desactivado = cerrado / apagado: así una puerta «no conectada» no dispara la alarma.
    // La sirena no: su valor dice si la alarma está sonando, aunque no tenga sirena conectada.
    if (!enabled && c->kind != K_SIREN) c->value = 0;
    setupChannel(*c);
    saveConfig(*c);
    if (!enabled && c->kind != K_SIREN && wasOn) report(*c);
  }
  sendLine("OK:V" + String(c->vpin) + " GPIO " + String(gpio) + (inverted ? " inv" : "") + (enabled ? "" : " off"));
}

void handleLine(Src src, String line) {
  line.trim();
  if (line.length() == 0) return;

  if (line == "PING") { reply(src, "PONG"); return; }
  if (line.startsWith("AUTH:")) { handleAuth(src, line.substring(5)); return; }
  if (line.startsWith("CLAVE:")) { handleNewKey(src, line.substring(6)); return; }
  if (!authed[src]) { reply(src, houseKey.length() ? "AUTH:PIDE" : "AUTH:NUEVA"); return; }

  if (line == "SYNC") { sendState(); return; }
  if (line == "TEST") { startTest(src); return; }
  if (line.startsWith("CFG:V")) { handleConfig(line); return; }

  // V<pin>:<valor>, los dos números de verdad: «V:1» o «Vx:1» ya no abren el garaje (antes valían V0).
  int colon = line.indexOf(':');
  int vpin, value;
  if (line[0] != 'V' || colon < 0 || !parseIntStrict(line.substring(1, colon), vpin) ||
      !parseIntStrict(line.substring(colon + 1), value)) {
    sendLine("ERR:no entiendo " + line);
    return;
  }

  if (vpin == VPIN_ARMED) { setArmed(value == 1); return; }
  if (vpin == VPIN_SIREN) {
    if (value == 1) startAlarm("Alarma activada a mano");
    else setArmed(false);
    return;
  }
  if (vpin == VPIN_ALL_LIGHTS) {
    for (int i = 0; i < N; i++) if (ch[i].kind == K_LIGHT && ch[i].enabled) setValue(ch[i], value);
    return;
  }

  Channel* c = findCh(vpin);
  if (!c) { sendLine("ERR:V" + String(vpin) + " no existe"); return; }
  if (!c->enabled) {
    // Desactivado cuenta como cerrado / apagado: pedirle 0 solo lo confirma; otro valor es un error.
    if (value == 0) report(*c);
    else sendLine("ERR:V" + String(vpin) + " desactivado");
    return;
  }
  setValue(*c, value);
}

// Junta caracteres hasta completar una línea y entonces la procesa.
// Una línea de más de 120 caracteres se descarta entera (antes se cortaba y se ejecutaba).
void feedChar(Src src, char k) {
  LineIn& in = inbox[src];
  if (k == '\n') {
    bool skipped = in.skip;
    String line = in.buf;
    in = LineIn();
    if (!skipped) handleLine(src, line);
    return;
  }
  if (k == '\r' || in.skip) return;
  if (in.buf.length() >= MAX_LINE) {
    in.buf = "";
    in.skip = true;
    reply(src, "ERR:linea demasiado larga (maximo 120 caracteres)");
    return;
  }
  in.buf += k;
}

// Se perdieron caracteres de la línea en curso: se descarta entera en vez de ejecutarla incompleta.
void dropLine(Src src) {
  LineIn& in = inbox[src];
  if (in.skip) return;   // ya se estaba descartando
  in.buf = "";
  in.skip = true;
  reply(src, "ERR:se perdio parte de un mensaje; no se ejecuto");
}

// ---------- Bluetooth LE (servicio Nordic UART) ----------
#if USE_BLE
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <esp_gap_ble_api.h>
#define NUS_SERVICE "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
const size_t BLE_CHUNK = 20;          // cabe en cualquier conexión BLE
const unsigned long BLE_AUTH_MS = 15000;   // tiempo para entregar la clave antes de que se corte
BLECharacteristic* txChar = nullptr;
volatile bool bleConnected = false;
// Bytes recibidos; el Bluetooth corre en otra tarea. Cada byte lleva el número de la conexión que lo
// mandó (bits 0 a 6) y, en el bit 7, si justo antes se perdieron bytes porque la cola estaba llena.
// Así loop() descarta lo que quedó en la cola del teléfono anterior (por ejemplo, un AUTH viejo).
struct BleByte { uint8_t ch; uint8_t tag; };
const uint8_t BLE_LOST = 0x80;
QueueHandle_t bleRxQueue;
volatile uint8_t bleSession = 0;      // cambia con cada conexión y desconexión (tarea del Bluetooth)
uint8_t bleSessionSeen = 0;           // la última conexión que atendió loop()
bool bleLost = false;                 // se perdieron bytes (solo lo usa la tarea del Bluetooth)
esp_bd_addr_t bleRemote;              // teléfono conectado, para poder desconectarlo
unsigned long bleUnauthedSince = 0;   // desde cuándo el teléfono conectado no entrega la clave

class ServerCb : public BLEServerCallbacks {
  // Cada teléfono que se conecta tiene que entregar la clave de nuevo.
  // Primero cambia el número de conexión y después bleConnected (loop() los lee al revés).
  void onConnect(BLEServer*, esp_ble_gatts_cb_param_t* param) override {
    memcpy(bleRemote, param->connect.remote_bda, sizeof(esp_bd_addr_t));
    authed[SRC_BLE] = false;
    bleLost = false;
    bleSession = (bleSession + 1) & 0x7F;
    bleConnected = true;
  }
  void onDisconnect(BLEServer* s, esp_ble_gatts_cb_param_t*) override {
    bleConnected = false;
    authed[SRC_BLE] = false;
    bleLost = false;
    bleSession = (bleSession + 1) & 0x7F;
    s->getAdvertising()->start();
  }
};
class RxCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    const uint8_t* data = c->getData();
    for (size_t i = 0; i < c->getLength(); i++) {
      BleByte b = {data[i], (uint8_t)(bleSession | (bleLost ? BLE_LOST : 0))};
      bleLost = xQueueSend(bleRxQueue, &b, 0) != pdTRUE;   // cola llena: el próximo byte lo avisa
    }
  }
};

void setupBle() {
  bleRxQueue = xQueueCreate(512, sizeof(BleByte));
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

// Conexión nueva o desconexión: se empieza de cero (clave, intentos, línea a medias y plazo).
void bleCheckSession() {
  uint8_t s = bleSession;
  if (s == bleSessionSeen) return;
  bleSessionSeen = s;
  resetConn(SRC_BLE);
  bleUnauthedSince = 0;
}

void loopBle() {
  bool connected = bleConnected;   // antes que el número de conexión (ver onConnect)
  bleCheckSession();
  BleByte b;
  // Como mucho 128 bytes por vuelta, para que una ráfaga no frene la alarma ni el watchdog.
  for (int n = 0; n < 128 && xQueueReceive(bleRxQueue, &b, 0) == pdTRUE; n++) {
    bleCheckSession();
    if ((b.tag & 0x7F) != bleSessionSeen) continue;   // del teléfono anterior: se descarta
    if (b.tag & BLE_LOST) dropLine(SRC_BLE);
    feedChar(SRC_BLE, (char)b.ch);
  }
  // Con la casa ya con clave, un teléfono que no la entrega en 15 s se desconecta.
  // Sin clave no: el primer teléfono necesita tiempo para crearla.
  if (!connected || authed[SRC_BLE] || houseKey.length() == 0) { bleUnauthedSince = 0; return; }
  unsigned long now = millis();
  if (bleUnauthedSince == 0) {
    bleUnauthedSince = now | 1;
  } else if (now - bleUnauthedSince >= BLE_AUTH_MS) {
    Serial.println("Bluetooth: el telefono no entrego la clave en 15 s; se desconecta");
    esp_ble_gap_disconnect(bleRemote);
    bleUnauthedSince = 0;   // si no se cortara, se intenta otra vez en 15 s
  }
}

// Envía en trozos pequeños para que los mensajes largos no se corten.
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
#endif

// ---------- Wi-Fi (TCP) ----------
#if USE_WIFI
#include <WiFi.h>
#include <errno.h>
#include <lwip/sockets.h>
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;
bool tcpOpen = false;                    // hay un teléfono conectado por Wi-Fi
unsigned long tcpLastRx = 0;             // última vez que ese teléfono mandó algo
// Lo que falta enviarle. Se envía sin esperar en cada vuelta de loop(): antes, un teléfono que
// salía de rango dejaba la placa congelada hasta 10 s en cada línea.
String tcpOut;
unsigned long tcpOutAt = 0;              // última vez que salió algo (o que empezó a haber algo)
const unsigned long TCP_IDLE_MS = 6000;  // la app manda PING cada 3 s: 6 s callado = teléfono perdido
const unsigned long TCP_STUCK_MS = 5000; // tanto tiempo sin poder enviarle nada: se cierra
const size_t TCP_OUT_MAX = 2048;

void setupWifi() {
#if WIFI_PROPIA
  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(DEVICE_NAME, AP_PASS)) { Serial.println("No se pudo crear la red Wi-Fi"); return; }
  Serial.println("Wi-Fi propio listo: conecta el telefono a la red \"" DEVICE_NAME "\" y en la app usa la IP "
                 + WiFi.softAPIP().toString() + " y el puerto " + String(TCP_PORT));
#else
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Conectando a Wi-Fi");
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) { delay(250); Serial.print("."); }
  if (WiFi.status() != WL_CONNECTED) { Serial.println("\nNo se pudo conectar al Wi-Fi. Revisa WIFI_SSID y WIFI_PASS."); return; }
  Serial.println("\nWi-Fi listo. En la app usa la IP " + WiFi.localIP().toString() + " y el puerto " + String(TCP_PORT));
#endif
  tcpServer.begin();
  tcpServer.setNoDelay(true);
}

// Cierra la conexión Wi-Fi actual y olvida su clave, sus intentos y lo que quedaba por enviar.
void tcpClose(const char* why) {
  tcpClient.stop();
  tcpOpen = false;
  tcpOut = "";
  resetConn(SRC_TCP);
  Serial.println(String("Wi-Fi: ") + why);
}

void tcpQueue(const String& line) {
  if (!tcpOpen) return;
  if (tcpOut.length() == 0) tcpOutAt = millis();
  tcpOut += line;
  tcpOut += '\n';
}

// Envía lo pendiente sin quedarse esperando; lo que no cupo sale en la próxima vuelta, en orden.
void tcpFlush() {
  if (!tcpOpen || tcpOut.length() == 0) return;
  int sent = lwip_send(tcpClient.fd(), tcpOut.c_str(), tcpOut.length(), MSG_DONTWAIT);
  if (sent > 0) { tcpOut.remove(0, sent); tcpOutAt = millis(); return; }
  if (sent < 0 && errno != EAGAIN && errno != EWOULDBLOCK) { tcpClose("se perdio la conexion"); return; }
  if (millis() - tcpOutAt >= TCP_STUCK_MS || tcpOut.length() > TCP_OUT_MAX) tcpClose("el telefono no recibe; se cierra la conexion");
}

void loopWifi() {
  if (tcpOpen && !tcpClient.connected()) tcpClose("el telefono se desconecto");
  if (tcpServer.hasClient()) {
    WiFiClient incoming = tcpServer.accept();
    unsigned long now = millis();
    if (tcpOpen && authed[SRC_TCP] && now - tcpLastRx < TCP_IDLE_MS) {
      // Ya hay un teléfono con la clave que sigue activo: no se le quita la conexión; se rechaza al nuevo.
      // Se lee lo que haya mandado, porque cerrar con datos sin leer corta brusco y el aviso no llega.
      for (int n = 0; n < 256 && incoming.available(); n++) incoming.read();
      const char* busy = "ERR:ya hay otro telefono conectado por Wi-Fi\n";
      lwip_send(incoming.fd(), busy, strlen(busy), MSG_DONTWAIT);
      incoming.stop();
      Serial.println("Wi-Fi: se rechazo otro telefono (ya hay uno conectado)");
    } else {
      // El anterior no tenía la clave o lleva más de 6 s callado (salió de rango): entra el nuevo.
      if (tcpOpen) tcpClose("llego otro telefono; se cierra el anterior (sin clave o sin responder)");
      tcpClient = incoming;
      tcpOpen = true;
      tcpLastRx = now;
      resetConn(SRC_TCP);   // cada teléfono entrega la clave de nuevo, con sus propios intentos
      reply(SRC_TCP, "HELLO:" DEVICE_NAME);
    }
  }
  // Como mucho 128 bytes por vuelta, igual que por Bluetooth.
  for (int n = 0; n < 128 && tcpOpen && tcpClient.available(); n++) {
    tcpLastRx = millis();
    feedChar(SRC_TCP, tcpClient.read());
  }
  tcpFlush();
}
#endif

// Respuesta solo para quien preguntó (por ejemplo, el resultado de la clave).
void reply(Src src, const String& line) {
  Serial.println("-> " + line);
#if USE_BLE
  if (src == SRC_BLE) bleSend(line + "\n");
#endif
#if USE_WIFI
  if (src == SRC_TCP) tcpQueue(line);
#endif
}

// Aviso para todos: el Monitor Serie y cada teléfono que ya entregó la clave.
void sendLine(const String& line) {
  Serial.println("-> " + line);
#if USE_BLE
  if (authed[SRC_BLE]) bleSend(line + "\n");
#endif
#if USE_WIFI
  if (authed[SRC_TCP]) tcpQueue(line);
#endif
}

// ---------- Programa principal ----------
void setup() {
  loadConfig();
  loadKey();
  loadArmed();
  pinMode(BOOT_PIN, INPUT_PULLUP);
  // Luces y sirena apagadas lo antes posible; después, servos a su posición cerrada.
  for (int i = 0; i < N; i++) if (!isServo(ch[i])) setupChannel(ch[i]);

  Serial.begin(115200);
  delay(200);
  Serial.println("\n== " DEVICE_NAME " (" FW_VERSION ") ==");

  for (int t = 0; t < 4; t++) ESP32PWM::allocateTimer(t);
  for (int i = 0; i < N; i++) if (isServo(ch[i])) setupChannel(ch[i]);

#if USE_BLE
  setupBle();
#endif
#if USE_WIFI
  setupWifi();
#endif
  Serial.println(houseKey.length() ? "La casa tiene clave." : "La casa no tiene clave: el primer telefono que se conecte la crea.");
  if (armed) Serial.println("La seguridad estaba armada antes de reiniciar: sigue armada.");
  warnPins();
  Serial.println("Escribe mensajes aqui mismo para probar, por ejemplo: V10:1");
  // Watchdog del loop: si algo lo deja colgado 5 s, la placa se reinicia sola.
  // Nada en loop() espera más de unas decenas de milisegundos.
  enableLoopWDT();
}

void loop() {
  // Mensajes escritos en el Monitor Serie (útil para probar sin teléfono)
  while (Serial.available()) feedChar(SRC_SERIAL, Serial.read());
#if USE_BLE
  loopBle();
#endif
#if USE_WIFI
  loopWifi();
#endif

  unsigned long now = millis();
  loopSecurity(now);
  loopFlash(now);
  loopTest(now);
  loopResetButton(now);
}
