// Reglages du pont en NVS (espace "amaran"). Les cles n'en sortent jamais : la
// console n'affiche que leur empreinte.
#include "config_amaran.h"

#include <string.h>

#include "esp_random.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

#include "texte.h"

#define ESPACE "amaran"

_Static_assert(AMARAN_LAMPES_MAX == 2, "NOMS_LAMPES a completer");
static const char *const NOMS_LAMPES[AMARAN_LAMPES_MAX] = {"lampe0", "lampe1"};

static bool lire_blob(nvs_handle_t h, const char *cle, void *dst, size_t taille) {
  size_t n = taille;
  return nvs_get_blob(h, cle, dst, &n) == ESP_OK && n == taille;
}

static esp_err_t ouvrir(nvs_handle_t *h) { return nvs_open(ESPACE, NVS_READWRITE, h); }

static esp_err_t fermer(nvs_handle_t h, esp_err_t err) {
  if (err == ESP_OK) err = nvs_commit(h);
  nvs_close(h);
  return err;
}

static esp_err_t effacer(nvs_handle_t h, const char *cle) {
  const esp_err_t e = nvs_erase_key(h, cle);
  return e == ESP_ERR_NVS_NOT_FOUND ? ESP_OK : e;
}

esp_err_t config_charger(amaran_config_t *c) {
  memset(c, 0, sizeof(*c));
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  c->cles_presentes = lire_blob(h, "netkey", c->netkey, 16) && lire_blob(h, "appkey", c->appkey, 16);
  if (!c->cles_presentes) {
    memset(c->netkey, 0, sizeof(c->netkey));
    memset(c->appkey, 0, sizeof(c->appkey));
  }
  if (!lire_blob(h, "devkey", c->devkey, 16)) {
    esp_fill_random(c->devkey, sizeof(c->devkey));
    err = nvs_set_blob(h, "devkey", c->devkey, sizeof(c->devkey));
  }
  if (nvs_get_u32(h, "iv", &c->iv) != ESP_OK) c->iv = 0;
  if (nvs_get_u16(h, "adresse", &c->adresse) != ESP_OK || c->adresse < AMARAN_ADRESSE_MIN ||
      c->adresse > AMARAN_ADRESSE_MAX) {
    // Tiree au hasard dans la plage reservee : apres un effacement de la
    // flash, peu de chances de retomber sur une adresse dont les lampes
    // gardent un compteur plus haut que le notre (elles nous ignoreraient).
    c->adresse = (uint16_t)(AMARAN_ADRESSE_MIN + esp_random() % (AMARAN_ADRESSE_MAX - AMARAN_ADRESSE_MIN + 1));
    if (err == ESP_OK) err = nvs_set_u16(h, "adresse", c->adresse);
  }
  if (nvs_get_u32(h, "plancher", &c->plancher_seq) != ESP_OK) c->plancher_seq = 0;
  for (uint8_t i = 0; i < AMARAN_LAMPES_MAX; i++) {
    if (!lire_blob(h, NOMS_LAMPES[i], &c->lampes[i], sizeof(amaran_lampe_t))) {
      memset(&c->lampes[i], 0, sizeof(amaran_lampe_t));
    }
    c->lampes[i].nom[AMARAN_NOM_MAX - 1] = '\0';
    if (c->lampes[i].adresse != 0) c->nb_lampes++;
  }
  return fermer(h, err);
}

esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = nvs_set_blob(h, "netkey", netkey, 16);
  if (err == ESP_OK) err = nvs_set_blob(h, "appkey", appkey, 16);
  return fermer(h, err);
}

esp_err_t config_sauver_lampe(uint8_t index, const amaran_lampe_t *lampe) {
  if (index >= AMARAN_LAMPES_MAX) return ESP_ERR_INVALID_ARG;
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_blob(h, NOMS_LAMPES[index], lampe, sizeof(*lampe)));
}

esp_err_t config_sauver_iv(uint32_t iv) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "iv", iv));
}

esp_err_t config_sauver_adresse(uint16_t adresse) {
  if (adresse < AMARAN_ADRESSE_MIN || adresse > AMARAN_ADRESSE_MAX) return ESP_ERR_INVALID_ARG;
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = nvs_set_u16(h, "adresse", adresse);
  // Nouvelle adresse source : les lampes n'en connaissent aucun compteur.
  if (err == ESP_OK) err = nvs_set_u32(h, "plancher", 0);
  return fermer(h, err);
}

esp_err_t config_sauver_plancher(uint32_t plancher) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "plancher", plancher));
}

esp_err_t config_oublier_cles(void) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = effacer(h, "netkey");
  if (err == ESP_OK) err = effacer(h, "appkey");
  for (uint8_t i = 0; i < AMARAN_LAMPES_MAX && err == ESP_OK; i++) err = effacer(h, NOMS_LAMPES[i]);
  return fermer(h, err);
}

void config_empreinte(const uint8_t cle[16], char sortie[9]) {
  uint8_t condensat[32];
  mbedtls_sha256(cle, 16, condensat, 0);
  texte_octets_vers_hex(condensat, 4, sortie);
}
