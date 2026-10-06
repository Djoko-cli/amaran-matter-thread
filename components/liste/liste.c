// Liste des lampes du pont (voir liste.h).
#include "liste.h"

#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "catalogue.h"

// Le format en NVS est l'image de ces structures : leur disposition ne change pas
// sans changer LISTE_VERSION (la meme sur l'ESP32-C6 et sur le Mac des tests).
_Static_assert(sizeof(liste_entete_t) == 4, "en-tete NVS : 4 octets");
_Static_assert(sizeof(liste_lampe_v2_t) == 48 && offsetof(liste_lampe_v2_t, mac) == 2 &&
                   offsetof(liste_lampe_v2_t, nom) == 8 && offsetof(liste_lampe_v2_t, code) == 40 &&
                   offsetof(liste_lampe_v2_t, endpoint) == 44 && offsetof(liste_lampe_v2_t, drapeaux) == 46,
               "lampe en NVS : 48 octets, disposition fixe");
_Static_assert(sizeof(liste_logiciel_nvs_t) == 22, "versions d'une lampe en NVS : 22 octets");
_Static_assert(sizeof(liste_v1_t) == 40, "emplacement du plan 2 : 40 octets");

static const uint8_t MAC_NULLE[6] = {0};

static bool adresse_valide(uint16_t a) {
  return a >= 0x0001 && a <= 0x7FFF && (a < LISTE_RESERVEE_MIN || a > LISTE_RESERVEE_MAX);
}

static bool nom_valide(const char nom[LISTE_NOM_MAX]) {
  if (nom[0] == '\0') return false;
  for (int i = 0; i < LISTE_NOM_MAX; i++) {
    if (nom[i] == '\0') return true;
    if ((unsigned char)nom[i] < 0x20 || nom[i] == 0x7F) return false;  // caractere de controle
  }
  return false;  // pas de NUL : nom trop long
}

bool liste_logiciel_valide(const char *v) {
  if (v[0] == '\0') return true;
  int avant = 0, apres = 0, point = 0;
  for (const char *c = v; *c; c++) {
    if (*c == '.') {
      if (point++) return false;
    } else if (*c >= '0' && *c <= '9') {
      if (point) {
        apres++;
      } else {
        avant++;
      }
    } else {
      return false;
    }
  }
  return point == 1 && avant >= 1 && avant <= 3 && apres >= 1 && apres <= 3;
}

int liste_lire_jeton_logiciel(const char *mot, char logiciel[LISTE_LOGICIEL_MAX], char ble[LISTE_LOGICIEL_MAX]) {
  if (mot[0] != 'v' || mot[1] < '0' || mot[1] > '9') return 0;
  const char *barre = strchr(mot + 1, '/');
  const size_t n1 = barre ? (size_t)(barre - (mot + 1)) : strlen(mot + 1);
  const size_t n2 = barre ? strlen(barre + 1) : 0;
  if (n1 >= LISTE_LOGICIEL_MAX || n2 >= LISTE_LOGICIEL_MAX || (barre && n2 == 0)) return -1;
  char a[LISTE_LOGICIEL_MAX] = "", b[LISTE_LOGICIEL_MAX] = "";
  memcpy(a, mot + 1, n1);
  if (barre) memcpy(b, barre + 1, n2);
  if (!liste_logiciel_valide(a) || !liste_logiciel_valide(b)) return -1;
  memcpy(logiciel, a, LISTE_LOGICIEL_MAX);
  memcpy(ble, b, LISTE_LOGICIEL_MAX);
  return 1;
}

int liste_lire_logiciel_argv(int argc, char *const argv[], int i, char logiciel[LISTE_LOGICIEL_MAX],
                             char ble[LISTE_LOGICIEL_MAX]) {
  if (i + 1 >= argc || strchr(argv[i], ' ')) return i;
  return liste_lire_jeton_logiciel(argv[i], logiciel, ble) == 1 ? i + 1 : i;
}

void liste_texte_logiciel(const liste_lampe_t *l, char *texte, unsigned taille) {
  if (!taille) return;
  if (!l->logiciel[0]) {
    texte[0] = '\0';
  } else if (l->ble[0]) {
    snprintf(texte, taille, "%s (BLE %s)", l->logiciel, l->ble);
  } else {
    snprintf(texte, taille, "%s", l->logiciel);
  }
}

