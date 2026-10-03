// Commandes de console communes aux deux firmwares (ecoute et pont) : `mesh`
// (etat, reglages, balayage, autotest) et `taches` (marges de pile), plus
// l'impression des evenements du crochet. Spec 7.5 et 7.7 : les cles ne
// s'affichent jamais, seulement leurs empreintes.
#include "mesh_console.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "linenoise/linenoise.h"

#include "catalogue.h"
#include "telink.h"
#include "texte.h"

static amaran_config_t *s_cfg;
static const char *const *s_taches;
static size_t s_nb_taches;

void mesh_console_init(amaran_config_t *cfg, const char *const *taches, size_t nb_taches) {
  s_cfg = cfg;
  s_taches = taches;
  s_nb_taches = nb_taches;
}

void mesh_console_redemarrer(void) {
  printf("redemarrage\n");
  fflush(stdout);
  vTaskDelay(pdMS_TO_TICKS(200));
  esp_restart();
}

// Age en secondes d'un instant capte. L'appelant traite d'abord le cas "jamais" (instant a 0).
static long long age_s(int64_t quand_us) { return (long long)((esp_timer_get_time() - quand_us) / 1000000); }

// "balayage : 20 ms sur 40 ms (50 %)" : la part de temps radio que le Mesh
// passe a ecouter, arrondie au pour cent.
static void afficher_balayage(void) {
  uint16_t fenetre = 0, intervalle = 0;
  mesh_balayage(&fenetre, &intervalle);
  printf("balayage : %u ms sur %u ms (%u %%)\n", (unsigned)fenetre, (unsigned)intervalle,
         intervalle ? (unsigned)((100u * fenetre + intervalle / 2u) / intervalle) : 0u);
}

static void afficher_etat(void) {
  mesh_stats_t st;
  mesh_lire_stats(&st);
  printf("mesh pret : %s\n", mesh_pret() ? "oui" : "non");
  if (s_cfg->cles_presentes) {
    char en[9], ea[9];
    config_empreinte(s_cfg->netkey, en);
    config_empreinte(s_cfg->appkey, ea);
    printf("cles : reseau %s, application %s\n", en, ea);
  } else {
    printf("cles : absentes (outils/cles_amaran.py)\n");
  }
  printf("adresse 0x%04x, IV Index 0x%08" PRIx32 " (NVS 0x%08" PRIx32 "), sequence 0x%06" PRIx32
         " (plancher NVS 0x%06" PRIx32 ")\n",
         s_cfg->adresse, mesh_iv_courant(), s_cfg->iv, mesh_sequence(),
         mesh_pret() ? mesh_plancher() : s_cfg->plancher_seq);
  for (int i = 0; i < s_cfg->liste.n; i++) {
    const liste_lampe_t *l = &s_cfg->liste.lampes[i];
    if (st.derniere_reponse_us[i]) {
      printf("lampe %d : 0x%04x %s, derniere reponse il y a %lld s\n", i + 1, l->adresse, l->nom,
             age_s(st.derniere_reponse_us[i]));
    } else {
      printf("lampe %d : 0x%04x %s, derniere reponse : jamais\n", i + 1, l->adresse, l->nom);
    }
  }
  printf("messages vus %" PRIu32 " (NID reconnu %" PRIu32 ", inconnu %" PRIu32 ", NetMIC faux %" PRIu32
         "), acces dechiffres %" PRIu32 ", etats de lampes %" PRIu32 " (+%" PRIu32 " doublons ecartes)\n",
         st.annonces, st.nid_reconnu, st.nid_inconnu, st.netmic_faux, st.acces_dechiffres, st.etats_lampes,
         st.doublons);
  if (st.balises_notres) {
    printf("balises : notres %" PRIu32 " (derniere IV 0x%08" PRIx32 ", drapeaux 0x%02x, il y a %lld s), autres %" PRIu32
           ", fausses %" PRIu32 "\n",
           st.balises_notres, st.derniere_balise_iv, (unsigned)st.derniere_balise_flags, age_s(st.derniere_balise_us),
           st.balises_autres, st.balises_fausses);
  } else {
    printf("balises : notres 0 (aucune), autres %" PRIu32 ", fausses %" PRIu32 "\n", st.balises_autres,
           st.balises_fausses);
  }
  printf("emission : %" PRIu32 " messages, %" PRIu32 " refus ; evenements perdus %" PRIu32 "\n", st.emis,
         st.echecs_emission, st.file_pleine);
  afficher_balayage();
  if (st.netmic_faux > 0 && st.acces_dechiffres == 0) {
    printf("indice : NetMIC faux sans message dechiffre : IV Index faux ? (mesh iv cherche)\n");
  }
  if (st.nid_inconnu > 0 && st.nid_reconnu == 0) {
    printf("indice : aucun message de notre reseau : cles perimees, ou lampes hors de portee ?\n");
  }
}

