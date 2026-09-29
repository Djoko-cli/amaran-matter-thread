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
// Reseau : en place ; *len perd le NetMIC. Rend 0 si le NetMIC est bon, -1 si
// *len n'est pas entre 18 et 32 (18 = le plus court message reseau que la pile
// accepte, net.c) ou si le retrait de l'obfuscation echoue, -2 si le NetMIC est
// faux. Apres -2 le tampon est en partie desobfusque et dechiffre : ne jamais le
// reutiliser, travailler sur une copie. Sur un NetMIC faux elle ne journalise
// jamais : la tache Bluetooth l'appelle a chaque message, et la recherche de
// l'IV Index, une fois par candidat.
int crochet_dechiffrer_reseau(const uint8_t enc[16], const uint8_t privacy[16], uint32_t iv, uint8_t *pdu,
                              size_t *len);
// Acces (message non segmente) d'un message reseau en clair ; ad = Label UUID
// pour une adresse virtuelle, NULL sinon. Rend 0 si le TransMIC est bon.
int crochet_dechiffrer_acces(const uint8_t appkey[16], const uint8_t *clair, size_t len, uint32_t iv,
                             const uint8_t *ad, uint8_t *acces, size_t *acces_len);

// Cherche l'IV Index de 0 a max (max <= 0xFFFFFF) sur les messages au NetMIC
// faux gardes par le crochet. 0 : trouve ; 1 : hors de la plage ; 2 : aucun
// message garde ; -1 : pas de cle reseau.
int crochet_chercher_iv(uint32_t max, uint32_t *trouve);
