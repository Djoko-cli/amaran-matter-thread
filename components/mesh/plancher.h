// Regles du compteur de sequence Mesh de l'ESP32 (spec 5.4), en C pur, sorties
// de mesh_amaran.c pour etre testees sur le Mac (tests/hote/test_plancher.c) :
// - le plancher sauve en NVS devance toujours tout numero deja parti ;
// - la sequence ne redescend jamais, meme quand la pile la remet a 0 ;
// - l'adresse change avant le seuil de mise a jour d'IV de la pile.
// Une seule tache l'appelle (la tache d'emission) : pas de verrou ici.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PLANCHER_BLOC 256u  // le plancher sauve devance la sequence d'au plus ce bloc (plus le lot en cours)
// Sous le seuil ou la pile lance seule une mise a jour d'IV (IV_UPDATE_SEQ_LIMIT
// = 8000000 dans net.c) ; au-dela : adresse suivante (spec 5.4).
#define PLANCHER_LIMITE 0x700000u

typedef struct {
  uint32_t seq_min;         // plus haut numero parti + 1 : la sequence n'y redescend jamais
  uint32_t plancher_sauve;  // valeur gardee en NVS
} plancher_t;

typedef enum {
  PLANCHER_ENVOYER,           // la sequence est en etat : emettre
  PLANCHER_SAUVER,            // sauver *nouveau en NVS, puis plancher_sauve(), puis emettre
  PLANCHER_ADRESSE_SUIVANTE,  // la limite serait depassee : adresse suivante, puis redemarrer
} plancher_decision_t;

// Au demarrage, avec le plancher lu en NVS : la sequence repart de la.
void plancher_init(plancher_t *p, uint32_t plancher_nvs);
// Le plancher lu depasse deja la limite : adresse suivante avant tout envoi.
bool plancher_epuise(const plancher_t *p);
// Avant d'emettre a_consommer messages (un numero chacun). *seq : la sequence a
// donner a la pile (jamais sous seq_min). *nouveau : le plancher a sauver.
plancher_decision_t plancher_preparer(const plancher_t *p, uint32_t seq_pile, uint32_t a_consommer, uint32_t *seq,
                                      uint32_t *nouveau);
// La NVS a garde le nouveau plancher.
void plancher_sauve(plancher_t *p, uint32_t nouveau);
// Juste avant chaque message : la sequence a donner a la pile.
uint32_t plancher_remonter(const plancher_t *p, uint32_t seq_pile);
// Un message est parti avec le numero seq_envoi.
void plancher_parti(plancher_t *p, uint32_t seq_envoi);

#ifdef __cplusplus
}
#endif
