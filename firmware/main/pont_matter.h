// Cote Matter du pont (spec 6) : noeud (EP0), agregateur (EP1) et une lampe
// pontee par emplacement (EP2, EP3), ordres des controleurs, etat des lampes
// publie sans echo, abonnements plafonnes, identite. Ecrit en C++ (esp-matter),
// appele depuis le C.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
// marche et/ou intensite 0..1000 (NULL : inchange).
typedef void (*pont_ordre_cb_t)(int lampe, const bool *marche, const uint16_t *intensite);

// Cree les endpoints (noms et adresses : cfg), ecrit l'identite, puis demarre
// Matter. Les ordres arrivent par ordre().
esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre);
// Etat d'une lampe dans Matter (attribute::report : aucun rappel, donc aucun
// echo). etat NULL : jamais lu, seule la joignabilite change. Intensite 0 (lampe
// noire jamais vue allumee) : OnOff est publie, CurrentLevel reste ce qu'il est.
void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable);
// Au moins une fabrique (Maison ou un autre controleur).
bool pont_appaire(void);
// CHIPoBLE annonce (mise en service) : le Mesh ne doit pas emettre.
bool pont_ble_annonce(void);
// Thread attache (enfant, routeur ou chef), d'apres le dernier evenement de role.
bool pont_thread_attache(void);
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
void pont_afficher(void);
// Retire toutes les fabriques Matter, puis la pile redemarre la carte. Les
// reglages "amaran" (cles, lampes) restent (spec 7.7).
void pont_desappairer(void);
// Un controleur demande l'identification (IdentifyTime ou un effet en cours).
bool pont_identifie(void);

#ifdef __cplusplus
}
#endif
