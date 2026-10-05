// Tests sur le Mac du coeur du pont (lampes). Lancer : sh tests/hote/lancer.sh
// Horloge simulee : chaque test fait avancer le temps par tics de 50 ms, comme
// la tache lampes du firmware.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lampes.h"
#include "telink.h"
#include "unite.h"

// --- Sorties enregistrees

typedef struct {
  uint16_t dst;
  uint8_t t[TELINK_TAILLE];
  uint8_t rep;
} envoi_t;

typedef struct {
  int lampe;
  bool connu;
  lampe_etat_t e;
  bool joignable;
} publication_t;

typedef struct {
  int lampe;
  lampes_signal_t s;
} signal_t;

typedef struct {
  int lampe;
  bool manque;
  uint8_t pour_cent;
} alerte_t;

static envoi_t g_envois[512];
static int g_nb_envois;
static publication_t g_pubs[128];
static int g_nb_pubs;
static signal_t g_sigs[64];
static int g_nb_sigs;
static alerte_t g_alertes[16];
static int g_nb_alertes;
static bool g_refuser;

#define NB_ELEMENTS(tableau) ((int)(sizeof(tableau) / sizeof((tableau)[0])))

// Un tableau d'enregistrement plein est un echec du test, jamais un depassement
// silencieux (comportement indefini, ou vert trompeur).
static void debordement(const char *tableau) {
  VERIFIE(false, "tableau %s plein : une sortie n'est pas enregistree", tableau);
}

static bool f_envoyer(void *ctx, uint16_t dst, const uint8_t t[TELINK_TAILLE], uint8_t rep) {
  (void)ctx;
  if (g_refuser) return false;
  if (g_nb_envois >= NB_ELEMENTS(g_envois)) {
    debordement("g_envois");
    return true;
  }
  g_envois[g_nb_envois].dst = dst;
  memcpy(g_envois[g_nb_envois].t, t, TELINK_TAILLE);
  g_envois[g_nb_envois].rep = rep;
  g_nb_envois++;
  return true;
}

static void f_publier(void *ctx, int lampe, const lampe_etat_t *e, bool joignable) {
  (void)ctx;
  if (g_nb_pubs >= NB_ELEMENTS(g_pubs)) {
    debordement("g_pubs");
    return;
  }
  publication_t *p = &g_pubs[g_nb_pubs++];
  p->lampe = lampe;
  p->connu = e != NULL;
  if (e) p->e = *e;
  p->joignable = joignable;
}

static void f_signaler(void *ctx, int lampe, lampes_signal_t s) {
  (void)ctx;
  if (g_nb_sigs >= NB_ELEMENTS(g_sigs)) {
    debordement("g_sigs");
    return;
  }
  g_sigs[g_nb_sigs].lampe = lampe;
  g_sigs[g_nb_sigs].s = s;
  g_nb_sigs++;
}

static void f_alerter(void *ctx, int lampe, bool manque, uint8_t pour_cent) {
  (void)ctx;
  if (g_nb_alertes >= NB_ELEMENTS(g_alertes)) {
    debordement("g_alertes");
    return;
  }
  g_alertes[g_nb_alertes].lampe = lampe;
  g_alertes[g_nb_alertes].manque = manque;
  g_alertes[g_nb_alertes].pour_cent = pour_cent;
  g_nb_alertes++;
}

static void oublier_sorties(void) {
  g_nb_envois = g_nb_pubs = g_nb_sigs = g_nb_alertes = 0;
  g_refuser = false;
}

// --- Aides

static const uint16_t ADR[2] = {0x0002, 0x0004};
static lampes_t L;
static uint32_t T;  // horloge simulee

static void demarrer(uint32_t t0, bool pret) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, f_alerter, NULL};
  T = t0;
  lampes_init(&L, ADR, 2, &s, T);
  if (pret) lampes_mesh_pret(&L, true, T);
  lampes_tic(&L, T);  // premiere relecture
  oublier_sorties();
}

static void avancer(uint32_t ms) {
  if (ms % 50 != 0) {  // l'horloge avance par tics de 50 ms : sans cela, la boucle ne finirait jamais
    fflush(stdout);
    fprintf(stderr, "avancer(%u) : la duree doit etre un multiple de 50 ms\n", (unsigned)ms);
    abort();
  }
  const uint32_t fin = T + ms;
  while (T != fin) {
    T += 50;
    lampes_tic(&L, T);
  }
}

static void trame_etat(uint8_t t[TELINK_TAILLE], bool marche, uint16_t v) {
  memset(t, 0, TELINK_TAILLE);
  t[1] = marche ? 0x01 : 0x00;
  t[5] = 0x40;  // champs de temperature, comme au banc
  t[6] = 0x01;
  t[7] = (uint8_t)(((v & 0x03) << 6) | 0x23);
  t[8] = (uint8_t)(v >> 2);
  t[9] = TELINK_MODE_CCT;
  t[0] = telink_somme(t);
}

static void recevoir(uint16_t src, bool marche, uint16_t v) {
  uint8_t t[TELINK_TAILLE];
  trame_etat(t, marche, v);
  lampes_trame_recue(&L, src, t, T);
}

static void ordre_matter(int lampe, const bool *marche, const uint16_t *intensite) {
  lampes_ordre(&L, lampe, marche, intensite, true, T);
}

// Nombre de trames de type cmd (octet 9) envoyees a dst.
static int compter(uint16_t dst, uint8_t cmd) {
  int n = 0;
  for (int i = 0; i < g_nb_envois; i++) {
    if (g_envois[i].dst == dst && g_envois[i].t[9] == cmd) n++;
  }
  return n;
}

static uint16_t intensite_envoyee(const envoi_t *e) { return (uint16_t)(((unsigned)e->t[8] << 2) | (e->t[7] >> 6)); }

// Repart de zero : la lampe 1 est relue eteinte a 500, puis un ordre d'intensite
// `demande` arrive. Rend l'intensite de la trame partie apres le regroupement, ou
// -1 si aucune trame d'intensite n'est partie.
static int intensite_partie_pour(uint16_t demande, bool depuis_matter) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  lampes_ordre(&L, 0, NULL, &demande, depuis_matter, T);
  avancer(100);  // 80 ms de regroupement : les trames sont parties
  for (int i = 0; i < g_nb_envois; i++) {
    if (g_envois[i].dst == 0x0002 && g_envois[i].t[9] == TELINK_CMD_INTENSITE) return intensite_envoyee(&g_envois[i]);
  }
  return -1;
}

