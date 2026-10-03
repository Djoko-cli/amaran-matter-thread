// Liste des lampes du pont (voir liste.h).
#include "liste.h"

#include <stddef.h>
#include <string.h>

// Le format en NVS est l'image de ces structures : leur disposition ne change pas
// sans changer LISTE_VERSION (la meme sur l'ESP32-C6 et sur le Mac des tests).
_Static_assert(sizeof(liste_entete_t) == 4, "en-tete NVS : 4 octets");
_Static_assert(sizeof(liste_lampe_t) == 48 && offsetof(liste_lampe_t, mac) == 2 && offsetof(liste_lampe_t, nom) == 8 &&
                   offsetof(liste_lampe_t, code) == 40 && offsetof(liste_lampe_t, endpoint) == 44 &&
                   offsetof(liste_lampe_t, drapeaux) == 46,
               "lampe en NVS : 48 octets, disposition fixe");
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

liste_erreur_t liste_valider(const liste_t *l, int *fautive) {
  *fautive = -1;
  if (l->n > LISTE_CAPACITE) return LISTE_TROP_LONGUE;
  for (int i = 0; i < l->n; i++) {
    const liste_lampe_t *a = &l->lampes[i];
    *fautive = i;
    if (!adresse_valide(a->adresse)) return LISTE_ADRESSE_INVALIDE;
    if (!memcmp(a->mac, MAC_NULLE, 6)) return LISTE_MAC_NULLE;
    if (!nom_valide(a->nom)) return LISTE_NOM_INVALIDE;
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
  return (uint32_t)(sizeof(liste_entete_t) + (size_t)n_borne(l) * sizeof(liste_lampe_t));
}

void liste_vers_nvs(const liste_t *l, uint8_t *tampon) {
  const uint8_t n = n_borne(l);
  const liste_entete_t e = {LISTE_VERSION, n, (uint8_t)sizeof(liste_lampe_t), 0};
  memcpy(tampon, &e, sizeof(e));
  memcpy(tampon + sizeof(e), l->lampes, (size_t)n * sizeof(liste_lampe_t));
}

bool liste_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille) {
  memset(l, 0, sizeof(*l));
  liste_entete_t e;
  if (taille < sizeof(e)) return false;
  memcpy(&e, tampon, sizeof(e));
  if (e.version != LISTE_VERSION || e.taille_lampe != sizeof(liste_lampe_t) || e.n > LISTE_CAPACITE ||
      taille != sizeof(e) + (size_t)e.n * sizeof(liste_lampe_t)) {
    return false;
  }
  l->n = e.n;
  memcpy(l->lampes, tampon + sizeof(e), (size_t)e.n * sizeof(liste_lampe_t));
  for (int i = 0; i < l->n; i++) l->lampes[i].nom[LISTE_NOM_MAX - 1] = '\0';
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
