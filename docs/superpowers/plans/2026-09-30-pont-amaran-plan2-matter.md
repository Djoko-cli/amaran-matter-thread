# Pont amaran, plan 2 : Matter sur Thread (phases 1 et 2) : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le firmware produit du pont. Un pont Matter sur Thread montre les deux amaran 60d dans Maison et les pilote par le Bluetooth Mesh, sur la même ESP32-C6, avec le socle du pont Halo (voyant, bouton BOOT, console). Puis le banc C (une carte ou deux) et les bancs T.

**Architecture:** ESP-IDF v5.5.4 + esp-matter : l'approche A de la spec.
- Le cœur `lampes` (C pur, testé sur le Mac) décide quoi envoyer, confirme, relit et abandonne.
- Le composant `mesh` du plan 1 émet et capte. Il gagne un compteur de séquence en module pur, l'écart des doublons, les balises authentifiées, une console partagée et le diagnostic de 7.3.
- `pont_matter` fait le pont : un agrégateur et deux lampes pontées.
- Une tâche `lampes` possède l'état : Matter et la console y déposent leurs ordres, et l'état repart vers Matter par `attribute::report()`.
- La pile Matter possède l'hôte NimBLE ; le Bluetooth Mesh n'entre dans le réseau des lampes qu'après la mise en service.
- Le socle recopie la logique du Halo (`statusled`, `bootbtn`, avec ses tests), et porte en ESP-IDF la moitié Arduino.

```
Maison ─Thread─► pont_matter ─ordres─► tâche lampes (lampes.c) ─trames─► mesh ─annonces─► 60d
                      ▲                    │     ▲                          │
                      └──── report() ◄─────┘     └──── états (crochet) ◄────┘
                 socle : voyant WS2812, bouton BOOT, console
```

**Tech Stack:** ESP-IDF v5.5.4 (C11, C++17, FreeRTOS à 1 kHz, NimBLE, ESP-BLE-MESH, OpenThread MTD), esp-matter `c5b9ea8` (connectedhomeip `efefc94f`), clang et clang++ pour les tests natifs, Python 3 pour les outils du plan 1.

**Spec:** `docs/superpowers/specs/2026-09-28-pont-amaran-design.md`, surtout les sections 4, 5.6 à 5.8, 6, 7, 8.3 et 8.4. Les résultats des bancs R, qui fixent plusieurs choix, sont dans `docs/BANC.md` et `docs/PROTOCOLE.md`.

**Modèle :** le pont Halo, `~/Documents/Dev/esp32/benq`, commit `3f82f76` (lecture seule). On en reprend le voyant, le bouton, le plafond des abonnements, l'identité, et ses leçons côté Apple.

## Global Constraints

- ESP-IDF v5.5.4 dans `~/esp/esp-idf`, esp-matter commit `c5b9ea8` dans `~/esp/esp-matter`. Cible `esp32c6`, flash 4 Mo, une seule application (pas d'OTA).
- **ESP-IDF et esp-matter ne sont jamais modifiés** : le SmartButton et le Halo partagent l'installation. Le crochet passe par `-Wl,--wrap`. `components/mesh` refuse de compiler avec une autre version d'ESP-IDF.
- Pile Bluetooth : NimBLE. Dans le pont, c'est la pile Matter qui possède l'hôte.
- L'adresse Mesh de l'ESP32 est dans `0x7F00`–`0x7F7F`, **jamais `0x0001`** (l'adresse d'amaran Desktop).
- **Aucune clé** dans le dépôt, un journal ou un affichage. L'empreinte d'une clé = les 8 premiers chiffres hexa, en majuscules, de son SHA-256. La trace de la pile Mesh reste épinglée à ERROR : au-dessus, elle imprime des clés.
- Le dépôt est public : ni MAC complète (lampes, carte), ni numéro de série USB, ni empreinte réelle de clé.
- `CONFIG_MBEDTLS_HARDWARE_AES=n`.
- Émission :
  - au moins 70 ms entre deux messages ;
  - un ordre part 2 fois, une demande d'état 2 fois (1 fois jusqu'au banc C : commit `c0b7f13`) ;
  - 3 copies réseau à 20 ms d'écart, TTL 3.
- Français partout : code, console, commits, docs. Les commentaires du code sont **sans accents** (style du pont Halo).
- Commits : directement sur `main`, message en français, terminé par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **Aucun push sans l'accord de Djoko.**
- **Les sous-agents ne flashent jamais et n'ouvrent jamais de port série.**
  - Claude flashe avec l'accord de Djoko.
  - Djoko est présent dès qu'on émet vers les lampes.
- La carte du pont se reconnaît au champ `SER=` de `python -m serial.tools.list_ports -v`, jamais au nom du port. Le port est toujours donné explicitement. Ne jamais ouvrir ni flasher la C6 du maillage Thread BenQ, ni un écran LG (eux aussi en `usbmodem`).
- Seul Claude lit la base d'amaran Desktop (`~/Library/Containers/com.sidus.amaran-desktop`), pour charger les clés. Jamais un sous-agent.
- Dans les scripts et les commandes, utiliser `/usr/bin/grep` : le `grep` du poste est ugrep.
- Environnement, dans la même commande shell que `idf.py` : `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null`, suivi, pour le firmware du pont, de `&& source ~/esp/esp-matter/export.sh >/dev/null`. Le `PATH` d'abord : le Python 3.11 de PlatformIO, souvent en tête, fait échouer `export.sh`.
- `SRC_DIRS "."` : un fichier ajouté à `firmware/main` n'est compilé qu'après `idf.py reconfigure`.
- Tests natifs : `sh tests/hote/lancer.sh`, tout vert avant chaque commit.

## Écarts assumés par rapport à la spec

1. **6.3 : le niveau part même lampe éteinte.** R3 : une lampe éteinte retient le niveau reçu sans s'allumer, puis s'allume directement à ce niveau. Garder le niveau en consigne jusqu'à l'allumage ramènerait le curseur de Maison à l'ancien niveau, à la relecture suivante.
2. **5.6 : un ordre attend 80 ms avant de partir.** Une commande Matter écrit souvent plusieurs attributs de suite : l'arrêt avec effet écrit CurrentLevel au minimum, OnOff, puis CurrentLevel restauré. Tout part en une salve, avec la consigne finale.
3. **3.4, 6.6, 10 : pas de `blemesh_platform`.**
   - La pile Matter possède l'hôte NimBLE, et garde CHIPoBLE après la mise en service.
   - Le Bluetooth Mesh ne démarre qu'une fois Maison appairée et CHIPoBLE silencieux, 3 s plus tard.
   - Il retient ses émissions si CHIPoBLE annonce de nouveau.
   - `CONFIG_BLE_MESH_PROXY=n` : le Mesh n'enregistre aucun service GATT.
4. **4.3, 6.4 : pas d'écho, par construction.** L'état des lampes part par `attribute::report()`. Il prend lui-même le verrou de la pile, et ne rappelle pas l'application : ni marquage, ni `ScheduleWork`.
5. **6.6, 8.4 : codes d'appairage de test du SDK**, VID/PID `0xFFF1`/`0x8000`, comme pour le Halo, au lieu d'une partition d'usine propre à la carte.
   - Une seule carte, à la maison. Maison accepte, avec l'avertissement « non certifié ».
   - Le Halo a les mêmes codes : ne pas mettre les deux en service en même temps.
6. **5.8, 8.3 : Thread en enfant non dormant (MED) seulement.** Le banc C se passe en MED. Le rôle dormant n'est essayé que si la règle 5.8 échoue : c'est l'un des leviers du plan 2b.
7. **6.1 : endpoints fixes.** Les deux emplacements sont toujours créés, dans le même ordre (EP2, EP3) : leurs numéros ne changent jamais, sans rien garder en NVS. Un emplacement sans lampe est « Pas de réponse ».
8. **7.3, 7.4 : rouge fixe seulement une fois appairé.** Avant, le bleu clignotant prime, et le Mesh n'est pas démarré.
9. **8.4 : console et fiche produit dès la phase 1.** Le banc C en a besoin. La phase 2 ajoute le voyant, le bouton et Identify.
10. **6.2 : le niveau publié ne descend pas sous 4.** Leçon du Halo : sous 4, Maison montre une lampe allumée à fond. Une intensité qui donnerait un niveau de 1 à 3 est publiée au niveau 4 (`PONT_NIVEAU_PLANCHER`, `pont_matter.h`).

## Choix fixés par les bancs R (spec 8.2)

- Relecture au groupe `0xC000` toutes les 5 s. R4 : aucun état spontané, donc pas d'espacement. R5 : les deux lampes répondent au groupe.
- Ordre des trames : éteindre avant de changer le niveau ; régler le niveau avant d'allumer (R3).
- Pas de miroir vers amaran Desktop (R6) : accepté, comme le prévoyait la spec (11).

## Ajouts

- Le pont n'émet plus la balise « non provisionné » en entrant dans le réseau.
- Les copies réseau d'une même réponse sont écartées (par lampe, IV Index et SEQ). L'IV Index d'une balise n'est cru que si son authentification est juste.
- La commande `mesh` est partagée par les deux firmwares.
- Commandes en plus : `taches`, `cause`, `led stop`, `mesh ecoute on|off`.
- Le diagnostic de 7.3 signale aussi « clés présentes, mais pas entré dans le réseau » après 2 min.
- `mesh balayage [fenêtre intervalle]` : la part d'écoute du Bluetooth Mesh se lit et se règle à chaud (banc C, levier 1). Le pont la règle à 20 ms sur 40 ms (50 %) au démarrage, avant d'entrer dans le réseau.
- `led` sans argument : état du voyant (motif, couleur affichée, ordres confirmés et abandonnés).

## Carte des fichiers

| fichier | rôle | tâche |
|---|---|---|
| `components/lampes/{CMakeLists.txt,include/lampes.h,lampes.c}` | le cœur : consignes, ordres, relectures, joignabilité (C pur) | 1 |
| `tests/hote/test_lampes.c` | ses tests (72 vérifications) | 1 |
| `tests/hote/test_telink.c` | les trames réelles du banc (états, `0x0A`, `0x00`) | 1 |
| `components/mesh/{plancher.h,plancher.c}`, `tests/hote/test_plancher.c` | compteur de séquence et plancher (C pur) | 2 |
| `components/mesh/{include/mesh_amaran.h,mesh_amaran.c}` | adhésion sans balise, émissions retenues, compteurs | 2, 3 |
| `components/mesh/{include/hote_ble.h,hote_ble.c}` | l'hôte NimBLE, en-tête public | 2 |
| `components/mesh/include/{config_amaran.h,texte.h,crochet_tri.h}` | gardes `extern "C"` ; période de relecture en NVS | 2, 7 |
| `components/mesh/config_amaran.c` | période de relecture en NVS | 7 |
| `ecoute/main/app_main.c`, `ecoute/sdkconfig.defaults` | l'écoute démarre elle-même l'hôte NimBLE | 2 |
| `components/mesh/{crochet_tri.c,crochet.c,autotest.c}`, `tests/hote/test_crochet_tri.c` | doublons écartés, balises authentifiées | 3 |
| `components/mesh/{include/mesh_console.h,mesh_console.c}` | la commande `mesh`, partagée | 4 |
| `components/mesh/{include/diagnostic.h,diagnostic.c}`, `tests/hote/test_diagnostic.c` | le diagnostic de 7.3 (C pur) | 4 |
| `ecoute/main/console_ecoute.c` | la console d'écoute, allégée | 4 |
| `components/mesh/CMakeLists.txt` | sources et dépendances du composant | 2, 4 |
| `tests/hote/lancer.sh` | tests natifs | 1, 2, 4, 9 |
| `firmware/{CMakeLists.txt,partitions.csv,sdkconfig.defaults,dependencies.lock}` | le projet du pont | 6 |
| `firmware/main/{CMakeLists.txt,CHIPProjectConfig.h}` | composant principal, fiche produit | 6 |
| `firmware/main/{pont_matter.h,pont_matter.cpp}` | le côté Matter | 6, 10 |
| `firmware/main/app_main.cpp` | le démarrage | 6, 7, 10 |
| `firmware/main/{tache_lampes.h,tache_lampes.c}` | la tâche des lampes | 7, 10 |
| `firmware/main/{console_pont.h,console_pont.c}` | la console du pont | 7, 10 |
| `outils/check_sdkconfig.sh` | vérifie aussi le firmware du pont | 6 |
| `components/socle/{CMakeLists.txt,include/status_led.h,status_led.cpp,include/boot_button.h,boot_button.cpp}`, `tests/hote/test_socle.cpp` | la logique du voyant et du bouton, copiée du Halo | 9 |
| `firmware/main/{ws2812.h,ws2812.c,socle.h,socle.cpp}` | le voyant et le bouton sur la carte | 10 |
| `docs/BANC.md`, `README.md` | bancs et état | 5, 8, 11 |

Les Tasks 5, 8 et 11 se passent au banc, avec Djoko : Claude les mène lui-même, sans sous-agent. Les autres se prêtent à un sous-agent.

---

### Task 1: Le cœur `lampes` (C pur, testé sur le Mac)

**Files:**
- Create: `components/lampes/CMakeLists.txt`, `components/lampes/include/lampes.h`, `components/lampes/lampes.c`
- Create: `tests/hote/test_lampes.c`
- Modify: `tests/hote/lancer.sh`, `tests/hote/test_telink.c`

