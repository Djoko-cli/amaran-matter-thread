// Adhesion au reseau Bluetooth Mesh des lampes et file d'emission (spec 5.1,
// 5.4, 5.6). Sequence d'adhesion reprise d'amaran-bridge (Kevin Schaich, MIT) :
// role noeud, bt_mesh_provision(), puis AppKey et liaison au modele vendeur a
// la fin du provisionnement.
#include "mesh_amaran.h"

#include <inttypes.h>
#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "esp_ble_mesh_common_api.h"
#include "esp_ble_mesh_config_model_api.h"
#include "esp_ble_mesh_defs.h"
#include "esp_ble_mesh_networking_api.h"
#include "esp_ble_mesh_provisioning_api.h"

// En-tetes internes de la pile (chemins ajoutes par CMakeLists.txt) : aucune
// API publique ne permet d'entrer dans un reseau existant.
#include "local.h"      // bt_mesh_node_local_app_key_add, bt_mesh_node_bind_app_key_to_model
#include "mesh/main.h"  // bt_mesh_provision
#include "net.h"        // bt_mesh : seq, iv_index

#include "crochet.h"
#include "hote_ble.h"

static const char *TAG = "mesh";

#define NET_IDX 0x0000
#define APP_IDX 0x0000
#define TTL 3
#define ECART_MS 70          // entre deux messages et entre deux repetitions
#define FILE_TX 16
#define BLOC_SEQ 256         // le plancher sauve devance toujours la sequence
#define SEQ_LIMITE 0xF00000  // au-dela : adresse suivante (spec 5.4)

typedef struct {
  uint16_t dst;
  uint8_t repetitions;
  uint8_t trame[TELINK_TAILLE];
} message_tx_t;

static amaran_config_t s_cfg;
static QueueHandle_t s_tx;
static volatile bool s_pret;
static uint32_t s_plancher_sauve;
static uint32_t s_emis;
static uint32_t s_echecs;

static esp_ble_mesh_cfg_srv_t s_cfg_srv = {
    .net_transmit = ESP_BLE_MESH_TRANSMIT(2, 20),  // 3 copies a 20 ms
    .relay = ESP_BLE_MESH_RELAY_NOT_SUPPORTED,
    .beacon = ESP_BLE_MESH_BEACON_DISABLED,
    .friend_state = ESP_BLE_MESH_FRIEND_NOT_SUPPORTED,
    .gatt_proxy = ESP_BLE_MESH_GATT_PROXY_NOT_SUPPORTED,
    .default_ttl = TTL,
};

static esp_ble_mesh_model_t s_racine[] = {
    ESP_BLE_MESH_MODEL_CFG_SRV(&s_cfg_srv),
};

// Forme a 3 octets pour que l'AppKey ait un modele ou se lier, et forme a 1
// octet (0x26), celle qu'emploient vraiment les lampes.
static esp_ble_mesh_model_op_t s_ops[] = {
    ESP_BLE_MESH_MODEL_OP(ESP_BLE_MESH_MODEL_OP_3(TELINK_OPCODE, TELINK_CID), 1),
    ESP_BLE_MESH_MODEL_OP(TELINK_OPCODE, 1),
    ESP_BLE_MESH_MODEL_OP_END,
};

static esp_ble_mesh_model_t s_vendeur[] = {
    ESP_BLE_MESH_VENDOR_MODEL(TELINK_CID, 0x0000, s_ops, NULL, NULL),
};

static esp_ble_mesh_elem_t s_elements[] = {
    ESP_BLE_MESH_ELEMENT(0, s_racine, s_vendeur),
};

static esp_ble_mesh_comp_t s_composition = {
    .cid = TELINK_CID,
    .element_count = 1,
    .elements = s_elements,
};

static uint8_t s_uuid[16];
static esp_ble_mesh_prov_t s_prov = {.uuid = s_uuid};

// --- Adhesion

static void fin_adhesion(void) {
  int rc = bt_mesh_node_local_app_key_add(NET_IDX, APP_IDX, s_cfg.appkey);
  if (rc) {
    ESP_LOGE(TAG, "AppKey refusee (%d)", rc);
    return;
  }
  rc = bt_mesh_node_bind_app_key_to_model(s_cfg.adresse, 0x0000, TELINK_CID, APP_IDX);
  if (rc) {
    ESP_LOGE(TAG, "liaison de l'AppKey refusee (%d)", rc);
    return;
  }
  // La sequence repart au-dessus de tout ce qui a pu partir avant (5.4).
  bt_mesh.seq = s_cfg.plancher_seq;
  s_plancher_sauve = s_cfg.plancher_seq + BLOC_SEQ;
  config_sauver_plancher(s_plancher_sauve);
  s_pret = true;
  ESP_LOGI(TAG, "pret : adresse 0x%04x, IV 0x%08" PRIx32 ", sequence 0x%06" PRIx32, s_cfg.adresse,
           (uint32_t)bt_mesh.iv_index, (uint32_t)bt_mesh.seq);
}

static void rappel_prov(esp_ble_mesh_prov_cb_event_t ev, esp_ble_mesh_prov_cb_param_t *p) {
  if (ev == ESP_BLE_MESH_NODE_PROV_COMPLETE_EVT) {
    ESP_LOGI(TAG, "entre dans le reseau, adresse 0x%04x", p->node_prov_complete.addr);
    fin_adhesion();
  }
}

