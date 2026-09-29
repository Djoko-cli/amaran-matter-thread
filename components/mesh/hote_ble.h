#pragma once

#include "esp_err.h"

// Demarre l'hote NimBLE et attend sa synchronisation avec le controleur.
esp_err_t hote_ble_demarrer(void);