**Interfaces:**
- Consumes : `telink.h` (Task 1 du plan 1) : `telink_demande_etat`, `telink_marche`, `telink_intensite`, `telink_lire_etat`, `telink_somme`, `TELINK_*`.
- Produces :
  - `lampes_t`, `lampe_t`, `lampe_etat_t`, `lampes_sorties_t`, `lampes_signal_t` (voir l'en-tête) ;
  - `void lampes_init(lampes_t *l, const uint16_t adresses[], int n, const lampes_sorties_t *sorties, uint32_t maintenant_ms);`
  - `void lampes_mesh_pret(lampes_t *l, bool pret, uint32_t maintenant_ms);`
  - `void lampes_regler_releve(lampes_t *l, uint32_t periode_ms);`
  - `void lampes_ordre(lampes_t *l, int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter, uint32_t maintenant_ms);`
  - `void lampes_trame_recue(lampes_t *l, uint16_t src, const uint8_t trame[TELINK_TAILLE], uint32_t maintenant_ms);`
  - `void lampes_tic(lampes_t *l, uint32_t maintenant_ms);` (toutes les 50 ms) ;
  - `uint16_t lampes_niveau_vers_intensite(uint8_t niveau);`, `uint8_t lampes_intensite_vers_niveau(uint16_t intensite);`.

Règles appliquées (spec, et bancs de phase 0) :
- un ordre : trames envoyées 2 fois, demande d'état 200 ms après, confirmation par un état égal à la consigne dans la seconde, 3 essais puis abandon (5.6, 7.1) ;
- l'ordre attend 80 ms (`LAMPES_REGROUPEMENT_MS`) : une commande Matter écrit souvent plusieurs attributs de suite (l'arrêt avec effet de LevelControl écrit CurrentLevel au minimum, OnOff faux, puis CurrentLevel restauré) ; tout part en une salve, avec la consigne finale ;
- une seule consigne en attente par lampe : une nouvelle valeur remplace l'ancienne, au plus une salve par lampe toutes les 200 ms (T2) ;
- ordre des trames : éteindre avant de changer le niveau ; régler le niveau avant d'allumer (R3 : la lampe retient un niveau reçu éteinte et s'allume ensuite directement à ce niveau). **Amendement de la spec 6.3** : le niveau part tout de suite, même lampe éteinte, sinon la relecture ramènerait le curseur de Maison à l'ancien niveau ;
- relecture au groupe `0xC000` toutes les 5 s (R4 : aucun état spontané ; R5 : les deux lampes répondent au groupe) ; muette après 3 relectures sans réponse ; toute trame de la lampe (0x0A compris) prouve qu'elle vit ;
- pendant un ordre, les états qui ne tiennent pas la consigne ne sont pas montrés (ils peuvent être périmés) ;
- mesures du banc C (règle 5.8) : relectures répondues par lampe, délai de confirmation (total, max, nombre au-delà d'une seconde).

- [ ] **Step 1 : écrire les tests.**

`tests/hote/test_lampes.c` :

```c
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
```

- [ ] **Step 2 : les ajouter au lanceur, et les voir échouer.**

Dans `tests/hote/lancer.sh`, remplacer la ligne `CFLAGS=...` par :

```sh
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Icomponents/lampes/include -Itests/hote"
```

et ajouter, avant la ligne `echo "tests hote : tout est vert"` :

```sh
compiler_et_lancer test_lampes components/telink/telink.c components/lampes/lampes.c tests/hote/test_lampes.c
```

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation (`lampes.h` introuvable).

- [ ] **Step 3 : écrire le composant.**

`components/lampes/CMakeLists.txt` :

```cmake
idf_component_register(SRCS "lampes.c"
                       INCLUDE_DIRS "include"
                       REQUIRES telink)
```

`components/lampes/include/lampes.h` :

```c
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
#define LAMPES_REPETITIONS_ETAT 1u

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
  void (*publier)(void *ctx, int lampe, const lampe_etat_t *etat, bool joignable);
  void (*signaler)(void *ctx, int lampe, lampes_signal_t signal);
  void *ctx;
} lampes_sorties_t;

typedef enum {
  LAMPE_REPOS,    // aucun ordre en cours
  LAMPE_TRAMES,   // trames parties ; demande d'etat a echeance
  LAMPE_ATTENTE,  // demande d'etat partie ; etat egal a la consigne attendu avant echeance
} lampe_phase_t;

typedef struct {
  uint16_t adresse;
  // Etat lu
  bool connu;                    // un etat a ete lu depuis le demarrage
  lampe_etat_t lu;
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
  uint32_t debut_ms;             // arrivee de l'ordre (delai de confirmation)
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
// le controleur a deja mis ces valeurs dans ses attributs.
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
```

`components/lampes/lampes.c` :

```c
// Coeur du pont (voir lampes.h).
#include "lampes.h"

#include <string.h>

// maintenant a-t-il atteint echeance ? Horloge de 32 bits qui deborde : juste
// tant que les ecarts restent sous 2^31 ms (~24 jours).
static bool atteint(uint32_t maintenant, uint32_t echeance) { return (int32_t)(maintenant - echeance) >= 0; }

uint16_t lampes_niveau_vers_intensite(uint8_t niveau) {
  if (niveau < 1) niveau = 1;
  if (niveau > 254) niveau = 254;
  return (uint16_t)((2000u * niveau + 254u) / 508u);  // arrondi(niveau x 1000 / 254)
}

uint8_t lampes_intensite_vers_niveau(uint16_t intensite) {
  if (intensite > TELINK_INTENSITE_MAX) intensite = TELINK_INTENSITE_MAX;
  unsigned n = (508u * intensite + 1000u) / 2000u;  // arrondi(intensite x 254 / 1000)
  if (n < 1) n = 1;  // une intensite de 0 lue sur la lampe donne le niveau 1 (6.2)
  if (n > 254) n = 254;
  return (uint8_t)n;
}

void lampes_init(lampes_t *l, const uint16_t adresses[], int n, const lampes_sorties_t *sorties,
                 uint32_t maintenant_ms) {
  memset(l, 0, sizeof(*l));
  l->n = n < 0 ? 0 : (n > LAMPES_MAX ? LAMPES_MAX : n);
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].adresse = adresses[i];
    l->lampes[i].joignable = true;         // 6.5 : pas de « Pas de reponse » fugace au demarrage
    l->lampes[i].montre_joignable = true;  // les endpoints naissent joignables
  }
  l->sorties = *sorties;
  l->periode_ms = LAMPES_RELEVE_DEFAUT_MS;
  l->prochaine_releve_ms = maintenant_ms;  // premiere relecture aussitot (6.5)
}

void lampes_regler_releve(lampes_t *l, uint32_t periode_ms) {
  if (periode_ms < LAMPES_RELEVE_MIN_MS) periode_ms = LAMPES_RELEVE_MIN_MS;
  if (periode_ms > LAMPES_RELEVE_MAX_MS) periode_ms = LAMPES_RELEVE_MAX_MS;
  l->periode_ms = periode_ms;
}

// Publie ce que Matter doit montrer, s'il differe de ce qu'il montre deja (ou
// toujours, si forcer).
static void montrer(lampes_t *l, int i, bool forcer) {
  lampe_t *p = &l->lampes[i];
  const bool meme = p->montre_connu == p->connu && p->montre_joignable == p->joignable &&
                    (!p->connu || (p->montre.marche == p->lu.marche && p->montre.intensite == p->lu.intensite));
  if (meme && !forcer) return;
  p->montre_connu = p->connu;
  p->montre = p->lu;
  p->montre_joignable = p->joignable;
  l->sorties.publier(l->sorties.ctx, i, p->connu ? &p->lu : NULL, p->joignable);
}

static bool consigne_tenue(const lampe_t *p, const lampe_etat_t *e) {
  if (p->veut_marche && e->marche != p->consigne.marche) return false;
  if (p->veut_intensite && e->intensite != p->consigne.intensite) return false;
  return true;
}

// Trames de la consigne, dans l'ordre qui evite tout eclat : eteindre avant de
// changer le niveau ; regler le niveau avant d'allumer (R3 : la lampe retient un
// niveau recu eteinte, et s'allume ensuite directement a ce niveau). Une trame
// refusee par la file n'est pas rejouee ici : l'essai suivant la renverra.
static void envoyer_trames(lampes_t *l, const lampe_t *p) {
  uint8_t t[TELINK_TAILLE];
  if (p->veut_marche && !p->consigne.marche) {
    telink_marche(false, t);
    l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ORDRE);
  }
  if (p->veut_intensite) {
    telink_intensite(p->consigne.intensite, t);
    l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ORDRE);
  }
  if (p->veut_marche && p->consigne.marche) {
    telink_marche(true, t);
    l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ORDRE);
  }
}

static void demarrer_essai(lampes_t *l, lampe_t *p, uint32_t maintenant_ms) {
  envoyer_trames(l, p);
  p->a_refaire = false;
  p->phase = LAMPE_TRAMES;
  p->echeance_ms = maintenant_ms + LAMPES_DELAI_ETAT_MS;
}

static void finir(lampes_t *l, int i, lampes_signal_t signal, uint32_t maintenant_ms) {
  lampe_t *p = &l->lampes[i];
  p->phase = LAMPE_REPOS;
  p->veut_marche = p->veut_intensite = false;
  p->a_refaire = false;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    const uint32_t delai = maintenant_ms - p->debut_ms;
    l->confirmes++;
    l->delai_total_ms += delai;
    if (delai > l->delai_max_ms) l->delai_max_ms = delai;
    if (delai > 1000u) l->lents++;
  } else {
    l->abandons++;
  }
  l->sorties.signaler(l->sorties.ctx, i, signal);
  montrer(l, i, signal == LAMPES_SIGNAL_ABANDON);  // abandon : Maison revient au dernier etat lu (7.1)
}

void lampes_mesh_pret(lampes_t *l, bool pret, uint32_t maintenant_ms) {
  if (pret == l->mesh_pret) return;
  l->mesh_pret = pret;
  if (pret) {
    l->prochaine_releve_ms = maintenant_ms;  // relecture aussitot
    return;
  }
  for (int i = 0; i < l->n; i++) {
    if (l->lampes[i].phase != LAMPE_REPOS) finir(l, i, LAMPES_SIGNAL_ABANDON, maintenant_ms);
  }
}

void lampes_ordre(lampes_t *l, int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter,
                  uint32_t maintenant_ms) {
  if (lampe < 0 || lampe >= l->n || (!marche && !intensite)) return;
  lampe_t *p = &l->lampes[lampe];
  l->ordres++;
  // Le controleur montre deja sa consigne : la prochaine publication part d'office.
  if (depuis_matter) p->montre_connu = false;
  if (marche) {
    p->veut_marche = true;
    p->consigne.marche = *marche;
  }
  if (intensite) {
    p->veut_intensite = true;
    p->consigne.intensite = *intensite > TELINK_INTENSITE_MAX ? TELINK_INTENSITE_MAX : *intensite;
  }
  if (!l->mesh_pret) {
    finir(l, lampe, LAMPES_SIGNAL_ABANDON, maintenant_ms);
    return;
  }
  // Une seule consigne en attente par lampe : la nouvelle valeur remplace
  // l'ancienne, et part au plus tot a la prochaine etape (5.6).
  if (p->phase != LAMPE_REPOS) {
    p->a_refaire = true;
    return;
  }
  // Une valeur egale au dernier etat lu ne fait jamais emettre (6.4).
  if (p->connu && consigne_tenue(p, &p->lu)) {
    p->veut_marche = p->veut_intensite = false;
    montrer(l, lampe, false);
    return;
  }
  // Les trames partent apres LAMPES_REGROUPEMENT_MS : une commande Matter ecrit
  // souvent plusieurs attributs a la suite (l'arret avec effet : CurrentLevel au
  // minimum, OnOff faux, puis CurrentLevel restaure), et tout part en une salve,
  // avec la consigne finale.
  p->essai = 1;
  p->a_refaire = true;
  p->phase = LAMPE_TRAMES;
  p->echeance_ms = maintenant_ms + LAMPES_REGROUPEMENT_MS;
  p->debut_ms = maintenant_ms;
}

void lampes_trame_recue(lampes_t *l, uint16_t src, const uint8_t trame[TELINK_TAILLE], uint32_t maintenant_ms) {
  int i = -1;
  for (int k = 0; k < l->n; k++) {
    if (l->lampes[k].adresse == src) {
      i = k;
      break;
    }
  }
  if (i < 0) return;
  lampe_t *p = &l->lampes[i];
  l->trames_recues++;
  // Toute trame de la lampe prouve qu'elle vit, y compris celles que l'on ne lit
  // pas (0x0A, reponses aux questions d'amaran Desktop).
  p->reponse_ms = maintenant_ms;
  p->releves_sans_reponse = 0;
  p->joignable = true;
  if (!p->repondu) {
    p->repondu = true;
    p->releves_repondues++;
  }
  telink_etat_t e;
  const bool etat = telink_lire_etat(trame, &e);
  if (etat) {
    p->connu = true;
    p->lu.marche = e.marche;
    p->lu.intensite = e.intensite;
  }
  if (p->phase == LAMPE_REPOS) {
    montrer(l, i, false);
    return;
  }
  // Ordre en cours : seul un etat recu apres notre demande et egal a la
  // consigne compte. Les autres peuvent etre perimes : on ne les montre pas (5.6).
  if (etat && p->phase == LAMPE_ATTENTE && !p->a_refaire && consigne_tenue(p, &p->lu)) {
    finir(l, i, LAMPES_SIGNAL_CONFIRME, maintenant_ms);
  }
}

void lampes_tic(lampes_t *l, uint32_t maintenant_ms) {
  for (int i = 0; i < l->n; i++) {
    lampe_t *p = &l->lampes[i];
    if (p->phase == LAMPE_TRAMES) {
      if (!atteint(maintenant_ms, p->echeance_ms)) continue;
      if (p->a_refaire) {  // au plus une salve de trames par lampe toutes les 200 ms
        p->essai = 1;
        demarrer_essai(l, p, maintenant_ms);
        continue;
      }
      uint8_t t[TELINK_TAILLE];
      telink_demande_etat(t);
      l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ETAT);
      p->demande_ms = maintenant_ms;
      p->phase = LAMPE_ATTENTE;
      p->echeance_ms = maintenant_ms + LAMPES_FENETRE_MS;
    } else if (p->phase == LAMPE_ATTENTE) {
      if (p->a_refaire) {
        p->essai = 1;
        demarrer_essai(l, p, maintenant_ms);
        continue;
      }
      if (!atteint(maintenant_ms, p->echeance_ms)) continue;
      if (p->essai < LAMPES_ESSAIS) {
        p->essai++;
        demarrer_essai(l, p, maintenant_ms);
      } else {
        finir(l, i, LAMPES_SIGNAL_ABANDON, maintenant_ms);
      }
    }
  }
  // Relecture periodique au groupe « All » (5.7).
  if (!atteint(maintenant_ms, l->prochaine_releve_ms)) return;
  l->prochaine_releve_ms = maintenant_ms + l->periode_ms;
  for (int i = 0; i < l->n; i++) {
    lampe_t *p = &l->lampes[i];
    if (p->releves_sans_reponse >= LAMPES_RELEVES_MUETTE && p->joignable) {
      p->joignable = false;  // 3 relectures sans reponse : « Pas de reponse » (7.2)
      if (p->phase == LAMPE_REPOS) montrer(l, i, false);
    }
    if (p->releves_sans_reponse < 255) p->releves_sans_reponse++;
    if (l->mesh_pret) p->repondu = false;  // la relecture qui part attend sa reponse
  }
  // Mesh pas pret : rien ne part, mais les periodes comptent, et les lampes
  // deviennent muettes au bout de trois (7.3).
  if (!l->mesh_pret) return;
  uint8_t t[TELINK_TAILLE];
  telink_demande_etat(t);
  l->sorties.envoyer(l->sorties.ctx, LAMPES_GROUPE, t, LAMPES_REPETITIONS_ETAT);
  l->releves++;
}
```

- [ ] **Step 4 : les tests passent.**

Run: `sh tests/hote/lancer.sh`
Expected : `lampes : 72 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 5 : les trames du banc dans les tests de `telink`.**

La revue finale du plan 1 l'a demandé : `lampes` repose sur `telink_lire_etat()`, et les vraies trames du banc (`docs/PROTOCOLE.md`) doivent y rester vraies. Ces tests passent d'emblée : ils fixent le comportement.

Dans `tests/hote/test_telink.c`, juste avant `int main(void) {`, ajouter :

```c
// Trames relevees au banc du 30/09/2026 (docs/PROTOCOLE.md).
static void test_trames_du_banc(void) {
  static const struct {
    uint8_t t[TELINK_TAILLE];
    bool marche;
    uint16_t intensite;
  } etats[] = {
      {{0xCE, 0x00, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0xE8, 0x02}, false, 930},  // lampe 1
      {{0x4D, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0x66, 0x02}, true, 410},   // lampe 1
      {{0x75, 0x00, 0x00, 0x00, 0x00, 0x40, 0x01, 0x23, 0x0F, 0x02}, false, 60},   // lampe 2
      {{0xB2, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0x23, 0x4B, 0x02}, true, 300},   // lampe 2
  };
  for (size_t i = 0; i < sizeof(etats) / sizeof(etats[0]); i++) {
    telink_etat_t e;
    VERIFIE(telink_lire_etat(etats[i].t, &e) && e.mode == TELINK_MODE_CCT, "etat du banc %u lisible", (unsigned)i);
    VERIFIE(e.marche == etats[i].marche && e.intensite == etats[i].intensite, "etat du banc %u : %d, %u", (unsigned)i,
            e.marche, (unsigned)e.intensite);
  }
  // Alimentation (0x0A) et produit (0x00) : sommes justes, mais pas des etats.
  const uint8_t alimentation[TELINK_TAILLE] = {0x86, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x31, 0x4B, 0x0A};
  const uint8_t produit[TELINK_TAILLE] = {0xB4, 0x03, 0x80, 0xA3, 0x7C, 0x08, 0x6E, 0x00, 0x9C, 0x00};
  telink_etat_t e;
  VERIFIE(telink_somme(alimentation) == alimentation[0] && !telink_lire_etat(alimentation, &e), "0x0A : pas un etat");
  VERIFIE(telink_somme(produit) == produit[0] && !telink_lire_etat(produit, &e), "0x00 : pas un etat");
  // Ordre d'intensite 700, capte a l'emission, du pont comme de l'app.
  const uint8_t v700[TELINK_TAILLE] = {0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAF, 0x8F};
  uint8_t t[TELINK_TAILLE];
  telink_intensite(700, t);
  VERIFIE(memcmp(t, v700, TELINK_TAILLE) == 0, "intensite 700 du banc");
}
```

et, dans `main()`, après `test_lire_etat();`, ajouter `test_trames_du_banc();`.

Run: `sh tests/hote/lancer.sh`
Expected : `telink : 25 verifications, 0 echecs`, et tout le reste vert.

- [ ] **Step 6 : commit.**

```bash
git add components/lampes tests/hote/test_lampes.c tests/hote/test_telink.c tests/hote/lancer.sh
git commit -m "$(printf "Ajouter le coeur du pont : consignes, confirmation, abandon et joignabilite des lampes\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 2: Le compteur de séquence en module pur, et l'entrée dans le réseau sans annonce

**Files:**
- Create: `components/mesh/plancher.h`, `components/mesh/plancher.c`, `tests/hote/test_plancher.c`
- Move: `components/mesh/hote_ble.h` -> `components/mesh/include/hote_ble.h` (`git mv`)
- Modify: `components/mesh/mesh_amaran.c` (fichier entier ci-dessous), `components/mesh/hote_ble.c`, `components/mesh/CMakeLists.txt`
- Modify: `components/mesh/include/mesh_amaran.h`, `components/mesh/include/config_amaran.h`, `components/mesh/include/texte.h`, `components/mesh/include/crochet_tri.h` (gardes `extern "C"`)
- Modify: `ecoute/main/app_main.c` (fichier entier), `ecoute/sdkconfig.defaults`, `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : `config_sauver_plancher`, `config_sauver_adresse` (plan 1, tâche 6) ; `bt_mesh` (`net.h`) ; `bt_mesh_atomic_set_bit` (`mesh/atomic.h`).
- Produces :
  - `plancher_t`, `plancher_decision_t` ; `plancher_init`, `plancher_epuise`, `plancher_preparer`, `plancher_sauve`, `plancher_remonter`, `plancher_parti` (voir `plancher.h`) ;
  - `bool hote_ble_pret(void);` (en-tête public `hote_ble.h`) ;
  - `void mesh_autoriser_emission(bool oui);` : le pont retient les émissions Mesh pendant que Matter annonce en BLE ;
  - `mesh_demarrer()` ne démarre plus l'hôte NimBLE : l'appelant le fait (firmware d'écoute) ou la pile Matter (pont) ; il attend 10 s au plus qu'il soit synchronisé.

Pourquoi (revue finale du plan 1 et recherche esp-matter) :
- les règles du plancher (spec 5.4), corrigées en trois tours au plan 1, vivent dans un module pur testé par une simulation (remises à 0 de la pile, refus de la NVS, redémarrages, changement d'adresse) ;
- dans le pont, la pile Matter possède l'hôte NimBLE (elle le démarre dans `esp_matter::start()`) : le Mesh ne doit plus le démarrer lui-même ;
- `esp_ble_mesh_node_prov_enable()` lançait la balise « non provisionné » (notre UUID) le temps que `bt_mesh_provision()` passe : on pose le rôle nœud à la main (`bt_mesh_provision()` démarre le scan et appelle la fin d'adhésion comme avant, `net.c` : `bt_mesh_net_start`) ;
- le code C++ du pont inclura les en-têtes du Mesh : gardes `extern "C"` ;
- le composant lit des internes d'ESP-IDF v5.5.4 : un `#error` protège de toute autre version ;
- `CONFIG_BLE_MESH_PROXY=n` : la pile Mesh n'enregistre plus aucun service GATT (obligatoire dans le pont, où l'hôte NimBLE appartient à Matter) ;
- journal NimBLE aux avertissements (557 lignes « GAP procedure » au banc du 30/09) ;
- chargement des réglages non fatal (plus de boucle de redémarrage sur une erreur NVS).

- [ ] **Step 1 : les tests du plancher.**

`tests/hote/test_plancher.c` :

```c
// Tests sur le Mac des regles du compteur de sequence Mesh (spec 5.4).
// Lancer : sh tests/hote/lancer.sh
#include "plancher.h"
#include "unite.h"

static void test_depart(void) {
  plancher_t p;
  uint32_t seq, nouveau;
  plancher_init(&p, 0);
  VERIFIE(plancher_preparer(&p, 0, 2, &seq, &nouveau) == PLANCHER_SAUVER && seq == 0 &&
              nouveau == 2 + PLANCHER_BLOC,
          "premier envoi : le plancher se sauve d'abord");
  plancher_sauve(&p, nouveau);
  VERIFIE(plancher_preparer(&p, 0, 2, &seq, &nouveau) == PLANCHER_ENVOYER, "plancher sauve : envoyer");
}

static void test_ne_redescend_jamais(void) {
  plancher_t p;
  uint32_t seq, nouveau;
  plancher_init(&p, 1000);
  plancher_parti(&p, 1000);
  plancher_parti(&p, 1001);
  VERIFIE(p.seq_min == 1002, "seq_min suit le plus haut numero parti");
  plancher_parti(&p, 500);
  VERIFIE(p.seq_min == 1002, "seq_min ne descend pas");
  VERIFIE(plancher_remonter(&p, 0) == 1002, "pile remise a 0 : remontee");
  VERIFIE(plancher_remonter(&p, 5000) == 5000, "pile plus haut : gardee");
  plancher_sauve(&p, 2000);
  (void)plancher_preparer(&p, 0, 1, &seq, &nouveau);
  VERIFIE(seq == 1002, "preparer remonte aussi");
  plancher_sauve(&p, 1500);
  VERIFIE(p.plancher_sauve == 2000, "le plancher sauve ne recule pas");
}

static void test_limite(void) {
  plancher_t p;
  uint32_t seq, nouveau;
  plancher_init(&p, PLANCHER_LIMITE - 2);
  VERIFIE(!plancher_epuise(&p), "juste sous la limite : pas epuise");
  VERIFIE(plancher_preparer(&p, 0, 2, &seq, &nouveau) == PLANCHER_SAUVER, "dernier bloc");
  VERIFIE(plancher_preparer(&p, PLANCHER_LIMITE - 1, 2, &seq, &nouveau) == PLANCHER_ADRESSE_SUIVANTE,
          "au-dela de la limite : adresse suivante");
  plancher_init(&p, PLANCHER_LIMITE + 1);
  VERIFIE(plancher_epuise(&p), "plancher lu au-dela de la limite : epuise");
}

// Simulation : la pile remet sa sequence a 0 a tout moment (reprise d'IV), la
// NVS refuse parfois d'ecrire, la carte redemarre, l'adresse change. A chaque
// message, les invariants de la spec 5.4.
static uint32_t g_alea = 12345;
static uint32_t alea(uint32_t n) {
  g_alea = g_alea * 1103515245u + 12345u;
  return ((g_alea >> 16) & 0x7FFF) % n;
}

static void test_simulation(void) {
  uint32_t nvs = PLANCHER_LIMITE - 60000;  // pres de la limite : l'adresse changera en route
  uint32_t pile;                           // bt_mesh.seq
  uint32_t dernier = 0;                    // plus haut numero parti a cette adresse
  bool deja = false;
  plancher_t p;
  plancher_init(&p, nvs);
  pile = nvs;  // fin d'adhesion : la pile repart du plancher
  unsigned violations = 0, envois = 0, redemarrages = 0, adresses = 0, refus = 0;
  for (int pas = 0; pas < 300000; pas++) {
    const uint32_t r = alea(1000);
    if (r < 5 || plancher_epuise(&p)) {  // redemarrage (ou plancher deja au-dela de la limite)
      if (plancher_epuise(&p)) {
        adresses++;
        nvs = 0;
        deja = false;
      }
      plancher_init(&p, nvs);
      pile = nvs;
      redemarrages++;
      continue;
    }
    if (r < 15) {
      pile = 0;  // reprise d'IV entre deux ordres
      continue;
    }
    const uint32_t a = 1 + alea(2);
    uint32_t seq, nouveau;
    const plancher_decision_t d = plancher_preparer(&p, pile, a, &seq, &nouveau);
    if (d == PLANCHER_ADRESSE_SUIVANTE) {  // adresse suivante sauvee, compteur remis a 0, redemarrage
      adresses++;
      nvs = 0;
      deja = false;
      plancher_init(&p, nvs);
      pile = nvs;
      continue;
    }
    if (d == PLANCHER_SAUVER) {
      if (alea(20) == 0) {  // la NVS refuse : rien ne part
        refus++;
        continue;
      }
      nvs = nouveau;
      plancher_sauve(&p, nouveau);
    }
    pile = seq;
    for (uint32_t k = 0; k < a; k++) {
      if (alea(50) == 0) pile = 0;  // reprise d'IV entre deux repetitions
      pile = plancher_remonter(&p, pile);
      const uint32_t envoi = pile++;  // la pile consomme un numero par message
      if (deja && envoi <= dernier) violations++;  // rejeu : les lampes le jetteraient
      if (envoi >= nvs) violations++;              // numero pas encore couvert par la NVS
      if (envoi > PLANCHER_LIMITE) violations++;   // la pile lancerait une mise a jour d'IV
      dernier = envoi;
      deja = true;
      envois++;
      plancher_parti(&p, envoi);
    }
  }
  VERIFIE(violations == 0, "%u violation(s) des invariants", violations);
  VERIFIE(envois > 100000 && redemarrages > 1000 && adresses >= 1 && refus > 100,
          "la simulation couvre tous les cas (%u envois, %u redemarrages, %u adresses, %u refus)", envois,
          redemarrages, adresses, refus);
}

int main(void) {
  test_depart();
  test_ne_redescend_jamais();
  test_limite();
  test_simulation();
  return bilan("plancher");
}
```

Dans `tests/hote/lancer.sh`, ajouter `-Icomponents/mesh` à `CFLAGS` (après `-Icomponents/mesh/include`), puis, avant la ligne `compiler_et_lancer test_lampes ...` :

```sh
compiler_et_lancer test_plancher components/mesh/plancher.c tests/hote/test_plancher.c
```

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation (`plancher.h` introuvable).

- [ ] **Step 2 : le module.**

`components/mesh/plancher.h` :

```c
// Regles du compteur de sequence Mesh de l'ESP32 (spec 5.4), en C pur, sorties
// de mesh_amaran.c pour etre testees sur le Mac (tests/hote/test_plancher.c) :
// - le plancher sauve en NVS devance toujours tout numero deja parti ;
// - la sequence ne redescend jamais, meme quand la pile la remet a 0 ;
// - l'adresse change avant le seuil de mise a jour d'IV de la pile.
// Une seule tache l'appelle (la tache d'emission) : pas de verrou ici.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PLANCHER_BLOC 256u  // le plancher sauve devance la sequence d'au moins ce bloc
// Sous le seuil ou la pile lance seule une mise a jour d'IV (IV_UPDATE_SEQ_LIMIT
// = 8000000 dans net.c) ; au-dela : adresse suivante (spec 5.4).
#define PLANCHER_LIMITE 0x700000u

typedef struct {
  uint32_t seq_min;         // plus haut numero parti + 1 : la sequence n'y redescend jamais
  uint32_t plancher_sauve;  // valeur gardee en NVS
} plancher_t;

typedef enum {
  PLANCHER_ENVOYER,           // la sequence est en etat : emettre
  PLANCHER_SAUVER,            // sauver *nouveau en NVS, puis plancher_sauve(), puis emettre
  PLANCHER_ADRESSE_SUIVANTE,  // la limite serait depassee : adresse suivante, puis redemarrer
} plancher_decision_t;

// Au demarrage, avec le plancher lu en NVS : la sequence repart de la.
void plancher_init(plancher_t *p, uint32_t plancher_nvs);
// Le plancher lu depasse deja la limite : adresse suivante avant tout envoi.
bool plancher_epuise(const plancher_t *p);
// Avant d'emettre a_consommer messages (un numero chacun). *seq : la sequence a
// donner a la pile (jamais sous seq_min). *nouveau : le plancher a sauver.
plancher_decision_t plancher_preparer(const plancher_t *p, uint32_t seq_pile, uint32_t a_consommer, uint32_t *seq,
                                      uint32_t *nouveau);
// La NVS a garde le nouveau plancher.
void plancher_sauve(plancher_t *p, uint32_t nouveau);
// Juste avant chaque message : la sequence a donner a la pile.
uint32_t plancher_remonter(const plancher_t *p, uint32_t seq_pile);
// Un message est parti avec le numero seq_envoi.
void plancher_parti(plancher_t *p, uint32_t seq_envoi);

#ifdef __cplusplus
}
#endif
```

`components/mesh/plancher.c` :

```c
// Regles du compteur de sequence Mesh (voir plancher.h).
#include "plancher.h"

void plancher_init(plancher_t *p, uint32_t plancher_nvs) {
  p->seq_min = plancher_nvs;
  p->plancher_sauve = plancher_nvs;
}

bool plancher_epuise(const plancher_t *p) { return p->plancher_sauve > PLANCHER_LIMITE; }

uint32_t plancher_remonter(const plancher_t *p, uint32_t seq_pile) {
  // La pile remet la sequence a 0 lors d'une reprise d'IV Index (net.c), a tout
  // moment : sans cela, (IV, sequence) resservirait apres un redemarrage et les
  // lampes rejetteraient nos messages comme des rejeux.
  return seq_pile < p->seq_min ? p->seq_min : seq_pile;
}

plancher_decision_t plancher_preparer(const plancher_t *p, uint32_t seq_pile, uint32_t a_consommer, uint32_t *seq,
                                      uint32_t *nouveau) {
  *seq = plancher_remonter(p, seq_pile);
  *nouveau = p->plancher_sauve;
  if (*seq + a_consommer > PLANCHER_LIMITE) return PLANCHER_ADRESSE_SUIVANTE;
  // Le plancher en NVS devance toujours la sequence : il est releve, et sauve,
  // avant que les numeros correspondants partent.
  if (*seq + a_consommer >= p->plancher_sauve) {
    *nouveau = *seq + a_consommer + PLANCHER_BLOC;
    return PLANCHER_SAUVER;
  }
  return PLANCHER_ENVOYER;
}

void plancher_sauve(plancher_t *p, uint32_t nouveau) {
  if (nouveau > p->plancher_sauve) p->plancher_sauve = nouveau;
}

void plancher_parti(plancher_t *p, uint32_t seq_envoi) {
  if (seq_envoi + 1 > p->seq_min) p->seq_min = seq_envoi + 1;
}
```

Run: `sh tests/hote/lancer.sh`
Expected : `plancher : 14 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 3 : l'hôte NimBLE, public et partageable.**

```bash
git mv components/mesh/hote_ble.h components/mesh/include/hote_ble.h
```

`components/mesh/include/hote_ble.h` devient :

```c
// Hote NimBLE du Bluetooth Mesh. Le firmware d'ecoute le demarre lui-meme ; dans
// le firmware du pont, c'est la pile Matter qui le demarre et le possede (spec
// 3.4, plan 2) : on attend seulement qu'il soit synchronise.
#pragma once

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Demarre l'hote NimBLE et attend sa synchronisation avec le controleur.
esp_err_t hote_ble_demarrer(void);
// Vrai quand l'hote NimBLE est synchronise (demarre par nous ou par Matter).
bool hote_ble_pret(void);

#ifdef __cplusplus
}
#endif
```

Dans `components/mesh/hote_ble.c`, juste avant `esp_err_t hote_ble_demarrer(void) {`, ajouter :

```c
bool hote_ble_pret(void) { return ble_hs_synced(); }
```

- [ ] **Step 4 : gardes `extern "C"`.**

Dans chacun de `components/mesh/include/mesh_amaran.h`, `config_amaran.h`, `texte.h` et `crochet_tri.h` : juste après la dernière ligne `#include` du fichier, insérer

```c

#ifdef __cplusplus
extern "C" {
#endif
```

et à la toute fin du fichier, ajouter

```c

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 5 : `mesh_amaran.h`.**

Remplacer la ligne `esp_err_t mesh_demarrer(const amaran_config_t *cfg);` par :

```c
// Entre dans le reseau des lampes. L'hote NimBLE doit etre demarre, par
// hote_ble_demarrer() ou par la pile Matter : on attend 10 s au plus qu'il soit
// synchronise (ESP_ERR_TIMEOUT sinon).
esp_err_t mesh_demarrer(const amaran_config_t *cfg);
```

et, juste après la ligne `uint32_t mesh_plancher(void);`, ajouter :

```c
// Retient les emissions (faux) tant que Matter s'annonce en BLE : un seul jeu
// d'annonces existe. Vrai au demarrage.
void mesh_autoriser_emission(bool oui);
```

- [ ] **Step 6 : `mesh_amaran.c`, fichier entier.**

```c
// Adhesion au reseau Bluetooth Mesh des lampes et file d'emission (spec 5.1,
// 5.4, 5.6).
//
// Adapte de main/mesh.c d'amaran-bridge :
// https://github.com/kevinschaich/amaran-bridge
// Suivent son code de pres : la sequence d'adhesion et la table d'opcodes du modele vendeur.
//
// MIT License
//
// Copyright (c) 2026 Kevin Schaich
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
#include "mesh_amaran.h"

#include <inttypes.h>
#include <string.h>

#include "sdkconfig.h"

#include "esp_idf_version.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "esp_ble_mesh_common_api.h"
#include "esp_ble_mesh_config_model_api.h"
#include "esp_ble_mesh_defs.h"
#include "esp_ble_mesh_networking_api.h"
#include "esp_ble_mesh_provisioning_api.h"

// En-tetes internes de la pile (chemins ajoutes par CMakeLists.txt) : aucune
// API publique ne permet d'entrer dans un reseau existant.
#include "local.h"        // bt_mesh_node_local_app_key_add, bt_mesh_node_bind_app_key_to_model
#include "mesh/atomic.h"  // bt_mesh_atomic_set_bit
#include "mesh/main.h"    // bt_mesh_provision
#include "net.h"          // bt_mesh : flags, seq, iv_index

#include "crochet.h"
#include "hote_ble.h"
#include "plancher.h"

// Ce composant lit des en-tetes internes de la pile (net.h, local.h, mesh/main.h)
// et en intercepte deux fonctions (--wrap) : tout y est verifie pour ESP-IDF
// v5.5.4 seulement.
#if ESP_IDF_VERSION != ESP_IDF_VERSION_VAL(5, 5, 4)
#error "components/mesh depend des internes d'ESP-IDF v5.5.4 : a reverifier avant de changer de version"
#endif

// Garde-fou : au-dessus d'ERROR, la pile Mesh imprime des cles (BT_WARN
// AppKeyValExist et NetKeyValExist dans core/local.c, BT_INFO NetKey et DevKey
// dans core/main.c, BT_DBG dans core/crypto.c). Le niveau est epingle dans
// ecoute/sdkconfig.defaults. Pas de BLE_MESH_NO_LOG : la spec 5.3 veut garder
// l'erreur "IVIndex out of sync" (BT_ERR). Symbole d'ESP-IDF (Kconfig.in) :
// 0 NONE, 1 ERROR, 2 WARNING, 3 INFO, 4 DEBUG, 5 VERBOSE.
#if defined(CONFIG_BLE_MESH_STACK_TRACE_LEVEL) && CONFIG_BLE_MESH_STACK_TRACE_LEVEL > 1
#error "Niveau de trace Bluetooth Mesh au-dessus d'ERROR : la pile imprimerait des cles du reseau. Choisir CONFIG_BLE_MESH_TRACE_LEVEL_ERROR (idf.py menuconfig, ou supprimer ecoute/sdkconfig pour le regenerer depuis sdkconfig.defaults)."
#endif

static const char *TAG = "mesh";

#define NET_IDX 0x0000
#define APP_IDX 0x0000
#define TTL 3
#define ECART_MS 70          // entre deux messages et entre deux repetitions
// vTaskDelay(n) dort entre n-1 et n ticks (60 a 70 ms a 100 Hz) : un tick de plus tient ECART_MS au moins.
#define ECART_TICKS (pdMS_TO_TICKS(ECART_MS) + 1)
#define FILE_TX 16

typedef struct {
  uint16_t dst;
  uint8_t repetitions;
  uint8_t trame[TELINK_TAILLE];
} message_tx_t;

static amaran_config_t s_cfg;
static QueueHandle_t s_tx;
static volatile bool s_pret;
static volatile bool s_emission_permise = true;
static plancher_t s_plancher;  // compteur de sequence (spec 5.4), tenu par la tache d'emission
static uint32_t s_emis;
static uint32_t s_echecs;

static esp_ble_mesh_cfg_srv_t s_cfg_srv = {
    .net_transmit = ESP_BLE_MESH_TRANSMIT(2, 20),  // 3 copies a 20 ms
    .relay = ESP_BLE_MESH_RELAY_NOT_SUPPORTED,
    .beacon = ESP_BLE_MESH_BEACON_DISABLED,
    .friend_state = ESP_BLE_MESH_FRIEND_NOT_SUPPORTED,
    .gatt_proxy = ESP_BLE_MESH_GATT_PROXY_NOT_SUPPORTED,
    .default_ttl = TTL,
};

static esp_ble_mesh_model_t s_racine[] = {
    ESP_BLE_MESH_MODEL_CFG_SRV(&s_cfg_srv),
};

// Forme a 3 octets pour que l'AppKey ait un modele ou se lier, et forme a 1
// octet (0x26), celle qu'emploient vraiment les lampes.
static esp_ble_mesh_model_op_t s_ops[] = {
    ESP_BLE_MESH_MODEL_OP(ESP_BLE_MESH_MODEL_OP_3(TELINK_OPCODE, TELINK_CID), 1),
    ESP_BLE_MESH_MODEL_OP(TELINK_OPCODE, 1),
    ESP_BLE_MESH_MODEL_OP_END,
};

static esp_ble_mesh_model_t s_vendeur[] = {
    ESP_BLE_MESH_VENDOR_MODEL(TELINK_CID, 0x0000, s_ops, NULL, NULL),
};

static esp_ble_mesh_elem_t s_elements[] = {
    ESP_BLE_MESH_ELEMENT(0, s_racine, s_vendeur),
};

static esp_ble_mesh_comp_t s_composition = {
    .cid = TELINK_CID,
    .element_count = 1,
    .elements = s_elements,
};

static uint8_t s_uuid[16];
static esp_ble_mesh_prov_t s_prov = {.uuid = s_uuid};

// --- Adhesion

static void fin_adhesion(void) {
  int rc = bt_mesh_node_local_app_key_add(NET_IDX, APP_IDX, s_cfg.appkey);
  if (rc) {
    ESP_LOGE(TAG, "AppKey refusee (%d)", rc);
    return;
  }
  rc = bt_mesh_node_bind_app_key_to_model(s_cfg.adresse, 0x0000, TELINK_CID, APP_IDX);
  if (rc) {
    ESP_LOGE(TAG, "liaison de l'AppKey refusee (%d)", rc);
    return;
  }
  // La sequence repart au-dessus de tout ce qui a pu partir avant (5.4). La NVS
  // garde deja le plancher : la tache d'emission sauve le bloc suivant avant le
  // premier envoi, et un echec de sauvegarde y bloque l'envoi.
  bt_mesh.seq = s_plancher.seq_min;
  s_pret = true;
  ESP_LOGI(TAG, "pret : adresse 0x%04x, IV 0x%08" PRIx32 ", sequence 0x%06" PRIx32, s_cfg.adresse,
           (uint32_t)bt_mesh.iv_index, (uint32_t)bt_mesh.seq);
}

static void rappel_prov(esp_ble_mesh_prov_cb_event_t ev, esp_ble_mesh_prov_cb_param_t *p) {
  if (ev == ESP_BLE_MESH_NODE_PROV_COMPLETE_EVT) {
    ESP_LOGI(TAG, "entre dans le reseau, adresse 0x%04x", p->node_prov_complete.addr);
    fin_adhesion();
  }
}

static void rappel_cfg_srv(esp_ble_mesh_cfg_server_cb_event_t ev, esp_ble_mesh_cfg_server_cb_param_t *p) {
  (void)ev;
  (void)p;  // personne ne configure ce noeud
}

static void rappel_modele(esp_ble_mesh_model_cb_event_t ev, esp_ble_mesh_model_cb_param_t *p) {
  (void)ev;
  (void)p;  // les etats arrivent par le crochet, pas ici
}

// --- Emission

// Sequence bientot epuisee : l'adresse source suivante repart de zero (5.4).
// Sur ESP_OK l'appelant redemarre ; sinon rien n'a change.
static esp_err_t changer_d_adresse(uint32_t seq) {
  const uint16_t suivante =
      s_cfg.adresse >= AMARAN_ADRESSE_MAX ? AMARAN_ADRESSE_MIN : (uint16_t)(s_cfg.adresse + 1);
  ESP_LOGW(TAG, "sequence 0x%06" PRIx32 " presque epuisee : adresse 0x%04x", seq, suivante);
  const esp_err_t err = config_sauver_adresse(suivante);
  if (err != ESP_OK) ESP_LOGE(TAG, "adresse 0x%04x non sauvee : %s", suivante, esp_err_to_name(err));
  return err;
}

// Met la sequence en etat avant d'emettre a_consommer messages (un numero
// chacun), selon plancher.c. Faux : l'envoi est abandonne (NVS refusee, ou
// adresse suivante impossible a sauver).
static bool preparer_sequence(uint32_t a_consommer) {
  uint32_t seq = 0, nouveau = 0;
  // La pile remet la sequence a 0 lors d'une reprise d'IV Index (net.c), a tout
  // moment : on la lit une seule fois.
  switch (plancher_preparer(&s_plancher, bt_mesh.seq, a_consommer, &seq, &nouveau)) {
    case PLANCHER_ADRESSE_SUIVANTE:
      if (changer_d_adresse(seq) == ESP_OK) esp_restart();
      return false;
    case PLANCHER_SAUVER: {
      const esp_err_t err = config_sauver_plancher(nouveau);
      if (err != ESP_OK) {
        ESP_LOGE(TAG, "plancher de sequence non sauve : %s", esp_err_to_name(err));
        return false;
      }
      plancher_sauve(&s_plancher, nouveau);
      break;
    }
    case PLANCHER_ENVOYER:
      break;
  }
  bt_mesh.seq = seq;
  return true;
}

static void tache_tx(void *arg) {
  (void)arg;
  message_tx_t m;
  for (;;) {
    if (xQueueReceive(s_tx, &m, portMAX_DELAY) != pdTRUE) continue;
    // Pas d'emission avant l'adhesion, ni pendant que Matter s'annonce en BLE : un
    // seul jeu d'annonces existe, et chacun arreterait celle de l'autre (plan 2).
    while (!s_pret || !s_emission_permise) vTaskDelay(pdMS_TO_TICKS(100));
    if (!preparer_sequence(m.repetitions)) {
      s_echecs++;
      vTaskDelay(ECART_TICKS);
      continue;
    }
    esp_ble_mesh_msg_ctx_t ctx = {
        .net_idx = NET_IDX,
        .app_idx = APP_IDX,
        .addr = m.dst,
        .send_ttl = TTL,
    };
    esp_err_t err = ESP_OK;
    for (uint8_t r = 0; r < m.repetitions; r++) {
      // La pile peut remettre la sequence a 0 a tout moment (reprise d'IV) : on
      // la remonte avant chaque envoi, et le minimum ne fait que monter.
      bt_mesh.seq = plancher_remonter(&s_plancher, bt_mesh.seq);
      const uint32_t seq_envoi = bt_mesh.seq;
      err = esp_ble_mesh_server_model_send_msg(&s_vendeur[0], &ctx, TELINK_OPCODE, TELINK_TAILLE, m.trame);
      if (err != ESP_OK) break;
      plancher_parti(&s_plancher, seq_envoi);
      if (r + 1 < m.repetitions) vTaskDelay(ECART_TICKS);
    }
    if (err == ESP_OK) {
      s_emis++;
    } else {
      s_echecs++;
      ESP_LOGW(TAG, "envoi vers 0x%04x refuse : %s", m.dst, esp_err_to_name(err));
    }
    vTaskDelay(ECART_TICKS);
  }
}

// --- API

esp_err_t mesh_demarrer(const amaran_config_t *cfg) {
  if (!cfg->cles_presentes) return ESP_ERR_INVALID_STATE;
  s_cfg = *cfg;
  plancher_init(&s_plancher, s_cfg.plancher_seq);
  if (plancher_epuise(&s_plancher)) {
    // Si la NVS refuse l'adresse, pas de redemarrage : il bouclerait.
    if (changer_d_adresse(s_cfg.plancher_seq) != ESP_OK) return ESP_FAIL;
    esp_restart();
  }
  s_tx = xQueueCreate(FILE_TX, sizeof(message_tx_t));
  if (!s_tx) return ESP_ERR_NO_MEM;
  esp_err_t err = crochet_demarrer(&s_cfg);
  if (err != ESP_OK) return err;
  // L'hote NimBLE doit etre synchronise : demarre par hote_ble_demarrer() dans le
  // firmware d'ecoute, par la pile Matter dans celui du pont.
  for (int i = 0; i < 100 && !hote_ble_pret(); i++) vTaskDelay(pdMS_TO_TICKS(100));
  if (!hote_ble_pret()) return ESP_ERR_TIMEOUT;
  esp_read_mac(s_uuid, ESP_MAC_BT);
  // Erreurs seules : le relais coupe ferait avertir la pile a chaque message qu'elle
  // ne relaie pas. Seconde barriere pour les cles : les avertissements qui en
  // impriment (AppKeyValExist, NetKeyValExist dans local.c) ne sont deja plus
  // compiles au niveau ERROR que le garde-fou ci-dessus impose.
  esp_log_level_set("BLE_MESH", ESP_LOG_ERROR);
  esp_ble_mesh_register_prov_callback(rappel_prov);
  esp_ble_mesh_register_config_server_callback(rappel_cfg_srv);
  esp_ble_mesh_register_custom_model_callback(rappel_modele);
  err = esp_ble_mesh_init(&s_prov, &s_composition);
  if (err != ESP_OK) return err;
  if (xTaskCreate(tache_tx, "amaran_tx", 3072, NULL, 5, NULL) != pdPASS) return ESP_ERR_NO_MEM;
  // Role noeud pose a la main, et non par esp_ble_mesh_node_prov_enable() : celle-ci
  // lance aussi la balise « non provisionne » (notre UUID) le temps que
  // bt_mesh_provision() passe, et amaran Desktop pourrait la voir (spec 5.1).
  // bt_mesh_provision() demarre ensuite le scan (bt_mesh_net_start, net.c), et le
  // rappel de fin d'adhesion arrive comme avant (bt_mesh_prov_complete).
  bt_mesh_atomic_set_bit(bt_mesh.flags, BLE_MESH_NODE);
  const int rc = bt_mesh_provision(s_cfg.netkey, NET_IDX, 0, s_cfg.iv, s_cfg.adresse, s_cfg.devkey);
  if (rc) {
    bt_mesh_atomic_clear_bit(bt_mesh.flags, BLE_MESH_NODE);
    ESP_LOGE(TAG, "bt_mesh_provision a echoue (%d)", rc);
    return ESP_FAIL;
  }
  return ESP_OK;
}

bool mesh_pret(void) { return s_pret; }

esp_err_t mesh_envoyer(uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions) {
  if (!s_tx) return ESP_ERR_INVALID_STATE;
  message_tx_t m = {.dst = dst, .repetitions = repetitions ? repetitions : 1};
  memcpy(m.trame, trame, TELINK_TAILLE);
  return xQueueSend(s_tx, &m, 0) == pdTRUE ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t mesh_file_evenements(void) { return crochet_file(); }

void mesh_ecoute_detaillee(bool oui) { crochet_ecoute_detaillee(oui); }

void mesh_lire_stats(mesh_stats_t *stats) {
  crochet_lire_stats(stats);
  stats->emis = s_emis;
  stats->echecs_emission = s_echecs;
}

uint32_t mesh_iv_courant(void) { return bt_mesh.iv_index; }

uint32_t mesh_sequence(void) { return bt_mesh.seq; }

uint32_t mesh_plancher(void) { return s_plancher.plancher_sauve; }

void mesh_autoriser_emission(bool oui) { s_emission_permise = oui; }

int mesh_iv_chercher(uint32_t max, uint32_t *trouve) { return crochet_chercher_iv(max, trouve); }
```

Dans `components/mesh/CMakeLists.txt`, remplacer `"crochet.c" "mesh_amaran.c"` par `"crochet.c" "plancher.c" "mesh_amaran.c"`.

- [ ] **Step 7 : le firmware d'écoute démarre lui-même l'hôte NimBLE.**

`ecoute/main/app_main.c` devient :

```c
// Firmware de reconnaissance (phase 0) : rejoint le reseau Bluetooth Mesh des
// lampes et donne une console pour les essais R1 a R6 (docs/BANC.md).
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "console_ecoute.h"
#include "hote_ble.h"
#include "mesh_amaran.h"

static const char *TAG = "ecoute";

void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS illisible : effacee (cles a recharger)");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  static amaran_config_t cfg;
  err = config_charger(&cfg);
  if (err != ESP_OK) {
    // Pas de boucle de redemarrage : la console reste la pour diagnostiquer.
    ESP_LOGE(TAG, "reglages illisibles (%s) : console seule", esp_err_to_name(err));
    cfg.cles_presentes = false;
  }
  if (cfg.cles_presentes) {
    err = hote_ble_demarrer();
    if (err == ESP_OK) err = mesh_demarrer(&cfg);
    if (err == ESP_OK) {
      journal_demarrer(&cfg);
    } else {
      ESP_LOGE(TAG, "Bluetooth Mesh non demarre : %s", esp_err_to_name(err));
    }
  } else {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
  }
  console_demarrer(&cfg);
}
```

Dans `ecoute/sdkconfig.defaults`, après la ligne `CONFIG_BLE_MESH_GATT_PROXY_SERVER=n`, ajouter :

```
# Ni proxy ni PB-GATT : la pile Mesh n'enregistre aucun service GATT. Obligatoire
# dans le firmware du pont, ou l'hote NimBLE appartient a Matter.
CONFIG_BLE_MESH_PROXY=n
```

et après la ligne `CONFIG_BT_NIMBLE_50_FEATURE_SUPPORT=n` :

```
# Journal NimBLE aux avertissements : au banc, 557 lignes « GAP procedure » a l'INFO.
CONFIG_BT_NIMBLE_LOG_LEVEL_WARNING=y
```

- [ ] **Step 8 : tout vérifier.**

Run :

```bash
sh tests/hote/lancer.sh && export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && \
cd ecoute && rm -f sdkconfig && idf.py build && cd .. && bash outils/check_sdkconfig.sh
```

Expected : `tests hote : tout est vert` ; `Project build complete.` avec pour seuls avertissements les deux d'ESP-IDF déjà connus (`adapter.c:2372` et `:2407`, fonctions inutilisées) ; `ok : tous les symboles existent` et `ok : niveau 1`. (`rm -f sdkconfig` : les nouveaux réglages de `sdkconfig.defaults` ne s'appliquent qu'à un `sdkconfig` régénéré.)

- [ ] **Step 9 : commit.**

```bash
git add components/mesh tests/hote ecoute/main/app_main.c ecoute/sdkconfig.defaults
git commit -m "$(printf "Sortir les regles du compteur de sequence en module pur et entrer dans le reseau sans annonce\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 3: Crochet : doublons et rejeux écartés, balises authentifiées

**Files:**
- Modify: `components/mesh/include/crochet_tri.h`, `components/mesh/crochet_tri.c`, `tests/hote/test_crochet_tri.c`
- Modify: `components/mesh/include/mesh_amaran.h`, `components/mesh/crochet.c`, `components/mesh/autotest.c`

**Interfaces:**
- Consumes : `bt_mesh_secure_beacon_auth`, `bt_mesh_secure_beacon_key` (`crypto.h` interne) ; `sub->keys[0].beacon` (`net.h`).
- Produces :
  - `tri_balise_t.auth[8]` ; `tri_dernier_t` ; `bool tri_plus_recent(const tri_dernier_t *d, uint32_t iv, uint32_t seq);` ; `void tri_retenir(tri_dernier_t *d, uint32_t iv, uint32_t seq);`
  - `mesh_evenement_t.seq` (SEQ du message) ; `iv` rempli aussi pour `MESH_EV_ETAT_LAMPE` et `MESH_EV_ACCES` ;
  - `mesh_stats_t.doublons`, `mesh_stats_t.balises_fausses`.

Pourquoi (revue finale du plan 1) :
- chaque réponse d'une lampe arrive 1 à 3 fois (copies réseau, banc du 30/09) : le crochet ne garde que le premier message de chaque (IV Index, SEQ) par lampe, et écarte aussi un rejeu (SEQ plus ancien) ; retenu en RAM seulement ;
- une balise « de notre réseau » était reconnue à son seul NetID, qui se recopie : l'IV annoncé n'est cru que si l'authentification, calculée avec la BeaconKey du réseau, est juste (comme la pile) ;
- l'autotest vérifie en plus la BeaconKey (exemple 8.2.6 de la spec Mesh) et l'authentification de la balise 8.4.3 (valeurs confirmées par BlueZ `unit/test-mesh-crypto.c` et recalculées en Python).

- [ ] **Step 1 : les tests du tri.**

Dans `tests/hote/test_crochet_tri.c`, dans `test_balise()`, remplacer :

```c
  const uint8_t net_id[8] = {0x3E, 0xCA, 0xFF, 0x67, 0x2F, 0x67, 0x33, 0x70};
  tri_balise_t bal;
  VERIFIE(tri_lire_balise(b, 22, &bal) && bal.iv_index == 0x12345678 && bal.flags == 0 &&
              memcmp(bal.net_id, net_id, 8) == 0,
          "balise 8.4.3");
```

par :

```c
  const uint8_t net_id[8] = {0x3E, 0xCA, 0xFF, 0x67, 0x2F, 0x67, 0x33, 0x70};
  const uint8_t auth[8] = {0x8E, 0xA2, 0x61, 0x58, 0x2F, 0x36, 0x4F, 0x6F};
  tri_balise_t bal;
  VERIFIE(tri_lire_balise(b, 22, &bal) && bal.iv_index == 0x12345678 && bal.flags == 0 &&
              memcmp(bal.net_id, net_id, 8) == 0,
          "balise 8.4.3");
  VERIFIE(memcmp(bal.auth, auth, 8) == 0, "balise 8.4.3 : authentification lue");
```

et remplacer :

```c
int main(void) {
  test_entete();
```

par :

```c
static void test_plus_recent(void) {
  tri_dernier_t d = {0};
  VERIFIE(tri_plus_recent(&d, 0, 5), "premier message retenu");
  tri_retenir(&d, 0, 5);
  VERIFIE(!tri_plus_recent(&d, 0, 5), "copie reseau (meme SEQ) ecartee");
  VERIFIE(!tri_plus_recent(&d, 0, 4), "rejeu (SEQ plus ancien) ecarte");
  VERIFIE(tri_plus_recent(&d, 0, 6), "SEQ suivant retenu");
  VERIFIE(tri_plus_recent(&d, 1, 0), "IV Index suivant : SEQ repart de 0");
  tri_retenir(&d, 1, 0);
  VERIFIE(!tri_plus_recent(&d, 0, 100), "IV Index plus ancien ecarte");
}

int main(void) {
  test_entete();
  test_plus_recent();
```

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation (`tri_dernier_t` inconnu, pas de champ `auth`).

- [ ] **Step 2 : le tri.**

Dans `components/mesh/include/crochet_tri.h`, remplacer :

```c
typedef struct {
  uint8_t flags;
  uint8_t net_id[8];
  uint32_t iv_index;
} tri_balise_t;
```

par :

```c
typedef struct {
  uint8_t flags;
  uint8_t net_id[8];
  uint32_t iv_index;
  uint8_t auth[8];  // a verifier avec la BeaconKey du reseau avant de croire l'IV
} tri_balise_t;

// Dernier message retenu d'une source : (IV Index, SEQ).
typedef struct {
  bool connu;
  uint32_t iv;
  uint32_t seq;
} tri_dernier_t;
```

et, après la déclaration de `tri_lire_balise`, ajouter :

```c
// Vrai si (iv, seq) est plus recent que le dernier message retenu de la source :
// une copie reseau (meme SEQ) ou un rejeu (SEQ plus ancien) rendent faux.
bool tri_plus_recent(const tri_dernier_t *d, uint32_t iv, uint32_t seq);
void tri_retenir(tri_dernier_t *d, uint32_t iv, uint32_t seq);
```

Dans `components/mesh/crochet_tri.c`, dans `tri_lire_balise`, juste avant son `return true;`, ajouter `memcpy(balise->auth, b + 14, 8);`, puis à la fin du fichier :

```c
bool tri_plus_recent(const tri_dernier_t *d, uint32_t iv, uint32_t seq) {
  if (!d->connu || iv > d->iv) return true;
  return iv == d->iv && seq > d->seq;
}

void tri_retenir(tri_dernier_t *d, uint32_t iv, uint32_t seq) {
  d->connu = true;
  d->iv = iv;
  d->seq = seq;
}
```

Run: `sh tests/hote/lancer.sh`
Expected : `crochet_tri : 21 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 3 : événements et compteurs.**

Dans `components/mesh/include/mesh_amaran.h`, dans `mesh_evenement_t`, remplacer la ligne du champ `iv` par :

```c
  uint32_t iv;        // IV Index du message, de la balise, ou le nouveau (MESH_EV_IV_CHANGE)
  uint32_t seq;       // SEQ du message (MESH_EV_ETAT_LAMPE, MESH_EV_ACCES)
```

Dans `mesh_stats_t`, après la ligne du champ `etats_lampes`, ajouter :

```c
  uint32_t doublons;          // copies reseau et rejeux ecartes (meme SEQ, ou plus ancien)
```

et après la ligne du champ `balises_autres` :

```c
  uint32_t balises_fausses;   // NetID du reseau, mais authentification fausse : ignorees
```

- [ ] **Step 4 : le crochet.**

Dans `components/mesh/crochet.c` :

1. Remplacer `#include "esp_timer.h"` par :

```c
#include "esp_idf_version.h"
#include "esp_timer.h"
```

2. Remplacer la ligne `#include "crypto.h"  // bt_mesh_net_obfuscate, bt_mesh_ccm_decrypt_raw_key, bt_mesh_app_decrypt` par :

```c
#include "crypto.h"  // bt_mesh_net_obfuscate, bt_mesh_ccm_decrypt_raw_key, bt_mesh_app_decrypt, bt_mesh_secure_beacon_auth
```

3. Juste après `#include "crochet_tri.h"`, ajouter :

```c

// --wrap et en-tetes internes : verifies pour ESP-IDF v5.5.4 seulement.
#if ESP_IDF_VERSION != ESP_IDF_VERSION_VAL(5, 5, 4)
#error "components/mesh depend des internes d'ESP-IDF v5.5.4 : a reverifier avant de changer de version"
#endif
```

4. Après la ligne `static uint32_t s_iv_connu;`, ajouter :

```c
// Dernier message retenu de chaque lampe : ecarte les copies reseau (1 a 3 par
// reponse au banc) et les rejeux. En RAM seulement : repart a zero au demarrage.
static tri_dernier_t s_dernier[AMARAN_LAMPES_MAX];
```

5. Remplacer l'en-tête de `traiter_acces` et le début de son corps :

```c
static void traiter_acces(const tri_entete_t *e, const uint8_t *acces, size_t n) {
  s_st.acces_dechiffres++;
  mesh_evenement_t ev = {
      .type = MESH_EV_ACCES,
      .quand_us = esp_timer_get_time(),
      .src = e->src,
      .dst = e->dst,
      .lampe = -1,
      .len = (uint8_t)n,
  };
  memcpy(ev.acces, acces, n);
  uint8_t trame[TELINK_TAILLE];
  const int l = tri_etat_lampe(e->src, acces, n, s_lampes, AMARAN_LAMPES_MAX, trame);
  if (l >= 0) {
    ev.type = MESH_EV_ETAT_LAMPE;
```

par :

```c
static void traiter_acces(const tri_entete_t *e, uint32_t iv, const uint8_t *acces, size_t n) {
  s_st.acces_dechiffres++;
  mesh_evenement_t ev = {
      .type = MESH_EV_ACCES,
      .quand_us = esp_timer_get_time(),
      .src = e->src,
      .dst = e->dst,
      .lampe = -1,
      .len = (uint8_t)n,
      .iv = iv,
      .seq = e->seq,
  };
  memcpy(ev.acces, acces, n);
  uint8_t trame[TELINK_TAILLE];
  const int l = tri_etat_lampe(e->src, acces, n, s_lampes, AMARAN_LAMPES_MAX, trame);
  if (l >= 0) {
    if (!tri_plus_recent(&s_dernier[l], iv, e->seq)) {
      s_st.doublons++;
      return;
    }
    tri_retenir(&s_dernier[l], iv, e->seq);
    ev.type = MESH_EV_ETAT_LAMPE;
```

6. Dans `traiter()`, remplacer `traiter_acces(&e, acces, na);` par `traiter_acces(&e, iv, acces, na);`.

7. Dans `__wrap_bt_mesh_beacon_recv`, remplacer :

```c
    if (sub && sub->net_idx != BLE_MESH_KEY_UNUSED && memcmp(sub->keys[0].net_id, b.net_id, sizeof(b.net_id)) == 0) {
      s_st.balises_notres++;
```

par :

```c
    const bool notre_id =
        sub && sub->net_idx != BLE_MESH_KEY_UNUSED && memcmp(sub->keys[0].net_id, b.net_id, sizeof(b.net_id)) == 0;
    // Le NetID seul se recopie : on ne croit l'IV annonce que si l'authentification,
    // calculee avec la BeaconKey du reseau, est juste (la pile fait de meme).
    uint8_t auth[8];
    const bool authentique = notre_id &&
                             bt_mesh_secure_beacon_auth(sub->keys[0].beacon, b.flags, b.net_id, b.iv_index, auth) == 0 &&
                             memcmp(auth, b.auth, sizeof(auth)) == 0;
    if (notre_id && !authentique) {
      s_st.balises_fausses++;
    } else if (authentique) {
      s_st.balises_notres++;
```

(la branche `} else { s_st.balises_autres++; }` qui suit reste telle quelle.)

- [ ] **Step 5 : l'autotest.**

Dans `components/mesh/autotest.c`, remplacer la ligne d'include de `crypto.h` par :

```c
#include "crypto.h"  // bt_mesh_k2, bt_mesh_k3, bt_mesh_app_id, bt_mesh_secure_beacon_key, bt_mesh_secure_beacon_auth
```

et, juste après la ligne `verifie(bt_mesh_k3(netkey, net_id) == 0 && memcmp(net_id, b.net_id, 8) == 0, "8.4.3 : NetID (k3)");`, ajouter :

```c
  // 8.2.6 : BeaconKey ; 8.4.3 : authentification de la balise, comme le crochet.
  uint8_t cle_balise[16], auth[8];
  hexa("5423d967da639a99cb02231a83f7d254", attendu, 16);
  verifie(bt_mesh_secure_beacon_key(netkey, cle_balise) == 0 && memcmp(cle_balise, attendu, 16) == 0,
          "8.2.6 : cle de balise");
  verifie(bt_mesh_secure_beacon_auth(cle_balise, b.flags, b.net_id, b.iv_index, auth) == 0 &&
              memcmp(auth, b.auth, 8) == 0,
          "8.4.3 : authentification de la balise");
```

- [ ] **Step 6 : compiler.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build`
Expected : `Project build complete.`, aucun nouvel avertissement (seulement les deux connus d'`adapter.c`).

- [ ] **Step 7 : commit.**

```bash
git add components/mesh tests/hote/test_crochet_tri.c
git commit -m "$(printf "Ecarter les doublons et rejeux des lampes, et n'en croire les balises qu'authentifiees\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 4: La console `mesh` partagée, et le diagnostic du Bluetooth Mesh

**Files:**
- Create: `components/mesh/include/mesh_console.h`, `components/mesh/mesh_console.c`
- Create: `components/mesh/include/diagnostic.h`, `components/mesh/diagnostic.c`, `tests/hote/test_diagnostic.c`
- Modify: `components/mesh/CMakeLists.txt`, `ecoute/main/console_ecoute.c` (fichier entier), `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : tout `mesh_amaran.h` et `config_amaran.h` ; `mesh_stats_t.doublons`, `mesh_stats_t.balises_fausses` (Task 3).
- Produces :
  - `void mesh_console_init(amaran_config_t *cfg, const char *const *taches, size_t nb_taches);`
  - `int mesh_console_commande(int argc, char **argv);` (la commande `mesh`) ; `int mesh_console_taches(int argc, char **argv);` (la commande `taches`) ;
  - `void mesh_console_redemarrer(void);` ; `void mesh_console_evenement(const mesh_evenement_t *ev, bool etats);` (imprime un événement du crochet, et sauve l'IV Index qui change) ;
  - `diagnostic_t`, `diagnostic_ecarts_t`, `diagnostic_suivi_t`, `DIAGNOSTIC_FENETRE_MS` ; `diagnostic_mesh()`, `diagnostic_suivre()`, `diagnostic_texte()` (spec 7.3).

Pourquoi : le firmware du pont (Task 7) a la même commande `mesh` que le firmware d'écoute (spec 7.5) ; la copier ferait deux versions de ~250 lignes. Elle passe dans le composant `mesh`, et le firmware d'écoute ne garde que ce qui lui est propre (`lampe` en trames brutes, `groupe`, le journal). Le diagnostic 7.3 est pur et testé : clés absentes tout de suite ; « pas entré dans le réseau » seulement au bout d'une fenêtre de 2 min (sinon rouge à chaque démarrage) ; l'alerte tombe dès l'entrée ; clés périmées et IV faux se jugent aux écarts de chaque fenêtre.

- [ ] **Step 1 : les tests du diagnostic.**

`tests/hote/test_diagnostic.c` :

```c
// Tests sur le Mac du diagnostic du Bluetooth Mesh (spec 7.3).
// Lancer : sh tests/hote/lancer.sh
#include <string.h>

#include "diagnostic.h"
#include "unite.h"

static void test_causes(void) {
  const diagnostic_ecarts_t calme = {0, 0, 0, 0}, sain = {40, 40, 0, 12}, etranger = {30, 0, 0, 0},
                            iv_faux = {30, 30, 30, 0}, melange = {30, 30, 5, 3};
  VERIFIE(diagnostic_mesh(false, false, &sain) == DIAG_CLES_ABSENTES, "cles absentes d'abord");
  VERIFIE(diagnostic_mesh(true, false, &sain) == DIAG_PAS_ENTRE, "pas entre dans le reseau");
  VERIFIE(diagnostic_mesh(true, true, &sain) == DIAG_OK, "trafic sain");
  VERIFIE(diagnostic_mesh(true, true, &calme) == DIAG_OK, "aucune annonce : rien a conclure");
  VERIFIE(diagnostic_mesh(true, true, &etranger) == DIAG_CLES_PERIMEES, "seulement d'autres NID : cles perimees");
  VERIFIE(diagnostic_mesh(true, true, &iv_faux) == DIAG_IV_FAUX, "NetMIC faux sans dechiffrement : IV faux");
  VERIFIE(diagnostic_mesh(true, true, &melange) == DIAG_OK, "quelques NetMIC faux mais du dechiffre : ok");
  VERIFIE(strstr(diagnostic_texte(DIAG_IV_FAUX), "mesh iv") != NULL, "le texte donne le remede");
  VERIFIE(strstr(diagnostic_texte(DIAG_CLES_ABSENTES), "cles_amaran.py") != NULL, "remede des cles absentes");
}

static void test_suivi(void) {
  diagnostic_suivi_t s = {0};
  diagnostic_ecarts_t c = {0, 0, 0, 0};
  // Demarrage normal : pas encore entre, mais pas d'alerte avant 2 min.
  VERIFIE(!diagnostic_suivre(&s, true, false, &c, 0) && s.etat == DIAG_OK, "pas de rouge au demarrage");
  VERIFIE(!diagnostic_suivre(&s, true, true, &c, 3000) && s.etat == DIAG_OK, "entre en 3 s : rien a dire");
  c = (diagnostic_ecarts_t){100, 100, 0, 30};
  VERIFIE(!diagnostic_suivre(&s, true, true, &c, 120000) && s.etat == DIAG_OK, "fenetre saine");
  // Reseau recree dans amaran Desktop : que des NID etrangers pendant 2 min.
  c.annonces += 50;
  VERIFIE(!diagnostic_suivre(&s, true, true, &c, 200000), "rien avant la fin de la fenetre");
  VERIFIE(diagnostic_suivre(&s, true, true, &c, 240000) && s.etat == DIAG_CLES_PERIMEES, "cles perimees");
  // IV Index faux : notre NID, NetMIC faux, rien de dechiffre.
  c.annonces += 20;
  c.nid_reconnu += 20;
  c.netmic_faux += 20;
  VERIFIE(diagnostic_suivre(&s, true, true, &c, 360000) && s.etat == DIAG_IV_FAUX, "IV faux");
  c.annonces += 20;
  c.nid_reconnu += 20;
  c.acces_dechiffres += 8;
  VERIFIE(diagnostic_suivre(&s, true, true, &c, 480000) && s.etat == DIAG_OK, "retour a la normale");
  // Cles oubliees : tout de suite.
  VERIFIE(diagnostic_suivre(&s, false, false, &c, 481000) && s.etat == DIAG_CLES_ABSENTES, "cles absentes aussitot");
  // Cles rechargees, carte redemarree : pas entre au bout d'une fenetre.
  diagnostic_suivi_t r = {0};
  VERIFIE(!diagnostic_suivre(&r, true, false, &c, 0), "nouveau demarrage");
  VERIFIE(diagnostic_suivre(&r, true, false, &c, 120000) && r.etat == DIAG_PAS_ENTRE, "pas entre en 2 min");
  VERIFIE(diagnostic_suivre(&r, true, true, &c, 121000) && r.etat == DIAG_OK, "entre : l'alerte tombe aussitot");
  // Horloge de 32 bits qui deborde : la fenetre se mesure en ecart non signe.
  diagnostic_suivi_t w = {0};
  VERIFIE(!diagnostic_suivre(&w, true, false, &c, 0xFFFFF000u), "depart pres du debordement");
  VERIFIE(!diagnostic_suivre(&w, true, false, &c, 0x00001000u), "8 s plus tard : pas encore");
  VERIFIE(diagnostic_suivre(&w, true, false, &c, 0xFFFFF000u + DIAGNOSTIC_FENETRE_MS) && w.etat == DIAG_PAS_ENTRE,
          "fenetre finie de l'autre cote de 0");
}

int main(void) {
  test_causes();
  test_suivi();
  return bilan("diagnostic");
}
```

Dans `tests/hote/lancer.sh`, avant `echo "tests hote : tout est vert"`, ajouter :

```sh
compiler_et_lancer test_diagnostic components/mesh/diagnostic.c tests/hote/test_diagnostic.c
```

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation (`diagnostic.h` introuvable).

- [ ] **Step 2 : le diagnostic.**

`components/mesh/include/diagnostic.h` :

```c
// Diagnostic du Bluetooth Mesh (spec 7.3), en C pur : a partir des compteurs du
// crochet sur une fenetre (en general 2 min), la cause probable d'une panne.
// Teste sur le Mac (tests/hote/test_diagnostic.c).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  DIAG_OK,
  DIAG_CLES_ABSENTES,  // jamais chargees, ou `mesh oublie`
  DIAG_PAS_ENTRE,      // cles la, mais pas (encore) dans le reseau
  DIAG_CLES_PERIMEES,  // des annonces Mesh, aucune de notre NID : reseau recree dans amaran Desktop ?
  DIAG_IV_FAUX,        // notre NID, NetMIC faux, rien de dechiffre : IV Index faux
} diagnostic_t;

