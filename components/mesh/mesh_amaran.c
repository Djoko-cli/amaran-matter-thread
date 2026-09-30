// Adhesion au reseau Bluetooth Mesh des lampes et file d'emission (spec 5.1,
// 5.4, 5.6).
//
// Adapte de main/mesh.c d'amaran-bridge :
// https://github.com/kevinschaich/amaran-bridge
// Suivent son code de pres : la sequence d'adhesion et la table d'opcodes du modele vendeur.
//
// MIT License
//
// Copyright (c) 2026 Kevin Schaich
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
#include "mesh_amaran.h"

#include <inttypes.h>
#include <string.h>

#include "sdkconfig.h"

#include "esp_idf_version.h"
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
// API publique ne permet d'entrer dans un reseau existant, ni de regler le
// balayage.
#include "local.h"        // bt_mesh_node_local_app_key_add, bt_mesh_node_bind_app_key_to_model
#include "mesh/atomic.h"  // bt_mesh_atomic_set_bit
#include "mesh/main.h"    // bt_mesh_provision
#include "net.h"          // bt_mesh : flags, seq, iv_index
#include "scan.h"         // bt_mesh_scan_param_update, struct bt_mesh_scan_param

#include "crochet.h"
#include "hote_ble.h"
#include "plancher.h"

// Ce composant lit des en-tetes internes de la pile (net.h, local.h, mesh/main.h)
// et en intercepte deux fonctions (--wrap) : tout y est verifie pour ESP-IDF
// v5.5.4 seulement.
#if ESP_IDF_VERSION != ESP_IDF_VERSION_VAL(5, 5, 4)
#error "components/mesh depend des internes d'ESP-IDF v5.5.4 : a reverifier avant de changer de version"
#endif

// Garde-fou : au-dessus d'ERROR, la pile Mesh imprime des cles (BT_WARN
// AppKeyValExist et NetKeyValExist dans core/local.c, BT_INFO NetKey et DevKey
// dans core/main.c, BT_DBG dans core/crypto.c). Le niveau est epingle dans
// ecoute/sdkconfig.defaults. Pas de BLE_MESH_NO_LOG : la spec 5.3 veut garder
// l'erreur "IVIndex out of sync" (BT_ERR). Symbole d'ESP-IDF (Kconfig.in) :
// 0 NONE, 1 ERROR, 2 WARNING, 3 INFO, 4 DEBUG, 5 VERBOSE.
#if defined(CONFIG_BLE_MESH_STACK_TRACE_LEVEL) && CONFIG_BLE_MESH_STACK_TRACE_LEVEL > 1
#error "Niveau de trace Bluetooth Mesh au-dessus d'ERROR : la pile imprimerait des cles du reseau. Choisir CONFIG_BLE_MESH_TRACE_LEVEL_ERROR (idf.py menuconfig, ou supprimer ecoute/sdkconfig pour le regenerer depuis sdkconfig.defaults)."
#endif

static const char *TAG = "mesh";

#define NET_IDX 0x0000
#define APP_IDX 0x0000
#define TTL 3
#define ECART_MS 70          // entre deux messages et entre deux repetitions
// vTaskDelay(n) dort entre n-1 et n ticks (60 a 70 ms a 100 Hz) : un tick de plus tient ECART_MS au moins.
#define ECART_TICKS (pdMS_TO_TICKS(ECART_MS) + 1)
#define FILE_TX 16

typedef struct {
  uint16_t dst;
  uint8_t repetitions;
  uint8_t trame[TELINK_TAILLE];
} message_tx_t;

static amaran_config_t s_cfg;
static QueueHandle_t s_tx;
static volatile bool s_pret;
static volatile bool s_emission_permise = true;
// Balayage en ms : la pile demarre a 0x20 unites de 0,625 ms pour la fenetre et
// l'intervalle (SCAN_WINDOW, SCAN_INTERVAL dans core/scan.c), soit 20 sur 20 ms.
static uint16_t s_fenetre_ms = 20;
static uint16_t s_intervalle_ms = 20;
static plancher_t s_plancher;  // compteur de sequence (spec 5.4), tenu par la tache d'emission
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
  // La sequence repart au-dessus de tout ce qui a pu partir avant (5.4). La NVS
  // garde deja le plancher : la tache d'emission sauve le bloc suivant avant le
  // premier envoi, et un echec de sauvegarde y bloque l'envoi.
  bt_mesh.seq = s_plancher.seq_min;
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

