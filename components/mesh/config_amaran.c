// Reglages du pont en NVS (espace "amaran"). Les cles n'en sortent jamais : la
// console n'affiche que leur empreinte.
#include "config_amaran.h"

#include <string.h>

#include "esp_log.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

#include "texte.h"

#define ESPACE "amaran"
#define CLE_LISTE "lampes"
#define CLE_LOGICIELS "logiciels"  // versions des lampes, a part (spec fiche des lampes 3)

static const char *TAG = "config";

// Ancien format (plan 2) : deux emplacements de 40 octets.
_Static_assert(sizeof(liste_v1_t) == 40, "format du plan 2 : adresse, MAC, nom de 32 octets");
static const char *const NOMS_V1[2] = {"lampe0", "lampe1"};

// La liste se lit et s'ecrit en entier : la console (chargement, masquer, afficher),
// la tache lampes (premiere reponse) et le demarrage (numeros d'endpoint) la mettent
// a jour chacun son tour, sous ce verrou. Il est cree par config_charger, appele au
// demarrage avant toute autre fonction et avant les taches. Tampons statiques : les
// piles sont serrees.
static SemaphoreHandle_t s_verrou;
static StaticSemaphore_t s_verrou_memoire;
static liste_t s_actuelle, s_nouvelle;
static uint8_t s_tampon[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_v2_t)];
static uint8_t s_tampon_logiciels[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_logiciel_nvs_t)];

static void verrouiller(void) { xSemaphoreTake(s_verrou, portMAX_DELAY); }

static void deverrouiller(void) { xSemaphoreGive(s_verrou); }

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

// Liste en NVS (sous le verrou). ESP_ERR_NVS_NOT_FOUND : jamais ecrite. Une liste
// illisible (trop longue : un firmware de plus grande capacite) ou invalide donne une
// liste vide, et le dit au journal : la suivante l'ecrasera.
static esp_err_t lire_liste(nvs_handle_t h, liste_t *l) {
  memset(l, 0, sizeof(*l));
  size_t n = sizeof(s_tampon);
  const esp_err_t err = nvs_get_blob(h, CLE_LISTE, s_tampon, &n);
  if (err == ESP_ERR_NVS_INVALID_LENGTH) {
    ESP_LOGE(TAG, "liste des lampes illisible (trop longue) : liste vide");
    return ESP_OK;
  }
  if (err != ESP_OK) return err;
  int fautive = -1;
  if (!liste_depuis_nvs(l, s_tampon, (uint32_t)n)) {
    ESP_LOGE(TAG, "liste des lampes illisible (format) : liste vide");
  } else if (liste_valider(l, &fautive) != LISTE_OK) {
    ESP_LOGE(TAG, "liste des lampes invalide (lampe %d) : liste vide", fautive + 1);
    memset(l, 0, sizeof(*l));
  } else {
    // Les versions, par MAC : absentes (liste chargee avant le plan 3b-3, ou par un
    // firmware plus ancien) ou illisibles, elles restent inconnues.
    size_t m = sizeof(s_tampon_logiciels);
    const esp_err_t e = nvs_get_blob(h, CLE_LOGICIELS, s_tampon_logiciels, &m);
    if (e == ESP_OK) {
      if (!liste_logiciels_depuis_nvs(l, s_tampon_logiciels, (uint32_t)m)) {
        ESP_LOGE(TAG, "versions des lampes illisibles (format) : inconnues");
      }
    } else if (e != ESP_ERR_NVS_NOT_FOUND) {
      ESP_LOGE(TAG, "versions des lampes illisibles (%s) : inconnues", esp_err_to_name(e));
    }
  }
  return ESP_OK;
}

// La liste, puis ses versions : un firmware d'avant le plan 3b-3 relit la premiere
// et ignore la seconde.
static esp_err_t ecrire_liste(nvs_handle_t h, const liste_t *l) {
  liste_vers_nvs(l, s_tampon);
  esp_err_t err = nvs_set_blob(h, CLE_LISTE, s_tampon, liste_taille_nvs(l));
  if (err != ESP_OK) return err;
  liste_logiciels_vers_nvs(l, s_tampon_logiciels);
  return nvs_set_blob(h, CLE_LOGICIELS, s_tampon_logiciels, liste_logiciels_taille_nvs(l));
}