#define DIAGNOSTIC_FENETRE_MS 120000u  // 2 min (spec 7.3)

// Compteurs du crochet (cumules), ou leurs ecarts sur une fenetre.
typedef struct {
  uint32_t annonces, nid_reconnu, netmic_faux, acces_dechiffres;
} diagnostic_ecarts_t;

// Cause probable, d'apres les ecarts de la fenetre ecoulee.
diagnostic_t diagnostic_mesh(bool cles, bool entre, const diagnostic_ecarts_t *e);

typedef struct {
  bool lance;
  uint32_t debut_ms;
  diagnostic_ecarts_t avant;  // compteurs au debut de la fenetre
  diagnostic_t etat;
} diagnostic_suivi_t;

// A appeler souvent (tache lampes) avec les compteurs cumules. Cles absentes :
// tout de suite. Pas entre dans le reseau : seulement au bout d'une fenetre
// (sinon rouge a chaque demarrage). Entree faite : l'alerte tombe aussitot. Le
// reste se juge aux ecarts de chaque fenetre de 2 min. Vrai si l'etat change.
bool diagnostic_suivre(diagnostic_suivi_t *s, bool cles, bool entre, const diagnostic_ecarts_t *compteurs,
                       uint32_t maintenant_ms);
// Texte de la console : cause et remede (spec 7.3).
const char *diagnostic_texte(diagnostic_t d);

