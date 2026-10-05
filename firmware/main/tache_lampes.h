// Tache du coeur du pont (spec 4.3) : la seule qui touche l'etat des lampes.
// Elle recoit les ordres (Matter, console) et les evenements du crochet, fait
// tourner lampes_tic() toutes les 50 ms, et fait entrer dans Maison une lampe
// jamais vue a sa premiere reponse (spec N lampes 7).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "diagnostic.h"
#include "lampes.h"
#include "liste.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t tache_lampes_demarrer(const amaran_config_t *cfg);
// Ordre pour une lampe, sans bloquer, depuis n'importe quelle tache (la tache
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Ordre de l'app (mode JSON) : son id reviendra dans l'evenement ordre qui le finira,
// avec l'octet origine tel quel. json_pont y met la session qui l'a donne : son
// origine (2 bits bas : JSON_PONT_USB, ou session distante) et 6 bits de sa
// generation, pour qu'une session qui a pris la place d'une autre ne recoive pas ses
// id. Rend false si l'ordre n'a pas pu entrer dans la file (pleine, ou lampe inconnue).
bool tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id, uint8_t origine);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
// Copie coherente de l'etat, pour la console.
void tache_lampes_lire(lampes_t *copie);
// Copie de la liste du demarrage, drapeaux a jour (vue, masquee).
void tache_lampes_lire_liste(liste_t *copie);
// Retire la lampe de Maison (afficher faux), ou l'y remet (vrai, meme jamais vue) ;
// le choix est sauve en NVS. Depuis la console (pas la tache CHIP).
esp_err_t tache_lampes_exposition(int lampe, bool afficher);
// Ecoute detaillee : imprimer aussi chaque etat recu des lampes.
void tache_lampes_ecoute(bool oui);
// Ordres confirmes et abandonnes depuis le demarrage (ne font que croitre).
uint32_t tache_lampes_confirmes(void);
uint32_t tache_lampes_abandons(void);
// Etat du diagnostic du Bluetooth Mesh (spec 7.3).
diagnostic_t tache_lampes_diagnostic(void);

#ifdef __cplusplus
}
#endif
