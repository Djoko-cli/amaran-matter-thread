// Trames Telink des lampes amaran.
//
// Adapte de main/telink.c d'amaran-bridge :
// https://github.com/kevinschaich/amaran-bridge
//
// MIT License
//
// Copyright (c) 2026 Kevin Schaich
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
#include "telink.h"

#include <string.h>

uint8_t telink_somme(const uint8_t t[TELINK_TAILLE]) {
  unsigned s = 0;
  for (int i = 1; i < TELINK_TAILLE; i++) s += t[i];
  return (uint8_t)(s & 0xFF);
}

void telink_demande_etat(uint8_t t[TELINK_TAILLE]) {
  memset(t, 0, TELINK_TAILLE);
  t[9] = TELINK_CMD_ETAT;
  t[0] = telink_somme(t);
}

void telink_marche(bool marche, uint8_t t[TELINK_TAILLE]) {
  memset(t, 0, TELINK_TAILLE);
  t[8] = marche ? 0x01 : 0x00;
  t[9] = TELINK_CMD_MARCHE;
  t[0] = telink_somme(t);
}

void telink_intensite(uint16_t intensite, uint8_t t[TELINK_TAILLE]) {
  const uint16_t v = intensite > TELINK_INTENSITE_MAX ? TELINK_INTENSITE_MAX : intensite;
  memset(t, 0, TELINK_TAILLE);
  t[7] = (uint8_t)((v & 0x03) << 6);
  t[8] = (uint8_t)(v >> 2);
  t[9] = TELINK_CMD_INTENSITE;
  t[0] = telink_somme(t);
}

bool telink_lire_etat(const uint8_t t[TELINK_TAILLE], telink_etat_t *etat) {
  memset(etat, 0, sizeof(*etat));
  if (t[0] != telink_somme(t)) return false;
  etat->mode = t[9] & 0x7F;
  if (etat->mode != TELINK_MODE_CCT && etat->mode != TELINK_MODE_HSI) return false;
  etat->marche = (t[1] & 0x01) != 0;
  const uint16_t v = (uint16_t)((((unsigned)t[8] << 2) | (t[7] >> 6)) & 0x3FF);
  etat->intensite = v > TELINK_INTENSITE_MAX ? TELINK_INTENSITE_MAX : v;
  etat->valide = true;
  return true;
}
