// Canal du pont par Thread (spec 3b, section 7 ; docs/PROTOCOLE-JSON.md, section 10) :
// socket UDP 5480 sur OpenThread, enveloppe H1 (components/h1), cle UDP en NVS.
//
// Chaque emplacement de session (0 ou 1) a une generation, qui change a chaque session
// neuve, oubli ou cle changee ; json_pont l'apprend par json_pont_distant_fin avant toute
// ligne de la session, et la rend a chaque appel ci-dessous : un appel d'une generation
// perimee (une autre session a pris la place) ne touche a rien.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NET_UDP_PORT 5480
#define NET_UDP_SESSIONS 2  // h1::kSlots
#define NET_UDP_ADRESSES 4
#define NET_UDP_PLACES_LIGNE 2  // places libres qu'une ligne demande : la derniere reste au DEFI

typedef enum { NET_UDP_OMR, NET_UDP_ML_EID, NET_UDP_AUTRE } net_udp_type_t;

typedef struct {
  bool cle;
  char empreinte[9];  // 8 hexa ; vide sans cle
  bool ouvert;        // port 5480 ouvert
  uint8_t sessions;   // sessions H1 etablies
  uint32_t recus, emis, rejets, perdus;
  char srp[64];       // nom SRP (sans .local) ; vide : inconnu
  uint8_t n;
  struct {
    uint8_t a[16];
    net_udp_type_t type;
  } adresses[NET_UDP_ADRESSES];
} net_udp_etat_t;

// Apres pont_demarrer (la file de taches d'OpenThread existe) : lit la cle en NVS,
// ouvre le port si elle existe, lance la tache udp.
esp_err_t net_udp_demarrer(void);

// Une ligne machine (JSON, sans RS ni LF) vers la session `slot` de generation `gen`,
// scellee et mise en file, sans attendre : la tache udp la remet a OpenThread. Une
// place de la file reste toujours pour un DEFI : la ligne n'entre que s'il en reste
// au moins NET_UDP_PLACES_LIGNE. false : session partie (generation perimee), ou file
// pleine (ligne perdue, a compter).
bool net_udp_envoyer(uint8_t slot, uint32_t gen, const uint8_t *ligne, size_t n);

// Places libres de la file d'emission (6, partagees par les sessions et les DEFI) ;
// 0 si net_udp n'est pas demarre ou si le port est ferme.
uint8_t net_udp_libres(void);

// Fin de la session machine (json 0, bail echu) : l'emplacement peut resservir.
void net_udp_finir(uint8_t slot, uint32_t gen);
// Nouvelle commande admise de la session (jamais un renvoi servi par le cache) : elle
// sert de nouveau, meme apres json 0 (h1::Table::resume).
void net_udp_reprendre(uint8_t slot, uint32_t gen);

// json cle nouvelle (10.2) : cle = HMAC-SHA256(alea de l'app, alea du pont), gardee
// en NVS ; rend la cle (64 hexa) une seule fois, et son empreinte (8 hexa).
// ESP_ERR_INVALID_STATE : net_udp n'est pas demarre (Matter non demarre), rien ne
// change, NVS comprise ; une erreur de la NVS : rien ne change.
esp_err_t net_udp_cle_nouvelle(const uint8_t alea_app[32], char cle_hex[65], char empreinte[9]);
// json cle efface, decommission, BOOT 8 s : cle effacee, sessions tombees, port ferme.
// ESP_ERR_INVALID_STATE : net_udp n'est pas demarre, rien ne change. Une erreur de la
// NVS est rendue : la cle a quitte la memoire, mais elle reviendra au redemarrage.
esp_err_t net_udp_cle_effacer(void);

// Releve pour le bloc reseau ip (adresses et nom SRP relus toutes les 5 s).
void net_udp_lire(net_udp_etat_t *e);

#ifdef __cplusplus
}
#endif
