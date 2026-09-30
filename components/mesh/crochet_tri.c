#include "crochet_tri.h"

#include <string.h>

bool tri_lire_entete(const uint8_t *c, size_t len, tri_entete_t *e) {
  if (len < TRI_ENTETE_RESEAU) return false;
  e->ctl = (c[1] & 0x80) != 0;
  e->ttl = c[1] & 0x7F;
  e->seq = ((uint32_t)c[2] << 16) | ((uint32_t)c[3] << 8) | c[4];
  e->src = (uint16_t)((c[5] << 8) | c[6]);
  e->dst = (uint16_t)((c[7] << 8) | c[8]);
  return true;
}

void tri_lire_transport(uint8_t octet, tri_transport_t *t) {
  t->segmente = (octet & 0x80) != 0;
  t->akf = (octet & 0x40) != 0;
  t->aid = octet & 0x3F;
}

int tri_etat_lampe(uint16_t src, const uint8_t *acces, size_t len, const uint16_t *lampes, size_t nb,
                   uint8_t trame[TELINK_TAILLE]) {
  if (len != 1 + TELINK_TAILLE || acces[0] != TELINK_OPCODE) return -1;
  if (acces[1] != telink_somme(acces + 1)) return -1;
  for (size_t i = 0; i < nb; i++) {
    if (lampes[i] != 0 && lampes[i] == src) {
      memcpy(trame, acces + 1, TELINK_TAILLE);
      return (int)i;
    }
  }
  return -1;
}

bool tri_lire_balise(const uint8_t *b, size_t len, tri_balise_t *balise) {
  if (len < 22 || b[0] != 0x01) return false;
  balise->flags = b[1];
  memcpy(balise->net_id, b + 2, 8);
  balise->iv_index = ((uint32_t)b[10] << 24) | ((uint32_t)b[11] << 16) | ((uint32_t)b[12] << 8) | b[13];
  memcpy(balise->auth, b + 14, 8);
  return true;
}

bool tri_plus_recent(const tri_dernier_t *d, uint32_t iv, uint32_t seq) {
  if (!d->connu || iv > d->iv) return true;
  return iv == d->iv && seq > d->seq;
}

void tri_retenir(tri_dernier_t *d, uint32_t iv, uint32_t seq) {
  d->connu = true;
  d->iv = iv;
  d->seq = seq;
}
