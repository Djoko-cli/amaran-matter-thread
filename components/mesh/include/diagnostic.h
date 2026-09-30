// Diagnostic du Bluetooth Mesh (spec 7.3), en C pur : a partir des compteurs du
// crochet sur une fenetre (en general 2 min), la cause probable d'une panne.
// Teste sur le Mac (tests/hote/test_diagnostic.c).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  DIAG_OK,
  DIAG_CLES_ABSENTES,  // jamais chargees, ou `mesh oublie`
  DIAG_PAS_ENTRE,      // cles la, mais pas (encore) dans le reseau
  DIAG_CLES_PERIMEES,  // des annonces Mesh, aucune de notre NID : reseau recree dans amaran Desktop ?
  DIAG_IV_FAUX,        // notre NID, NetMIC faux, rien de dechiffre : IV Index faux
} diagnostic_t;

#define DIAGNOSTIC_FENETRE_MS 120000u  // 2 min (spec 7.3)

// Compteurs du crochet (cumules), ou leurs ecarts sur une fenetre.
typedef struct {
  uint32_t annonces, nid_reconnu, netmic_faux, acces_dechiffres;
} diagnostic_ecarts_t;

// Cause probable, d'apres les ecarts de la fenetre ecoulee.
diagnostic_t diagnostic_mesh(bool cles, bool entre, const diagnostic_ecarts_t *e);

typedef struct {
  bool lance;
  uint32_t debut_ms;
  diagnostic_ecarts_t avant;  // compteurs au debut de la fenetre
  diagnostic_t etat;
} diagnostic_suivi_t;

// A appeler souvent (tache lampes) avec les compteurs cumules. Cles absentes :
// tout de suite. Pas entre dans le reseau : seulement au bout d'une fenetre
// (sinon rouge a chaque demarrage). Entree faite : l'alerte tombe aussitot. Le
// reste se juge aux ecarts de chaque fenetre de 2 min. Vrai si l'etat change.
bool diagnostic_suivre(diagnostic_suivi_t *s, bool cles, bool entre, const diagnostic_ecarts_t *compteurs,
                       uint32_t maintenant_ms);
// Texte de la console : cause et remede (spec 7.3).
const char *diagnostic_texte(diagnostic_t d);

#ifdef __cplusplus
}
#endif
