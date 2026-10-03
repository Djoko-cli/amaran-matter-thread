// Console du pont (spec 7.5) : lampes, lampe, mesh (et mesh releve), matter,
// decommission, redemarre, taches. Les cles ne s'affichent jamais (7.7).
#include "console_pont.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_console.h"
#include "esp_timer.h"

#include "lampes.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "telink.h"
#include "texte.h"

static amaran_config_t *s_cfg;

static void imprimer_etat(const lampe_etat_t *e) {
  printf("%s %u,%u %%", e->marche ? "marche" : "arret", (unsigned)(e->intensite / 10), (unsigned)(e->intensite % 10));
}

static int cmd_lampes(int argc, char **argv) {
  (void)argc;
  (void)argv;
  static lampes_t l;  // copie : trop grosse pour la pile de la console
  tache_lampes_lire(&l);
  const uint32_t t = (uint32_t)(esp_timer_get_time() / 1000);
  for (int i = 0; i < l.n; i++) {
    const lampe_t *p = &l.lampes[i];
    printf("lampe %d : 0x%04x %s, %s\n", i + 1, p->adresse, s_cfg->lampes[i].adresse ? s_cfg->lampes[i].nom : "(absente)",
           p->joignable ? "joignable" : "PAS DE REPONSE");
    printf("  lue       : ");
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
      if (p->veut_intensite) printf("%u,%u %% ", (unsigned)(p->consigne.intensite / 10), (unsigned)(p->consigne.intensite % 10));
      printf("(essai %u sur %u)\n", (unsigned)p->essai, LAMPES_ESSAIS);
    }
    printf("  releves   : %" PRIu32 " repondue(s) sur %" PRIu32 "\n", p->releves_repondues, l.releves);
  }
  printf("ordres : %" PRIu32 " (confirmes %" PRIu32 ", abandonnes %" PRIu32 ")", l.ordres, l.confirmes, l.abandons);
  if (l.confirmes) {
    printf(" ; delai moyen %" PRIu32 " ms, max %" PRIu32 " ms, %" PRIu32 " au-dela d'1 s", l.delai_total_ms / l.confirmes,
           l.delai_max_ms, l.lents);
  }
  printf("\nrelecture toutes les %" PRIu32 " s, au groupe 0x%04x ; Bluetooth Mesh %s\n", l.periode_ms / 1000,
         LAMPES_GROUPE, l.mesh_pret ? "pret" : "PAS PRET");
  return 0;
}

static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > PONT_EMPLACEMENTS || !s_cfg->lampes[n - 1].adresse) {
    printf("erreur : lampe <1-%d> on|off|niveau <0-1000>|releve (lampe declaree ?)\n", PONT_EMPLACEMENTS);
    return 1;
  }
  const int i = (int)n - 1;
  const char *action = argv[2];
  if (!strcmp(action, "releve") && argc == 3) {
    uint8_t t[TELINK_TAILLE];
    telink_demande_etat(t);
    const esp_err_t err = mesh_envoyer(s_cfg->lampes[i].adresse, t, MESH_REPETITIONS_ETAT);
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
    printf("erreur : lampe <n> on|off|niveau <0-1000>|releve\n");
    return 1;
  }
  printf("ok ordre pour la lampe %d (suivi : 'lampes')\n", i + 1);
  return 0;
}

// `mesh` du pont : celle du composant mesh, plus la periode de relecture, et
// l'ecoute detaillee qui imprime aussi les etats des lampes.
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

static const char *const TACHES[] = {"lampes", "socle", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP",
                                     "ot_task", "console_repl"};

void console_pont_demarrer(amaran_config_t *cfg) {
  s_cfg = cfg;
  mesh_console_init(cfg, TACHES, sizeof(TACHES) / sizeof(TACHES[0]));
  esp_console_repl_t *repl = NULL;
  esp_console_repl_config_t conf = ESP_CONSOLE_REPL_CONFIG_DEFAULT();
  conf.prompt = "amaran>";
  conf.task_stack_size = 6144;  // `matter` et `mesh autotest` y tournent
  esp_console_dev_usb_serial_jtag_config_t usb = ESP_CONSOLE_DEV_USB_SERIAL_JTAG_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_console_new_repl_usb_serial_jtag(&usb, &conf, &repl));
  const esp_console_cmd_t cmds[] = {
      {.command = "lampes", .help = "etat des lampes : lu, consigne, joignabilite, releves, ordres", .func = cmd_lampes},
      {.command = "lampe", .help = "lampe <1-2> on|off|niveau <0-1000>|releve", .func = cmd_lampe},
      {.command = "mesh",
       .help = "etat ; mesh cles|lampe|iv|adresse|oublie|ecoute|balayage|autotest|releve ...",
       .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
      {.command = "decommission", .help = "retire toutes les fabriques Matter (cles gardees)", .func = cmd_decommission},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "led", .help = "led [test|stop] : motif du voyant ; test = chaque motif a tour de role", .func = socle_commande_led},
      {.command = "cause", .help = "pourquoi la carte a redemarre la derniere fois", .func = socle_commande_cause},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = mesh_console_taches},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
