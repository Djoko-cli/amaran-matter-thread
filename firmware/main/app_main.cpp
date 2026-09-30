// Firmware du pont (plan 2) : Matter sur Thread vers Maison, Bluetooth Mesh vers
// les deux amaran 60d. Ordre de demarrage : spec 6.5 et 6.6.
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "pont_matter.h"

static const char *TAG = "pont";

// Provisoire : la tache lampes (Task 7) recevra ces ordres.
static void ordre_matter(int lampe, const bool *marche, const uint16_t *intensite) {
  ESP_LOGI(TAG, "ordre Matter, lampe %d : marche %d, intensite %d", lampe + 1, marche ? (int)*marche : -1,
           intensite ? (int)*intensite : -1);
}

extern "C" void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS illisible : effacee (mise en service et cles a refaire)");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  static amaran_config_t cfg;
  err = config_charger(&cfg);
  if (err != ESP_OK) {
    // Pas de boucle de redemarrage : on demarre sans Bluetooth Mesh.
    ESP_LOGE(TAG, "reglages illisibles (%s) : sans Bluetooth Mesh", esp_err_to_name(err));
    cfg.cles_presentes = false;
  }
  err = pont_demarrer(&cfg, ordre_matter);
  if (err != ESP_OK) ESP_LOGE(TAG, "Matter non demarre : %s", esp_err_to_name(err));
}
