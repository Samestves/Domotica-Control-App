/*
  Escritura · de un texto a los movimientos del robot
  ---------------------------------------------------
  El marcador está en el centro, entre las dos ruedas: al girar en el lugar no se mueve, así que cada trazo
  recto es «girar hacia el punto y avanzar». Si el punto queda detrás, el robot va marcha atrás en vez de dar
  media vuelta (la línea es la misma y tarda menos).

  Dónde empieza: el robot se pone donde va la esquina de abajo a la izquierda de la primera letra, mirando
  hacia donde sigue el texto. Las letras quedan paradas hacia su izquierda.

  Este archivo no usa nada de Arduino: se prueba en la computadora (ver la prueba del robot en la carpeta
  de pruebas del firmware) con el mismo código que corre en la placa.

  Uso:
    Escritor e;  e.empezar("HOLA", 30, lapizAbajo);     // letras de 30 mm
    Paso p;  while (e.siguiente(p)) { ...hacer p... }   // el robot hace cada paso y pide el siguiente
    Conversor c;  c.pasos(p, medidas, izq, der);        // giro o avance → pasos de cada rueda
*/
#pragma once
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "letras.h"

// PASO_LAPIZ: 1 = bajar, 0 = subir · PASO_GIRO: radianes, + = hacia la izquierda · PASO_AVANCE: mm, − = marcha
// atrás · PASO_LETRA: empieza la letra número `valor` (1, 2, ...) de las que se dibujan (los espacios no cuentan).
enum PasoTipo : uint8_t { PASO_LAPIZ, PASO_GIRO, PASO_AVANCE, PASO_LETRA };
struct Paso { PasoTipo tipo; float valor; };

const int ESCRITURA_MAX = 24;            // letras por texto

// La letra con la que empieza [s] y cuántos bytes ocupa (la Ñ y las vocales con tilde son 2 en UTF-8).
// Minúsculas y tildes se dibujan como la mayúscula sin tilde. nullptr si no hay una letra para ese carácter.
inline const Letra* buscarLetra(const char* s, int& largo) {
  largo = 1;
  char ch[3] = {(char)s[0], 0, 0};
  const unsigned char a = s[0], b = s[1];
  if (a >= 'a' && a <= 'z') ch[0] = (char)(a - 'a' + 'A');
  if (a == 0xC3 && b) {
    largo = 2;
    const char* desde = "\x81\x89\x8D\x93\x9A\x9C\xA1\xA9\xAD\xB3\xBA\xBC";   // ÁÉÍÓÚÜ áéíóúü
    const char* hacia = "AEIOUUAEIOUU";
    const char* k = strchr(desde, b);
    if (k) { ch[0] = hacia[k - desde]; }
    else if (b == 0x91 || b == 0xB1) { ch[0] = (char)0xC3; ch[1] = (char)0x91; }   // Ñ ñ
    else return nullptr;
  }
  for (const Letra& l : LETRAS) if (strcmp(l.ch, ch) == 0) return &l;
  return nullptr;
}

inline float anguloNormal(float a) {     // a (−π, π]
  while (a > (float)M_PI) a -= 2 * (float)M_PI;
  while (a <= -(float)M_PI) a += 2 * (float)M_PI;
  return a;
}

class Escritor {
 public:
  // Prepara el texto con letras de [altoMm] de alto. Los caracteres sin letra se saltan. Si el marcador
  // está abajo, primero lo sube. Devuelve cuántas letras se van a dibujar (0 = nada que dibujar).
  int empezar(const char* texto, float altoMm, bool lapizAbajo) {
    n_ = total_ = letra_ = dibujadas_ = 0;
    anunciada_ = -1;
    for (const char* s = texto; *s && n_ < ESCRITURA_MAX;) {
      int largo;
      const Letra* l = buscarLetra(s, largo);
      s += largo;
      if (!l) continue;
      texto_[n_++] = l;
      if (*l->trazos) total_++;
    }
    while (n_ && !*texto_[n_ - 1]->trazos) n_--;   // los espacios del final no mueven al robot
    escala_ = altoMm / LETRA_ALTO;
    x_ = y_ = rumbo_ = 0;
    trazo_ = nullptr;
    enCola_ = leido_ = 0;
    abajo_ = lapizAbajo;
    activo_ = total_ > 0;
    return total_;
  }

  // El próximo paso, o false si ya terminó (con el marcador arriba).
  bool siguiente(Paso& p) {
    while (true) {
      if (leido_ < enCola_) { p = cola_[leido_++]; return true; }
      enCola_ = leido_ = 0;
      if (!activo_) return false;
      planear();
    }
  }

  bool activo() const { return activo_ || leido_ < enCola_; }
  int letras() const { return total_; }

  // Dónde cree que está el robot (mm y radianes): sirve a las pruebas.
  float x() const { return x_; }
  float y() const { return y_; }
  float rumbo() const { return rumbo_; }

