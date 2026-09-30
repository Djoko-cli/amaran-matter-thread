// Hote NimBLE du Bluetooth Mesh. Le firmware d'ecoute le demarre lui-meme ; dans
// le firmware du pont, c'est la pile Matter qui le demarre et le possede (spec
// 3.4, plan 2) : on attend seulement qu'il soit synchronise.
#pragma once

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Demarre l'hote NimBLE et attend sa synchronisation avec le controleur.
esp_err_t hote_ble_demarrer(void);
// Vrai quand l'hote NimBLE est synchronise (demarre par nous ou par Matter).
bool hote_ble_pret(void);

#ifdef __cplusplus
}
#endif
