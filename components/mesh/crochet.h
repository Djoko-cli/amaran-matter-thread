// Crochet de reception (prive au composant mesh).
#pragma once

#include <stdbool.h>

#include "config_amaran.h"
#include "mesh_amaran.h"

esp_err_t crochet_demarrer(const amaran_config_t *cfg);
QueueHandle_t crochet_file(void);
void crochet_lire_stats(mesh_stats_t *stats);
void crochet_ecoute_detaillee(bool oui);
