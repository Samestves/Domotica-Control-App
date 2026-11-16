/*
  Casa Domótica · programa para el ESP32 de la maqueta
  ----------------------------------------------------
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
    V17       seguridad: 1 = armada, 0 = desarmada
    V18       avisos de texto (de la placa a la app)

  Seguridad (igual que en su versión de Blynk): con la seguridad armada, si el garaje
  o la puerta principal quedan abiertos 20 s, suena la sirena y las luces parpadean.

  Otros mensajes:
    CFG:V10:2:0:1   V10 pasa al GPIO 2, sin invertir (0) y activado (1). Se guarda en la placa.
    SYNC            la placa responde con el estado actual de todo
    TEST            mueve cada salida una por una para ver qué es cada cosa
    PING            la placa responde PONG

  Librerías: ESP32Servo (Kevin Harrington). Placa: "ESP32 Dev Module".
*/

#include <Arduino.h>
#include <Preferences.h>
#include <ESP32Servo.h>

// ============ CONFIGURACIÓN ============
#define DEVICE_NAME  "Casa Domotica"
#define USE_BLE      1        // 1 = conectar por Bluetooth LE
#define USE_WIFI     0        // 1 = conectar por Wi-Fi (escribe la red abajo)
const char* WIFI_SSID = "TuRed";
const char* WIFI_PASS = "TuClave";
const uint16_t TCP_PORT = 3333;
// =======================================

enum Kind { K_DOOR, K_BLIND, K_SIREN, K_LIGHT };

struct Channel {
  uint8_t vpin;      // pin virtual (el mismo número que en Blynk)
  int8_t  gpio;      // pin físico del ESP32
  Kind    kind;
  bool    inverted;  // true si se activa con señal baja (módulos de relé)
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
  {13, 12, K_LIGHT, false, true, "Luz bano",          0},
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
unsigned long graceStart = 0, lastFlash = 0;

void sendLine(const String& line);

// ---------- Utilidades ----------
Channel* findCh(int vpin) {
  for (int i = 0; i < N; i++) if (ch[i].vpin == vpin) return &ch[i];
  return nullptr;
}
int indexOf(Channel* c) { return c - ch; }
bool isServo(const Channel& c) { return c.kind == K_DOOR || c.kind == K_BLIND; }

void notice(const String& text) { sendLine("V" + String(VPIN_NOTICE) + ":" + text); }
void report(const Channel& c) { sendLine("V" + String(c.vpin) + ":" + String(c.value)); }

// Mismas reglas que gpioProblem() en la app. Devuelve el problema, o nullptr si el GPIO sirve.
const char* gpioProblem(int gpio, bool output) {
  if (gpio < 0 || gpio > 39) return "no existe (0 a 39)";
  if (gpio >= 6 && gpio <= 11) return "lo usa la memoria de la placa";
  if (gpio == 20 || gpio == 24 || (gpio >= 28 && gpio <= 31)) return "no existe en el ESP32";
  if (output && gpio >= 34) return "solo sirve como entrada";
  return nullptr;
}

// ---------- Salidas ----------
void writeDigital(const Channel& c, bool on) {
  if (c.enabled) digitalWrite(c.gpio, (on != c.inverted) ? HIGH : LOW);
}

int servoAngle(const Channel& c) {
  if (c.kind == K_DOOR) return c.value ? DOOR_OPEN : DOOR_CLOSED;
  return c.value;
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
void setSiren(bool on) {
  Channel* s = findCh(VPIN_SIREN);
  if (!s) return;
  s->value = on;
  writeDigital(*s, on);
}

void startAlarm(const String& reason) {
  sounding = true;
  armed = true;
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
  graceStart = 0;
  if (!on) stopAlarm();
  sendLine("V" + String(VPIN_ARMED) + ":" + String(on ? 1 : 0));
  notice(on ? "Seguridad armada" : "Seguridad desarmada");
}

bool entranceOpen() {
  Channel* garage = findCh(VPIN_GARAGE);
  Channel* front = findCh(VPIN_MAIN_DOOR);
  return (garage && garage->value) || (front && front->value);
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

// ---------- Mensajes de la app ----------
// Envía el estado real de la casa, para que la app muestre lo que hay y no lo que recuerda.
void sendState() {
  for (int i = 0; i < N; i++) if (ch[i].enabled) report(ch[i]);
  sendLine("V" + String(VPIN_ARMED) + ":" + String(armed ? 1 : 0));
}

// Mueve cada salida un momento para identificar qué hay en cada pin.
void runTest() {
  for (int i = 0; i < N; i++) {
    Channel& c = ch[i];
    if (!c.enabled) continue;
    sendLine("OK:TEST V" + String(c.vpin) + " " + c.name + " GPIO " + String(c.gpio));
    if (isServo(c)) {
      servos[i].write(90); delay(700);
    } else {
      writeDigital(c, true); delay(c.kind == K_SIREN ? 200 : 700);
    }
    applyOutput(c);
    if (c.kind == K_SIREN) writeDigital(c, sounding);
    delay(300);
  }
  sendLine("OK:TEST terminado");
}

// CFG:V<pin>:<gpio>:<invertido>[:<activado>]
void handleConfig(const String& line) {
  int a = line.indexOf(':', 5);
  int b = a < 0 ? -1 : line.indexOf(':', a + 1);
  if (a < 0 || b < 0) { sendLine("ERR:CFG " + line); return; }
  int e = line.indexOf(':', b + 1);

  Channel* c = findCh(line.substring(5, a).toInt());
  if (!c) { sendLine("ERR:CFG " + line); return; }
  int gpio = line.substring(a + 1, b).toInt();
  bool inverted = line.substring(b + 1, e < 0 ? line.length() : e).toInt() == 1;
  bool enabled = e < 0 ? true : line.substring(e + 1).toInt() == 1;

  const char* problem = gpioProblem(gpio, true);
  if (problem) { sendLine("ERR:GPIO " + String(gpio) + " " + problem); return; }

  bool changed = c->gpio != gpio || c->inverted != inverted || c->enabled != enabled;
  if (changed) {
    if (!isServo(*c)) writeDigital(*c, false);   // apaga el pin anterior
    c->gpio = gpio; c->inverted = inverted; c->enabled = enabled;
    setupChannel(*c);
    saveConfig(*c);
  }
  sendLine("OK:V" + String(c->vpin) + " GPIO " + String(gpio) + (inverted ? " inv" : "") + (enabled ? "" : " off"));
}

void handleLine(String line) {
  line.trim();
  if (line.length() == 0) return;

  if (line == "PING") { sendLine("PONG"); return; }
  if (line == "SYNC") { sendState(); return; }
  if (line == "TEST") { runTest(); return; }
  if (line.startsWith("CFG:V")) { handleConfig(line); return; }

  int colon = line.indexOf(':');
  if (line[0] != 'V' || colon < 0) { sendLine("ERR:no entiendo " + line); return; }
  int vpin = line.substring(1, colon).toInt();
  int value = line.substring(colon + 1).toInt();

  if (vpin == VPIN_ARMED) { setArmed(value == 1); return; }
  if (vpin == VPIN_SIREN) {
    if (value == 1) startAlarm("Alarma activada a mano");
    else setArmed(false);
    return;
  }
  if (vpin == VPIN_ALL_LIGHTS) {
    for (int i = 0; i < N; i++) if (ch[i].kind == K_LIGHT) setValue(ch[i], value);
    return;
  }

  Channel* c = findCh(vpin);
  if (!c) { sendLine("ERR:V" + String(vpin) + " no existe"); return; }
  if (!c->enabled) { sendLine("ERR:V" + String(vpin) + " desactivado"); return; }
  setValue(*c, value);
}

// Junta caracteres hasta completar una línea y entonces la procesa.
void feedChar(String& buffer, char k) {
  if (k == '\n') { handleLine(buffer); buffer = ""; }
  else if (k != '\r' && buffer.length() < 120) buffer += k;
}

// ---------- Bluetooth LE (servicio Nordic UART) ----------
#if USE_BLE
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#define NUS_SERVICE "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
const size_t BLE_CHUNK = 20;          // cabe en cualquier conexión BLE
BLECharacteristic* txChar = nullptr;
volatile bool bleConnected = false;
QueueHandle_t bleRxQueue;             // bytes recibidos; el Bluetooth corre en otra tarea
String bleBuffer;

class ServerCb : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConnected = true; }
  void onDisconnect(BLEServer* s) override { bleConnected = false; s->getAdvertising()->start(); }
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

// ---------- Wi-Fi (TCP en la red local) ----------
#if USE_WIFI
#include <WiFi.h>
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;
String tcpBuffer;

void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Conectando a Wi-Fi");
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) { delay(250); Serial.print("."); }
  if (WiFi.status() == WL_CONNECTED) {
    tcpServer.begin();
    tcpServer.setNoDelay(true);
    Serial.println("\nWi-Fi listo. En la app usa la IP " + WiFi.localIP().toString() + " y el puerto " + String(TCP_PORT));
  } else {
    Serial.println("\nNo se pudo conectar al Wi-Fi. Revisa WIFI_SSID y WIFI_PASS.");
  }
}

