/*
  Cara del robot · una o dos pantallas OLED de 0,96" (128×64 puntos, I2C)
  -----------------------------------------------------------------------
  Ojos que parpadean, miran y cambian de ánimo según lo que hace el robot. Es la misma cara del simulador
  (docs/cara-carrito/index.html): al encender dibuja el logo de Control Domótica, que se cierra como un párpado
  y abre los ojos.

  Cables (VCC → 3V3 y GND → GND en las dos; sin librerías extra, solo Wire):
    ojo izquierdo del robot (a la derecha de quien lo mira)   SDA → GPIO 21 · SCL → GPIO 22
    ojo derecho del robot (a la izquierda de quien lo mira)   SDA → GPIO 23 · SCL → GPIO 4
  Con las dos, cada pantalla muestra un ojo grande. Con una sola (cualquiera), esa muestra los dos ojos.
  Las filas 0 a 15 son la franja de arriba (amarilla en la pantalla de dos colores): conexión, velocidad y
  mensajes. Las filas 16 a 63, los ojos.

  Sin pantallas el robot funciona igual: la que no responde se vuelve a buscar cada 3 s.
  Nunca frena al robot: cada vuelta de loop() envía como mucho una franja de 8 filas (unos 3 ms).

  La app también puede ver la cara (desde carro-0.7): caraState() y caraLabel() dicen lo que la cara quiere
  mostrar, y la app lo anima igual con el mismo motor de ojos (lib/ui/widgets/robot_face.dart). La cara se
  anima aunque no haya pantallas, para que la app la vea igual.

  Otras pantallas:
    - 1,3" con chip SH1106 (132 columnas): poner OLED_SH1106 en 1.
    - 2,42" con chip SSD1309: funciona tal cual (mismas órdenes que el SSD1306).
*/
#pragma once
#include <Wire.h>

#define OLED_SH1106 0                    // 1 = pantalla de 1,3" con chip SH1106
const int OLED_SDA = 21, OLED_SCL = 22, OLED2_SDA = 23, OLED2_SCL = 4;

// Lo que el robot le cuenta a la cara está al final (caraBegin, caraLoop, caraLink...). Todo lo demás vive
// dentro de «cara», para que nombres como line o text no choquen con los del programa del robot.
enum CaraKey : uint8_t { CARA_KEY_ASK, CARA_KEY_OK, CARA_KEY_BAD };