// Trames d'ordre (marche ou intensite) envoyees, a toutes les adresses.
static int compter_ordres(void) {
  int n = 0;
  for (int i = 0; i < g_nb_envois; i++) {
    if (g_envois[i].t[9] == TELINK_CMD_MARCHE || g_envois[i].t[9] == TELINK_CMD_INTENSITE) n++;
  }
  return n;
}

// Publications d'une lampe : leur nombre, et la derniere (NULL si aucune).
static int publications_de(int lampe) {
  int n = 0;
  for (int i = 0; i < g_nb_pubs; i++) {
    if (g_pubs[i].lampe == lampe) n++;
  }
  return n;
}

static const publication_t *derniere_pub(int lampe) {
  const publication_t *r = NULL;
  for (int i = 0; i < g_nb_pubs; i++) {
    if (g_pubs[i].lampe == lampe) r = &g_pubs[i];
  }
  return r;
}

// Lampe 1 lue en marche a l'intensite 0 (molette a 0 %), apres avoir ete vue a 300
// si avec_memoire. Les sorties sont oubliees : le test part de cet etat.
static void lampe_noire(bool avec_memoire) {
  demarrer(0, true);
  if (avec_memoire) recevoir(0x0002, true, 300);
  recevoir(0x0002, true, 0);
  oublier_sorties();
}

// --- Tests

static void test_conversion(void) {
  VERIFIE(lampes_niveau_vers_intensite(1) == 4, "niveau 1 -> 4");
  VERIFIE(lampes_niveau_vers_intensite(127) == 500, "niveau 127 -> 500");
  VERIFIE(lampes_niveau_vers_intensite(254) == 1000, "niveau 254 -> 1000");
  VERIFIE(lampes_niveau_vers_intensite(0) == 4, "niveau 0 borne a 1");
  VERIFIE(lampes_niveau_vers_intensite(255) == 1000, "niveau 255 borne a 254");
  VERIFIE(lampes_intensite_vers_niveau(0) == 1, "intensite 0 -> niveau 1");
  VERIFIE(lampes_intensite_vers_niveau(500) == 127, "intensite 500 -> 127");
  VERIFIE(lampes_intensite_vers_niveau(1000) == 254, "intensite 1000 -> 254");
  VERIFIE(lampes_intensite_vers_niveau(2000) == 254, "intensite bornee a 1000");
  int ecarts = 0;
  for (int n = 1; n <= 254; n++) {
    if (lampes_intensite_vers_niveau(lampes_niveau_vers_intensite((uint8_t)n)) != n) ecarts++;
  }
  VERIFIE(ecarts == 0, "aller-retour exact sur les 254 niveaux (%d ecarts)", ecarts);
}

static void test_demarrage_relit_aussitot(void) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, f_alerter, NULL};
  oublier_sorties();
  T = 1000;
  lampes_init(&L, ADR, 2, &s, T);
  lampes_mesh_pret(&L, true, T);
  lampes_tic(&L, T);
  VERIFIE(g_nb_envois == 1 && g_envois[0].dst == LAMPES_GROUPE && g_envois[0].t[9] == TELINK_CMD_ETAT &&
              g_envois[0].rep == LAMPES_REPETITIONS_ETAT,
          "une demande d'etat au groupe, aussitot");
  VERIFIE(g_nb_pubs == 0 && g_nb_sigs == 0, "rien de publie avant le premier etat lu");
  avancer(LAMPES_RELEVE_DEFAUT_MS);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 2, "relecture suivante une periode plus tard");
}

static void test_premier_etat_publie_doublons_ignores(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 930);
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].lampe == 0 && g_pubs[0].connu && !g_pubs[0].e.marche &&
              g_pubs[0].e.intensite == 930 && g_pubs[0].joignable,
          "premier etat publie");
  recevoir(0x0002, false, 930);
  recevoir(0x0002, false, 930);
  VERIFIE(g_nb_pubs == 1, "copies reseau du meme etat : rien de plus");
  recevoir(0x0002, true, 930);
  VERIFIE(g_nb_pubs == 2 && g_pubs[1].e.marche, "changement publie");
  recevoir(0x0009, true, 100);
  VERIFIE(g_nb_pubs == 2, "adresse inconnue ignoree");
}

static void test_ordre_confirme(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(50);
  VERIFIE(g_nb_envois == 0, "rien ne part pendant le regroupement (80 ms)");
  avancer(50);
  VERIFIE(g_nb_envois == 1 && g_envois[0].dst == 0x0002 && g_envois[0].t[9] == TELINK_CMD_MARCHE &&
              g_envois[0].t[8] == 1 && g_envois[0].rep == LAMPES_REPETITIONS_ORDRE,
          "marche envoyee 2 fois au premier tic apres le regroupement");
  avancer(150);
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 0, "pas de demande d'etat avant 200 ms");
  avancer(50);
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 1, "demande d'etat 200 ms apres les trames");
  avancer(100);
  recevoir(0x0002, true, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "ordre confirme");
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].e.marche && g_pubs[0].e.intensite == 500, "etat confirme publie");
  VERIFIE(L.confirmes == 1 && L.lampes[0].phase == LAMPE_REPOS, "compteur et repos");
  VERIFIE(L.lampes[0].dernier_delai_ms == 400 && L.lampes[0].essai == 1,
          "delai du dernier ordre (%u ms), au premier essai", (unsigned)L.lampes[0].dernier_delai_ms);
}

static void test_niveau_puis_marche_en_une_salve(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 930);
  oublier_sorties();
  const bool on = true;
  const uint16_t v = 300;
  ordre_matter(0, NULL, &v);  // MoveToLevelWithOnOff : CurrentLevel puis OnOff, ensemble
  ordre_matter(0, &on, NULL);
  avancer(100);
  VERIFIE(g_nb_envois == 2, "une salve de deux trames (%d)", g_nb_envois);
  VERIFIE(g_envois[0].t[9] == TELINK_CMD_INTENSITE && intensite_envoyee(&g_envois[0]) == 300,
          "le niveau d'abord");
  VERIFIE(g_envois[1].t[9] == TELINK_CMD_MARCHE && g_envois[1].t[8] == 1, "puis la marche (R3)");
  avancer(200);
  recevoir(0x0002, true, 300);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme par un seul etat");
}

