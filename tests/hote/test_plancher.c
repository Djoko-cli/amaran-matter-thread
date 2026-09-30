// Tests sur le Mac des regles du compteur de sequence Mesh (spec 5.4).
// Lancer : sh tests/hote/lancer.sh
#include "plancher.h"
#include "unite.h"

static void test_depart(void) {
  plancher_t p;
  uint32_t seq, nouveau;
  plancher_init(&p, 0);
  VERIFIE(plancher_preparer(&p, 0, 2, &seq, &nouveau) == PLANCHER_SAUVER && seq == 0 &&
              nouveau == 2 + PLANCHER_BLOC,
          "premier envoi : le plancher se sauve d'abord");
  plancher_sauve(&p, nouveau);
  VERIFIE(plancher_preparer(&p, 0, 2, &seq, &nouveau) == PLANCHER_ENVOYER, "plancher sauve : envoyer");
}

static void test_ne_redescend_jamais(void) {
  plancher_t p;
  uint32_t seq, nouveau;
  plancher_init(&p, 1000);
  plancher_parti(&p, 1000);
  plancher_parti(&p, 1001);
  VERIFIE(p.seq_min == 1002, "seq_min suit le plus haut numero parti");
  plancher_parti(&p, 500);
  VERIFIE(p.seq_min == 1002, "seq_min ne descend pas");
  VERIFIE(plancher_remonter(&p, 0) == 1002, "pile remise a 0 : remontee");
  VERIFIE(plancher_remonter(&p, 5000) == 5000, "pile plus haut : gardee");
  plancher_sauve(&p, 2000);
  (void)plancher_preparer(&p, 0, 1, &seq, &nouveau);
  VERIFIE(seq == 1002, "preparer remonte aussi");
  plancher_sauve(&p, 1500);
  VERIFIE(p.plancher_sauve == 2000, "le plancher sauve ne recule pas");
}

static void test_limite(void) {
  plancher_t p;
  uint32_t seq, nouveau;
  plancher_init(&p, PLANCHER_LIMITE - 2);
  VERIFIE(!plancher_epuise(&p), "juste sous la limite : pas epuise");
  VERIFIE(plancher_preparer(&p, 0, 2, &seq, &nouveau) == PLANCHER_SAUVER, "dernier bloc");
  VERIFIE(plancher_preparer(&p, PLANCHER_LIMITE - 1, 2, &seq, &nouveau) == PLANCHER_ADRESSE_SUIVANTE,
          "au-dela de la limite : adresse suivante");
  plancher_init(&p, PLANCHER_LIMITE + 1);
  VERIFIE(plancher_epuise(&p), "plancher lu au-dela de la limite : epuise");
}

// Simulation : la pile remet sa sequence a 0 a tout moment (reprise d'IV), la
// NVS refuse parfois d'ecrire, la carte redemarre, l'adresse change. A chaque
// message, les invariants de la spec 5.4.
static uint32_t g_alea = 12345;
static uint32_t alea(uint32_t n) {
  g_alea = g_alea * 1103515245u + 12345u;
  return ((g_alea >> 16) & 0x7FFF) % n;
}

static void test_simulation(void) {
  uint32_t nvs = PLANCHER_LIMITE - 60000;  // pres de la limite : l'adresse changera en route
  uint32_t pile;                           // bt_mesh.seq
  uint32_t dernier = 0;                    // plus haut numero parti a cette adresse
  bool deja = false;
  plancher_t p;
  plancher_init(&p, nvs);
  pile = nvs;  // fin d'adhesion : la pile repart du plancher
  unsigned violations = 0, envois = 0, redemarrages = 0, adresses = 0, refus = 0;
  for (int pas = 0; pas < 300000; pas++) {
    const uint32_t r = alea(1000);
    if (r < 5 || plancher_epuise(&p)) {  // redemarrage (ou plancher deja au-dela de la limite)
      if (plancher_epuise(&p)) {
        adresses++;
        nvs = 0;
        deja = false;
      }
      plancher_init(&p, nvs);
      pile = nvs;
      redemarrages++;
      continue;
    }
    if (r < 15) {
      pile = 0;  // reprise d'IV entre deux ordres
      continue;
    }
    const uint32_t a = 1 + alea(2);
    uint32_t seq, nouveau;
    const plancher_decision_t d = plancher_preparer(&p, pile, a, &seq, &nouveau);
    if (d == PLANCHER_ADRESSE_SUIVANTE) {  // adresse suivante sauvee, compteur remis a 0, redemarrage
      adresses++;
      nvs = 0;
      deja = false;
      plancher_init(&p, nvs);
      pile = nvs;
      continue;
    }
    if (d == PLANCHER_SAUVER) {
      if (alea(20) == 0) {  // la NVS refuse : rien ne part
        refus++;
        continue;
      }
      nvs = nouveau;
      plancher_sauve(&p, nouveau);
    }
    pile = seq;
    for (uint32_t k = 0; k < a; k++) {
      if (alea(50) == 0) pile = 0;  // reprise d'IV entre deux repetitions
      pile = plancher_remonter(&p, pile);
      const uint32_t envoi = pile++;  // la pile consomme un numero par message
      if (deja && envoi <= dernier) violations++;  // rejeu : les lampes le jetteraient
      if (envoi >= nvs) violations++;              // numero pas encore couvert par la NVS
      if (envoi > PLANCHER_LIMITE) violations++;   // la pile lancerait une mise a jour d'IV
      dernier = envoi;
      deja = true;
      envois++;
      plancher_parti(&p, envoi);
    }
  }
  VERIFIE(violations == 0, "%u violation(s) des invariants", violations);
  VERIFIE(envois > 100000 && redemarrages > 1000 && adresses >= 1 && refus > 100,
          "la simulation couvre tous les cas (%u envois, %u redemarrages, %u adresses, %u refus)", envois,
          redemarrages, adresses, refus);
}

int main(void) {
  test_depart();
  test_ne_redescend_jamais();
  test_limite();
  test_simulation();
  return bilan("plancher");
}
