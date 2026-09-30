// Commandes de console communes aux deux firmwares (ecoute et pont) : `mesh`
// (etat, reglages, autotest) et `taches` (marges de pile), plus l'impression des
// evenements du crochet. Spec 7.5 et 7.7 : les cles ne s'affichent jamais,
// seulement leurs empreintes.
#include "mesh_console.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "linenoise/linenoise.h"

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
  printf("ok lampe %" PRIu32 " 0x%04x %s (redemarrer pour l'appliquer)\n", n, l.adresse, l.nom);
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

int mesh_console_commande(int argc, char **argv) {
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
        s_cfg->iv = ev->iv;
        printf("[%lld ms] IV Index 0x%08" PRIx32 " adopte et sauve\n", ms, ev->iv);
      } else {
        printf("[%lld ms] IV Index 0x%08" PRIx32 " adopte, mais non sauve (NVS : %s)\n", ms, ev->iv,
               esp_err_to_name(err));
      }
      break;
    }
  }
}
