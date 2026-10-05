// Mode JSON du pont (docs/PROTOCOLE-JSON.md), par l'USB et par Thread : une session
// par origine (l'USB, et chaque session H1 de net_udp), la tache json qui forme et
// ecrit les lignes, l'execution des lignes (prefixe id=, reponses, ordres
// asynchrones, liste blanche a distance). Les briques pures sont dans
// components/protocole.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "diagnostic.h"
#include "lampes.h"

#ifdef __cplusplus
extern "C" {
#endif

#define JSON_PONT_CMD_MAX 127  // ligne de l'hote, prefixe id= compris (2.5)
#define JSON_PONT_IDS_MAX 4    // id en attente par lampe (evenement ordre)
#define JSON_PONT_USB 0        // origine de l'USB ; 1 et 2 : sessions distantes

// Avant le socle, la console et la tache des lampes, qui lui envoient leurs
// evenements : tire le numero de demarrage, cree les files et les taches json et
// distant. cfg reste a l'appelant (empreintes des cles, adresse, liste).
esp_err_t json_pont_demarrer(const amaran_config_t *cfg);
// Mode machine en cours par l'USB : la console lit l'USB sans echo ni invite.
bool json_pont_machine(void);
// Mode machine : lit l'USB (200 ms au plus), sans echo, et execute chaque ligne
// complete. Tache de la console seulement.
void json_pont_lire(void);
// Une ligne de la console, sans son LF, en mode texte comme en mode machine :
// prefixe id=, cadence, puis la commande et ses reponses. trop_long : la ligne
// depassait JSON_PONT_CMD_MAX octets ; rien n'est execute. Tache de la console.
void json_pont_executer(char *ligne, bool trop_long);
// La commande `json` de la console (aide, et ligne sans id).
int json_pont_commande(int argc, char **argv);

// Par Thread (net_udp) : une ligne verifiee de la session H1 `slot` (0 ou 1) de
// generation `gen` (tache udp) ; la fin d'une session (oubliee, remplacee, cle
// changee : tache udp, ou tache qui change la cle), qui remet son puits a zero et
// lui donne la generation `gen` de la suivante. net_udp annonce chaque generation
// par json_pont_distant_fin avant toute ligne : une ligne d'une autre generation
// que celle du puits, ou une fin plus ancienne que la sienne, est ignoree.
void json_pont_distant_ligne(uint8_t slot, uint32_t gen, char *ligne, size_t n);
void json_pont_distant_fin(uint8_t slot, uint32_t gen);
// La tache courante execute une commande venue de Thread : sa sortie part par
// Thread, rien de secret ne doit s'y imprimer (codes d'appairage, 10.1).
bool json_pont_tache_distante(void);

// Evenements (section 7), depuis n'importe quelle tache, sans bloquer ; ignores
// hors du mode machine.
// Fin d'un ordre de lampe : ids, les id des ordres de l'app qu'il couvre, et la
// marque de chacun (origine et generation de la session qui l'a donne, rendue
// par tache_lampes telle quelle : une session ne recoit que les siens).
void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     const uint8_t *origines, uint8_t n_ids, uint32_t ids_perdus);
void json_pont_alerte_releves(int lampe, bool manque, uint8_t pour_cent);
void json_pont_alerte_mesh(diagnostic_t etat);
typedef enum { JSON_LAMPE_ENTREE, JSON_LAMPE_MASQUEE, JSON_LAMPE_REMISE, JSON_LAMPE_ECHEC } json_lampe_t;
void json_pont_lampe(int lampe, json_lampe_t quoi, uint16_t endpoint);
// Le voyant change de motif (codes de status_led.h : patternCode).
void json_pont_led(const char *motif, const char *avant, bool test, uint32_t depuis_ms);
// Trafic Bluetooth Mesh (7.6), seulement si une session l'a demande (json trames 1).
// rx : etat recu, sinon emis ; quoi : "ordre", "demande", "etat" ; lampe -1 : le groupe ;
// marche, intensite : -1 si absents.
bool json_pont_trames_actives(void);
void json_pont_trame(bool rx, const char *quoi, int lampe, int8_t marche, int32_t intensite, uint8_t essai);
// Annonce du pont (une ligne, sans LF) : message log en mode machine avec
// `json log 1`, sinon texte. src : "lampes", "mesh", "bouton".
void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) __attribute__((format(printf, 3, 4)));

#ifdef __cplusplus
}
#endif
