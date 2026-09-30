// Diagnostic du Bluetooth Mesh (voir diagnostic.h).
#include "diagnostic.h"

diagnostic_t diagnostic_mesh(bool cles, bool entre, const diagnostic_ecarts_t *e) {
  if (!cles) return DIAG_CLES_ABSENTES;
  if (!entre) return DIAG_PAS_ENTRE;
  if (e->annonces > 0 && e->nid_reconnu == 0) return DIAG_CLES_PERIMEES;
  if (e->netmic_faux > 0 && e->acces_dechiffres == 0) return DIAG_IV_FAUX;
  return DIAG_OK;
}

bool diagnostic_suivre(diagnostic_suivi_t *s, bool cles, bool entre, const diagnostic_ecarts_t *compteurs,
                       uint32_t maintenant_ms) {
  if (!s->lance) {
    s->lance = true;
    s->debut_ms = maintenant_ms;
    s->avant = *compteurs;
    s->etat = DIAG_OK;
  }
  diagnostic_t d = s->etat;
  const bool fenetre_finie = maintenant_ms - s->debut_ms >= DIAGNOSTIC_FENETRE_MS;
  if (!cles) {
    d = DIAG_CLES_ABSENTES;
  } else if (entre) {
    if (s->etat == DIAG_CLES_ABSENTES || s->etat == DIAG_PAS_ENTRE) d = DIAG_OK;  // vient d'entrer
    if (fenetre_finie) {
      const diagnostic_ecarts_t e = {
          compteurs->annonces - s->avant.annonces,
          compteurs->nid_reconnu - s->avant.nid_reconnu,
          compteurs->netmic_faux - s->avant.netmic_faux,
          compteurs->acces_dechiffres - s->avant.acces_dechiffres,
      };
      d = diagnostic_mesh(true, true, &e);
    }
  } else if (fenetre_finie) {
    d = DIAG_PAS_ENTRE;
  }
  if (fenetre_finie) {
    s->debut_ms = maintenant_ms;
    s->avant = *compteurs;
  }
  if (d == s->etat) return false;
  s->etat = d;
  return true;
}

const char *diagnostic_texte(diagnostic_t d) {
  switch (d) {
    case DIAG_OK:
      return "ok";
    case DIAG_CLES_ABSENTES:
      return "cles absentes : lancer outils/cles_amaran.py";
    case DIAG_PAS_ENTRE:
      return "pas entre dans le reseau des lampes (mise en service Matter faite ?)";
    case DIAG_CLES_PERIMEES:
      return "aucun message de notre reseau depuis 2 min : cles perimees ? (recharger avec outils/cles_amaran.py)";
    case DIAG_IV_FAUX:
      return "NetMIC faux sans message dechiffre : IV Index faux ? (mesh iv, ou mesh iv cherche)";
  }
  return "?";
}