static void test_effet_d_arret_regroupe(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 600);
  oublier_sorties();
  const bool off = false;
  const uint16_t mini = lampes_niveau_vers_intensite(1), avant = 600;
  ordre_matter(0, NULL, &mini);  // LevelControl, effet d'arret : minimum,
  ordre_matter(0, &off, NULL);   // puis OnOff faux,
  ordre_matter(0, NULL, &avant);  // puis niveau restaure : dans la meme commande
  avancer(100);
  VERIFIE(compter(0x0002, TELINK_CMD_INTENSITE) == 1 && compter(0x0002, TELINK_CMD_MARCHE) == 1,
          "une seule salve (%d trames)", g_nb_envois);
  const envoi_t *niveau = NULL;
  for (int i = 0; i < g_nb_envois; i++) {
    if (g_envois[i].t[9] == TELINK_CMD_INTENSITE) niveau = &g_envois[i];
  }
  VERIFIE(niveau && intensite_envoyee(niveau) == 600, "jamais le minimum : pas d'eclat");
  VERIFIE(g_envois[0].t[9] == TELINK_CMD_MARCHE && g_envois[0].t[8] == 0, "l'arret en premier");
}

static void test_eteindre_avant_le_niveau(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 500);
  oublier_sorties();
  const bool off = false;
  const uint16_t v = 100;
  ordre_matter(0, &off, &v);
  avancer(100);
  VERIFIE(g_nb_envois == 2 && g_envois[0].t[9] == TELINK_CMD_MARCHE && g_envois[0].t[8] == 0 &&
              g_envois[1].t[9] == TELINK_CMD_INTENSITE,
          "arret puis niveau : aucun eclat");
  avancer(200);
  recevoir(0x0002, false, 100);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme eteinte au nouveau niveau");
}

static void test_trois_essais_puis_abandon(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(3600);  // 50 + 3 x (200 + 1000) - 50
  VERIFIE(g_nb_sigs == 0, "pas encore d'abandon a 3,6 s");
  avancer(100);
  VERIFIE(compter(0x0002, TELINK_CMD_MARCHE) == 3, "trois essais (%d)", compter(0x0002, TELINK_CMD_MARCHE));
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 3, "trois demandes d'etat");
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_ABANDON, "abandon apres le 3e essai");
  VERIFIE(g_nb_pubs == 1 && !g_pubs[0].e.marche && g_pubs[0].e.intensite == 500,
          "Maison revient au dernier etat lu");
  VERIFIE(L.abandons == 1 && L.lampes[0].phase == LAMPE_REPOS && !L.lampes[0].veut_marche,
          "consigne effacee");
  VERIFIE(L.lampes[0].dernier_delai_ms == 3700 && L.lampes[0].essai == LAMPES_ESSAIS,
          "abandon : delai depuis l'ordre (%u ms), au dernier essai", (unsigned)L.lampes[0].dernier_delai_ms);
}

static void test_curseur_glisse_sans_empilement(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 500);
  oublier_sorties();
  for (int k = 0; k < 10; k++) {  // curseur glisse : 10 valeurs en 500 ms
    const uint16_t v = (uint16_t)(510 + 10 * k);
    ordre_matter(0, NULL, &v);
    avancer(50);
  }
  const int salves = compter(0x0002, TELINK_CMD_INTENSITE);
  VERIFIE(salves <= 4, "au plus une salve par 200 ms (%d)", salves);
  avancer(400);  // derniere salve a 650 ms, demande d'etat a 850 ms
  const envoi_t *dernier = NULL;
  for (int i = 0; i < g_nb_envois; i++) {
    if (g_envois[i].t[9] == TELINK_CMD_INTENSITE) dernier = &g_envois[i];
  }
  VERIFIE(dernier && intensite_envoyee(dernier) == 600, "la derniere valeur part");
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 1, "une seule demande d'etat, apres la derniere salve");
  recevoir(0x0002, true, 600);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme a la derniere valeur");
}

static void test_etat_perime_ignore(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(100);
  recevoir(0x0002, true, 500);  // pendant les trames : ne confirme pas
  VERIFIE(g_nb_sigs == 0 && g_nb_pubs == 0, "etat recu avant la demande : ni confirme ni montre");
  avancer(200);
  recevoir(0x0002, false, 500);  // perime (reponse a une relecture d'avant)
  VERIFIE(g_nb_sigs == 0 && g_nb_pubs == 0, "etat perime : ni confirme ni montre");
  recevoir(0x0002, true, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "le bon etat confirme");
}

static void test_valeur_egale_n_emet_pas(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 500);
  oublier_sorties();
  const bool on = true;
  const uint16_t v = 500;
  ordre_matter(0, &on, &v);
  avancer(1500);
  VERIFIE(compter(0x0002, TELINK_CMD_MARCHE) == 0 && compter(0x0002, TELINK_CMD_INTENSITE) == 0,
          "rien n'est emis");
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_TENU && g_sigs[0].lampe == 0,
          "un signal : deja tenu (%d signaux)", g_nb_sigs);
  VERIFIE(L.tenus == 1 && L.confirmes == 0 && L.abandons == 0 && L.lampes[0].dernier_delai_ms == 0,
          "compte comme tenu, sans delai");
}

static void test_muette_apres_trois_releves(void) {
  demarrer(0, true);  // relecture 1 a 0 ms, deja faite
  avancer(2 * LAMPES_RELEVE_DEFAUT_MS);  // relectures 2 et 3
  VERIFIE(g_nb_pubs == 0, "encore joignable apres deux periodes");
  avancer(LAMPES_RELEVE_DEFAUT_MS);  // relecture 4 : trois relectures sans reponse
  VERIFIE(g_nb_pubs == 2 && !g_pubs[0].joignable && !g_pubs[1].joignable && !g_pubs[0].connu,
          "les deux lampes muettes a la quatrieme relecture");
  recevoir(0x0004, false, 60);
  VERIFIE(g_nb_pubs == 3 && g_pubs[2].lampe == 1 && g_pubs[2].joignable && g_pubs[2].connu &&
              g_pubs[2].e.intensite == 60,
          "premiere reponse : joignable et etat reel");
}

static void test_trame_non_lue_prouve_la_vie(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 930);
  avancer(20000);
  oublier_sorties();
  VERIFIE(!L.lampes[0].joignable, "muette");
  const uint8_t alim[TELINK_TAILLE] = {0x86, 0, 0, 0, 0, 0, 0, 0x31, 0x4B, 0x0A};  // releve au banc
  lampes_trame_recue(&L, 0x0002, alim, T);
  VERIFIE(L.lampes[0].joignable, "une trame 0x0A suffit");
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].joignable && g_pubs[0].connu && g_pubs[0].e.intensite == 930,
          "republiee joignable avec le dernier etat lu");
}

