/*
  Actualización por Wi-Fi · la misma en la casa y en el carrito
  -------------------------------------------------------------
  (Este archivo está repetido, idéntico, en firmware/casa_esp32 y firmware/carro_esp32: Arduino solo
  compila lo que está en la carpeta del programa. tool/compilar_firmware.py avisa si dejan de ser iguales.)

  El teléfono manda el programa nuevo por la conexión Wi-Fi, después de entregar la clave:

    app   OTA:<tamaño>:<md5>     por ejemplo OTA:1512304:9e107d9d372bb6826bd81d3542a419d6
    placa OTA:LISTO              lista: ahora llegan <tamaño> bytes tal cual, sin saltos de línea
    placa OTA:AVANCE:35          cada 5 %: lo que de verdad quedó escrito en la placa
    placa OTA:OK                 completo y con la misma huella MD5: se reinicia con la versión nueva
    placa OTA:ERR:<motivo>       no se instaló nada: sigue la versión actual. Si falla a mitad, la placa
                                 descarta los bytes que falten antes de volver a leer órdenes, y la app
                                 deja de enviar y cierra la conexión.

  Mientras llega, la placa sigue funcionando con su versión y escribe la nueva en el otro espacio de programa
  (por eso se compila con «Minimal SPIFFS»: dos espacios de 1,9 MB). Si se corta, falta un byte o la huella no
  coincide, lo escrito se descarta y la placa sigue igual. La clave y los ajustes están en otra zona: no se tocan.

  Vuelta atrás: una versión recién recibida arranca «a prueba». Si funciona OTA_CONFIRM_MS seguidos, queda.
  Si se reinicia antes (se cuelga y el watchdog la corta), el arranque siguiente vuelve solo a la anterior.

  Cómo lo usa cada programa:
    - la línea OTA:... (solo por Wi-Fi y con clave)  →  contestar otaBegin(...)
    - mientras otaActive(): leer como mucho otaWant() bytes  →  contestar otaReceive(...) si no es ""
    - si se corta el Wi-Fi                           →  otaAbort()
    - en cada vuelta de loop()                       →  contestar otaLoop(now) si no es ""
*/
#pragma once
#include <Update.h>
#include <esp_ota_ops.h>

const uint32_t OTA_CONFIRM_MS = 10000;   // funcionando este tiempo, la versión nueva queda confirmada
const uint32_t OTA_IDLE_MS = 10000;      // sin bytes este tiempo durante la recepción: se cancela
const uint32_t OTA_RESTART_MS = 800;     // tras OTA:OK, tiempo para que la respuesta llegue antes de reiniciar
const int      OTA_STEP = 5;             // cada cuántos puntos de porcentaje se avisa el avance

struct OtaJob {
  bool active = false;                   // llegan los bytes del programa (o se descartan, ver draining)
  bool draining = false;                 // falló a mitad: se descartan los bytes que faltan, sin leerlos como órdenes
  size_t size = 0, received = 0;
  int reported = 0;                      // último porcentaje avisado
  uint32_t lastData = 0;
  uint32_t restartAt = 0;                // 0 = sin reinicio pendiente
};
OtaJob ota;

// El núcleo de Arduino da por buena una versión nueva en cuanto arranca. Así no: la confirma otaLoop() después
// de OTA_CONFIRM_MS, y una versión que se cuelga antes vuelve sola a la anterior. (En C, como en el núcleo.)
extern "C" bool verifyRollbackLater() { return true; }

bool otaActive() { return ota.active; }

// Bytes que todavía faltan: nunca se lee más que esto, así lo que venga detrás no se toma como programa.
size_t otaWant() { return ota.active ? ota.size - ota.received : 0; }

// Cancela: lo escrito se descarta y la placa sigue con su versión. Con [drain], los bytes que el teléfono
// todavía esté mandando se leen y se tiran: si no, un pedazo de programa podría tomarse como una orden.
String otaFailed(const String& why, bool drain) {
  if (!ota.draining) Update.abort();
  ota.draining = drain && ota.received < ota.size;
  ota.active = ota.draining;
  Serial.println("Actualizacion cancelada: " + why);
  return "OTA:ERR:" + why;
}

