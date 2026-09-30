// Tache du coeur du pont (spec 4.3) : la seule qui touche l'etat des lampes.
// Elle recoit les ordres (Matter, console) et les evenements du crochet, et fait
// tourner lampes_tic() toutes les 50 ms.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t tache_lampes_demarrer(const amaran_config_t *cfg);
// Ordre pour une lampe, sans bloquer, depuis n'importe quelle tache (la tache
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
// Copie coherente de l'etat, pour la console.
void tache_lampes_lire(lampes_t *copie);
// Ecoute detaillee : imprimer aussi chaque etat recu des lampes.
void tache_lampes_ecoute(bool oui);
// Ordres confirmes et abandonnes depuis le demarrage (ne font que croitre).
uint32_t tache_lampes_confirmes(void);
uint32_t tache_lampes_abandons(void);

#ifdef __cplusplus
}
#endif