namespace cara {

// ===================== Pantalla: búfer de 1 bit, igual al del chip =====================
const int W = 128, H = 64, BAND = 16, PAGES = H / 8;
const uint32_t RETRY_MS = 3000, FRAME_MS = 33;   // buscar la pantalla otra vez · un cuadro cada 33 ms (30 por s)
const uint8_t ADDRS[] = {0x3C, 0x3D};

// Una pantalla en su propio bus I2C, con su imagen: byte = 8 filas de una columna (bit 0 arriba), como en el chip.
struct Oled {
  TwoWire& bus;
  int sda, scl;
  const char* name;
  uint8_t addr = 0;                      // 0 = sin pantalla
  uint32_t retryAt = 0;
  uint8_t fb[W * PAGES];
  Oled(TwoWire& b, int d, int c, const char* n) : bus(b), sda(d), scl(c), name(n) {}
};
Oled screens[2] = {{Wire, OLED_SDA, OLED_SCL, "ojo izquierdo"}, {Wire1, OLED2_SDA, OLED2_SCL, "ojo derecho"}};
uint8_t* fb = screens[0].fb;             // donde dibujan las funciones de abajo
int page = -1;                           // franja que falta enviar del cuadro actual: 0..2·PAGES-1 (-1 = enviado)

bool command(Oled& o, const uint8_t* bytes, size_t n) {
  o.bus.beginTransmission(o.addr);
  o.bus.write(0x00);                     // lo que sigue son órdenes
  o.bus.write(bytes, n);
  return o.bus.endTransmission() == 0;
}

// Una franja de 8 filas. false si la pantalla no respondió.
bool sendPage(Oled& o, int p) {
  const uint8_t col = OLED_SH1106 ? 2 : 0;
  const uint8_t at[] = {(uint8_t)(0xB0 | p), (uint8_t)(col & 0x0F), (uint8_t)(0x10 | (col >> 4))};
  if (!command(o, at, sizeof(at))) return false;
  for (int x = 0; x < W; x += 64) {      // de a 64 bytes: el búfer de Wire es de 128
    o.bus.beginTransmission(o.addr);
    o.bus.write(0x40);                   // lo que sigue son puntos
    o.bus.write(o.fb + p * W + x, 64);
    if (o.bus.endTransmission() != 0) return false;
  }
  return true;
}

bool start(Oled& o) {
  o.addr = 0;
  for (uint8_t a : ADDRS) {
    o.bus.beginTransmission(a);
    if (o.bus.endTransmission() == 0) { o.addr = a; break; }
  }
  if (!o.addr) return false;
  const uint8_t init[] = {
    0xAE,                                // apagada mientras se prepara
    0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40,
#if OLED_SH1106
    0xAD, 0x8B,                          // fuente interna (SH1106)
#else
    0x8D, 0x14, 0x20, 0x02,              // fuente interna y escritura por franjas (SSD1306)
#endif
    0xA1, 0xC8,                          // girada para que el conector quede arriba
    0xDA, 0x12, 0x81, 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6,
  };
  memset(o.fb, 0, sizeof(o.fb));
  bool ok = command(o, init, sizeof(init));
  for (int p = 0; ok && p < PAGES; p++) ok = sendPage(o, p);   // la memoria del chip arranca con basura
  const uint8_t on[] = {0xAF};
  if (ok) ok = command(o, on, 1);
  if (!ok) o.addr = 0;
  return ok;
}

void hline(float fx0, float fx1, float fy, bool on) {
  int y = lroundf(fy);
  if (y < 0 || y >= H) return;
  int x0 = max(0L, lroundf(fx0)), x1 = min((long)W - 1, lroundf(fx1));
  uint8_t bit = 1 << (y & 7);
  uint8_t* row = fb + (y >> 3) * W;
  for (int x = x0; x <= x1; x++) row[x] = on ? row[x] | bit : row[x] & ~bit;
}
void rect(float x, float y, float w, float h, bool on) {
  for (long j = lroundf(y); j < lroundf(y + h); j++) hline(x, x + w - 1, j, on);
}
void rrect(float fx, float fy, float fw, float fh, float fr, bool on) {   // rectángulo redondeado
  int x = lroundf(fx), y = lroundf(fy), w = lroundf(fw), h = lroundf(fh);
  if (w <= 0 || h <= 0) return;
  int r = max(0, min((int)lroundf(fr), min(w / 2, h / 2)));
  for (int j = 0; j < h; j++) {
    float d = j < r ? r - j - .5f : (j >= h - r ? j - (h - r) + .5f : 0);
    int inset = d > 0 ? lroundf(r - sqrtf(max(0.f, r * r - d * d))) : 0;
    hline(x + inset, x + w - 1 - inset, y + j, on);
  }
}
void tri(float x0, float y0, float x1, float y1, float x2, float y2, bool on) {   // triángulo relleno
  const float e[3][4] = {{x0, y0, x1, y1}, {x1, y1, x2, y2}, {x2, y2, x0, y0}};
  for (long y = lroundf(min(y0, min(y1, y2))); y <= lroundf(max(y0, max(y1, y2))); y++) {
    float yc = y + .5f, lo = 1e9, hi = -1e9;
    int n = 0;
    for (auto& s : e) {
      if ((s[1] <= yc && s[3] > yc) || (s[3] <= yc && s[1] > yc)) {
        float x = s[0] + (yc - s[1]) * (s[2] - s[0]) / (s[3] - s[1]);
        lo = min(lo, x); hi = max(hi, x); n++;
      }
    }
    if (n >= 2) hline(lo, hi, y, on);
  }
}
void dot(float x, float y, float r) { rrect(x - r, y - r, 2 * r + 1, 2 * r + 1, r, true); }
void line(float x0, float y0, float x1, float y1, float r, float frac) {   // trazo grueso; frac = la parte dibujada
  if (frac <= 0) return;
  int n = max(1, (int)ceilf(hypotf(x1 - x0, y1 - y0) * 2 * frac));
  for (int i = 0; i <= n; i++) { float t = (float)i / n * frac; dot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r); }
}
void arc(float cx, float cy, float rad, float a0, float a1, float r) {
  int n = (int)ceilf(fabsf(a1 - a0) * rad * 2);
  for (int i = 0; i <= n; i++) { float a = a0 + (a1 - a0) * i / n; dot(cx + cosf(a) * rad, cy + sinf(a) * rad, r); }
}

