/*
  Letras de un solo trazo · las que dibuja el robot con el marcador
  -----------------------------------------------------------------
  Cada letra vive en una cuadrícula de 4 de ancho por 6 de alto (la Ñ y la coma salen un poco de ella),
  con y hacia arriba. Un trazo es una lista de puntos «x,y» separados por espacios: el marcador baja en el
  primero, recorre los demás y sube. Los trazos de una letra se separan con «|». Un trazo de un solo punto
  es un punto (el marcador baja y sube).

  La app tiene la misma tabla en lib/models/letras.dart para mostrar lo que va a dibujar; una prueba
  (test/letras_test.dart) revisa que las dos sean iguales.
*/
#pragma once

struct Letra { const char* ch; const char* trazos; };   // ch en UTF-8: «A», «Ñ»

const int LETRA_ANCHO = 4, LETRA_ALTO = 6, LETRA_ESPACIO = 2;   // en cuadros; ESPACIO = separación entre letras

const Letra LETRAS[] = {
  {"A", "0,0 2,6 4,0|1,3 3,3"},
  {"B", "0,3 3,3 4,4 4,5 3,6 0,6 0,0 3,0 4,1 4,2 3,3"},
  {"C", "4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1"},
  {"D", "0,0 0,6 2,6 4,4 4,2 2,0 0,0"},
  {"E", "4,6 0,6 0,0 4,0|0,3 3,3"},
  {"F", "4,6 0,6 0,0|0,3 3,3"},
  {"G", "4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,3 2,3"},
  {"H", "0,6 0,0|0,3 4,3|4,6 4,0"},
  {"I", "1,6 3,6|2,6 2,0|1,0 3,0"},
  {"J", "4,6 4,1 3,0 1,0 0,1"},
  {"K", "0,6 0,0|4,6 0,2|1,3 4,0"},
  {"L", "0,6 0,0 4,0"},
  {"M", "0,0 0,6 2,3 4,6 4,0"},
  {"N", "0,0 0,6 4,0 4,6"},
  {"\xC3\x91", "0,0 0,5 4,0 4,5|0,6 1,7 3,6 4,7"},   // Ñ
  {"O", "1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0"},
  {"P", "0,0 0,6 3,6 4,5 4,4 3,3 0,3"},
  {"Q", "1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|2,2 4,0"},
  {"R", "0,0 0,6 3,6 4,5 4,4 3,3 0,3|2,3 4,0"},
  {"S", "4,5 3,6 1,6 0,5 0,4 1,3 3,3 4,2 4,1 3,0 1,0 0,1"},
  {"T", "0,6 4,6|2,6 2,0"},
  {"U", "0,6 0,1 1,0 3,0 4,1 4,6"},
  {"V", "0,6 2,0 4,6"},
  {"W", "0,6 1,0 2,4 3,0 4,6"},
  {"X", "0,0 4,6|0,6 4,0"},
  {"Y", "0,6 2,3 4,6|2,3 2,0"},
  {"Z", "0,6 4,6 0,0 4,0"},
  {"0", "1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|0,1 4,5"},
  {"1", "1,5 2,6 2,0|1,0 3,0"},
  {"2", "0,5 1,6 3,6 4,5 4,4 0,0 4,0"},
  {"3", "0,5 1,6 3,6 4,5 4,4 3,3 1,3|3,3 4,2 4,1 3,0 1,0 0,1"},
  {"4", "3,0 3,6 0,2 4,2"},
  {"5", "4,6 0,6 0,3 3,3 4,2 4,1 3,0 0,0"},
  {"6", "4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,2 3,3 0,3"},
  {"7", "0,6 4,6 1,0"},
  {"8", "1,3 0,4 0,5 1,6 3,6 4,5 4,4 3,3 1,3 0,2 0,1 1,0 3,0 4,1 4,2 3,3"},
  {"9", "4,3 1,3 0,4 0,5 1,6 3,6 4,5 4,1 3,0 1,0 0,1"},
  {".", "2,0"},
  {",", "2,0 1,-1"},
  {"!", "2,6 2,2|2,0"},
  {"?", "0,5 1,6 3,6 4,5 4,4 2,3 2,2|2,0"},
  {"-", "1,3 3,3"},
  {"+", "2,1 2,5|0,3 4,3"},
  {":", "2,1|2,4"},
  {" ", ""},
};
