// Trames Telink des lampes amaran : opcode d'un octet 0x26, charge de 10
// octets, octet 0 = somme des octets 1 a 9 (spec 3.2). Format etabli par
// amaran-bridge (Kevin Schaich, MIT), voir telink.c.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#define TELINK_OPCODE 0x26
#define TELINK_CID 0x0211
#define TELINK_TAILLE 10

#define TELINK_CMD_ETAT 0x0E
#define TELINK_CMD_MARCHE 0x8C
#define TELINK_CMD_INTENSITE 0x8F
#define TELINK_MODE_HSI 0x01
#define TELINK_MODE_CCT 0x02
#define TELINK_INTENSITE_MAX 1000

typedef struct {
  bool valide;         // somme juste et mode connu (CCT ou HSI)
  uint8_t mode;        // octet 9 & 0x7F
  bool marche;         // bit 0 de l'octet 1
  uint16_t intensite;  // 0..1000, pas de 0,1 %
} telink_etat_t;

#ifdef __cplusplus
extern "C" {
#endif

uint8_t telink_somme(const uint8_t t[TELINK_TAILLE]);
void telink_demande_etat(uint8_t t[TELINK_TAILLE]);
void telink_marche(bool marche, uint8_t t[TELINK_TAILLE]);
void telink_intensite(uint16_t intensite, uint8_t t[TELINK_TAILLE]);
bool telink_lire_etat(const uint8_t t[TELINK_TAILLE], telink_etat_t *etat);

#ifdef __cplusplus
}
#endif
