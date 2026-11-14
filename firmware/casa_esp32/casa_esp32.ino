/*
  Casa Domótica · programa para ESP32
  -----------------------------------
  Recibe mensajes de la app (por Bluetooth LE, Wi-Fi o el Monitor Serie) y mueve
  las salidas de la maqueta. También envía lecturas y alarmas de vuelta a la app.

  Mensajes (una línea cada uno):
    V1:1            enciende la luz de la sala      V3:90     puerta (servo) a 90°
    V7:1 / V7:0     arma / desarma la alarma        V6:Hola   texto para la LCD
    CFG:V1:23:1:1   V1 pasa al GPIO 23, invertido (1) y activado (1). Se guarda en la placa.
    SYNC            la placa responde con el estado actual de todo
    TEST            activa cada salida una por una para ver qué es cada cosa
    PING            la placa responde PONG

  Librerías (Arduino IDE → Gestor de librerías):
    - ESP32Servo (Kevin Harrington)                       obligatoria
    - LiquidCrystal I2C (Frank de Brabander)              solo si USE_LCD = 1
    - DHT sensor library (Adafruit)                       solo si USE_DHT = 1

  Placa: "ESP32 Dev Module". Si usas Bluetooth y Wi-Fi a la vez, elige en
  Herramientas → Partition Scheme → "Huge APP (3MB No OTA)", porque el programa es grande.
*/

#include <Arduino.h>
#include <Preferences.h>
#include <ESP32Servo.h>

// ============ CONFIGURACIÓN: cambia esto ============
#define DEVICE_NAME  "Casa Domotica"
#define USE_BLE      1        // 1 = conectar por Bluetooth LE
#define USE_WIFI     0        // 1 = conectar por Wi-Fi (escribe tu red abajo)
#define USE_LCD      0        // 1 = hay una pantalla LCD I2C (SDA 21, SCL 22)
#define USE_DHT      0        // 1 = hay un sensor de temperatura DHT11/DHT22
const char* WIFI_SSID = "TuRed";
const char* WIFI_PASS = "TuClave";
const uint16_t TCP_PORT = 3333;
#define LCD_ADDR     0x27     // dirección típica; algunas pantallas usan 0x3F
#define DHT_PIN      4
#define DHT_TYPE     DHT11
// ====================================================

enum Kind { K_SWITCH, K_SERVO, K_BUZZER, K_SENSOR };

struct Channel {
  uint8_t vpin;      // pin virtual que usa la app (V1, V2...)
  int8_t  gpio;      // pin físico del ESP32
  Kind    kind;
  bool    inverted;  // true si se activa con señal baja (casi todos los módulos de relé)
  bool    enabled;   // false = no conectado: la placa lo ignora
  const char* name;
  int16_t value;     // último valor: 0/1 en interruptores, ángulo en servos
};

// Tabla de la maqueta. Debe coincidir con los cables reales.
// Todo esto se puede cambiar desde la app sin volver a cargar el programa.
// El sensor de movimiento viene desactivado: si no hay sensor, su pin queda
// «al aire», lee valores al azar y dispararía la alarma sola.
Channel ch[] = {
  {1,  23, K_SWITCH, true,  true,  "Luz sala",          0},
  {2,  19, K_SWITCH, true,  true,  "Luz cocina",        0},
  {8,  18, K_SWITCH, true,  true,  "Luz cuarto",        0},
  {9,   5, K_SWITCH, true,  true,  "Ventilador",        0},
  {3,  13, K_SERVO,  false, true,  "Puerta",            0},
  {4,  14, K_SERVO,  false, true,  "Ventana",           0},
  {5,  27, K_BUZZER, false, true,  "Timbre",            0},
  {11, 34, K_SENSOR, false, false, "Sensor movimiento", 0},
};
const int N = sizeof(ch) / sizeof(ch[0]);
const uint8_t VPIN_BUZZER = 5, VPIN_LCD = 6, VPIN_ALARM = 7, VPIN_TEMP = 10, VPIN_MOTION = 11;

Servo servos[N];
Preferences prefs;

bool armed = false, triggered = false;
unsigned long buzzerOffAt = 0, lastSensorAt = 0, lastTempAt = 0;

