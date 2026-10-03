// Tache du coeur du pont (voir tache_lampes.h).
#include "tache_lampes.h"

#include <stdio.h>
#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "diagnostic.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
#include "pont_matter.h"
#include "socle.h"

#define TIC_MS 50
#define FILE_ORDRES 16

typedef enum { MSG_ORDRE, MSG_RELEVE } message_type_t;

typedef struct {
  message_type_t type;
  int8_t lampe;
  bool a_marche, marche, a_intensite, depuis_matter;
  uint16_t intensite;
  uint32_t releve_ms;
} message_t;

static QueueHandle_t s_file;
static SemaphoreHandle_t s_verrou;  // s_lampes, lu en copie par la console
static lampes_t s_lampes;
static volatile bool s_ecoute;
static volatile uint32_t s_confirmes, s_abandons;
static bool s_cles;                  // cles du reseau presentes au demarrage
static diagnostic_suivi_t s_diag;    // Bluetooth Mesh inoperant (spec 7.3)

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static bool sortie_envoyer(void *ctx, uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions) {
  (void)ctx;
  return mesh_envoyer(dst, trame, repetitions) == ESP_OK;
}

static void sortie_publier(void *ctx, int lampe, const lampe_etat_t *etat, bool joignable) {
  (void)ctx;
  pont_publier(lampe, etat, joignable);
}

static void sortie_signaler(void *ctx, int lampe, lampes_signal_t signal) {
  (void)ctx;
  (void)lampe;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    s_confirmes++;
  } else {
    s_abandons++;
  }
}

static void traiter(const message_t *m) {
  if (m->type == MSG_RELEVE) {
    lampes_regler_releve(&s_lampes, m->releve_ms);
    return;
  }
  lampes_ordre(&s_lampes, m->lampe, m->a_marche ? &m->marche : NULL, m->a_intensite ? &m->intensite : NULL,
               m->depuis_matter, maintenant_ms());
}

// Bluetooth Mesh inoperant (spec 7.3) : message a la console, rouge fixe au voyant.
static void diagnostiquer(uint32_t t) {
  mesh_stats_t st;
  mesh_lire_stats(&st);
  const diagnostic_ecarts_t compteurs = {st.annonces, st.nid_reconnu, st.netmic_faux, st.acces_dechiffres};
  if (!diagnostic_suivre(&s_diag, s_cles, mesh_pret(), &compteurs, t)) return;
  if (s_diag.etat == DIAG_OK) {
    printf("[mesh] de nouveau operationnel\n");
  } else {
    printf("!! Bluetooth Mesh inoperant : %s\n", diagnostic_texte(s_diag.etat));
  }
  socle_panne_mesh(s_diag.etat != DIAG_OK);
}

static void tache(void *arg) {
  (void)arg;
  uint32_t prochain_tic = maintenant_ms();
  for (;;) {
    message_t m;
    const int32_t attente = (int32_t)(prochain_tic - maintenant_ms());
    if (xQueueReceive(s_file, &m, attente > 0 ? pdMS_TO_TICKS(attente) : 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      traiter(&m);
      xSemaphoreGive(s_verrou);
      continue;  // la file d'abord : une commande Matter arrive en plusieurs ecritures
    }
    // Evenements du crochet : etats des lampes ; IV Index a sauver ; le reste,
    // imprime en ecoute detaillee.
    QueueHandle_t evenements = mesh_file_evenements();
    mesh_evenement_t ev;
    while (evenements && xQueueReceive(evenements, &ev, 0) == pdTRUE) {
      if (ev.type == MESH_EV_ETAT_LAMPE) {
        xSemaphoreTake(s_verrou, portMAX_DELAY);
        lampes_trame_recue(&s_lampes, ev.src, ev.acces + 1, maintenant_ms());
        xSemaphoreGive(s_verrou);
      }
      mesh_console_evenement(&ev, s_ecoute);
    }
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    lampes_mesh_pret(&s_lampes, mesh_pret(), maintenant_ms());
    lampes_tic(&s_lampes, maintenant_ms());
    xSemaphoreGive(s_verrou);
    diagnostiquer(maintenant_ms());
    prochain_tic = maintenant_ms() + TIC_MS;
  }
}

esp_err_t tache_lampes_demarrer(const amaran_config_t *cfg) {
  s_cles = cfg->cles_presentes;
  s_file = xQueueCreate(FILE_ORDRES, sizeof(message_t));
  s_verrou = xSemaphoreCreateMutex();
  if (!s_file || !s_verrou) return ESP_ERR_NO_MEM;
  uint16_t adresses[PONT_EMPLACEMENTS];
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) adresses[i] = cfg->lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL, NULL};
  lampes_init(&s_lampes, adresses, PONT_EMPLACEMENTS, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
  return xTaskCreate(tache, "lampes", 4096, NULL, 4, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  if (!s_file || lampe < 0 || lampe >= PONT_EMPLACEMENTS) return;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter};
  if (marche) {
    m.a_marche = true;
    m.marche = *marche;
  }
  if (intensite) {
    m.a_intensite = true;
    m.intensite = *intensite;
  }
  // File pleine : l'ordre se perd, et Maison reste sur sa valeur jusqu'au prochain changement
  // de la lampe (la relecture ne republie rien tant que la lampe ne change pas). Cela n'arrive
  // en pratique jamais : la tache CHIP produit elle-meme les ecritures, et la tache lampes
  // vide la file en continu.
  xQueueSend(s_file, &m, 0);
}

void tache_lampes_regler_releve(uint32_t releve_ms) {
  if (!s_file) return;
  const message_t m = {.type = MSG_RELEVE, .releve_ms = releve_ms};
  xQueueSend(s_file, &m, 0);
}

void tache_lampes_lire(lampes_t *copie) {
  if (!s_verrou) {
    memset(copie, 0, sizeof(*copie));
    return;
  }
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  *copie = s_lampes;
  xSemaphoreGive(s_verrou);
}

void tache_lampes_ecoute(bool oui) { s_ecoute = oui; }

uint32_t tache_lampes_confirmes(void) { return s_confirmes; }

uint32_t tache_lampes_abandons(void) { return s_abandons; }
