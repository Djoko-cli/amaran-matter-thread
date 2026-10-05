// Console du pont (spec 7.5 ; spec N lampes 10) : lampes, lampe, mesh (et mesh
// releve, mesh lampe <n> masquer|afficher), matter, decommission, redemarre,
// taches, json. Les cles ne s'affichent jamais (7.7).
//
// La tache de la console est la notre, et non la REPL d'ESP-IDF : linenoise fait
// toujours l'echo de ce qu'il lit, et le mode machine du protocole JSON
// (json_pont.h) lit l'USB sans echo ni invite. En mode texte, linenoise lit la
// ligne ; dans les deux modes, json_pont_executer l'execute.
#include "console_pont.h"

#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "driver/usb_serial_jtag.h"
#include "driver/usb_serial_jtag_vfs.h"
#include "esp_console.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "linenoise/linenoise.h"

#include "catalogue.h"
#include "json_pont.h"
#include "lampes.h"
#include "liste.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "telink.h"
#include "texte.h"

#define INVITE "amaran> "
#define LIGNE_MAX 256  // linenoise : au-dela, la ligne est coupee ; 128 a 255 sont refusees (JSON_PONT_CMD_MAX)

static amaran_config_t *s_cfg;
// Copies : trop grosses pour la pile de la console. Une commande a la fois.
static lampes_t s_l;
static liste_t s_liste;

static void imprimer_etat(const lampe_etat_t *e) {
  printf("%s %u,%u %%", e->marche ? "marche" : "arret", (unsigned)(e->intensite / 10), (unsigned)(e->intensite % 10));
}

// "EP2", "jamais vue" ou "masquee" : la lampe dans Maison.
static void imprimer_maison(int i) {
  const uint16_t ep = pont_endpoint(i);
  if (ep) {
    printf("EP%u", (unsigned)ep);
  } else if (s_liste.lampes[i].drapeaux & LISTE_MASQUEE) {
    printf("masquee");
  } else if (!(s_liste.lampes[i].drapeaux & LISTE_VUE)) {
    printf("jamais vue");
  } else {
    printf("hors de Maison");  // vue, mais endpoint non cree (journal de demarrage)
  }
}

// Une ligne par lampe, puis les ordres et la relecture.
static int cmd_lampes(int argc, char **argv) {
  (void)argc;
  (void)argv;
  tache_lampes_lire(&s_l);
  tache_lampes_lire_liste(&s_liste);
  for (int i = 0; i < s_l.n; i++) {
    const lampe_t *p = &s_l.lampes[i];
    printf("lampe %d : %s [", i + 1, s_liste.lampes[i].nom);
    imprimer_maison(i);
    printf("] ");
    if (p->connu) {
      imprimer_etat(&p->lu);
      if (p->lu.marche && p->lu.intensite == 0) printf(" (noire)");
    } else {
      printf("lue jamais");
    }
    printf(", %s, relectures %" PRIu32 "/%" PRIu32, p->joignable ? "joignable" : "PAS DE REPONSE", p->releves_repondues,
           s_l.releves);
    if (p->alerte) printf(" !! manquees");
    printf("\n");
  }
  if (s_l.n == 0) printf("aucune lampe (outils/cles_amaran.py)\n");
  printf("ordres : %" PRIu32 " (confirmes %" PRIu32 ", abandonnes %" PRIu32 ")", s_l.ordres, s_l.confirmes,
         s_l.abandons);
  if (s_l.confirmes) {
    printf(" ; delai moyen %" PRIu32 " ms, max %" PRIu32 " ms, %" PRIu32 " au-dela d'1 s",
           s_l.delai_total_ms / s_l.confirmes, s_l.delai_max_ms, s_l.lents);
  }
  printf("\nrelecture toutes les %" PRIu32 " s, au groupe 0x%04x ; Bluetooth Mesh %s\n", s_l.periode_ms / 1000,
         LAMPES_GROUPE, s_l.mesh_pret ? "pret" : "PAS PRET");
  return 0;
}