static int mesh_cles(int argc, char **argv) {
  // La ligne tapee contient les cles, meme invalide ou si la NVS echoue : on
  // vide l'historique (fleche haut) avant tout le reste.
  linenoiseHistoryFree();
  uint8_t net[16], app[16];
  if (argc != 4 || !texte_hex_vers_octets(argv[2], net, 16) || !texte_hex_vers_octets(argv[3], app, 16)) {
    printf("erreur : mesh cles <reseau 32 hexa> <application 32 hexa>\n");
    return 1;
  }
  if (config_sauver_cles(net, app) != ESP_OK) {
    printf("erreur : ecriture NVS\n");
    return 1;
  }
  char en[9], ea[9];
  config_empreinte(net, en);
  config_empreinte(app, ea);
  printf("ok cles %s %s (redemarrer pour les appliquer)\n", en, ea);
  return 0;
}

// Chargement d'une liste (spec N lampes 10) : `mesh lampes <N>` ouvre une liste de N
// lampes, et chaque `mesh lampe <n> ...` en donne une. Elle n'est validee et sauvee
// qu'une fois les N donnees : tout ou rien. Effet au redemarrage.
static liste_t s_brouillon;
static uint8_t s_attendues;  // N de la liste en cours ; 0 : aucune
static uint32_t s_donnees;   // bit n-1 : lampe n donnee

static int mesh_lampes(int argc, char **argv) {
  uint32_t n = 0;
  if (argc != 3 || !texte_lire_nombre(argv[2], &n) || n > LISTE_CAPACITE) {
    printf("erreur : mesh lampes <0-%d>\n", LISTE_CAPACITE);
    return 1;
  }
  s_attendues = 0;
  memset(&s_brouillon, 0, sizeof(s_brouillon));
  if (n == 0) {
    if (config_sauver_liste(&s_brouillon) != ESP_OK) {
      printf("erreur : ecriture NVS\n");
      return 1;
    }
    printf("ok liste vide enregistree (redemarrer pour l'appliquer)\n");
    return 0;
  }
  s_brouillon.n = (uint8_t)n;
  s_attendues = (uint8_t)n;
  s_donnees = 0;
  printf("ok liste de %" PRIu32 " lampe(s) : envoyer mesh lampe 1 a %" PRIu32 "\n", n, n);
  return 0;
}

// mesh lampe <n> <adresse> <mac> <code> <nom...> : le code avant le nom, qu'un nombre
// peut terminer (« Lampe 2 »).
static int mesh_lampe(int argc, char **argv) {
  if (!s_attendues) {
    printf("erreur : mesh lampes <N> d'abord\n");
    return 1;
  }
  uint32_t n = 0, adresse = 0, code = 0;
  liste_lampe_t l;
  memset(&l, 0, sizeof(l));
  if (argc < 7 || !texte_lire_nombre(argv[2], &n) || n < 1 || n > s_attendues ||
      !texte_lire_nombre(argv[3], &adresse) || adresse > 0xFFFF || !texte_lire_mac(argv[4], l.mac) ||
      !texte_lire_nombre(argv[5], &code)) {
    printf("erreur : mesh lampe <1-%u> <adresse> <mac> <code> <nom>\n", (unsigned)s_attendues);
    return 1;
  }
  l.adresse = (uint16_t)adresse;
  l.code = code;
  size_t pos = 0;
  for (int i = 6; i < argc; i++) {
    const size_t m = strlen(argv[i]);
    const size_t espace = i > 6 ? 1 : 0;
    if (pos + espace + m >= LISTE_NOM_MAX) break;
    if (espace) l.nom[pos++] = ' ';
    memcpy(l.nom + pos, argv[i], m);
    pos += m;
  }
  l.nom[pos] = '\0';
  // Cette lampe seule d'abord (adresse, MAC, nom) : l'erreur vise la bonne ligne.
  liste_t une = {.n = 1};
  une.lampes[0] = l;
  int fautive = -1;
  const liste_erreur_t e = liste_valider(&une, &fautive);
  if (e != LISTE_OK) {
    printf("erreur : lampe %" PRIu32 " : %s\n", n, liste_erreur_texte(e));
    return 1;
  }
  s_brouillon.lampes[n - 1] = l;
  s_donnees |= 1u << (n - 1);
  // Une seule ligne par commande : `ok ...` ou `erreur ...` (outils/cles_amaran.py en
  // attend une). La derniere lampe donnee : la liste entiere (doublons), puis la NVS.
  const uint8_t total = s_attendues;
  const bool complete = s_donnees == (1u << total) - 1u;
  if (complete) {
    s_attendues = 0;
    const liste_erreur_t eliste = liste_valider(&s_brouillon, &fautive);
    if (eliste != LISTE_OK) {
      printf("erreur : liste refusee (lampe %d : %s)\n", fautive + 1, liste_erreur_texte(eliste));
      return 1;
    }
    if (config_sauver_liste(&s_brouillon) != ESP_OK) {
      printf("erreur : ecriture NVS\n");
      return 1;
    }
  }
  const catalogue_modele_t *m = catalogue_trouver(code);
  printf("ok lampe %" PRIu32 " 0x%04x modele %" PRIu32 " %s [%s] : %s", n, l.adresse, code,
         catalogue_connu(code) ? m->nom : "non catalogue", catalogue_capacites_texte(m->capacites), l.nom);
  if (complete) printf(" ; liste de %u lampe(s) enregistree (redemarrer pour l'appliquer)", (unsigned)total);
  printf("\n");
  return 0;
}

