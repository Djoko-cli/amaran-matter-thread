// Crochet de reception (spec 5.5). Les lampes adressent leurs etats a 0x0001
// (amaran Desktop), et la pile jette ces messages. On intercepte ses deux
// points d'entree par l'editeur de liens (-Wl,--wrap, voir CMakeLists.txt) :
// la pile traite le message comme d'habitude, puis on dechiffre une COPIE a
// cote. Ne jamais rappeler bt_mesh_net_decode() : il inscrit le message dans
// le cache anti-doublon, et la pile rejetterait l'original.
#include "crochet.h"

#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "access.h"  // bt_mesh_rx_netkey_*, bt_mesh_rx_appkey_*
#include "crypto.h"  // bt_mesh_net_obfuscate, bt_mesh_ccm_decrypt_raw_key, bt_mesh_app_decrypt
#include "mesh/buf.h"
#include "net.h"

#include "crochet_tri.h"

#define FILE_EVENEMENTS 32
#define PDU_MIN 18  // plancher de la pile (net.c) : le plus court message reseau qu'elle accepte
#define PDU_MAX 32
#define BALISE_MAX 24
#define ECHANTILLONS 4
#define MIC_ACCES 4
#define IV_CHERCHE_MAX 0xFFFFFF  // plage documentee de crochet_chercher_iv (crochet.h)

static QueueHandle_t s_file;
static uint16_t s_lampes[AMARAN_LAMPES_MAX];
static volatile bool s_detail;
static mesh_stats_t s_st;
static uint32_t s_iv_connu;

// Messages de notre reseau au NetMIC faux : matiere de `mesh iv cherche`. La
// tache Bluetooth les remplace (garder_echantillon), la tache de la console les
// copie (crochet_chercher_iv) : toujours sous s_verrou.
static struct {
  uint8_t pdu[PDU_MAX];
  size_t len;
} s_echantillons[ECHANTILLONS];
static int s_echantillon_suivant;
static portMUX_TYPE s_verrou = portMUX_INITIALIZER_UNLOCKED;

// Faux si l'evenement est perdu (file pleine).
static bool publier(const mesh_evenement_t *ev) {
  if (xQueueSend(s_file, ev, 0) == pdTRUE) return true;
  s_st.file_pleine++;
  return false;
}