#ifdef __cplusplus
}
#endif
```

`components/mesh/diagnostic.c` :

```c
// Diagnostic du Bluetooth Mesh (voir diagnostic.h).
#include "diagnostic.h"

diagnostic_t diagnostic_mesh(bool cles, bool entre, const diagnostic_ecarts_t *e) {
  if (!cles) return DIAG_CLES_ABSENTES;
  if (!entre) return DIAG_PAS_ENTRE;
  if (e->annonces > 0 && e->nid_reconnu == 0) return DIAG_CLES_PERIMEES;
  if (e->netmic_faux > 0 && e->acces_dechiffres == 0) return DIAG_IV_FAUX;
  return DIAG_OK;
}

bool diagnostic_suivre(diagnostic_suivi_t *s, bool cles, bool entre, const diagnostic_ecarts_t *compteurs,
                       uint32_t maintenant_ms) {
  if (!s->lance) {
    s->lance = true;
    s->debut_ms = maintenant_ms;
    s->avant = *compteurs;
    s->etat = DIAG_OK;
  }
  diagnostic_t d = s->etat;
  const bool fenetre_finie = maintenant_ms - s->debut_ms >= DIAGNOSTIC_FENETRE_MS;
  if (!cles) {
    d = DIAG_CLES_ABSENTES;
  } else if (entre) {
    if (s->etat == DIAG_CLES_ABSENTES || s->etat == DIAG_PAS_ENTRE) d = DIAG_OK;  // vient d'entrer
    if (fenetre_finie) {
      const diagnostic_ecarts_t e = {
          compteurs->annonces - s->avant.annonces,
          compteurs->nid_reconnu - s->avant.nid_reconnu,
          compteurs->netmic_faux - s->avant.netmic_faux,
          compteurs->acces_dechiffres - s->avant.acces_dechiffres,
      };
      d = diagnostic_mesh(true, true, &e);
    }
  } else if (fenetre_finie) {
    d = DIAG_PAS_ENTRE;
  }
  if (fenetre_finie) {
    s->debut_ms = maintenant_ms;
    s->avant = *compteurs;
  }
  if (d == s->etat) return false;
  s->etat = d;
  return true;
}

const char *diagnostic_texte(diagnostic_t d) {
  switch (d) {
    case DIAG_OK:
      return "ok";
    case DIAG_CLES_ABSENTES:
      return "cles absentes : lancer outils/cles_amaran.py";
    case DIAG_PAS_ENTRE:
      return "pas entre dans le reseau des lampes (mise en service Matter faite ?)";
    case DIAG_CLES_PERIMEES:
      return "aucun message de notre reseau depuis 2 min : cles perimees ? (recharger avec outils/cles_amaran.py)";
    case DIAG_IV_FAUX:
      return "NetMIC faux sans message dechiffre : IV Index faux ? (mesh iv, ou mesh iv cherche)";
  }
  return "?";
}
```

Run: `sh tests/hote/lancer.sh`
Expected : `diagnostic : 23 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 3 : la console partagée.**

`components/mesh/include/mesh_console.h` :

```c
// Commandes de console communes aux deux firmwares : `mesh` et `taches`, et
// impression des evenements du crochet (spec 7.5).
#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "config_amaran.h"
#include "mesh_amaran.h"

#ifdef __cplusplus
extern "C" {
#endif

// cfg reste la propriete de l'appelant (la console le lit ; l'IV y est mis a
// jour). taches : les noms de taches que `taches` examine.
void mesh_console_init(amaran_config_t *cfg, const char *const *taches, size_t nb_taches);
// La commande `mesh` : etat sans argument ; cles, lampe, iv, adresse, oublie,
// ecoute, autotest.
int mesh_console_commande(int argc, char **argv);
// La commande `taches` : pile libre au plus bas de chaque tache, et le tas.
int mesh_console_taches(int argc, char **argv);
// Message, vidage de la sortie, puis esp_restart().
void mesh_console_redemarrer(void);
// Imprime un evenement du crochet ; un changement d'IV Index est aussi sauve en
// NVS. etats : imprimer aussi les etats des lampes (sinon, seulement le reste).
void mesh_console_evenement(const mesh_evenement_t *ev, bool etats);

#ifdef __cplusplus
}
#endif
```

