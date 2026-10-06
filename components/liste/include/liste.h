// Liste des lampes du pont (spec N lampes 4 a 7) : pour chaque lampe, son adresse
// Mesh, sa MAC, son nom, son modele, son numero d'endpoint Matter, son exposition
// dans Maison et la version de son logiciel (spec fiche des lampes 3). C pur, sans ESP-IDF : tout se teste sur le Mac
// (tests/hote/test_liste.c).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LISTE_CAPACITE 16           // lampes au plus ; a relever si le banc de capacite le permet
#define LISTE_NOM_MAX 32            // nom, NUL compris (NodeLabel dans Matter)
#define LISTE_VERSION 2             // format en NVS de la cle "lampes" (1 : les deux emplacements du plan 2)
#define LISTE_LOGICIEL_MAX 8        // version "x.y" (1 a 3 chiffres de chaque cote), NUL compris
#define LISTE_LOGICIELS_VERSION 1   // format en NVS de la cle "logiciels" (spec fiche des lampes 3)
#define LISTE_FABRICANT "Aputure"   // fabricant d'une lampe dans Maison (spec fiche des lampes 2)
// Fin de la reponse a `mesh lampes <N>` d'un pont qui prend la version : outils/cles_amaran.py
// la cherche (VERSION_PERMISE), c'est un contrat.
#define LISTE_JETON_AIDE "[v<x.y>[/<x.y>]]"
#define LISTE_RESERVEE_MIN 0x7F00   // nos adresses (spec du pont 5.4) : jamais celle d'une lampe
#define LISTE_RESERVEE_MAX 0x7F7F
#define LISTE_CODE_V1 40065u        // avant le plan 3a, seules des COB 60d ont pu etre chargees

enum {
  LISTE_VUE = 1u << 0,      // la lampe a repondu au moins une fois : exposee dans Maison
  LISTE_MASQUEE = 1u << 1,  // retiree de Maison par un geste explicite
};

typedef struct {
  uint16_t adresse;         // unicast de la lampe
  uint8_t mac[6];           // identite stable (UniqueID dans Matter)
  char nom[LISTE_NOM_MAX];
  uint32_t code;            // code produit Sidus (40065 : COB 60d) ; 0 : inconnu
  uint16_t endpoint;        // numero d'endpoint Matter ; 0 : pas encore attribue
  uint8_t drapeaux;         // LISTE_VUE, LISTE_MASQUEE
  uint8_t reserve;
  // En NVS sous la cle "logiciels", a part : la cle "lampes" reste au format 2, que
  // relit un firmware d'avant le plan 3b-3.
  char logiciel[LISTE_LOGICIEL_MAX];  // logiciel de commande de la lampe ; "" : inconnu
  char ble[LISTE_LOGICIEL_MAX];       // son module Bluetooth ; "" : inconnu
} liste_lampe_t;

typedef struct {
  uint8_t n;
  liste_lampe_t lampes[LISTE_CAPACITE];
} liste_t;

typedef enum {
  LISTE_OK,
  LISTE_TROP_LONGUE,
  LISTE_ADRESSE_INVALIDE,
  LISTE_ADRESSE_EN_DOUBLE,
  LISTE_MAC_NULLE,
  LISTE_MAC_EN_DOUBLE,
  LISTE_NOM_INVALIDE,
  LISTE_LOGICIEL_INVALIDE,
} liste_erreur_t;

// Premiere faute de la liste ; *fautive : index de la lampe en cause (-1 : la liste).
liste_erreur_t liste_valider(const liste_t *l, int *fautive);
const char *liste_erreur_texte(liste_erreur_t e);
// Index de la lampe de cette MAC, ou -1.
int liste_chercher_mac(const liste_t *l, const uint8_t mac[6]);
// Chargement d'une nouvelle liste, deja validee (liste_valider : pas de MAC en double) :
// une MAC deja connue garde son endpoint et ses drapeaux ; une MAC nouvelle part sans
// endpoint, ni vue ni masquee ; une MAC absente de la nouvelle liste disparait, avec
// son numero (jamais reattribue).
void liste_fusionner(liste_t *nouvelle, const liste_t *actuelle);

// Version d'un logiciel : 1 a 3 chiffres, un point, 1 a 3 chiffres. Vide : valide
// (inconnue).
bool liste_logiciel_valide(const char *v);
// Jeton de version de `mesh lampe` (spec fiche des lampes 3) : v<logiciel>[/<ble>].
// 1 : jeton lu (logiciel, et ble ou "") ; 0 : pas un jeton (ne commence pas par v
// suivi d'un chiffre), rien n'est ecrit ; -1 : jeton mal forme, rien n'est ecrit.
int liste_lire_jeton_logiciel(const char *mot, char logiciel[LISTE_LOGICIEL_MAX], char ble[LISTE_LOGICIEL_MAX]);
// Les mots de `mesh lampe` a partir de argv[i] (apres le code) : argv[i] est le jeton
// s'il est bien forme, sans espace (un nom entre guillemets reste un nom) et suivi
// d'au moins un mot ; sinon il commence le nom, sans erreur. Rend l'index du premier
// mot du nom ; logiciel et ble ne sont ecrits que pour un jeton.
int liste_lire_logiciel_argv(int argc, char *const argv[], int i, char logiciel[LISTE_LOGICIEL_MAX],
                             char ble[LISTE_LOGICIEL_MAX]);
