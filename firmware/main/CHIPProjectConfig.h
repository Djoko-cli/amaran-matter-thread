// Fiche produit du pont (spec 6.1), lue par la pile Matter (Basic Information).
// Le numero de serie, propre a la carte, est ecrit au demarrage (pont_matter.cpp).
#pragma once

#define CHIP_DEVICE_CONFIG_DEVICE_VENDOR_NAME "Djoko-CLI"
#define CHIP_DEVICE_CONFIG_DEVICE_PRODUCT_NAME "Pont amaran"
#define CHIP_DEVICE_CONFIG_DEFAULT_DEVICE_HARDWARE_VERSION_STRING "ESP32-C6 SuperMini"

// ConfigurationVersion (Basic Information, Matter 1.4 ; spec fiche des lampes 4) :
// sur ESP32, la pile rend cette constante et ne sait pas la ranger. Le pont la tient
// lui-meme, en NVS, et l'incremente quand ce qu'il expose change (pont_matter.cpp).
#include <stdint.h>
#ifdef __cplusplus
extern "C"
#endif
uint32_t pont_version_configuration(void);
#define CHIP_DEVICE_CONFIG_DEVICE_CONFIGURATION_VERSION pont_version_configuration()
