// Firmware de reconnaissance (phase 0) : rejoint le reseau Bluetooth Mesh des
// lampes et donne une console pour les essais R1 a R6 (docs/BANC.md).
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "console_ecoute.h"
#include "mesh_amaran.h"

static const char *TAG = "ecoute";

void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS illisible : effacee (cles a recharger)");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  static amaran_config_t cfg;
  ESP_ERROR_CHECK(config_charger(&cfg));
  if (cfg.cles_presentes) {
    err = mesh_demarrer(&cfg);
    if (err == ESP_OK) {
      journal_demarrer(&cfg);
    } else {
      ESP_LOGE(TAG, "Bluetooth Mesh non demarre : %s", esp_err_to_name(err));
    }
  } else {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
  }
  console_demarrer(&cfg);
}
