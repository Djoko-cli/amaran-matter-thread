// Console de la reconnaissance (phase 0) : reglages, pilotage manuel des
// lampes et journal des etats captes. Procedures : docs/BANC.md.
#include "console_ecoute.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_console.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "linenoise/linenoise.h"

#include "mesh_amaran.h"
#include "telink.h"
#include "texte.h"

static amaran_config_t *s_cfg;

static void redemarrer(void) {
  printf("redemarrage\n");
  fflush(stdout);
  vTaskDelay(pdMS_TO_TICKS(200));
  esp_restart();
}

static long long age_s(int64_t quand_us) {
  return quand_us ? (long long)((esp_timer_get_time() - quand_us) / 1000000) : -1;
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
  for (int i = 0; i < AMARAN_LAMPES_MAX; i++) {
    const amaran_lampe_t *l = &s_cfg->lampes[i];
    if (!l->adresse) continue;
    printf("lampe %d : 0x%04x %s, derniere reponse il y a %lld s\n", i + 1, l->adresse, l->nom,
           age_s(st.derniere_reponse_us[i]));
  }
  printf("messages vus %" PRIu32 " (NID reconnu %" PRIu32 ", inconnu %" PRIu32 ", NetMIC faux %" PRIu32
         "), acces dechiffres %" PRIu32 ", etats de lampes %" PRIu32 "\n",
         st.annonces, st.nid_reconnu, st.nid_inconnu, st.netmic_faux, st.acces_dechiffres, st.etats_lampes);
  printf("balises : notres %" PRIu32 " (derniere IV 0x%08" PRIx32 ", drapeaux 0x%02x, il y a %lld s), autres %" PRIu32
         "\n",
         st.balises_notres, st.derniere_balise_iv, (unsigned)st.derniere_balise_flags, age_s(st.derniere_balise_us),
         st.balises_autres);
  printf("emission : %" PRIu32 " messages, %" PRIu32 " refus ; evenements perdus %" PRIu32 "\n", st.emis,
         st.echecs_emission, st.file_pleine);
  if (st.netmic_faux > 0 && st.acces_dechiffres == 0) {
    printf("indice : NetMIC faux sans message dechiffre : IV Index faux ? (mesh iv cherche)\n");
  }
  if (st.nid_inconnu > 0 && st.nid_reconnu == 0) {
    printf("indice : aucun message de notre reseau : cles perimees, ou lampes hors de portee ?\n");
  }
}

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

static int mesh_cles(int argc, char **argv) {
  uint8_t net[16], app[16];
  if (argc != 4 || !texte_hex_vers_octets(argv[2], net, 16) || !texte_hex_vers_octets(argv[3], app, 16)) {
    printf("erreur : mesh cles <reseau 32 hexa> <application 32 hexa>\n");
    return 1;
  }
  if (config_sauver_cles(net, app) != ESP_OK) {
    printf("erreur : ecriture NVS\n");
    return 1;
  }
  linenoiseHistoryFree();  // la ligne tapee contenait les cles
  char en[9], ea[9];
  config_empreinte(net, en);
  config_empreinte(app, ea);
  printf("ok cles %s %s (redemarrer pour les appliquer)\n", en, ea);
  return 0;
}

static int mesh_lampe(int argc, char **argv) {
  uint32_t n = 0, adresse = 0;
  amaran_lampe_t l;
  memset(&l, 0, sizeof(l));
  if (argc < 6 || !texte_lire_nombre(argv[2], &n) || n < 1 || n > AMARAN_LAMPES_MAX ||
      !texte_lire_nombre(argv[3], &adresse) || adresse == 0 || adresse > 0x7FFF || !texte_lire_mac(argv[4], l.mac)) {
    printf("erreur : mesh lampe <1-%d> <adresse> <mac> <nom>\n", AMARAN_LAMPES_MAX);
    return 1;
  }
  l.adresse = (uint16_t)adresse;
  size_t pos = 0;
  for (int i = 5; i < argc; i++) {
    const size_t m = strlen(argv[i]);
    const size_t espace = i > 5 ? 1 : 0;
    if (pos + espace + m >= AMARAN_NOM_MAX) break;
    if (espace) l.nom[pos++] = ' ';
    memcpy(l.nom + pos, argv[i], m);
    pos += m;
  }
  l.nom[pos] = '\0';
  if (config_sauver_lampe((uint8_t)(n - 1), &l) != ESP_OK) {
    printf("erreur : ecriture NVS\n");
    return 1;
  }
  printf("ok lampe %" PRIu32 " 0x%04x %s\n", n, l.adresse, l.nom);
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
  redemarrer();
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
  redemarrer();
  return 0;
}

