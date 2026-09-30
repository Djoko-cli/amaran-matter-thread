// La WS2812 de la C6 SuperMini (IO8), par le RMT d'ESP-IDF.
#pragma once

#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// A appeler apres le demarrage (IO8 est une broche de strapping) : met la LED au noir.
esp_err_t ws2812_demarrer(int gpio);
// Une couleur (0..255 par canal), envoyee dans l'ordre G, R, B de la WS2812.
esp_err_t ws2812_ecrire(uint8_t r, uint8_t g, uint8_t b);

#ifdef __cplusplus
}
#endif
