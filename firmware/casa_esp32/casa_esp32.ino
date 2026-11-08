/*
  Casa Domótica · programa para ESP32
  -----------------------------------
  Recibe mensajes de la app (por Bluetooth LE, Wi-Fi o el Monitor Serie) y mueve
  las salidas de la maqueta. También envía lecturas y alarmas de vuelta a la app.

  Mensajes (una línea cada uno):
    V1:1          enciende la luz de la sala      V3:90       puerta (servo) a 90°
    V7:1 / V7:0   arma / desarma la alarma        V6:Hola     texto para la LCD
    CFG:V1:23:1   la luz de la sala pasa al GPIO 23 e invertida (se guarda en la placa)
    TEST          activa cada salida una por una para ver qué es cada cosa
    PING          la placa responde PONG

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

enum Kind { DIGITAL, SERVO, BUZZER, INPUT_PIN };

struct Channel {
  uint8_t vpin;      // pin virtual que usa la app (V1, V2...)
  int8_t  gpio;      // pin físico del ESP32
  Kind    kind;
  bool    inverted;  // true si el módulo se activa con señal baja (casi todos los relés)
  const char* name;
};

// Tabla de la maqueta. Debe coincidir con los cables reales.
// Los números se pueden cambiar desde la app sin volver a cargar el programa.
Channel ch[] = {
  {1,  23, DIGITAL,   true,  "Luz sala"},
  {2,  19, DIGITAL,   true,  "Luz cocina"},
  {8,  18, DIGITAL,   true,  "Luz cuarto"},
  {9,   5, DIGITAL,   true,  "Ventilador"},
  {3,  13, SERVO,     false, "Puerta"},
  {4,  14, SERVO,     false, "Ventana"},
  {5,  27, BUZZER,    false, "Timbre"},
  {11, 34, INPUT_PIN, false, "Sensor movimiento"},
};
const int N = sizeof(ch) / sizeof(ch[0]);

Servo servos[N];
int   servoAngle[N];
Preferences prefs;

bool armed = false, triggered = false, lastMotion = false;
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

// ---------- Envío de mensajes a la app ----------
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

void writeDigital(Channel& c, bool on) {
  digitalWrite(c.gpio, (on != c.inverted) ? HIGH : LOW);
}

void setupChannel(Channel& c) {
  int i = indexOf(&c);
  switch (c.kind) {
    case DIGITAL: pinMode(c.gpio, OUTPUT); writeDigital(c, false); break;
    case BUZZER:  pinMode(c.gpio, OUTPUT); writeDigital(c, false); break;
    case SERVO:
      if (servos[i].attached()) servos[i].detach();
      servos[i].setPeriodHertz(50);
      servos[i].attach(c.gpio, 500, 2400);
      servos[i].write(servoAngle[i]);
      break;
    case INPUT_PIN: pinMode(c.gpio, INPUT); break;   // GPIO 34-39 solo sirven como entrada
  }
}

void loadConfig() {
  prefs.begin("pines", true);
  for (int i = 0; i < N; i++) {
    String k = "v" + String(ch[i].vpin);
    ch[i].gpio = prefs.getChar((k + "g").c_str(), ch[i].gpio);
    ch[i].inverted = prefs.getBool((k + "i").c_str(), ch[i].inverted);
  }
  prefs.end();
}

void saveConfig(Channel& c) {
  prefs.begin("pines", false);
  String k = "v" + String(c.vpin);
  prefs.putChar((k + "g").c_str(), c.gpio);
  prefs.putBool((k + "i").c_str(), c.inverted);
  prefs.end();
}

void beep(int ms) {
  Channel* b = findCh(5);
  if (!b) return;
  writeDigital(*b, true);
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
    if (c.kind == INPUT_PIN) continue;
    sendLine("OK:TEST V" + String(c.vpin) + " " + c.name + " GPIO " + String(c.gpio));
    if (c.kind == SERVO) {
      servos[i].write(90); delay(700); servos[i].write(0); delay(500);
      servoAngle[i] = 0;
    } else {
      writeDigital(c, true); delay(700); writeDigital(c, false); delay(300);
    }
  }
  sendLine("OK:TEST terminado");
}

// ---------- Mensajes de la app ----------
void handleLine(String line) {
  line.trim();
  if (line.length() == 0) return;

  if (line == "PING") { sendLine("PONG"); return; }
  if (line == "TEST") { runTest(); return; }

  if (line.startsWith("CFG:V")) {                 // CFG:V1:23:1
    int a = line.indexOf(':', 5), b = line.indexOf(':', a + 1);
    int vpin = line.substring(5, a).toInt();
    int gpio = line.substring(a + 1, b).toInt();
    bool inv = line.substring(b + 1).toInt() == 1;
    Channel* c = findCh(vpin);
    if (!c || a < 0 || b < 0) { sendLine("ERR:CFG " + line); return; }
    const char* problem = gpioProblem(gpio, c->kind != INPUT_PIN);
    if (problem) { sendLine("ERR:GPIO " + String(gpio) + " " + problem); return; }
    if (c->kind == DIGITAL || c->kind == BUZZER) writeDigital(*c, false);
    c->gpio = gpio; c->inverted = inv;
    setupChannel(*c);
    saveConfig(*c);
    sendLine("OK:V" + String(vpin) + " GPIO " + String(gpio) + (inv ? " invertido" : ""));
    return;
  }

  if (line[0] != 'V') { sendLine("ERR:no entiendo " + line); return; }
  int colon = line.indexOf(':');
  if (colon < 0) return;
  int vpin = line.substring(1, colon).toInt();
  String val = line.substring(colon + 1);

  switch (vpin) {
    case 6: showLcd(val); sendLine("V6:OK"); return;
    case 7: {
      armed = val.toInt() == 1;
      triggered = false;
      Channel* bz = findCh(5);
      if (bz) writeDigital(*bz, false);
      sendLine(String("OK:alarma ") + (armed ? "armada" : "desarmada"));
      return;
    }
  }

  Channel* c = findCh(vpin);
  if (!c) { sendLine("ERR:V" + String(vpin) + " no existe"); return; }
  int i = indexOf(c);
  switch (c->kind) {
    case DIGITAL: writeDigital(*c, val.toInt() == 1); break;
    case SERVO:   servoAngle[i] = constrain(val.toInt(), 0, 180); servos[i].write(servoAngle[i]); break;
    case BUZZER:  beep(300); break;
    case INPUT_PIN: break;
  }
}

// ---------- Bluetooth LE (servicio Nordic UART) ----------
#if USE_BLE
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#define NUS_SERVICE "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
BLECharacteristic* txChar = nullptr;
bool bleConnected = false;
String bleBuffer, bleInbox;

class ServerCb : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConnected = true; }
  void onDisconnect(BLEServer* s) override { bleConnected = false; s->getAdvertising()->start(); }
};
class RxCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    bleBuffer += String(c->getValue().c_str());
    int nl;
    while ((nl = bleBuffer.indexOf('\n')) >= 0) {
      bleInbox += bleBuffer.substring(0, nl) + "\n";   // se procesa en loop(), no aquí
      bleBuffer.remove(0, nl + 1);
    }
  }
};

void setupBle() {
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
    tcpClient = tcpServer.available();
    sendLine("HELLO:" DEVICE_NAME);
  }
  while (tcpClient && tcpClient.connected() && tcpClient.available()) {
    char k = tcpClient.read();
    if (k == '\n') { handleLine(tcpBuffer); tcpBuffer = ""; }
    else if (k != '\r' && tcpBuffer.length() < 120) tcpBuffer += k;
  }
}
#endif

void sendLine(const String& line) {
  Serial.println("-> " + line);
#if USE_BLE
  if (bleConnected && txChar) {
    String out = line + "\n";
    txChar->setValue((uint8_t*)out.c_str(), out.length());
    txChar->notify();
  }
#endif
#if USE_WIFI
  if (tcpClient && tcpClient.connected()) tcpClient.print(line + "\n");
#endif
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
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') { handleLine(serialBuffer); serialBuffer = ""; }
    else if (c != '\r' && serialBuffer.length() < 120) serialBuffer += c;
  }
#if USE_BLE
  if (bleInbox.length()) {
    String inbox = bleInbox; bleInbox = "";
    int nl;
    while ((nl = inbox.indexOf('\n')) >= 0) { handleLine(inbox.substring(0, nl)); inbox.remove(0, nl + 1); }
  }
#endif
#if USE_WIFI
  loopWifi();
#endif

  unsigned long now = millis();

  // Apagar el timbre cuando termina el pitido (si no está sonando la alarma)
  if (buzzerOffAt && now > buzzerOffAt && !triggered) {
    Channel* b = findCh(5); if (b) writeDigital(*b, false);
    buzzerOffAt = 0;
  }

  // Sensor de movimiento y alarma
  if (now - lastSensorAt > 150) {
    lastSensorAt = now;
    Channel* pir = findCh(11);
    if (pir) {
      bool motion = (digitalRead(pir->gpio) == HIGH) != pir->inverted;
      if (motion != lastMotion) { lastMotion = motion; sendLine(String("V11:") + (motion ? "1" : "0")); }
      if (armed && motion && !triggered) {
        triggered = true;
        sendLine("V7:DISPARO");
      }
      if (triggered) {                     // sirena intermitente hasta que se desarme
        Channel* b = findCh(5);
        if (b) writeDigital(*b, (now / 300) % 2);
      }
    }
  }

#if USE_DHT
  if (now - lastTempAt > 5000) {
    lastTempAt = now;
    float t = dht.readTemperature();
    if (!isnan(t)) sendLine("V10:" + String(t, 1));
  }
#endif
}
