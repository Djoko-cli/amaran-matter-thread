// Reglages du pont en NVS, espace "amaran" (spec 5.2 et 5.4) : cles du reseau,
// IV Index, adresse de l'ESP32, plancher de sequence, lampes.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AMARAN_LAMPES_MAX 2
#define AMARAN_NOM_MAX 32
#define AMARAN_ADRESSE_MIN 0x7F00
#define AMARAN_ADRESSE_MAX 0x7F7F

typedef struct {
  uint16_t adresse;  // adresse Mesh de la lampe ; 0 = emplacement libre
  uint8_t mac[6];
  char nom[AMARAN_NOM_MAX];
} amaran_lampe_t;

typedef struct {
  bool cles_presentes;
  uint8_t netkey[16];
  uint8_t appkey[16];
  uint8_t devkey[16];     // tiree au hasard une fois, jamais utilisee par les lampes
  uint32_t iv;            // IV Index de depart
  uint16_t adresse;       // adresse Mesh de l'ESP32
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
  uint8_t nb_lampes;
  amaran_lampe_t lampes[AMARAN_LAMPES_MAX];
} amaran_config_t;

// Lit la NVS. Tire et sauve l'adresse et la cle d'appareil si elles manquent.
esp_err_t config_charger(amaran_config_t *c);
esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]);
esp_err_t config_sauver_lampe(uint8_t index, const amaran_lampe_t *lampe);
esp_err_t config_sauver_iv(uint32_t iv);
// Nouvelle adresse source : le plancher de sequence repart de 0 si l'adresse change.
esp_err_t config_sauver_adresse(uint16_t adresse);
esp_err_t config_sauver_plancher(uint32_t plancher);
// Efface les cles et les lampes ; garde adresse, plancher et IV Index.
esp_err_t config_oublier_cles(void);
// 8 premiers chiffres hexa (majuscules) du SHA-256 de la cle, et un NUL.
void config_empreinte(const uint8_t cle[16], char sortie[9]);

#ifdef __cplusplus
}
#endif