`components/mesh/mesh_console.c` (repris de `ecoute/main/console_ecoute.c`, avec les doublons écartés et les balises fausses dans l'état) :

```c
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
```

Dans `components/mesh/CMakeLists.txt`, remplacer `"plancher.c" "mesh_amaran.c"` par `"plancher.c" "mesh_amaran.c" "mesh_console.c" "diagnostic.c"`, et `PRIV_REQUIRES nvs_flash mbedtls bt esp_timer` par `PRIV_REQUIRES nvs_flash mbedtls bt esp_timer console`.

- [ ] **Step 4 : la console du firmware d'écoute s'appuie dessus.**

`ecoute/main/console_ecoute.c` devient :

```c
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
       .help = "etat ; mesh cles|lampe|iv|adresse|oublie|ecoute|autotest ...",
       .func = mesh_console_commande},
      {.command = "lampe", .help = "lampe <1-2> releve|on|off|niveau <0-1000>", .func = cmd_lampe},
      {.command = "groupe", .help = "groupe releve : demande d'etat au groupe All (0xC000)", .func = cmd_groupe},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = mesh_console_taches},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
```

- [ ] **Step 5 : compiler.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build`
Expected : `Project build complete.`, aucun nouvel avertissement.

- [ ] **Step 6 : commit.**

```bash
git add components/mesh ecoute/main/console_ecoute.c tests/hote
git commit -m "$(printf "Partager la console mesh entre les deux firmwares, et diagnostiquer le Bluetooth Mesh\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 5: Au banc : le firmware d'écoute après les Tasks 2 à 4 (Claude et Djoko)

**Qui :** Claude, le contrôleur, avec Djoko présent. **Pas de sous-agent** : on flashe et on ouvre un port série.

**Files:**
- Modify: `docs/BANC.md` (résultats)

**Interfaces:**
- Consumes : le firmware d'écoute des Tasks 2 à 4 ; `outils/console.py` (plan 1). La C6 du pont porte encore le firmware d'écoute du plan 1, avec les clés en NVS.
- Produces : le constat, sur la carte, que l'entrée dans le réseau sans balise « non provisionné », le plancher de séquence en module, l'écart des doublons, les balises authentifiées et la console partagée marchent, avant d'y ajouter Matter.

Pourquoi : les Tasks 2 à 4 touchent l'adhésion, le compteur de séquence et le crochet. Une régression serait bien plus dure à trouver avec Matter et Thread sur la même radio. Le contrôle n'émet que des demandes d'état : les lampes ne changent pas.

- [ ] **Step 1 : tests et compilation.**

Run: `sh tests/hote/lancer.sh && export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build | tail -2 && cd ..`
Expected : `tests hote : tout est vert`, puis `Project build complete.`

- [ ] **Step 2 : reconnaître la carte.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && python -m serial.tools.list_ports -v`
La C6 du pont est celle dont le champ `SER=` est le numéro noté hors du dépôt (jamais écrit dans le dépôt). Jamais la C6 du maillage Thread BenQ, jamais un écran LG (eux aussi en `usbmodem`). Au moindre doute : s'arrêter et demander à Djoko.

- [ ] **Step 3 : flasher, avec l'accord de Djoko.**

Demander à Djoko : « Je flashe le firmware d'écoute à jour sur la C6 du pont (`<port>`) ? ». Après son accord :

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py -p <port> flash && cd ..`
Expected : `Hard resetting via RTS pin...`. La NVS n'est pas effacée : clés, adresse, IV Index et plancher de séquence restent.

- [ ] **Step 4 : contrôle sans émission.**

Run: `python3 outils/console.py --port <port> "mesh autotest" "mesh" "@30" "mesh" "taches"`
Expected :
- 11 lignes `ok`, dont `8.2.6 : cle de balise` et `8.4.3 : authentification de la balise`, puis `autotest : 0 echec(s)` ;
- `mesh pret : oui` ; l'adresse et les empreintes des clés sont celles du banc R (journaux de `logs/`) ;
- au second `mesh` : `balises : notres` plus grand que 0, et `fausses 0` ;
- `taches` : aucune tâche sous 512 o de pile libre.

`notres 0` avec `fausses` plus grand que 0 : l'authentification des balises est fausse. S'arrêter (superpowers:systematic-debugging) et corriger avant la Task 6.

- [ ] **Step 5 : R2 abrégé, Djoko présent.**

Prévenir Djoko : dix demandes d'état, les lampes ne changent pas.

Run: `python3 outils/console.py --port <port> "lampe 1 releve" "@2" "lampe 1 releve" "@2" "lampe 1 releve" "@2" "lampe 1 releve" "@2" "lampe 1 releve" "@2" "lampe 2 releve" "@2" "lampe 2 releve" "@2" "lampe 2 releve" "@2" "lampe 2 releve" "@2" "lampe 2 releve" "@2" "mesh"`
Expected :
- exactement une ligne `etat lampe <n>` par demande, 10 en tout : les copies réseau sont écartées ;
- `mesh` : `(+N doublons ecartes)` avec N plus grand que 0 (au banc R, 16 réponses sur 20 arrivaient en double) ; `emission : ... 0 refus` ; `NetMIC faux` inchangé.

Une réponse manquante, ou deux lignes pour une même demande : s'arrêter et chercher la cause.

- [ ] **Step 6 : consigner.**

Dans `docs/BANC.md`, à la fin de la section `## Résultats`, ajouter, avec les valeurs relevées :

```markdown
### Plan 2 : contrôle du firmware d'écoute (Tasks 2 à 4)

<date>, firmware `ecoute` du commit `<commit>` :
- autotest : 11 vérifications, 0 échec (BeaconKey 8.2.6 et authentification de balise 8.4.3 compris) ;
- balises des lampes authentifiées : `<n>` en 30 s, 0 fausse ;
- R2 abrégé : 10 réponses sur 10, une ligne chacune ; `<n>` doublons écartés ;
- marges : pile libre la plus basse `<tâche>` `<n>` o ; tas libre au plus bas `<n>` o.
```

Run: `git add docs/BANC.md && git commit -m "$(printf "Consigner le controle du firmware d'ecoute apres les taches 2 a 4\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"`

---

### Task 6: Le firmware du pont, côté Matter

**Files:**
- Create: `firmware/CMakeLists.txt`, `firmware/partitions.csv`, `firmware/sdkconfig.defaults`
- Create: `firmware/main/CMakeLists.txt`, `firmware/main/CHIPProjectConfig.h`
- Create: `firmware/main/pont_matter.h`, `firmware/main/pont_matter.cpp`, `firmware/main/app_main.cpp` (provisoire)
- Create: `firmware/dependencies.lock` (écrit par la première compilation, à garder dans le dépôt)
- Modify: `outils/check_sdkconfig.sh` (fichier entier)

**Interfaces:**
- Consumes :
  - `lampes.h` (Task 1) : `LAMPES_MAX`, `lampe_etat_t`, `lampes_niveau_vers_intensite()`, `lampes_intensite_vers_niveau()` ;
  - `mesh_amaran.h` (Task 2) : `void mesh_autoriser_emission(bool oui);` ;
  - `config_amaran.h` (plan 1) : `amaran_config_t` (`lampes[i].adresse`, `.mac`, `.nom`), `config_charger()`.
- Produces (`firmware/main/pont_matter.h`) :
  - `typedef void (*pont_ordre_cb_t)(int lampe, const bool *marche, const uint16_t *intensite);`
  - `esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre);`
  - `void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable);`
  - `bool pont_appaire(void);`, `bool pont_ble_annonce(void);`, `bool pont_thread_attache(void);`
  - `void pont_afficher(void);` (la commande `matter`), `void pont_desappairer(void);`
  - `PONT_PLAFOND_ABONNEMENT_S` (20), `PONT_NIVEAU_PLANCHER` (4).

Pourquoi (recherche esp-matter et pont Halo, `~/Documents/Dev/esp32/benq`, commit `3f82f76`) :
- **la pile Matter possède l'hôte NimBLE** : `esp_matter::start()` le démarre ; `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING=n` le garde après la mise en service (sinon il est libéré et le Mesh meurt). Pas de `blemesh_platform` (amendement 3) ;
- **endpoints fixes** : 0 nœud, 1 agrégateur, 2 et 3 les lampes, toujours les deux et dans cet ordre, donc des numéros stables (6.1). UniqueID = MAC, NodeLabel = nom de la base. Un emplacement sans lampe n'est jamais joignable ;
- **l'état des lampes part par `attribute::report()`** : il prend lui-même le verrou de la pile, et ne rappelle pas l'application. Donc aucun écho, sans marquage (6.4, 4.3 ; amendement 4) ;
- **les ordres des contrôleurs arrivent en `POST_UPDATE`** sur OnOff et CurrentLevel des EP2 et EP3. Ceux des 2 premières secondes sont ignorés : c'est la pile qui pose ses valeurs (leçon du Halo) ;
- **`StartUpOnOff` et `StartUpCurrentLevel` nuls** : les défauts d'esp-matter (0) éteindraient les lampes à chaque démarrage (6.5) ;
- **CurrentLevel publié au moins à 4** (leçon du Halo : en dessous, Maison montre une lampe allumée à fond). Transitions de LevelControl ignorées (`IGNORE_LEVEL_CONTROL_CLUSTER_TRANSITION`) : chaque pas partirait vers la lampe ;
- **abonnements plafonnés à 20 s** (6.6) par un `ReadHandler::ApplicationCallback`, comme le Halo ;
- **identité** : fiche dans `CHIPProjectConfig.h` ; série `AMARAN-<MAC>` écrite dans `chip-factory`/`serial-num` avant le démarrage ; version `0.1.0-<commit>[-dirty]` ;
- **codes d'appairage de test du SDK**, VID/PID `0xFFF1`/`0x8000`, comme le Halo : Maison les accepte, avec l'avertissement « non certifié » (amendement 5) ;
- **dernière fabrique retirée** depuis Maison : la fenêtre de mise en service se rouvre (DNS-SD, 300 s), comme le faisait la bibliothèque Arduino du Halo ;
- **rôle Thread lu dans les événements** `OPENTHREAD_EVENT_ROLE_CHANGED` : jamais le verrou d'OpenThread depuis nos tâches (sur IDF 5.5.4, un essai raté le laisse pris : leçon du Halo) ;
- **émissions Mesh retenues pendant que CHIPoBLE annonce** (`kCHIPoBLEAdvertisingChange`) : un seul jeu d'annonces BLE (amendement 3) ;
- **Thread en MTD, enfant non dormant (MED)** : un routeur ne tient pas face au scan Mesh permanent (ESP-IDF, `coexist.rst`). Le rôle dormant est un levier du plan 2b (amendement 6) ;
- `CONFIG_FREERTOS_HZ=1000` dès maintenant, pour le bouton et le voyant du Halo (Task 10) : le changer plus tard recompilerait tout ;
- `app_main` provisoire : Matter seul. La Task 7 y branche la tâche des lampes, la console et le Mesh.

- [ ] **Step 1 : le projet.**

`firmware/CMakeLists.txt` :

```cmake
cmake_minimum_required(VERSION 3.16)
# Firmware du pont (plan 2) : Matter sur Thread et Bluetooth Mesh sur une C6,
# ESP-IDF v5.5.4 + esp-matter (~/esp). Structure des exemples d'esp-matter et
# du SmartButton.
if(NOT DEFINED ENV{ESP_MATTER_PATH})
  message(FATAL_ERROR "ESP_MATTER_PATH absent : sourcer ~/esp/esp-matter/export.sh")
endif()

# Version montree dans Maison (« Programme interne ») : 0.1.0-<commit>[-dirty],
# 31 caracteres au plus (esp_app_desc). Calculee a la configuration, refaite a
# chaque commit (dependance sur .git/logs/HEAD).
execute_process(COMMAND git --no-optional-locks rev-parse --short=7 HEAD
                WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
                OUTPUT_VARIABLE REV OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE REV_RC)
if(NOT REV_RC EQUAL 0 OR REV STREQUAL "")
  set(REV "nogit")
endif()
execute_process(COMMAND git --no-optional-locks status --porcelain --untracked-files=no
                WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
                OUTPUT_VARIABLE SALE OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(NOT SALE STREQUAL "")
  set(REV "${REV}-dirty")
endif()
set(PROJECT_VER "0.1.0-${REV}")
set(PROJECT_VER_NUMBER 1)
if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../.git/logs/HEAD")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/../.git/logs/HEAD")
endif()

set(ESP_MATTER_PATH $ENV{ESP_MATTER_PATH})
set(MATTER_SDK_PATH ${ESP_MATTER_PATH}/connectedhomeip/connectedhomeip)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
set(EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_LIST_DIR}/../components"
    "${MATTER_SDK_PATH}/config/esp32/components"
    "${ESP_MATTER_PATH}/components")
project(amaran_pont)

idf_build_set_property(CXX_COMPILE_OPTIONS "-std=gnu++17;-Os;-DCHIP_HAVE_CONFIG_H;-Wno-overloaded-virtual" APPEND)
idf_build_set_property(C_COMPILE_OPTIONS "-Os" APPEND)
idf_build_set_property(COMPILE_OPTIONS "-Wno-format-nonliteral;-Wno-format-security" APPEND)
# Transitions de LevelControl immediates : sinon chaque pas d'une transition
# rappellerait l'application, et partirait vers la lampe.
idf_build_set_property(COMPILE_DEFINITIONS "IGNORE_LEVEL_CONTROL_CLUSTER_TRANSITION" APPEND)
```

`firmware/partitions.csv` :

```
# Nom,     Type, SousType, Adresse,  Taille
# Une seule application, pas d'OTA (spec 10). nvs : Matter, Thread, et l'espace
# "amaran" (cles du reseau Mesh, lampes, plancher de sequence).
nvs,       data, nvs,      0x9000,   0xC000,
phy_init,  data, phy,      0x15000,  0x1000,
factory,   app,  factory,  0x20000,  0x3E0000,
```

`firmware/main/CMakeLists.txt` :

```cmake
idf_component_register(SRC_DIRS "."
                       PRIV_INCLUDE_DIRS ".")
target_compile_options(${COMPONENT_LIB} PRIVATE "-DCHIP_HAVE_CONFIG_H")
```

`firmware/main/CHIPProjectConfig.h` :

```c
// Fiche produit du pont (spec 6.1), lue par la pile Matter (Basic Information).
// Le numero de serie, propre a la carte, est ecrit au demarrage (pont_matter.cpp).
#pragma once

#define CHIP_DEVICE_CONFIG_DEVICE_VENDOR_NAME "Djoko-CLI"
#define CHIP_DEVICE_CONFIG_DEVICE_PRODUCT_NAME "Pont amaran"
#define CHIP_DEVICE_CONFIG_DEFAULT_DEVICE_HARDWARE_VERSION_STRING "ESP32-C6 SuperMini"
```

- [ ] **Step 2 : les réglages.**

`firmware/sdkconfig.defaults` :

```
# Firmware du pont : ESP32-C6, Matter sur Thread (esp-matter) et Bluetooth Mesh
# sur le meme hote NimBLE. Chaque symbole est verifie par outils/check_sdkconfig.sh.

CONFIG_IDF_TARGET="esp32c6"
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions.csv"

# Console et journaux sur l'USB natif : la C6 SuperMini n'a pas de pont USB-serie.
CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y
# Tic de 1 ms : bouton BOOT et voyant repris du Halo (Arduino tourne a 1000 Hz).
CONFIG_FREERTOS_HZ=1000

# Bluetooth : NimBLE. La pile Matter demarre l'hote et le garde apres la mise en
# service (USE_BLE_ONLY_FOR_COMMISSIONING=n, sinon le Mesh meurt a l'appairage).
CONFIG_BT_ENABLED=y
CONFIG_BT_NIMBLE_ENABLED=y
CONFIG_BT_NIMBLE_EXT_ADV=n
CONFIG_BT_NIMBLE_50_FEATURE_SUPPORT=n
CONFIG_BT_LE_50_FEATURE_SUPPORT=n
CONFIG_BT_LE_SCAN_DUPL_TYPE_DATA_DEVICE=y
CONFIG_BT_NIMBLE_ENABLE_CONN_REATTEMPT=n
CONFIG_BT_NIMBLE_LOG_LEVEL_WARNING=y
CONFIG_ENABLE_CHIPOBLE=y
CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING=n

# Bluetooth Mesh : noeud qui entre seul dans le reseau des lampes (spec 5.1),
# memes reglages que le firmware d'ecoute.
CONFIG_BLE_MESH=y
CONFIG_BLE_MESH_NODE=y
CONFIG_BLE_MESH_PB_ADV=y
CONFIG_BLE_MESH_PB_GATT=n
CONFIG_BLE_MESH_GATT_PROXY_SERVER=n
# Ni proxy ni PB-GATT : la pile Mesh n'enregistre aucun service GATT sur un hote
# que Matter a deja demarre (elle planterait si CHIPoBLE annonce).
CONFIG_BLE_MESH_PROXY=n
CONFIG_BLE_MESH_RELAY=n
CONFIG_BLE_MESH_FRIEND=n
CONFIG_BLE_MESH_LOW_POWER=n
CONFIG_BLE_MESH_SETTINGS=n
CONFIG_BLE_MESH_SUBNET_COUNT=1
CONFIG_BLE_MESH_APP_KEY_COUNT=2
CONFIG_BLE_MESH_MODEL_KEY_COUNT=2
CONFIG_BLE_MESH_MODEL_GROUP_COUNT=4
CONFIG_BLE_MESH_CRPL=20
CONFIG_BLE_MESH_ADV_BUF_COUNT=120
CONFIG_BLE_MESH_IVU_RECOVERY_IVI=y
# Trace de la pile epinglee a ERROR : au-dessus, elle imprime des cles
# (components/mesh/mesh_amaran.c refuse de compiler au-dela).
CONFIG_BLE_MESH_TRACE_LEVEL_ERROR=y

# Thread : appareil minimal (MTD), donc enfant toujours a l'ecoute (MED) des le
# demarrage. Un routeur ne tient pas face au scan Mesh permanent (ESP-IDF,
# coexist.rst). Le mode dormant (ICD) est une variante du banc C.
CONFIG_OPENTHREAD_ENABLED=y
CONFIG_OPENTHREAD_MTD=y
CONFIG_OPENTHREAD_SRP_CLIENT=y
CONFIG_OPENTHREAD_DNS_CLIENT=y
CONFIG_OPENTHREAD_LOG_LEVEL_DYNAMIC=n
CONFIG_OPENTHREAD_LOG_LEVEL_NOTE=y
CONFIG_OPENTHREAD_CLI=n
CONFIG_ENABLE_ICD_SERVER=n
CONFIG_LWIP_IPV6_AUTOCONFIG=n
CONFIG_LWIP_IPV6_NUM_ADDRESSES=8
CONFIG_LWIP_MULTICAST_PING=y
CONFIG_LWIP_HOOK_IP6_ROUTE_DEFAULT=y
CONFIG_LWIP_HOOK_ND6_GET_GW_DEFAULT=y
CONFIG_USE_MINIMAL_MDNS=n
CONFIG_ENABLE_EXTENDED_DISCOVERY=y
CONFIG_ENABLE_WIFI_STATION=n

# Matter : fiche produit (main/CHIPProjectConfig.h), VID/PID et codes d'essai du
# SDK (comme le Halo : Maison accepte, avec l'avertissement « non certifie »).
CONFIG_CHIP_PROJECT_CONFIG="main/CHIPProjectConfig.h"
CONFIG_DEVICE_VENDOR_ID=0xFFF1
CONFIG_DEVICE_PRODUCT_ID=0x8000
CONFIG_ENABLE_PERSIST_SUBSCRIPTIONS=y
CONFIG_ENABLE_CHIP_SHELL=n
CONFIG_ENABLE_OTA_REQUESTOR=n
CONFIG_SUPPORT_GROUPCAST_CLUSTER=n
CONFIG_MBEDTLS_HKDF_C=y

# AES logiciel : l'AES materiel fait une allocation DMA par bloc, et la pile
# Mesh finit par s'arreter (amaran-bridge : "Encrypt failed").
CONFIG_MBEDTLS_HARDWARE_AES=n
```

- [ ] **Step 3 : le vérificateur des réglages couvre les deux firmwares.**

`outils/check_sdkconfig.sh` devient (seule la fin change : le niveau de trace de la pile Mesh se vérifie pour `ecoute` et pour `firmware`) :

```bash
#!/usr/bin/env bash
# Verifie que chaque symbole des sdkconfig.defaults* existe dans les Kconfig
# d'ESP-IDF (et d'esp-matter si ESP_MATTER_PATH est pose). Un symbole inconnu
# est ignore EN SILENCE par idf.py. Repris du SmartButton.
# Verifie aussi, pour chaque sdkconfig genere (ecoute, firmware), que la pile
# Mesh n'est pas reglee au-dessus du niveau de trace ERROR (elle imprimerait des cles).
#
# Usage : source ~/esp/esp-idf/export.sh, puis bash outils/check_sdkconfig.sh
set -u
: "${IDF_PATH:?source ~/esp/esp-idf/export.sh d abord}"
GREP=/usr/bin/grep
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNUS="$(mktemp)"
trap 'rm -f "$CONNUS"' EXIT

dossiers=("$IDF_PATH/components")
if [ -n "${ESP_MATTER_PATH:-}" ]; then
  dossiers+=("$ESP_MATTER_PATH/components" "$ESP_MATTER_PATH/device_hal"
             "$ESP_MATTER_PATH/connectedhomeip/connectedhomeip/config/esp32")
fi

{ find "$IDF_PATH" -maxdepth 1 -name 'Kconfig*' -type f -print0
  find "${dossiers[@]}" -name 'Kconfig*' -type f -print0 2>/dev/null; } \
  | xargs -0 "$GREP" -hoE '^[[:space:]]*(menu)?config[[:space:]]+[A-Z0-9_]+' 2>/dev/null \
  | awk '{print $NF}' | sort -u > "$CONNUS"
echo "$(wc -l < "$CONNUS" | tr -d ' ') symboles connus"

rc=0
for f in "$ICI"/ecoute/sdkconfig.defaults* "$ICI"/firmware/sdkconfig.defaults*; do
  [ -f "$f" ] || continue
  echo "-- ${f#"$ICI"/}"
  mauvais=0
  while IFS= read -r sym; do
    [ "$sym" = "IDF_TARGET" ] && continue  # pose par idf.py set-target
    if ! "$GREP" -qxF "$sym" "$CONNUS"; then
      echo "   x CONFIG_$sym : INCONNU (ignore en silence)"
      mauvais=$((mauvais + 1))
      rc=1
    fi
  done < <("$GREP" -oE '^CONFIG_[A-Z0-9_]+' "$f" | sed 's/^CONFIG_//' | sort -u)
  [ "$mauvais" -eq 0 ] && echo "   ok : tous les symboles existent"
done

# Valeur epinglee, lue dans le sdkconfig genere (ignore par git) de chaque
# firmware : au-dessus d'ERROR la pile Mesh imprime des cles (voir
# components/mesh/mesh_amaran.c). sdkconfig.defaults ne pese que sur les symboles
# absents de sdkconfig : une valeur plus ancienne, ou posee par menuconfig,
# l'emporterait en silence.
for projet in ecoute firmware; do
  SDKCONFIG="$ICI/$projet/sdkconfig"
  echo "-- $projet/sdkconfig (niveau de trace de la pile Mesh)"
  if [ ! -f "$SDKCONFIG" ]; then
    echo "   sdkconfig absent (pas encore genere) : rien a verifier ici, mesh_amaran.c garde la compilation"
  elif "$GREP" -qx 'CONFIG_BLE_MESH_NO_LOG=y' "$SDKCONFIG"; then
    echo "   ok : BLE_MESH_NO_LOG, la pile n'imprime rien (mais l'erreur \"IVIndex out of sync\" disparait, spec 5.3)"
  else
    niveau="$("$GREP" -E '^CONFIG_BLE_MESH_STACK_TRACE_LEVEL=[0-9]+$' "$SDKCONFIG" | cut -d= -f2)"
    if [ -z "$niveau" ]; then
      echo "   x CONFIG_BLE_MESH_STACK_TRACE_LEVEL : introuvable dans $projet/sdkconfig"
      rc=1
    elif [ "$niveau" -gt 1 ]; then
      echo "   x CONFIG_BLE_MESH_STACK_TRACE_LEVEL=$niveau : au-dessus d'ERROR (1), la pile imprime des cles"
      rc=1
    else
      echo "   ok : niveau $niveau (0 NONE, 1 ERROR) : la pile n'imprime aucune cle"
    fi
  fi
done
exit $rc
```

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && bash outils/check_sdkconfig.sh`
Expected : `-- firmware/sdkconfig.defaults` suivi de `ok : tous les symboles existent` ; `-- firmware/sdkconfig (...)` suivi de `sdkconfig absent (pas encore genere)`. Un symbole `INCONNU` : le corriger avant d'aller plus loin (idf.py l'ignorerait en silence).

- [ ] **Step 4 : l'interface du côté Matter.**

`firmware/main/pont_matter.h` :

```c
// Cote Matter du pont (spec 6) : noeud (EP0), agregateur (EP1) et une lampe
// pontee par emplacement (EP2, EP3), ordres des controleurs, etat des lampes
// publie sans echo, abonnements plafonnes. Ecrit en C++ (esp-matter),
// appele depuis le C.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
// marche et/ou intensite 0..1000 (NULL : inchange).
typedef void (*pont_ordre_cb_t)(int lampe, const bool *marche, const uint16_t *intensite);

// Cree les endpoints (noms et adresses : cfg), ecrit l'identite, puis demarre
// Matter. Les ordres arrivent par ordre().
esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre);
// Etat d'une lampe dans Matter (attribute::report : aucun rappel, donc aucun
// echo). etat NULL : jamais lu, seule la joignabilite change.
void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable);
// Au moins une fabrique (Maison ou un autre controleur).
bool pont_appaire(void);
// CHIPoBLE annonce (mise en service) : le Mesh ne doit pas emettre.
bool pont_ble_annonce(void);
// Thread attache (enfant, routeur ou chef), d'apres le dernier evenement de role.
bool pont_thread_attache(void);
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
void pont_afficher(void);
// Retire toutes les fabriques Matter, puis la pile redemarre la carte. Les
// reglages "amaran" (cles, lampes) restent (spec 7.7).
void pont_desappairer(void);

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 5 : le côté Matter.**

`firmware/main/pont_matter.cpp` :