// `lampe <n>` : le detail d'une lampe.
static void detail(int i) {
  const lampe_t *p = &s_l.lampes[i];
  const liste_lampe_t *a = &s_liste.lampes[i];
  const catalogue_modele_t *m = catalogue_trouver(a->code);
  const uint32_t t = (uint32_t)(esp_timer_get_time() / 1000);
  printf("lampe %d : %s\n", i + 1, a->nom);
  printf("  adresse   : 0x%04x, MAC %02X:%02X:%02X:%02X:%02X:%02X\n", a->adresse, a->mac[0], a->mac[1], a->mac[2],
         a->mac[3], a->mac[4], a->mac[5]);
  printf("  modele    : %" PRIu32 " %s (%s)\n", a->code, catalogue_connu(a->code) ? m->nom : "non catalogue",
         catalogue_capacites_texte(m->capacites));
  printf("  Maison    : ");
  imprimer_maison(i);
  if (a->endpoint && !pont_endpoint(i)) printf(" (garde EP%u)", (unsigned)a->endpoint);
  printf("\n  lue       : ");
  if (p->connu) {
    imprimer_etat(&p->lu);
    if (p->lu.marche && p->lu.intensite == 0) printf(" (noire : eteinte pour Maison)");
    printf(" (il y a %" PRIu32 " s)\n", (t - p->reponse_ms) / 1000);
  } else {
    printf("jamais\n");
  }
  printf("  consigne  : ");
  if (p->phase == LAMPE_REPOS) {
    printf("aucune en cours\n");
  } else {
    if (p->veut_marche) printf("%s ", p->consigne.marche ? "marche" : "arret");
    if (p->veut_intensite) {
      printf("%u,%u %% ", (unsigned)(p->consigne.intensite / 10), (unsigned)(p->consigne.intensite % 10));
    }
    printf("(essai %u sur %u)\n", (unsigned)p->essai, LAMPES_ESSAIS);
  }
  printf("  releves   : %" PRIu32 " repondue(s) sur %" PRIu32, p->releves_repondues, s_l.releves);
  const int part = lampes_part_repondue(&s_l, i);
  if (part >= 0) printf(" ; sur 10 min : %d %%%s", part, p->alerte ? " (relectures manquees)" : "");
  printf("\n");
}

static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 2 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > s_cfg->liste.n) {
    printf("erreur : lampe <1-%u> [on|off|niveau <0-1000>|releve] (lampe declaree ?)\n", (unsigned)s_cfg->liste.n);
    return 1;
  }
  const int i = (int)n - 1;
  if (argc == 2) {
    tache_lampes_lire(&s_l);
    tache_lampes_lire_liste(&s_liste);
    detail(i);
    return 0;
  }
  const char *action = argv[2];
  if (!strcmp(action, "releve") && argc == 3) {
    uint8_t t[TELINK_TAILLE];
    telink_demande_etat(t);
    const esp_err_t err = mesh_envoyer(s_cfg->liste.lampes[i].adresse, t, MESH_REPETITIONS_ETAT);
    printf(err == ESP_OK ? "ok demande d'etat a la lampe %d\n" : "erreur : envoi impossible (lampe %d)\n", i + 1);
    return err == ESP_OK ? 0 : 1;
  }
  bool marche = false;
  uint32_t v = 0;
  if ((!strcmp(action, "on") || !strcmp(action, "off")) && argc == 3) {
    marche = !strcmp(action, "on");
    tache_lampes_ordre(i, &marche, NULL, false);
  } else if (!strcmp(action, "niveau") && argc == 4 && texte_lire_nombre(argv[3], &v) && v <= TELINK_INTENSITE_MAX) {
    const uint16_t intensite = (uint16_t)v;
    tache_lampes_ordre(i, NULL, &intensite, false);
  } else {
    printf("erreur : lampe <n> [on|off|niveau <0-1000>|releve]\n");
    return 1;
  }
  printf("ok ordre pour la lampe %d (suivi : 'lampes')\n", i + 1);
  return 0;
}

