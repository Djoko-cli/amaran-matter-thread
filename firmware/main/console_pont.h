// Console du pont, en francais (spec 7.5), et son mode machine
// (docs/PROTOCOLE-JSON.md, json_pont.h).
#pragma once

#include "config_amaran.h"

#ifdef __cplusplus
extern "C" {
#endif

// Taches dont `taches` et le bloc sante du protocole JSON donnent la marge de pile.
#define CONSOLE_PONT_NB_TACHES 11
extern const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES];

// Demarre la console sur l'USB natif, apres json_pont_demarrer. cfg reste la
// propriete de l'appelant.
void console_pont_demarrer(amaran_config_t *cfg);

#ifdef __cplusplus
}
#endif