void liste_fiche(const liste_lampe_t *l, liste_fiche_t *f) {
  memset(f, 0, sizeof(*f));
  if (catalogue_connu(l->code)) {
    snprintf(f->produit, sizeof(f->produit), "%s", catalogue_trouver(l->code)->nom);
  } else {
    snprintf(f->produit, sizeof(f->produit), "amaran %" PRIu32, l->code);
  }
  snprintf(f->serie, sizeof(f->serie), "AMARAN-%02X%02X%02X%02X%02X%02X", l->mac[0], l->mac[1], l->mac[2], l->mac[3],
           l->mac[4], l->mac[5]);
  liste_texte_logiciel(l, f->logiciel, sizeof(f->logiciel));
  if (l->logiciel[0] && liste_logiciel_valide(l->logiciel)) {
    const char *point = strchr(l->logiciel, '.');
    uint32_t x = 0, y = 0;
    for (const char *c = l->logiciel; c < point; c++) x = x * 10 + (uint32_t)(*c - '0');
    for (const char *c = point + 1; *c; c++) y = y * 10 + (uint32_t)(*c - '0');
    f->logiciel_nombre = x * 1000 + y;
  }
}

static uint32_t fnv(uint32_t h, const void *d, size_t n) {
  const uint8_t *o = (const uint8_t *)d;
  for (size_t i = 0; i < n; i++) h = (h ^ o[i]) * 16777619u;
  return h;
}

static uint32_t fnv_texte(uint32_t h, const char *t) { return fnv(h, t, strlen(t) + 1); }

uint32_t liste_empreinte_fiches(const liste_lampe_t *const lampes[], const uint16_t eps[], int n) {
  // "fiche3" : a changer si ce que couvre l'empreinte change (2 : SoftwareVersion ; 3 :
  // ConfigurationVersion de chaque lampe).
  uint32_t h = fnv_texte(fnv_texte(2166136261u, "fiche3"), LISTE_FABRICANT);
  uint32_t dernier = 0;
  for (;;) {
    int suivante = -1;
    for (int i = 0; i < n; i++) {
      if (eps[i] > dernier && (suivante < 0 || eps[i] < eps[suivante])) suivante = i;
    }
    if (suivante < 0) return h;
    dernier = eps[suivante];
    const liste_lampe_t *l = lampes[suivante];
    liste_fiche_t f;
    liste_fiche(l, &f);
    const uint16_t ep = eps[suivante];
    const uint8_t type = (uint8_t)catalogue_trouver(l->code)->type;
    h = fnv(h, &ep, sizeof(ep));
    h = fnv(h, &type, sizeof(type));
    h = fnv_texte(h, l->nom);
    h = fnv_texte(h, f.produit);
    h = fnv_texte(h, f.serie);
    h = fnv_texte(h, f.logiciel);
  }
}

liste_erreur_t liste_valider(const liste_t *l, int *fautive) {
  *fautive = -1;
  if (l->n > LISTE_CAPACITE) return LISTE_TROP_LONGUE;
  for (int i = 0; i < l->n; i++) {
    const liste_lampe_t *a = &l->lampes[i];
    *fautive = i;
    if (!adresse_valide(a->adresse)) return LISTE_ADRESSE_INVALIDE;
    if (!memcmp(a->mac, MAC_NULLE, 6)) return LISTE_MAC_NULLE;
    if (!nom_valide(a->nom)) return LISTE_NOM_INVALIDE;
    if (memchr(a->logiciel, '\0', LISTE_LOGICIEL_MAX) == NULL || memchr(a->ble, '\0', LISTE_LOGICIEL_MAX) == NULL ||
        !liste_logiciel_valide(a->logiciel) || !liste_logiciel_valide(a->ble) || (!a->logiciel[0] && a->ble[0])) {
      return LISTE_LOGICIEL_INVALIDE;
    }
    for (int j = 0; j < i; j++) {
      if (l->lampes[j].adresse == a->adresse) return LISTE_ADRESSE_EN_DOUBLE;
      if (!memcmp(l->lampes[j].mac, a->mac, 6)) return LISTE_MAC_EN_DOUBLE;
    }
  }
  *fautive = -1;
  return LISTE_OK;
}