void loopWifi() {
  if (tcpServer.hasClient()) {
    if (tcpClient && tcpClient.connected()) tcpClient.stop();   // una app a la vez
    tcpClient = tcpServer.accept();
    tcpBuffer = "";
    sendLine("HELLO:" DEVICE_NAME);
  }
  while (tcpClient && tcpClient.connected() && tcpClient.available()) feedChar(tcpBuffer, tcpClient.read());
}
#endif

void sendLine(const String& line) {
  Serial.println("-> " + line);
#if USE_BLE
  bleSend(line + "\n");
#endif
#if USE_WIFI
  if (tcpClient && tcpClient.connected()) tcpClient.print(line + "\n");
#endif
}

// ---------- Programa principal ----------
String serialBuffer;

void setup() {
  loadConfig();
  // Luces y sirena apagadas lo antes posible; después, servos a su posición cerrada.
  for (int i = 0; i < N; i++) if (!isServo(ch[i])) setupChannel(ch[i]);

  Serial.begin(115200);
  delay(200);
  Serial.println("\n== " DEVICE_NAME " ==");

  for (int t = 0; t < 4; t++) ESP32PWM::allocateTimer(t);
  for (int i = 0; i < N; i++) if (isServo(ch[i])) setupChannel(ch[i]);

#if USE_BLE
  setupBle();
#endif
#if USE_WIFI
  setupWifi();
#endif
  Serial.println("Escribe mensajes aqui mismo para probar, por ejemplo: V10:1");
}

void loop() {
  // Mensajes escritos en el Monitor Serie (útil para probar sin teléfono)
  while (Serial.available()) feedChar(serialBuffer, Serial.read());
#if USE_BLE
  loopBle();
#endif
#if USE_WIFI
  loopWifi();
#endif

  unsigned long now = millis();
  loopSecurity(now);
  loopFlash(now);
}
