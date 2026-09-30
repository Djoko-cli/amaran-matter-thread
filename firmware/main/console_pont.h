// Console du pont, en francais (spec 7.5).
#pragma once

#include "config_amaran.h"

#ifdef __cplusplus
extern "C" {
#endif

// Demarre la console sur l'USB natif. cfg reste la propriete de l'appelant.
void console_pont_demarrer(amaran_config_t *cfg);

#ifdef __cplusplus
}
#endif