```cpp
// Cote Matter du pont (voir pont_matter.h). Modeles : l'exemple light
// d'esp-matter (demarrage, Thread), le pont Halo (plafond des abonnements,
// identite, fenetre rouverte quand la derniere fabrique part).
#include "pont_matter.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "nvs.h"

#include <esp_matter.h>
#include <esp_openthread_types.h>
#include <openthread/thread.h>
#include <platform/ESP32/OpenthreadLauncher.h>

#include <app/InteractionModelEngine.h>
#include <app/server/CommissioningWindowManager.h>
#include <app/server/Server.h>
#include <platform/DeviceInstanceInfoProvider.h>
#include <setup_payload/OnboardingCodesUtil.h>

#include "mesh_amaran.h"

using namespace esp_matter;
using namespace chip::app::Clusters;

static const char *TAG = "pont";

static uint16_t s_ep_lampe[LAMPES_MAX];  // EP2 et EP3 ; 0 = pas encore cree
static char s_nom_lampe[LAMPES_MAX][AMARAN_NOM_MAX];
static pont_ordre_cb_t s_ordre;
static int64_t s_ordres_des_us;  // avant : valeurs posees par la pile au demarrage, pas des ordres
static volatile bool s_ble_annonce;
static volatile int s_role = OT_DEVICE_ROLE_DISABLED;
static volatile uint32_t s_abo_demandes, s_abo_plafonnes, s_abo_etablis, s_abo_termines;

// --- Abonnements : intervalle maximal plafonne (lecon du Halo : apres un
// redemarrage du noeud, Apple ne se reabonne que quand cet intervalle expire).

class PlafondAbonnements : public chip::app::ReadHandler::ApplicationCallback {
  CHIP_ERROR OnSubscriptionRequested(chip::app::ReadHandler &rh, chip::Transport::SecureSession &session) override {
    (void)session;
    uint16_t plancher = 0, max = 0;
    rh.GetReportingIntervals(plancher, max);
    s_abo_demandes++;
    const uint16_t voulu = plancher > PONT_PLAFOND_ABONNEMENT_S ? plancher : PONT_PLAFOND_ABONNEMENT_S;
    if (voulu < max && rh.SetMaxReportingInterval(voulu) == CHIP_NO_ERROR) s_abo_plafonnes++;
    return CHIP_NO_ERROR;  // jamais de refus : l'abonnement tomberait
  }
  void OnSubscriptionEstablished(chip::app::ReadHandler &rh) override {
    (void)rh;
    s_abo_etablis++;
  }
  void OnSubscriptionTerminated(chip::app::ReadHandler &rh) override {
    (void)rh;
    s_abo_termines++;
  }
};

static PlafondAbonnements s_plafond;

// --- Rappels de la pile (tache CHIP : jamais bloquer)

static int lampe_de(uint16_t ep) {
  for (int i = 0; i < LAMPES_MAX; i++) {
    if (s_ep_lampe[i] == ep) return i;
  }
  return -1;
}

// POST_UPDATE : la valeur est posee. Nos propres publications passent par
// attribute::report(), qui ne rappelle pas : tout ce qui arrive ici vient d'un
// controleur, d'une scene ou du cluster lui-meme (spec 6.4).
static esp_err_t rappel_attribut(attribute::callback_type_t type, uint16_t ep, uint32_t cluster, uint32_t attr,
                                 esp_matter_attr_val_t *val, void *priv) {
  (void)priv;
  if (type != attribute::POST_UPDATE || !s_ordre) return ESP_OK;
  const int lampe = lampe_de(ep);
  if (lampe < 0 || esp_timer_get_time() < s_ordres_des_us) return ESP_OK;
  if (cluster == OnOff::Id && attr == OnOff::Attributes::OnOff::Id) {
    const bool marche = val->val.b;
    s_ordre(lampe, &marche, NULL);
  } else if (cluster == LevelControl::Id && attr == LevelControl::Attributes::CurrentLevel::Id) {
    const uint8_t niveau = val->val.u8;
    if (niveau < 1 || niveau > 254) return ESP_OK;  // nul (0xFF) ou hors plage
    const uint16_t intensite = lampes_niveau_vers_intensite(niveau);
    s_ordre(lampe, NULL, &intensite);
  }
  return ESP_OK;
}

static void rappel_evenement(const chip::DeviceLayer::ChipDeviceEvent *ev, intptr_t arg) {
  (void)arg;
  using namespace chip::DeviceLayer;
  switch (ev->Type) {
    case DeviceEventType::kCHIPoBLEAdvertisingChange:
      // Un seul jeu d'annonces BLE : le Mesh se tait pendant que Matter annonce.
      s_ble_annonce = ev->CHIPoBLEAdvertisingChange.Result == kActivity_Started;
      mesh_autoriser_emission(!s_ble_annonce);
      break;
    case DeviceEventType::kCommissioningComplete:
      ESP_LOGI(TAG, "mise en service terminee");
      break;
    case DeviceEventType::kFabricRemoved: {
      // Derniere fabrique retiree depuis Maison : la fenetre de mise en service
      // se rouvre (DNS-SD, 300 s), comme la bibliotheque Arduino du Halo le faisait.
      if (chip::Server::GetInstance().GetFabricTable().FabricCount() != 0) break;
      chip::CommissioningWindowManager &fenetre = chip::Server::GetInstance().GetCommissioningWindowManager();
      if (!fenetre.IsCommissioningWindowOpen()) {
        const CHIP_ERROR err = fenetre.OpenBasicCommissioningWindow(chip::System::Clock::Seconds16(300),
                                                                    chip::CommissioningWindowAdvertisement::kDnssdOnly);
        if (err != CHIP_NO_ERROR) ESP_LOGE(TAG, "fenetre de mise en service non rouverte : %" CHIP_ERROR_FORMAT, err.Format());
      }
      break;
    }
    default:
      break;
  }
}

static void rappel_role(void *arg, esp_event_base_t base, int32_t id, void *donnees) {
  (void)arg;
  (void)base;
  (void)id;
  s_role = static_cast<const esp_openthread_role_changed_event_t *>(donnees)->current_role;
}

// --- Identite (spec 6.1)

// Numero de serie AMARAN-<MAC en 12 hexa>, lu par la pile dans chip-factory.
static void ecrire_numero_de_serie(void) {
  uint8_t mac[8] = {0};  // 8 octets : lecon du Halo (certaines lectures rendent un EUI-64 sur le C6)
  if (esp_read_mac(mac, ESP_MAC_BASE) != ESP_OK) return;
  char serie[20];
  snprintf(serie, sizeof(serie), "AMARAN-%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  nvs_handle_t h;
  if (nvs_open("chip-factory", NVS_READWRITE, &h) != ESP_OK) return;
  char lu[20] = {0};
  size_t n = sizeof(lu);
  if (nvs_get_str(h, "serial-num", lu, &n) != ESP_OK || strcmp(lu, serie) != 0) {
    if (nvs_set_str(h, "serial-num", serie) == ESP_OK) nvs_commit(h);
  }
  nvs_close(h);
}

// --- API

esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre) {
  s_ordre = ordre;
  ecrire_numero_de_serie();

  node::config_t cfg_noeud;
  snprintf(cfg_noeud.root_node.basic_information.node_label,
           sizeof(cfg_noeud.root_node.basic_information.node_label), "%s", "Pont amaran");
  // Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1).
  node_t *noeud = node::create(&cfg_noeud, rappel_attribut, NULL);
  if (!noeud) return ESP_FAIL;
  // SerialNumber est facultatif : cree vide, la pile le lit dans chip-factory.
  cluster_t *infos = cluster::get(endpoint::get(noeud, 0), BasicInformation::Id);
  if (infos) cluster::basic_information::attribute::create_serial_number(infos, NULL, 0);

  endpoint::aggregator::config_t cfg_agregateur;
  endpoint_t *agregateur = endpoint::aggregator::create(noeud, &cfg_agregateur, ENDPOINT_FLAG_NONE, NULL);
  if (!agregateur) return ESP_FAIL;

  // Une lampe pontee par emplacement, toujours les deux : les numeros d'endpoint
  // (2 et 3) suivent l'ordre de creation et ne changent jamais (spec 6.1).
  for (int i = 0; i < LAMPES_MAX; i++) {
    const amaran_lampe_t *l = &cfg->lampes[i];
    endpoint::bridged_node::config_t cfg_pontee;
    char *uid = cfg_pontee.bridged_device_basic_information.unique_id;
    const size_t tuid = sizeof(cfg_pontee.bridged_device_basic_information.unique_id);
    if (l->adresse) {
      snprintf(uid, tuid, "%02X%02X%02X%02X%02X%02X", l->mac[0], l->mac[1], l->mac[2], l->mac[3], l->mac[4],
               l->mac[5]);
    } else {
      snprintf(uid, tuid, "amaran-%d", i + 1);
    }
    endpoint_t *ep = endpoint::bridged_node::create(noeud, &cfg_pontee, ENDPOINT_FLAG_NONE, NULL);
    if (!ep) return ESP_FAIL;
    endpoint::dimmable_light::config_t cfg_lampe;
    // Defauts d'esp-matter a 0 : ils eteindraient les lampes, ou les baisseraient
    // au minimum, a chaque demarrage. Nuls : rien ne change (spec 6.5).
    cfg_lampe.on_off_lighting.start_up_on_off = nullptr;
    cfg_lampe.level_control_lighting.start_up_current_level = nullptr;
    if (endpoint::dimmable_light::add(ep, &cfg_lampe) != ESP_OK) return ESP_FAIL;
    if (endpoint::set_parent_endpoint(ep, agregateur) != ESP_OK) return ESP_FAIL;
    snprintf(s_nom_lampe[i], sizeof(s_nom_lampe[i]), "%s", l->adresse ? l->nom : "lampe absente");
    cluster_t *pontee = cluster::get(ep, BridgedDeviceBasicInformation::Id);
    if (pontee) {
      cluster::bridged_device_basic_information::attribute::create_node_label(pontee, s_nom_lampe[i],
                                                                              strlen(s_nom_lampe[i]));
    }
    s_ep_lampe[i] = endpoint::get_id(ep);
    // Les etats relus changent CurrentLevel souvent : ecriture en flash differee.
    attribute::set_deferred_persistence(
        attribute::get(s_ep_lampe[i], LevelControl::Id, LevelControl::Attributes::CurrentLevel::Id));
  }

  // Thread sur la radio du C6 (exemple light d'esp-matter).
  esp_openthread_platform_config_t ot = {};
  ot.radio_config.radio_mode = RADIO_MODE_NATIVE;
  ot.host_config.host_connection_mode = HOST_CONNECTION_MODE_NONE;
  ot.port_config.storage_partition_name = "nvs";
  ot.port_config.netif_queue_size = 10;
  ot.port_config.task_queue_size = 10;
  set_openthread_platform_config(&ot);

  // Role Thread lu dans ses evenements : jamais le verrou d'OpenThread depuis
  // nos taches (lecon du Halo ; sur IDF 5.5.4 un essai rate le laisserait pris).
  const esp_err_t boucle = esp_event_loop_create_default();
  if (boucle != ESP_OK && boucle != ESP_ERR_INVALID_STATE) return boucle;
  esp_event_handler_register(OPENTHREAD_EVENT, OPENTHREAD_EVENT_ROLE_CHANGED, rappel_role, NULL);

  const esp_err_t err = esp_matter::start(rappel_evenement);
  if (err != ESP_OK) return err;
  s_ordres_des_us = esp_timer_get_time() + 2000000;  // lecon du Halo : ce qui arrive avant vient de la pile
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    chip::app::InteractionModelEngine::GetInstance()->RegisterReadHandlerAppCallback(&s_plafond);
  }
  // Un emplacement sans lampe n'est jamais joignable. Les autres partent
  // joignables (spec 6.5) et se calent au premier etat lu.
  for (int i = 0; i < LAMPES_MAX; i++) {
    if (!cfg->lampes[i].adresse) pont_publier(i, NULL, false);
  }
  return ESP_OK;
}

void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable) {
  if (lampe < 0 || lampe >= LAMPES_MAX || !s_ep_lampe[lampe]) return;
  const uint16_t ep = s_ep_lampe[lampe];
  esp_matter_attr_val_t v = esp_matter_bool(joignable);
  attribute::report(ep, BridgedDeviceBasicInformation::Id, BridgedDeviceBasicInformation::Attributes::Reachable::Id,
                    &v);
  if (!etat) return;
  v = esp_matter_bool(etat->marche);
  attribute::report(ep, OnOff::Id, OnOff::Attributes::OnOff::Id, &v);
  uint8_t niveau = lampes_intensite_vers_niveau(etat->intensite);
  if (niveau < PONT_NIVEAU_PLANCHER) niveau = PONT_NIVEAU_PLANCHER;
  v = esp_matter_nullable_uint8(niveau);
  attribute::report(ep, LevelControl::Id, LevelControl::Attributes::CurrentLevel::Id, &v);
}

bool pont_appaire(void) { return chip::Server::GetInstance().GetFabricTable().FabricCount() > 0; }

bool pont_ble_annonce(void) { return s_ble_annonce; }

bool pont_thread_attache(void) {
  const int r = s_role;
  return r == OT_DEVICE_ROLE_CHILD || r == OT_DEVICE_ROLE_ROUTER || r == OT_DEVICE_ROLE_LEADER;
}

void pont_desappairer(void) { esp_matter::factory_reset(); }

void pont_afficher(void) {
  // Tout est lu sous le verrou de la pile, puis imprime apres (la sortie USB
  // peut attendre : la pile n'attend pas avec elle).
  char qr[128] = {0}, manuel[32] = {0}, fabricant[33] = {0}, produit[33] = {0}, serie[33] = {0};
  uint8_t fabriques = 0;
  uint32_t actifs = 0;
  bool codes = false;
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
    actifs = chip::app::InteractionModelEngine::GetInstance()->GetNumActiveReadHandlers(
        chip::app::ReadHandler::InteractionType::Subscribe);
    chip::DeviceLayer::DeviceInstanceInfoProvider *infos = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
    if (!infos || infos->GetVendorName(fabricant, sizeof(fabricant)) != CHIP_NO_ERROR) snprintf(fabricant, sizeof(fabricant), "?");
    if (!infos || infos->GetProductName(produit, sizeof(produit)) != CHIP_NO_ERROR) snprintf(produit, sizeof(produit), "?");
    if (!infos || infos->GetSerialNumber(serie, sizeof(serie)) != CHIP_NO_ERROR) snprintf(serie, sizeof(serie), "?");
    if (fabriques == 0) {
      // Codes d'appairage montres seulement avant la mise en service (lecon du Halo).
      chip::MutableCharSpan qr_span(qr), manuel_span(manuel);
      const chip::RendezvousInformationFlags ble(chip::RendezvousInformationFlag::kBLE);
      codes = GetQRCode(qr_span, ble) == CHIP_NO_ERROR && GetManualPairingCode(manuel_span, ble) == CHIP_NO_ERROR;
    }
  }
  printf("\n=== Matter ===\n");
  if (fabriques) {
    printf("  mise en service : faite (%u fabrique(s))\n", (unsigned)fabriques);
  } else {
    printf("  mise en service : EN ATTENTE\n");
  }
  printf("  Thread          : %s%s\n", otThreadDeviceRoleToString(static_cast<otDeviceRole>(s_role)),
         pont_thread_attache() ? " (attache)" : "");
  printf("  BLE             : %s\n", s_ble_annonce ? "annonce de mise en service EN COURS (Mesh muet)" : "sans annonce");
  printf("  abonnements     : %" PRIu32 " actif(s) ; demandes %" PRIu32 ", plafonnees a %d s %" PRIu32
         ", etablis %" PRIu32 ", termines %" PRIu32 "\n",
         actifs, s_abo_demandes, PONT_PLAFOND_ABONNEMENT_S, s_abo_plafonnes, s_abo_etablis, s_abo_termines);
  if (codes) {
    printf("  code manuel     : %s\n", manuel);
    printf("  QR code         : %s\n", qr);
  }
  printf("  identite        : %s, %s, n/s %s\n", fabricant, produit, serie);
  printf("  version         : %s\n", esp_app_get_description()->version);
  for (int i = 0; i < LAMPES_MAX; i++) printf("  EP%u             : %s\n", (unsigned)s_ep_lampe[i], s_nom_lampe[i]);
}
```

- [ ] **Step 6 : un `app_main` provisoire.**

`firmware/main/app_main.cpp` :

```cpp
// Firmware du pont (plan 2) : Matter sur Thread vers Maison, Bluetooth Mesh vers
// les deux amaran 60d. Ordre de demarrage : spec 6.5 et 6.6.
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "pont_matter.h"

static const char *TAG = "pont";

// Provisoire : la tache lampes (Task 7) recevra ces ordres.
static void ordre_matter(int lampe, const bool *marche, const uint16_t *intensite) {
  ESP_LOGI(TAG, "ordre Matter, lampe %d : marche %d, intensite %d", lampe + 1, marche ? (int)*marche : -1,
           intensite ? (int)*intensite : -1);
}

extern "C" void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS illisible : effacee (mise en service et cles a refaire)");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  static amaran_config_t cfg;
  err = config_charger(&cfg);
  if (err != ESP_OK) {
    // Pas de boucle de redemarrage : on demarre sans Bluetooth Mesh.
    ESP_LOGE(TAG, "reglages illisibles (%s) : sans Bluetooth Mesh", esp_err_to_name(err));
    cfg.cles_presentes = false;
  }
  err = pont_demarrer(&cfg, ordre_matter);
  if (err != ESP_OK) ESP_LOGE(TAG, "Matter non demarre : %s", esp_err_to_name(err));
}
```

- [ ] **Step 7 : compiler.**

La première compilation télécharge les composants gérés (réseau nécessaire) et dure 7 à 10 min.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py set-target esp32c6 && idf.py build 2>&1 | tee "${TMPDIR:-/tmp}/amaran-firmware.log" | tail -5 && idf.py size && cd ..`
Expected : `Project build complete.` ; une ligne `amaran_pont.bin binary size 0x17.... bytes. Smallest app partition is 0x3e0000 bytes.` (environ 1,45 Mo, 63 % libres) ; `idf.py size` imprime l'occupation de la RAM. Noter les deux chiffres dans le rapport.

Run: `/usr/bin/grep -E "(firmware/main|components/(lampes|mesh|telink))/[^ ]*: warning:" "${TMPDIR:-/tmp}/amaran-firmware.log"`
Expected : aucune ligne.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && bash outils/check_sdkconfig.sh`
Expected : `-- firmware/sdkconfig (niveau de trace de la pile Mesh)` suivi de `ok : niveau 1 (0 NONE, 1 ERROR) : la pile n'imprime aucune cle`.

- [ ] **Step 8 : commit.**

`firmware/dependencies.lock` fige les versions des composants gérés : il entre dans le dépôt (le SmartButton l'ignorait, et ne se reconstruisait plus à l'identique). `build/`, `sdkconfig` et `managed_components/` restent ignorés.

```bash
git add firmware/CMakeLists.txt firmware/partitions.csv firmware/sdkconfig.defaults firmware/dependencies.lock firmware/main outils/check_sdkconfig.sh
git status --short   # attendu : rien sous firmware/build, firmware/sdkconfig ni firmware/managed_components
git commit -m "$(printf "Ajouter le firmware du pont, cote Matter : agregateur, deux lampes pontees, abonnements plafonnes\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 7: La tâche des lampes, la console du pont et le démarrage

**Files:**
- Create: `firmware/main/tache_lampes.h`, `firmware/main/tache_lampes.c`
- Create: `firmware/main/console_pont.h`, `firmware/main/console_pont.c`
- Modify: `firmware/main/app_main.cpp` (fichier entier)
- Modify: `components/mesh/include/config_amaran.h`, `components/mesh/config_amaran.c`

**Interfaces:**
- Consumes :
  - `pont_matter.h` (Task 6) : `pont_demarrer`, `pont_publier`, `pont_appaire`, `pont_ble_annonce`, `pont_afficher`, `pont_desappairer`, `pont_ordre_cb_t` ;
  - `lampes.h` (Task 1) : `lampes_init`, `lampes_mesh_pret`, `lampes_regler_releve`, `lampes_ordre`, `lampes_trame_recue`, `lampes_tic`, `lampes_t`, `lampe_t`, `LAMPE_REPOS`, `LAMPES_*` ;
  - `diagnostic.h`, `mesh_console.h` (Task 4) : `diagnostic_suivre`, `diagnostic_texte`, `DIAG_OK`, `diagnostic_ecarts_t`, `diagnostic_suivi_t` ; `mesh_console_init`, `mesh_console_commande`, `mesh_console_taches`, `mesh_console_redemarrer`, `mesh_console_evenement` ;
  - `mesh_amaran.h` (plan 1, Tasks 2 et 3) : `mesh_demarrer`, `mesh_envoyer`, `mesh_pret`, `mesh_file_evenements`, `mesh_lire_stats`, `mesh_ecoute_detaillee`, `mesh_stats_t`, `mesh_evenement_t` (`type`, `src`, `acces`), `MESH_EV_ETAT_LAMPE`, `MESH_REPETITIONS_ETAT` ;
  - `telink.h` : `telink_demande_etat`, `TELINK_TAILLE`, `TELINK_INTENSITE_MAX` ; `texte.h` : `texte_lire_nombre`.
- Produces :
  - `amaran_config_t.releve_ms` (clé NVS `releve` ; 0 = 5 s par défaut) et `esp_err_t config_sauver_releve(uint32_t releve_ms);` ;
  - `firmware/main/tache_lampes.h` : `tache_lampes_demarrer`, `tache_lampes_ordre`, `tache_lampes_regler_releve`, `tache_lampes_lire`, `tache_lampes_ecoute`, `tache_lampes_confirmes`, `tache_lampes_abandons` (voir l'en-tête) ;
  - `firmware/main/console_pont.h` : `void console_pont_demarrer(amaran_config_t *cfg);`.

Pourquoi (spec 4.3, 6.5, 6.6, 7.3, 7.5) :
- la tâche `lampes` est la seule qui touche l'état des lampes (4.3). Elle vide d'abord la file des ordres (une commande Matter arrive en plusieurs écritures), puis les événements du crochet, puis fait tourner `lampes_tic()` toutes les 50 ms. La console lit une copie sous verrou ;
- le diagnostic 7.3 s'imprime à la console. Le voyant rouge viendra avec le socle (Task 10) ;
- la console du pont reprend la commande `mesh` partagée, et y ajoute `mesh releve <s>` (5.7, gardée en NVS) et `mesh ecoute on|off` (qui imprime aussi les états des lampes). `lampe <n> ...` passe par la tâche `lampes` : l'ordre est confirmé, répété, abandonné comme un ordre de Maison ;
- démarrage : NVS, réglages (non fatal), console, tâche des lampes, Matter ; puis le Mesh entre dans le réseau une fois Maison appairée et CHIPoBLE silencieux, 3 s plus tard (amendement 3). Seules des demandes d'état partent au démarrage (6.5) : `lampes` relit aussitôt le Mesh prêt ;
- `taches` suit les tâches du pont : `lampes`, `amaran_tx`, `nimble_host`, `mesh_adv_task`, `CHIP`, `ot_task`, `console_repl`.

- [ ] **Step 1 : la période de relecture en NVS.**

Dans `components/mesh/include/config_amaran.h`, remplacer :

```c
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
```

par :

```c
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
  uint32_t releve_ms;     // periode de relecture des lampes (pont) ; 0 = celle par defaut
```

et, après la déclaration de `config_sauver_plancher`, ajouter :

```c
// Periode de relecture des lampes, en ms (commande `mesh releve` du pont).
esp_err_t config_sauver_releve(uint32_t releve_ms);
```

Dans `components/mesh/config_amaran.c`, dans `config_charger()`, après la ligne :

```c
  if (nvs_get_u32(h, "plancher", &c->plancher_seq) != ESP_OK) c->plancher_seq = 0;
```

ajouter :

```c
  if (nvs_get_u32(h, "releve", &c->releve_ms) != ESP_OK) c->releve_ms = 0;
```

et, après la fonction `config_sauver_plancher()`, ajouter :

```c
esp_err_t config_sauver_releve(uint32_t releve_ms) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "releve", releve_ms));
}
```

- [ ] **Step 2 : la tâche des lampes.**

`firmware/main/tache_lampes.h` :

```c
// Tache du coeur du pont (spec 4.3) : la seule qui touche l'etat des lampes.
// Elle recoit les ordres (Matter, console) et les evenements du crochet, et fait
// tourner lampes_tic() toutes les 50 ms.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t tache_lampes_demarrer(const amaran_config_t *cfg);
// Ordre pour une lampe, sans bloquer, depuis n'importe quelle tache (la tache
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
// Copie coherente de l'etat, pour la console.
void tache_lampes_lire(lampes_t *copie);
// Ecoute detaillee : imprimer aussi chaque etat recu des lampes.
void tache_lampes_ecoute(bool oui);
// Ordres confirmes et abandonnes depuis le demarrage (ne font que croitre).
uint32_t tache_lampes_confirmes(void);
uint32_t tache_lampes_abandons(void);

#ifdef __cplusplus
}
#endif
```

`firmware/main/tache_lampes.c` :

```c
// Tache du coeur du pont (voir tache_lampes.h).
#include "tache_lampes.h"

#include <stdio.h>
#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "diagnostic.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
#include "pont_matter.h"

#define TIC_MS 50
#define FILE_ORDRES 16

typedef enum { MSG_ORDRE, MSG_RELEVE } message_type_t;

typedef struct {
  message_type_t type;
  int8_t lampe;
  bool a_marche, marche, a_intensite, depuis_matter;
  uint16_t intensite;
  uint32_t releve_ms;
} message_t;

static QueueHandle_t s_file;
static SemaphoreHandle_t s_verrou;  // s_lampes, lu en copie par la console
static lampes_t s_lampes;
static volatile bool s_ecoute;
static volatile uint32_t s_confirmes, s_abandons;
static bool s_cles;                  // cles du reseau presentes au demarrage
static diagnostic_suivi_t s_diag;    // Bluetooth Mesh inoperant (spec 7.3)

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static bool sortie_envoyer(void *ctx, uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions) {
  (void)ctx;
  return mesh_envoyer(dst, trame, repetitions) == ESP_OK;
}

static void sortie_publier(void *ctx, int lampe, const lampe_etat_t *etat, bool joignable) {
  (void)ctx;
  pont_publier(lampe, etat, joignable);
}

static void sortie_signaler(void *ctx, int lampe, lampes_signal_t signal) {
  (void)ctx;
  (void)lampe;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    s_confirmes++;
  } else {
    s_abandons++;
  }
}

static void traiter(const message_t *m) {
  if (m->type == MSG_RELEVE) {
    lampes_regler_releve(&s_lampes, m->releve_ms);
    return;
  }
  lampes_ordre(&s_lampes, m->lampe, m->a_marche ? &m->marche : NULL, m->a_intensite ? &m->intensite : NULL,
               m->depuis_matter, maintenant_ms());
}

// Bluetooth Mesh inoperant (spec 7.3) : message a la console.
static void diagnostiquer(uint32_t t) {
  mesh_stats_t st;
  mesh_lire_stats(&st);
  const diagnostic_ecarts_t compteurs = {st.annonces, st.nid_reconnu, st.netmic_faux, st.acces_dechiffres};
  if (!diagnostic_suivre(&s_diag, s_cles, mesh_pret(), &compteurs, t)) return;
  if (s_diag.etat == DIAG_OK) {
    printf("[mesh] de nouveau operationnel\n");
  } else {
    printf("!! Bluetooth Mesh inoperant : %s\n", diagnostic_texte(s_diag.etat));
  }
}

