// Commandes de console communes aux deux firmwares : `mesh` et `taches`, et
// impression des evenements du crochet (spec 7.5).
#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "config_amaran.h"
#include "mesh_amaran.h"

#ifdef __cplusplus
extern "C" {
#endif

// A appeler avant toute autre fonction de ce module (mesh_console_evenement
// compris). cfg reste la propriete de l'appelant (la console le lit ; l'IV y est mis a
// jour). taches : les noms de taches que `taches` examine.
void mesh_console_init(amaran_config_t *cfg, const char *const *taches, size_t nb_taches);
// La commande `mesh` : etat sans argument ; cles, lampes, lampe, iv, adresse,
// oublie, ecoute, balayage, autotest.
int mesh_console_commande(int argc, char **argv);
// La commande `taches` : pile libre au plus bas de chaque tache, et le tas.
int mesh_console_taches(int argc, char **argv);
// Message, vidage de la sortie, puis esp_restart().
void mesh_console_redemarrer(void);
// Imprime un evenement du crochet ; un changement d'IV Index est aussi sauve en
// NVS. etats : imprimer aussi les etats des lampes (sinon, seulement le reste).
void mesh_console_evenement(const mesh_evenement_t *ev, bool etats);

#ifdef __cplusplus
}
#endif
