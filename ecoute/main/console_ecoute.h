// Console et journal du firmware de reconnaissance (phase 0).
#pragma once

#include "config_amaran.h"

// Demarre la console sur l'USB natif. cfg reste la propriete de l'appelant.
void console_demarrer(amaran_config_t *cfg);
// Demarre la tache qui imprime les evenements du crochet.
void journal_demarrer(amaran_config_t *cfg);
