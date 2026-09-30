// Regles du compteur de sequence Mesh (voir plancher.h).
#include "plancher.h"

void plancher_init(plancher_t *p, uint32_t plancher_nvs) {
  p->seq_min = plancher_nvs;
  p->plancher_sauve = plancher_nvs;
}

bool plancher_epuise(const plancher_t *p) { return p->plancher_sauve > PLANCHER_LIMITE; }

uint32_t plancher_remonter(const plancher_t *p, uint32_t seq_pile) {
  // La pile remet la sequence a 0 lors d'une reprise d'IV Index (net.c), a tout
  // moment : sans cela, (IV, sequence) resservirait apres un redemarrage et les
  // lampes rejetteraient nos messages comme des rejeux.
  return seq_pile < p->seq_min ? p->seq_min : seq_pile;
}

plancher_decision_t plancher_preparer(const plancher_t *p, uint32_t seq_pile, uint32_t a_consommer, uint32_t *seq,
                                      uint32_t *nouveau) {
  *seq = plancher_remonter(p, seq_pile);
  *nouveau = p->plancher_sauve;
  if (*seq + a_consommer > PLANCHER_LIMITE) return PLANCHER_ADRESSE_SUIVANTE;
  // Le plancher en NVS devance toujours la sequence : il est releve, et sauve,
  // avant que les numeros correspondants partent.
  if (*seq + a_consommer >= p->plancher_sauve) {
    *nouveau = *seq + a_consommer + PLANCHER_BLOC;
    return PLANCHER_SAUVER;
  }
  return PLANCHER_ENVOYER;
}

void plancher_sauve(plancher_t *p, uint32_t nouveau) {
  if (nouveau > p->plancher_sauve) p->plancher_sauve = nouveau;
}

void plancher_parti(plancher_t *p, uint32_t seq_envoi) {
  if (seq_envoi + 1 > p->seq_min) p->seq_min = seq_envoi + 1;
}
