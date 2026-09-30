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

// Trames relevees au banc du 30/09/2026 (docs/PROTOCOLE.md).
static void test_trames_du_banc(void) {
  static const struct {
    uint8_t t[TELINK_TAILLE];
    bool marche;
    uint16_t intensite;
  } etats[] = {
      {{0xCE, 0x00, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0xE8, 0x02}, false, 930},  // lampe 1
      {{0x4D, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0x66, 0x02}, true, 410},   // lampe 1
      {{0x75, 0x00, 0x00, 0x00, 0x00, 0x40, 0x01, 0x23, 0x0F, 0x02}, false, 60},   // lampe 2
      {{0xB2, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0x23, 0x4B, 0x02}, true, 300},   // lampe 2
  };
  for (size_t i = 0; i < sizeof(etats) / sizeof(etats[0]); i++) {
    telink_etat_t e;
    VERIFIE(telink_lire_etat(etats[i].t, &e) && e.mode == TELINK_MODE_CCT, "etat du banc %u lisible", (unsigned)i);
    VERIFIE(e.marche == etats[i].marche && e.intensite == etats[i].intensite, "etat du banc %u : %d, %u", (unsigned)i,
            e.marche, (unsigned)e.intensite);
  }
  // Alimentation (0x0A) et produit (0x00) : sommes justes, mais pas des etats.
  const uint8_t alimentation[TELINK_TAILLE] = {0x86, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x31, 0x4B, 0x0A};
  const uint8_t produit[TELINK_TAILLE] = {0xB4, 0x03, 0x80, 0xA3, 0x7C, 0x08, 0x6E, 0x00, 0x9C, 0x00};
  telink_etat_t e;
  VERIFIE(telink_somme(alimentation) == alimentation[0] && !telink_lire_etat(alimentation, &e), "0x0A : pas un etat");
  VERIFIE(telink_somme(produit) == produit[0] && !telink_lire_etat(produit, &e), "0x00 : pas un etat");
  // Ordre d'intensite 700, capte a l'emission, du pont comme de l'app.
  const uint8_t v700[TELINK_TAILLE] = {0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAF, 0x8F};
  uint8_t t[TELINK_TAILLE];
  telink_intensite(700, t);
  VERIFIE(memcmp(t, v700, TELINK_TAILLE) == 0, "intensite 700 du banc");
}

int main(void) {
  test_demande_etat();
  test_marche();
  test_intensite();
  test_lire_etat();
  test_trames_du_banc();
  return bilan("telink");
}