// Letras de 5×7: solo las que usa la cara. Cada fila es un byte (bit 4 = columna izquierda).
struct Glyph { char ch; uint8_t rows[7]; };
const Glyph FONT[] = {
  {'A', {14, 17, 17, 31, 17, 17, 17}}, {'B', {30, 17, 17, 30, 17, 17, 30}}, {'C', {15, 16, 16, 16, 16, 16, 15}},
  {'D', {30, 17, 17, 17, 17, 17, 30}}, {'E', {31, 16, 16, 30, 16, 16, 31}}, {'F', {31, 16, 16, 30, 16, 16, 16}},
  {'H', {17, 17, 17, 31, 17, 17, 17}}, {'I', {31, 4, 4, 4, 4, 4, 31}},     {'L', {16, 16, 16, 16, 16, 16, 31}},
  {'M', {17, 27, 21, 21, 17, 17, 17}}, {'N', {17, 25, 21, 19, 17, 17, 17}}, {'O', {14, 17, 17, 17, 17, 17, 14}},
  {'R', {30, 17, 17, 30, 20, 18, 17}}, {'S', {15, 16, 16, 14, 1, 1, 30}},   {'T', {31, 4, 4, 4, 4, 4, 4}},
  {'U', {17, 17, 17, 17, 17, 17, 14}}, {'V', {17, 17, 17, 17, 10, 10, 4}},  {'W', {17, 17, 17, 21, 21, 27, 17}},
  {'X', {17, 17, 10, 4, 10, 17, 17}},  {'Z', {31, 1, 2, 4, 8, 16, 31}},     {'P', {30, 17, 17, 30, 16, 16, 16}},
  {'Q', {14, 17, 17, 17, 21, 18, 13}}, {'G', {15, 16, 16, 23, 17, 17, 15}}, {'K', {17, 18, 20, 24, 20, 18, 17}},
  {'J', {7, 2, 2, 2, 2, 18, 12}},      {'Y', {17, 17, 10, 4, 4, 4, 4}},     {'/', {1, 1, 2, 4, 8, 16, 16}},
  {':', {0, 12, 12, 0, 12, 12, 0}},    {'.', {0, 0, 0, 0, 0, 12, 12}},     {',', {0, 0, 0, 0, 12, 4, 8}},
  {'0', {14, 19, 21, 21, 25, 17, 14}}, {'1', {4, 12, 4, 4, 4, 4, 14}},      {'2', {14, 17, 1, 6, 8, 16, 31}},
  {'3', {30, 1, 1, 14, 1, 1, 30}},     {'4', {2, 6, 10, 18, 31, 2, 2}},     {'5', {31, 16, 30, 1, 1, 17, 14}},
  {'6', {6, 8, 16, 30, 17, 17, 14}},   {'7', {31, 1, 2, 4, 8, 8, 8}},       {'8', {14, 17, 17, 14, 17, 17, 14}},
  {'9', {14, 17, 17, 15, 1, 2, 12}},   {'!', {4, 4, 4, 4, 4, 0, 4}},        {'?', {14, 17, 1, 6, 4, 0, 4}},
  {'-', {0, 0, 0, 31, 0, 0, 0}},       {'%', {25, 26, 2, 4, 8, 11, 19}},
};
int textW(const char* s) { return max(0, (int)strlen(s) * 6 - 1); }
void text(const char* s, int x, int y) {
  for (; *s; s++, x += 6) {
    for (const Glyph& g : FONT) {
      if (g.ch != *s) continue;
      for (int j = 0; j < 7; j++)
        for (int i = 0; i < 5; i++)
          if (g.rows[j] & (16 >> i)) hline(x + i, x + i, y + j, true);
      break;
    }
  }
}