static void test_mesh_pas_pret(void) {
  demarrer(0, false);
  const bool on = true;
  ordre_matter(0, &on, NULL);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_ABANDON, "ordre abandonne aussitot");
  avancer(20000);
  VERIFIE(g_nb_envois == 0, "rien n'est emis");
  int muettes = 0;
  for (int i = 0; i < g_nb_pubs; i++) {
    if (!g_pubs[i].joignable) muettes++;
  }
  VERIFIE(muettes == 2, "les deux lampes muettes au bout de trois periodes (7.3)");
}

static void test_mesh_perdu_pendant_un_ordre(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(300);
  lampes_mesh_pret(&L, false, T);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].lampe == 0 && g_sigs[0].s == LAMPES_SIGNAL_ABANDON,
          "ordre de la lampe 1 abandonne");
  lampes_mesh_pret(&L, true, T + 2000);
  oublier_sorties();
  lampes_tic(&L, T + 2000);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 1, "relecture aussitot au retour du Mesh");
}

// La tache redit l'etat du Mesh a chaque tic : seul un changement compte, sinon une
// relecture partirait a chaque tic.
static void test_mesh_pret_redit_sans_effet(void) {
  demarrer(0, true);
  avancer(500);
  lampes_mesh_pret(&L, true, T);
  avancer(50);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 0, "Mesh pret redit : pas de relecture de plus");
}

static void test_ordre_console(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 500);
  oublier_sorties();
  const bool off = false;
  lampes_ordre(&L, 0, &off, NULL, false, T);
  avancer(300);
  recevoir(0x0002, false, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme");
  VERIFIE(g_nb_pubs == 1 && !g_pubs[0].e.marche, "Maison apprend le changement fait a la console");
}

static void test_horloge_qui_deborde(void) {
  demarrer(0xFFFFFF06u, true);  // 250 ms avant le debordement
  recevoir(0x0002, false, 500);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(150);  // trames a -150 ms ; echeance de la demande d'etat a +50 ms, apres 0
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 0, "pas de demande d'etat avant l'echeance, avant 0");
  avancer(200);
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 1, "demande d'etat apres le debordement");
  recevoir(0x0002, true, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme de l'autre cote de 0");
}

static void test_regler_releve(void) {
  demarrer(0, true);
  lampes_regler_releve(&L, 500);
  VERIFIE(L.periode_ms == LAMPES_RELEVE_MIN_MS, "borne basse");
  lampes_regler_releve(&L, 100000);
  VERIFIE(L.periode_ms == LAMPES_RELEVE_MAX_MS, "borne haute");
  lampes_regler_releve(&L, 7000);
  avancer(LAMPES_RELEVE_DEFAUT_MS);  // la periode en cours s'acheve, puis 7 s
  const int avant = compter(LAMPES_GROUPE, TELINK_CMD_ETAT);
  avancer(6950);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == avant, "rien avant la nouvelle periode");
  avancer(50);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == avant + 1, "nouvelle periode appliquee");
}

static void test_file_refusee(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  g_refuser = true;
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(1200);      // essai 1 (trames et demande d'etat) refuse par la file
  g_refuser = false;  // la file se libere : l'essai 2 part a 1250 ms
  avancer(300);
  VERIFIE(compter(0x0002, TELINK_CMD_MARCHE) == 1, "l'essai suivant renvoie la trame");
  recevoir(0x0002, true, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme malgre le refus");
}

static void test_mesures_du_banc_c(void) {
  demarrer(0, true);  // relecture 1 partie a 0 ms
  recevoir(0x0002, false, 500);
  recevoir(0x0002, false, 500);  // copie : une seule reponse comptee
  avancer(LAMPES_RELEVE_DEFAUT_MS);  // relecture 2 : sans reponse
  avancer(LAMPES_RELEVE_DEFAUT_MS);  // relecture 3
  recevoir(0x0002, false, 500);
  VERIFIE(L.releves == 3 && L.lampes[0].releves_repondues == 2 && L.lampes[1].releves_repondues == 0,
          "relectures repondues : %u sur %u (lampe 1)", (unsigned)L.lampes[0].releves_repondues,
          (unsigned)L.releves);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(350);  // trames a 100 ms, demande d'etat a 300 ms
  recevoir(0x0002, true, 500);
  VERIFIE(L.confirmes == 1 && L.delai_max_ms == 350 && L.delai_total_ms == 350 && L.lents == 0,
          "delai de confirmation mesure (%u ms)", (unsigned)L.delai_max_ms);
  const bool off = false;
  ordre_matter(0, &off, NULL);
  avancer(1500);  // essai 1 sans reponse ; essai 2 : trames a 1400 ms, demande a 1600 ms
  avancer(150);
  recevoir(0x0002, false, 500);
  VERIFIE(L.confirmes == 2 && L.lents == 1 && L.delai_max_ms == 1650, "confirmation lente comptee (%u ms)",
          (unsigned)L.delai_max_ms);
}

static void test_delai_depuis_le_dernier_ordre(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 500);
  oublier_sorties();
  for (int k = 0; k < 12; k++) {  // curseur de Maison : une valeur toutes les 250 ms pendant 3 s
    const uint16_t v = (uint16_t)(510 + 10 * k);
    ordre_matter(0, NULL, &v);
    avancer(250);
  }
  avancer(500);  // la derniere valeur (620) est partie, sa demande d'etat aussi
  recevoir(0x0002, true, 620);
  VERIFIE(L.confirmes == 1 && L.lents == 0 && L.delai_max_ms < 1000,
          "delai compte depuis la derniere valeur (%u ms)", (unsigned)L.delai_max_ms);
}

