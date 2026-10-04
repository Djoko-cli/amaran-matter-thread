// Reglages du pont en NVS, espace "amaran" (spec 5.2 et 5.4) : cles du reseau,
// IV Index, adresse de l'ESP32, plancher de sequence, liste des lampes (spec N
// lampes 4).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "liste.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AMARAN_ADRESSE_MIN LISTE_RESERVEE_MIN
#define AMARAN_ADRESSE_MAX LISTE_RESERVEE_MAX

typedef struct {
  bool cles_presentes;
  uint8_t netkey[16];
  uint8_t appkey[16];
  uint8_t devkey[16];     // tiree au hasard une fois, jamais utilisee par les lampes
  uint32_t iv;            // IV Index de depart
  uint16_t adresse;       // adresse Mesh de l'ESP32
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
  uint32_t releve_ms;     // periode de relecture des lampes (pont) ; 0 = celle par defaut
  liste_t liste;          // lue au demarrage ; une liste chargee ensuite s'applique au redemarrage
} amaran_config_t;

// Lit la NVS. Tire et sauve l'adresse et la cle d'appareil si elles manquent. La
// liste de l'ancien format (deux emplacements, plan 2) est convertie une fois ; une
// ancienne liste invalide ne l'est pas (liste vide). A appeler au demarrage, avant
// toute autre fonction de ce fichier et avant les taches : elle cree le verrou.
esp_err_t config_charger(amaran_config_t *c);
esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]);
// Nouvelle liste (chargement) : fusionnee avec celle en NVS (une MAC connue garde son
// endpoint et ses drapeaux), validee, puis sauvee. Effet au redemarrage.
// ESP_ERR_INVALID_ARG si elle est invalide.
esp_err_t config_sauver_liste(const liste_t *nouvelle);
// Mise a jour d'une lampe de la liste en NVS, retrouvee par sa MAC :
// ESP_ERR_NOT_FOUND si une liste chargee depuis le demarrage ne la contient plus.
esp_err_t config_maj_endpoint(const uint8_t mac[6], uint16_t endpoint);
esp_err_t config_maj_drapeaux(const uint8_t mac[6], uint8_t drapeaux);
esp_err_t config_sauver_iv(uint32_t iv);
// Nouvelle adresse source : le plancher de sequence repart de 0 si l'adresse change.
esp_err_t config_sauver_adresse(uint16_t adresse);
esp_err_t config_sauver_plancher(uint32_t plancher);
// Periode de relecture des lampes, en ms (commande `mesh releve` du pont).
esp_err_t config_sauver_releve(uint32_t releve_ms);
// Efface les cles ; garde la liste des lampes (leurs tuiles restent dans Maison),
// l'adresse, le plancher et l'IV Index. Vider la liste : `mesh lampes 0`.
esp_err_t config_oublier_cles(void);
// 8 premiers chiffres hexa (majuscules) du SHA-256 de la cle, et un NUL.
void config_empreinte(const uint8_t cle[16], char sortie[9]);

#ifdef __cplusplus
}
#endif