static void tache(void *arg) {
  (void)arg;
  uint32_t prochain_tic = maintenant_ms();
  for (;;) {
    message_t m;
    const int32_t attente = (int32_t)(prochain_tic - maintenant_ms());
    if (xQueueReceive(s_file, &m, attente > 0 ? pdMS_TO_TICKS(attente) : 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      traiter(&m);
      xSemaphoreGive(s_verrou);
      continue;  // la file d'abord : une commande Matter arrive en plusieurs ecritures
    }
    // Evenements du crochet : etats des lampes ; IV Index a sauver ; le reste,
    // imprime en ecoute detaillee.
    QueueHandle_t evenements = mesh_file_evenements();
    mesh_evenement_t ev;
    while (evenements && xQueueReceive(evenements, &ev, 0) == pdTRUE) {
      if (ev.type == MESH_EV_ETAT_LAMPE) {
        xSemaphoreTake(s_verrou, portMAX_DELAY);
        lampes_trame_recue(&s_lampes, ev.src, ev.acces + 1, maintenant_ms());
        xSemaphoreGive(s_verrou);
      }
      mesh_console_evenement(&ev, s_ecoute);
    }
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    lampes_mesh_pret(&s_lampes, mesh_pret(), maintenant_ms());
    lampes_tic(&s_lampes, maintenant_ms());
    xSemaphoreGive(s_verrou);
    diagnostiquer(maintenant_ms());
    prochain_tic = maintenant_ms() + TIC_MS;
  }
}

esp_err_t tache_lampes_demarrer(const amaran_config_t *cfg) {
  s_cles = cfg->cles_presentes;
  s_file = xQueueCreate(FILE_ORDRES, sizeof(message_t));
  s_verrou = xSemaphoreCreateMutex();
  if (!s_file || !s_verrou) return ESP_ERR_NO_MEM;
  uint16_t adresses[LAMPES_MAX];
  for (int i = 0; i < LAMPES_MAX; i++) adresses[i] = cfg->lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL};
  lampes_init(&s_lampes, adresses, LAMPES_MAX, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
  return xTaskCreate(tache, "lampes", 4096, NULL, 4, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  if (!s_file || lampe < 0 || lampe >= LAMPES_MAX) return;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter};
  if (marche) {
    m.a_marche = true;
    m.marche = *marche;
  }
  if (intensite) {
    m.a_intensite = true;
    m.intensite = *intensite;
  }
  xQueueSend(s_file, &m, 0);  // file pleine : l'ordre se perd, Maison sera recale a la relecture
}

void tache_lampes_regler_releve(uint32_t releve_ms) {
  if (!s_file) return;
  const message_t m = {.type = MSG_RELEVE, .releve_ms = releve_ms};
  xQueueSend(s_file, &m, 0);
}

void tache_lampes_lire(lampes_t *copie) {
  if (!s_verrou) {
    memset(copie, 0, sizeof(*copie));
    return;
  }
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  *copie = s_lampes;
  xSemaphoreGive(s_verrou);
}

void tache_lampes_ecoute(bool oui) { s_ecoute = oui; }

uint32_t tache_lampes_confirmes(void) { return s_confirmes; }

uint32_t tache_lampes_abandons(void) { return s_abandons; }
```

- [ ] **Step 3 : la console du pont.**

`firmware/main/console_pont.h` :

```c
// Console du pont, en francais (spec 7.5).
#pragma once

#include "config_amaran.h"

#ifdef __cplusplus
extern "C" {
#endif

// Demarre la console sur l'USB natif. cfg reste la propriete de l'appelant.
void console_pont_demarrer(amaran_config_t *cfg);

#ifdef __cplusplus
}
#endif
```

`firmware/main/console_pont.c` :

```c
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
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > LAMPES_MAX || !s_cfg->lampes[n - 1].adresse) {
    printf("erreur : lampe <1-%d> on|off|niveau <0-1000>|releve (lampe declaree ?)\n", LAMPES_MAX);
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
  (void)argc;
  (void)argv;
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

static const char *const TACHES[] = {"lampes", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP", "ot_task",
                                     "console_repl"};

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
      {.command = "mesh", .help = "etat ; mesh cles|lampe|iv|adresse|oublie|ecoute|autotest|releve ...", .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
      {.command = "decommission", .help = "retire toutes les fabriques Matter (cles gardees)", .func = cmd_decommission},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = mesh_console_taches},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
```

- [ ] **Step 4 : le démarrage.**

`firmware/main/app_main.cpp` devient :

```cpp
// Firmware du pont (plan 2) : Matter sur Thread vers Maison, Bluetooth Mesh vers
// les deux amaran 60d. Ordre de demarrage : spec 6.5 et 6.6.
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "console_pont.h"
#include "mesh_amaran.h"
#include "pont_matter.h"
#include "tache_lampes.h"

static const char *TAG = "pont";

static void ordre_matter(int lampe, const bool *marche, const uint16_t *intensite) {
  tache_lampes_ordre(lampe, marche, intensite, true);
}

extern "C" void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS illisible : effacee (mise en service et cles a refaire)");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  static amaran_config_t cfg;
  err = config_charger(&cfg);
  if (err != ESP_OK) {
    // Pas de boucle de redemarrage : la console reste la pour diagnostiquer.
    ESP_LOGE(TAG, "reglages illisibles (%s) : sans Bluetooth Mesh", esp_err_to_name(err));
    cfg.cles_presentes = false;
  }
  console_pont_demarrer(&cfg);
  ESP_ERROR_CHECK(tache_lampes_demarrer(&cfg));
  err = pont_demarrer(&cfg, ordre_matter);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "Matter non demarre : %s", esp_err_to_name(err));
    return;
  }
  if (!cfg.cles_presentes) {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
    return;
  }
  // Le Bluetooth Mesh n'entre dans le reseau des lampes qu'une fois Maison
  // appairee : pendant la mise en service, CHIPoBLE a besoin des annonces (6.6).
  while (!pont_appaire() || pont_ble_annonce()) vTaskDelay(pdMS_TO_TICKS(500));
  vTaskDelay(pdMS_TO_TICKS(3000));  // la connexion BLE de mise en service se ferme
  err = mesh_demarrer(&cfg);
  if (err != ESP_OK) ESP_LOGE(TAG, "Bluetooth Mesh non demarre : %s", esp_err_to_name(err));
}
```

- [ ] **Step 5 : compiler, et vérifier.**

`SRC_DIRS "."` ne voit les nouveaux fichiers de `firmware/main` qu'à la configuration : d'où `reconfigure`.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py reconfigure build 2>&1 | tee "${TMPDIR:-/tmp}/amaran-firmware.log" | tail -5 && idf.py size && cd ..`
Expected : `Project build complete.` ; `amaran_pont.bin binary size 0x19..... bytes` (environ 1,62 Mo, 58 % libres). Noter la taille et la RAM statique dans le rapport.

Run: `/usr/bin/grep -E "(firmware/main|components/(lampes|mesh|telink))/[^ ]*: warning:" "${TMPDIR:-/tmp}/amaran-firmware.log"`
Expected : aucune ligne.

`config_amaran` est aussi compilé par le firmware d'écoute :

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build | tail -2 && cd .. && sh tests/hote/lancer.sh`
Expected : `Project build complete.`, puis `tests hote : tout est vert`.

- [ ] **Step 6 : commit.**

```bash
git add firmware/main components/mesh/include/config_amaran.h components/mesh/config_amaran.c
git commit -m "$(printf "Brancher les lampes sur Matter : tache des lampes, console du pont, Mesh apres la mise en service\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 8: Au banc : appairage dans Maison et banc C de la radio partagée (Claude et Djoko)

**Qui :** Claude, le contrôleur, avec Djoko présent. **Pas de sous-agent** : on efface, on flashe, on lit la base d'amaran Desktop.

**Files:**
- Modify: `docs/BANC.md` (procédure et résultats du banc C), `README.md` (état)

**Interfaces:**
- Consumes : le firmware du pont (Tasks 6 et 7) ; `outils/cles_amaran.py` et `outils/console.py` (plan 1).
- Produces : le verdict de la règle 5.8 (une carte ou deux), les marges de mémoire (spec 11), et un pont appairé dans Maison, que reprennent les bancs T.

Pourquoi (spec 5.8, 8.3) : Thread et Bluetooth se partagent la radio du C6. C'est la seule inconnue que ni les tests ni la compilation ne tranchent, et elle décide de la suite : une carte ou deux.

- [ ] **Step 1 : compiler au commit de la Task 7.**

Run: `git status --short && sh tests/hote/lancer.sh && export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py build | tail -2 && cd ..`
Expected : `git status` ne montre rien (sinon la version porterait `-dirty`) ; `tests hote : tout est vert` ; `Project build complete.`

- [ ] **Step 2 : reconnaître la carte.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && python -m serial.tools.list_ports -v`
La C6 du pont est celle dont le champ `SER=` est le numéro noté hors du dépôt. Jamais la C6 du maillage Thread BenQ, jamais un écran LG. Au moindre doute : s'arrêter et demander à Djoko.

- [ ] **Step 3 : effacer et flasher, avec l'accord de Djoko.**

Demander à Djoko : « J'efface la C6 du pont (`<port>`) et j'y flashe le firmware du pont ? Je rechargerai ensuite les clés. »

Pourquoi effacer : la table de partitions change (la NVS du pont, 48 Ko, recouvre l'ancienne application d'écoute), et Matter comme Thread doivent partir d'une NVS vierge.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py -p <port> erase-flash flash && cd ..`
Expected : `Hard resetting via RTS pin...`

Ce qui est perdu, et revient aux Steps 4 et 5 : les clés, l'IV Index (0 : celui du réseau), l'adresse Mesh (retirée au hasard dans `0x7F00`–`0x7F7F`) et le plancher de séquence (0, pour la nouvelle adresse).

- [ ] **Step 4 : recharger les clés (Claude seul : l'outil lit la base d'amaran Desktop).**

Run: `python3 outils/cles_amaran.py --port <port>`
Expected : l'outil reconnaît le pont (la commande `mesh` est partagée), imprime les empreintes des clés, égales à celles du banc R, charge les deux lampes, et la carte redémarre.

- [ ] **Step 5 : l'état avant l'appairage.**

Run: `python3 outils/console.py --port <port> "mesh autotest" "mesh" "matter" "lampes" "taches"`
Expected :
- `autotest : 0 echec(s)`, après 11 lignes `ok` : les fonctions de chiffrement du Mesh marchent aussi dans le firmware du pont (même moteur que l'écoute : `CONFIG_BLE_MESH_USE_UNIFIED_CRYPTO`) ;
- `mesh pret : non` : normal, le Mesh attend l'appairage (amendement 3) ; les empreintes du Step 4 ; `lampe 1 : 0x0002 ...` et `lampe 2 : 0x0004 ...` ;
- l'adresse tirée. Si c'est `0x7f38`, l'adresse des bancs R (les lampes gardent son compteur de séquence) : `mesh adresse suivante`, et la carte redémarre ;
- `matter` : `mise en service : EN ATTENTE`, un code manuel et un QR code, `identite : Djoko-CLI, Pont amaran, n/s AMARAN-...`, `version : 0.1.0-<commit>`, `EP2 : amaran COB 60d #1`, `EP3 : amaran COB 60d #2` ;
- `lampes` : `Bluetooth Mesh PAS PRET`.

Le numéro de série contient la MAC de la carte : il reste dans `logs/`, jamais dans le dépôt.

- [ ] **Step 6 : appairer dans Maison (Djoko).**

Lancer d'abord l'écoute : `python3 outils/console.py --port <port> "@180" "matter" "mesh" "lampes"`.

Pendant ce temps, Djoko, sur l'iPhone : Maison, « + », « Ajouter un accessoire », « Plus d'options… », puis le code manuel imprimé par `matter`. Maison prévient que l'accessoire n'est pas certifié : « Ajouter quand même ». Choisir une pièce ; Maison montre un pont et deux lampes.

Expected :
- au journal : `mise en service terminee` ;
- `matter` : `mise en service : faite (1 fabrique(s))`, `Thread : child (attache)`, `BLE : sans annonce`, au moins un abonnement actif ;
- `mesh` : `mesh pret : oui`, `balises : notres` plus grand que 0 ;
- `lampes` : les deux lampes `joignable`, avec un état lu récent ;
- dans Maison : les noms « amaran COB 60d #1 » et « #2 », et l'état réel des lampes. Noms non repris : les donner à la main (spec 11) et le noter.

`mesh pret` encore à `non` une minute après l'appairage, ou une panique au journal : ce n'est pas un échec du banc C, mais un défaut d'intégration entre Matter et le Mesh sur l'hôte NimBLE. S'arrêter, chercher la cause (superpowers:systematic-debugging), corriger, puis reprendre ici.

- [ ] **Step 7 : banc C, au repos (30 min).**

amaran Desktop fermé ; personne ne touche aux lampes.

Run: `python3 outils/console.py --port <port> "lampes" "mesh" "@1800" "lampes" "mesh" "matter" "taches"`
Pour chaque lampe, relever `releves : <r> repondue(s) sur <n>` au début (r1, n1) et à la fin (r2, n2) : part répondue = (r2 − r1) / (n2 − n1). À 5 s, 30 min font 360 relectures.
Expected :
- part répondue ≥ 95 % pour chaque lampe ;
- `evenements perdus 0` ; `Thread : child (attache)` à la fin ;
- `taches` : aucune tâche sous 512 o de pile libre. Sinon, l'agrandir (dans `tache_lampes.c` ou `console_pont.c`) avant la phase 2.

- [ ] **Step 8 : banc C, ordres depuis Maison (Djoko).**

Run: `python3 outils/console.py --port <port> "lampes"` (avant)

Djoko donne une trentaine d'ordres depuis Maison, à quelques secondes d'écart, sur les deux lampes : marche, arrêt, et des luminosités variées (1 %, 10 %, 50 %, 100 %…). Il regarde la lampe après chacun.

Run: `python3 outils/console.py --port <port> "lampes"` (après)

Relever `ordres : ... (confirmes <c>, abandonnes <a>) ; delai moyen <m> ms, max <M> ms, <l> au-dela d'1 s`. `ordres` compte chaque écriture reçue ; une commande de Maison en fait parfois plusieurs, qui partent en une seule salve (Task 1). D'où : salves = Δc + Δa ; en échec ou lentes = Δa + Δl.
Expected : chaque lampe obéit sous les yeux de Djoko ; (Δa + Δl) ≤ 1 % des salves, c'est-à-dire aucune sur une trentaine.

- [ ] **Step 9 : banc C, ordres de la console (Djoko présent).**

Dix ordres à 1 s d'écart, cinq par lampe :

Run: `python3 outils/console.py --port <port> "lampe 1 niveau 100" "lampe 1 niveau 700" "lampe 1 off" "lampe 1 on" "lampe 1 niveau 400" "lampe 2 niveau 900" "lampe 2 off" "lampe 2 niveau 250" "lampe 2 on" "lampe 2 niveau 600" "@3" "lampes"`
Expected : chaque ordre confirmé (Δa = 0), délai maximal sous 1 s ; la lampe 1 finit allumée à 40 %, la lampe 2 allumée à 60 %.

- [ ] **Step 10 : verdict (règle 5.8).**

Réussi si les deux lampes ont au moins 95 % de relectures répondues sur 30 min, et si au plus 1 % des ordres de Maison échouent ou dépassent une seconde.
- **Réussi** : une seule C6. Continuer à la Task 9.
- **Échoué : STOP.** Consigner (Step 11), puis écrire avec Djoko un plan 2b, avec les leviers de 5.8 dans l'ordre : priorités de coexistence d'ESP-IDF, Thread dormant avec relève rapide, puis une 2ᵉ C6. Les Tasks 9 à 11 attendent ce plan.

- [ ] **Step 11 : consigner.**

À la fin de `docs/BANC.md`, ajouter, avec les valeurs relevées :

```markdown
## Phase 1 : banc C, radio partagée (firmware du pont)

Procédure : plan 2, Task 8. Firmware du commit `<commit>`, Thread en enfant non dormant (MED), relecture au groupe toutes les 5 s, amaran Desktop fermé.

| mesure | lampe 1 | lampe 2 | seuil (spec 5.8) |
|---|---|---|---|
| relectures répondues sur 30 min | <r>/<n> (<p> %) | <r>/<n> (<p> %) | au moins 95 % |
| ordres de Maison : salves, échecs, au-delà d'1 s | <s>, <a>, <l> | (les deux lampes) | au plus 1 % |
| délai de confirmation, moyen et maximal | <m> ms, <M> ms | | |
| ordres de la console : salves, échecs, délai maximal | <s>, <a>, <M> ms | | |

Verdict : <une C6 suffit / deux C6>.

Mémoire : image `<taille>` ; RAM statique `<n>` o ; pile libre la plus basse `<tâche>` `<n>` o ; tas libre au plus bas `<n>` o.

Remarques : <noms repris par Maison ou non ; incidents>.
```

Dans `README.md`, remplacer la ligne de la phase P1 du tableau `## État` par :

```markdown
| P1 | Matter sur la même carte, et banc de la radio partagée entre Thread et Bluetooth : une ou deux C6 | faite (<date>) : <verdict> ; <p1> % et <p2> % des relectures répondues, <s> ordres de Maison, <a> échec |
```

Run: `git add docs/BANC.md README.md && git commit -m "$(printf "Consigner le banc C : appairage dans Maison et radio partagee entre Thread et Bluetooth\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"`

**CHECKPOINT.** Montrer le verdict à Djoko avant la Task 9. Pousser seulement avec son accord.

---

### Task 9: Le socle du Halo : voyant et bouton BOOT, logique testée sur le Mac

**Files:**
- Create: `components/socle/CMakeLists.txt`
- Create: `components/socle/include/status_led.h`, `components/socle/status_led.cpp`
- Create: `components/socle/include/boot_button.h`, `components/socle/boot_button.cpp`
- Create: `tests/hote/test_socle.cpp`
- Modify: `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : le pont Halo, dépôt local `~/Documents/Dev/esp32/benq`, commit `3f82f76`, en lecture seule (`git show`) : `src/status_led.h`, `src/status_led.cpp`, `src/boot_button.h`, `src/boot_button.cpp`, `tools/host_tests/test_halo1.cpp`.
- Produces (espaces de noms du Halo, inchangés) :
  - `statusled::Logic` : `setNet(Net, now)`, `setIdentify(bool, now)`, `setFault(bool, now)`, `setButton(Button, now)`, `delivered(now)`, `unreachable(now)`, `frame(now)` (rend `Frame {p, c}`), `startTest(now)`, `stopTest()`, `testing()` ;
  - `statusled::Net::{Unpaired, Offline, Online}`, `statusled::Rgb {r, g, b}`, `statusled::buttonFor(bootbtn::Phase)`, `statusled::patternName(Pattern)`, `statusled::kTest`, `statusled::TestStep {p, ms}`, `statusled::testTotalMs()`, `statusled::kMax`, `statusled::kRebootFlashMs` ;
  - `statusled::effectEnd(uint32_t end, uint8_t effect, uint32_t now)`, `statusled::effectPending(uint32_t end, uint32_t now)` (effets d'Identify) ;
  - `bootbtn::Machine` : `begin(bool low, now)`, `update(bool low, now)` (rend un `Event`), `phase()`, `lastPressMs()`, `lastGapMs()` ;
  - `bootbtn::Event::{None, Armed, Cancelled, Unsure, Dropped, BootReleased, Reboot, Unpair}`, `bootbtn::Phase` (dont `Unpair`), `bootbtn::kSettleMs`, `bootbtn::kRebootDelayMs`.

Pourquoi (spec 7.4 et 7.6 : « comme sur le Halo ») :
- la logique du voyant et du bouton est du C++17 pur (`<stdint.h>`), éprouvée sur le Halo : priorités et intensités des motifs, `led test`, effets d'Identify, machine du bouton (action au relâchement, 8 s pour désappairer, appui incertain ignoré) ;
- on reprend le haut de chaque fichier, sans les moitiés `#ifdef ARDUINO` : la carte est portée en ESP-IDF à la Task 10 ;
- trois libellés de `patternName()` changent : ceux du Halo parlent de sa lampe et de son module radio ;
- les tests d'origine (`testStatusLed`, `testBootButton`) viennent avec, inchangés : 79 023 vérifications.

- [ ] **Step 1 : les tests d'abord.**

Depuis la racine du dépôt :

```bash
H=~/Documents/Dev/esp32/benq
{ cat <<'FIN'
// Tests sur le Mac du socle repris du pont Halo (voyant et bouton BOOT) :
// testStatusLed et testBootButton de tools/host_tests/test_halo1.cpp du Halo
// (commit 3f82f76), inchanges. Lancer : sh tests/hote/lancer.sh
#include <initializer_list>
#include <stdio.h>
#include <string.h>

#include "boot_button.h"
#include "status_led.h"

static int gChecks = 0, gFails = 0;

#define CHECK(cond, ...)                                      \
  do {                                                        \
    gChecks++;                                                \
    if (!(cond)) {                                            \
      if (++gFails <= 40) {                                   \
        printf("ECHEC %s:%d : ", __FILE__, __LINE__);         \
        printf(__VA_ARGS__);                                  \
        printf("\n");                                         \
      }                                                       \
    }                                                         \
  } while (0)

FIN
  git -C "$H" show 3f82f76:tools/host_tests/test_halo1.cpp | sed -n '1795,2558p'
  cat <<'FIN'

int main() {
  testStatusLed();
  testBootButton();
  printf("socle : %d verifications, %d echecs\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
FIN
} > tests/hote/test_socle.cpp
```

Les lignes 1795 à 2558 du Halo sont ses fonctions `testStatusLed()` et `testBootButton()`, avec leurs aides. Le haut du fichier (la macro `CHECK`) et le `main` sont ceux ci-dessus.

Dans `tests/hote/lancer.sh`, avant `echo "tests hote : tout est vert"`, ajouter :

```sh
# Socle repris du Halo : C++17, comme ses tests d'origine.
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/socle/include components/socle/status_led.cpp \
  components/socle/boot_button.cpp tests/hote/test_socle.cpp -o "$SORTIE/test_socle"
"$SORTIE/test_socle"
```

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation (`boot_button.h` introuvable).

- [ ] **Step 2 : la logique, copiée du Halo.**

```bash
H=~/Documents/Dev/esp32/benq
mkdir -p components/socle/include
git -C "$H" show 3f82f76:src/status_led.h   | sed -n '1,159p' > components/socle/include/status_led.h
git -C "$H" show 3f82f76:src/status_led.cpp | sed -n '1,230p' > components/socle/status_led.cpp
git -C "$H" show 3f82f76:src/boot_button.h  | sed -n '1,110p' > components/socle/include/boot_button.h
git -C "$H" show 3f82f76:src/boot_button.cpp | sed -n '1,143p' > components/socle/boot_button.cpp
```

Chaque plage s'arrête avant la partie « Cote carte » du fichier : le code Arduino, que la Task 10 remplace.

Dans `components/socle/status_led.cpp`, fonction `patternName()`, remplacer les trois lignes :

```cpp
    case Pattern::Unreachable: return "lampe injoignable (rouge x3)";
    case Pattern::RadioFault: return "module radio en panne (rouge fixe)";
    case Pattern::Delivered: return "consigne livree (eclat vert)";
```

par :

```cpp
    case Pattern::Unreachable: return "ordre abandonne apres 3 essais (rouge x3)";
    case Pattern::RadioFault: return "Bluetooth Mesh inoperant (rouge fixe)";
    case Pattern::Delivered: return "ordre confirme par la lampe (eclat vert)";
```

`components/socle/CMakeLists.txt` :

```cmake
# Logique pure du socle, reprise du pont Halo (commit 3f82f76) : voyant et
# bouton BOOT. Testee sur le Mac (tests/hote/test_socle.cpp).
idf_component_register(SRCS "status_led.cpp" "boot_button.cpp"
                       INCLUDE_DIRS "include")
```

- [ ] **Step 3 : la copie est exacte.**

Run: `shasum -a 256 components/socle/include/status_led.h components/socle/status_led.cpp components/socle/include/boot_button.h components/socle/boot_button.cpp tests/hote/test_socle.cpp`
Expected :

```
de5b0633c816573bb081686de88a0e70e3255b753fd77bd7fb2a11e2be721bb4  components/socle/include/status_led.h
17cc9211dd0b71138b47d8b185d1bad7fc20acc523b7cba956cee90a1e237ddc  components/socle/status_led.cpp
43e0865bfc8214b43bcd03e4bf6602c5e6429e3169d75c982e2e13176134482d  components/socle/include/boot_button.h
12650581b9ae60628c96a88072722ff4b9b3d2c6ddfbfda3b2b68ca05a727be2  components/socle/boot_button.cpp
1ca8add5370e61291910f860cdeeb325f1a4928ac68849ec286cda01c5d8a529  tests/hote/test_socle.cpp
```

Une somme différente : refaire le step concerné, sans retoucher le fichier à la main.

- [ ] **Step 4 : les tests passent.**

Run: `sh tests/hote/lancer.sh`
Expected : `socle : 79023 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 5 : commit.**

```bash
git add components/socle tests/hote/test_socle.cpp tests/hote/lancer.sh
git commit -m "$(printf "Reprendre du pont Halo la logique du voyant et du bouton BOOT, avec ses tests\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 10: Le socle sur la carte : voyant, bouton BOOT, Identify, `led` et `cause`

**Files:**
- Create: `firmware/main/ws2812.h`, `firmware/main/ws2812.c`
- Create: `firmware/main/socle.h`, `firmware/main/socle.cpp`
- Modify: `firmware/main/pont_matter.h`, `firmware/main/pont_matter.cpp` (Identify)
- Modify: `firmware/main/tache_lampes.c` (panne du Mesh au voyant), `firmware/main/console_pont.c` (`led`, `cause`, tâche `socle`), `firmware/main/app_main.cpp` (`socle_demarrer`)

**Interfaces:**
- Consumes :
  - `status_led.h`, `boot_button.h` (Task 9) : `statusled::Logic`, `statusled::Net`, `statusled::buttonFor`, `statusled::patternName`, `statusled::kTest`, `statusled::testTotalMs`, `statusled::kMax`, `statusled::kRebootFlashMs`, `statusled::effectEnd`, `statusled::effectPending` ; `bootbtn::Machine`, `bootbtn::Event`, `bootbtn::Phase`, `bootbtn::kSettleMs`, `bootbtn::kRebootDelayMs` ;
  - `pont_matter.h` (Task 6) : `pont_appaire`, `pont_thread_attache`, `pont_desappairer` ;
  - `tache_lampes.h` (Task 7) : `tache_lampes_confirmes`, `tache_lampes_abandons` ; le diagnostic de `tache_lampes.c` (`s_diag.etat`, `DIAG_OK`).
- Produces :
  - `firmware/main/socle.h` : `esp_err_t socle_demarrer(void);`, `void socle_panne_mesh(bool oui);`, `int socle_commande_led(int argc, char **argv);`, `int socle_commande_cause(int argc, char **argv);` ;
  - `firmware/main/ws2812.h` : `esp_err_t ws2812_demarrer(int gpio);`, `esp_err_t ws2812_ecrire(uint8_t r, uint8_t g, uint8_t b);` ;
  - `pont_matter.h` : `bool pont_identifie(void);`.

Pourquoi (spec 7.3, 7.4, 7.6 ; moitié Arduino de `status_led.cpp` et `boot_button.cpp` du Halo, portée en ESP-IDF) :
- une tâche `socle` à 1 ms : d'abord le bouton, puis le voyant, dans l'ordre de la boucle du Halo (`CONFIG_FREERTOS_HZ=1000`, Task 6) ;
- la WS2812 d'IO8 par le RMT d'ESP-IDF (exemple `led_strip_simple_encoder`), sans composant géré ; on n'écrit que les changements de couleur ;
- IO9 est une broche de démarrage : un reset BOOT tenu mène au mode téléchargement. D'où une garde sur **tous** les resets logiciels, enregistrée avant Matter : ESP-IDF appelle les gestionnaires d'arrêt du dernier enregistré au premier, elle passe donc juste avant le reset. Les actions du bouton ont lieu au relâchement, après une dernière relecture de la broche ;
- désappairage : `pont_desappairer()`. La pile efface ses espaces (`chip-config`, `chip-counters`, les fabriques, Thread) ; l'espace `amaran` (clés, lampes) reste (7.7). Filet : toujours en marche 10 s plus tard, on redémarre ;
- le voyant suit des états (appairé, Thread attaché, Identify, panne du Mesh) et deux compteurs (ordres confirmés, abandonnés) : les producteurs ignorent le voyant, comme sur le Halo ;
- rouge fixe seulement une fois appairé (amendement 8) ;
- Identify : START et STOP par endpoint, et une fin d'effet, car la pile n'envoie jamais STOP après un effet (leçon du Halo). Le voyant fait l'arc-en-ciel ; la lampe ne bouge pas (6.1) ;
- la commande `led` tourne dans la tâche de la console : elle dépose des demandes, et lit ce que la tâche `socle` publie. `statusled::Logic` n'est touché que par la tâche `socle` ;
- `cause` : la raison du dernier démarrage, comme sur le Halo (utile au banc T10).

- [ ] **Step 1 : la WS2812.**

`firmware/main/ws2812.h` :

```c
// La WS2812 de la C6 SuperMini (IO8), par le RMT d'ESP-IDF.
#pragma once

#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// A appeler apres le demarrage (IO8 est une broche de strapping) : met la LED au noir.
esp_err_t ws2812_demarrer(int gpio);
// Une couleur (0..255 par canal), envoyee dans l'ordre G, R, B de la WS2812.
esp_err_t ws2812_ecrire(uint8_t r, uint8_t g, uint8_t b);

#ifdef __cplusplus
}
#endif
```

`firmware/main/ws2812.c` :

```c
// La WS2812 de la C6 SuperMini, d'apres l'exemple d'ESP-IDF
// peripherals/rmt/led_strip_simple_encoder : un pixel, ordre G, R, B (verifie
// sur la carte avec 'led test' pour le Halo).
#include "ws2812.h"

#include "driver/rmt_encoder.h"
#include "driver/rmt_tx.h"

#define RESOLUTION_HZ 10000000  // 1 pas = 0,1 us

static const rmt_symbol_word_t SYMBOLE_0 = {.level0 = 1, .duration0 = 3, .level1 = 0, .duration1 = 9};  // 0,3 us / 0,9 us
static const rmt_symbol_word_t SYMBOLE_1 = {.level0 = 1, .duration0 = 9, .level1 = 0, .duration1 = 3};  // 0,9 us / 0,3 us
static const rmt_symbol_word_t SYMBOLE_RAZ = {.level0 = 0, .duration0 = 250, .level1 = 0, .duration1 = 250};  // 50 us

static rmt_channel_handle_t s_canal;
static rmt_encoder_handle_t s_encodeur;

static size_t encoder(const void *donnees, size_t taille, size_t ecrits, size_t libres, rmt_symbol_word_t *symboles,
                      bool *fini, void *arg) {
  (void)arg;
  if (libres < 8) return 0;
  const size_t pos = ecrits / 8;
  const uint8_t *octets = donnees;
  if (pos < taille) {
    for (int i = 0; i < 8; i++) symboles[i] = (octets[pos] & (0x80 >> i)) ? SYMBOLE_1 : SYMBOLE_0;
    return 8;
  }
  symboles[0] = SYMBOLE_RAZ;
  *fini = true;
  return 1;
}

esp_err_t ws2812_demarrer(int gpio) {
  const rmt_tx_channel_config_t canal = {
      .gpio_num = gpio,
      .clk_src = RMT_CLK_SRC_DEFAULT,
      .resolution_hz = RESOLUTION_HZ,
      .mem_block_symbols = 48,
      .trans_queue_depth = 2,
  };
  esp_err_t err = rmt_new_tx_channel(&canal, &s_canal);
  if (err != ESP_OK) return err;
  const rmt_simple_encoder_config_t codeur = {.callback = encoder};
  err = rmt_new_simple_encoder(&codeur, &s_encodeur);
  if (err == ESP_OK) err = rmt_enable(s_canal);
  if (err == ESP_OK) err = ws2812_ecrire(0, 0, 0);  // elle garde sa couleur a travers un reset
  return err;
}

esp_err_t ws2812_ecrire(uint8_t r, uint8_t g, uint8_t b) {
  if (!s_canal) return ESP_ERR_INVALID_STATE;
  static uint8_t grb[3];  // lu par le RMT pendant l'envoi
  grb[0] = g;
  grb[1] = r;
  grb[2] = b;
  const rmt_transmit_config_t envoi = {.loop_count = 0};
  esp_err_t err = rmt_transmit(s_canal, s_encodeur, grb, sizeof(grb), &envoi);
  if (err == ESP_OK) err = rmt_tx_wait_all_done(s_canal, 10);
  return err;
}
```

- [ ] **Step 2 : le socle.**

`firmware/main/socle.h` :

```c
// Socle repris du pont Halo : voyant WS2812 (IO8) et bouton BOOT (IO9), plus
// les commandes `led` et `cause` (spec 7.4 a 7.6).
#pragma once

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// A demarrer tot, avant Matter : la garde du bouton passe alors en dernier avant
// chaque reset, et le voyant montre l'etat des le demarrage.
esp_err_t socle_demarrer(void);
// Bluetooth Mesh inoperant (spec 7.3) : rouge fixe une fois le pont appaire.
void socle_panne_mesh(bool oui);
// Commande `led [test|stop]`.
int socle_commande_led(int argc, char **argv);
// Commande `cause` : pourquoi la carte a redemarre la derniere fois.
int socle_commande_cause(int argc, char **argv);

#ifdef __cplusplus
}
#endif
```

`firmware/main/socle.cpp` :

```cpp
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
```

- [ ] **Step 3 : Identify, côté Matter.**

Dans `firmware/main/pont_matter.h` :

1. remplacer :

```c
// publie sans echo, abonnements plafonnes. Ecrit en C++ (esp-matter),
```

par :

```c
// publie sans echo, abonnements plafonnes, identite. Ecrit en C++ (esp-matter),
```

2. remplacer :

```c
void pont_desappairer(void);
```

par :

```c
void pont_desappairer(void);
// Un controleur demande l'identification (IdentifyTime ou un effet en cours).
bool pont_identifie(void);
```

Dans `firmware/main/pont_matter.cpp` :

1. remplacer :

```cpp
#include "mesh_amaran.h"
```

par :

```cpp
#include "mesh_amaran.h"
#include "status_led.h"
```

2. remplacer :

```cpp
static volatile uint32_t s_abo_demandes, s_abo_plafonnes, s_abo_etablis, s_abo_termines;
```

par :

```cpp
static volatile uint32_t s_abo_demandes, s_abo_plafonnes, s_abo_etablis, s_abo_termines;
// Identify : endpoints en IdentifyTime (bits), et fin d'effet par endpoint (ms,
// 0 = aucun) : la pile n'envoie jamais de STOP apres un effet (lecon du Halo).
static volatile uint32_t s_identifie;
static volatile uint32_t s_effet_fin[LAMPES_MAX + 2];
```

3. remplacer :

```cpp
static void rappel_evenement(const chip::DeviceLayer::ChipDeviceEvent *ev, intptr_t arg) {
```

par :

```cpp
// Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1) :
// seul le voyant fait l'arc-en-ciel, pour un autre controleur.
static esp_err_t rappel_identification(identification::callback_type_t type, uint16_t ep, uint8_t effet,
                                       uint8_t variante, void *priv) {
  (void)variante;
  (void)priv;
  if (ep >= LAMPES_MAX + 2) return ESP_OK;
  switch (type) {
    case identification::callback_type_t::START:
      s_identifie = s_identifie | (1u << ep);
      break;
    case identification::callback_type_t::STOP:
      s_identifie = s_identifie & ~(1u << ep);
      break;
    case identification::callback_type_t::EFFECT:
      s_effet_fin[ep] = statusled::effectEnd(s_effet_fin[ep], effet, (uint32_t)(esp_timer_get_time() / 1000));
      break;
  }
  return ESP_OK;
}

static void rappel_evenement(const chip::DeviceLayer::ChipDeviceEvent *ev, intptr_t arg) {
```

4. remplacer :

```cpp
  // Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1).
  node_t *noeud = node::create(&cfg_noeud, rappel_attribut, NULL);
```

par :

```cpp
  node_t *noeud = node::create(&cfg_noeud, rappel_attribut, rappel_identification);
```

5. remplacer :

```cpp
void pont_desappairer(void) { esp_matter::factory_reset(); }
```

par :

```cpp
void pont_desappairer(void) { esp_matter::factory_reset(); }

bool pont_identifie(void) {
  if (s_identifie) return true;
  const uint32_t t = (uint32_t)(esp_timer_get_time() / 1000);
  for (int ep = 0; ep < LAMPES_MAX + 2; ep++) {
    if (statusled::effectPending(s_effet_fin[ep], t)) return true;
  }
  return false;
}
```

- [ ] **Step 4 : la panne du Mesh au voyant.**

Dans `firmware/main/tache_lampes.c` :

1. remplacer :

```c
#include "pont_matter.h"
```

par :

```c
#include "pont_matter.h"
#include "socle.h"
```

2. remplacer :

```c
// Bluetooth Mesh inoperant (spec 7.3) : message a la console.
```

par :

```c
// Bluetooth Mesh inoperant (spec 7.3) : message a la console, rouge fixe au voyant.
```

3. remplacer :

```c
    printf("!! Bluetooth Mesh inoperant : %s\n", diagnostic_texte(s_diag.etat));
  }
}
```

par :

```c
    printf("!! Bluetooth Mesh inoperant : %s\n", diagnostic_texte(s_diag.etat));
  }
  socle_panne_mesh(s_diag.etat != DIAG_OK);
}
```

- [ ] **Step 5 : `led`, `cause`, et la tâche `socle` dans `taches`.**

Dans `firmware/main/console_pont.c` :

1. remplacer :

```c
#include "pont_matter.h"
```

par :

```c
#include "pont_matter.h"
#include "socle.h"
```

2. remplacer :

```c
static const char *const TACHES[] = {"lampes", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP", "ot_task",
                                     "console_repl"};
```

par :

```c
static const char *const TACHES[] = {"lampes", "socle", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP",
                                     "ot_task", "console_repl"};
```

3. remplacer :

```c
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
```

par :

```c
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
      {.command = "led", .help = "led [test|stop] : motif du voyant ; test = chaque motif a tour de role", .func = socle_commande_led},
      {.command = "cause", .help = "pourquoi la carte a redemarre la derniere fois", .func = socle_commande_cause},
```

- [ ] **Step 6 : le socle démarre en premier.**

Dans `firmware/main/app_main.cpp` :

1. remplacer :

```cpp
#include "pont_matter.h"
```

par :

```cpp
#include "pont_matter.h"
#include "socle.h"
```

2. remplacer :

```cpp
  console_pont_demarrer(&cfg);
```

par :

```cpp
  // Le socle d'abord : la garde du bouton BOOT passe ainsi en dernier avant tout
  // reset, et le voyant montre l'etat des le demarrage.
  if (socle_demarrer() != ESP_OK) ESP_LOGE(TAG, "socle (voyant, bouton) non demarre");
  console_pont_demarrer(&cfg);
```

- [ ] **Step 7 : compiler, et vérifier.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py reconfigure build 2>&1 | tee "${TMPDIR:-/tmp}/amaran-firmware.log" | tail -5 && idf.py size && cd ..`
Expected : `Project build complete.` ; `amaran_pont.bin binary size 0x1a4..... bytes` (environ 1,64 Mo, 58 % libres).

Run: `/usr/bin/grep -E "(firmware/main|components/(lampes|mesh|telink|socle))/[^ ]*: warning:" "${TMPDIR:-/tmp}/amaran-firmware.log"`
Expected : aucune ligne.

Run: `sh tests/hote/lancer.sh`
Expected : `tests hote : tout est vert`.

- [ ] **Step 8 : commit.**

```bash
git add firmware/main
git commit -m "$(printf "Ajouter le socle du Halo au pont : voyant, bouton BOOT, Identify, commandes led et cause\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 11: Au banc : T1 à T10, puis la documentation (Claude et Djoko)

**Qui :** Claude, le contrôleur, avec Djoko présent. **Pas de sous-agent** : on flashe, on émet vers les lampes, et T9 relit la base d'amaran Desktop.

**Files:**
- Modify: `docs/BANC.md` (procédure et résultats de la phase 2), `README.md`

**Interfaces:**
- Consumes : le firmware complet (Tasks 6, 7 et 10), appairé dans Maison à la Task 8 ; `outils/console.py`, `outils/cles_amaran.py`.
- Produces : les bancs T de la spec 8.4, et un README qui dit comment installer et utiliser le pont.

Pourquoi : les bancs T sont l'acceptation de la v1 (spec 8.4). Chacun se lit dans Maison, sur la lampe et à la console.

- [ ] **Step 1 : flasher le firmware complet, avec l'accord de Djoko.**

Run: `git status --short && sh tests/hote/lancer.sh && export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py build | tail -2 && cd ..`
Expected : `git status` vide ; tout vert ; `Project build complete.`

Reconnaître la carte par son `SER=` (Task 8, Step 2), puis demander à Djoko : « Je flashe le firmware complet sur la C6 du pont (`<port>`) ? ». Sans effacer : l'appairage et les clés restent.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py -p <port> flash && cd ..`

Run: `python3 outils/console.py --port <port> "@20" "cause" "matter" "mesh" "led" "led test" "@22" "taches"`
Expected :
- `cause du dernier demarrage` : `reinitialisation par l'USB` ou `redemarrage logiciel` ;
- `matter` : toujours appairé, `Thread : child (attache)` ; `mesh pret : oui` ;
- le voyant : éteint, avec une brève lueur blanche toutes les 10 s ; `led` : `motif     : operationnel (lueur blanche toutes les 10 s)` ;
- `led test` : Djoko voit chaque motif de la liste imprimée, dans l'ordre, pendant 21 s ;
- `taches` : la tâche `socle` et les autres au-dessus de 512 o libres.

- [ ] **Step 2 : T1, ordres depuis Maison.**

Djoko, dans Maison, pour chaque lampe : allumer, régler 50 %, régler 25 %, régler 100 %, éteindre. Il regarde la lampe après chaque ordre.

Run (après) : `python3 outils/console.py --port <port> "lampes"`
Expected : la lampe obéit à chaque ordre ; un éclat vert au voyant par ordre ; à 50 % dans Maison, `lue : marche 50,0 %` à la console (conversion linéaire, 6.2) ; `abandonnes` inchangé. Les tuiles portent les noms d'amaran Desktop.

- [ ] **Step 3 : T2, curseur glissé vite.**

Djoko fait glisser vite le curseur de la lampe 1, d'un bout à l'autre, pendant 5 s environ, et le lâche sur une valeur.

Run (avant et après) : `python3 outils/console.py --port <port> "lampes" "mesh"`
Expected : la lampe suit, puis s'arrête à la valeur lâchée ; `lampes` : `consigne : aucune en cours`, aucun abandon ; les salves (Δ confirmés + Δ abandonnés) sont bien moins nombreuses que les écritures (Δ `ordres`) ; `mesh` : `0 refus`.

- [ ] **Step 4 : T3, la molette.**

Lampe allumée (une lampe éteinte par Maison ignore sa molette : R4). Djoko tourne la molette de la lampe 1, trois fois, en notant quand Maison suit ; de même pour la lampe 2.
Expected : Maison montre la nouvelle luminosité en 5 s environ (une relecture toutes les 5 s).

- [ ] **Step 5 : T4, amaran Desktop.**

amaran Desktop ouvert (réparé : spec 8.1). Djoko change la luminosité de la lampe 1, puis l'éteint, depuis l'app.
Expected : Maison suit en 5 s environ ; l'app fonctionne normalement. Qu'elle ne suive pas les ordres de Maison est connu (R6) et accepté (spec 11).

- [ ] **Step 6 : T5, lampe coupée.**

Djoko coupe l'alimentation de la lampe 2 (bouton d'alimentation, ou secteur), puis la rallume au bout d'une minute.