 private:
  const Letra* texto_[ESCRITURA_MAX];
  int n_ = 0, total_ = 0, letra_ = 0, dibujadas_ = 0;
  int anunciada_ = -1;                   // la última letra que ya avisó que empezaba (PASO_LETRA)
  const char* trazo_ = nullptr;          // el próximo punto de la letra actual (nullptr = empieza la letra)
  bool empiezaTrazo_ = true;
  bool abajo_ = false, activo_ = false;
  float x_ = 0, y_ = 0, rumbo_ = 0, escala_ = 5;
  Paso cola_[6];                         // lo que sale de un punto: letra, subir, girar, avanzar, bajar
  int enCola_ = 0, leido_ = 0;

  void poner(PasoTipo t, float v) { cola_[enCola_++] = {t, v}; }

  // Lee el próximo punto de la letra actual. [nuevo] = es el primero de un trazo.
  bool leerPunto(float& gx, float& gy, bool& nuevo) {
    nuevo = empiezaTrazo_;
    while (*trazo_ == ' ' || *trazo_ == '|') { if (*trazo_ == '|') nuevo = true; trazo_++; }
    if (!*trazo_) return false;
    char* fin;
    long x = strtol(trazo_, &fin, 10);
    if (*fin != ',') return false;       // una letra mal escrita termina ahí (no pasa con la tabla probada)
    long y = strtol(fin + 1, &fin, 10);
    trazo_ = fin;
    empiezaTrazo_ = false;
    gx = (float)x; gy = (float)y;
    return true;
  }

  // Gira hacia el punto y avanza (o va marcha atrás si queda detrás).
  void irA(float px, float py) {
    float dx = px - x_, dy = py - y_, d = hypotf(dx, dy);
    if (d < .05f) return;
    float giro = anguloNormal(atan2f(dy, dx) - rumbo_), avance = d;
    if (fabsf(giro) > (float)M_PI / 2) { giro = anguloNormal(giro - (float)M_PI); avance = -d; }
    if (fabsf(giro) > .0005f) { poner(PASO_GIRO, giro); rumbo_ = anguloNormal(rumbo_ + giro); }
    poner(PASO_AVANCE, avance);
    x_ = px; y_ = py;
  }

  // Pone en la cola los pasos del próximo punto que mueva algo, o los del final.
  void planear() {
    while (letra_ < n_) {
      if (!trazo_) { trazo_ = texto_[letra_]->trazos; empiezaTrazo_ = true; }
      float gx, gy;
      bool nuevo;
      if (!leerPunto(gx, gy, nuevo)) { letra_++; trazo_ = nullptr; continue; }
      if (anunciada_ != letra_) { anunciada_ = letra_; poner(PASO_LETRA, (float)++dibujadas_); }   // su primer punto
      float px = (letra_ * (LETRA_ANCHO + LETRA_ESPACIO) + gx) * escala_, py = gy * escala_;
      bool aqui = fabsf(px - x_) < .05f && fabsf(py - y_) < .05f;
      // Un trazo nuevo que empieza justo donde está el marcador sigue sin levantarlo: la línea es la misma.
      if (nuevo && abajo_ && !aqui) { poner(PASO_LAPIZ, 0); abajo_ = false; }
      irA(px, py);
      if (nuevo && !abajo_) { poner(PASO_LAPIZ, 1); abajo_ = true; }
      if (enCola_) return;
    }
    activo_ = false;
    if (abajo_) { poner(PASO_LAPIZ, 0); abajo_ = false; }
  }
};

// Diámetro de las ruedas y distancia entre ellas (de centro a centro), en mm.
struct Medidas { float ruedaMm, ejeMm; };

// Medios pasos por vuelta del motor 28BYJ-48 (con su caja de engranajes).
const float PASOS_VUELTA = 4096;

// Pasa giros y avances a pasos de cada rueda. Lleva la cuenta de lo que sobra al redondear: después de
// cientos de trazos el robot sigue donde debe, sin irse corriendo de a medio paso.
class Conversor {
 public:
  void reiniciar() { idealI_ = idealD_ = 0; dadosI_ = dadosD_ = 0; }

  // Pasos de la rueda izquierda y la derecha (+ = hacia adelante) para [p]. Lápiz y letra: 0 y 0.
  void pasos(const Paso& p, const Medidas& m, int32_t& izq, int32_t& der) {
    const double porMm = PASOS_VUELTA / (M_PI * m.ruedaMm);
    if (p.tipo == PASO_AVANCE) { idealI_ += p.valor * porMm; idealD_ += p.valor * porMm; }
    if (p.tipo == PASO_GIRO) {                   // a la izquierda: la izquierda atrás, la derecha adelante
      const double arco = p.valor * m.ejeMm / 2 * porMm;
      idealI_ -= arco; idealD_ += arco;
    }
    const int64_t i = llround(idealI_), d = llround(idealD_);
    izq = (int32_t)(i - dadosI_); der = (int32_t)(d - dadosD_);
    dadosI_ = i; dadosD_ = d;
  }

 private:
  double idealI_ = 0, idealD_ = 0;
  int64_t dadosI_ = 0, dadosD_ = 0;
};
