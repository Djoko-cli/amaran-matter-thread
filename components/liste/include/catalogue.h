// Catalogue des modeles de lampes (spec N lampes 6) : pour chaque code produit
// Sidus, le nom du modele, ses capacites et le type d'appareil Matter qui en
// decoule. Le firmware en est la source unique. C pur, teste sur le Mac.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CATALOGUE_CODE_COB_60D 40065u

enum {
  CATALOGUE_INTENSITE = 1u << 0,
  CATALOGUE_CCT = 1u << 1,      // temperature de couleur (Light CTL)
  CATALOGUE_COULEUR = 1u << 2,  // couleur (Light HSL)
};

typedef enum {
  CATALOGUE_LAMPE_VARIABLE,     // Dimmable Light : marche et intensite
  CATALOGUE_LAMPE_TEMPERATURE,  // Color Temperature Light (pas encore realise)
  CATALOGUE_LAMPE_COULEUR,      // Extended Color Light (pas encore realise)
} catalogue_type_t;

typedef struct {
  uint32_t code;                // code produit Sidus ; 0 : le repli
  const char *nom;
  uint8_t capacites;            // CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR
  uint16_t cct_min_k, cct_max_k;  // 0 sans CCT
  catalogue_type_t type;
} catalogue_modele_t;

// Le modele de ce code ; un code inconnu donne le repli (intensite seule, lampe a
// intensite variable). Jamais NULL.
const catalogue_modele_t *catalogue_trouver(uint32_t code);
bool catalogue_connu(uint32_t code);
// "intensite", "intensite+cct", "intensite+couleur"... : les capacites, en mots
// (console, et reponse de `mesh lampe` que lit outils/cles_amaran.py).
const char *catalogue_capacites_texte(uint8_t capacites);
// Les modeles catalogues un a un (i < catalogue_nombre()), et le repli : le
// catalogue du protocole JSON (docs/PROTOCOLE-JSON.md, config.catalogue).
unsigned catalogue_nombre(void);
const catalogue_modele_t *catalogue_modele(unsigned i);
const catalogue_modele_t *catalogue_repli(void);

#ifdef __cplusplus
}
#endif