// Une 60d ne garde que le pour cent entier de l'intensite (banc C : 433 relu 430,
// 437 relu 430). La consigne est donc arrondie au pour cent le plus proche avant
// d'etre envoyee et comparee a l'etat relu ; sans cela, toute consigne qui n'est
// pas un multiple de 10 serait abandonnee apres 3 essais alors que la lampe a obei.
static void test_intensite_au_pour_cent(void) {
  demarrer(0, true);
  recevoir(0x0002, false, 500);
  oublier_sorties();
  const uint16_t v = 433;  // niveau 110 de Maison
  ordre_matter(0, NULL, &v);
  avancer(100);
  VERIFIE(g_nb_envois == 1 && g_envois[0].t[9] == TELINK_CMD_INTENSITE, "une trame d'intensite (%d envois)",
          g_nb_envois);
  VERIFIE(intensite_envoyee(&g_envois[0]) == 430, "433 part a 430 (%u)", (unsigned)intensite_envoyee(&g_envois[0]));
  avancer(200);
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 1, "demande d'etat 200 ms apres la trame");
  recevoir(0x0002, false, 430);  // la lampe a obei : elle relit 430
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "ordre confirme par l'etat relu a 430 (%d signaux)",
          g_nb_sigs);
  VERIFIE(L.confirmes == 1 && L.abandons == 0 && L.lampes[0].phase == LAMPE_REPOS, "confirme, sans abandon");

  VERIFIE(intensite_partie_pour(437, true) == 440, "437 part a 440 : le pour cent le plus proche");
  VERIFIE(intensite_partie_pour(435, true) == 440, "435 part a 440 : demi vers le haut");
  VERIFIE(intensite_partie_pour(4, true) == 10, "4 part a 10 : au moins un pour cent (niveau 1 de Matter)");
  VERIFIE(intensite_partie_pour(0, false) == 0, "0 reste 0 (ordre de la console)");
  VERIFIE(intensite_partie_pour(995, true) == 1000, "995 part a 1000");
  VERIFIE(intensite_partie_pour(65535, true) == 1000, "au-dela du maximum : borne a 1000");

  // Lampe relue a 430 : un ordre a 433 est deja tenu, egal apres l'arrondi.
  demarrer(0, true);
  recevoir(0x0002, false, 430);
  oublier_sorties();
  ordre_matter(0, NULL, &v);
  avancer(1500);
  VERIFIE(compter(0x0002, TELINK_CMD_INTENSITE) == 0, "433 egale 430 relu : aucune trame d'intensite");
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 0, "aucune demande d'etat pour cet ordre");
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_TENU, "ni confirmation ni abandon : deja tenu");
}

// --- Lampe noire (banc du 01/10) : molette a 0 %, la lampe reste en marche a
// l'intensite 0 et n'eclaire pas. Maison la montre eteinte, au dernier niveau non
// nul lu ; On la rallume a ce niveau ; le pont n'eteint jamais de lui-meme une lampe
// noire : sa molette resterait sans effet (PROTOCOLE.md).

static void test_noire_montree_eteinte(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 0);
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].lampe == 0 && g_pubs[0].connu && !g_pubs[0].e.marche &&
              g_pubs[0].e.intensite == 0,
          "premier etat {marche, 0} : montre eteint, intensite 0 (%d publication(s))", g_nb_pubs);
  recevoir(0x0002, true, 300);
  VERIFIE(g_nb_pubs == 2 && g_pubs[1].e.marche && g_pubs[1].e.intensite == 300, "puis {marche, 300} : allumee a 300");
  recevoir(0x0002, true, 0);
  VERIFIE(g_nb_pubs == 3 && !g_pubs[2].e.marche && g_pubs[2].e.intensite == 300,
          "molette a 0 : eteinte, au dernier niveau non nul (300)");
  recevoir(0x0002, false, 0);
  recevoir(0x0002, true, 0);
  VERIFIE(g_nb_pubs == 3, "{arret, 0} puis {marche, 0} : meme vue, rien de plus (%d publications)", g_nb_pubs);
}

static void test_allumer_une_noire(void) {
  lampe_noire(true);
  const bool on = true;
  ordre_matter(0, &on, NULL);  // On seul : sans intensite, l'ordre serait deja tenu (6.4)
  avancer(100);
  VERIFIE(g_nb_envois == 2 && g_envois[0].dst == 0x0002 && g_envois[0].t[9] == TELINK_CMD_INTENSITE &&
              intensite_envoyee(&g_envois[0]) == 300 && g_envois[1].t[9] == TELINK_CMD_MARCHE &&
              g_envois[1].t[8] == 1,
          "2 trames : l'intensite retenue (300), puis la marche (%d trames)", g_nb_envois);
  avancer(200);
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 1, "une demande d'etat 200 ms apres les trames");
  recevoir(0x0002, true, 300);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme par l'etat relu a 300");
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].e.marche && g_pubs[0].e.intensite == 300, "Maison voit la lampe allumee a 300");
}

static void test_allumer_une_noire_avec_l_effet(void) {
  lampe_noire(true);
  const bool on = true;
  const uint16_t mini = lampes_niveau_vers_intensite(1), garde = lampes_niveau_vers_intensite(127);
  ordre_matter(0, &on, NULL);     // On de Maison,
  ordre_matter(0, NULL, &mini);   // puis l'effet de LevelControl : minimum,
  ordre_matter(0, NULL, &garde);  // puis le niveau garde par le controleur (127 : 500)
  avancer(100);
  VERIFIE(g_nb_envois == 2 && g_envois[0].t[9] == TELINK_CMD_INTENSITE && intensite_envoyee(&g_envois[0]) == 500 &&
              g_envois[1].t[9] == TELINK_CMD_MARCHE && g_envois[1].t[8] == 1,
          "une seule salve : intensite 500, puis marche (%d trames)", g_nb_envois);
  avancer(200);
  recevoir(0x0002, true, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme a {marche, 500}");
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].e.marche && g_pubs[0].e.intensite == 500, "Maison voit la lampe allumee a 500");
}

static void test_allumer_une_noire_sans_memoire(void) {
  lampe_noire(false);  // jamais vue allumee depuis le demarrage
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(100);
  VERIFIE(g_nb_envois == 2 && g_envois[0].t[9] == TELINK_CMD_INTENSITE &&
              intensite_envoyee(&g_envois[0]) == LAMPES_INTENSITE_RALLUMAGE && g_envois[1].t[9] == TELINK_CMD_MARCHE,
          "sans memoire : l'intensite de rallumage (%u), puis la marche", (unsigned)LAMPES_INTENSITE_RALLUMAGE);
  avancer(200);
  recevoir(0x0002, true, LAMPES_INTENSITE_RALLUMAGE);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme a l'intensite de rallumage");
}

static void test_allumer_eteinte_a_zero(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 300);
  recevoir(0x0002, false, 0);  // eteinte a l'intensite 0 : Maison la montre eteinte a 300
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(100);
  VERIFIE(g_nb_envois == 2 && g_envois[0].t[9] == TELINK_CMD_INTENSITE && intensite_envoyee(&g_envois[0]) == 300 &&
              g_envois[1].t[9] == TELINK_CMD_MARCHE && g_envois[1].t[8] == 1,
          "intensite 300 d'abord, puis la marche : pas de lumiere a 0 (%d trames)", g_nb_envois);
  avancer(200);
  recevoir(0x0002, true, 300);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme a {marche, 300}");
}

