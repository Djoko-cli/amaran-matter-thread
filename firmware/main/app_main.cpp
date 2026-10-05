// Firmware du pont (plan 2) : Matter sur Thread vers Maison, Bluetooth Mesh vers
// les deux amaran 60d. Ordre de demarrage : spec 6.5 et 6.6.
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "console_pont.h"
#include "json_pont.h"
#include "mesh_amaran.h"
#include "net_udp.h"
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"

static const char *TAG = "pont";

// pont_demarrer expose les lampes sur la pile de main (sdkconfig.defaults) : un
// sdkconfig ancien, garde par erreur, l'aurait laissee a 4 Ko.
static_assert(CONFIG_ESP_MAIN_TASK_STACK_SIZE >= 6144, "supprimer firmware/sdkconfig : pile de main de 6 Ko");

static void ordre_matter(int lampe, const bool *marche, const uint16_t *intensite) {
  tache_lampes_ordre(lampe, marche, intensite, true);
}

// Marge de la pile de main (CONFIG_ESP_MAIN_TASK_STACK_SIZE), relevee au banc :
// la tache se termine a la fin d'app_main.
static void marge_main(void) {
  ESP_LOGI(TAG, "pile de main : %u o libres au plus bas", (unsigned)uxTaskGetStackHighWaterMark(NULL));
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
    // Pas de boucle de redemarrage : la console reste la pour diagnostiquer.
    ESP_LOGE(TAG, "reglages illisibles (%s) : sans Bluetooth Mesh", esp_err_to_name(err));
    cfg.cles_presentes = false;
  }
  // Le mode JSON d'abord : le socle, la console et la tache des lampes lui
  // envoient leurs evenements, et le numero de demarrage se tire avant toute radio.
  if (json_pont_demarrer(&cfg) != ESP_OK) ESP_LOGE(TAG, "mode JSON non demarre");
  // Puis le socle : la garde du bouton BOOT passe ainsi en dernier avant tout
  // reset, et le voyant montre l'etat des le demarrage.
  if (socle_demarrer() != ESP_OK) ESP_LOGE(TAG, "socle (voyant, bouton) non demarre");
  console_pont_demarrer(&cfg);
  ESP_ERROR_CHECK(tache_lampes_demarrer(&cfg));
  err = pont_demarrer(&cfg, ordre_matter);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "Matter non demarre : %s", esp_err_to_name(err));
    marge_main();
    return;
  }
  if (net_udp_demarrer() != ESP_OK) ESP_LOGE(TAG, "socket UDP non ouverte");
  if (!cfg.cles_presentes) {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
    marge_main();
    return;
  }
  // Le Bluetooth Mesh n'entre dans le reseau des lampes qu'une fois Maison
  // appairee : pendant la mise en service, CHIPoBLE a besoin des annonces (6.6).
  while (!pont_appaire() || pont_ble_annonce()) vTaskDelay(pdMS_TO_TICKS(500));
  vTaskDelay(pdMS_TO_TICKS(3000));  // la connexion BLE de mise en service se ferme
  // Banc C, levier 1 : le Mesh n'ecoute que la moitie du temps, pour laisser la radio a
  // Thread (a 100 %, plus aucune emission Thread ne passe). Retenu ici, pose dans la pile
  // par mesh_demarrer avant l'adhesion : le balayage ne tourne jamais a 100 %.
  err = mesh_regler_balayage(20, 40);
  if (err != ESP_OK) ESP_LOGE(TAG, "balayage du Bluetooth Mesh non regle : %s", esp_err_to_name(err));
  err = mesh_demarrer(&cfg);
  if (err != ESP_OK) ESP_LOGE(TAG, "Bluetooth Mesh non demarre : %s", esp_err_to_name(err));
  marge_main();
}
