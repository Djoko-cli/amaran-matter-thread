// Cote Matter du pont (spec 6 ; spec N lampes 5 et 7) : noeud (EP0), agregateur
// (EP1) et un endpoint ponte par lampe exposee, avec son numero ; ordres des
// controleurs, etat des lampes publie sans echo, abonnements plafonnes, identite.
// Ecrit en C++ (esp-matter), appele depuis le C.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"
#include "liste.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond
#define PONT_NOM "Pont amaran"        // NodeLabel

// Releve du cote Matter pour le protocole JSON : rien n'y prend un verrou.
typedef struct {
  bool demarre;
  uint8_t fabriques;
  bool ble_annonce, identifie, thread_attache;
  const char *role;  // role Thread du dernier evenement : disabled, detached, child, router, leader
  uint32_t abo_demandes, abo_plafonnes, abo_etablis, abo_termines;
  // Lus une fois, juste apres le demarrage de Matter ; NULL avant, ou en cas d'echec.
  const char *code_manuel, *qr, *fabricant, *produit, *serie;
} pont_infos_t;

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
// marche et/ou intensite 0..1000 (NULL : inchange).
typedef void (*pont_ordre_cb_t)(int lampe, const bool *marche, const uint16_t *intensite);

// Cree le noeud et l'agregateur, ecrit l'identite, demarre Matter, puis cree
// l'endpoint de chaque lampe exposee de cfg (pont_exposer). Les ordres arrivent par
// ordre().
esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre);
// Fait entrer la lampe dans Maison : son endpoint, avec son numero s'il en a un (le
// suivant du compteur d'esp-matter sinon, sauve en NVS), et le type d'appareil que
// donne le catalogue ; masquee depuis le demarrage, son endpoint est reactive. Sans
// effet si elle y est deja. Une fois pont_demarrer fini (sinon ESP_ERR_INVALID_STATE),
// hors de la tache CHIP : prend le verrou de la pile.
esp_err_t pont_exposer(int lampe, const liste_lampe_t *l);
// Desactive l'endpoint de la lampe, sans le detruire : Maison retire sa tuile, et la
// lampe garde son numero. Memes conditions que pont_exposer.
esp_err_t pont_masquer(int lampe);
// Numero d'endpoint de la lampe ; 0 si elle n'est pas exposee.
uint16_t pont_endpoint(int lampe);
// Etat d'une lampe dans Matter (attribute::report : aucun rappel, donc aucun
// echo). etat NULL : jamais lu, seule la joignabilite change. Intensite 0 (lampe
// noire jamais vue allumee) : OnOff est publie, CurrentLevel reste ce qu'il est.
// Sans effet tant que Matter n'est pas demarre, ou pour une lampe non exposee.
void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable);
// Au moins une fabrique (Maison ou un autre controleur).
bool pont_appaire(void);
// CHIPoBLE annonce (mise en service) : le Mesh ne doit pas emettre.
bool pont_ble_annonce(void);
// Thread attache (enfant, routeur ou chef), d'apres le dernier evenement de role.
bool pont_thread_attache(void);
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
void pont_afficher(void);
// Releve pour le protocole JSON, depuis n'importe quelle tache, sans verrou.
void pont_lire(pont_infos_t *infos);
// Retire toutes les fabriques Matter, puis la pile redemarre la carte. Les
// reglages "amaran" (cles, lampes) restent (spec 7.7).
void pont_desappairer(void);
// Un controleur demande l'identification (IdentifyTime ou un effet en cours).
bool pont_identifie(void);

#ifdef __cplusplus
}
#endif
