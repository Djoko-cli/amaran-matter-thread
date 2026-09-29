// Hote NimBLE pour le Bluetooth Mesh, d'apres l'exemple d'ESP-IDF
// examples/bluetooth/esp_ble_mesh/common_components/example_init. Fichier a
// part : les en-tetes NimBLE et ceux de la pile Mesh ne se melangent pas.
#include "hote_ble.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"

static const char *TAG = "hote_ble";
static SemaphoreHandle_t s_synchro;

void ble_store_config_init(void);

static void reinitialise(int raison) { ESP_LOGW(TAG, "hote NimBLE reinitialise (raison %d)", raison); }

static void synchronise(void) {
  const int rc = ble_hs_util_ensure_addr(0);
  if (rc != 0) ESP_LOGE(TAG, "pas d'adresse BLE (%d)", rc);
  xSemaphoreGive(s_synchro);
}

static void tache_hote(void *arg) {
  (void)arg;
  nimble_port_run();
  nimble_port_freertos_deinit();
}

esp_err_t hote_ble_demarrer(void) {
  s_synchro = xSemaphoreCreateBinary();
  if (!s_synchro) return ESP_ERR_NO_MEM;
  const esp_err_t err = nimble_port_init();
  if (err != ESP_OK) return err;
  ble_hs_cfg.reset_cb = reinitialise;
  ble_hs_cfg.sync_cb = synchronise;
  ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
  ble_store_config_init();
  nimble_port_freertos_init(tache_hote);
  xSemaphoreTake(s_synchro, portMAX_DELAY);
  return ESP_OK;
}
