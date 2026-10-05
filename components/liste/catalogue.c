// Catalogue des modeles de lampes (voir catalogue.h). Ajouter un modele : une
// entree ici, puis le banc avec la vraie lampe.
#include "catalogue.h"

static const catalogue_modele_t MODELES[] = {
    {CATALOGUE_CODE_COB_60D, "amaran COB 60d", CATALOGUE_INTENSITE, 0, 0, CATALOGUE_LAMPE_VARIABLE},
};

// Trames 0x8C (marche) et 0x8F (intensite) : communes au protocole Sidus.
static const catalogue_modele_t REPLI = {0, "modele non catalogue", CATALOGUE_INTENSITE, 0, 0,
                                         CATALOGUE_LAMPE_VARIABLE};

const catalogue_modele_t *catalogue_trouver(uint32_t code) {
  for (unsigned i = 0; i < sizeof(MODELES) / sizeof(MODELES[0]); i++) {
    if (MODELES[i].code == code) return &MODELES[i];
  }
  return &REPLI;
}

bool catalogue_connu(uint32_t code) { return code != 0 && catalogue_trouver(code) != &REPLI; }

unsigned catalogue_nombre(void) { return sizeof(MODELES) / sizeof(MODELES[0]); }

const catalogue_modele_t *catalogue_modele(unsigned i) { return i < catalogue_nombre() ? &MODELES[i] : &REPLI; }

const catalogue_modele_t *catalogue_repli(void) { return &REPLI; }

const char *catalogue_capacites_texte(uint8_t capacites) {
  switch (capacites & (CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR)) {
    case CATALOGUE_INTENSITE:
      return "intensite";
    case CATALOGUE_INTENSITE | CATALOGUE_CCT:
      return "intensite+cct";
    case CATALOGUE_INTENSITE | CATALOGUE_COULEUR:
      return "intensite+couleur";
    case CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR:
      return "intensite+cct+couleur";
    default:
      return "aucune";
  }
}