// Sequence bientot epuisee : l'adresse source suivante repart de zero (5.4).
// Sur ESP_OK l'appelant redemarre ; sinon rien n'a change.
static esp_err_t changer_d_adresse(uint32_t seq) {
  const uint16_t suivante =
      s_cfg.adresse >= AMARAN_ADRESSE_MAX ? AMARAN_ADRESSE_MIN : (uint16_t)(s_cfg.adresse + 1);
  ESP_LOGW(TAG, "sequence 0x%06" PRIx32 " presque epuisee : adresse 0x%04x", seq, suivante);
  const esp_err_t err = config_sauver_adresse(suivante);
  if (err != ESP_OK) ESP_LOGE(TAG, "adresse 0x%04x non sauvee : %s", suivante, esp_err_to_name(err));
  return err;
}

// Met la sequence en etat avant d'emettre a_consommer messages (un numero
// chacun), selon plancher.c. Faux : l'envoi est abandonne (NVS refusee, ou
// adresse suivante impossible a sauver).
static bool preparer_sequence(uint32_t a_consommer) {
  uint32_t seq = 0, nouveau = 0;
  // La pile remet la sequence a 0 lors d'une reprise d'IV Index (net.c), a tout
  // moment : on la lit une seule fois.
  switch (plancher_preparer(&s_plancher, bt_mesh.seq, a_consommer, &seq, &nouveau)) {
    case PLANCHER_ADRESSE_SUIVANTE:
      if (changer_d_adresse(seq) == ESP_OK) esp_restart();
      return false;
    case PLANCHER_SAUVER: {
      const esp_err_t err = config_sauver_plancher(nouveau);
      if (err != ESP_OK) {
        ESP_LOGE(TAG, "plancher de sequence non sauve : %s", esp_err_to_name(err));
        return false;
      }
      plancher_sauve(&s_plancher, nouveau);
      break;
    }
    case PLANCHER_ENVOYER:
      break;
  }
  bt_mesh.seq = seq;
  return true;
}

static void tache_tx(void *arg) {
  (void)arg;
  message_tx_t m;
  for (;;) {
    if (xQueueReceive(s_tx, &m, portMAX_DELAY) != pdTRUE) continue;
    // Pas d'emission avant l'adhesion, ni pendant que Matter s'annonce en BLE : un
    // seul jeu d'annonces existe, et chacun arreterait celle de l'autre (plan 2).
    while (!s_pret || !s_emission_permise) vTaskDelay(pdMS_TO_TICKS(100));
    if (!preparer_sequence(m.repetitions)) {
      s_echecs++;
      vTaskDelay(ECART_TICKS);
      continue;
    }
    esp_ble_mesh_msg_ctx_t ctx = {
        .net_idx = NET_IDX,
        .app_idx = APP_IDX,
        .addr = m.dst,
        .send_ttl = TTL,
    };
    esp_err_t err = ESP_OK;
    for (uint8_t r = 0; r < m.repetitions; r++) {
      // La pile peut remettre la sequence a 0 a tout moment (reprise d'IV) : on
      // la remonte avant chaque envoi, et le minimum ne fait que monter.
      bt_mesh.seq = plancher_remonter(&s_plancher, bt_mesh.seq);
      const uint32_t seq_envoi = bt_mesh.seq;
      err = esp_ble_mesh_server_model_send_msg(&s_vendeur[0], &ctx, TELINK_OPCODE, TELINK_TAILLE, m.trame);
      if (err != ESP_OK) break;
      plancher_parti(&s_plancher, seq_envoi);
      if (r + 1 < m.repetitions) vTaskDelay(ECART_TICKS);
    }
    if (err == ESP_OK) {
      s_emis++;
    } else {
      s_echecs++;
      ESP_LOGW(TAG, "envoi vers 0x%04x refuse : %s", m.dst, esp_err_to_name(err));
    }
    vTaskDelay(ECART_TICKS);
  }
}

// --- API