static void test_molette_remonte_de_zero(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 300);
  recevoir(0x0002, true, 0);  // la molette descend a 0 %
  const publication_t *vue = derniere_pub(0);
  VERIFIE(vue && !vue->e.marche && vue->e.intensite == 300, "Maison voit la lampe eteinte, au niveau 300");
  oublier_sorties();
  for (int k = 0; k < 6; k++) {  // 30 s de relectures, toutes repondues {marche, 0}
    avancer(5000);
    recevoir(0x0002, true, 0);
  }
  VERIFIE(compter_ordres() == 0, "le pont n'eteint ni ne regle jamais une lampe noire (%d trames d'ordre)",
          compter_ordres());
  VERIFIE(publications_de(0) == 0, "la vue ne change pas : rien de republie (%d)", publications_de(0));
  recevoir(0x0002, true, 200);  // la molette remonte
  const publication_t *apres = derniere_pub(0);
  VERIFIE(publications_de(0) == 1 && apres && apres->e.marche && apres->e.intensite == 200,
          "la molette remonte : Maison voit la lampe allumee a 200");
}

static void test_abandon_d_un_allumage_de_noire(void) {
  lampe_noire(true);
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(3700);  // trois essais sans reponse : 100 + 3 x (200 + 1000) ms
  VERIFIE(compter(0x0002, TELINK_CMD_INTENSITE) == 3 && compter(0x0002, TELINK_CMD_MARCHE) == 3,
          "chaque essai renvoie l'intensite et la marche");
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_ABANDON, "abandon apres le 3e essai (%d signaux)", g_nb_sigs);
  const publication_t *p = derniere_pub(0);
  VERIFIE(p && p->connu && !p->e.marche && p->e.intensite == 300, "Maison revient a eteinte, au niveau retenu (300)");
}

static void test_niveau_seul_sur_une_noire(void) {
  lampe_noire(true);
  const uint16_t v = 500;
  ordre_matter(0, NULL, &v);  // MoveToLevel sans OnOff : la lampe est deja en marche, elle s'allume
  avancer(100);
  VERIFIE(compter(0x0002, TELINK_CMD_INTENSITE) == 1 && compter(0x0002, TELINK_CMD_MARCHE) == 0,
          "une trame d'intensite, aucune trame de marche (%d trames)", g_nb_envois);
  avancer(200);
  recevoir(0x0002, true, 500);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_CONFIRME, "confirme a {marche, 500}");
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].e.marche && g_pubs[0].e.intensite == 500, "Maison voit la lampe allumee a 500");
}

// Garde-fou de 6.4 : la regle de la lampe noire ne joue pas sur une lampe allumee.
static void test_on_sur_allumee_n_emet_pas(void) {
  demarrer(0, true);
  recevoir(0x0002, true, 300);
  oublier_sorties();
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(1500);
  VERIFIE(g_nb_envois == 0, "aucune trame (%d)", g_nb_envois);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_TENU, "ni confirmation ni abandon : deja tenu");
}

// Une lampe jamais lue n'est pas connue noire : un On n'invente aucune intensite.
static void test_on_sur_lampe_jamais_lue(void) {
  demarrer(0, true);
  const bool on = true;
  ordre_matter(0, &on, NULL);
  avancer(100);
  VERIFIE(g_nb_envois == 1 && g_envois[0].t[9] == TELINK_CMD_MARCHE && g_envois[0].t[8] == 1,
          "la seule trame de marche (%d trames)", g_nb_envois);
}

// --- Plan 3a : N lampes, lampe entendue, publication forcee, alerte de relectures

static void test_capacite(void) {
  uint16_t adresses[LAMPES_CAPACITE + 4];
  for (int i = 0; i < LAMPES_CAPACITE + 4; i++) adresses[i] = (uint16_t)(0x0010 + i);
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, f_alerter, NULL};
  T = 0;
  lampes_init(&L, adresses, LAMPES_CAPACITE + 4, &s, T);
  VERIFIE(L.n == LAMPES_CAPACITE, "au plus LAMPES_CAPACITE lampes (%d)", L.n);
  lampes_mesh_pret(&L, true, T);
  oublier_sorties();
  lampes_tic(&L, T);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 1, "une seule demande au groupe, pour toutes les lampes");
  recevoir((uint16_t)(0x0010 + LAMPES_CAPACITE - 1), true, 500);
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].lampe == LAMPES_CAPACITE - 1 && g_pubs[0].e.intensite == 500,
          "la derniere lampe est lue et publiee");
}

// Toute trame prouve que la lampe est la, meme une trame que l'on ne lit pas.
static void test_entendue(void) {
  demarrer(0, true);
  VERIFIE(!L.lampes[0].entendue && !L.lampes[1].entendue, "personne d'entendu au demarrage");
  const uint8_t alim[TELINK_TAILLE] = {0x86, 0, 0, 0, 0, 0, 0, 0x31, 0x4B, 0x0A};  // releve au banc
  lampes_trame_recue(&L, 0x0002, alim, T);
  VERIFIE(L.lampes[0].entendue && !L.lampes[0].connu, "entendue, mais pas d'etat lu");
  VERIFIE(!L.lampes[1].entendue, "l'autre lampe, non");
}

// L'endpoint d'une lampe vient d'etre cree : ce qu'il doit montrer part, meme inchange.
static void test_forcer_publication(void) {
  demarrer(0, true);
  recevoir(0x0004, true, 300);
  oublier_sorties();
  recevoir(0x0004, true, 300);
  VERIFIE(g_nb_pubs == 0, "inchange : rien de publie");
  lampes_forcer_publication(&L, 1);
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].lampe == 1 && g_pubs[0].connu && g_pubs[0].e.marche &&
              g_pubs[0].e.intensite == 300 && g_pubs[0].joignable,
          "republiee telle quelle");
  lampes_forcer_publication(&L, 7);  // hors de la liste : rien
  lampes_forcer_publication(&L, 2);  // juste apres la derniere lampe (n = 2)
  lampes_forcer_publication(&L, -1);
  VERIFIE(g_nb_pubs == 1, "lampes hors de la liste ignorees (7, n, -1)");
}

// Avance de ms en repondant aux relectures : la lampe k manque une relecture sur
// manque_une_sur[k] (0 : jamais ; 1 : toutes, elle se tait).
static int g_releves_vues;
static void avancer_en_repondant(uint32_t ms, const int manque_une_sur[2]) {
  const uint32_t fin = T + ms;
  while (T != fin) {
    T += 50;
    const int avant = compter(LAMPES_GROUPE, TELINK_CMD_ETAT);
    lampes_tic(&L, T);
    if (compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == avant) continue;
    g_releves_vues++;
    for (int k = 0; k < 2; k++) {
      const int m = manque_une_sur[k];
      if (m == 1 || (m > 1 && g_releves_vues % m == 0)) continue;
      recevoir(ADR[k], true, 500);
    }
    g_nb_envois = 0;  // dix minutes de relectures depasseraient le tableau
  }
}

