// Tests sur le Mac du coeur du pont (lampes). Lancer : sh tests/hote/lancer.sh
// Horloge simulee : chaque test fait avancer le temps par tics de 50 ms, comme
// la tache lampes du firmware.
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

static envoi_t g_envois[512];
static int g_nb_envois;
static publication_t g_pubs[128];
static int g_nb_pubs;
static signal_t g_sigs[64];
static int g_nb_sigs;
static bool g_refuser;

static bool f_envoyer(void *ctx, uint16_t dst, const uint8_t t[TELINK_TAILLE], uint8_t rep) {
  (void)ctx;
  if (g_refuser) return false;
  if (g_nb_envois < (int)(sizeof(g_envois) / sizeof(g_envois[0]))) {
    g_envois[g_nb_envois].dst = dst;
    memcpy(g_envois[g_nb_envois].t, t, TELINK_TAILLE);
    g_envois[g_nb_envois].rep = rep;
    g_nb_envois++;
  }
  return true;
}

static void f_publier(void *ctx, int lampe, const lampe_etat_t *e, bool joignable) {
  (void)ctx;
  publication_t *p = &g_pubs[g_nb_pubs++];
  p->lampe = lampe;
  p->connu = e != NULL;
  if (e) p->e = *e;
  p->joignable = joignable;
}

static void f_signaler(void *ctx, int lampe, lampes_signal_t s) {
  (void)ctx;
  g_sigs[g_nb_sigs].lampe = lampe;
  g_sigs[g_nb_sigs].s = s;
  g_nb_sigs++;
}

static void oublier_sorties(void) {
  g_nb_envois = g_nb_pubs = g_nb_sigs = 0;
  g_refuser = false;
}

// --- Aides

static const uint16_t ADR[2] = {0x0002, 0x0004};
static lampes_t L;
static uint32_t T;  // horloge simulee

static void demarrer(uint32_t t0, bool pret) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, NULL};
  T = t0;
  lampes_init(&L, ADR, 2, &s, T);
  if (pret) lampes_mesh_pret(&L, true, T);
  lampes_tic(&L, T);  // premiere relecture
  oublier_sorties();
}

static void avancer(uint32_t ms) {
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
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, NULL};
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
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 2, "relecture suivante 5 s plus tard");
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
  VERIFIE(g_nb_sigs == 0, "ni confirmation ni abandon");
}

static void test_muette_apres_trois_releves(void) {
  demarrer(0, true);  // relecture 1 a 0 ms, deja faite
  avancer(10000);     // relectures 2 et 3
  VERIFIE(g_nb_pubs == 0, "encore joignable a 10 s");
  avancer(5000);  // relecture 4 : trois relectures sans reponse
  VERIFIE(g_nb_pubs == 2 && !g_pubs[0].joignable && !g_pubs[1].joignable && !g_pubs[0].connu,
          "les deux lampes muettes a 15 s");
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
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_ABANDON, "ordre abandonne");
  lampes_mesh_pret(&L, true, T + 2000);
  oublier_sorties();
  lampes_tic(&L, T + 2000);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 1, "relecture aussitot au retour du Mesh");
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
  lampes_regler_releve(&L, 2000);
  avancer(5000);  // la periode en cours (5 s) s'acheve, puis 2 s
  avancer(2000);
  VERIFIE(compter(LAMPES_GROUPE, TELINK_CMD_ETAT) == 2, "nouvelle periode appliquee");
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
  avancer(5000);                 // relecture 2 : sans reponse
  avancer(5000);                 // relecture 3
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
  test_ordre_console();
  test_horloge_qui_deborde();
  test_regler_releve();
  test_file_refusee();
  test_mesures_du_banc_c();
  return bilan("lampes");
}
