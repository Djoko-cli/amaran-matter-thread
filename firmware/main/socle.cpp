// Socle repris du pont Halo (spec 7.4, 7.6) : voyant WS2812 (IO8) et bouton
// BOOT (IO9). La logique (components/socle, testee sur le Mac) est celle du
// Halo, commit 3f82f76 ; ici, la carte en ESP-IDF, portee de la moitie Arduino
// de boot_button.cpp et status_led.cpp du Halo.
#include "socle.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "esp_system.h"
#include "esp_task_wdt.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "boot_button.h"
#include "pont_matter.h"
#include "status_led.h"
#include "tache_lampes.h"
#include "ws2812.h"

#define GPIO_VOYANT 8
#define GPIO_BOUTON GPIO_NUM_9

using namespace bootbtn;

// L'eclat blanc doit etre fini, et la LED ecrite au noir, avant le reset : la
// WS2812 garde sa couleur a travers un reset.
static_assert(kRebootDelayMs >= statusled::kRebootFlashMs + 50, "reset avant la fin de l'eclat blanc");

static constexpr uint32_t kGardeMaxMs = 1000;        // derniere garde : au-dela, action abandonnee
static constexpr uint32_t kArretHautMs = 50;         // garde de esp_restart() : broche haute de suite
static constexpr uint32_t kDesappairageMs = 10000;   // desappairage sans redemarrage : on redemarre
static constexpr uint32_t kReseauMs = 200;           // etat Matter et Thread relu toutes les 200 ms

static statusled::Logic s_led;  // touche par la seule tache "socle"
static Machine s_bouton;
static volatile bool s_desappairage, s_redemarrage, s_panne_mesh;
static uint32_t s_desappairage_ms;
// Commande `led` (tache de la console) : des demandes, que la tache "socle"
// applique, et ce qu'elle affiche, qu'elle publie (motif, couleur 0xRRGGBB).
static volatile bool s_demande_test, s_demande_arret, s_en_test;
static volatile statusled::Pattern s_motif;
static volatile uint32_t s_couleur;

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static bool bouton_bas(void) { return gpio_get_level(GPIO_BOUTON) == 0; }

// --- Bouton BOOT

// Derniere garde juste avant un reset : broche relue haute sans interruption
// pendant kSettleMs. Faux si le bouton est rappuye et tenu : mieux vaut
// abandonner que redemarrer broche basse (mode telechargement).
static bool broche_stable(void) {
  const uint32_t t0 = maintenant_ms();
  uint32_t haute_depuis = t0;
  for (;;) {
    const uint32_t t = maintenant_ms();
    if (bouton_bas()) {
      haute_depuis = t;
    } else if (t - haute_depuis >= kSettleMs) {
      return true;
    }
    if (t - t0 >= kGardeMaxMs) return false;
    vTaskDelay(1);
  }
}

// Garde de TOUS les resets logiciels (bouton, `redemarre`, `decommission`, et
// la fin du desappairage par la tache CHIP, bouton libre entre-temps) : pas de
// reset tant qu'IO9 n'a pas ete relue haute kArretHautMs de suite. Enregistree
// avant Matter, elle passe en dernier. Sans borne : un bouton coince garde la
// carte dans le firmware (le relacher la redemarre) au lieu du mode telechargement.
static void attendre_bouton_haut(void) {
  s_redemarrage = true;
  if (xPortInIsrContext() || xTaskGetSchedulerState() != taskSCHEDULER_RUNNING) return;
  const bool chien = esp_task_wdt_status(NULL) == ESP_OK;
  bool dit = false;
  int64_t haute_depuis = esp_timer_get_time();
  for (;;) {
    const int64_t t = esp_timer_get_time();
    if (bouton_bas()) {
      haute_depuis = t;
      if (!dit) {
        dit = true;
        printf("[bouton] tenu pendant un redemarrage : reset au relachement (IO9, broche de strapping)\n");
      }
    } else if (t - haute_depuis >= (int64_t)kArretHautMs * 1000) {
      return;
    }
    if (chien) esp_task_wdt_reset();
    vTaskDelay(1);
  }
}

static Phase phase_bouton(void) { return s_desappairage ? Phase::Unpair : s_bouton.phase(); }

