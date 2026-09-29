// Firmware de reconnaissance (phase 0) : reglages lus au demarrage.
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"

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
  char en[9] = "-", ea[9] = "-";
  if (cfg.cles_presentes) {
    config_empreinte(cfg.netkey, en);
    config_empreinte(cfg.appkey, ea);
  }
  ESP_LOGI(TAG, "adresse 0x%04x, IV 0x%08lx, cles %s/%s, %u lampe(s)", cfg.adresse, (unsigned long)cfg.iv, en, ea,
           (unsigned)cfg.nb_lampes);
}