#if USE_LCD
  #include <Wire.h>
  #include <LiquidCrystal_I2C.h>
  LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);
#endif
#if USE_DHT
  #include <DHT.h>
  DHT dht(DHT_PIN, DHT_TYPE);
#endif

void sendLine(const String& line);

// ---------- Salidas ----------
Channel* findCh(int vpin) {
  for (int i = 0; i < N; i++) if (ch[i].vpin == vpin) return &ch[i];
  return nullptr;
}
int indexOf(Channel* c) { return c - ch; }

// Mismas reglas que gpioProblem() en la app. Devuelve el problema, o nullptr si el GPIO sirve.
const char* gpioProblem(int gpio, bool output) {
  if (gpio < 0 || gpio > 39) return "no existe (0 a 39)";
  if (gpio >= 6 && gpio <= 11) return "lo usa la memoria de la placa";
  if (gpio == 20 || gpio == 24 || (gpio >= 28 && gpio <= 31)) return "no existe en el ESP32";
  if (output && gpio >= 34) return "solo sirve como entrada";
  return nullptr;
}

// Pone una salida digital en encendido o apagado, respetando el «invertir».
void writeOutput(Channel& c, bool on) {
  if (!c.enabled) return;
  digitalWrite(c.gpio, (on != c.inverted) ? HIGH : LOW);
}

void setBuzzer(bool on) {
  Channel* b = findCh(VPIN_BUZZER);
  if (b) writeOutput(*b, on);
}

// Prepara el pin de un canal y lo deja en su valor actual.
void setupChannel(Channel& c) {
  int i = indexOf(&c);
  if (c.kind == K_SERVO && servos[i].attached()) servos[i].detach();
  if (!c.enabled) return;
  switch (c.kind) {
    case K_SWITCH: pinMode(c.gpio, OUTPUT); writeOutput(c, c.value == 1); break;
    case K_BUZZER: pinMode(c.gpio, OUTPUT); writeOutput(c, false); break;
    case K_SERVO:
      servos[i].setPeriodHertz(50);
      servos[i].attach(c.gpio, 500, 2400);
      servos[i].write(c.value);
      break;
    case K_SENSOR: pinMode(c.gpio, INPUT); break;   // GPIO 34-39 solo sirven como entrada
  }
}

void loadConfig() {
  prefs.begin("pines", true);
  for (int i = 0; i < N; i++) {
    String k = "v" + String(ch[i].vpin);
    ch[i].gpio = prefs.getChar((k + "g").c_str(), ch[i].gpio);
    ch[i].inverted = prefs.getBool((k + "i").c_str(), ch[i].inverted);
    ch[i].enabled = prefs.getBool((k + "e").c_str(), ch[i].enabled);
  }
  prefs.end();
}

void saveConfig(Channel& c) {
  prefs.begin("pines", false);
  String k = "v" + String(c.vpin);
  prefs.putChar((k + "g").c_str(), c.gpio);
  prefs.putBool((k + "i").c_str(), c.inverted);
  prefs.putBool((k + "e").c_str(), c.enabled);
  prefs.end();
}

void beep(int ms) {
  setBuzzer(true);
  buzzerOffAt = millis() + ms;
}

void showLcd(const String& text) {
#if USE_LCD
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(text.substring(0, 16));
  if (text.length() > 16) { lcd.setCursor(0, 1); lcd.print(text.substring(16, 32)); }
#endif
  Serial.println("LCD: " + text);
}

// Activa cada salida un momento para identificar qué hay en cada pin.
void runTest() {
  for (int i = 0; i < N; i++) {
    Channel& c = ch[i];
    if (c.kind == K_SENSOR || !c.enabled) continue;
    sendLine("OK:TEST V" + String(c.vpin) + " " + c.name + " GPIO " + String(c.gpio));
    if (c.kind == K_SERVO) {
      servos[i].write(90); delay(700);
      servos[i].write(c.value); delay(500);
    } else {
      writeOutput(c, true); delay(700);
      writeOutput(c, c.kind == K_SWITCH && c.value == 1); delay(300);
    }
  }
  sendLine("OK:TEST terminado");
}