const char *liste_erreur_texte(liste_erreur_t e) {
  switch (e) {
    case LISTE_OK:
      return "ok";
    case LISTE_TROP_LONGUE:
      return "trop de lampes";
    case LISTE_ADRESSE_INVALIDE:
      return "adresse hors de l'unicast, ou dans nos adresses (0x7F00-0x7F7F)";
    case LISTE_ADRESSE_EN_DOUBLE:
      return "adresse deja prise par une autre lampe";
    case LISTE_MAC_NULLE:
      return "MAC nulle";
    case LISTE_MAC_EN_DOUBLE:
      return "MAC deja prise par une autre lampe";
    case LISTE_NOM_INVALIDE:
      return "nom vide, trop long, ou avec un caractere de controle";
    case LISTE_LOGICIEL_INVALIDE:
      return "version du logiciel mal formee (attendu x.y)";
  }
  return "?";
}

int liste_chercher_mac(const liste_t *l, const uint8_t mac[6]) {
  for (int i = 0; i < l->n && i < LISTE_CAPACITE; i++) {
    if (!memcmp(l->lampes[i].mac, mac, 6)) return i;
  }
  return -1;
}

void liste_fusionner(liste_t *nouvelle, const liste_t *actuelle) {
  for (int i = 0; i < nouvelle->n && i < LISTE_CAPACITE; i++) {
    liste_lampe_t *a = &nouvelle->lampes[i];
    const int j = liste_chercher_mac(actuelle, a->mac);
    a->endpoint = j >= 0 ? actuelle->lampes[j].endpoint : 0;
    a->drapeaux = j >= 0 ? actuelle->lampes[j].drapeaux : 0;
  }
}

bool liste_exposee(const liste_lampe_t *l) { return (l->drapeaux & LISTE_VUE) && !(l->drapeaux & LISTE_MASQUEE); }

bool liste_a_exposer_a_l_ecoute(const liste_lampe_t *l) { return !(l->drapeaux & (LISTE_VUE | LISTE_MASQUEE)); }

void liste_marquer_vue(liste_lampe_t *l) { l->drapeaux |= LISTE_VUE; }

void liste_masquer(liste_lampe_t *l) { l->drapeaux |= LISTE_MASQUEE; }

void liste_afficher(liste_lampe_t *l) { l->drapeaux = (uint8_t)((l->drapeaux | LISTE_VUE) & ~LISTE_MASQUEE); }

// n borne a la capacite : meme une liste non validee ne deborde jamais.
static uint8_t n_borne(const liste_t *l) { return l->n > LISTE_CAPACITE ? LISTE_CAPACITE : l->n; }

uint32_t liste_taille_nvs(const liste_t *l) {
  return (uint32_t)(sizeof(liste_entete_t) + (size_t)n_borne(l) * sizeof(liste_lampe_v2_t));
}

void liste_vers_nvs(const liste_t *l, uint8_t *tampon) {
  const uint8_t n = n_borne(l);
  const liste_entete_t e = {LISTE_VERSION, n, (uint8_t)sizeof(liste_lampe_v2_t), 0};
  memcpy(tampon, &e, sizeof(e));
  for (int i = 0; i < n; i++) {
    const liste_lampe_t *a = &l->lampes[i];
    liste_lampe_v2_t b;
    memset(&b, 0, sizeof(b));
    b.adresse = a->adresse;
    memcpy(b.mac, a->mac, 6);
    memcpy(b.nom, a->nom, LISTE_NOM_MAX);
    b.code = a->code;
    b.endpoint = a->endpoint;
    b.drapeaux = a->drapeaux;
    memcpy(tampon + sizeof(e) + (size_t)i * sizeof(b), &b, sizeof(b));
  }
}