static int mesh_iv(int argc, char **argv) {
  if (argc >= 3 && !strcmp(argv[2], "cherche")) {
    uint32_t max = 0xFFFF, trouve = 0;
    if (argc > 4 || (argc == 4 && (!texte_lire_nombre(argv[3], &max) || max > 0xFFFFFF))) {
      printf("erreur : mesh iv cherche [max <= 0xFFFFFF]\n");
      return 1;
    }
    if (!mesh_pret()) {
      printf("erreur : Bluetooth Mesh pas pret\n");
      return 1;
    }
    printf("recherche de 0 a 0x%06" PRIx32 " (ne peut pas etre interrompue)...\n", max);
    const int r = mesh_iv_chercher(max, &trouve);
    if (r == 0) {
      printf("ok IV Index 0x%08" PRIx32 " (mesh iv 0x%08" PRIx32 " pour l'adopter)\n", trouve, trouve);
      return 0;
    }
    if (r == -1) {
      printf("erreur : pas de cle reseau\n");
      return 1;
    }
    printf("%s\n", r == 2 ? "erreur : aucun message de notre reseau au NetMIC faux ; attendre du trafic"
                          : "erreur : IV Index hors de la plage");
    return 1;
  }
  uint32_t iv = 0;
  if (argc != 3 || !texte_lire_nombre(argv[2], &iv)) {
    printf("erreur : mesh iv <valeur> | mesh iv cherche [max]\n");
    return 1;
  }
  if (config_sauver_iv(iv) != ESP_OK) {
    printf("erreur : ecriture NVS\n");
    return 1;
  }
  printf("ok iv 0x%08" PRIx32 "\n", iv);
  mesh_console_redemarrer();
  return 0;
}

static int mesh_adresse(int argc, char **argv) {
  uint32_t a = 0;
  if (argc == 3 && !strcmp(argv[2], "suivante")) {
    a = s_cfg->adresse >= AMARAN_ADRESSE_MAX ? AMARAN_ADRESSE_MIN : s_cfg->adresse + 1u;
  } else if (argc != 3 || !texte_lire_nombre(argv[2], &a) || a < AMARAN_ADRESSE_MIN || a > AMARAN_ADRESSE_MAX) {
    printf("erreur : mesh adresse <0x7F00-0x7F7F> | suivante\n");
    return 1;
  }
  if (a == s_cfg->adresse) {
    printf("ok adresse 0x%04" PRIx32 " inchangee\n", a);
    return 0;
  }
  if (config_sauver_adresse((uint16_t)a) != ESP_OK) {
    printf("erreur : ecriture NVS\n");
    return 1;
  }
  printf("ok adresse 0x%04" PRIx32 " (compteur remis a 0)\n", a);
  mesh_console_redemarrer();
  return 0;
}

// mesh balayage : affiche le reglage ; mesh balayage <fenetre_ms> <intervalle_ms> :
// le change a chaud (banc C : laisser de la radio a Thread).
static int mesh_balayage_cmd(int argc, char **argv) {
  if (argc == 2) {
    afficher_balayage();
    return 0;
  }
  uint32_t fenetre = 0, intervalle = 0;
  if (argc != 4 || !texte_lire_nombre(argv[2], &fenetre) || !texte_lire_nombre(argv[3], &intervalle)) {
    printf("erreur : mesh balayage [<fenetre_ms> <intervalle_ms>]\n");
    return 1;
  }
  // Une valeur au-dela de 16 bits ne doit pas se replier sur une valeur valide :
  // on la borne a 65535, et mesh_regler_balayage la refuse (elle depasse 1000).
  const esp_err_t err = mesh_regler_balayage(fenetre > UINT16_MAX ? UINT16_MAX : (uint16_t)fenetre,
                                             intervalle > UINT16_MAX ? UINT16_MAX : (uint16_t)intervalle);
  switch (err) {
    case ESP_OK:
      printf("ok ");
      afficher_balayage();
      return 0;
    case ESP_ERR_INVALID_ARG:
      printf("erreur : bornes : multiples de 5 ms, 5 <= fenetre <= intervalle <= 1000\n");
      return 1;
    default:
      printf("erreur : refus de la pile Bluetooth Mesh (%s)\n", esp_err_to_name(err));
      return 1;
  }
}

