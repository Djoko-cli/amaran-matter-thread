// Tests sur le Mac des trames Telink. Lancer : sh tests/hote/lancer.sh
// Vecteurs : spec 3.2 et calcul des octets (somme = octets 1 a 9, mod 256).
#include <string.h>

#include "telink.h"
#include "unite.h"

static void test_demande_etat(void) {
  uint8_t t[TELINK_TAILLE];
  const uint8_t attendu[TELINK_TAILLE] = {0x0E, 0, 0, 0, 0, 0, 0, 0, 0, 0x0E};
  telink_demande_etat(t);
  VERIFIE(memcmp(t, attendu, TELINK_TAILLE) == 0, "demande d'etat");
}

static void test_marche(void) {
  uint8_t t[TELINK_TAILLE];
  const uint8_t on[TELINK_TAILLE] = {0x8D, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x8C};
  const uint8_t off[TELINK_TAILLE] = {0x8C, 0, 0, 0, 0, 0, 0, 0, 0x00, 0x8C};
  telink_marche(true, t);
  VERIFIE(memcmp(t, on, TELINK_TAILLE) == 0, "marche");
  telink_marche(false, t);
  VERIFIE(memcmp(t, off, TELINK_TAILLE) == 0, "arret");
}

static void test_intensite(void) {
  uint8_t t[TELINK_TAILLE];
  const uint8_t v500[TELINK_TAILLE] = {0x0C, 0, 0, 0, 0, 0, 0, 0x00, 0x7D, 0x8F};
  const uint8_t v1000[TELINK_TAILLE] = {0x89, 0, 0, 0, 0, 0, 0, 0x00, 0xFA, 0x8F};
  const uint8_t v1[TELINK_TAILLE] = {0xCF, 0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x8F};
  telink_intensite(500, t);
  VERIFIE(memcmp(t, v500, TELINK_TAILLE) == 0, "intensite 500");
  telink_intensite(1000, t);
  VERIFIE(memcmp(t, v1000, TELINK_TAILLE) == 0, "intensite 1000");
  telink_intensite(1, t);
  VERIFIE(memcmp(t, v1, TELINK_TAILLE) == 0, "intensite 1");
  telink_intensite(1500, t);
  VERIFIE(memcmp(t, v1000, TELINK_TAILLE) == 0, "intensite bornee a 1000");
}

static void test_lire_etat(void) {
  // Etat CCT reconstruit : marche, 93,0 %, 5600 K, G/M neutre.
  const uint8_t cct[TELINK_TAILLE] = {0xCF, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0xE8, 0x02};
  telink_etat_t e;
  VERIFIE(telink_lire_etat(cct, &e), "etat CCT lisible");
  VERIFIE(e.valide && e.mode == TELINK_MODE_CCT, "mode CCT (%u)", (unsigned)e.mode);
  VERIFIE(e.marche, "marche");
  VERIFIE(e.intensite == 930, "intensite 930 (%u)", (unsigned)e.intensite);

  uint8_t faux[TELINK_TAILLE];
  memcpy(faux, cct, TELINK_TAILLE);
  faux[0] ^= 0x01;
  VERIFIE(!telink_lire_etat(faux, &e) && !e.valide, "somme fausse refusee");

  uint8_t inconnu[TELINK_TAILLE] = {0, 0x01, 0, 0, 0, 0, 0, 0, 0, 0x0A};
  inconnu[0] = telink_somme(inconnu);
  VERIFIE(!telink_lire_etat(inconnu, &e), "mode 0x0A refuse");

  uint8_t arret[TELINK_TAILLE];
  memcpy(arret, cct, TELINK_TAILLE);
  arret[1] = 0x00;
  arret[0] = telink_somme(arret);
  VERIFIE(telink_lire_etat(arret, &e) && !e.marche && e.intensite == 930, "arret, intensite gardee");
}

int main(void) {
  test_demande_etat();
  test_marche();
  test_intensite();
  test_lire_etat();
  return bilan("telink");
}