esp_err_t crochet_demarrer(const amaran_config_t *cfg) {
  for (int i = 0; i < AMARAN_LAMPES_MAX; i++) s_lampes[i] = cfg->lampes[i].adresse;
  s_iv_connu = cfg->iv;
  s_file = xQueueCreate(FILE_EVENEMENTS, sizeof(mesh_evenement_t));
  return s_file ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t crochet_file(void) { return s_file; }

void crochet_lire_stats(mesh_stats_t *stats) { memcpy(stats, &s_st, sizeof(*stats)); }

void crochet_ecoute_detaillee(bool oui) { s_detail = oui; }

int crochet_dechiffrer_reseau(const uint8_t enc[16], const uint8_t privacy[16], uint32_t iv, uint8_t *pdu,
                              size_t *len) {
  if (*len < PDU_MIN || *len > PDU_MAX) return -1;
  if (bt_mesh_net_obfuscate(pdu, iv, privacy)) return -1;
  // Ce que fait bt_mesh_net_decrypt(), sans lui : il journalise (BT_ERR) chaque
  // NetMIC faux, et ce chemin tourne dans la tache Bluetooth, une fois par copie
  // de message, ou une fois par IV candidat de la recherche.
  const size_t mic = (pdu[1] & 0x80) ? 8 : 4;  // CTL : NetMIC de 64 bits
  uint8_t nonce[13] = {0};                     // type reseau 0x00, deux octets de remplissage a 0
  memcpy(&nonce[1], &pdu[1], 6);               // CTL/TTL, SEQ (3), SRC (2), deja en clair
  nonce[9] = (uint8_t)(iv >> 24);
  nonce[10] = (uint8_t)(iv >> 16);
  nonce[11] = (uint8_t)(iv >> 8);
  nonce[12] = (uint8_t)iv;
  // DST et PDU de transport (des l'octet 7), NetMIC juste apres.
  if (bt_mesh_ccm_decrypt_raw_key(enc, nonce, &pdu[7], *len - mic - 7, NULL, 0, &pdu[7], mic)) return -2;
  *len -= mic;
  return 0;
}

int crochet_dechiffrer_acces(const uint8_t appkey[16], const uint8_t *clair, size_t len, uint32_t iv,
                             const uint8_t *ad, uint8_t *acces, size_t *acces_len) {
  tri_entete_t e = {0};
  if (!tri_lire_entete(clair, len, &e) || len < TRI_ENTETE_RESEAU + 1 + 1 + MIC_ACCES) return -1;
  const size_t n = len - TRI_ENTETE_RESEAU - 1 - MIC_ACCES;
  if (n > *acces_len) return -1;
  // La pile lit le TransMIC juste apres les n octets chiffres.
  struct net_buf_simple in, out;
  net_buf_simple_init_with_data(&in, (void *)(clair + TRI_ENTETE_RESEAU + 1), n);
  net_buf_simple_init_with_data(&out, acces, *acces_len);
  out.len = 0;
  if (bt_mesh_app_decrypt(appkey, false, 0, &in, &out, ad, e.src, e.dst, e.seq, iv)) return -2;
  *acces_len = out.len;
  return 0;
}

static uint32_t iv_du_message(uint8_t ivi) {
  const uint32_t iv = bt_mesh.iv_index;
  return (ivi != (iv & 0x01)) ? iv - 1 : iv;
}

static void garder_echantillon(const uint8_t *pdu, size_t len) {
  portENTER_CRITICAL(&s_verrou);
  memcpy(s_echantillons[s_echantillon_suivant].pdu, pdu, len);
  s_echantillons[s_echantillon_suivant].len = len;
  s_echantillon_suivant = (s_echantillon_suivant + 1) % ECHANTILLONS;
  portEXIT_CRITICAL(&s_verrou);
}

// Copie l'echantillon e d'un seul tenant et rend sa longueur (0 : emplacement
// vide). Rien d'autre dans la section critique : ni chiffrement, ni attente.
static size_t copier_echantillon(int e, uint8_t copie[PDU_MAX]) {
  portENTER_CRITICAL(&s_verrou);
  const size_t len = s_echantillons[e].len;
  memcpy(copie, s_echantillons[e].pdu, len);
  portEXIT_CRITICAL(&s_verrou);
  return len;
}

static void traiter_acces(const tri_entete_t *e, const uint8_t *acces, size_t n) {
  s_st.acces_dechiffres++;
  mesh_evenement_t ev = {
      .type = MESH_EV_ACCES,
      .quand_us = esp_timer_get_time(),
      .src = e->src,
      .dst = e->dst,
      .lampe = -1,
      .len = (uint8_t)n,
  };
  memcpy(ev.acces, acces, n);
  uint8_t trame[TELINK_TAILLE];
  const int l = tri_etat_lampe(e->src, acces, n, s_lampes, AMARAN_LAMPES_MAX, trame);
  if (l >= 0) {
    ev.type = MESH_EV_ETAT_LAMPE;
    ev.lampe = (int8_t)l;
    s_st.etats_lampes++;
    s_st.derniere_reponse_us[l] = ev.quand_us;
    publier(&ev);
  } else if (s_detail) {
    publier(&ev);
  }
}

static void traiter(const uint8_t *pdu, size_t len) {
  s_st.annonces++;
  const uint8_t nid = pdu[0] & 0x7F;
  const uint32_t iv = iv_du_message(pdu[0] >> 7);
  bool reconnu = false;
  for (size_t i = 0; i < bt_mesh_rx_netkey_size(); i++) {
    struct bt_mesh_subnet *sub = bt_mesh_rx_netkey_get(i);
    if (!sub || sub->net_idx == BLE_MESH_KEY_UNUSED) continue;
    for (int k = 0; k < 2; k++) {
      if (k == 1 && sub->kr_phase == BLE_MESH_KR_NORMAL) break;
      if (sub->keys[k].nid != nid) continue;
      if (!reconnu) {
        reconnu = true;
        s_st.nid_reconnu++;
      }
      uint8_t clair[PDU_MAX];
      size_t n = len;
      memcpy(clair, pdu, len);
      if (crochet_dechiffrer_reseau(sub->keys[k].enc, sub->keys[k].privacy, iv, clair, &n)) {
        s_st.netmic_faux++;
        garder_echantillon(pdu, len);
        continue;
      }
      tri_entete_t e = {0};
      if (!tri_lire_entete(clair, n, &e) || e.ctl || n <= TRI_ENTETE_RESEAU) return;
      tri_transport_t t;
      tri_lire_transport(clair[TRI_ENTETE_RESEAU], &t);
      if (t.segmente || !t.akf) return;
      for (size_t j = 0; j < bt_mesh_rx_appkey_size(); j++) {
        struct bt_mesh_app_key *cle = bt_mesh_rx_appkey_get(j);
        if (!cle || cle->net_idx != sub->net_idx) continue;
        const struct bt_mesh_app_keys *ak = (k == 1 && cle->updated) ? &cle->keys[1] : &cle->keys[0];
        if (ak->id != t.aid) continue;
        uint8_t acces[16];
        size_t na = sizeof(acces);
        if (crochet_dechiffrer_acces(ak->val, clair, n, iv, NULL, acces, &na) == 0) {
          traiter_acces(&e, acces, na);
          return;
        }
      }
      return;
    }
  }
  if (!reconnu) s_st.nid_inconnu++;
}

void __real_bt_mesh_generic_net_recv(struct net_buf_simple *data, struct bt_mesh_net_rx *rx,
                                     enum bt_mesh_net_if net_if);

void __wrap_bt_mesh_generic_net_recv(struct net_buf_simple *data, struct bt_mesh_net_rx *rx,
                                     enum bt_mesh_net_if net_if) {
  uint8_t copie[PDU_MAX];
  const size_t n = data->len;
  const bool garder = s_file && net_if == BLE_MESH_NET_IF_ADV && n >= PDU_MIN && n <= sizeof(copie);
  if (garder) memcpy(copie, data->data, n);
  __real_bt_mesh_generic_net_recv(data, rx, net_if);
  if (garder) traiter(copie, n);
}

void __real_bt_mesh_beacon_recv(struct net_buf_simple *buf, int8_t rssi);

void __wrap_bt_mesh_beacon_recv(struct net_buf_simple *buf, int8_t rssi) {
  uint8_t copie[BALISE_MAX];
  const size_t n = buf->len;
  const bool garder = s_file && n <= sizeof(copie);
  if (garder) memcpy(copie, buf->data, n);
  __real_bt_mesh_beacon_recv(buf, rssi);
  if (!garder) return;
  tri_balise_t b;
  if (tri_lire_balise(copie, n, &b)) {
    struct bt_mesh_subnet *sub = bt_mesh_rx_netkey_size() ? bt_mesh_rx_netkey_get(0) : NULL;
    if (sub && sub->net_idx != BLE_MESH_KEY_UNUSED && memcmp(sub->keys[0].net_id, b.net_id, sizeof(b.net_id)) == 0) {
      s_st.balises_notres++;
      s_st.derniere_balise_us = esp_timer_get_time();
      s_st.derniere_balise_iv = b.iv_index;
      s_st.derniere_balise_flags = b.flags;
      if (s_detail) {
        mesh_evenement_t ev = {
            .type = MESH_EV_BALISE, .quand_us = s_st.derniere_balise_us, .lampe = -1, .iv = b.iv_index,
            .flags = b.flags,
        };
        publier(&ev);
      }
    } else {
      s_st.balises_autres++;
    }
  }
  // La pile refuse tout IV Index plus bas que le sien (net.c) : apres l'adhesion il
  // ne fait que monter. Ne publier que ce qui depasse ce que la console connait
  // deja evite l'IV Index 0 d'avant l'adhesion (bt_mesh_provision le pose apres
  // le demarrage du scan), et s_iv_connu n'avance qu'une fois l'evenement parti :
  // file pleine, la balise suivante retente.
  const uint32_t iv = bt_mesh.iv_index;
  if (iv > s_iv_connu) {
    mesh_evenement_t ev = {.type = MESH_EV_IV_CHANGE, .quand_us = esp_timer_get_time(), .lampe = -1, .iv = iv};
    if (publier(&ev)) s_iv_connu = iv;
  }
}

int crochet_chercher_iv(uint32_t max, uint32_t *trouve) {
  struct bt_mesh_subnet *sub = bt_mesh_rx_netkey_size() ? bt_mesh_rx_netkey_get(0) : NULL;
  if (!sub || sub->net_idx == BLE_MESH_KEY_UNUSED) return -1;
  if (max > IV_CHERCHE_MAX) max = IV_CHERCHE_MAX;  // plus haut, iv += 2 finirait par reboucler
  int cherches = 0;     // emplacements pleins essayes
  uint32_t essais = 0;  // candidats essayes, tous emplacements confondus
  for (int e = 0; e < ECHANTILLONS; e++) {
    // La tache Bluetooth remplace les echantillons pendant cette recherche, qui
    // dure des secondes : chaque emplacement est copie d'un seul tenant quand
    // vient son tour, et tout le travail se fait sur cette copie (sinon copie
    // dechiree, ou parite de l'IVI changee en route).
    uint8_t garde[PDU_MAX];
    const size_t len = copier_echantillon(e, garde);
    if (len == 0) continue;
    cherches++;
    const uint8_t ivi = garde[0] >> 7;
    for (uint32_t iv = ivi; iv <= max; iv += 2) {  // meme parite que le bit IVI
      uint8_t essai[PDU_MAX];  // le dechiffrement travaille en place
      size_t n = len;
      memcpy(essai, garde, len);
      if (crochet_dechiffrer_reseau(sub->keys[0].enc, sub->keys[0].privacy, iv, essai, &n) == 0) {
        *trouve = iv;
        return 0;
      }
      if (++essais % 1024 == 0) vTaskDelay(1);  // laisser tourner les autres taches
    }
  }
  return cherches ? 1 : 2;
}