static void rappel_cfg_srv(esp_ble_mesh_cfg_server_cb_event_t ev, esp_ble_mesh_cfg_server_cb_param_t *p) {
  (void)ev;
  (void)p;  // personne ne configure ce noeud
}

static void rappel_modele(esp_ble_mesh_model_cb_event_t ev, esp_ble_mesh_model_cb_param_t *p) {
  (void)ev;
  (void)p;  // les etats arrivent par le crochet, pas ici
}

// --- Emission

static void verifier_plancher(uint32_t a_consommer) {
  if (bt_mesh.seq + a_consommer >= s_plancher_sauve) {
    s_plancher_sauve = bt_mesh.seq + a_consommer + BLOC_SEQ;
    config_sauver_plancher(s_plancher_sauve);
  }
}

static void tache_tx(void *arg) {
  (void)arg;
  message_tx_t m;
  for (;;) {
    if (xQueueReceive(s_tx, &m, portMAX_DELAY) != pdTRUE) continue;
    while (!s_pret) vTaskDelay(pdMS_TO_TICKS(100));
    verifier_plancher(m.repetitions);
    esp_ble_mesh_msg_ctx_t ctx = {
        .net_idx = NET_IDX,
        .app_idx = APP_IDX,
        .addr = m.dst,
        .send_ttl = TTL,
    };
    esp_err_t err = ESP_OK;
    for (uint8_t r = 0; r < m.repetitions; r++) {
      err = esp_ble_mesh_server_model_send_msg(&s_vendeur[0], &ctx, TELINK_OPCODE, TELINK_TAILLE, m.trame);
      if (err != ESP_OK) break;
      if (r + 1 < m.repetitions) vTaskDelay(pdMS_TO_TICKS(ECART_MS));
    }
    if (err == ESP_OK) {
      s_emis++;
    } else {
      s_echecs++;
      ESP_LOGW(TAG, "envoi vers 0x%04x refuse : %s", m.dst, esp_err_to_name(err));
    }
    vTaskDelay(pdMS_TO_TICKS(ECART_MS));
  }
}

// --- API

esp_err_t mesh_demarrer(const amaran_config_t *cfg) {
  if (!cfg->cles_presentes) return ESP_ERR_INVALID_STATE;
  s_cfg = *cfg;
  if (s_cfg.plancher_seq > SEQ_LIMITE) {
    const uint16_t suivante =
        s_cfg.adresse >= AMARAN_ADRESSE_MAX ? AMARAN_ADRESSE_MIN : (uint16_t)(s_cfg.adresse + 1);
    ESP_LOGW(TAG, "sequence 0x%06" PRIx32 " presque epuisee : adresse 0x%04x", s_cfg.plancher_seq, suivante);
    config_sauver_adresse(suivante);
    esp_restart();
  }
  s_tx = xQueueCreate(FILE_TX, sizeof(message_tx_t));
  if (!s_tx) return ESP_ERR_NO_MEM;
  esp_err_t err = crochet_demarrer(&s_cfg);
  if (err != ESP_OK) return err;
  err = hote_ble_demarrer();
  if (err != ESP_OK) return err;
  esp_read_mac(s_uuid, ESP_MAC_BT);
  // Relais coupe : la pile avertirait pour chaque message qu'elle ne relaie pas.
  esp_log_level_set("BLE_MESH", ESP_LOG_ERROR);
  esp_ble_mesh_register_prov_callback(rappel_prov);
  esp_ble_mesh_register_config_server_callback(rappel_cfg_srv);
  esp_ble_mesh_register_custom_model_callback(rappel_modele);
  err = esp_ble_mesh_init(&s_prov, &s_composition);
  if (err != ESP_OK) return err;
  if (xTaskCreate(tache_tx, "amaran_tx", 3072, NULL, 5, NULL) != pdPASS) return ESP_ERR_NO_MEM;
  // Le role noeud doit etre actif pour que bt_mesh_provision() tienne.
  err = esp_ble_mesh_node_prov_enable(ESP_BLE_MESH_PROV_ADV);
  if (err != ESP_OK) return err;
  const int rc = bt_mesh_provision(s_cfg.netkey, NET_IDX, 0, s_cfg.iv, s_cfg.adresse, s_cfg.devkey);
  esp_ble_mesh_node_prov_disable(ESP_BLE_MESH_PROV_ADV);
  if (rc) {
    ESP_LOGE(TAG, "bt_mesh_provision a echoue (%d)", rc);
    return ESP_FAIL;
  }
  return ESP_OK;
}

bool mesh_pret(void) { return s_pret; }

esp_err_t mesh_envoyer(uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions) {
  if (!s_tx) return ESP_ERR_INVALID_STATE;
  message_tx_t m = {.dst = dst, .repetitions = repetitions ? repetitions : 1};
  memcpy(m.trame, trame, TELINK_TAILLE);
  return xQueueSend(s_tx, &m, 0) == pdTRUE ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t mesh_file_evenements(void) { return crochet_file(); }

void mesh_ecoute_detaillee(bool oui) { crochet_ecoute_detaillee(oui); }

void mesh_lire_stats(mesh_stats_t *stats) {
  crochet_lire_stats(stats);
  stats->emis = s_emis;
  stats->echecs_emission = s_echecs;
}

uint32_t mesh_iv_courant(void) { return bt_mesh.iv_index; }

uint32_t mesh_sequence(void) { return bt_mesh.seq; }
