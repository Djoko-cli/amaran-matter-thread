// Crochet de reception (prive au composant mesh).
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "config_amaran.h"
#include "mesh_amaran.h"

esp_err_t crochet_demarrer(const amaran_config_t *cfg);
QueueHandle_t crochet_file(void);
void crochet_lire_stats(mesh_stats_t *stats);
void crochet_ecoute_detaillee(bool oui);

// Dechiffrement a cles explicites, partage avec l'autotest (tache 9).
// Reseau : en place ; *len perd le NetMIC. Rend 0 si le NetMIC est bon.
int crochet_dechiffrer_reseau(const uint8_t enc[16], const uint8_t privacy[16], uint32_t iv, uint8_t *pdu,
                              size_t *len);
// Acces (message non segmente) d'un message reseau en clair ; ad = Label UUID
// pour une adresse virtuelle, NULL sinon. Rend 0 si le TransMIC est bon.
int crochet_dechiffrer_acces(const uint8_t appkey[16], const uint8_t *clair, size_t len, uint32_t iv,
                             const uint8_t *ad, uint8_t *acces, size_t *acces_len);