// mesh lampe <n> masquer|afficher : retirer la lampe de Maison, ou l'y remettre
// (meme jamais vue : banc de capacite). Effet immediat, garde en NVS.
static int mesh_exposition(int argc, char **argv) {
  uint32_t n = 0;
  const bool afficher = !strcmp(argv[3], "afficher");
  if (!texte_lire_nombre(argv[2], &n) || n < 1 || n > s_cfg->liste.n) {
    printf("erreur : mesh lampe <1-%u> masquer|afficher\n", (unsigned)s_cfg->liste.n);
    return 1;
  }
  const esp_err_t err = tache_lampes_exposition((int)n - 1, afficher);
  if (err == ESP_ERR_NOT_FOUND) {
    printf("erreur : lampe %" PRIu32 " absente de la liste chargee depuis le demarrage : redemarrer\n", n);
    return 1;
  }
  if (err != ESP_OK) {
    printf("erreur : %s (%s)\n", afficher ? "afficher" : "masquer", esp_err_to_name(err));
    return 1;
  }
  if (afficher) {
    printf("ok lampe %" PRIu32 " dans Maison (EP%u)\n", n, (unsigned)pont_endpoint((int)n - 1));
  } else {
    printf("ok lampe %" PRIu32 " retiree de Maison (mesh lampe %" PRIu32 " afficher pour la remettre)\n", n, n);
  }
  return 0;
}

// `mesh` du pont : celle du composant mesh, plus la periode de relecture,
// l'exposition d'une lampe, et l'ecoute detaillee qui imprime aussi les etats.
static int cmd_mesh(int argc, char **argv) {
  if (argc >= 2 && !strcmp(argv[1], "releve")) {
    uint32_t s = 0;
    if (argc != 3 || !texte_lire_nombre(argv[2], &s) || s < LAMPES_RELEVE_MIN_MS / 1000 ||
        s > LAMPES_RELEVE_MAX_MS / 1000) {
      printf("erreur : mesh releve <%u-%u s>\n", LAMPES_RELEVE_MIN_MS / 1000, LAMPES_RELEVE_MAX_MS / 1000);
      return 1;
    }
    if (config_sauver_releve(s * 1000) != ESP_OK) {
      printf("erreur : ecriture NVS\n");
      return 1;
    }
    s_cfg->releve_ms = s * 1000;
    tache_lampes_regler_releve(s * 1000);
    printf("ok relecture toutes les %" PRIu32 " s\n", s);
    return 0;
  }
  if (argc == 4 && !strcmp(argv[1], "lampe") && (!strcmp(argv[3], "masquer") || !strcmp(argv[3], "afficher"))) {
    return mesh_exposition(argc, argv);
  }
  if (argc == 3 && !strcmp(argv[1], "ecoute") && (!strcmp(argv[2], "on") || !strcmp(argv[2], "off"))) {
    const bool oui = !strcmp(argv[2], "on");
    mesh_ecoute_detaillee(oui);
    tache_lampes_ecoute(oui);
    printf("ok ecoute detaillee %s\n", argv[2]);
    return 0;
  }
  return mesh_console_commande(argc, argv);
}

static int cmd_matter(int argc, char **argv) {
  (void)argc;
  (void)argv;
  pont_afficher();
  return 0;
}

static int cmd_decommission(int argc, char **argv) {
  (void)argv;
  if (argc != 1) {  // `decommission ?` ne doit pas desappairer
    printf("erreur : decommission ne prend pas d'argument\n");
    return 1;
  }
  printf("Retrait de toutes les fabriques Matter, puis redemarrage (cles et lampes gardees)...\n");
  pont_desappairer();
  return 0;
}

static int cmd_redemarre(int argc, char **argv) {
  (void)argc;
  (void)argv;
  mesh_console_redemarrer();
  return 0;
}