String alarmState() {
  return triggered ? "DISPARO" : (armed ? "1" : "0");
}

// Envía el estado real de la casa, para que la app muestre lo que hay y no lo que recuerda.
void sendState() {
  for (int i = 0; i < N; i++) {
    Channel& c = ch[i];
    if (c.kind == K_BUZZER || !c.enabled) continue;
    sendLine("V" + String(c.vpin) + ":" + String(c.value));
  }
  sendLine("V" + String(VPIN_ALARM) + ":" + alarmState());
}

// ---------- Mensajes de la app ----------
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

  const char* problem = gpioProblem(gpio, c->kind != K_SENSOR);
  if (problem) { sendLine("ERR:GPIO " + String(gpio) + " " + problem); return; }

  bool changed = c->gpio != gpio || c->inverted != inverted || c->enabled != enabled;
  if (changed) {
    if (c->kind == K_SWITCH || c->kind == K_BUZZER) writeOutput(*c, false);   // apaga el pin anterior
    c->gpio = gpio; c->inverted = inverted; c->enabled = enabled;
    setupChannel(*c);
    saveConfig(*c);
  }
  sendLine("OK:V" + String(c->vpin) + " GPIO " + String(gpio) + (inverted ? " inv" : "") + (enabled ? "" : " off"));
}

void handleAlarm(const String& val) {
  armed = val.toInt() == 1;
  triggered = false;
  setBuzzer(false);
  sendLine("V" + String(VPIN_ALARM) + ":" + alarmState());
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
  String val = line.substring(colon + 1);

  if (vpin == VPIN_LCD) { showLcd(val); sendLine("V6:OK"); return; }
  if (vpin == VPIN_ALARM) { handleAlarm(val); return; }

  Channel* c = findCh(vpin);
  if (!c) { sendLine("ERR:V" + String(vpin) + " no existe"); return; }
  if (!c->enabled) { sendLine("ERR:V" + String(vpin) + " desactivado"); return; }
  switch (c->kind) {
    case K_SWITCH: c->value = val.toInt() == 1; writeOutput(*c, c->value == 1); break;
    case K_SERVO:  c->value = constrain(val.toInt(), 0, 180); servos[indexOf(c)].write(c->value); break;
    case K_BUZZER: beep(300); break;
    case K_SENSOR: break;
  }
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

// ---------- Sensores y alarma ----------
void loopMotion(unsigned long now) {
  if (now - lastSensorAt < 150) return;
  lastSensorAt = now;
  Channel* pir = findCh(VPIN_MOTION);
  if (!pir || !pir->enabled) return;

  bool motion = (digitalRead(pir->gpio) == HIGH) != pir->inverted;
  if (motion != (pir->value == 1)) {
    pir->value = motion;
    sendLine("V" + String(VPIN_MOTION) + ":" + String(pir->value));
  }
  if (armed && motion && !triggered) {
    triggered = true;
    sendLine("V" + String(VPIN_ALARM) + ":DISPARO");
  }
}

void loopBuzzer(unsigned long now) {
  if (triggered) { setBuzzer((now / 300) % 2); return; }   // sirena intermitente hasta desarmar
  if (buzzerOffAt && now > buzzerOffAt) { setBuzzer(false); buzzerOffAt = 0; }
}

// ---------- Programa principal ----------
String serialBuffer;

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n== " DEVICE_NAME " ==");
  loadConfig();
  for (int i = 0; i < N; i++) setupChannel(ch[i]);
#if USE_LCD
  Wire.begin(21, 22);
  lcd.init(); lcd.backlight();
  showLcd("Casa lista");
#endif
#if USE_DHT
  dht.begin();
#endif
#if USE_BLE
  setupBle();
#endif
#if USE_WIFI
  setupWifi();
#endif
  Serial.println("Escribe mensajes aqui mismo para probar, por ejemplo: V1:1");
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
  loopMotion(now);
  loopBuzzer(now);

#if USE_DHT
  if (now - lastTempAt > 5000) {
    lastTempAt = now;
    float t = dht.readTemperature();
    if (!isnan(t)) sendLine("V" + String(VPIN_TEMP) + ":" + String(t, 1));
  }
#endif
}