static void bouton_relever(uint32_t t) {
  if (s_desappairage) {
    // La tache CHIP efface puis redemarre : bouton inerte. Filet si rien ne
    // redemarre : esp_matter::factory_reset() ne dit pas son echec.
    if (s_redemarrage || t - s_desappairage_ms < kDesappairageMs) return;
    printf("[bouton] toujours en marche %" PRIu32 " s apres le desappairage : redemarrage\n", kDesappairageMs / 1000);
    if (broche_stable()) esp_restart();
    s_desappairage_ms = maintenant_ms();
    return;
  }
  const Event e = s_bouton.update(bouton_bas(), t);
  const uint32_t tenu = s_bouton.lastPressMs();
  switch (e) {
    case Event::None:
      return;
    case Event::Armed:
      printf("[bouton] tenu 8 s : relacher pour desappairer (retrait de Matter)\n");
      return;
    case Event::Cancelled:
      printf("[bouton] appui de %" PRIu32 " ms (2 a 8 s) : annule, rien fait\n", tenu);
      return;
    case Event::Unsure:
      printf("[bouton] appui de %" PRIu32 " ms ignore : releves interrompus %" PRIu32 " ms, duree incertaine\n", tenu,
             s_bouton.lastGapMs());
      return;
    case Event::Dropped:
      printf("[bouton] nouvel appui : action en attente abandonnee\n");
      return;
    case Event::BootReleased:
      printf("[bouton] relache : il etait tenu au demarrage, ignore\n");
      return;
    case Event::Reboot:
      printf("[bouton] appui court (%" PRIu32 " ms) : redemarrage\n", tenu);
      if (!broche_stable()) break;
      esp_restart();
      return;
    case Event::Unpair:
      printf("[bouton] appui long (%" PRIu32 " ms) : retrait de toutes les fabriques Matter, puis redemarrage\n", tenu);
      if (!broche_stable()) break;
      s_desappairage = true;
      s_desappairage_ms = maintenant_ms();
      pont_desappairer();
      return;
  }
  // Rappuye pendant la derniere garde : pas de reset broche basse.
  printf("[bouton] rappuye juste avant le reset : action annulee\n");
  s_bouton.begin(bouton_bas(), maintenant_ms());
}

// --- Voyant

static void voyant_relever(uint32_t t) {
  static bool premier = true, affiche_ok = false;
  static uint32_t reseau_ms, confirmes, abandons;
  static statusled::Rgb affiche;
  if (s_demande_test) {
    s_demande_test = false;
    s_led.startTest(t);
  }
  if (s_demande_arret) {
    s_demande_arret = false;
    s_led.stopTest();
  }
  if (premier || t - reseau_ms >= kReseauMs) {
    reseau_ms = t;
    s_led.setNet(!pont_appaire()          ? statusled::Net::Unpaired
                 : !pont_thread_attache() ? statusled::Net::Offline
                                          : statusled::Net::Online,
                 t);
  }
  s_led.setIdentify(pont_identifie(), t);
  // Rouge fixe seulement une fois appaire : avant, le bleu (mettre en service) prime.
  s_led.setFault(s_panne_mesh && pont_appaire(), t);
  s_led.setButton(statusled::buttonFor(phase_bouton()), t);
  // Les producteurs ne connaissent pas la LED : elle suit leurs compteurs.
  const uint32_t c = tache_lampes_confirmes(), a = tache_lampes_abandons();
  if (premier) {
    confirmes = c;
    abandons = a;
  }
  if (c != confirmes) {
    confirmes = c;
    s_led.delivered(t);
  }
  if (a != abandons) {
    abandons = a;
    s_led.unreachable(t);
  }
  premier = false;
  const statusled::Frame f = s_led.frame(t);
  s_motif = f.p;
  s_couleur = (uint32_t)f.c.r << 16 | (uint32_t)f.c.g << 8 | f.c.b;
  s_en_test = s_led.testing();
  if (!affiche_ok || f.c != affiche) {  // n'ecrire que les changements
    if (ws2812_ecrire(f.c.r, f.c.g, f.c.b) == ESP_OK) {
      affiche = f.c;
      affiche_ok = true;
    }
  }
}

