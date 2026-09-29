// Pont amaran : adhesion au reseau Bluetooth Mesh des lampes, emission des
// trames Telink et evenements du crochet de reception (spec 5.1 a 5.7).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#include "config_amaran.h"
#include "telink.h"

#define MESH_GROUPE_TOUS 0xC000
#define MESH_REPETITIONS_ORDRE 2
#define MESH_REPETITIONS_ETAT 1

typedef enum {
  MESH_EV_ETAT_LAMPE,  // trame 0x26 d'une de nos lampes
  MESH_EV_ACCES,       // autre message d'acces dechiffre (ecoute detaillee)
  MESH_EV_BALISE,      // balise de notre reseau (ecoute detaillee)
  MESH_EV_IV_CHANGE,   // IV Index change par la pile : a sauver
} mesh_ev_type_t;

typedef struct {
  mesh_ev_type_t type;
  int64_t quand_us;
  uint16_t src;
  uint16_t dst;
  int8_t lampe;       // index 0..AMARAN_LAMPES_MAX-1, ou -1
  uint8_t len;        // octets utiles de acces
  uint8_t acces[16];  // opcode puis charge
  uint32_t iv;        // MESH_EV_BALISE, MESH_EV_IV_CHANGE
  uint8_t flags;      // MESH_EV_BALISE
} mesh_evenement_t;

typedef struct {
  uint32_t annonces;          // messages Mesh vus sur les annonces
  uint32_t nid_reconnu;       // ... portant le NID de notre reseau
  uint32_t nid_inconnu;       // ... d'un autre reseau
  uint32_t netmic_faux;       // notre NID, mais NetMIC faux (IV Index ?)
  uint32_t acces_dechiffres;  // messages d'acces dechiffres avec l'AppKey
  uint32_t etats_lampes;      // dont trames 0x26 de nos lampes
  uint32_t balises_notres;
  uint32_t balises_autres;
  uint32_t file_pleine;       // evenements perdus
  uint32_t emis;              // messages partis (repetitions comptees une fois)
  uint32_t echecs_emission;
  int64_t derniere_balise_us;
  uint32_t derniere_balise_iv;
  uint8_t derniere_balise_flags;
  int64_t derniere_reponse_us[AMARAN_LAMPES_MAX];
} mesh_stats_t;

esp_err_t mesh_demarrer(const amaran_config_t *cfg);
bool mesh_pret(void);
// repetitions : MESH_REPETITIONS_ORDRE pour un ordre, MESH_REPETITIONS_ETAT
// pour une demande d'etat.
esp_err_t mesh_envoyer(uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions);
QueueHandle_t mesh_file_evenements(void);
void mesh_ecoute_detaillee(bool oui);
void mesh_lire_stats(mesh_stats_t *stats);
uint32_t mesh_iv_courant(void);
uint32_t mesh_sequence(void);
// plancher de sequence sauve en NVS (0 avant l'adhesion)
uint32_t mesh_plancher(void);
// Cherche l'IV Index du reseau de 0 a max (max <= 0xFFFFFF), voir crochet.h.
// Bloque la tache appelante jusqu'a la fin.
int mesh_iv_chercher(uint32_t max, uint32_t *trouve);
// Passe les exemples chiffres de la specification Mesh ; rend le nombre d'echecs.
int mesh_autotest(void);