Run: `python3 outils/console.py --port <port> "lampes" "@25" "lampes" "@60" "lampes"`
Expected : Maison affiche « Pas de réponse » pour la lampe 2 en 15 à 20 s (3 relectures sans réponse), et `lampes` dit `PAS DE REPONSE` ; rallumée, la lampe revient allumée vers 40 % (R4), et Maison le montre en 5 s environ, joignable.

- [ ] **Step 7 : T6, redémarrage du pont.**

Djoko regarde les lampes.

Run: `python3 outils/console.py --port <port> "redemarre" "@30" "cause" "lampes" "mesh"`
Expected : aucune lampe ne bouge ; `redemarrage logiciel` ; `lampes` : `ordres : 0` ; `mesh` : les messages émis sont des relectures, une toutes les 5 s environ ; Maison garde les lampes joignables et montre leur état réel.

- [ ] **Step 8 : T7, Thread perdu.**

Djoko choisit comment couper le réseau Thread vu par le pont (débrancher les routeurs de bordure, ou éloigner la carte), puis le rétablit au bout de 2 min.

Run: `python3 outils/console.py --port <port> "matter" "@120" "matter" "@10" "matter" "@10" "matter" "@10" "matter" "@10" "matter" "@10" "matter"`
Expected : sans Thread, le rôle n'est plus `child` et le voyant passe à l'orange lent ; au retour, `Thread : child (attache)`, puis au moins un abonnement actif en 60 s au plus ; un ordre de Maison marche de nouveau.

- [ ] **Step 9 : T8, bouton BOOT.**

Djoko appuie :
1. brièvement : éclat blanc, puis la carte redémarre ; `cause` dit `redemarrage logiciel` ;
2. 4 s : la console dit `appui de ... ms (2 a 8 s) : annule, rien fait` ;
3. 8 s : le voyant clignote rouge, noir, violet, noir ; Djoko relâche. La console dit `appui long ... retrait de toutes les fabriques Matter`, la carte redémarre, et le voyant clignote en bleu.

Run (après le 3) : `python3 outils/console.py --port <port> "matter" "mesh"`
Expected : `mise en service : EN ATTENTE` ; les clés sont toujours là (mêmes empreintes). Djoko retire le pont de Maison, puis l'appaire de nouveau (Task 8, Step 6) : le voyant repasse au blanc, les lampes reviennent.

- [ ] **Step 10 : T9, clés oubliées puis rechargées.**

Run: `python3 outils/console.py --port <port> "mesh oublie" "@25" "mesh"`
Expected : la carte redémarre ; `!! Bluetooth Mesh inoperant : cles absentes : lancer outils/cles_amaran.py` à la console ; voyant rouge fixe ; Maison affiche « Pas de réponse » pour les deux lampes en 15 à 20 s.

Puis (Claude seul) : `python3 outils/cles_amaran.py --port <port>`
Expected : la carte redémarre ; `mesh pret : oui` ; voyant revenu ; les lampes joignables, avec leur état réel.

Noter si Maison recrée les tuiles des lampes au retour : le temps de l'oubli, leur UniqueID n'était plus leur MAC mais `amaran-1` et `amaran-2` (Task 6). Si c'est le cas, le dire à Djoko : un remède (garder la liste des lampes à l'oubli) serait un petit changement du plan 1.

- [ ] **Step 11 : T10, endurance 24 h.**

Djoko se sert des lampes normalement. Le Mac ne dort pas (`caffeinate`).

Run: `caffeinate -i python3 outils/console.py --port <port> "cause" "lampes" "mesh" "taches" "@86400" "cause" "lampes" "mesh" "taches" "matter"`
Expected, sur les 24 h :
- aucun redémarrage : les compteurs de `lampes` ont continué (environ 17 000 relectures) ;
- au moins 95 % des relectures répondues, pour chaque lampe ;
- `evenements perdus 0`, `0 refus` ; le tas libre au plus bas ne baisse plus après la première heure ; aucune tâche sous 512 o ;
- la séquence Mesh avance d'environ une unité par relecture et par trame émise, loin de `0x700000` ;
- au moins un abonnement actif à la fin.

- [ ] **Step 12 : consigner les bancs.**

À la fin de `docs/BANC.md`, ajouter, avec les valeurs relevées :

```markdown
## Phase 2 : bancs T (firmware complet)

Procédure : plan 2, Task 11. Firmware du commit `<commit>`.

| banc | date | résultat | remarques |
|---|---|---|---|
| T1 ordres depuis Maison | | | |
| T2 curseur glissé vite | | | écritures, salves |
| T3 molette | | | délai observé |
| T4 amaran Desktop | | | |
| T5 lampe coupée | | | délai du « Pas de réponse », état au retour |
| T6 redémarrage du pont | | | |
| T7 Thread perdu | | | délai de reprise des abonnements |
| T8 bouton BOOT | | | |
| T9 clés oubliées, rechargées | | | |
| T10 endurance 24 h | | | relectures répondues, tas au plus bas, séquence |
```

- [ ] **Step 13 : le README.**

Dans `README.md` :

1. sous `## État`, remplacer le paragraphe en gras par : `**Le pont marche : les deux lampes sont dans Maison.**` (préciser « sur une seule C6 » si le banc C l'a établi), et la ligne de la phase P2 du tableau par :

```markdown
| P2 | Produit : voyant, bouton, console, fiche produit ; bancs, puis endurance 24 h | faite (<date>) : T1 à T10 ; <résumé> |
```

2. remplacer le titre `## Ce que le pont fera` par `## Ce que fait le pont`, et mettre ses trois points au présent ;

3. avant `## Clés du réseau`, ajouter :

````markdown
## Installer

Il faut ESP-IDF v5.5.4 et esp-matter (commit `c5b9ea8`) dans `~/esp`, une ESP32-C6 SuperMini, et un routeur de bordure Thread (HomePod mini, Apple TV).

1. Compiler et flasher. Le port est toujours donné explicitement :

   ```bash
   source ~/esp/esp-idf/export.sh && source ~/esp/esp-matter/export.sh
   cd firmware && idf.py build && idf.py -p /dev/cu.usbmodemXXXX erase-flash flash
   ```

2. Charger les clés du réseau des lampes, lues dans la base d'amaran Desktop :

   ```bash
   python3 outils/cles_amaran.py --port /dev/cu.usbmodemXXXX
   ```

3. Appairer. `python3 outils/console.py --port /dev/cu.usbmodemXXXX matter` imprime le code manuel. Dans Maison : « + », « Ajouter un accessoire », « Plus d'options… », puis ce code. Le pont utilise les codes de test du SDK Matter : Maison prévient qu'il n'est pas certifié, « Ajouter quand même ».

Une fois appairé, le pont entre dans le réseau des lampes, et elles apparaissent sous leurs noms d'amaran Desktop.

## Voyant et bouton

| voyant | sens |
|---|---|
| bleu clignotant | pas appairé à Maison |
| orange lent | réseau Thread absent |
| éteint, brève lueur blanche toutes les 10 s | tout va bien |
| rouge fixe | Bluetooth Mesh inopérant : la console dit pourquoi |
| éclat vert | ordre confirmé par la lampe |
| rouge ×3 | ordre abandonné après 3 essais |
| arc-en-ciel | un contrôleur demande l'identification |
| rouge, noir, violet, noir, vite | BOOT tenu 8 s : relâcher pour désappairer |
| éclat blanc | BOOT court : redémarrage |

Bouton BOOT : appui court, redémarrage ; de 2 à 8 s, rien ; 8 s ou plus, désappairage de Maison. Les clés restent.

## Console

Sur l'USB, en français (`python3 outils/console.py --port <port> "<commande>"`, ou tout terminal série) :
- `lampes` : état lu, consigne, joignabilité, relectures et ordres de chaque lampe ;
- `lampe <n> on|off|niveau <0-1000>|releve` ;
- `mesh` : réseau, empreintes des clés, compteurs ; `mesh releve <s>`, `mesh ecoute on|off`, `mesh autotest`, etc. ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre`.

## À savoir

- Une lampe éteinte depuis Maison, ou depuis amaran Desktop, ignore sa molette et le bouton de sa molette. Pour la rallumer à la main : couper puis remettre son alimentation ; elle revient allumée vers 40 %.
- Maison suit la molette et amaran Desktop en 5 s environ : les lampes ne signalent rien d'elles-mêmes, et le pont les relit toutes les 5 s.
- amaran Desktop, lui, ne suit pas les ordres venus de Maison.
````

4. dans `## Crédits`, avant la dernière phrase, ajouter :

```markdown
Le voyant et le bouton BOOT reprennent la logique du pont Halo
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
du même auteur) : `components/socle`, avec ses tests.
```

Run: `git add docs/BANC.md README.md && git commit -m "$(printf "Consigner les bancs T et documenter l'installation du pont\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"`

- [ ] **Step 14 : pousser, avec l'accord de Djoko.**

Montrer à Djoko `git log --oneline origin/main..main` et le résumé des bancs. Demander : « Je pousse sur GitHub ? ». Après son accord seulement :

Run: `git push origin main`