static void tache(void *arg) {
  (void)arg;
  s_bouton.begin(bouton_bas(), maintenant_ms());  // tenu au demarrage : ignore jusqu'au relachement
  for (;;) {
    const uint32_t t = maintenant_ms();
    bouton_relever(t);  // d'abord le bouton, puis la LED (ordre du Halo)
    voyant_relever(t);
    vTaskDelay(1);  // 1 ms (CONFIG_FREERTOS_HZ=1000)
  }
}

// --- API

esp_err_t socle_demarrer(void) {
  const gpio_config_t bouton = {
      .pin_bit_mask = 1ULL << GPIO_BOUTON,
      .mode = GPIO_MODE_INPUT,
      .pull_up_en = GPIO_PULLUP_ENABLE,
      .pull_down_en = GPIO_PULLDOWN_DISABLE,
      .intr_type = GPIO_INTR_DISABLE,
  };
  esp_err_t err = gpio_config(&bouton);
  if (err != ESP_OK) return err;
  // Avant Matter : IDF appelle les gestionnaires d'arret du dernier enregistre au
  // premier, celui-ci passe donc juste avant le reset. Cinq places seulement.
  err = esp_register_shutdown_handler(attendre_bouton_haut);
  if (err != ESP_OK) {
    printf("!! bouton BOOT : garde du reset non enregistree (%s) ; ne pas tenir BOOT pendant un redemarrage\n",
           esp_err_to_name(err));
  }
  err = ws2812_demarrer(GPIO_VOYANT);
  if (err != ESP_OK) printf("!! voyant WS2812 : %s\n", esp_err_to_name(err));
  return xTaskCreate(tache, "socle", 3072, NULL, 3, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}

void socle_panne_mesh(bool oui) { s_panne_mesh = oui; }

int socle_commande_led(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "test")) {
    s_demande_test = true;
    printf("Test de la LED, %" PRIu32 " s ('led stop' pour l'arreter) :\n", statusled::testTotalMs() / 1000);
    uint32_t debut = 0;
    for (const statusled::TestStep &s : statusled::kTest) {
      printf("  %2" PRIu32 " s  %s\n", debut / 1000, statusled::patternName(s.p));
      debut += s.ms;
    }
    return 0;
  }
  if (argc == 2 && !strcmp(argv[1], "stop")) {
    s_demande_arret = true;
    printf("Test de la LED arrete.\n");
    return 0;
  }
  if (argc != 1) {
    printf("Format attendu : led [test|stop]\n");
    return 1;
  }
  const uint32_t c = s_couleur;
  printf("LED d'etat : WS2812 sur IO8\n");
  printf("  motif     : %s%s\n", statusled::patternName(s_motif), s_en_test ? " -- test en cours" : "");
  printf("  affiche   : R %u V %u B %u (plafond %u par canal)\n", (unsigned)(c >> 16), (unsigned)(c >> 8 & 0xFF),
         (unsigned)(c & 0xFF), statusled::kMax);
  printf("  ordres    : %" PRIu32 " confirme(s), %" PRIu32 " abandon(s) depuis le demarrage\n",
         tache_lampes_confirmes(), tache_lampes_abandons());
  return 0;
}

int socle_commande_cause(int argc, char **argv) {
  (void)argc;
  (void)argv;
  const char *texte = "inconnue";
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: texte = "mise sous tension"; break;
    case ESP_RST_EXT: texte = "broche de reset"; break;
    case ESP_RST_SW: texte = "redemarrage logiciel"; break;
    case ESP_RST_PANIC: texte = "PANIQUE (exception)"; break;
    case ESP_RST_INT_WDT: texte = "CHIEN DE GARDE des interruptions"; break;
    case ESP_RST_TASK_WDT: texte = "CHIEN DE GARDE de tache"; break;
    case ESP_RST_WDT: texte = "CHIEN DE GARDE (autre)"; break;
    case ESP_RST_BROWNOUT: texte = "BAISSE DE TENSION"; break;
    case ESP_RST_USB: texte = "reinitialisation par l'USB"; break;
    default: break;
  }
  printf("  cause du dernier demarrage : %s\n", texte);
  return 0;
}
