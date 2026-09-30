// Tri pur des messages Mesh captes par le crochet (spec 5.5), teste sur le Mac.
// Les en-tetes sont lus APRES dechiffrement du message reseau.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "telink.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TRI_ENTETE_RESEAU 9  // IVI/NID, CTL/TTL, SEQ (3), SRC (2), DST (2)

typedef struct {
  bool ctl;
  uint8_t ttl;
  uint32_t seq;
  uint16_t src;
  uint16_t dst;
} tri_entete_t;

typedef struct {
  bool segmente;
  bool akf;     // chiffre par une AppKey (sinon cle d'appareil)
  uint8_t aid;  // identifiant de l'AppKey
} tri_transport_t;

typedef struct {
  uint8_t flags;
  uint8_t net_id[8];
  uint32_t iv_index;
} tri_balise_t;

bool tri_lire_entete(const uint8_t *clair, size_t len, tri_entete_t *e);
void tri_lire_transport(uint8_t octet, tri_transport_t *t);
// Charge d'acces dechiffree = opcode 0x26 + 10 octets a la somme juste, d'une
// source presente dans lampes : rend son index et copie la trame, sinon -1.
int tri_etat_lampe(uint16_t src, const uint8_t *acces, size_t len, const uint16_t *lampes, size_t nb,
                   uint8_t trame[TELINK_TAILLE]);
// Balise reseau securisee (type 0x01), octet de type compris : 22 octets.
bool tri_lire_balise(const uint8_t *b, size_t len, tri_balise_t *balise);

#ifdef __cplusplus
}
#endif