int mesh_console_commande(int argc, char **argv) {
  if (argc == 1) {
    afficher_etat();
    return 0;
  }
  const char *s = argv[1];
  if (!strcmp(s, "cles")) return mesh_cles(argc, argv);
  if (!strcmp(s, "lampes")) return mesh_lampes(argc, argv);
  if (!strcmp(s, "lampe")) return mesh_lampe(argc, argv);
  if (!strcmp(s, "iv")) return mesh_iv(argc, argv);
  if (!strcmp(s, "adresse")) return mesh_adresse(argc, argv);
  if (!strcmp(s, "balayage")) return mesh_balayage_cmd(argc, argv);
  if (!strcmp(s, "oublie") && argc == 2) {
    if (config_oublier_cles() != ESP_OK) {
      printf("erreur : ecriture NVS\n");
      return 1;
    }
    printf("ok cles oubliees (la liste des lampes reste ; mesh lampes 0 pour la vider)\n");
    mesh_console_redemarrer();
    return 0;
  }
  if (!strcmp(s, "ecoute") && argc == 3 && (!strcmp(argv[2], "on") || !strcmp(argv[2], "off"))) {
    mesh_ecoute_detaillee(!strcmp(argv[2], "on"));
    printf("ok ecoute detaillee %s\n", argv[2]);
    return 0;
  }
  if (!strcmp(s, "autotest") && argc == 2) return mesh_autotest() ? 1 : 0;
  printf("erreur : sous-commande inconnue (help)\n");
  return 1;
}

// Verification de banc : marge de pile de chaque tache (octets, sur ESP-IDF) et du tas.
int mesh_console_taches(int argc, char **argv) {
  (void)argc;
  (void)argv;
  for (size_t i = 0; i < s_nb_taches; i++) {
    const TaskHandle_t tache = xTaskGetHandle(s_taches[i]);
    if (tache) {
      printf("%s : pile libre au plus bas %u o\n", s_taches[i], (unsigned)uxTaskGetStackHighWaterMark(tache));
    } else {
      printf("%s : absente\n", s_taches[i]);
    }
  }
  printf("tas libre %" PRIu32 " o (au plus bas %" PRIu32 " o)\n", esp_get_free_heap_size(),
         esp_get_minimum_free_heap_size());
  return 0;
}

void mesh_console_evenement(const mesh_evenement_t *ev, bool etats) {
  char hex[2 * sizeof(ev->acces) + 1];
  const long long ms = (long long)(ev->quand_us / 1000);
  switch (ev->type) {
    case MESH_EV_ETAT_LAMPE: {
      if (!etats) break;
      telink_etat_t e;
      texte_octets_vers_hex(ev->acces + 1, TELINK_TAILLE, hex);
      if (telink_lire_etat(ev->acces + 1, &e)) {
        printf("[%lld ms] etat lampe %d (0x%04x -> 0x%04x) : %s, intensite %u (%u,%u %%), mode %s, trame %s\n", ms,
               ev->lampe + 1, ev->src, ev->dst, e.marche ? "marche" : "arret", (unsigned)e.intensite,
               (unsigned)(e.intensite / 10), (unsigned)(e.intensite % 10),
               e.mode == TELINK_MODE_CCT ? "CCT" : "HSI", hex);
      } else {
        printf("[%lld ms] trame lampe %d (0x%04x -> 0x%04x) non lue : %s\n", ms, ev->lampe + 1, ev->src, ev->dst,
               hex);
      }
      break;
    }
    case MESH_EV_ACCES:
      texte_octets_vers_hex(ev->acces, ev->len, hex);
      printf("[%lld ms] acces 0x%04x -> 0x%04x : %s\n", ms, ev->src, ev->dst, hex);
      break;
    case MESH_EV_BALISE:
      printf("[%lld ms] balise : IV Index 0x%08" PRIx32 ", drapeaux 0x%02x\n", ms, ev->iv, (unsigned)ev->flags);
      break;
    case MESH_EV_IV_CHANGE: {
      const esp_err_t err = config_sauver_iv(ev->iv);
      if (err == ESP_OK) {
        if (s_cfg) s_cfg->iv = ev->iv;
        printf("[%lld ms] IV Index 0x%08" PRIx32 " adopte et sauve\n", ms, ev->iv);
      } else {
        printf("[%lld ms] IV Index 0x%08" PRIx32 " adopte, mais non sauve (NVS : %s)\n", ms, ev->iv,
               esp_err_to_name(err));
      }
      break;
    }
  }
}