// Ancien format, converti une fois : l'emplacement i gardait l'endpoint 2 + i.
// L'ancien n'est efface qu'une fois le nouveau ecrit (coupure : on recommence).
// Le plan 2 acceptait ce que la liste refuse (adresse reservee, MAC nulle, doublon) :
// une ancienne liste invalide donne une liste vide, a chaque demarrage, et reste.
static esp_err_t migrer_v1(nvs_handle_t h, liste_t *l) {
  liste_v1_t v1[2];
  bool lu[2];
  for (int i = 0; i < 2; i++) lu[i] = lire_blob(h, NOMS_V1[i], &v1[i], sizeof(v1[i]));
  liste_migrer_v1(l, v1, lu);
  if (!lu[0] && !lu[1]) return ESP_OK;
  int fautive = -1;
  if (liste_valider(l, &fautive) != LISTE_OK) {
    ESP_LOGE(TAG, "ancienne liste des lampes invalide (lampe %d) : liste vide, recharger les cles", fautive + 1);
    memset(l, 0, sizeof(*l));
    return ESP_OK;
  }
  esp_err_t err = ecrire_liste(h, l);
  if (err == ESP_OK) err = nvs_commit(h);
  for (int i = 0; i < 2 && err == ESP_OK; i++) err = effacer(h, NOMS_V1[i]);
  if (err == ESP_OK) ESP_LOGI(TAG, "liste des lampes convertie : %u lampe(s), EP2 et EP3 gardes", l->n);
  return err;
}

esp_err_t config_charger(amaran_config_t *c) {
  if (!s_verrou) s_verrou = xSemaphoreCreateMutexStatic(&s_verrou_memoire);
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
  if (nvs_get_u32(h, "releve", &c->releve_ms) != ESP_OK) c->releve_ms = 0;
  verrouiller();
  const esp_err_t lu = lire_liste(h, &c->liste);
  if (lu == ESP_ERR_NVS_NOT_FOUND) {
    const esp_err_t m = migrer_v1(h, &c->liste);
    if (m != ESP_OK) ESP_LOGE(TAG, "conversion de la liste des lampes : %s", esp_err_to_name(m));
  } else if (lu != ESP_OK) {
    ESP_LOGE(TAG, "liste des lampes illisible (%s) : liste vide", esp_err_to_name(lu));
  }
  deverrouiller();
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

esp_err_t config_sauver_liste(const liste_t *nouvelle) {
  int fautive = -1;
  if (liste_valider(nouvelle, &fautive) != LISTE_OK) return ESP_ERR_INVALID_ARG;
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  verrouiller();
  const esp_err_t lu = lire_liste(h, &s_actuelle);
  if (lu == ESP_OK || lu == ESP_ERR_NVS_NOT_FOUND) {
    s_nouvelle = *nouvelle;
    liste_fusionner(&s_nouvelle, &s_actuelle);
    err = ecrire_liste(h, &s_nouvelle);
  } else {
    err = lu;
  }
  deverrouiller();
  return fermer(h, err);
}

// Lit la liste, change une lampe retrouvee par sa MAC, ecrit la liste.
static esp_err_t maj_lampe(const uint8_t mac[6], bool endpoint, uint16_t valeur) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  verrouiller();
  err = lire_liste(h, &s_actuelle);
  if (err == ESP_ERR_NVS_NOT_FOUND) err = ESP_ERR_NOT_FOUND;  // aucune liste en NVS : la lampe n'y est pas
  const int i = err == ESP_OK ? liste_chercher_mac(&s_actuelle, mac) : -1;
  if (err == ESP_OK && i < 0) err = ESP_ERR_NOT_FOUND;
  if (err == ESP_OK) {
    if (endpoint) {
      s_actuelle.lampes[i].endpoint = valeur;
    } else {
      s_actuelle.lampes[i].drapeaux = (uint8_t)valeur;
    }
    err = ecrire_liste(h, &s_actuelle);
  }
  deverrouiller();
  return fermer(h, err);
}

esp_err_t config_maj_endpoint(const uint8_t mac[6], uint16_t endpoint) { return maj_lampe(mac, true, endpoint); }

esp_err_t config_maj_drapeaux(const uint8_t mac[6], uint8_t drapeaux) { return maj_lampe(mac, false, drapeaux); }

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
  uint16_t ancienne_adresse;
  const bool adresse_change = nvs_get_u16(h, "adresse", &ancienne_adresse) != ESP_OK || ancienne_adresse != adresse;
  err = nvs_set_u16(h, "adresse", adresse);
  // Nouvelle adresse source : les lampes n'en connaissent aucun compteur.
  if (err == ESP_OK && adresse_change) err = nvs_set_u32(h, "plancher", 0);
  return fermer(h, err);
}

esp_err_t config_sauver_plancher(uint32_t plancher) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "plancher", plancher));
}

esp_err_t config_sauver_releve(uint32_t releve_ms) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "releve", releve_ms));
}

esp_err_t config_oublier_cles(void) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = effacer(h, "netkey");
  if (err == ESP_OK) err = effacer(h, "appkey");
  return fermer(h, err);
}

void config_empreinte(const uint8_t cle[16], char sortie[9]) {
  uint8_t condensat[32];
  mbedtls_sha256(cle, 16, condensat, 0);
  texte_octets_vers_hex(condensat, 4, sortie);
}
