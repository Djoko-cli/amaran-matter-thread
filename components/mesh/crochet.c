// Crochet de reception : file d'evenements et compteurs. Le dechiffrement et
// l'interception arrivent a la tache 8.
#include "crochet.h"

#include <string.h>

#define FILE_EVENEMENTS 32

static QueueHandle_t s_file;
static mesh_stats_t s_st;
static volatile bool s_detail;

esp_err_t crochet_demarrer(const amaran_config_t *cfg) {
  (void)cfg;
  s_file = xQueueCreate(FILE_EVENEMENTS, sizeof(mesh_evenement_t));
  return s_file ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t crochet_file(void) { return s_file; }

void crochet_lire_stats(mesh_stats_t *stats) { memcpy(stats, &s_st, sizeof(*stats)); }

void crochet_ecoute_detaillee(bool oui) { s_detail = oui; }