bool liste_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille) {
  memset(l, 0, sizeof(*l));
  liste_entete_t e;
  if (taille < sizeof(e)) return false;
  memcpy(&e, tampon, sizeof(e));
  if (e.version != LISTE_VERSION || e.taille_lampe != sizeof(liste_lampe_v2_t) || e.n > LISTE_CAPACITE ||
      taille != sizeof(e) + (size_t)e.n * sizeof(liste_lampe_v2_t)) {
    return false;
  }
  l->n = e.n;
  for (int i = 0; i < l->n; i++) {
    liste_lampe_t *a = &l->lampes[i];
    liste_lampe_v2_t b;
    memcpy(&b, tampon + sizeof(e) + (size_t)i * sizeof(b), sizeof(b));
    a->adresse = b.adresse;
    memcpy(a->mac, b.mac, 6);
    memcpy(a->nom, b.nom, LISTE_NOM_MAX);
    a->nom[LISTE_NOM_MAX - 1] = '\0';
    a->code = b.code;
    a->endpoint = b.endpoint;
    a->drapeaux = b.drapeaux;
  }
  return true;
}

uint32_t liste_logiciels_taille_nvs(const liste_t *l) {
  uint32_t n = 0;
  for (int i = 0; i < n_borne(l); i++) n += l->lampes[i].logiciel[0] ? 1u : 0u;
  return (uint32_t)(sizeof(liste_entete_t) + n * sizeof(liste_logiciel_nvs_t));
}

void liste_logiciels_vers_nvs(const liste_t *l, uint8_t *tampon) {
  uint8_t n = 0;
  for (int i = 0; i < n_borne(l); i++) {
    const liste_lampe_t *a = &l->lampes[i];
    if (!a->logiciel[0]) continue;
    liste_logiciel_nvs_t v;
    memset(&v, 0, sizeof(v));
    memcpy(v.mac, a->mac, 6);
    memcpy(v.logiciel, a->logiciel, LISTE_LOGICIEL_MAX);
    memcpy(v.ble, a->ble, LISTE_LOGICIEL_MAX);
    v.logiciel[LISTE_LOGICIEL_MAX - 1] = v.ble[LISTE_LOGICIEL_MAX - 1] = '\0';
    memcpy(tampon + sizeof(liste_entete_t) + (size_t)n * sizeof(v), &v, sizeof(v));
    n++;
  }
  const liste_entete_t e = {LISTE_LOGICIELS_VERSION, n, (uint8_t)sizeof(liste_logiciel_nvs_t), 0};
  memcpy(tampon, &e, sizeof(e));
}

bool liste_logiciels_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille) {
  liste_entete_t e;
  if (taille < sizeof(e)) return false;
  memcpy(&e, tampon, sizeof(e));
  if (e.version != LISTE_LOGICIELS_VERSION || e.taille_lampe != sizeof(liste_logiciel_nvs_t) ||
      e.n > LISTE_CAPACITE || taille != sizeof(e) + (size_t)e.n * sizeof(liste_logiciel_nvs_t)) {
    return false;
  }
  for (int k = 0; k < e.n; k++) {
    liste_logiciel_nvs_t v;
    memcpy(&v, tampon + sizeof(e) + (size_t)k * sizeof(v), sizeof(v));
    v.logiciel[LISTE_LOGICIEL_MAX - 1] = v.ble[LISTE_LOGICIEL_MAX - 1] = '\0';
    if (!v.logiciel[0] || !liste_logiciel_valide(v.logiciel) || !liste_logiciel_valide(v.ble)) continue;
    const int i = liste_chercher_mac(l, v.mac);
    if (i < 0) continue;
    memcpy(l->lampes[i].logiciel, v.logiciel, LISTE_LOGICIEL_MAX);
    memcpy(l->lampes[i].ble, v.ble, LISTE_LOGICIEL_MAX);
  }
  return true;
}

void liste_migrer_v1(liste_t *l, const liste_v1_t v1[2], const bool lu[2]) {
  memset(l, 0, sizeof(*l));
  for (int i = 0; i < 2; i++) {
    if (!lu[i] || v1[i].adresse == 0) continue;
    liste_lampe_t *a = &l->lampes[l->n++];
    a->adresse = v1[i].adresse;
    memcpy(a->mac, v1[i].mac, 6);
    memcpy(a->nom, v1[i].nom, LISTE_NOM_MAX);
    a->nom[LISTE_NOM_MAX - 1] = '\0';
    a->code = LISTE_CODE_V1;
    a->endpoint = (uint16_t)(2 + i);
    a->drapeaux = LISTE_VUE;
  }
}