// Iconos de la franja de arriba: una fila por número, bit más alto = columna izquierda.
const uint16_t ICON_BT[] = {0x18, 0x14, 0x52, 0x34, 0x18, 0x34, 0x52, 0x14, 0x18};   // 7 de ancho
const uint16_t ICON_WIFI[] = {0x7C, 0x82, 0x139, 0x44, 0x38, 0x00, 0x10};            // 9 de ancho
void icon(const uint16_t* rows, int n, int width, int x, int y) {
  for (int j = 0; j < n; j++)
    for (int i = 0; i < width; i++)
      if (rows[j] & (1 << (width - 1 - i))) hline(x + i, x + i, y + j, true);
}

// ===================== Encendido: el logo de Control Domótica =====================
const uint32_t BOOT_DRAW = 1300, BOOT_HOLD = 2100, BOOT_CLOSE = 2400, BOOT_OPEN = 3300;   // ms
float clamp01(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

void drawLogo(uint32_t t) {
  // Las medidas del logo de la app (caja de 100), a 0,42 puntos por unidad, centrado en la zona de los ojos.
  // Al final se aplasta hacia el centro, como un párpado que se cierra.
  const float s = .42f, sy = t < BOOT_HOLD ? 1 : 1 - clamp01((float)(t - BOOT_HOLD) / (BOOT_CLOSE - BOOT_HOLD));
  if (sy <= 0) return;
  auto X = [&](float u) { return 64 + (u - 50) * s; };
  auto Y = [&](float v) { return 41 + (v - 52) * s * sy; };
  float roof = clamp01(t / 450.f), walls = clamp01((t - 350.f) / 450.f), floor = clamp01((t - 600.f) / 250.f);
  line(X(8), Y(47), X(50), Y(10), 1, roof);            // techo: sube desde los dos lados hasta la punta
  line(X(92), Y(47), X(50), Y(10), 1, roof);
  line(X(20), Y(38), X(20), Y(90), 1, walls);          // paredes
  line(X(80), Y(38), X(80), Y(90), 1, walls);
  line(X(20), Y(90), X(80), Y(90), 1, floor);          // piso
  // La señal: el punto y dos arcos que aparecen como el Wi-Fi conectándose, y después laten.
  float dx = X(50), dy = Y(75);
  if (t > 800) dot(dx, dy, 2);
  int pulse = t > BOOT_DRAW ? (t - BOOT_DRAW) / 260 % 3 : 2;
  if (t > 950 && pulse >= 1) arc(dx, dy, 15 * s, -PI * .75f, -PI * .25f, 1);
  if (t > 1100 && pulse >= 2) arc(dx, dy, 27 * s, -PI * .75f, -PI * .25f, 1);
}

// ===================== Motor de ojos =====================
struct Eyes { float lx, ly, scale, tired, angry, sad, happy, curious, blinkL, blinkR; };
Eyes cur = {0, 0, 1, 0, 0, 0, 0, 0, 1, 1}, tgt = cur;

enum Mood : uint8_t { NORMAL, FELIZ, ENOJADO, TRISTE, CANSADO, ENFOCADO, SORPRESA };
struct Shape { float tired, angry, sad, happy, scale; };
const Shape MOODS[] = {
  {0, 0, 0, 0, 1},       // normal
  {0, 0, 0, 1, 1},       // feliz: ojos en media luna
  {0, 1, 0, 0, .96f},    // enojado: párpado inclinado hacia adentro
  {.15f, 0, 1, 0, .94f}, // triste: inclinado hacia afuera
  {.7f, 0, 0, 0, .96f},  // cansado
  {.32f, 0, 0, 0, 1},    // enfocado: entrecerrados
  {0, 0, 0, 0, 1.2f},    // sorpresa: grandes
};

struct Face {
  uint32_t t0 = 0, now = 0, frameAt = 0;
  Mood moodAfter = NORMAL; uint32_t moodUntil = 0;
  Mood chainMood = NORMAL; uint32_t chainAt = 0, chainMs = 0;   // un ánimo que sigue a otro (sorpresa → enojo)
  bool sleeping = false, opening = true; uint32_t lastInput = 0;
  bool ble = false, wifi = false;
  int speed = 0;
  uint32_t nextBlink = 4500, blinkEnd = 0, nextLook = 4200, holdLook = 4200;
  int8_t wink = 0;                       // -1 guiña el izquierdo, 1 el derecho, 0 parpadean los dos
  uint32_t shakeUntil = 0, bounceUntil = 0;
  char label[20] = "CONTROL DOMOTICA"; uint32_t labelUntil = 1500;
  uint16_t labelSeq = 0; uint32_t labelMs = 1500;   // para la app: cada mensaje nuevo y cuánto dura
};
Face f;

float rnd(float a, float b) { return a + (float)random(10000) / 10000 * (b - a); }
bool chance(float p) { return random(10000) < p * 10000; }

void setMood(Mood m, uint32_t ms = 0, Mood after = NORMAL) {
  f.moodUntil = ms ? f.now + ms : 0;
  f.moodAfter = after;
  tgt.tired = MOODS[m].tired; tgt.angry = MOODS[m].angry; tgt.sad = MOODS[m].sad;
  tgt.happy = MOODS[m].happy; tgt.scale = MOODS[m].scale;
}
void look(float x, float y, uint32_t holdMs) { tgt.lx = x; tgt.ly = y; f.holdLook = f.now + holdMs; }
void blink(int8_t side) { f.wink = side; f.blinkEnd = f.now + 140; }
void say(const char* s, uint32_t ms) {
  strlcpy(f.label, s, sizeof(f.label));
  f.labelUntil = f.now + ms;
  f.labelMs = ms;
  f.labelSeq++;
}

void wake() {
  f.lastInput = f.now;
  if (!f.sleeping) return;
  f.sleeping = false;
  setMood(SORPRESA, 600);
  look(0, 0, 800);
  say("!", 800);
}

float ease(float v, float to, float k) { return v + (to - v) * k; }

void update(uint32_t dt) {
  uint32_t now = f.now;
  if (f.chainAt && now >= f.chainAt) { setMood(f.chainMood, f.chainMs); f.chainAt = 0; }
  if (f.moodUntil && now > f.moodUntil) setMood(f.moodAfter);
  if (f.opening) {                       // al encender: logo, y después abre los ojos de a poco
    tgt.blinkL = tgt.blinkR = now < BOOT_CLOSE ? 1 : 0;
    if (now > 1500 && now < 1600) say("AUTO ROBOT", 1700);
    if (now > BOOT_OPEN + 600) f.opening = false;
  }
  if (!f.sleeping && now - f.lastInput > 60000) { f.sleeping = true; setMood(CANSADO); look(0, .4f, 1e9); }
  if (!f.opening) {
    if (f.sleeping) {
      tgt.blinkL = tgt.blinkR = .92f;
    } else if (now < f.blinkEnd) {
      tgt.blinkL = f.wink >= 0 ? 1 : 0;
      tgt.blinkR = f.wink <= 0 ? 1 : 0;
    } else {
      tgt.blinkL = tgt.blinkR = 0;
      if (now > f.nextBlink) { blink(0); f.nextBlink = now + (chance(.15f) ? 260 : rnd(2000, 5000)); }
    }
  }
  if (!f.sleeping && now > f.holdLook && now > f.nextLook) {   // mira alrededor; con un teléfono, más al frente
    if (chance(f.ble || f.wifi ? .55f : .3f)) { tgt.lx = 0; tgt.ly = 0; }
    else { tgt.lx = rnd(-1, 1); tgt.ly = rnd(-.6f, .6f); }
    tgt.curious = chance(.25f) ? 1 : 0;
    f.nextLook = now + rnd(1200, 3500);
  }
  // Se acercan a lo pedido a la misma velocidad aunque cambie la cantidad de cuadros por segundo.
  auto k = [&](float base, float slow) { return 1 - powf(1 - base, dt / 33.f / slow); };
  float kf = k(.45f, f.opening ? 4 : 1), km = k(.2f, 1), kl = k(.28f, 1);
  cur.blinkL = ease(cur.blinkL, tgt.blinkL, kf); cur.blinkR = ease(cur.blinkR, tgt.blinkR, kf);
  cur.tired = ease(cur.tired, tgt.tired, km); cur.angry = ease(cur.angry, tgt.angry, km);
  cur.sad = ease(cur.sad, tgt.sad, km); cur.happy = ease(cur.happy, tgt.happy, km);
  cur.scale = ease(cur.scale, tgt.scale, km); cur.curious = ease(cur.curious, tgt.curious, km);
  cur.lx = ease(cur.lx, tgt.lx, kl); cur.ly = ease(cur.ly, tgt.ly, kl);
}

// [only]: el ojo que se dibuja (-1 el de la izquierda de quien mira, 1 el de la derecha, 0 los dos). Un ojo
// solo va en el centro y más grande: es el de su propia pantalla.
void drawEyes(int only) {
  const Eyes& c = cur;
  uint32_t now = f.now;
  float cy0 = BAND + (H - BAND) / 2.f;
  float shake = now < f.shakeUntil ? sinf(now / 18.f) * 3 : 0;
  float bounce = now < f.bounceUntil ? -fabsf(sinf(now / 110.f)) * 4 : 0;
  const float grow = only ? 1.25f : 1, gap = only ? 0 : 25, travel = only ? 22 : 14;
  for (int side = -1; side <= 1; side += 2) {
    if (only && side != only) continue;
    float toward = (c.lx > 0) - (c.lx < 0) == side ? .14f : -.08f;   // el ojo hacia donde mira, más grande
    float big = c.curious * toward * min(1.f, fabsf(c.lx) * 2);
    float size = 36 * c.scale * grow * (1 + big);
    float h = max(2.f, size * (1 - (side < 0 ? c.blinkL : c.blinkR)));
    float cx = 64 + side * gap + c.lx * travel + shake;
    float cy = cy0 + c.ly * 6 + bounce + (size - h) * .15f;
    float x = cx - size / 2, y = cy - h / 2, w = size;
    rrect(x, y, w, h, (12 + 6 * c.happy) * c.scale, true);
    float inner = side < 0 ? x + w : x, outer = side < 0 ? x : x + w;
    if (c.tired > .01f) rect(x - 1, y - 1, w + 2, h * .55f * c.tired + 1, false);
    if (c.angry > .01f) tri(outer, y - 1, inner, y - 1, inner, y + h * .62f * c.angry, false);
    if (c.sad > .01f) tri(inner, y - 1, outer, y - 1, outer, y + h * .58f * c.sad, false);
    if (c.happy > .01f) rrect(x - 6, y + h - h * .58f * c.happy, w + 12, h + 4, 18, false);
  }
}

// Franja de arriba: conexión a la izquierda, velocidad a la derecha, mensajes al centro. Con dos pantallas,
// la de la izquierda (de quien mira) lleva la conexión y la de la derecha la velocidad: [icons] y [bars].
void drawBand(bool icons, bool bars) {
  uint32_t now = f.now;
  bool showLabel = !f.sleeping && now < f.labelUntil;
  // Un mensaje largo (ACTUALIZANDO 45%) ocupa casi todo el ancho: los iconos esperan a que termine.
  if (icons && now >= BOOT_OPEN && !(showLabel && textW(f.label) > W - 2 * 22)) {
    if (f.ble) icon(ICON_BT, 9, 7, 2, 3);
    else if (f.wifi) icon(ICON_WIFI, 7, 9, 1, 5);
    else text("X", 2, 4);
  }
  if (bars && now >= BOOT_OPEN && !(showLabel && textW(f.label) > 64)) {
    for (int i = 0; i < 5; i++) {        // cinco barras de velocidad
      int bh = 2 + i * 2;
      if (f.speed > i * 20) rect(W - 26 + i * 5, 12 - bh, 4, bh, true);
      else rect(W - 26 + i * 5, 11, 4, 1, true);
    }
  }
  if (f.sleeping) {
    float p = fmodf(now / 900.f, 1);
    text("Z", 50, lroundf(8 - p * 6));
    text("Z", 60, lroundf(6 - fmodf(p + .4f, 1) * 4));
    text("Z", 70, lroundf(9 - fmodf(p + .7f, 1) * 7));
  } else if (showLabel) {
    text(f.label, (W - textW(f.label)) / 2, 4);
  }
}

// La imagen de cada pantalla que respondió. Con dos, cada una es un ojo; con una, esa lleva la cara entera.
void draw() {
  const bool both = screens[0].addr && screens[1].addr;
  for (int i = 0; i < 2; i++) {
    if (!screens[i].addr) continue;
    fb = screens[i].fb;
    memset(fb, 0, sizeof(screens[i].fb));
    const int eye = both ? (i == 0 ? 1 : -1) : 0;   // el ojo izquierdo del robot queda a la derecha de quien mira
    if (f.now < BOOT_CLOSE) drawLogo(f.now); else drawEyes(eye);
    drawBand(eye <= 0, eye >= 0);
  }
}

// ===================== Lo que el carrito le cuenta a la cara =====================

void report(const Oled& o, const char* what) {
  Serial.println(String("Pantalla del ") + o.name + " (SDA " + o.sda + ", SCL " + o.scl + "): " + what);
}

void caraBegin() {
  f.t0 = millis();
  randomSeed(esp_random());
  for (Oled& o : screens) {
    o.bus.begin(o.sda, o.scl, 400000);
    report(o, start(o) ? "lista." : "no responde; el robot funciona igual.");
    o.retryAt = millis() + RETRY_MS;
  }
}

void caraLoop(uint32_t ms) {
  for (Oled& o : screens) {              // la que no está se vuelve a buscar de vez en cuando
    if (o.addr || (int32_t)(ms - o.retryAt) < 0) continue;
    o.retryAt = ms + RETRY_MS;
    if (start(o)) { report(o, "encontrada."); page = -1; }
    return;                              // una búsqueda por vuelta: cada una tarda unos milisegundos
  }
  const bool any = screens[0].addr || screens[1].addr;
  if (any && page >= 0) {                // una franja por vuelta
    Oled& o = screens[page / PAGES];
    if (o.addr && !sendPage(o, page % PAGES)) { o.addr = 0; o.retryAt = ms + RETRY_MS; report(o, "dejo de responder."); }
    if (++page == 2 * PAGES) page = -1;
    return;
  }
  uint32_t now = ms - f.t0;
  if (now - f.frameAt < FRAME_MS) return;
  uint32_t dt = min(now - f.frameAt, (uint32_t)200);   // tras una pausa larga, sin saltos bruscos
  f.frameAt = now;
  f.now = now;
  update(dt);                            // sin pantallas también: la app puede estar mirando la cara
  if (!any) return;
  draw();
  page = 0;
}

// Lo que la cara quiere mostrar, para la app (V33): ánimo, hacia dónde mira y el parpadeo (los valores a los
// que se acercan los ojos, ×100), la velocidad y unas marcas: 1 dormida, 2 sacudiéndose, 4 saltando,
// 8 Bluetooth, 16 Wi-Fi. La app los anima igual que aquí. Cambia solo cuando cambia algo.
String caraState() {
  auto q = [](float v) { return String(lroundf(v * 100)); };
  const int marks = (f.sleeping ? 1 : 0) | (f.now < f.shakeUntil ? 2 : 0) | (f.now < f.bounceUntil ? 4 : 0) |
                    (f.ble ? 8 : 0) | (f.wifi ? 16 : 0);
  return q(tgt.tired) + "," + q(tgt.angry) + "," + q(tgt.sad) + "," + q(tgt.happy) + "," + q(tgt.scale) + "," +
         q(tgt.curious) + "," + q(tgt.lx) + "," + q(tgt.ly) + "," + q(tgt.blinkL) + "," + q(tgt.blinkR) + "," +
         String(f.speed) + "," + String(marks);
}

// El mensaje de la franja de arriba, para la app (V34): «número,ms,TEXTO». El número cambia con cada mensaje
// nuevo (aunque repita el texto) y ms es cuánto se muestra.
String caraLabel() { return String(f.labelSeq) + "," + String(f.labelMs) + "," + f.label; }

void caraLink(bool ble, bool wifi) {
  bool before = f.ble || f.wifi, after = ble || wifi;
  f.ble = ble;
  f.wifi = wifi;
  if (!before && after) { wake(); setMood(FELIZ, 1800); f.bounceUntil = f.now + 1200; look(0, -.3f, 1200); say("HOLA", 1800); }
  if (before && !after) { f.speed = 0; setMood(TRISTE, 4000); look(0, .6f, 3500); say("DESCONECTADO", 3000); }
}

void caraKey(CaraKey k) {
  wake();
  switch (k) {
    case CARA_KEY_ASK: setMood(NORMAL); look(.55f, .9f, 2600); say("CLAVE?", 2600); break;
    case CARA_KEY_OK:  setMood(FELIZ, 1600); f.bounceUntil = f.now + 900; look(0, 0, 800); say("LISTO", 1600); break;
    case CARA_KEY_BAD: setMood(ENOJADO, 1500); f.shakeUntil = f.now + 600; say("NO", 1800); break;
  }
}

void caraWake() { wake(); }

void caraDrive(int left, int right) {
  int speed = max(abs(left), abs(right));
  if (speed == 0) {                      // frenó: mira al frente y parpadea
    if (f.speed) { setMood(NORMAL); look(0, 0, 600); blink(0); }
    f.speed = 0;
    return;
  }
  wake();
  f.speed = speed;
  if (left < 0 && right < 0) { setMood(NORMAL); look(0, .9f, 1500); }                    // reversa: mira atrás
  else if (left - right > 30) { setMood(ENFOCADO); tgt.curious = 1; look(1, -.2f, 1500); }  // gira a la derecha
  else if (right - left > 30) { setMood(ENFOCADO); tgt.curious = 1; look(-1, -.2f, 1500); } // a la izquierda
  else { setMood(ENFOCADO); look(0, -.35f, 1500); }                                      // adelante
}

// Prueba (TEST): 0 rueda izquierda, 1 derecha, 2 y 3 el lápiz, o -1 al terminar. Mira lo que se mueve.
void caraTest(int part) {
  static const char* NAME[] = {"RUEDA IZQ", "RUEDA DER", "LAPIZ", "LAPIZ"};
  static const float X[] = {1, -1, 0, 0}, Y[] = {.6f, .6f, .9f, .9f};   // la izquierda del robot, a la derecha de quien mira
  wake();
  if (part < 0 || part > 3) { look(0, 0, 600); setMood(FELIZ, 900); say("LISTO", 1200); return; }
  setMood(NORMAL);
  look(X[part], Y[part], 1700);
  say(NAME[part], 1700);
}

// El marcador baja o sube: mira hacia abajo un momento.
void caraPen(bool down) {
  wake();
  look(0, down ? .9f : .3f, 900);
  if (down) blink(0);
}

// Escribiendo: letra [letter] de [total]. letter 0 = terminó bien; -1 = se canceló.
void caraWrite(int letter, int total) {
  wake();
  if (letter < 0) { setMood(TRISTE, 2500); say("PARADO", 2000); return; }
  if (letter == 0) { setMood(FELIZ, 2200); f.bounceUntil = f.now + 1200; look(0, -.3f, 1500); say("LISTO", 2200); return; }
  char s[32];                            // «ESCRIBIENDO 24/24» cabe en la franja (y en label)
  snprintf(s, sizeof(s), "ESCRIBIENDO %d/%d", letter, total);
  setMood(ENFOCADO);
  look(0, .7f, 4000);
  say(s, 60000);                         // hasta la letra siguiente
}

void caraUpdate(int pct) {
  wake();
  if (pct < 0) { setMood(TRISTE, 3000); say("NO SE ACTUALIZO", 3000); return; }
  if (pct >= 100) { setMood(FELIZ, 2000); say("LISTO", 2000); return; }
  char s[20];
  snprintf(s, sizeof(s), "ACTUALIZANDO %d%%", pct);
  setMood(ENFOCADO);
  look(0, .5f, 3000);
  say(s, 15000);
}

}  // namespace cara

using cara::caraBegin;      // en setup()
using cara::caraLoop;       // en cada vuelta de loop()
using cara::caraLink;       // qué teléfonos están conectados (cada vez que cambia)
using cara::caraKey;        // pide la clave, la aceptó o la rechazó
using cara::caraWake;       // llegó una orden: si dormía, se despierta
using cara::caraDrive;      // velocidad de cada rueda, -100 a 100
using cara::caraTest;       // prueba: 0 a 3 (rueda izquierda, derecha, lápiz abajo, arriba), o -1 al terminar
using cara::caraPen;        // el marcador baja (true) o sube
using cara::caraWrite;      // escribiendo la letra n de total; 0 = terminó, -1 = se canceló
using cara::caraUpdate;     // actualización por Wi-Fi: 0 a 100, o -1 si falló
using cara::caraState;      // para la app (V33): lo que muestran los ojos
using cara::caraLabel;      // para la app (V34): el mensaje de la franja de arriba
