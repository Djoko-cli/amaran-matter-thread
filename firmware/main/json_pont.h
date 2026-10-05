// Mode JSON du pont sur l'USB (docs/PROTOCOLE-JSON.md) : la session (mode
// machine, bail, periodes), la tache json qui forme et ecrit les lignes, et
// l'execution des lignes de la console (prefixe id=, reponses, ordres
// asynchrones). Les briques pures sont dans components/protocole.
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

// Avant le socle, la console et la tache des lampes, qui lui envoient leurs
// evenements : tire le numero de demarrage, cree les files et la tache json.
// cfg reste a l'appelant (empreintes des cles, adresse, liste).
esp_err_t json_pont_demarrer(const amaran_config_t *cfg);
// Mode machine en cours : la console lit l'USB sans echo ni invite.
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

// Evenements (section 7), depuis n'importe quelle tache, sans bloquer ; ignores
// hors du mode machine.
// Fin d'un ordre de lampe : ids, les id des ordres de l'app qu'il couvre.
void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     uint8_t n_ids, uint32_t ids_perdus);
void json_pont_alerte_releves(int lampe, bool manque, uint8_t pour_cent);
void json_pont_alerte_mesh(diagnostic_t etat);
typedef enum { JSON_LAMPE_ENTREE, JSON_LAMPE_MASQUEE, JSON_LAMPE_REMISE, JSON_LAMPE_ECHEC } json_lampe_t;
void json_pont_lampe(int lampe, json_lampe_t quoi, uint16_t endpoint);
// Le voyant change de motif (codes de status_led.h : patternCode).
void json_pont_led(const char *motif, const char *avant, bool test, uint32_t depuis_ms);
// Annonce du pont (une ligne, sans LF) : message log en mode machine avec
// `json log 1`, sinon texte. src : "lampes", "mesh", "bouton".
void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) __attribute__((format(printf, 3, 4)));

#ifdef __cplusplus
}
#endif