esp_err_t mesh_demarrer(const amaran_config_t *cfg) {
  if (!cfg->cles_presentes) return ESP_ERR_INVALID_STATE;
  s_cfg = *cfg;
  plancher_init(&s_plancher, s_cfg.plancher_seq);
  if (plancher_epuise(&s_plancher)) {
    // Si la NVS refuse l'adresse, pas de redemarrage : il bouclerait.
    if (changer_d_adresse(s_cfg.plancher_seq) != ESP_OK) return ESP_FAIL;
    esp_restart();
  }
  s_tx = xQueueCreate(FILE_TX, sizeof(message_tx_t));
  if (!s_tx) return ESP_ERR_NO_MEM;
  esp_err_t err = crochet_demarrer(&s_cfg);
  if (err != ESP_OK) return err;
  // L'hote NimBLE doit etre synchronise : demarre par hote_ble_demarrer() dans le
  // firmware d'ecoute, par la pile Matter dans celui du pont.
  for (int i = 0; i < 100 && !hote_ble_pret(); i++) vTaskDelay(pdMS_TO_TICKS(100));
  if (!hote_ble_pret()) return ESP_ERR_TIMEOUT;
  esp_read_mac(s_uuid, ESP_MAC_BT);
  // Erreurs seules : le relais coupe ferait avertir la pile a chaque message qu'elle
  // ne relaie pas. Seconde barriere pour les cles : les avertissements qui en
  // impriment (AppKeyValExist, NetKeyValExist dans local.c) ne sont deja plus
  // compiles au niveau ERROR que le garde-fou ci-dessus impose.
  esp_log_level_set("BLE_MESH", ESP_LOG_ERROR);
  esp_ble_mesh_register_prov_callback(rappel_prov);
  esp_ble_mesh_register_config_server_callback(rappel_cfg_srv);
  esp_ble_mesh_register_custom_model_callback(rappel_modele);
  err = esp_ble_mesh_init(&s_prov, &s_composition);
  if (err != ESP_OK) return err;
  if (xTaskCreate(tache_tx, "amaran_tx", 3072, NULL, 5, NULL) != pdPASS) return ESP_ERR_NO_MEM;
  // Role noeud pose a la main, et non par esp_ble_mesh_node_prov_enable() : celle-ci
  // lance aussi la balise « non provisionne » (notre UUID) le temps que
  // bt_mesh_provision() passe, et amaran Desktop pourrait la voir (spec 5.1).
  // bt_mesh_provision() demarre ensuite le scan (bt_mesh_net_start, net.c), et le
  // rappel de fin d'adhesion arrive comme avant (bt_mesh_prov_complete).
  bt_mesh_atomic_set_bit(bt_mesh.flags, BLE_MESH_NODE);
  const int rc = bt_mesh_provision(s_cfg.netkey, NET_IDX, 0, s_cfg.iv, s_cfg.adresse, s_cfg.devkey);
  if (rc) {
    bt_mesh_atomic_clear_bit(bt_mesh.flags, BLE_MESH_NODE);
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

uint32_t mesh_plancher(void) { return s_plancher.plancher_sauve; }

void mesh_autoriser_emission(bool oui) { s_emission_permise = oui; }

// La pile compte en unites de 0,625 ms : 8 unites font 5 ms, donc un multiple de
// 5 ms tombe juste (ms * 8 / 5).
#define BALAYAGE_MIN_MS 5
#define BALAYAGE_MAX_MS 1000
#define BALAYAGE_PAS_MS 5

esp_err_t mesh_regler_balayage(uint16_t fenetre_ms, uint16_t intervalle_ms) {
  if (fenetre_ms < BALAYAGE_MIN_MS || fenetre_ms > intervalle_ms || intervalle_ms > BALAYAGE_MAX_MS ||
      fenetre_ms % BALAYAGE_PAS_MS != 0 || intervalle_ms % BALAYAGE_PAS_MS != 0) {
    return ESP_ERR_INVALID_ARG;
  }
  if (!s_pret) return ESP_ERR_INVALID_STATE;
  struct bt_mesh_scan_param param = {
      .type = BLE_MESH_SCAN_PASSIVE,
#if CONFIG_BLE_MESH_USE_DUPLICATE_SCAN
      .filter_dup = BLE_MESH_SCAN_FILTER_DUP_ENABLE,
#else
      .filter_dup = BLE_MESH_SCAN_FILTER_DUP_DISABLE,
#endif
      .interval = (uint16_t)(intervalle_ms * 8 / 5),
      .window = (uint16_t)(fenetre_ms * 8 / 5),
      .scan_fil_policy = BLE_MESH_SP_ADV_ALL,
  };
  // Arrete le balayage et le relance avec ces deux valeurs seulement ; le reste
  // (type, doublons, filtre) est celui que la pile garde (core/scan.c).
  const int rc = bt_mesh_scan_param_update(&param);
  if (rc != 0) {
    ESP_LOGW(TAG, "balayage %u sur %u ms refuse par la pile (%d)", (unsigned)fenetre_ms, (unsigned)intervalle_ms, rc);
    return ESP_FAIL;
  }
  s_fenetre_ms = fenetre_ms;
  s_intervalle_ms = intervalle_ms;
  ESP_LOGI(TAG, "balayage regle : %u ms sur %u ms", (unsigned)fenetre_ms, (unsigned)intervalle_ms);
  return ESP_OK;
}

void mesh_balayage(uint16_t *fenetre_ms, uint16_t *intervalle_ms) {
  if (fenetre_ms) *fenetre_ms = s_fenetre_ms;
  if (intervalle_ms) *intervalle_ms = s_intervalle_ms;
}

int mesh_iv_chercher(uint32_t max, uint32_t *trouve) { return crochet_chercher_iv(max, trouve); }