// OTA:<tamaño>:<md5> → OTA:LISTO, u OTA:ERR:<motivo> sin tocar nada.
String otaBegin(const String& arg) {
  if (ota.active || ota.restartAt) return "OTA:ERR:ya hay una actualizacion en curso";
  int colon = arg.indexOf(':');
  String sizeText = arg.substring(0, colon), md5 = arg.substring(colon + 1);
  md5.toLowerCase();
  bool hex = md5.length() == 32;
  for (size_t i = 0; hex && i < md5.length(); i++) hex = isHexadecimalDigit(md5[i]);
  long size = sizeText.toInt();
  if (colon < 0 || !hex || size <= 0 || String(size) != sizeText) return "OTA:ERR:usa OTA:<tamano>:<md5>";
  const esp_partition_t* next = esp_ota_get_next_update_partition(nullptr);
  if (!next) return "OTA:ERR:esta placa no tiene espacio para actualizar por Wi-Fi; instala esta version por cable";
  if ((size_t)size > next->size) return "OTA:ERR:el programa no cabe (" + String(size) + " bytes; caben " + String(next->size) + ")";
  if (!Update.begin(size)) return "OTA:ERR:no se pudo preparar la memoria: " + String(Update.errorString());
  Update.setMD5(md5.c_str());
  ota.active = true;
  ota.draining = false;
  ota.size = size;
  ota.received = 0;
  ota.reported = 0;
  ota.lastData = millis();
  Serial.println("Recibiendo una version nueva por Wi-Fi (" + String(size) + " bytes)...");
  return "OTA:LISTO";
}

// Un trozo del programa → "" (nada que avisar todavía), OTA:AVANCE:n, OTA:OK u OTA:ERR:<motivo>.
String otaReceive(uint8_t* data, size_t len) {
  if (!ota.active) return "";
  ota.lastData = millis();
  ota.received += len;
  if (ota.draining) {                    // después de un error: solo se tira lo que falta
    if (ota.received >= ota.size) ota.active = ota.draining = false;
    return "";
  }
  if (Update.write(data, len) != len) return otaFailed(Update.errorString(), true);
  if (ota.received < ota.size) {
    int pct = (int)((uint64_t)ota.received * 100 / ota.size);
    if (pct < ota.reported + OTA_STEP) return "";
    ota.reported = pct;
    return "OTA:AVANCE:" + String(pct);
  }
  ota.active = false;                    // completo: Update.end() revisa la huella MD5
  if (!Update.end()) return otaFailed(Update.errorString(), false);
  ota.restartAt = millis() | 1;          // nunca 0, que significa «sin reinicio»
  Serial.println("Version nueva recibida y revisada: la placa se reinicia.");
  return "OTA:OK";
}

// Se cortó la conexión a mitad: lo escrito se descarta y la placa sigue con su versión.
void otaAbort() {
  if (ota.active) otaFailed("se corto la conexion", false);
}

// En cada vuelta de loop(): cancela una recepción que quedó sin bytes, reinicia cuando toca y confirma la
// versión que está funcionando. Devuelve un aviso para el teléfono, o "".
String otaLoop(uint32_t now) {
  static bool confirmed = false;
  if (!confirmed && now > OTA_CONFIRM_MS) {
    confirmed = true;
    esp_ota_img_states_t state;
    if (esp_ota_get_state_partition(esp_ota_get_running_partition(), &state) == ESP_OK &&
        state == ESP_OTA_IMG_PENDING_VERIFY) {
      esp_ota_mark_app_valid_cancel_rollback();
      Serial.println("Version nueva confirmada: funciona.");
    }
  }
  // Con signo: si `now` se leyó justo antes que lastData, la resta no da un número enorme.
  if (ota.restartAt && (int32_t)(now - ota.restartAt) >= (int32_t)OTA_RESTART_MS) {
    Serial.flush();
    ESP.restart();
  }
  if (ota.active && (int32_t)(now - ota.lastData) > (int32_t)OTA_IDLE_MS) {
    bool silent = ota.draining;          // terminar de descartar no es un error nuevo
    String why = otaFailed("no llegaron mas datos", false);
    if (!silent) return why;
  }
  return "";
}