// Programme interne affiche dans Maison : "1.4 (BLE 1.69)", "1.4", ou "" (inconnu).
void liste_texte_logiciel(const liste_lampe_t *l, char *texte, unsigned taille);

// Fiche d'une lampe dans Maison (spec fiche des lampes 2), hors nom et fabricant
// (LISTE_FABRICANT) : modele (nom du catalogue, ou "amaran <code>"), numero de serie
// AMARAN-<MAC>, programme interne ("" : inconnu) et sa forme numerique
// (SoftwareVersion : x * 1000 + y du logiciel de commande ; 0 : inconnu).
typedef struct {
  char produit[33];
  char serie[20];
  char logiciel[24];
  uint32_t logiciel_nombre;
} liste_fiche_t;
void liste_fiche(const liste_lampe_t *l, liste_fiche_t *f);
// Empreinte de ce que Maison voit des lampes exposees : pour chacune, dans l'ordre
// croissant de eps (numeros d'endpoint, distincts), le numero, le nom, la fiche et le
// type d'appareil. Ne depend pas de l'ordre de lampes et eps. FNV-1a 32 bits : une
// comparaison, pas un secret.
uint32_t liste_empreinte_fiches(const liste_lampe_t *const lampes[], const uint16_t eps[], int n);

// Exposition dans Maison (spec N lampes 7).
bool liste_exposee(const liste_lampe_t *l);              // vue et non masquee
bool liste_a_exposer_a_l_ecoute(const liste_lampe_t *l);  // ni vue ni masquee
void liste_marquer_vue(liste_lampe_t *l);
void liste_masquer(liste_lampe_t *l);
void liste_afficher(liste_lampe_t *l);                   // exposee, meme jamais entendue

// Format en NVS : un en-tete, puis n lampes. La taille d'une lampe y est notee : une
// capacite relevee plus tard relit toujours une liste ecrite avant.
typedef struct {
  uint8_t version;          // LISTE_VERSION
  uint8_t n;
  uint8_t taille_lampe;     // sizeof(liste_lampe_t)
  uint8_t reserve;
} liste_entete_t;

// Octets a ecrire pour la liste l (n borne a LISTE_CAPACITE).
uint32_t liste_taille_nvs(const liste_t *l);
// Ecrit la liste dans tampon (au moins liste_taille_nvs(l) octets).
void liste_vers_nvs(const liste_t *l, uint8_t *tampon);
// Relit une liste ecrite par liste_vers_nvs (versions vides : liste_logiciels_depuis_nvs).
// Faux (et liste vide) si le format ne convient pas : version, taille d'une lampe,
// longueur. Les noms relus sont termines.
bool liste_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille);

// Cle "logiciels" : un en-tete (liste_entete_t, version LISTE_LOGICIELS_VERSION), puis,
// pour chaque lampe dont le logiciel est connu, sa MAC et ses versions. Rangees par MAC :
// une liste rechargee par un firmware d'avant le plan 3b-3 ne prete jamais a une lampe
// les versions d'une autre.
typedef struct {
  uint8_t mac[6];
  char logiciel[LISTE_LOGICIEL_MAX];
  char ble[LISTE_LOGICIEL_MAX];
} liste_logiciel_nvs_t;
uint32_t liste_logiciels_taille_nvs(const liste_t *l);
void liste_logiciels_vers_nvs(const liste_t *l, uint8_t *tampon);
// Donne a chaque lampe de l les versions rangees pour sa MAC ; une entree mal formee
// ou d'une MAC absente est ignoree. Faux si le format ne convient pas (rien n'est change).
bool liste_logiciels_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille);

// Format 2 en NVS (plan 3a, toujours en service) : une lampe, sans ses versions.
typedef struct {
  uint16_t adresse;
  uint8_t mac[6];
  char nom[LISTE_NOM_MAX];
  uint32_t code;
  uint16_t endpoint;
  uint8_t drapeaux;
} liste_lampe_v2_t;

// Ancien format (plan 2) : deux emplacements, cles NVS "lampe0" et "lampe1".
typedef struct {
  uint16_t adresse;         // 0 : emplacement libre
  uint8_t mac[6];
  char nom[LISTE_NOM_MAX];
} liste_v1_t;

// Les lampes des emplacements lus et non libres, dans l'ordre. L'emplacement i
// avait toujours l'endpoint 2 + i, et sa tuile existe : la lampe garde ce numero et
// reste exposee. Leur modele : LISTE_CODE_V1.
void liste_migrer_v1(liste_t *l, const liste_v1_t v1[2], const bool lu[2]);

#ifdef __cplusplus
}
#endif