static int cmd_mesh(int argc, char **argv) {
  if (argc == 1) {
    afficher_etat();
    return 0;
  }
  const char *s = argv[1];
  if (!strcmp(s, "cles")) return mesh_cles(argc, argv);
  if (!strcmp(s, "lampe")) return mesh_lampe(argc, argv);
  if (!strcmp(s, "iv")) return mesh_iv(argc, argv);
  if (!strcmp(s, "adresse")) return mesh_adresse(argc, argv);
  if (!strcmp(s, "oublie") && argc == 2) {
    if (config_oublier_cles() != ESP_OK) {
      printf("erreur : ecriture NVS\n");
      return 1;
    }
    printf("ok cles et lampes oubliees\n");
    redemarrer();
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

static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > AMARAN_LAMPES_MAX ||
      !s_cfg->lampes[n - 1].adresse) {
    printf("erreur : lampe <1-%d> releve|on|off|niveau <0-1000> (lampe declaree ?)\n", AMARAN_LAMPES_MAX);
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
  return envoyer(s_cfg->lampes[n - 1].adresse, t, repetitions);
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
  redemarrer();
  return 0;
}

// Verification de banc : marge de pile de chaque tache (octets, sur ESP-IDF) et du tas.
static int cmd_taches(int argc, char **argv) {
  (void)argc;
  (void)argv;
  static const char *const noms[] = {"amaran_tx", "journal", "nimble_host", "mesh_adv_task", "console_repl"};
  for (size_t i = 0; i < sizeof(noms) / sizeof(noms[0]); i++) {
    const TaskHandle_t tache = xTaskGetHandle(noms[i]);
    if (tache) {
      printf("%s : pile libre au plus bas %u o\n", noms[i], (unsigned)uxTaskGetStackHighWaterMark(tache));
    } else {
      printf("%s : absente\n", noms[i]);
    }
  }
  printf("tas libre %" PRIu32 " o (au plus bas %" PRIu32 " o)\n", esp_get_free_heap_size(),
         esp_get_minimum_free_heap_size());
  return 0;
}

static void tache_journal(void *arg) {
  (void)arg;
  QueueHandle_t file = mesh_file_evenements();
  mesh_evenement_t ev;
  char hex[2 * sizeof(ev.acces) + 1];
  for (;;) {
    if (xQueueReceive(file, &ev, portMAX_DELAY) != pdTRUE) continue;
    const long long ms = (long long)(ev.quand_us / 1000);
    switch (ev.type) {
      case MESH_EV_ETAT_LAMPE: {
        telink_etat_t e;
        texte_octets_vers_hex(ev.acces + 1, TELINK_TAILLE, hex);
        if (telink_lire_etat(ev.acces + 1, &e)) {
          printf("[%lld ms] etat lampe %d (0x%04x -> 0x%04x) : %s, intensite %u (%u,%u %%), mode %s, trame %s\n", ms,
                 ev.lampe + 1, ev.src, ev.dst, e.marche ? "marche" : "arret", (unsigned)e.intensite,
                 (unsigned)(e.intensite / 10), (unsigned)(e.intensite % 10),
                 e.mode == TELINK_MODE_CCT ? "CCT" : "HSI", hex);
        } else {
          printf("[%lld ms] trame lampe %d (0x%04x -> 0x%04x) non lue : %s\n", ms, ev.lampe + 1, ev.src, ev.dst,
                 hex);
        }
        break;
      }
      case MESH_EV_ACCES:
        texte_octets_vers_hex(ev.acces, ev.len, hex);
        printf("[%lld ms] acces 0x%04x -> 0x%04x : %s\n", ms, ev.src, ev.dst, hex);
        break;
      case MESH_EV_BALISE:
        printf("[%lld ms] balise : IV Index 0x%08" PRIx32 ", drapeaux 0x%02x\n", ms, ev.iv, (unsigned)ev.flags);
        break;
      case MESH_EV_IV_CHANGE:
        if (config_sauver_iv(ev.iv) == ESP_OK) s_cfg->iv = ev.iv;
        printf("[%lld ms] IV Index 0x%08" PRIx32 " adopte et sauve\n", ms, ev.iv);
        break;
    }
  }
}

void journal_demarrer(amaran_config_t *cfg) {
  s_cfg = cfg;
  xTaskCreate(tache_journal, "journal", 4096, NULL, 3, NULL);
}

void console_demarrer(amaran_config_t *cfg) {
  s_cfg = cfg;
  esp_console_repl_t *repl = NULL;
  esp_console_repl_config_t conf = ESP_CONSOLE_REPL_CONFIG_DEFAULT();
  conf.prompt = "amaran>";
  esp_console_dev_usb_serial_jtag_config_t usb = ESP_CONSOLE_DEV_USB_SERIAL_JTAG_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_console_new_repl_usb_serial_jtag(&usb, &conf, &repl));
  const esp_console_cmd_t cmds[] = {
      {.command = "mesh", .help = "etat ; mesh cles|lampe|iv|adresse|oublie|ecoute|autotest ...", .func = cmd_mesh},
      {.command = "lampe", .help = "lampe <1-2> releve|on|off|niveau <0-1000>", .func = cmd_lampe},
      {.command = "groupe", .help = "groupe releve : demande d'etat au groupe All (0xC000)", .func = cmd_groupe},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = cmd_taches},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