static void test_alerte_relectures_manquees(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int moitie[2] = {0, 2};  // lampe 2 : une relecture sur deux sans reponse
  avancer_en_repondant(9 * 60000, moitie);
  VERIFIE(g_nb_alertes == 0, "rien avant dix minutes completes");
  avancer_en_repondant(60000 + 50, moitie);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].lampe == 1 && g_alertes[0].manque && g_alertes[0].pour_cent == 49,
          "lampe 2 : relectures manquees, 49 %% (tronque ; %d alertes)", g_nb_alertes);
  VERIFIE(lampes_part_repondue(&L, 0) == 100 && lampes_part_repondue(&L, 1) == 50, "parts sur 10 min");
  avancer_en_repondant(5 * 60000, moitie);
  VERIFIE(g_nb_alertes == 1, "pas de repetition tant qu'elle reste dessous");

  const int toutes[2] = {0, 0};
  avancer_en_repondant(11 * 60000, toutes);
  VERIFIE(g_nb_alertes == 2 && g_alertes[1].lampe == 1 && !g_alertes[1].manque && g_alertes[1].pour_cent >= 95,
          "lampe 2 revenue au-dessus de 95 %% (%d alertes)", g_nb_alertes);
  avancer_en_repondant(5 * 60000, toutes);
  VERIFIE(g_nb_alertes == 2, "pas de repetition au-dessus");
}

// Une relecture manquee sur vingt-cinq (96 %) : au-dessus du seuil, pas d'alerte ;
// une sur dix (90 %) : alerte.
static void test_alerte_au_seuil(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int une_sur_vingt_cinq[2] = {0, 25};
  avancer_en_repondant(10 * 60000 + 50, une_sur_vingt_cinq);
  VERIFIE(g_nb_alertes == 0, "96 %% : pas d'alerte");
  demarrer(0, true);
  g_releves_vues = 0;
  const int une_sur_dix[2] = {0, 10};
  avancer_en_repondant(10 * 60000 + 50, une_sur_dix);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].manque && g_alertes[0].pour_cent == 89, "90 %% : alerte, 89 %% (tronque)");
}

// 95 % pile (une sur vingt, la premiere relecture repondue) : pas d'alerte, le seuil est
// strict ; un peu dessous (une sur dix-huit, 94 %) : alerte.
static void test_alerte_a_95_pile(void) {
  demarrer(0, true);
  recevoir(ADR[0], true, 500);
  recevoir(ADR[1], true, 500);
  g_releves_vues = 0;
  const int une_sur_vingt[2] = {0, 20};
  avancer_en_repondant(15 * 60000, une_sur_vingt);
  VERIFIE(g_nb_alertes == 0, "95 %% pile : pas d'alerte (%d)", g_nb_alertes);
  demarrer(0, true);
  g_releves_vues = 0;
  const int une_sur_dix_huit[2] = {0, 18};
  avancer_en_repondant(10 * 60000 + 50, une_sur_dix_huit);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].manque && g_alertes[0].pour_cent == 94, "94 %% : alerte (%d)", g_nb_alertes);
}

// La relecture partie juste avant une coupure du Mesh n'a pas d'issue : rien n'est compte.
static void test_alerte_relecture_d_avant_la_coupure(void) {
  demarrer(0, true);  // la premiere relecture part ; la coupure vient avant la reponse
  lampes_mesh_pret(&L, false, T);
  lampes_mesh_pret(&L, true, T);
  avancer(50);  // relecture aussitot
  VERIFIE(lampes_part_repondue(&L, 0) == -1 && lampes_part_repondue(&L, 1) == -1,
          "la relecture d'avant la coupure n'est pas comptee");
}

// Apres une coupure du Mesh, la fenetre est presque vide : pas de verdict sur quelques
// relectures, seulement sur la moitie au moins de celles attendues en 10 min.
static void test_alerte_apres_coupure_du_mesh(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int toutes[2] = {0, 0};
  avancer_en_repondant(10 * 60000 + 50, toutes);
  VERIFIE(g_nb_alertes == 0, "fenetre pleine, tout repondu : rien");
  lampes_mesh_pret(&L, false, T);
  avancer_en_repondant(12 * 60000, toutes);  // rien ne part : les lampes deviennent muettes
  VERIFIE(lampes_part_repondue(&L, 1) == -1, "fenetre videe par la coupure");
  lampes_mesh_pret(&L, true, T);
  const int une_sur_dix[2] = {0, 10};
  avancer_en_repondant(4 * 60000, une_sur_dix);
  VERIFIE(g_nb_alertes == 0, "4 min apres le retour : echantillon trop petit, pas de verdict (%d)", g_nb_alertes);
  avancer_en_repondant(6 * 60000, une_sur_dix);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].lampe == 1 && g_alertes[0].manque,
          "echantillon suffisant : l'alerte vient (%d)", g_nb_alertes);
}

// Une lampe eteinte a son bouton puis rallumee : meme regle.
static void test_alerte_lampe_qui_revient(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int muette[2] = {0, 1};
  avancer_en_repondant(15 * 60000, muette);
  VERIFIE(!L.lampes[1].joignable && g_nb_alertes == 0, "lampe 2 muette, sans alerte de relectures");
  const int une_sur_dix[2] = {0, 10};
  avancer_en_repondant(4 * 60000, une_sur_dix);
  VERIFIE(L.lampes[1].joignable && g_nb_alertes == 0, "revenue depuis 4 min : pas de verdict (%d)", g_nb_alertes);
  avancer_en_repondant(6 * 60000, une_sur_dix);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].lampe == 1 && g_alertes[0].manque, "puis l'alerte (%d)", g_nb_alertes);
}

// La fenetre suit l'horloge de 32 bits a travers son debordement.
static void test_alerte_horloge_qui_deborde(void) {
  demarrer(0u - 5u * 60000u, true);
  g_releves_vues = 0;
  const int moitie[2] = {0, 2};
  avancer_en_repondant(5 * 60000 + 50, moitie);
  VERIFIE(L.fen_pleines == 5, "une tranche par minute, a travers le debordement (%u)", (unsigned)L.fen_pleines);
  avancer_en_repondant(4 * 60000 - 50, moitie);
  VERIFIE(g_nb_alertes == 0, "pas avant dix minutes, malgre le debordement");
  avancer_en_repondant(60000 + 50, moitie);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].manque, "dix minutes apres, a travers le debordement (%d)", g_nb_alertes);
}

// Relectures comptees dans la fenetre d'une lampe.
static uint32_t releves_comptes(int lampe) {
  uint32_t n = 0;
  for (unsigned t = 0; t < LAMPES_ALERTE_TRANCHES; t++) n += L.lampes[lampe].fen_releves[t];
  return n;
}