const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES] = {
    "lampes", "socle", "json", "console", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP", "ot_task"};

static void tache_console(void *arg) {
  (void)arg;
  setvbuf(stdin, NULL, _IONBF, 0);  // rien ne reste dans un tampon de stdin au passage en mode machine
  printf("\nConsole du pont amaran : 'help' pour les commandes.\n");
  for (;;) {
    if (json_pont_machine()) {
      json_pont_lire();
      continue;
    }
    char *ligne = linenoise(INVITE);
    if (!ligne) continue;  // ligne vide
    linenoiseHistoryAdd(ligne);
    json_pont_executer(ligne, strlen(ligne) > JSON_PONT_CMD_MAX);
    linenoiseFree(ligne);
  }
}

void console_pont_demarrer(amaran_config_t *cfg) {
  s_cfg = cfg;
  mesh_console_init(cfg, CONSOLE_PONT_TACHES, CONSOLE_PONT_NB_TACHES);
  // Comme esp_console_new_repl_usb_serial_jtag (ESP-IDF 5.5.4), avec un tampon
  // d'emission de 4 Ko : une ligne machine fait jusqu'a 1 Ko (docs/PROTOCOLE-JSON.md 2.3).
  usb_serial_jtag_vfs_set_rx_line_endings(ESP_LINE_ENDINGS_CR);
  usb_serial_jtag_vfs_set_tx_line_endings(ESP_LINE_ENDINGS_CRLF);
  fcntl(fileno(stdout), F_SETFL, 0);
  fcntl(fileno(stdin), F_SETFL, 0);
  usb_serial_jtag_driver_config_t usb = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
  usb.tx_buffer_size = 4096;
  ESP_ERROR_CHECK(usb_serial_jtag_driver_install(&usb));
  esp_console_config_t conf = ESP_CONSOLE_CONFIG_DEFAULT();
  conf.max_cmdline_length = LIGNE_MAX;
  ESP_ERROR_CHECK(esp_console_init(&conf));
  usb_serial_jtag_vfs_use_driver();
  linenoiseSetMultiLine(1);
  linenoiseHistorySetMaxLen(20);
  linenoiseSetMaxLineLen(LIGNE_MAX);
  linenoiseAllowEmpty(false);
  // Toujours en mode simple : l'app partage cette console, et en mode evolue chaque linenoise()
  // ecrit ESC[6n puis lit stdin jusqu'a la reponse : la ligne de l'app serait prise pour elle.
  linenoiseSetDumbMode(1);
  const esp_console_cmd_t cmds[] = {
      {.command = "lampes", .help = "une ligne par lampe : Maison, etat lu, joignabilite, relectures ; ordres",
       .func = cmd_lampes},
      {.command = "lampe", .help = "lampe <n> : detail ; lampe <n> on|off|niveau <0-1000>|releve", .func = cmd_lampe},
      {.command = "mesh",
       .help = "etat ; mesh cles|lampes|lampe|iv|adresse|oublie|ecoute|balayage|autotest|releve ... ; "
               "mesh lampe <n> masquer|afficher",
       .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
      {.command = "decommission", .help = "retire toutes les fabriques Matter (cles gardees)", .func = cmd_decommission},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "led", .help = "led [test|stop] : motif du voyant ; test = chaque motif a tour de role", .func = socle_commande_led},
      {.command = "cause", .help = "pourquoi la carte a redemarre la derniere fois", .func = socle_commande_cause},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = mesh_console_taches},
      {.command = "json",
       .help = "mode machine de l'app (docs/PROTOCOLE-JSON.md) : json [1 [bail <s>]|0|etat|hello|ping|"
               "periode|lampes|compteurs|reseau <ms>|log 0|1]",
       .func = json_pont_commande},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  // 6 Ko : `matter` et `mesh autotest` y tournent.
  if (xTaskCreate(tache_console, "console", 6144, NULL, 2, NULL) != pdPASS) printf("!! console non demarree\n");
}
