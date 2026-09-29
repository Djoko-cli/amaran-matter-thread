// Tests sur le Mac du tri des messages captes. Lancer : sh tests/hote/lancer.sh
// Vecteurs en clair de la specification Mesh (8.3.1, 8.3.22, 8.4.3), releves
// dans unit/test-mesh-crypto.c de BlueZ.
#include <string.h>

#include "crochet_tri.h"
#include "texte.h"
#include "unite.h"

static void test_entete(void) {
  uint8_t c[20];
  texte_hex_vers_octets("68800000011201fffd034b50057e400000010000", c, 20);  // 8.3.1 en clair
  tri_entete_t e;
  VERIFIE(tri_lire_entete(c, 20, &e), "en-tete 8.3.1 lisible");
  VERIFIE(e.ctl && e.ttl == 0 && e.seq == 1 && e.src == 0x1201 && e.dst == 0xFFFD, "champs 8.3.1");
  uint8_t d[22];
  texte_hex_vers_octets("e80307080b1234b529663871b904d431526316ca48a0", d, 22);  // 8.3.22 en clair
  VERIFIE(tri_lire_entete(d, 22, &e) && !e.ctl && e.ttl == 3 && e.seq == 0x07080B && e.src == 0x1234 &&
              e.dst == 0xB529,
          "champs 8.3.22");
  VERIFIE(!tri_lire_entete(d, 8, &e), "en-tete trop courte");
}

static void test_transport(void) {
  tri_transport_t t;
  tri_lire_transport(0x66, &t);
  VERIFIE(!t.segmente && t.akf && t.aid == 0x26, "0x66 : non segmente, AppKey, AID 0x26");
  tri_lire_transport(0x80, &t);
  VERIFIE(t.segmente && !t.akf && t.aid == 0, "0x80 : segmente, cle d'appareil");
}

static void test_etat_lampe(void) {
  const uint16_t lampes[] = {0x0002, 0x0004};
  uint8_t acces[11] = {TELINK_OPCODE, 0xCF, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0xE8, 0x02};
  uint8_t trame[TELINK_TAILLE];
  VERIFIE(tri_etat_lampe(0x0004, acces, 11, lampes, 2, trame) == 1 && memcmp(trame, acces + 1, 10) == 0,
          "lampe 2 reconnue");
  VERIFIE(tri_etat_lampe(0x0003, acces, 11, lampes, 2, trame) == -1, "source inconnue");
  VERIFIE(tri_etat_lampe(0x0002, acces, 10, lampes, 2, trame) == -1, "longueur fausse");
  acces[0] = 0x27;
  VERIFIE(tri_etat_lampe(0x0002, acces, 11, lampes, 2, trame) == -1, "opcode faux");
  acces[0] = TELINK_OPCODE;
  acces[1] ^= 0xFF;
  VERIFIE(tri_etat_lampe(0x0002, acces, 11, lampes, 2, trame) == -1, "somme fausse");
}

static void test_balise(void) {
  uint8_t b[22];
  texte_hex_vers_octets("01003ecaff672f673370123456788ea261582f364f6f", b, 22);  // 8.4.3
  const uint8_t net_id[8] = {0x3E, 0xCA, 0xFF, 0x67, 0x2F, 0x67, 0x33, 0x70};
  tri_balise_t bal;
  VERIFIE(tri_lire_balise(b, 22, &bal) && bal.iv_index == 0x12345678 && bal.flags == 0 &&
              memcmp(bal.net_id, net_id, 8) == 0,
          "balise 8.4.3");
  b[0] = 0x00;
  VERIFIE(!tri_lire_balise(b, 22, &bal), "balise non securisee refusee");
  b[0] = 0x01;
  VERIFIE(!tri_lire_balise(b, 21, &bal), "balise courte refusee");
}

int main(void) {
  test_entete();
  test_transport();
  test_etat_lampe();
  test_balise();
  return bilan("crochet_tri");
}