// Une lampe qui se tait apres avoir manque la moitie de ses reponses n'est pas concernee :
// au dixieme tour de fenetre elle est muette, la fenetre est pleine, et rien n'est signale.
static void test_alerte_pas_pour_une_lampe_devenue_muette(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int moitie[2] = {0, 2};
  avancer_en_repondant(9 * 60000 + 30000, moitie);
  const int muette[2] = {0, 1};
  avancer_en_repondant(30000 + 50, muette);
  VERIFIE(!L.lampes[1].joignable, "lampe 2 devenue muette");
  VERIFIE(g_nb_alertes == 0, "pas d'alerte de relectures pour une muette (%d)", g_nb_alertes);
}

// Une coupure breve du Mesh (les lampes restent joignables) ne compte aucune relecture,
// meme si la derniere relecture d'avant la coupure etait restee sans reponse.
static void test_alerte_coupure_breve_ne_compte_rien(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int toutes[2] = {0, 0};
  avancer_en_repondant(3 * 60000, toutes);
  avancer(2000);  // une relecture part, sans reponse
  const uint32_t avant = releves_comptes(1);
  lampes_mesh_pret(&L, false, T);
  avancer(3950);  // des tics de relecture sans Mesh, la lampe reste joignable
  VERIFIE(L.lampes[1].joignable, "lampe 2 encore joignable pendant la coupure");
  lampes_mesh_pret(&L, true, T);
  avancer(50);  // relecture aussitot
  VERIFIE(releves_comptes(1) == avant, "rien de compte pendant la coupure (%u -> %u)", (unsigned)avant,
          (unsigned)releves_comptes(1));
}

// Periode de 1 s : 600 relectures attendues sur 10 min, verdict a 300 au moins.
static void test_alerte_echantillon_a_une_seconde(void) {
  demarrer(0, true);
  lampes_regler_releve(&L, 1000);
  g_releves_vues = 0;
  const int toutes[2] = {0, 0};
  avancer_en_repondant(10 * 60000 + 50, toutes);
  lampes_mesh_pret(&L, false, T);
  avancer_en_repondant(12 * 60000, toutes);
  lampes_mesh_pret(&L, true, T);
  const int une_sur_dix[2] = {0, 10};
  avancer_en_repondant(4 * 60000, une_sur_dix);
  VERIFIE(g_nb_alertes == 0, "1 s, 4 min apres le retour (240 relectures sur 600) : pas de verdict (%d)",
          g_nb_alertes);
  avancer_en_repondant(2 * 60000, une_sur_dix);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].lampe == 1 && g_alertes[0].manque, "1 s, 6 min apres le retour : verdict (%d)",
          g_nb_alertes);
}

// Periode de 60 s : 10 relectures attendues sur 10 min, verdict des 5. La lampe 1 cette
// fois : chaque lampe est jugee, la premiere aussi.
static void test_alerte_echantillon_a_soixante_secondes(void) {
  demarrer(0, true);
  recevoir(ADR[0], true, 500);
  recevoir(ADR[1], true, 500);
  lampes_regler_releve(&L, 60000);
  g_releves_vues = 0;
  const int moitie[2] = {2, 0};
  avancer_en_repondant(10 * 60000 + 50, moitie);
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].lampe == 0 && g_alertes[0].manque,
          "60 s : lampe 1, la moitie manquee, alerte au dixieme tour (%d)", g_nb_alertes);
}

// Une lampe muette (« Pas de reponse ») n'est pas concernee : c'est une autre alerte.
static void test_alerte_pas_pour_une_muette(void) {
  demarrer(0, true);
  g_releves_vues = 0;
  const int muette[2] = {0, 1};
  avancer_en_repondant(12 * 60000, muette);
  VERIFIE(!L.lampes[1].joignable, "lampe 2 muette");
  VERIFIE(g_nb_alertes == 0, "aucune alerte de relectures pour elle");
}

static void test_alerter_peut_manquer(void) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, NULL, NULL};
  T = 0;
  lampes_init(&L, ADR, 2, &s, T);
  lampes_mesh_pret(&L, true, T);
  lampes_tic(&L, T);
  oublier_sorties();
  g_releves_vues = 0;
  const int moitie[2] = {0, 2};
  avancer_en_repondant(11 * 60000, moitie);
  VERIFIE(L.lampes[1].alerte, "l'alerte est notee, sans sortie pour la signaler");
}

int main(void) {
  test_conversion();
  test_demarrage_relit_aussitot();
  test_premier_etat_publie_doublons_ignores();
  test_ordre_confirme();
  test_niveau_puis_marche_en_une_salve();
  test_eteindre_avant_le_niveau();
  test_effet_d_arret_regroupe();
  test_trois_essais_puis_abandon();
  test_curseur_glisse_sans_empilement();
  test_etat_perime_ignore();
  test_valeur_egale_n_emet_pas();
  test_muette_apres_trois_releves();
  test_trame_non_lue_prouve_la_vie();
  test_mesh_pas_pret();
  test_mesh_perdu_pendant_un_ordre();
  test_mesh_pret_redit_sans_effet();
  test_ordre_console();
  test_horloge_qui_deborde();
  test_regler_releve();
  test_file_refusee();
  test_mesures_du_banc_c();
  test_delai_depuis_le_dernier_ordre();
  test_intensite_au_pour_cent();
  test_noire_montree_eteinte();
  test_allumer_une_noire();
  test_allumer_une_noire_avec_l_effet();
  test_allumer_une_noire_sans_memoire();
  test_allumer_eteinte_a_zero();
  test_molette_remonte_de_zero();
  test_abandon_d_un_allumage_de_noire();
  test_niveau_seul_sur_une_noire();
  test_on_sur_allumee_n_emet_pas();
  test_on_sur_lampe_jamais_lue();
  test_capacite();
  test_entendue();
  test_forcer_publication();
  test_alerte_relectures_manquees();
  test_alerte_au_seuil();
  test_alerte_a_95_pile();
  test_alerte_relecture_d_avant_la_coupure();
  test_alerte_apres_coupure_du_mesh();
  test_alerte_lampe_qui_revient();
  test_alerte_horloge_qui_deborde();
  test_alerte_pas_pour_une_lampe_devenue_muette();
  test_alerte_coupure_breve_ne_compte_rien();
  test_alerte_echantillon_a_une_seconde();
  test_alerte_echantillon_a_soixante_secondes();
  test_alerte_pas_pour_une_muette();
  test_alerter_peut_manquer();
  return bilan("lampes");
}
