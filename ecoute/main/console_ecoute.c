// Console de la reconnaissance (phase 0) : reglages, pilotage manuel des
// lampes et journal des etats captes. Procedures : docs/BANC.md.
#include "console_ecoute.h"

#include <stdio.h>
#include <string.h>

#include "esp_console.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "mesh_amaran.h"
#include "mesh_console.h"
#include "telink.h"
#include "texte.h"

static amaran_config_t *s_cfg;

static int envoyer(uint16_t dst, const uint8_t t[TELINK_TAILLE], uint8_t repetitions) {
  char hex[2 * TELINK_TAILLE + 1];
  texte_octets_vers_hex(t, TELINK_TAILLE, hex);
  const esp_err_t err = mesh_envoyer(dst, t, repetitions);
  if (err != ESP_OK) {
    printf("erreur : envoi impossible (%s)\n", esp_err_to_name(err));
    return 1;
  }
  printf("ok envoi 0x%04x x%u : %s%s\n", dst, (unsigned)repetitions, hex,
         mesh_pret() ? "" : " (en attente : mesh pas pret)");
  return 0;
}

static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > s_cfg->liste.n) {
    printf("erreur : lampe <1-%u> releve|on|off|niveau <0-1000> (lampe declaree ?)\n", (unsigned)s_cfg->liste.n);
    return 1;
  }
  uint8_t t[TELINK_TAILLE];
  uint8_t repetitions = MESH_REPETITIONS_ORDRE;
  const char *action = argv[2];
  if (!strcmp(action, "releve") && argc == 3) {
    telink_demande_etat(t);
    repetitions = MESH_REPETITIONS_ETAT;
  } else if (!strcmp(action, "on") && argc == 3) {
    telink_marche(true, t);
  } else if (!strcmp(action, "off") && argc == 3) {
    telink_marche(false, t);
  } else if (!strcmp(action, "niveau") && argc == 4) {
    uint32_t v = 0;
    if (!texte_lire_nombre(argv[3], &v) || v > TELINK_INTENSITE_MAX) {
      printf("erreur : niveau de 0 a 1000\n");
      return 1;
    }
    telink_intensite((uint16_t)v, t);
  } else {
    printf("erreur : lampe <n> releve|on|off|niveau <0-1000>\n");
    return 1;
  }
  return envoyer(s_cfg->liste.lampes[n - 1].adresse, t, repetitions);
}

static int cmd_groupe(int argc, char **argv) {
  if (argc != 2 || strcmp(argv[1], "releve")) {
    printf("erreur : groupe releve\n");
    return 1;
  }
  uint8_t t[TELINK_TAILLE];
  telink_demande_etat(t);
  return envoyer(MESH_GROUPE_TOUS, t, MESH_REPETITIONS_ETAT);
}

static int cmd_redemarre(int argc, char **argv) {
  (void)argc;
  (void)argv;
  mesh_console_redemarrer();
  return 0;
}

static void tache_journal(void *arg) {
  (void)arg;
  QueueHandle_t file = mesh_file_evenements();
  mesh_evenement_t ev;
  for (;;) {
    if (xQueueReceive(file, &ev, portMAX_DELAY) == pdTRUE) mesh_console_evenement(&ev, true);
  }
}

void journal_demarrer(amaran_config_t *cfg) {
  s_cfg = cfg;
  xTaskCreate(tache_journal, "journal", 4096, NULL, 3, NULL);
}

static const char *const TACHES[] = {"amaran_tx", "journal", "nimble_host", "mesh_adv_task", "console_repl"};

void console_demarrer(amaran_config_t *cfg) {
  s_cfg = cfg;
  mesh_console_init(cfg, TACHES, sizeof(TACHES) / sizeof(TACHES[0]));
  esp_console_repl_t *repl = NULL;
  esp_console_repl_config_t conf = ESP_CONSOLE_REPL_CONFIG_DEFAULT();
  conf.prompt = "amaran>";
  esp_console_dev_usb_serial_jtag_config_t usb = ESP_CONSOLE_DEV_USB_SERIAL_JTAG_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_console_new_repl_usb_serial_jtag(&usb, &conf, &repl));
  const esp_console_cmd_t cmds[] = {
      {.command = "mesh",
       .help = "etat ; mesh cles|lampes|lampe|iv|adresse|oublie|ecoute|balayage|autotest ...",
       .func = mesh_console_commande},
      {.command = "lampe", .help = "lampe <n> releve|on|off|niveau <0-1000>", .func = cmd_lampe},
      {.command = "groupe", .help = "groupe releve : demande d'etat au groupe All (0xC000)", .func = cmd_groupe},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = mesh_console_taches},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
