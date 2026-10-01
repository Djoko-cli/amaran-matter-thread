// Coeur du pont (spec 4.1, 5.6, 5.7, 6.2 a 6.5, 7.1, 7.2) : pour chaque lampe,
// la consigne, le dernier etat lu, la joignabilite et le deroule des ordres.
// C pur, sans ESP-IDF ni Matter : l'horloge (millisecondes) et les sorties sont
// injectees, et tout se teste sur le Mac (tests/hote/test_lampes.c). Une seule
// tache l'appelle : pas de verrou ici.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "telink.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LAMPES_MAX 2
#define LAMPES_GROUPE 0xC000               // groupe « All » : les deux lampes repondent (R5)
#define LAMPES_RELEVE_DEFAUT_MS 5000u      // relecture periodique (spec 5.7 ; R4 : aucun etat spontane)
#define LAMPES_RELEVE_MIN_MS 1000u
#define LAMPES_RELEVE_MAX_MS 60000u
#define LAMPES_REGROUPEMENT_MS 80u         // un ordre attend ce delai : les ecritures d'une meme
                                           // commande Matter (OnOff, CurrentLevel...) partent ensemble
#define LAMPES_DELAI_ETAT_MS 200u          // trames -> demande d'etat (spec 5.6)
#define LAMPES_FENETRE_MS 1000u            // demande d'etat -> etat attendu (spec 5.6)
#define LAMPES_ESSAIS 3u                   // essais par ordre, puis abandon (spec 5.6, 7.1)
#define LAMPES_RELEVES_MUETTE 3u           // relectures sans reponse -> muette (spec 7.2)
#define LAMPES_REPETITIONS_ORDRE 2u
#define LAMPES_REPETITIONS_ETAT 2u        // banc C : ~1 reponse sur 10 manquee (radio partagee avec Thread), deux chances
#define LAMPES_PAS_INTENSITE 10            // une 60d ne garde que le pour cent entier (banc C : 433 relu 430)
#define LAMPES_INTENSITE_RALLUMAGE 400u    // rallumer une lampe noire jamais vue allumee : 40 %, comme la lampe
                                           // d'elle-meme apres une coupure (banc R4)

typedef struct {
  bool marche;
  uint16_t intensite;  // 0..1000, pas de 0,1 %
} lampe_etat_t;

typedef enum {
  LAMPES_SIGNAL_CONFIRME,  // ordre confirme par l'etat lu (voyant : eclat vert)
  LAMPES_SIGNAL_ABANDON,   // ordre abandonne : 3 essais, ou Mesh pas pret (rouge x3)
} lampes_signal_t;

typedef struct {
  // Depose une trame dans la file d'emission de mesh ; faux si elle est refusee.
  bool (*envoyer)(void *ctx, uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions);
  // Ce que Matter doit montrer pour la lampe : etat (NULL : jamais lu) et joignabilite.
  // marche = allumee (en marche ET intensite non nulle) : une lampe noire (en marche a
  // l'intensite 0, molette a 0 %) est eteinte, a sa derniere intensite non nulle lue ;
  // intensite 0 : aucune encore, le niveau de Matter reste ce qu'il est.
  void (*publier)(void *ctx, int lampe, const lampe_etat_t *etat, bool joignable);
  void (*signaler)(void *ctx, int lampe, lampes_signal_t signal);
  void *ctx;
} lampes_sorties_t;

typedef enum {
  LAMPE_REPOS,    // aucun ordre en cours
  LAMPE_TRAMES,   // regroupement (a_refaire : rien n'est parti), puis trames parties ; demande d'etat a echeance
  LAMPE_ATTENTE,  // demande d'etat partie ; etat egal a la consigne attendu avant echeance
} lampe_phase_t;

typedef struct {
  uint16_t adresse;
  // Etat lu
  bool connu;                    // un etat a ete lu depuis le demarrage
  lampe_etat_t lu;
  uint16_t memoire;              // derniere intensite non nulle lue (0 : aucune depuis le demarrage)
  uint32_t reponse_ms;           // derniere trame recue de la lampe
  bool joignable;                // part de vrai (spec 6.5)
  uint8_t releves_sans_reponse;
  bool repondu;                  // une trame depuis la derniere relecture
  uint32_t releves_repondues;    // relectures suivies d'une reponse (banc C, regle 5.8)
  // Consigne : seuls les champs marques comptent
  bool veut_marche, veut_intensite;
  lampe_etat_t consigne;
  lampe_phase_t phase;
  uint8_t essai;                 // 1..LAMPES_ESSAIS
  uint32_t echeance_ms;
  uint32_t demande_ms;           // demande d'etat de l'essai en cours
  uint32_t debut_ms;             // arrivee du dernier ordre de la chaine (delai de confirmation)
  bool a_refaire;                // consigne changee depuis les dernieres trames
  // Ce que Matter montre (publie par nous, ou ecrit par un controleur)
  bool montre_connu;
  lampe_etat_t montre;
  bool montre_joignable;
} lampe_t;

typedef struct {
  lampe_t lampes[LAMPES_MAX];
  int n;
  bool mesh_pret;
  uint32_t periode_ms;
  uint32_t prochaine_releve_ms;
  lampes_sorties_t sorties;
  uint32_t ordres, confirmes, abandons, releves, trames_recues;
  uint32_t delai_total_ms, delai_max_ms;  // ordre -> confirmation (banc C, regle 5.8 : 1 s)
  uint32_t lents;                         // confirmations en plus d'une seconde
} lampes_t;

void lampes_init(lampes_t *l, const uint16_t adresses[], int n, const lampes_sorties_t *sorties,
                 uint32_t maintenant_ms);
// Le reseau Mesh devient utilisable (ou cesse de l'etre). Pret : relecture aussitot.
void lampes_mesh_pret(lampes_t *l, bool pret, uint32_t maintenant_ms);
// Periode de relecture, bornee a [LAMPES_RELEVE_MIN_MS, LAMPES_RELEVE_MAX_MS].
void lampes_regler_releve(lampes_t *l, uint32_t periode_ms);
// Ordre pour une lampe : marche et/ou intensite (NULL : inchange). depuis_matter :
// le controleur a deja mis ces valeurs dans ses attributs. L'intensite est arrondie
// au pour cent le plus proche (au moins 1 % si elle n'est pas nulle) : la lampe ne
// garde pas mieux, et c'est cette valeur que l'etat relu doit egaler. Allumer une
// lampe lue a l'intensite 0 sans donner d'intensite la rallume a sa derniere
// intensite non nulle (LAMPES_INTENSITE_RALLUMAGE si elle n'en a jamais eu).
void lampes_ordre(lampes_t *l, int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter,
                  uint32_t maintenant_ms);
// Trame 0x26 recue d'une adresse (crochet de reception).
void lampes_trame_recue(lampes_t *l, uint16_t src, const uint8_t trame[TELINK_TAILLE], uint32_t maintenant_ms);
// A appeler souvent (toutes les 50 ms) : echeances des ordres et relecture.
void lampes_tic(lampes_t *l, uint32_t maintenant_ms);

// Conversions lineaires (spec 6.2), arrondi au plus proche, demi vers le haut.
uint16_t lampes_niveau_vers_intensite(uint8_t niveau);     // 1..254 -> 0..1000
uint8_t lampes_intensite_vers_niveau(uint16_t intensite);  // -> 1..254

#ifdef __cplusplus
}
#endif
