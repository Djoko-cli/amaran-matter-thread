# Pont amaran, plan 3a : N lampes et catalogue de modèles : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le pont pilote autant de lampes que la carte en tient (16 au départ), de tout modèle du protocole Sidus. Seule la COB 60d est cataloguée ; un modèle inconnu est exposé en intensité seule. Les numéros d'endpoint sont stables par MAC, une lampe n'entre dans Maison qu'à sa première réponse, et son retrait est un geste explicite.

**Architecture:**
- Un composant neuf, `liste` (C pur, testé sur le Mac), porte la liste des lampes et le catalogue des modèles. La liste couvre la validation, la fusion au chargement, les drapeaux « vue » et « masquée », le format NVS et la conversion de l'ancien format.
- Le cœur `lampes` passe de 2 lampes à `LAMPES_CAPACITE` (16). Il sait qu'une lampe a été « entendue », alerte sous 95 % de relectures répondues sur 10 minutes, et republie une lampe dont l'endpoint vient d'être créé.
- `config_amaran` garde la liste en NVS, en un enregistrement versionné, et convertit une fois l'ancien format (EP2 et EP3 gardés).
- `mesh_console` charge une liste tout ou rien : `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>`.
- `pont_matter` recrée les endpoints des lampes exposées juste après `esp_matter::start()`, avec leur numéro (`bridged_node::resume`), ou en crée un neuf (`bridged_node::create`). C'est le schéma des exemples de pont d'esp-matter. Le compteur de numéros est celui d'esp-matter, qui ne recule jamais.
- La tâche `lampes` expose une lampe à sa première réponse, et exécute `mesh lampe <n> masquer|afficher`.

```
outils/cles_amaran.py ──USB──► mesh lampes N, mesh lampe n ... ──► config_amaran (NVS : liste v2)
                                                                        │ au demarrage
                     Maison ◄──Thread── pont_matter ◄── exposer/masquer ── tache lampes ◄── crochet
                                (EP2, EP3, ... stables)   (premiere reponse, console)   (lampes.c, N)
```

**Tech Stack:** ESP-IDF v5.5.4 (C11, C++17, FreeRTOS à 1 kHz, NimBLE, ESP-BLE-MESH, OpenThread MTD), esp-matter `c5b9ea8`, clang et clang++ pour les tests natifs, Python 3 (unittest) pour l'outil des clés.

**Spec:** `docs/superpowers/specs/2026-10-03-pont-amaran-n-lampes-design.md` : c'est l'autorité de ce plan, sections 4 à 12. La spec du pont, `docs/superpowers/specs/2026-09-28-pont-amaran-design.md`, reste la référence pour tout ce qu'elle ne change pas.

**Modèle :** les exemples de pont d'esp-matter (`~/esp/esp-matter/examples/bridge_apps`, `examples/common/app_bridge`, et le composant `components/esp_matter_bridge`), en lecture seule.
- Les endpoints pontés y sont recréés juste après `esp_matter::start()` (`resume`), puis activés (`endpoint::enable`).
- On les retire avec `endpoint::destroy`.

## Global Constraints

- ESP-IDF v5.5.4 dans `~/esp/esp-idf`, esp-matter commit `c5b9ea8` dans `~/esp/esp-matter`. Cible `esp32c6`, flash 4 Mo, une seule application (pas d'OTA).
- **ESP-IDF et esp-matter ne sont jamais modifiés** : le SmartButton et le Halo partagent l'installation. Le crochet passe par `-Wl,--wrap`. `components/mesh` refuse de compiler avec une autre version d'ESP-IDF.
- Pile Bluetooth : NimBLE. Dans le pont, c'est la pile Matter qui possède l'hôte.
- L'adresse Mesh de l'ESP32 est dans `0x7F00`–`0x7F7F`, **jamais `0x0001`** (l'adresse d'amaran Desktop). Aucune lampe ne peut avoir une adresse de cette plage.
- **Aucune clé** dans le dépôt, un journal ou un affichage. L'empreinte d'une clé = les 8 premiers chiffres hexa, en majuscules, de son SHA-256. La trace de la pile Mesh reste épinglée à ERROR : au-dessus, elle imprime des clés.
- Le dépôt est public : ni MAC complète (lampes, carte), ni numéro de série USB, ni numéro `AMARAN-…`, ni empreinte réelle de clé. La console, elle, est locale : elle peut montrer la MAC d'une lampe.
- `CONFIG_MBEDTLS_HARDWARE_AES=n`.
- Émission :
  - au moins 70 ms entre deux messages ;
  - un ordre part 2 fois, une demande d'état 2 fois ;
  - 3 copies réseau à 20 ms d'écart, TTL 3.
- **Capacité : 16 lampes** (`LISTE_CAPACITE` dans `components/liste`, `LAMPES_CAPACITE` dans `components/lampes`, égales par assertion), et `CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT=18` (noeud, agrégateur, 16 lampes).
- Français partout : code, console, commits, docs. Les commentaires du code sont **sans accents** (style du pont Halo).
- Commits : directement sur `main`, message en français, terminé par une ligne `Co-Authored-By: Claude …` (le modèle qui écrit le commit). **Aucun push sans l'accord de Djoko.**
- **Les sous-agents ne flashent jamais et n'ouvrent jamais de port série.**
  - Claude flashe avec l'accord de Djoko.
  - Djoko est présent dès qu'on émet vers les lampes.
- La carte du pont se reconnaît au champ `SER=` de `python -m serial.tools.list_ports -v`, jamais au nom du port. Le port est toujours donné explicitement. Ne jamais ouvrir ni flasher la C6 du maillage Thread BenQ, ni un écran LG (eux aussi en `usbmodem`).
- Seul Claude lit la base d'amaran Desktop (`~/Library/Containers/com.sidus.amaran-desktop`), pour charger les clés. Jamais un sous-agent.
- Dans les scripts et les commandes, utiliser `/usr/bin/grep` : le `grep` du poste est ugrep.
- Environnement, dans la même commande shell que `idf.py` : `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null`, suivi, pour le firmware du pont, de `&& source ~/esp/esp-matter/export.sh >/dev/null`. Le `PATH` d'abord : le Python 3.11 de PlatformIO, souvent en tête, fait échouer `export.sh`.
- `SRC_DIRS "."` : un fichier ajouté à `firmware/main` n'est compilé qu'après `idf.py reconfigure`. Un composant neuf dans `components/` aussi.
- `firmware/sdkconfig` et `ecoute/sdkconfig` sont ignorés par git et générés depuis les `sdkconfig.defaults`. Un défaut changé ne s'applique qu'après suppression du `sdkconfig`.
- Tests natifs : `sh tests/hote/lancer.sh`, tout vert avant chaque commit. Tests de l'outil : `python3 -m unittest discover -s outils -p "test_*.py"`.

## Choix fixés en préparant le plan

Le code de ce plan a été écrit, compilé (les deux firmwares, à chaque tâche) et testé sur le Mac dans une copie de travail avant d'être recopié ici. Ce prototype a fixé les choix suivants, déjà reportés dans la spec (commits `7c7f59b` et `1189b73`) :

1. **Le compteur de numéros d'endpoint est celui d'esp-matter** (`min_uu_ep_id` en NVS). Une lampe reçoit son numéro à sa première exposition. `bridged_node::resume` recrée un endpoint avec son numéro, seulement après `esp_matter::start()` : les endpoints des lampes y sont donc recréés juste après le démarrage, comme dans les exemples de pont d'esp-matter.
2. **Chargement tout ou rien.** `mesh lampes <N>` ouvre une liste ; `mesh lampe <n> <adresse> <mac> <code> <nom>` en donne chaque lampe (le code avant le nom, qu'un nombre peut terminer). Chaque ligne reçoit **une seule** réponse, `ok …` ou `erreur …` : l'outil des clés en attend une. La dernière lampe donnée, la liste est validée puis sauvée, et la réponse se termine par `; liste de N lampe(s) enregistree`.
3. **`mesh oublie` garde la liste** : les tuiles restent dans Maison, en « Pas de réponse », comme au banc T9.
4. **L'outil des clés ne connaît pas le catalogue** : il compare ce que la lampe déclare (`composition_data`) à ce que le pont annonce dans sa réponse.
5. **État intermédiaire des Tasks 2 et 3** : le pont garde ses deux tuiles fixes sous une constante `PONT_EMPLACEMENTS` (2), que la Task 4 supprime. Chaque tâche laisse les deux firmwares compilables et le pont utilisable avec ses deux lampes.
6. **Alerte de relectures** : 10 tranches d'une minute. Premier verdict après 10 minutes pleines. Une lampe muette (« Pas de réponse ») n'est pas concernée.
7. **Retirer une lampe de la liste lui fait perdre son numéro** (spec 5). Pour une absence, le geste est `masquer`, qui le garde. Le banc 2 porte donc sur masquer et afficher.
8. **Lampes fictives** pour les bancs 3 et 4 : `outils/cles_amaran.py --fictives N`.

## Carte des fichiers

| fichier | rôle | tâche |
|---|---|---|
| `components/liste/{CMakeLists.txt,include/liste.h,include/catalogue.h,liste.c,catalogue.c}` | liste des lampes et catalogue des modèles (C pur) | 1 (8) |
| `tests/hote/test_liste.c`, `tests/hote/lancer.sh` | tests de la liste et du catalogue | 1 (8) |
| `components/lampes/{include/lampes.h,lampes.c}`, `tests/hote/test_lampes.c` | cœur à N lampes, lampe entendue, alerte, publication forcée | 2 |
| `components/mesh/{CMakeLists.txt,include/config_amaran.h,config_amaran.c}` | liste en NVS, conversion de l'ancien format | 3 |
| `components/mesh/{include/mesh_console.h,mesh_console.c,include/mesh_amaran.h,mesh_amaran.c,crochet.c}` | chargement tout ou rien, files à la capacité | 3 |
| `ecoute/main/console_ecoute.c` | `lampe <n>` sur la liste | 3 |
| `firmware/main/{pont_matter.h,pont_matter.cpp}` | endpoints à la demande, numéros stables | 2, 3, 4 |
| `firmware/main/{tache_lampes.h,tache_lampes.c}` | exposition à la première réponse, alertes, masquer et afficher | 2, 3, 4 (8) |
| `firmware/main/console_pont.c` | `lampes`, `lampe <n>`, `mesh lampe <n> masquer|afficher` | 2, 3, 4 (8) |
| `firmware/sdkconfig.defaults` | 18 endpoints dynamiques | 4 |
| `outils/{cles_amaran.py,test_cles_amaran.py}` | N lampes, code, `mesh lampes`, contrôle de la composition, lampes fictives | 5 |
| `README.md`, `docs/superpowers/specs/2026-09-28-pont-amaran-design.md` | documentation | 6 |
| `docs/BANC.md` | résultats des bancs | 7 |

---
### Task 1: Le composant `liste` : liste des lampes et catalogue des modèles (C pur, testé sur le Mac)

**Files:**
- Create: `components/liste/CMakeLists.txt`, `components/liste/include/liste.h`, `components/liste/include/catalogue.h`, `components/liste/liste.c`, `components/liste/catalogue.c`
- Create: `tests/hote/test_liste.c`
- Modify: `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : rien.
- Produces (les tâches suivantes s'en servent telles quelles) :
  - `LISTE_CAPACITE` (16), `LISTE_NOM_MAX` (32), `LISTE_RESERVEE_MIN`/`MAX` (`0x7F00`/`0x7F7F`), `LISTE_CODE_V1` (40065), drapeaux `LISTE_VUE`, `LISTE_MASQUEE` ;
  - `liste_lampe_t { uint16_t adresse; uint8_t mac[6]; char nom[32]; uint32_t code; uint16_t endpoint; uint8_t drapeaux; }`, `liste_t { uint8_t n; liste_lampe_t lampes[16]; }`, `liste_v1_t` (40 octets, l'ancien emplacement) ;
  - `liste_erreur_t liste_valider(const liste_t *, int *fautive)`, `const char *liste_erreur_texte(liste_erreur_t)`, `int liste_chercher_mac(const liste_t *, const uint8_t mac[6])`, `void liste_fusionner(liste_t *nouvelle, const liste_t *actuelle)` ;
  - `bool liste_exposee(const liste_lampe_t *)`, `bool liste_a_exposer_a_l_ecoute(const liste_lampe_t *)`, `void liste_marquer_vue(liste_lampe_t *)`, `void liste_masquer(liste_lampe_t *)`, `void liste_afficher(liste_lampe_t *)` ;
  - `uint32_t liste_taille_nvs(const liste_t *)`, `void liste_vers_nvs(const liste_t *, uint8_t *)`, `bool liste_depuis_nvs(liste_t *, const uint8_t *, uint32_t)`, `void liste_migrer_v1(liste_t *, const liste_v1_t v1[2], const bool lu[2])` ;
  - `CATALOGUE_CODE_COB_60D`, capacités `CATALOGUE_INTENSITE|CCT|COULEUR`, `catalogue_type_t`, `catalogue_modele_t`, `const catalogue_modele_t *catalogue_trouver(uint32_t code)` (jamais NULL : repli), `bool catalogue_connu(uint32_t)`, `const char *catalogue_capacites_texte(uint8_t)`.

Pourquoi : la spec N lampes, sections 4 à 7, en C pur. Tout ce qui se décide sans la carte se teste ici, sur le Mac : la validation, la fusion au chargement, l'exposition, le format NVS, la conversion et le catalogue.

- [ ] **Step 1 : écrire les tests.**

`tests/hote/test_liste.c` (contenu complet) :

````c
// Tests sur le Mac de la liste des lampes et du catalogue des modeles (plan 3a).
// Lancer : sh tests/hote/lancer.sh
#include <string.h>

#include "catalogue.h"
#include "liste.h"
#include "unite.h"

static liste_lampe_t lampe(uint16_t adresse, uint8_t dernier_octet, const char *nom) {
  liste_lampe_t a;
  memset(&a, 0, sizeof(a));
  a.adresse = adresse;
  const uint8_t mac[6] = {0x70, 0x3E, 0x97, 0x00, 0x00, dernier_octet};
  memcpy(a.mac, mac, 6);
  strncpy(a.nom, nom, LISTE_NOM_MAX - 1);
  a.code = CATALOGUE_CODE_COB_60D;
  return a;
}

static liste_t deux_lampes(void) {
  liste_t l;
  memset(&l, 0, sizeof(l));
  l.n = 2;
  l.lampes[0] = lampe(0x0002, 0x01, "Lampe A");
  l.lampes[1] = lampe(0x0004, 0x02, "Lampe B");
  return l;
}

static void test_valider(void) {
  int fautive = 99;
  liste_t l = deux_lampes();
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK && fautive == -1, "deux lampes valides");

  l.n = LISTE_CAPACITE + 1;
  VERIFIE(liste_valider(&l, &fautive) == LISTE_TROP_LONGUE && fautive == -1, "au-dela de la capacite");

  const uint16_t mauvaises[] = {0x0000, 0x8000, 0xC000, LISTE_RESERVEE_MIN, LISTE_RESERVEE_MAX};
  for (unsigned k = 0; k < sizeof(mauvaises) / sizeof(mauvaises[0]); k++) {
    l = deux_lampes();
    l.lampes[1].adresse = mauvaises[k];
    VERIFIE(liste_valider(&l, &fautive) == LISTE_ADRESSE_INVALIDE && fautive == 1, "adresse 0x%04x refusee",
            (unsigned)mauvaises[k]);
  }
  l = deux_lampes();
  l.lampes[1].adresse = 0x7F80;  // juste apres nos adresses : une lampe peut l'avoir
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK, "0x7F80 acceptee");

  l = deux_lampes();
  l.lampes[1].adresse = 0x0002;
  VERIFIE(liste_valider(&l, &fautive) == LISTE_ADRESSE_EN_DOUBLE && fautive == 1, "adresse en double");

  l = deux_lampes();
  memset(l.lampes[0].mac, 0, 6);
  VERIFIE(liste_valider(&l, &fautive) == LISTE_MAC_NULLE && fautive == 0, "MAC nulle");

  l = deux_lampes();
  memcpy(l.lampes[1].mac, l.lampes[0].mac, 6);
  VERIFIE(liste_valider(&l, &fautive) == LISTE_MAC_EN_DOUBLE && fautive == 1, "MAC en double");

  l = deux_lampes();
  l.lampes[0].nom[0] = '\0';
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE && fautive == 0, "nom vide");

  l = deux_lampes();
  strcpy(l.lampes[0].nom, "a\r\nredemarre");
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE, "nom avec un retour a la ligne");

  l = deux_lampes();
  memset(l.lampes[0].nom, 'x', LISTE_NOM_MAX);  // aucun NUL
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE, "nom sans fin");

  l = deux_lampes();
  l.n = 0;
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK, "liste vide valide");
  VERIFIE(strcmp(liste_erreur_texte(LISTE_MAC_NULLE), "MAC nulle") == 0, "texte d'une erreur");
}

static void test_chercher_mac(void) {
  const liste_t l = deux_lampes();
  VERIFIE(liste_chercher_mac(&l, l.lampes[1].mac) == 1, "MAC trouvee");
  const uint8_t inconnue[6] = {1, 2, 3, 4, 5, 6};
  VERIFIE(liste_chercher_mac(&l, inconnue) == -1, "MAC inconnue");
}

// Une MAC connue garde son numero et ses drapeaux, quelle que soit sa place ; une
// nouvelle part de zero ; une absente disparait.
static void test_fusionner(void) {
  liste_t actuelle = deux_lampes();
  actuelle.lampes[0].endpoint = 2;
  actuelle.lampes[0].drapeaux = LISTE_VUE;
  actuelle.lampes[1].endpoint = 3;
  actuelle.lampes[1].drapeaux = LISTE_VUE | LISTE_MASQUEE;

  liste_t nouvelle;
  memset(&nouvelle, 0, sizeof(nouvelle));
  nouvelle.n = 2;
  nouvelle.lampes[0] = lampe(0x0006, 0x03, "Lampe C");  // nouvelle
  nouvelle.lampes[1] = lampe(0x0008, 0x02, "Lampe B renommee");  // B, autre adresse, autre place
  nouvelle.lampes[1].endpoint = 77;  // ce que dit le chargement ne compte pas
  nouvelle.lampes[1].drapeaux = 0;
  liste_fusionner(&nouvelle, &actuelle);

  VERIFIE(nouvelle.lampes[0].endpoint == 0 && nouvelle.lampes[0].drapeaux == 0, "C : sans numero, jamais vue");
  VERIFIE(nouvelle.lampes[1].endpoint == 3 && nouvelle.lampes[1].drapeaux == (LISTE_VUE | LISTE_MASQUEE),
          "B garde EP3 et son masquage");
  VERIFIE(nouvelle.lampes[1].adresse == 0x0008 && !strcmp(nouvelle.lampes[1].nom, "Lampe B renommee"),
          "B prend sa nouvelle adresse et son nouveau nom");
  VERIFIE(liste_chercher_mac(&nouvelle, actuelle.lampes[0].mac) == -1, "A a disparu");
}

static void test_exposition(void) {
  liste_lampe_t a = lampe(0x0002, 0x01, "Lampe A");
  VERIFIE(!liste_exposee(&a) && liste_a_exposer_a_l_ecoute(&a), "jamais vue : pas exposee, a exposer a l'ecoute");
  liste_marquer_vue(&a);
  VERIFIE(liste_exposee(&a) && !liste_a_exposer_a_l_ecoute(&a), "vue : exposee");
  liste_masquer(&a);
  VERIFIE(!liste_exposee(&a) && !liste_a_exposer_a_l_ecoute(&a), "masquee : ni exposee ni a exposer");
  liste_afficher(&a);
  VERIFIE(liste_exposee(&a) && a.drapeaux == LISTE_VUE, "afficher : de nouveau exposee");

  liste_lampe_t fictive = lampe(0x0010, 0x10, "Fictive");
  liste_masquer(&fictive);
  liste_afficher(&fictive);
  VERIFIE(liste_exposee(&fictive), "afficher expose meme une lampe jamais entendue");
}

static void test_nvs_aller_retour(void) {
  liste_t l = deux_lampes();
  l.lampes[1].endpoint = 3;
  l.lampes[1].drapeaux = LISTE_VUE;
  uint8_t tampon[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_t)];
  const uint32_t n = liste_taille_nvs(&l);
  VERIFIE(n == sizeof(liste_entete_t) + 2 * sizeof(liste_lampe_t), "taille : en-tete et deux lampes");
  liste_vers_nvs(&l, tampon);
  liste_t relue;
  VERIFIE(liste_depuis_nvs(&relue, tampon, n) && relue.n == 2 && !memcmp(&relue.lampes[1], &l.lampes[1],
                                                                           sizeof(liste_lampe_t)),
          "aller-retour exact");

  VERIFIE(!liste_depuis_nvs(&relue, tampon, n - 1) && relue.n == 0, "tronquee : refusee, liste vide");
  VERIFIE(!liste_depuis_nvs(&relue, tampon, 3), "plus courte que l'en-tete");
  uint8_t autre[sizeof(tampon)];
  memcpy(autre, tampon, n);
  autre[0] = 3;  // version future
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "autre version refusee");
  memcpy(autre, tampon, n);
  autre[2] = (uint8_t)(sizeof(liste_lampe_t) + 4);  // lampe d'une autre taille
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "autre taille de lampe refusee");
  memcpy(autre, tampon, n);
  autre[1] = LISTE_CAPACITE + 1;
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "plus longue que la capacite refusee");

  l.n = 0;
  liste_vers_nvs(&l, tampon);
  VERIFIE(liste_depuis_nvs(&relue, tampon, liste_taille_nvs(&l)) && relue.n == 0, "liste vide relue");
}

static void test_migration_v1(void) {
  liste_v1_t v1[2];
  memset(v1, 0, sizeof(v1));
  v1[0].adresse = 0x0002;
  v1[0].mac[5] = 0x01;
  strcpy(v1[0].nom, "amaran COB 60d #1");
  v1[1].adresse = 0x0004;
  v1[1].mac[5] = 0x02;
  memset(v1[1].nom, 'y', LISTE_NOM_MAX);  // nom sans NUL : tronque
  const bool lus[2] = {true, true};
  liste_t l;
  liste_migrer_v1(&l, v1, lus);
  VERIFIE(l.n == 2, "deux lampes");
  VERIFIE(l.lampes[0].endpoint == 2 && l.lampes[1].endpoint == 3, "EP2 et EP3 gardes");
  VERIFIE(l.lampes[0].drapeaux == LISTE_VUE && l.lampes[1].drapeaux == LISTE_VUE, "vues : leurs tuiles restent");
  VERIFIE(l.lampes[0].code == LISTE_CODE_V1 && l.lampes[1].code == LISTE_CODE_V1, "modele : la 60d");
  VERIFIE(!strcmp(l.lampes[0].nom, "amaran COB 60d #1") && l.lampes[0].adresse == 0x0002 &&
              l.lampes[0].mac[5] == 0x01,
          "nom, adresse et MAC repris");
  VERIFIE(strlen(l.lampes[1].nom) == LISTE_NOM_MAX - 1, "nom sans fin : tronque");

  memset(v1, 0, sizeof(v1));
  v1[1].adresse = 0x0004;
  v1[1].mac[5] = 0x02;
  strcpy(v1[1].nom, "B");
  liste_migrer_v1(&l, v1, lus);
  VERIFIE(l.n == 1 && l.lampes[0].endpoint == 3, "emplacement 1 libre : la lampe 2 garde EP3");

  const bool un_seul[2] = {true, false};
  v1[0] = v1[1];
  liste_migrer_v1(&l, v1, un_seul);
  VERIFIE(l.n == 1 && l.lampes[0].endpoint == 2, "emplacement non lu : ignore");
}

static void test_catalogue(void) {
  const catalogue_modele_t *m = catalogue_trouver(CATALOGUE_CODE_COB_60D);
  VERIFIE(m->code == 40065u && !strcmp(m->nom, "amaran COB 60d") && m->capacites == CATALOGUE_INTENSITE &&
              m->type == CATALOGUE_LAMPE_VARIABLE,
          "la 60d : intensite seule, lampe a intensite variable");
  VERIFIE(catalogue_connu(40065u), "60d connue");
  const catalogue_modele_t *r = catalogue_trouver(99999u);
  VERIFIE(r != NULL && r->capacites == CATALOGUE_INTENSITE && r->type == CATALOGUE_LAMPE_VARIABLE &&
              !strcmp(r->nom, "modele non catalogue"),
          "code inconnu : repli en intensite seule");
  VERIFIE(!catalogue_connu(99999u) && !catalogue_connu(0), "inconnu, et 0");
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE), "intensite"), "texte : intensite");
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE | CATALOGUE_CCT), "intensite+cct"),
          "texte : intensite+cct");
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE | CATALOGUE_COULEUR), "intensite+couleur"),
          "texte : intensite+couleur");
}

int main(void) {
  test_valider();
  test_chercher_mac();
  test_fusionner();
  test_exposition();
  test_nvs_aller_retour();
  test_migration_v1();
  test_catalogue();
  return bilan("liste");
}
````

- [ ] **Step 2 : les inscrire dans `tests/hote/lancer.sh`.**

`tests/hote/lancer.sh`, bloc 1 sur 2. Remplacer :

````sh
mkdir -p "$SORTIE"
CC="${CC:-clang}"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Icomponents/mesh -Icomponents/lampes/include -Itests/hote"

compiler_et_lancer() {
````

par :

````sh
mkdir -p "$SORTIE"
CC="${CC:-clang}"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Icomponents/mesh -Icomponents/lampes/include -Icomponents/liste/include -Itests/hote"

compiler_et_lancer() {
````

`tests/hote/lancer.sh`, bloc 2 sur 2. Remplacer :

````sh
compiler_et_lancer test_lampes components/telink/telink.c components/lampes/lampes.c tests/hote/test_lampes.c
compiler_et_lancer test_diagnostic components/mesh/diagnostic.c tests/hote/test_diagnostic.c

# Socle repris du Halo : C++17, comme ses tests d'origine.
````

par :

````sh
compiler_et_lancer test_lampes components/telink/telink.c components/lampes/lampes.c tests/hote/test_lampes.c
compiler_et_lancer test_diagnostic components/mesh/diagnostic.c tests/hote/test_diagnostic.c
compiler_et_lancer test_liste components/liste/liste.c components/liste/catalogue.c tests/hote/test_liste.c

# Socle repris du Halo : C++17, comme ses tests d'origine.
````

- [ ] **Step 3 : les lancer, pour les voir échouer.**

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation de `test_liste` (`'catalogue.h' file not found`).

- [ ] **Step 4 : le composant.**

`components/liste/CMakeLists.txt` (contenu complet) :

````cmake
idf_component_register(SRCS "liste.c" "catalogue.c"
                       INCLUDE_DIRS "include")
````

`components/liste/include/liste.h` (contenu complet) :

````c
// Liste des lampes du pont (spec N lampes 4 a 7) : pour chaque lampe, son adresse
// Mesh, sa MAC, son nom, son modele, son numero d'endpoint Matter et son
// exposition dans Maison. C pur, sans ESP-IDF : tout se teste sur le Mac
// (tests/hote/test_liste.c).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LISTE_CAPACITE 16           // lampes au plus ; a relever si le banc de capacite le permet
#define LISTE_NOM_MAX 32            // nom, NUL compris (NodeLabel dans Matter)
#define LISTE_VERSION 2             // format en NVS (1 : les deux emplacements du plan 2)
#define LISTE_RESERVEE_MIN 0x7F00   // nos adresses (spec du pont 5.4) : jamais celle d'une lampe
#define LISTE_RESERVEE_MAX 0x7F7F
#define LISTE_CODE_V1 40065u        // avant le plan 3a, seules des COB 60d ont pu etre chargees

enum {
  LISTE_VUE = 1u << 0,      // la lampe a repondu au moins une fois : exposee dans Maison
  LISTE_MASQUEE = 1u << 1,  // retiree de Maison par un geste explicite
};

typedef struct {
  uint16_t adresse;         // unicast de la lampe
  uint8_t mac[6];           // identite stable (UniqueID dans Matter)
  char nom[LISTE_NOM_MAX];
  uint32_t code;            // code produit Sidus (40065 : COB 60d) ; 0 : inconnu
  uint16_t endpoint;        // numero d'endpoint Matter ; 0 : pas encore attribue
  uint8_t drapeaux;         // LISTE_VUE, LISTE_MASQUEE
} liste_lampe_t;

typedef struct {
  uint8_t n;
  liste_lampe_t lampes[LISTE_CAPACITE];
} liste_t;

typedef enum {
  LISTE_OK,
  LISTE_TROP_LONGUE,
  LISTE_ADRESSE_INVALIDE,
  LISTE_ADRESSE_EN_DOUBLE,
  LISTE_MAC_NULLE,
  LISTE_MAC_EN_DOUBLE,
  LISTE_NOM_INVALIDE,
} liste_erreur_t;

// Premiere faute de la liste ; *fautive : index de la lampe en cause (-1 : la liste).
liste_erreur_t liste_valider(const liste_t *l, int *fautive);
const char *liste_erreur_texte(liste_erreur_t e);
// Index de la lampe de cette MAC, ou -1.
int liste_chercher_mac(const liste_t *l, const uint8_t mac[6]);
// Chargement d'une nouvelle liste : une MAC deja connue garde son endpoint et ses
// drapeaux ; une MAC nouvelle part sans endpoint, ni vue ni masquee ; une MAC
// absente de la nouvelle liste disparait, avec son numero (jamais reattribue).
void liste_fusionner(liste_t *nouvelle, const liste_t *actuelle);

// Exposition dans Maison (spec N lampes 7).
bool liste_exposee(const liste_lampe_t *l);              // vue et non masquee
bool liste_a_exposer_a_l_ecoute(const liste_lampe_t *l);  // ni vue ni masquee
void liste_marquer_vue(liste_lampe_t *l);
void liste_masquer(liste_lampe_t *l);
void liste_afficher(liste_lampe_t *l);                   // exposee, meme jamais entendue

// Format en NVS : un en-tete, puis n lampes. La taille d'une lampe y est notee : une
// capacite relevee plus tard relit toujours une liste ecrite avant.
typedef struct {
  uint8_t version;          // LISTE_VERSION
  uint8_t n;
  uint8_t taille_lampe;     // sizeof(liste_lampe_t)
  uint8_t reserve;
} liste_entete_t;

// Octets a ecrire pour la liste l.
uint32_t liste_taille_nvs(const liste_t *l);
// Ecrit la liste dans tampon (au moins liste_taille_nvs(l) octets).
void liste_vers_nvs(const liste_t *l, uint8_t *tampon);
// Relit une liste ecrite par liste_vers_nvs. Faux (et liste vide) si le format ne
// convient pas : version, taille d'une lampe, longueur.
bool liste_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille);

// Ancien format (plan 2) : deux emplacements, cles NVS "lampe0" et "lampe1".
typedef struct {
  uint16_t adresse;         // 0 : emplacement libre
  uint8_t mac[6];
  char nom[LISTE_NOM_MAX];
} liste_v1_t;

// Les lampes des emplacements lus et non libres, dans l'ordre. L'emplacement i
// avait toujours l'endpoint 2 + i, et sa tuile existe : la lampe garde ce numero et
// reste exposee. Leur modele : LISTE_CODE_V1.
void liste_migrer_v1(liste_t *l, const liste_v1_t v1[2], const bool lu[2]);

#ifdef __cplusplus
}
#endif
````

`components/liste/include/catalogue.h` (contenu complet) :

````c
// Catalogue des modeles de lampes (spec N lampes 6) : pour chaque code produit
// Sidus, le nom du modele, ses capacites et le type d'appareil Matter qui en
// decoule. Le firmware en est la source unique. C pur, teste sur le Mac.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CATALOGUE_CODE_COB_60D 40065u

enum {
  CATALOGUE_INTENSITE = 1u << 0,
  CATALOGUE_CCT = 1u << 1,      // temperature de couleur (Light CTL)
  CATALOGUE_COULEUR = 1u << 2,  // couleur (Light HSL)
};

typedef enum {
  CATALOGUE_LAMPE_VARIABLE,     // Dimmable Light : marche et intensite
  CATALOGUE_LAMPE_TEMPERATURE,  // Color Temperature Light (pas encore realise)
  CATALOGUE_LAMPE_COULEUR,      // Extended Color Light (pas encore realise)
} catalogue_type_t;

typedef struct {
  uint32_t code;                // code produit Sidus ; 0 : le repli
  const char *nom;
  uint8_t capacites;            // CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR
  uint16_t cct_min_k, cct_max_k;  // 0 sans CCT
  catalogue_type_t type;
} catalogue_modele_t;

// Le modele de ce code ; un code inconnu donne le repli (intensite seule, lampe a
// intensite variable). Jamais NULL.
const catalogue_modele_t *catalogue_trouver(uint32_t code);
bool catalogue_connu(uint32_t code);
// "intensite", "intensite+cct", "intensite+couleur"... : les capacites, en mots
// (console, et reponse de `mesh lampe` que lit outils/cles_amaran.py).
const char *catalogue_capacites_texte(uint8_t capacites);

#ifdef __cplusplus
}
#endif
````

`components/liste/liste.c` (contenu complet) :

````c
// Liste des lampes du pont (voir liste.h).
#include "liste.h"

#include <string.h>

static const uint8_t MAC_NULLE[6] = {0};

static bool adresse_valide(uint16_t a) {
  return a >= 0x0001 && a <= 0x7FFF && (a < LISTE_RESERVEE_MIN || a > LISTE_RESERVEE_MAX);
}

static bool nom_valide(const char nom[LISTE_NOM_MAX]) {
  if (nom[0] == '\0') return false;
  for (int i = 0; i < LISTE_NOM_MAX; i++) {
    if (nom[i] == '\0') return true;
    if ((unsigned char)nom[i] < 0x20) return false;
  }
  return false;  // pas de NUL : nom trop long
}

liste_erreur_t liste_valider(const liste_t *l, int *fautive) {
  *fautive = -1;
  if (l->n > LISTE_CAPACITE) return LISTE_TROP_LONGUE;
  for (int i = 0; i < l->n; i++) {
    const liste_lampe_t *a = &l->lampes[i];
    *fautive = i;
    if (!adresse_valide(a->adresse)) return LISTE_ADRESSE_INVALIDE;
    if (!memcmp(a->mac, MAC_NULLE, 6)) return LISTE_MAC_NULLE;
    if (!nom_valide(a->nom)) return LISTE_NOM_INVALIDE;
    for (int j = 0; j < i; j++) {
      if (l->lampes[j].adresse == a->adresse) return LISTE_ADRESSE_EN_DOUBLE;
      if (!memcmp(l->lampes[j].mac, a->mac, 6)) return LISTE_MAC_EN_DOUBLE;
    }
  }
  *fautive = -1;
  return LISTE_OK;
}

const char *liste_erreur_texte(liste_erreur_t e) {
  switch (e) {
    case LISTE_OK:
      return "ok";
    case LISTE_TROP_LONGUE:
      return "trop de lampes";
    case LISTE_ADRESSE_INVALIDE:
      return "adresse hors de l'unicast, ou dans nos adresses (0x7F00-0x7F7F)";
    case LISTE_ADRESSE_EN_DOUBLE:
      return "adresse deja prise par une autre lampe";
    case LISTE_MAC_NULLE:
      return "MAC nulle";
    case LISTE_MAC_EN_DOUBLE:
      return "MAC deja prise par une autre lampe";
    case LISTE_NOM_INVALIDE:
      return "nom vide, trop long, ou avec un caractere de controle";
  }
  return "?";
}

int liste_chercher_mac(const liste_t *l, const uint8_t mac[6]) {
  for (int i = 0; i < l->n && i < LISTE_CAPACITE; i++) {
    if (!memcmp(l->lampes[i].mac, mac, 6)) return i;
  }
  return -1;
}

void liste_fusionner(liste_t *nouvelle, const liste_t *actuelle) {
  for (int i = 0; i < nouvelle->n && i < LISTE_CAPACITE; i++) {
    liste_lampe_t *a = &nouvelle->lampes[i];
    const int j = liste_chercher_mac(actuelle, a->mac);
    a->endpoint = j >= 0 ? actuelle->lampes[j].endpoint : 0;
    a->drapeaux = j >= 0 ? actuelle->lampes[j].drapeaux : 0;
  }
}

bool liste_exposee(const liste_lampe_t *l) { return (l->drapeaux & LISTE_VUE) && !(l->drapeaux & LISTE_MASQUEE); }

bool liste_a_exposer_a_l_ecoute(const liste_lampe_t *l) { return !(l->drapeaux & (LISTE_VUE | LISTE_MASQUEE)); }

void liste_marquer_vue(liste_lampe_t *l) { l->drapeaux |= LISTE_VUE; }

void liste_masquer(liste_lampe_t *l) { l->drapeaux |= LISTE_MASQUEE; }

void liste_afficher(liste_lampe_t *l) { l->drapeaux = (uint8_t)((l->drapeaux | LISTE_VUE) & ~LISTE_MASQUEE); }

uint32_t liste_taille_nvs(const liste_t *l) {
  return (uint32_t)(sizeof(liste_entete_t) + (size_t)l->n * sizeof(liste_lampe_t));
}

void liste_vers_nvs(const liste_t *l, uint8_t *tampon) {
  const liste_entete_t e = {LISTE_VERSION, l->n, (uint8_t)sizeof(liste_lampe_t), 0};
  memcpy(tampon, &e, sizeof(e));
  memcpy(tampon + sizeof(e), l->lampes, (size_t)l->n * sizeof(liste_lampe_t));
}

bool liste_depuis_nvs(liste_t *l, const uint8_t *tampon, uint32_t taille) {
  memset(l, 0, sizeof(*l));
  liste_entete_t e;
  if (taille < sizeof(e)) return false;
  memcpy(&e, tampon, sizeof(e));
  if (e.version != LISTE_VERSION || e.taille_lampe != sizeof(liste_lampe_t) || e.n > LISTE_CAPACITE ||
      taille != sizeof(e) + (size_t)e.n * sizeof(liste_lampe_t)) {
    return false;
  }
  l->n = e.n;
  memcpy(l->lampes, tampon + sizeof(e), (size_t)e.n * sizeof(liste_lampe_t));
  for (int i = 0; i < l->n; i++) l->lampes[i].nom[LISTE_NOM_MAX - 1] = '\0';
  return true;
}

void liste_migrer_v1(liste_t *l, const liste_v1_t v1[2], const bool lu[2]) {
  memset(l, 0, sizeof(*l));
  for (int i = 0; i < 2; i++) {
    if (!lu[i] || v1[i].adresse == 0) continue;
    liste_lampe_t *a = &l->lampes[l->n++];
    a->adresse = v1[i].adresse;
    memcpy(a->mac, v1[i].mac, 6);
    memcpy(a->nom, v1[i].nom, LISTE_NOM_MAX);
    a->nom[LISTE_NOM_MAX - 1] = '\0';
    a->code = LISTE_CODE_V1;
    a->endpoint = (uint16_t)(2 + i);
    a->drapeaux = LISTE_VUE;
  }
}
````

`components/liste/catalogue.c` (contenu complet) :

````c
// Catalogue des modeles de lampes (voir catalogue.h). Ajouter un modele : une
// entree ici, puis le banc avec la vraie lampe.
#include "catalogue.h"

static const catalogue_modele_t MODELES[] = {
    {CATALOGUE_CODE_COB_60D, "amaran COB 60d", CATALOGUE_INTENSITE, 0, 0, CATALOGUE_LAMPE_VARIABLE},
};

// Trames 0x8C (marche) et 0x8F (intensite) : communes au protocole Sidus.
static const catalogue_modele_t REPLI = {0, "modele non catalogue", CATALOGUE_INTENSITE, 0, 0,
                                         CATALOGUE_LAMPE_VARIABLE};

const catalogue_modele_t *catalogue_trouver(uint32_t code) {
  for (unsigned i = 0; i < sizeof(MODELES) / sizeof(MODELES[0]); i++) {
    if (MODELES[i].code == code) return &MODELES[i];
  }
  return &REPLI;
}

bool catalogue_connu(uint32_t code) { return code != 0 && catalogue_trouver(code) != &REPLI; }

const char *catalogue_capacites_texte(uint8_t capacites) {
  switch (capacites & (CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR)) {
    case CATALOGUE_INTENSITE:
      return "intensite";
    case CATALOGUE_INTENSITE | CATALOGUE_CCT:
      return "intensite+cct";
    case CATALOGUE_INTENSITE | CATALOGUE_COULEUR:
      return "intensite+couleur";
    case CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR:
      return "intensite+cct+couleur";
    default:
      return "aucune";
  }
}
````

- [ ] **Step 5 : les tests passent.**

Run: `sh tests/hote/lancer.sh`
Expected : `liste : 50 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 6 : commit.**

```bash
git add components/liste tests/hote/test_liste.c tests/hote/lancer.sh
git commit -m "$(printf "Ajouter la liste des lampes et le catalogue des modeles, testes sur le Mac\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---
### Task 2: Le cœur `lampes` à N lampes : lampe entendue, alerte de relectures, publication forcée

**Files:**
- Modify: `components/lampes/include/lampes.h`, `components/lampes/lampes.c`, `tests/hote/test_lampes.c`
- Modify: `firmware/main/pont_matter.h`, `firmware/main/pont_matter.cpp`, `firmware/main/console_pont.c`, `firmware/main/tache_lampes.c` (renommage, et la sortie `alerter` à `NULL`)

**Interfaces:**
- Consumes : rien de la Task 1.
- Produces :
  - `LAMPES_CAPACITE` (16) remplace `LAMPES_MAX` (2) dans `lampes.h` ;
  - `lampe_t` gagne `bool entendue` (une trame de la lampe depuis le démarrage, lue ou non), `bool releve_en_attente`, `uint16_t fen_releves[10]`, `uint16_t fen_repondues[10]`, `bool alerte` ; `lampes_t` gagne `fen_tranche`, `fen_pleines`, `fen_echeance_ms` ;
  - `lampes_sorties_t` gagne, avant `ctx`, `void (*alerter)(void *ctx, int lampe, bool manque, uint8_t pour_cent)` (peut être `NULL`) ;
  - `void lampes_forcer_publication(lampes_t *, int lampe)` et `int lampes_part_repondue(const lampes_t *, int lampe)` (-1 si rien de compté) ;
  - côté pont, pour cette tâche et la suivante seulement : `#define PONT_EMPLACEMENTS 2` dans `pont_matter.h` (EP2 et EP3 fixes, comme au plan 2). La Task 4 le supprime.

Pourquoi : la spec N lampes, section 8 (alerte sous 95 % sur 10 minutes, une lampe muette n'est pas concernée), et ce dont la Task 4 a besoin : savoir qu'une lampe a répondu (`entendue`), et republier une lampe dont l'endpoint vient d'être créé.

- [ ] **Step 1 : les tests.** Dans `tests/hote/test_lampes.c` :

`tests/hote/test_lampes.c`, bloc 1 sur 7. Remplacer :

````c
} signal_t;

static envoi_t g_envois[512];
static int g_nb_envois;
````

par :

````c
} signal_t;

typedef struct {
  int lampe;
  bool manque;
  uint8_t pour_cent;
} alerte_t;

static envoi_t g_envois[512];
static int g_nb_envois;
````

`tests/hote/test_lampes.c`, bloc 2 sur 7. Remplacer :

````c
static signal_t g_sigs[64];
static int g_nb_sigs;
static bool g_refuser;

````

par :

````c
static signal_t g_sigs[64];
static int g_nb_sigs;
static alerte_t g_alertes[16];
static int g_nb_alertes;
static bool g_refuser;

````

`tests/hote/test_lampes.c`, bloc 3 sur 7. Remplacer :

````c
}

static void oublier_sorties(void) {
  g_nb_envois = g_nb_pubs = g_nb_sigs = 0;
  g_refuser = false;
}
````

par :

````c
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
````

`tests/hote/test_lampes.c`, bloc 4 sur 7. Remplacer :

````c

static void demarrer(uint32_t t0, bool pret) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, NULL};
  T = t0;
  lampes_init(&L, ADR, 2, &s, T);
````

par :

````c

static void demarrer(uint32_t t0, bool pret) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, f_alerter, NULL};
  T = t0;
  lampes_init(&L, ADR, 2, &s, T);
````

`tests/hote/test_lampes.c`, bloc 5 sur 7. Remplacer :

````c

static void test_demarrage_relit_aussitot(void) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, NULL};
  oublier_sorties();
  T = 1000;
````

par :

````c

static void test_demarrage_relit_aussitot(void) {
  const lampes_sorties_t s = {f_envoyer, f_publier, f_signaler, f_alerter, NULL};
  oublier_sorties();
  T = 1000;
````

`tests/hote/test_lampes.c`, bloc 6 sur 7. Remplacer :

````c
}

int main(void) {
  test_conversion();
````

par :

````c
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
  VERIFIE(g_nb_pubs == 1, "lampe hors de la liste ignoree");
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
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].lampe == 1 && g_alertes[0].manque && g_alertes[0].pour_cent == 50,
          "lampe 2 : relectures manquees, 50 %% (%d alertes)", g_nb_alertes);
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
  VERIFIE(g_nb_alertes == 1 && g_alertes[0].manque && g_alertes[0].pour_cent == 90, "90 %% : alerte");
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
````

`tests/hote/test_lampes.c`, bloc 7 sur 7. Remplacer :

````c
  test_on_sur_allumee_n_emet_pas();
  test_on_sur_lampe_jamais_lue();
  return bilan("lampes");
}
````

par :

````c
  test_on_sur_allumee_n_emet_pas();
  test_on_sur_lampe_jamais_lue();
  test_capacite();
  test_entendue();
  test_forcer_publication();
  test_alerte_relectures_manquees();
  test_alerte_au_seuil();
  test_alerte_pas_pour_une_muette();
  test_alerter_peut_manquer();
  return bilan("lampes");
}
````

- [ ] **Step 2 : les lancer, pour les voir échouer.**

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation de `test_lampes` (`LAMPES_CAPACITE` inconnu, pas de champ `entendue`, initialiseur de `lampes_sorties_t` trop long...).

- [ ] **Step 3 : `lampes.h`.**

`components/lampes/include/lampes.h`, bloc 1 sur 8. Remplacer :

````c
#endif

#define LAMPES_MAX 2
#define LAMPES_GROUPE 0xC000               // groupe « All » : les deux lampes repondent (R5)
#define LAMPES_RELEVE_DEFAUT_MS 2000u      // relecture periodique (spec 5.7 ; R4 : aucun etat spontane ; 2 s depuis le 03/10)
#define LAMPES_RELEVE_MIN_MS 1000u
````

par :

````c
#endif

#define LAMPES_CAPACITE 16                // lampes au plus (spec N lampes 4 : LISTE_CAPACITE)
#define LAMPES_GROUPE 0xC000               // groupe « All » : toutes les lampes repondent (R5)
#define LAMPES_RELEVE_DEFAUT_MS 2000u      // relecture periodique (spec 5.7 ; R4 : aucun etat spontane ; 2 s depuis le 03/10)
#define LAMPES_RELEVE_MIN_MS 1000u
````

`components/lampes/include/lampes.h`, bloc 2 sur 8. Remplacer :

````c
#define LAMPES_INTENSITE_RALLUMAGE 400u    // rallumer une lampe noire jamais vue allumee : 40 %, comme la lampe
                                           // d'elle-meme apres une coupure (banc R4)

typedef struct {
````

par :

````c
#define LAMPES_INTENSITE_RALLUMAGE 400u    // rallumer une lampe noire jamais vue allumee : 40 %, comme la lampe
                                           // d'elle-meme apres une coupure (banc R4)
// Alerte de relectures manquees (spec N lampes 8) : part des relectures repondues
// sur une fenetre glissante de 10 tranches d'une minute, sous le seuil de la regle 5.8.
#define LAMPES_ALERTE_TRANCHE_MS 60000u
#define LAMPES_ALERTE_TRANCHES 10u
#define LAMPES_ALERTE_SEUIL_PC 95u

typedef struct {
````

`components/lampes/include/lampes.h`, bloc 3 sur 8. Remplacer :

````c
  void (*publier)(void *ctx, int lampe, const lampe_etat_t *etat, bool joignable);
  void (*signaler)(void *ctx, int lampe, lampes_signal_t signal);
  void *ctx;
} lampes_sorties_t;
````

par :

````c
  void (*publier)(void *ctx, int lampe, const lampe_etat_t *etat, bool joignable);
  void (*signaler)(void *ctx, int lampe, lampes_signal_t signal);
  // Relectures manquees : manque vrai quand la part des relectures repondues sur 10 min
  // passe sous LAMPES_ALERTE_SEUIL_PC, faux quand elle y revient ; pour_cent : cette
  // part, arrondie. Une seule fois par passage. Peut etre NULL.
  void (*alerter)(void *ctx, int lampe, bool manque, uint8_t pour_cent);
  void *ctx;
} lampes_sorties_t;
````

`components/lampes/include/lampes.h`, bloc 4 sur 8. Remplacer :

````c
  uint16_t adresse;
  // Etat lu
  bool connu;                    // un etat a ete lu depuis le demarrage
  lampe_etat_t lu;
````

par :

````c
  uint16_t adresse;
  // Etat lu
  bool entendue;                 // une trame de la lampe depuis le demarrage (lue ou non)
  bool connu;                    // un etat a ete lu depuis le demarrage
  lampe_etat_t lu;
````

`components/lampes/include/lampes.h`, bloc 5 sur 8. Remplacer :

````c
  bool repondu;                  // une trame depuis la derniere relecture
  uint32_t releves_repondues;    // relectures suivies d'une reponse (banc C, regle 5.8)
  // Consigne : seuls les champs marques comptent
  bool veut_marche, veut_intensite;
````

par :

````c
  bool repondu;                  // une trame depuis la derniere relecture
  uint32_t releves_repondues;    // relectures suivies d'une reponse (banc C, regle 5.8)
  bool releve_en_attente;        // une relecture est partie, son issue n'est pas encore comptee
  uint16_t fen_releves[LAMPES_ALERTE_TRANCHES];   // relectures par tranche d'une minute
  uint16_t fen_repondues[LAMPES_ALERTE_TRANCHES];
  bool alerte;                   // relectures manquees signalees
  // Consigne : seuls les champs marques comptent
  bool veut_marche, veut_intensite;
````

`components/lampes/include/lampes.h`, bloc 6 sur 8. Remplacer :

````c

typedef struct {
  lampe_t lampes[LAMPES_MAX];
  int n;
  bool mesh_pret;
````

par :

````c

typedef struct {
  lampe_t lampes[LAMPES_CAPACITE];
  int n;
  bool mesh_pret;
````

`components/lampes/include/lampes.h`, bloc 7 sur 8. Remplacer :

````c
  uint32_t delai_total_ms, delai_max_ms;  // ordre -> confirmation (banc C, regle 5.8 : 1 s)
  uint32_t lents;                         // confirmations en plus d'une seconde
} lampes_t;

````

par :

````c
  uint32_t delai_total_ms, delai_max_ms;  // ordre -> confirmation (banc C, regle 5.8 : 1 s)
  uint32_t lents;                         // confirmations en plus d'une seconde
  uint8_t fen_tranche;                    // tranche courante (0..LAMPES_ALERTE_TRANCHES-1)
  uint8_t fen_pleines;                    // tranches achevees, jusqu'a LAMPES_ALERTE_TRANCHES
  uint32_t fen_echeance_ms;               // fin de la tranche courante
} lampes_t;

````

`components/lampes/include/lampes.h`, bloc 8 sur 8. Remplacer :

````c
// A appeler souvent (toutes les 50 ms) : echeances des ordres et relecture.
void lampes_tic(lampes_t *l, uint32_t maintenant_ms);

// Conversions lineaires (spec 6.2), arrondi au plus proche, demi vers le haut.
````

par :

````c
// A appeler souvent (toutes les 50 ms) : echeances des ordres et relecture.
void lampes_tic(lampes_t *l, uint32_t maintenant_ms);
// Republie ce que Matter doit montrer de la lampe, meme inchange : son endpoint vient
// d'etre cree (premiere reponse, ou `afficher`).
void lampes_forcer_publication(lampes_t *l, int lampe);
// Part des relectures repondues sur la fenetre de 10 min, en pour cent arrondi ;
// -1 si aucune relecture n'y est encore comptee.
int lampes_part_repondue(const lampes_t *l, int lampe);

// Conversions lineaires (spec 6.2), arrondi au plus proche, demi vers le haut.
````

- [ ] **Step 4 : `lampes.c`.**

`components/lampes/lampes.c`, bloc 1 sur 5. Remplacer :

````c
                 uint32_t maintenant_ms) {
  memset(l, 0, sizeof(*l));
  l->n = n < 0 ? 0 : (n > LAMPES_MAX ? LAMPES_MAX : n);
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].adresse = adresses[i];
````

par :

````c
                 uint32_t maintenant_ms) {
  memset(l, 0, sizeof(*l));
  l->n = n < 0 ? 0 : (n > LAMPES_CAPACITE ? LAMPES_CAPACITE : n);
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].adresse = adresses[i];
````

`components/lampes/lampes.c`, bloc 2 sur 5. Remplacer :

````c
  l->periode_ms = LAMPES_RELEVE_DEFAUT_MS;
  l->prochaine_releve_ms = maintenant_ms;  // premiere relecture aussitot (6.5)
}

````

par :

````c
  l->periode_ms = LAMPES_RELEVE_DEFAUT_MS;
  l->prochaine_releve_ms = maintenant_ms;  // premiere relecture aussitot (6.5)
  l->fen_echeance_ms = maintenant_ms + LAMPES_ALERTE_TRANCHE_MS;
}

````

`components/lampes/lampes.c`, bloc 3 sur 5. Remplacer :

````c
  // Toute trame de la lampe prouve qu'elle vit, y compris celles que l'on ne lit
  // pas (0x0A, reponses aux questions d'amaran Desktop).
  p->reponse_ms = maintenant_ms;
  p->releves_sans_reponse = 0;
````

par :

````c
  // Toute trame de la lampe prouve qu'elle vit, y compris celles que l'on ne lit
  // pas (0x0A, reponses aux questions d'amaran Desktop).
  p->entendue = true;
  p->reponse_ms = maintenant_ms;
  p->releves_sans_reponse = 0;
````

`components/lampes/lampes.c`, bloc 4 sur 5. Remplacer :

````c
}

void lampes_tic(lampes_t *l, uint32_t maintenant_ms) {
  for (int i = 0; i < l->n; i++) {
    lampe_t *p = &l->lampes[i];
````

par :

````c
}

// Relectures et reponses de la fenetre de 10 min.
static void fenetre_sommes(const lampe_t *p, uint32_t *releves, uint32_t *repondues) {
  *releves = *repondues = 0;
  for (unsigned t = 0; t < LAMPES_ALERTE_TRANCHES; t++) {
    *releves += p->fen_releves[t];
    *repondues += p->fen_repondues[t];
  }
}

static uint8_t pour_cent(uint32_t part, uint32_t total) { return (uint8_t)((part * 100u + total / 2u) / total); }

// Issue de la relecture precedente, dans la tranche courante.
static void compter_releve(const lampes_t *l, lampe_t *p) {
  if (p->fen_releves[l->fen_tranche] < UINT16_MAX) p->fen_releves[l->fen_tranche]++;
  if (p->repondu && p->fen_repondues[l->fen_tranche] < UINT16_MAX) p->fen_repondues[l->fen_tranche]++;
}

// Fin d'une tranche d'une minute : une fois 10 tranches achevees, verdict sur les 10
// dernieres minutes (alerte, spec N lampes 8) ; puis la plus ancienne repart a zero.
static void tourner_fenetre(lampes_t *l, uint32_t maintenant_ms) {
  if (l->fen_pleines < LAMPES_ALERTE_TRANCHES) l->fen_pleines++;
  if (l->fen_pleines >= LAMPES_ALERTE_TRANCHES) {
    for (int i = 0; i < l->n; i++) {
      lampe_t *p = &l->lampes[i];
      if (!p->joignable) continue;  // une lampe muette releve de 7.2, pas de cette alerte
      uint32_t releves, repondues;
      fenetre_sommes(p, &releves, &repondues);
      if (!releves) continue;
      const bool manque = repondues * 100u < LAMPES_ALERTE_SEUIL_PC * releves;
      if (manque == p->alerte) continue;
      p->alerte = manque;
      if (l->sorties.alerter) l->sorties.alerter(l->sorties.ctx, i, manque, pour_cent(repondues, releves));
    }
  }
  l->fen_tranche = (uint8_t)((l->fen_tranche + 1u) % LAMPES_ALERTE_TRANCHES);
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].fen_releves[l->fen_tranche] = 0;
    l->lampes[i].fen_repondues[l->fen_tranche] = 0;
  }
  l->fen_echeance_ms = maintenant_ms + LAMPES_ALERTE_TRANCHE_MS;
}

void lampes_forcer_publication(lampes_t *l, int lampe) {
  if (lampe < 0 || lampe >= l->n) return;
  montrer(l, lampe, true);
}

int lampes_part_repondue(const lampes_t *l, int lampe) {
  if (lampe < 0 || lampe >= l->n) return -1;
  uint32_t releves, repondues;
  fenetre_sommes(&l->lampes[lampe], &releves, &repondues);
  return releves ? (int)pour_cent(repondues, releves) : -1;
}

void lampes_tic(lampes_t *l, uint32_t maintenant_ms) {
  if (atteint(maintenant_ms, l->fen_echeance_ms)) tourner_fenetre(l, maintenant_ms);
  for (int i = 0; i < l->n; i++) {
    lampe_t *p = &l->lampes[i];
````

`components/lampes/lampes.c`, bloc 5 sur 5. Remplacer :

````c
    }
    if (p->releves_sans_reponse < 255) p->releves_sans_reponse++;
    if (l->mesh_pret) p->repondu = false;  // la relecture qui part attend sa reponse
  }
  // Mesh pas pret : rien ne part, mais les periodes comptent, et les lampes
````

par :

````c
    }
    if (p->releves_sans_reponse < 255) p->releves_sans_reponse++;
    if (l->mesh_pret) {
      // Issue de la relecture precedente, comptee si la lampe est joignable (alerte, spec
      // N lampes 8), puis la relecture qui part attend sa reponse.
      if (p->releve_en_attente && p->joignable) compter_releve(l, p);
      p->repondu = false;
      p->releve_en_attente = true;
    }
  }
  // Mesh pas pret : rien ne part, mais les periodes comptent, et les lampes
````

- [ ] **Step 5 : les tests passent.**

Run: `sh tests/hote/lancer.sh`
Expected : `lampes : 136 verifications, 0 echecs`, et `tests hote : tout est vert`.

- [ ] **Step 6 : le firmware du pont suit le renommage.** Ses deux tuiles fixes prennent une constante à lui, le temps des Tasks 2 et 3.

`firmware/main/pont_matter.h`, bloc 1 sur 1. Remplacer :

````c
#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
````

par :

````c
#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond
#define PONT_EMPLACEMENTS 2           // EP2 et EP3, crees au demarrage (plan 2)

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
````

Puis renommer partout dans le pont :

```bash
sed -i '' 's/LAMPES_MAX/PONT_EMPLACEMENTS/g' firmware/main/pont_matter.cpp firmware/main/console_pont.c firmware/main/tache_lampes.c
```

Enfin, dans `firmware/main/tache_lampes.c` (après le `sed`), la sortie `alerter` est vide pour l'instant :

`firmware/main/tache_lampes.c`, bloc 1 sur 1. Remplacer :

````c
  uint16_t adresses[PONT_EMPLACEMENTS];
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) adresses[i] = cfg->lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL};
  lampes_init(&s_lampes, adresses, PONT_EMPLACEMENTS, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
````

par :

````c
  uint16_t adresses[PONT_EMPLACEMENTS];
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) adresses[i] = cfg->lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL, NULL};
  lampes_init(&s_lampes, adresses, PONT_EMPLACEMENTS, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
````

- [ ] **Step 7 : les deux firmwares compilent.**

Run: `/usr/bin/grep -rn "LAMPES_MAX" firmware/main components/lampes` : rien.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py build 2>&1 | tail -1) && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py build 2>&1 | tail -1)`
Expected : `Project build complete.` deux fois, et aucun avertissement dans nos fichiers (ceux d'ESP-IDF et d'esp-matter, déjà là, ne comptent pas).

- [ ] **Step 8 : commit.**

```bash
git add components/lampes tests/hote/test_lampes.c firmware/main
git commit -m "$(printf "Coeur des lampes a 16 lampes : lampe entendue, alerte de relectures manquees, publication forcee\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---
### Task 3: La liste en NVS et son chargement : format versionné, conversion, `mesh lampes` et `mesh lampe`

**Files:**
- Modify: `components/mesh/CMakeLists.txt`, `components/mesh/include/config_amaran.h`, `components/mesh/include/mesh_amaran.h`, `components/mesh/include/mesh_console.h`, `components/mesh/mesh_console.c`, `components/mesh/crochet.c`, `components/mesh/mesh_amaran.c`
- Replace: `components/mesh/config_amaran.c` (contenu complet ci-dessous)
- Modify: `ecoute/main/console_ecoute.c`
- Modify: `firmware/main/pont_matter.cpp`, `firmware/main/tache_lampes.c`, `firmware/main/console_pont.c` (la liste remplace les deux emplacements ; le pont garde EP2 et EP3 jusqu'à la Task 4)

**Interfaces:**
- Consumes : la Task 1 (`liste_t`, `liste_valider`, `liste_fusionner`, `liste_chercher_mac`, format NVS, `liste_migrer_v1`, catalogue) ; la Task 2 (`LAMPES_CAPACITE`).
- Produces :
  - `amaran_config_t.liste` (un `liste_t`) remplace `lampes[2]` et `nb_lampes` ; `AMARAN_LAMPES_MAX`, `AMARAN_NOM_MAX`, `amaran_lampe_t` et `config_sauver_lampe` disparaissent ;
  - `esp_err_t config_sauver_liste(const liste_t *nouvelle)` (fusion, validation, sauvegarde ; `ESP_ERR_INVALID_ARG` si invalide) ;
  - `esp_err_t config_maj_endpoint(const uint8_t mac[6], uint16_t endpoint)` et `esp_err_t config_maj_drapeaux(const uint8_t mac[6], uint8_t drapeaux)` (`ESP_ERR_NOT_FOUND` si la liste en NVS n'a plus cette MAC) ;
  - `config_oublier_cles()` garde la liste ;
  - console : `mesh lampes <N>`, `mesh lampe <n> <adresse> <mac> <code> <nom>`, une seule réponse par ligne (spec N lampes 10) ;
  - `mesh_stats_t.derniere_reponse_us[LISTE_CAPACITE]`, files d'émission, d'événements et d'ordres à la capacité.

Pourquoi : la spec N lampes, sections 4 et 10. La conversion se fait une fois, au premier démarrage du nouveau firmware, et l'ancien format n'est effacé qu'une fois le nouveau écrit. Le verrou de la liste protège trois écrivains : la console, la tâche des lampes et le démarrage. Les tampons sont statiques, parce que les piles sont serrées.

Pas de nouveau test sur le Mac ici : ce qui se décide sans NVS est déjà testé en Task 1. La conversion se vérifie au banc 1 (Task 7).

- [ ] **Step 1 : le composant `mesh` dépend de `liste`.**

`components/mesh/CMakeLists.txt`, bloc 1 sur 1. Remplacer :

````cmake
        "${IDF_PATH}/components/bt/esp_ble_mesh/core"
        "${IDF_PATH}/components/bt/esp_ble_mesh/common/include"
    REQUIRES telink
    PRIV_REQUIRES nvs_flash mbedtls bt esp_timer console)

````

par :

````cmake
        "${IDF_PATH}/components/bt/esp_ble_mesh/core"
        "${IDF_PATH}/components/bt/esp_ble_mesh/common/include"
    REQUIRES telink liste
    PRIV_REQUIRES nvs_flash mbedtls bt esp_timer console)

````

- [ ] **Step 2 : `config_amaran.h`.**

`components/mesh/include/config_amaran.h`, bloc 1 sur 4. Remplacer :

````c
// Reglages du pont en NVS, espace "amaran" (spec 5.2 et 5.4) : cles du reseau,
// IV Index, adresse de l'ESP32, plancher de sequence, lampes.
#pragma once

````

par :

````c
// Reglages du pont en NVS, espace "amaran" (spec 5.2 et 5.4) : cles du reseau,
// IV Index, adresse de l'ESP32, plancher de sequence, liste des lampes (spec N
// lampes 4).
#pragma once

````

`components/mesh/include/config_amaran.h`, bloc 2 sur 4. Remplacer :

````c
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AMARAN_LAMPES_MAX 2
#define AMARAN_NOM_MAX 32
#define AMARAN_ADRESSE_MIN 0x7F00
#define AMARAN_ADRESSE_MAX 0x7F7F

typedef struct {
  uint16_t adresse;  // adresse Mesh de la lampe ; 0 = emplacement libre
  uint8_t mac[6];
  char nom[AMARAN_NOM_MAX];
} amaran_lampe_t;

typedef struct {
````

par :

````c
#include "esp_err.h"

#include "liste.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AMARAN_ADRESSE_MIN LISTE_RESERVEE_MIN
#define AMARAN_ADRESSE_MAX LISTE_RESERVEE_MAX

typedef struct {
````

`components/mesh/include/config_amaran.h`, bloc 3 sur 4. Remplacer :

````c
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
  uint32_t releve_ms;     // periode de relecture des lampes (pont) ; 0 = celle par defaut
  uint8_t nb_lampes;
  amaran_lampe_t lampes[AMARAN_LAMPES_MAX];
} amaran_config_t;

// Lit la NVS. Tire et sauve l'adresse et la cle d'appareil si elles manquent.
esp_err_t config_charger(amaran_config_t *c);
esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]);
esp_err_t config_sauver_lampe(uint8_t index, const amaran_lampe_t *lampe);
esp_err_t config_sauver_iv(uint32_t iv);
// Nouvelle adresse source : le plancher de sequence repart de 0 si l'adresse change.
````

par :

````c
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
  uint32_t releve_ms;     // periode de relecture des lampes (pont) ; 0 = celle par defaut
  liste_t liste;          // lue au demarrage ; une liste chargee ensuite s'applique au redemarrage
} amaran_config_t;

// Lit la NVS. Tire et sauve l'adresse et la cle d'appareil si elles manquent. La
// liste de l'ancien format (deux emplacements, plan 2) est convertie une fois.
esp_err_t config_charger(amaran_config_t *c);
esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]);
// Nouvelle liste (chargement) : fusionnee avec celle en NVS (une MAC connue garde son
// endpoint et ses drapeaux), validee, puis sauvee. Effet au redemarrage.
// ESP_ERR_INVALID_ARG si elle est invalide.
esp_err_t config_sauver_liste(const liste_t *nouvelle);
// Mise a jour d'une lampe de la liste en NVS, retrouvee par sa MAC :
// ESP_ERR_NOT_FOUND si une liste chargee depuis le demarrage ne la contient plus.
esp_err_t config_maj_endpoint(const uint8_t mac[6], uint16_t endpoint);
esp_err_t config_maj_drapeaux(const uint8_t mac[6], uint8_t drapeaux);
esp_err_t config_sauver_iv(uint32_t iv);
// Nouvelle adresse source : le plancher de sequence repart de 0 si l'adresse change.
````

`components/mesh/include/config_amaran.h`, bloc 4 sur 4. Remplacer :

````c
// Periode de relecture des lampes, en ms (commande `mesh releve` du pont).
esp_err_t config_sauver_releve(uint32_t releve_ms);
// Efface les cles et les lampes ; garde adresse, plancher et IV Index.
esp_err_t config_oublier_cles(void);
// 8 premiers chiffres hexa (majuscules) du SHA-256 de la cle, et un NUL.
````

par :

````c
// Periode de relecture des lampes, en ms (commande `mesh releve` du pont).
esp_err_t config_sauver_releve(uint32_t releve_ms);
// Efface les cles ; garde la liste des lampes (leurs tuiles restent dans Maison),
// l'adresse, le plancher et l'IV Index. Vider la liste : `mesh lampes 0`.
esp_err_t config_oublier_cles(void);
// 8 premiers chiffres hexa (majuscules) du SHA-256 de la cle, et un NUL.
````

- [ ] **Step 3 : `config_amaran.c`, réécrit.**

`components/mesh/config_amaran.c` (contenu complet) :

````c
// Reglages du pont en NVS (espace "amaran"). Les cles n'en sortent jamais : la
// console n'affiche que leur empreinte.
#include "config_amaran.h"

#include <string.h>

#include "esp_log.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

#include "texte.h"

#define ESPACE "amaran"
#define CLE_LISTE "lampes"

static const char *TAG = "config";

// Ancien format (plan 2) : deux emplacements de 40 octets.
_Static_assert(sizeof(liste_v1_t) == 40, "format du plan 2 : adresse, MAC, nom de 32 octets");
static const char *const NOMS_V1[2] = {"lampe0", "lampe1"};

// La liste se lit et s'ecrit en entier : la console (chargement, masquer, afficher),
// la tache lampes (premiere reponse) et le demarrage (numeros d'endpoint) la mettent
// a jour chacun son tour, sous ce verrou. Tampons statiques : les piles sont serrees.
static SemaphoreHandle_t s_verrou;
static StaticSemaphore_t s_verrou_memoire;
static liste_t s_actuelle, s_nouvelle;
static uint8_t s_tampon[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_t)];

static void verrouiller(void) {
  if (!s_verrou) s_verrou = xSemaphoreCreateMutexStatic(&s_verrou_memoire);  // config_charger, au demarrage
  xSemaphoreTake(s_verrou, portMAX_DELAY);
}

static void deverrouiller(void) { xSemaphoreGive(s_verrou); }

static bool lire_blob(nvs_handle_t h, const char *cle, void *dst, size_t taille) {
  size_t n = taille;
  return nvs_get_blob(h, cle, dst, &n) == ESP_OK && n == taille;
}

static esp_err_t ouvrir(nvs_handle_t *h) { return nvs_open(ESPACE, NVS_READWRITE, h); }

static esp_err_t fermer(nvs_handle_t h, esp_err_t err) {
  if (err == ESP_OK) err = nvs_commit(h);
  nvs_close(h);
  return err;
}

static esp_err_t effacer(nvs_handle_t h, const char *cle) {
  const esp_err_t e = nvs_erase_key(h, cle);
  return e == ESP_ERR_NVS_NOT_FOUND ? ESP_OK : e;
}

// Liste en NVS (sous le verrou). ESP_ERR_NVS_NOT_FOUND : jamais ecrite. Une liste
// illisible ou invalide donne une liste vide, et le dit au journal.
static esp_err_t lire_liste(nvs_handle_t h, liste_t *l) {
  memset(l, 0, sizeof(*l));
  size_t n = sizeof(s_tampon);
  const esp_err_t err = nvs_get_blob(h, CLE_LISTE, s_tampon, &n);
  if (err != ESP_OK) return err;
  int fautive = -1;
  if (!liste_depuis_nvs(l, s_tampon, (uint32_t)n)) {
    ESP_LOGE(TAG, "liste des lampes illisible (format) : liste vide");
  } else if (liste_valider(l, &fautive) != LISTE_OK) {
    ESP_LOGE(TAG, "liste des lampes invalide (lampe %d) : liste vide", fautive + 1);
    memset(l, 0, sizeof(*l));
  }
  return ESP_OK;
}

static esp_err_t ecrire_liste(nvs_handle_t h, const liste_t *l) {
  liste_vers_nvs(l, s_tampon);
  return nvs_set_blob(h, CLE_LISTE, s_tampon, liste_taille_nvs(l));
}

// Ancien format, converti une fois : l'emplacement i gardait l'endpoint 2 + i.
// L'ancien n'est efface qu'une fois le nouveau ecrit (coupure : on recommence).
static esp_err_t migrer_v1(nvs_handle_t h, liste_t *l) {
  liste_v1_t v1[2];
  bool lu[2];
  for (int i = 0; i < 2; i++) lu[i] = lire_blob(h, NOMS_V1[i], &v1[i], sizeof(v1[i]));
  liste_migrer_v1(l, v1, lu);
  if (!lu[0] && !lu[1]) return ESP_OK;
  esp_err_t err = ecrire_liste(h, l);
  if (err == ESP_OK) err = nvs_commit(h);
  for (int i = 0; i < 2 && err == ESP_OK; i++) err = effacer(h, NOMS_V1[i]);
  if (err == ESP_OK) ESP_LOGI(TAG, "liste des lampes convertie : %u lampe(s), EP2 et EP3 gardes", l->n);
  return err;
}

esp_err_t config_charger(amaran_config_t *c) {
  memset(c, 0, sizeof(*c));
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  c->cles_presentes = lire_blob(h, "netkey", c->netkey, 16) && lire_blob(h, "appkey", c->appkey, 16);
  if (!c->cles_presentes) {
    memset(c->netkey, 0, sizeof(c->netkey));
    memset(c->appkey, 0, sizeof(c->appkey));
  }
  if (!lire_blob(h, "devkey", c->devkey, 16)) {
    esp_fill_random(c->devkey, sizeof(c->devkey));
    err = nvs_set_blob(h, "devkey", c->devkey, sizeof(c->devkey));
  }
  if (nvs_get_u32(h, "iv", &c->iv) != ESP_OK) c->iv = 0;
  if (nvs_get_u16(h, "adresse", &c->adresse) != ESP_OK || c->adresse < AMARAN_ADRESSE_MIN ||
      c->adresse > AMARAN_ADRESSE_MAX) {
    // Tiree au hasard dans la plage reservee : apres un effacement de la
    // flash, peu de chances de retomber sur une adresse dont les lampes
    // gardent un compteur plus haut que le notre (elles nous ignoreraient).
    c->adresse = (uint16_t)(AMARAN_ADRESSE_MIN + esp_random() % (AMARAN_ADRESSE_MAX - AMARAN_ADRESSE_MIN + 1));
    if (err == ESP_OK) err = nvs_set_u16(h, "adresse", c->adresse);
  }
  if (nvs_get_u32(h, "plancher", &c->plancher_seq) != ESP_OK) c->plancher_seq = 0;
  if (nvs_get_u32(h, "releve", &c->releve_ms) != ESP_OK) c->releve_ms = 0;
  verrouiller();
  const esp_err_t lu = lire_liste(h, &c->liste);
  if (lu == ESP_ERR_NVS_NOT_FOUND) {
    const esp_err_t m = migrer_v1(h, &c->liste);
    if (m != ESP_OK) ESP_LOGE(TAG, "conversion de la liste des lampes : %s", esp_err_to_name(m));
  } else if (lu != ESP_OK) {
    ESP_LOGE(TAG, "liste des lampes illisible (%s) : liste vide", esp_err_to_name(lu));
  }
  deverrouiller();
  return fermer(h, err);
}

esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = nvs_set_blob(h, "netkey", netkey, 16);
  if (err == ESP_OK) err = nvs_set_blob(h, "appkey", appkey, 16);
  return fermer(h, err);
}

esp_err_t config_sauver_liste(const liste_t *nouvelle) {
  int fautive = -1;
  if (liste_valider(nouvelle, &fautive) != LISTE_OK) return ESP_ERR_INVALID_ARG;
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  verrouiller();
  const esp_err_t lu = lire_liste(h, &s_actuelle);
  if (lu == ESP_OK || lu == ESP_ERR_NVS_NOT_FOUND) {
    s_nouvelle = *nouvelle;
    liste_fusionner(&s_nouvelle, &s_actuelle);
    err = ecrire_liste(h, &s_nouvelle);
  } else {
    err = lu;
  }
  deverrouiller();
  return fermer(h, err);
}

// Lit la liste, change une lampe retrouvee par sa MAC, ecrit la liste.
static esp_err_t maj_lampe(const uint8_t mac[6], bool endpoint, uint16_t valeur) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  verrouiller();
  err = lire_liste(h, &s_actuelle);
  const int i = err == ESP_OK ? liste_chercher_mac(&s_actuelle, mac) : -1;
  if (err == ESP_OK && i < 0) err = ESP_ERR_NOT_FOUND;
  if (err == ESP_OK) {
    if (endpoint) {
      s_actuelle.lampes[i].endpoint = valeur;
    } else {
      s_actuelle.lampes[i].drapeaux = (uint8_t)valeur;
    }
    err = ecrire_liste(h, &s_actuelle);
  }
  deverrouiller();
  return fermer(h, err);
}

esp_err_t config_maj_endpoint(const uint8_t mac[6], uint16_t endpoint) { return maj_lampe(mac, true, endpoint); }

esp_err_t config_maj_drapeaux(const uint8_t mac[6], uint8_t drapeaux) { return maj_lampe(mac, false, drapeaux); }

esp_err_t config_sauver_iv(uint32_t iv) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "iv", iv));
}

esp_err_t config_sauver_adresse(uint16_t adresse) {
  if (adresse < AMARAN_ADRESSE_MIN || adresse > AMARAN_ADRESSE_MAX) return ESP_ERR_INVALID_ARG;
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  uint16_t ancienne_adresse;
  const bool adresse_change = nvs_get_u16(h, "adresse", &ancienne_adresse) != ESP_OK || ancienne_adresse != adresse;
  err = nvs_set_u16(h, "adresse", adresse);
  // Nouvelle adresse source : les lampes n'en connaissent aucun compteur.
  if (err == ESP_OK && adresse_change) err = nvs_set_u32(h, "plancher", 0);
  return fermer(h, err);
}

esp_err_t config_sauver_plancher(uint32_t plancher) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "plancher", plancher));
}

esp_err_t config_sauver_releve(uint32_t releve_ms) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "releve", releve_ms));
}

esp_err_t config_oublier_cles(void) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = effacer(h, "netkey");
  if (err == ESP_OK) err = effacer(h, "appkey");
  return fermer(h, err);
}

void config_empreinte(const uint8_t cle[16], char sortie[9]) {
  uint8_t condensat[32];
  mbedtls_sha256(cle, 16, condensat, 0);
  texte_octets_vers_hex(condensat, 4, sortie);
}
````

- [ ] **Step 4 : `mesh_amaran.h`, `mesh_amaran.c` et `crochet.c` à la capacité.**

`components/mesh/include/mesh_amaran.h`, bloc 1 sur 2. Remplacer :

````c
  uint16_t src;
  uint16_t dst;
  int8_t lampe;       // index 0..AMARAN_LAMPES_MAX-1, ou -1
  uint8_t len;        // octets utiles de acces
  uint8_t acces[16];  // opcode puis charge
````

par :

````c
  uint16_t src;
  uint16_t dst;
  int8_t lampe;       // index dans la liste des lampes (0..LISTE_CAPACITE-1), ou -1
  uint8_t len;        // octets utiles de acces
  uint8_t acces[16];  // opcode puis charge
````

`components/mesh/include/mesh_amaran.h`, bloc 2 sur 2. Remplacer :

````c
  uint32_t derniere_balise_iv;
  uint8_t derniere_balise_flags;
  int64_t derniere_reponse_us[AMARAN_LAMPES_MAX];
} mesh_stats_t;

````

par :

````c
  uint32_t derniere_balise_iv;
  uint8_t derniere_balise_flags;
  int64_t derniere_reponse_us[LISTE_CAPACITE];
} mesh_stats_t;

````

`components/mesh/mesh_amaran.c`, bloc 1 sur 1. Remplacer :

````c
// vTaskDelay(n) dort entre n-1 et n ticks (60 a 70 ms a 100 Hz) : un tick de plus tient ECART_MS au moins.
#define ECART_TICKS (pdMS_TO_TICKS(ECART_MS) + 1)
#define FILE_TX 16

typedef struct {
````

par :

````c
// vTaskDelay(n) dort entre n-1 et n ticks (60 a 70 ms a 100 Hz) : un tick de plus tient ECART_MS au moins.
#define ECART_TICKS (pdMS_TO_TICKS(ECART_MS) + 1)
#define FILE_TX (3 * LISTE_CAPACITE + 4)  // une salve par lampe (3 trames au plus), et la relecture

typedef struct {
````

`components/mesh/crochet.c`, bloc 1 sur 5. Remplacer :

````c
#endif

#define FILE_EVENEMENTS 32
#define PDU_MIN 18  // plancher de la pile (net.c) : le plus court message reseau qu'elle accepte
#define PDU_MAX 32
````

par :

````c
#endif

#define FILE_EVENEMENTS (4 * LISTE_CAPACITE)  // toutes les lampes repondent a la meme relecture
#define PDU_MIN 18  // plancher de la pile (net.c) : le plus court message reseau qu'elle accepte
#define PDU_MAX 32
````

`components/mesh/crochet.c`, bloc 2 sur 5. Remplacer :

````c

static QueueHandle_t s_file;
static uint16_t s_lampes[AMARAN_LAMPES_MAX];
static volatile bool s_detail;
static mesh_stats_t s_st;
````

par :

````c

static QueueHandle_t s_file;
static uint16_t s_lampes[LISTE_CAPACITE];
static volatile bool s_detail;
static mesh_stats_t s_st;
````

`components/mesh/crochet.c`, bloc 3 sur 5. Remplacer :

````c
// Dernier message retenu de chaque lampe : ecarte les copies reseau (1 a 3 par
// reponse au banc) et les rejeux. En RAM seulement : repart a zero au demarrage.
static tri_dernier_t s_dernier[AMARAN_LAMPES_MAX];

// Messages de notre reseau au NetMIC faux : matiere de `mesh iv cherche`. La
````

par :

````c
// Dernier message retenu de chaque lampe : ecarte les copies reseau (1 a 3 par
// reponse au banc) et les rejeux. En RAM seulement : repart a zero au demarrage.
static tri_dernier_t s_dernier[LISTE_CAPACITE];

// Messages de notre reseau au NetMIC faux : matiere de `mesh iv cherche`. La
````

`components/mesh/crochet.c`, bloc 4 sur 5. Remplacer :

````c

esp_err_t crochet_demarrer(const amaran_config_t *cfg) {
  for (int i = 0; i < AMARAN_LAMPES_MAX; i++) s_lampes[i] = cfg->lampes[i].adresse;
  s_iv_connu = cfg->iv;
  s_file = xQueueCreate(FILE_EVENEMENTS, sizeof(mesh_evenement_t));
````

par :

````c

esp_err_t crochet_demarrer(const amaran_config_t *cfg) {
  for (int i = 0; i < LISTE_CAPACITE; i++) s_lampes[i] = i < cfg->liste.n ? cfg->liste.lampes[i].adresse : 0;
  s_iv_connu = cfg->iv;
  s_file = xQueueCreate(FILE_EVENEMENTS, sizeof(mesh_evenement_t));
````

`components/mesh/crochet.c`, bloc 5 sur 5. Remplacer :

````c
  memcpy(ev.acces, acces, n);
  uint8_t trame[TELINK_TAILLE];
  const int l = tri_etat_lampe(e->src, acces, n, s_lampes, AMARAN_LAMPES_MAX, trame);
  if (l >= 0) {
    if (!tri_plus_recent(&s_dernier[l], iv, e->seq)) {
````

par :

````c
  memcpy(ev.acces, acces, n);
  uint8_t trame[TELINK_TAILLE];
  const int l = tri_etat_lampe(e->src, acces, n, s_lampes, LISTE_CAPACITE, trame);
  if (l >= 0) {
    if (!tri_plus_recent(&s_dernier[l], iv, e->seq)) {
````

- [ ] **Step 5 : la console partagée : `mesh lampes`, `mesh lampe`, `mesh`, `mesh oublie`.**

`components/mesh/include/mesh_console.h`, bloc 1 sur 1. Remplacer :

````c
// jour). taches : les noms de taches que `taches` examine.
void mesh_console_init(amaran_config_t *cfg, const char *const *taches, size_t nb_taches);
// La commande `mesh` : etat sans argument ; cles, lampe, iv, adresse, oublie,
// ecoute, balayage, autotest.
int mesh_console_commande(int argc, char **argv);
// La commande `taches` : pile libre au plus bas de chaque tache, et le tas.
````

par :

````c
// jour). taches : les noms de taches que `taches` examine.
void mesh_console_init(amaran_config_t *cfg, const char *const *taches, size_t nb_taches);
// La commande `mesh` : etat sans argument ; cles, lampes, lampe, iv, adresse,
// oublie, ecoute, balayage, autotest.
int mesh_console_commande(int argc, char **argv);
// La commande `taches` : pile libre au plus bas de chaque tache, et le tas.
````

`components/mesh/mesh_console.c`, bloc 1 sur 6. Remplacer :

````c
#include "linenoise/linenoise.h"

#include "telink.h"
#include "texte.h"
````

par :

````c
#include "linenoise/linenoise.h"

#include "catalogue.h"
#include "telink.h"
#include "texte.h"
````

`components/mesh/mesh_console.c`, bloc 2 sur 6. Remplacer :

````c
         s_cfg->adresse, mesh_iv_courant(), s_cfg->iv, mesh_sequence(),
         mesh_pret() ? mesh_plancher() : s_cfg->plancher_seq);
  for (int i = 0; i < AMARAN_LAMPES_MAX; i++) {
    const amaran_lampe_t *l = &s_cfg->lampes[i];
    if (!l->adresse) continue;
    if (st.derniere_reponse_us[i]) {
      printf("lampe %d : 0x%04x %s, derniere reponse il y a %lld s\n", i + 1, l->adresse, l->nom,
````

par :

````c
         s_cfg->adresse, mesh_iv_courant(), s_cfg->iv, mesh_sequence(),
         mesh_pret() ? mesh_plancher() : s_cfg->plancher_seq);
  for (int i = 0; i < s_cfg->liste.n; i++) {
    const liste_lampe_t *l = &s_cfg->liste.lampes[i];
    if (st.derniere_reponse_us[i]) {
      printf("lampe %d : 0x%04x %s, derniere reponse il y a %lld s\n", i + 1, l->adresse, l->nom,
````

`components/mesh/mesh_console.c`, bloc 3 sur 6. Remplacer :

````c
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
````

par :

````c
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
````

`components/mesh/mesh_console.c`, bloc 4 sur 6. Remplacer :

````c
  }
  l.nom[pos] = '\0';
  if (config_sauver_lampe((uint8_t)(n - 1), &l) != ESP_OK) {
    printf("erreur : ecriture NVS\n");
    return 1;
  }
  printf("ok lampe %" PRIu32 " 0x%04x %s (redemarrer pour l'appliquer)\n", n, l.adresse, l.nom);
  return 0;
}
````

par :

````c
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
````

`components/mesh/mesh_console.c`, bloc 5 sur 6. Remplacer :

````c
  const char *s = argv[1];
  if (!strcmp(s, "cles")) return mesh_cles(argc, argv);
  if (!strcmp(s, "lampe")) return mesh_lampe(argc, argv);
  if (!strcmp(s, "iv")) return mesh_iv(argc, argv);
````

par :

````c
  const char *s = argv[1];
  if (!strcmp(s, "cles")) return mesh_cles(argc, argv);
  if (!strcmp(s, "lampes")) return mesh_lampes(argc, argv);
  if (!strcmp(s, "lampe")) return mesh_lampe(argc, argv);
  if (!strcmp(s, "iv")) return mesh_iv(argc, argv);
````

`components/mesh/mesh_console.c`, bloc 6 sur 6. Remplacer :

````c
      return 1;
    }
    printf("ok cles et lampes oubliees\n");
    mesh_console_redemarrer();
    return 0;
````

par :

````c
      return 1;
    }
    printf("ok cles oubliees (la liste des lampes reste ; mesh lampes 0 pour la vider)\n");
    mesh_console_redemarrer();
    return 0;
````

- [ ] **Step 6 : le firmware d'écoute.**

`ecoute/main/console_ecoute.c`, bloc 1 sur 3. Remplacer :

````c
static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > AMARAN_LAMPES_MAX ||
      !s_cfg->lampes[n - 1].adresse) {
    printf("erreur : lampe <1-%d> releve|on|off|niveau <0-1000> (lampe declaree ?)\n", AMARAN_LAMPES_MAX);
    return 1;
  }
````

par :

````c
static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > s_cfg->liste.n) {
    printf("erreur : lampe <1-%u> releve|on|off|niveau <0-1000> (lampe declaree ?)\n", (unsigned)s_cfg->liste.n);
    return 1;
  }
````

`ecoute/main/console_ecoute.c`, bloc 2 sur 3. Remplacer :

````c
    return 1;
  }
  return envoyer(s_cfg->lampes[n - 1].adresse, t, repetitions);
}

````

par :

````c
    return 1;
  }
  return envoyer(s_cfg->liste.lampes[n - 1].adresse, t, repetitions);
}

````

`ecoute/main/console_ecoute.c`, bloc 3 sur 3. Remplacer :

````c
  const esp_console_cmd_t cmds[] = {
      {.command = "mesh",
       .help = "etat ; mesh cles|lampe|iv|adresse|oublie|ecoute|balayage|autotest ...",
       .func = mesh_console_commande},
      {.command = "lampe", .help = "lampe <1-2> releve|on|off|niveau <0-1000>", .func = cmd_lampe},
      {.command = "groupe", .help = "groupe releve : demande d'etat au groupe All (0xC000)", .func = cmd_groupe},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
````

par :

````c
  const esp_console_cmd_t cmds[] = {
      {.command = "mesh",
       .help = "etat ; mesh cles|lampes|lampe|iv|adresse|oublie|ecoute|balayage|autotest ...",
       .func = mesh_console_commande},
      {.command = "lampe", .help = "lampe <n> releve|on|off|niveau <0-1000>", .func = cmd_lampe},
      {.command = "groupe", .help = "groupe releve : demande d'etat au groupe All (0xC000)", .func = cmd_groupe},
      {.command = "redemarre", .help = "redemarre la carte", .func = cmd_redemarre},
````

- [ ] **Step 7 : le pont, sur la liste, toujours avec EP2 et EP3.**

`firmware/main/pont_matter.cpp`, bloc 1 sur 4. Remplacer :

````cpp

static uint16_t s_ep_lampe[PONT_EMPLACEMENTS];  // EP2 et EP3 ; 0 = pas encore cree
static char s_nom_lampe[PONT_EMPLACEMENTS][AMARAN_NOM_MAX];
static pont_ordre_cb_t s_ordre;
static int64_t s_ordres_des_us;  // avant : valeurs posees par la pile au demarrage, pas des ordres
````

par :

````cpp

static uint16_t s_ep_lampe[PONT_EMPLACEMENTS];  // EP2 et EP3 ; 0 = pas encore cree
static char s_nom_lampe[PONT_EMPLACEMENTS][LISTE_NOM_MAX];
static pont_ordre_cb_t s_ordre;
static int64_t s_ordres_des_us;  // avant : valeurs posees par la pile au demarrage, pas des ordres
````

`firmware/main/pont_matter.cpp`, bloc 2 sur 4. Remplacer :

````cpp
  // (2 et 3) suivent l'ordre de creation et ne changent jamais (spec 6.1).
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) {
    const amaran_lampe_t *l = &cfg->lampes[i];
    endpoint::bridged_node::config_t cfg_pontee;
    char *uid = cfg_pontee.bridged_device_basic_information.unique_id;
    const size_t tuid = sizeof(cfg_pontee.bridged_device_basic_information.unique_id);
    if (l->adresse) {
      snprintf(uid, tuid, "%02X%02X%02X%02X%02X%02X", l->mac[0], l->mac[1], l->mac[2], l->mac[3], l->mac[4],
               l->mac[5]);
````

par :

````cpp
  // (2 et 3) suivent l'ordre de creation et ne changent jamais (spec 6.1).
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) {
    const liste_lampe_t *l = i < cfg->liste.n ? &cfg->liste.lampes[i] : NULL;
    endpoint::bridged_node::config_t cfg_pontee;
    char *uid = cfg_pontee.bridged_device_basic_information.unique_id;
    const size_t tuid = sizeof(cfg_pontee.bridged_device_basic_information.unique_id);
    if (l) {
      snprintf(uid, tuid, "%02X%02X%02X%02X%02X%02X", l->mac[0], l->mac[1], l->mac[2], l->mac[3], l->mac[4],
               l->mac[5]);
````

`firmware/main/pont_matter.cpp`, bloc 3 sur 4. Remplacer :

````cpp
    if (endpoint::dimmable_light::add(ep, &cfg_lampe) != ESP_OK) return ESP_FAIL;
    if (endpoint::set_parent_endpoint(ep, agregateur) != ESP_OK) return ESP_FAIL;
    snprintf(s_nom_lampe[i], sizeof(s_nom_lampe[i]), "%s", l->adresse ? l->nom : "lampe absente");
    cluster_t *pontee = cluster::get(ep, BridgedDeviceBasicInformation::Id);
    if (pontee) {
````

par :

````cpp
    if (endpoint::dimmable_light::add(ep, &cfg_lampe) != ESP_OK) return ESP_FAIL;
    if (endpoint::set_parent_endpoint(ep, agregateur) != ESP_OK) return ESP_FAIL;
    snprintf(s_nom_lampe[i], sizeof(s_nom_lampe[i]), "%s", l ? l->nom : "lampe absente");
    cluster_t *pontee = cluster::get(ep, BridgedDeviceBasicInformation::Id);
    if (pontee) {
````

`firmware/main/pont_matter.cpp`, bloc 4 sur 4. Remplacer :

````cpp
  // joignables (spec 6.5) et se calent au premier etat lu.
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) {
    if (!cfg->lampes[i].adresse) pont_publier(i, NULL, false);
  }
  return ESP_OK;
````

par :

````cpp
  // joignables (spec 6.5) et se calent au premier etat lu.
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) {
    if (i >= cfg->liste.n) pont_publier(i, NULL, false);
  }
  return ESP_OK;
````

`firmware/main/tache_lampes.c`, bloc 1 sur 3. Remplacer :

````c

#define TIC_MS 50
#define FILE_ORDRES 16

typedef enum { MSG_ORDRE, MSG_RELEVE } message_type_t;
````

par :

````c

#define TIC_MS 50
#define FILE_ORDRES (3 * LAMPES_CAPACITE)  // une commande Matter ecrit jusqu'a 3 attributs par lampe

typedef enum { MSG_ORDRE, MSG_RELEVE } message_type_t;
````

`firmware/main/tache_lampes.c`, bloc 2 sur 3. Remplacer :

````c
  s_verrou = xSemaphoreCreateMutex();
  if (!s_file || !s_verrou) return ESP_ERR_NO_MEM;
  uint16_t adresses[PONT_EMPLACEMENTS];
  for (int i = 0; i < PONT_EMPLACEMENTS; i++) adresses[i] = cfg->lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL, NULL};
  lampes_init(&s_lampes, adresses, PONT_EMPLACEMENTS, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
  return xTaskCreate(tache, "lampes", 4096, NULL, 4, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
````

par :

````c
  s_verrou = xSemaphoreCreateMutex();
  if (!s_file || !s_verrou) return ESP_ERR_NO_MEM;
  uint16_t adresses[LAMPES_CAPACITE];
  for (int i = 0; i < cfg->liste.n; i++) adresses[i] = cfg->liste.lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL, NULL};
  lampes_init(&s_lampes, adresses, cfg->liste.n, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
  return xTaskCreate(tache, "lampes", 4096, NULL, 4, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
````

`firmware/main/tache_lampes.c`, bloc 3 sur 3. Remplacer :

````c

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  if (!s_file || lampe < 0 || lampe >= PONT_EMPLACEMENTS) return;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter};
  if (marche) {
````

par :

````c

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  if (!s_file || lampe < 0 || lampe >= LAMPES_CAPACITE) return;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter};
  if (marche) {
````

`firmware/main/console_pont.c`, bloc 1 sur 4. Remplacer :

````c
  for (int i = 0; i < l.n; i++) {
    const lampe_t *p = &l.lampes[i];
    printf("lampe %d : 0x%04x %s, %s\n", i + 1, p->adresse, s_cfg->lampes[i].adresse ? s_cfg->lampes[i].nom : "(absente)",
           p->joignable ? "joignable" : "PAS DE REPONSE");
    printf("  lue       : ");
````

par :

````c
  for (int i = 0; i < l.n; i++) {
    const lampe_t *p = &l.lampes[i];
    printf("lampe %d : 0x%04x %s, %s\n", i + 1, p->adresse, s_cfg->liste.lampes[i].nom,
           p->joignable ? "joignable" : "PAS DE REPONSE");
    printf("  lue       : ");
````

`firmware/main/console_pont.c`, bloc 2 sur 4. Remplacer :

````c
static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > PONT_EMPLACEMENTS || !s_cfg->lampes[n - 1].adresse) {
    printf("erreur : lampe <1-%d> on|off|niveau <0-1000>|releve (lampe declaree ?)\n", PONT_EMPLACEMENTS);
    return 1;
  }
````

par :

````c
static int cmd_lampe(int argc, char **argv) {
  uint32_t n = 0;
  if (argc < 3 || !texte_lire_nombre(argv[1], &n) || n < 1 || n > s_cfg->liste.n) {
    printf("erreur : lampe <1-%u> on|off|niveau <0-1000>|releve (lampe declaree ?)\n", (unsigned)s_cfg->liste.n);
    return 1;
  }
````

`firmware/main/console_pont.c`, bloc 3 sur 4. Remplacer :

````c
    uint8_t t[TELINK_TAILLE];
    telink_demande_etat(t);
    const esp_err_t err = mesh_envoyer(s_cfg->lampes[i].adresse, t, MESH_REPETITIONS_ETAT);
    printf(err == ESP_OK ? "ok demande d'etat a la lampe %d\n" : "erreur : envoi impossible (lampe %d)\n", i + 1);
    return err == ESP_OK ? 0 : 1;
````

par :

````c
    uint8_t t[TELINK_TAILLE];
    telink_demande_etat(t);
    const esp_err_t err = mesh_envoyer(s_cfg->liste.lampes[i].adresse, t, MESH_REPETITIONS_ETAT);
    printf(err == ESP_OK ? "ok demande d'etat a la lampe %d\n" : "erreur : envoi impossible (lampe %d)\n", i + 1);
    return err == ESP_OK ? 0 : 1;
````

`firmware/main/console_pont.c`, bloc 4 sur 4. Remplacer :

````c
  const esp_console_cmd_t cmds[] = {
      {.command = "lampes", .help = "etat des lampes : lu, consigne, joignabilite, releves, ordres", .func = cmd_lampes},
      {.command = "lampe", .help = "lampe <1-2> on|off|niveau <0-1000>|releve", .func = cmd_lampe},
      {.command = "mesh",
       .help = "etat ; mesh cles|lampe|iv|adresse|oublie|ecoute|balayage|autotest|releve ...",
       .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
````

par :

````c
  const esp_console_cmd_t cmds[] = {
      {.command = "lampes", .help = "etat des lampes : lu, consigne, joignabilite, releves, ordres", .func = cmd_lampes},
      {.command = "lampe", .help = "lampe <n> on|off|niveau <0-1000>|releve", .func = cmd_lampe},
      {.command = "mesh",
       .help = "etat ; mesh cles|lampes|lampe|iv|adresse|oublie|ecoute|balayage|autotest|releve ...",
       .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
````

- [ ] **Step 8 : vérifications.**

Run: `/usr/bin/grep -rn "AMARAN_LAMPES_MAX\|amaran_lampe_t\|cfg->lampes\|s_cfg->lampes\|AMARAN_NOM_MAX\|config_sauver_lampe" components firmware/main ecoute/main` : rien.

Run: `sh tests/hote/lancer.sh` : `tests hote : tout est vert`.

Run (le composant `liste` est neuf pour les deux firmwares : `reconfigure` d'abord) : `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py reconfigure >/dev/null && idf.py build 2>&1 | tail -1) && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py reconfigure >/dev/null && idf.py build 2>&1 | tail -1)`
Expected : `Project build complete.` deux fois, sans avertissement dans nos fichiers.

- [ ] **Step 9 : commit.**

```bash
git add components/mesh ecoute/main firmware/main
git commit -m "$(printf "Garder la liste des lampes en NVS, convertir l'ancien format, charger une liste tout ou rien\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---
### Task 4: Les lampes dans Maison : endpoints à la demande, numéros stables, exposition, console

**Files:**
- Replace: `firmware/main/pont_matter.h`, `firmware/main/pont_matter.cpp`, `firmware/main/tache_lampes.h`, `firmware/main/console_pont.c` (contenus complets ci-dessous)
- Modify: `firmware/main/tache_lampes.c`, `firmware/sdkconfig.defaults`

**Interfaces:**
- Consumes : Tasks 1 à 3 (`liste_exposee`, `liste_a_exposer_a_l_ecoute`, `liste_marquer_vue`, `liste_masquer`, `liste_afficher`, catalogue, `config_maj_endpoint`, `config_maj_drapeaux`, `lampes_forcer_publication`, `lampes_part_repondue`, sortie `alerter`, `entendue`).
- Produces :
  - `esp_err_t pont_exposer(int lampe, const liste_lampe_t *l)`, `esp_err_t pont_masquer(int lampe)`, `uint16_t pont_endpoint(int lampe)` ;
  - `void tache_lampes_lire_liste(liste_t *copie)`, `esp_err_t tache_lampes_exposition(int lampe, bool afficher)` ;
  - console : `lampes` (une ligne par lampe), `lampe <n>` (détail), `mesh lampe <n> masquer|afficher` ;
  - `PONT_EMPLACEMENTS` disparaît.

Pourquoi : la spec N lampes, sections 5 et 7, sur le schéma des exemples de pont d'esp-matter (`examples/common/app_bridge/app_bridged_device.cpp`).
- **Démarrage.** Juste après `esp_matter::start()`, chaque lampe exposée est recréée avec son numéro (`bridged_node::resume`), dans l'ordre croissant des numéros, puis activée (`endpoint::enable`).
- **Lampe sans numéro.** Une lampe sans numéro, ou dont le numéro dépasse le compteur relu (désappairage complet), en reçoit un de `bridged_node::create`. Il est sauvé en NVS.
- **Garde.** Une garde de 2 s par lampe ignore les valeurs que la pile pose à la création de son endpoint.
- **Verrous.** `endpoint::enable` et `endpoint::destroy` prennent eux-mêmes le verrou de la pile : on ne les appelle jamais en le tenant, ni depuis la tâche CHIP.
- **Pile de la tâche des lampes.** `enable` fait tourner les rappels d'init des clusters Matter sur la pile de l'appelant. La tâche des lampes, qui expose une lampe à sa première réponse, passe donc de 4 à 6 Ko.

- [ ] **Step 1 : `pont_matter.h`.**

`firmware/main/pont_matter.h` (contenu complet) :

````c
// Cote Matter du pont (spec 6 ; spec N lampes 5 et 7) : noeud (EP0), agregateur
// (EP1) et un endpoint ponte par lampe exposee, avec son numero ; ordres des
// controleurs, etat des lampes publie sans echo, abonnements plafonnes, identite.
// Ecrit en C++ (esp-matter), appele depuis le C.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"
#include "liste.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
// marche et/ou intensite 0..1000 (NULL : inchange).
typedef void (*pont_ordre_cb_t)(int lampe, const bool *marche, const uint16_t *intensite);

// Cree le noeud et l'agregateur, ecrit l'identite, demarre Matter, puis cree
// l'endpoint de chaque lampe exposee de cfg (pont_exposer). Les ordres arrivent par
// ordre().
esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre);
// Fait entrer la lampe dans Maison : son endpoint, avec son numero s'il en a un (le
// suivant du compteur d'esp-matter sinon, sauve en NVS), et le type d'appareil que
// donne le catalogue. Sans effet si elle y est deja. Apres pont_demarrer, hors de
// la tache CHIP : prend le verrou de la pile.
esp_err_t pont_exposer(int lampe, const liste_lampe_t *l);
// Retire l'endpoint de la lampe : Maison retire sa tuile. La lampe garde son numero.
esp_err_t pont_masquer(int lampe);
// Numero d'endpoint de la lampe ; 0 si elle n'est pas exposee.
uint16_t pont_endpoint(int lampe);
// Etat d'une lampe dans Matter (attribute::report : aucun rappel, donc aucun
// echo). etat NULL : jamais lu, seule la joignabilite change. Intensite 0 (lampe
// noire jamais vue allumee) : OnOff est publie, CurrentLevel reste ce qu'il est.
// Sans effet tant que Matter n'est pas demarre, ou pour une lampe non exposee.
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
// Un controleur demande l'identification (IdentifyTime ou un effet en cours).
bool pont_identifie(void);

#ifdef __cplusplus
}
#endif
````

- [ ] **Step 2 : `pont_matter.cpp`.**

`firmware/main/pont_matter.cpp` (contenu complet) :

````cpp
// Cote Matter du pont (voir pont_matter.h). Modeles : l'exemple light
// d'esp-matter (demarrage, Thread), ses exemples de pont (endpoints pontes recrees
// juste apres esp_matter::start, avec leur numero, puis actives), le pont Halo
// (plafond des abonnements, identite, fenetre rouverte quand la derniere fabrique
// part).
#include "pont_matter.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
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

#include "catalogue.h"
#include "mesh_amaran.h"
#include "status_led.h"

using namespace esp_matter;
using namespace chip::app::Clusters;

static const char *TAG = "pont";

// EP0 (noeud), EP1 (agregateur), puis une lampe par endpoint dynamique.
static_assert(CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT >= LISTE_CAPACITE + 2,
              "CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT : noeud, agregateur et LISTE_CAPACITE lampes");

static node_t *s_noeud;
static endpoint_t *s_agregateur;
static uint16_t s_ep_lampe[LISTE_CAPACITE];  // numero d'endpoint ; 0 = lampe non exposee
// Dernier numero de chaque lampe, garde quand elle est masquee : la liste de
// l'appelant peut dater d'avant un renumerotage (desappairage complet).
static uint16_t s_numero[LISTE_CAPACITE];
static char s_nom_lampe[LISTE_CAPACITE][LISTE_NOM_MAX];
// Exposer et masquer : une lampe a la fois (console, tache lampes, demarrage).
static SemaphoreHandle_t s_verrou_exposition;
static pont_ordre_cb_t s_ordre;
// Avant cette echeance, ce qui arrive sur l'endpoint d'une lampe vient de la pile
// (valeurs posees a sa creation), pas d'un controleur (lecon du Halo : 2 s).
static int64_t s_ordres_des_us[LISTE_CAPACITE];
static volatile bool s_ble_annonce;
static volatile int s_role = OT_DEVICE_ROLE_DISABLED;
// Fabriques, relues dans la tache CHIP (evenements, et apres start) : lues sans
// le verrou de la pile depuis nos taches (spec 4.3).
static volatile uint8_t s_fabriques;
static volatile uint32_t s_abo_demandes, s_abo_plafonnes, s_abo_etablis, s_abo_termines;
// Identify, par emplacement : 0 et 1 pour le noeud et l'agregateur, 2 + i pour la
// lampe i (les numeros d'endpoint, eux, croissent sans fin). Emplacements en
// IdentifyTime (bits), et fin d'effet (ms, 0 = aucun) : la pile n'envoie jamais de
// STOP apres un effet (lecon du Halo).
#define EMPLACEMENTS (LISTE_CAPACITE + 2)
static_assert(EMPLACEMENTS <= 32, "s_identifie : un bit par emplacement");
static volatile uint32_t s_identifie;
static volatile uint32_t s_effet_fin[EMPLACEMENTS];

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
  if (ep < 2) return -1;
  for (int i = 0; i < LISTE_CAPACITE; i++) {
    if (s_ep_lampe[i] == ep) return i;
  }
  return -1;
}

static int emplacement_de(uint16_t ep) {
  if (ep < 2) return ep;
  const int i = lampe_de(ep);
  return i < 0 ? -1 : 2 + i;
}

// POST_UPDATE : la valeur est posee. Nos propres publications passent par
// attribute::report(), qui ne rappelle pas : tout ce qui arrive ici vient d'un
// controleur, d'une scene ou du cluster lui-meme (spec 6.4).
static esp_err_t rappel_attribut(attribute::callback_type_t type, uint16_t ep, uint32_t cluster, uint32_t attr,
                                 esp_matter_attr_val_t *val, void *priv) {
  (void)priv;
  if (type != attribute::POST_UPDATE || !s_ordre) return ESP_OK;
  const int lampe = lampe_de(ep);
  if (lampe < 0 || esp_timer_get_time() < s_ordres_des_us[lampe]) return ESP_OK;
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

// Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1) :
// seul le voyant fait l'arc-en-ciel, pour un autre controleur.
static esp_err_t rappel_identification(identification::callback_type_t type, uint16_t ep, uint8_t effet,
                                       uint8_t variante, void *priv) {
  (void)variante;
  (void)priv;
  const int e = emplacement_de(ep);
  if (e < 0) return ESP_OK;
  switch (type) {
    case identification::callback_type_t::START:
      s_identifie = s_identifie | (1u << e);
      break;
    case identification::callback_type_t::STOP:
      s_identifie = s_identifie & ~(1u << e);
      break;
    case identification::callback_type_t::EFFECT:
      s_effet_fin[e] = statusled::effectEnd(s_effet_fin[e], effet, (uint32_t)(esp_timer_get_time() / 1000));
      break;
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
      s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
      break;
    case DeviceEventType::kFabricCommitted:
      s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
      break;
    case DeviceEventType::kFabricRemoved: {
      // Derniere fabrique retiree depuis Maison : la fenetre de mise en service
      // se rouvre (DNS-SD, 300 s), comme la bibliotheque Arduino du Halo le faisait.
      s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
      if (s_fabriques != 0) break;
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

// --- Lampes dans Maison (spec N lampes 5 et 7)

// Le type d'appareil que donne le catalogue. Seule la lampe a intensite variable
// est realisee : un modele CCT ou couleur s'ajoutera ici, une fois verifie avec la
// vraie lampe.
static esp_err_t ajouter_type(endpoint_t *ep, const catalogue_modele_t *m) {
  switch (m->type) {
    case CATALOGUE_LAMPE_VARIABLE:
    case CATALOGUE_LAMPE_TEMPERATURE:
    case CATALOGUE_LAMPE_COULEUR:
    default: {
      endpoint::dimmable_light::config_t cfg_lampe;
      // Defauts d'esp-matter a 0 : ils eteindraient les lampes, ou les baisseraient
      // au minimum, a chaque demarrage. Nuls : rien ne change (spec 6.5).
      cfg_lampe.on_off_lighting.start_up_on_off = nullptr;
      cfg_lampe.level_control_lighting.start_up_current_level = nullptr;
      return endpoint::dimmable_light::add(ep, &cfg_lampe);
    }
  }
}

esp_err_t pont_exposer(int lampe, const liste_lampe_t *l) {
  if (lampe < 0 || lampe >= LISTE_CAPACITE || !l) return ESP_ERR_INVALID_ARG;
  if (!esp_matter::is_started() || !s_verrou_exposition) return ESP_ERR_INVALID_STATE;
  xSemaphoreTake(s_verrou_exposition, portMAX_DELAY);
  if (s_ep_lampe[lampe]) {
    xSemaphoreGive(s_verrou_exposition);
    return ESP_OK;
  }
  const catalogue_modele_t *m = catalogue_trouver(l->code);
  endpoint_t *ep = NULL;
  bool pret = false;
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    endpoint::bridged_node::config_t cfg_pontee;
    snprintf(cfg_pontee.bridged_device_basic_information.unique_id,
             sizeof(cfg_pontee.bridged_device_basic_information.unique_id), "%02X%02X%02X%02X%02X%02X", l->mac[0],
             l->mac[1], l->mac[2], l->mac[3], l->mac[4], l->mac[5]);
    // Son numero s'il en a un, deja passe par le compteur d'esp-matter (resume) ;
    // sinon, ou si ce compteur est reparti (desappairage complet), le suivant.
    const uint16_t numero = s_numero[lampe] ? s_numero[lampe] : l->endpoint;
    if (numero) ep = endpoint::bridged_node::resume(s_noeud, &cfg_pontee, ENDPOINT_FLAG_BRIDGE, numero, NULL);
    if (!ep) ep = endpoint::bridged_node::create(s_noeud, &cfg_pontee, ENDPOINT_FLAG_BRIDGE, NULL);
    if (ep) pret = ajouter_type(ep, m) == ESP_OK && endpoint::set_parent_endpoint(ep, s_agregateur) == ESP_OK;
    if (pret) {
      snprintf(s_nom_lampe[lampe], sizeof(s_nom_lampe[lampe]), "%s", l->nom);
      cluster_t *pontee = cluster::get(ep, BridgedDeviceBasicInformation::Id);
      if (pontee) {
        // Sans NONVOLATILE (create_node_label le mettrait en NVS, et ce premier nom
        // resterait) : le nom de la base prime a chaque demarrage.
        attribute::create(pontee, BridgedDeviceBasicInformation::Attributes::NodeLabel::Id,
                          ATTRIBUTE_FLAG_WRITABLE, esp_matter_char_str(s_nom_lampe[lampe], strlen(s_nom_lampe[lampe])),
                          32);
      }
      // Les etats relus changent CurrentLevel souvent : ecriture en flash differee.
      attribute::set_deferred_persistence(
          attribute::get(endpoint::get_id(ep), LevelControl::Id, LevelControl::Attributes::CurrentLevel::Id));
    }
  }
  if (!pret) {
    if (ep) endpoint::destroy(s_noeud, ep);  // prend le verrou de la pile lui-meme
    xSemaphoreGive(s_verrou_exposition);
    ESP_LOGE(TAG, "lampe %d : endpoint non cree", lampe + 1);
    return ESP_FAIL;
  }
  const uint16_t id = endpoint::get_id(ep);
  s_ordres_des_us[lampe] = esp_timer_get_time() + 2000000;
  // Prend le verrou de la pile : rappels d'init des clusters, liste des parties de
  // l'agregateur annoncee aux abonnes (Maison montre la tuile).
  endpoint::enable(ep);
  s_ep_lampe[lampe] = id;
  s_numero[lampe] = id;
  if (id != l->endpoint) {
    const esp_err_t err = config_maj_endpoint(l->mac, id);
    if (err != ESP_OK) ESP_LOGE(TAG, "lampe %d : numero EP%u non sauve (%s)", lampe + 1, id, esp_err_to_name(err));
  }
  xSemaphoreGive(s_verrou_exposition);
  ESP_LOGI(TAG, "lampe %d dans Maison : EP%u, %s", lampe + 1, id,
           catalogue_connu(l->code) ? m->nom : "modele non catalogue, intensite seule");
  return ESP_OK;
}

esp_err_t pont_masquer(int lampe) {
  if (lampe < 0 || lampe >= LISTE_CAPACITE) return ESP_ERR_INVALID_ARG;
  if (!esp_matter::is_started() || !s_verrou_exposition) return ESP_ERR_INVALID_STATE;
  xSemaphoreTake(s_verrou_exposition, portMAX_DELAY);
  const uint16_t id = s_ep_lampe[lampe];
  esp_err_t err = ESP_OK;
  if (id) {
    endpoint_t *ep;
    {
      lock::ScopedChipStackLock verrou(portMAX_DELAY);
      ep = endpoint::get(s_noeud, id);
    }
    s_ep_lampe[lampe] = 0;  // plus de publication, plus d'ordre
    s_identifie = s_identifie & ~(1u << (2 + lampe));
    s_effet_fin[2 + lampe] = 0;
    // Prend le verrou de la pile : la liste des parties change, Maison retire la tuile.
    if (ep) err = endpoint::destroy(s_noeud, ep);
    ESP_LOGI(TAG, "lampe %d retiree de Maison (EP%u)", lampe + 1, id);
  }
  xSemaphoreGive(s_verrou_exposition);
  return err;
}

uint16_t pont_endpoint(int lampe) { return lampe >= 0 && lampe < LISTE_CAPACITE ? s_ep_lampe[lampe] : 0; }

// --- API

esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre) {
  s_ordre = ordre;
  s_verrou_exposition = xSemaphoreCreateMutex();
  if (!s_verrou_exposition) return ESP_ERR_NO_MEM;
  ecrire_numero_de_serie();

  node::config_t cfg_noeud;
  snprintf(cfg_noeud.root_node.basic_information.node_label,
           sizeof(cfg_noeud.root_node.basic_information.node_label), "%s", "Pont amaran");
  // Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1).
  s_noeud = node::create(&cfg_noeud, rappel_attribut, rappel_identification);
  if (!s_noeud) return ESP_FAIL;
  // SerialNumber est facultatif : cree vide, la pile le lit dans chip-factory.
  cluster_t *infos = cluster::get(endpoint::get(s_noeud, 0), BasicInformation::Id);
  if (infos) cluster::basic_information::attribute::create_serial_number(infos, NULL, 0);

  endpoint::aggregator::config_t cfg_agregateur;
  s_agregateur = endpoint::aggregator::create(s_noeud, &cfg_agregateur, ENDPOINT_FLAG_NONE, NULL);
  if (!s_agregateur) return ESP_FAIL;

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
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    chip::app::InteractionModelEngine::GetInstance()->RegisterReadHandlerAppCallback(&s_plafond);
    s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
  }
  // Les lampes exposees, juste apres start (le compteur d'esp-matter vient d'etre
  // relu) : dans l'ordre croissant de leur numero, pour qu'apres un desappairage
  // complet (compteur reparti) les memes numeros reviennent. Sans numero : a la fin.
  int ordre_ep[LISTE_CAPACITE];
  int n = 0;
  for (int i = 0; i < cfg->liste.n; i++) {
    if (liste_exposee(&cfg->liste.lampes[i])) ordre_ep[n++] = i;
  }
  for (int a = 1; a < n; a++) {
    const int i = ordre_ep[a];
    const uint32_t cle = cfg->liste.lampes[i].endpoint ? cfg->liste.lampes[i].endpoint : UINT32_MAX;
    int b = a - 1;
    while (b >= 0) {
      const uint16_t eb = cfg->liste.lampes[ordre_ep[b]].endpoint;
      if ((eb ? eb : UINT32_MAX) <= cle) break;
      ordre_ep[b + 1] = ordre_ep[b];
      b--;
    }
    ordre_ep[b + 1] = i;
  }
  for (int k = 0; k < n; k++) pont_exposer(ordre_ep[k], &cfg->liste.lampes[ordre_ep[k]]);
  return ESP_OK;
}

void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable) {
  // Si esp_matter::start() a echoue, app_main garde la console : la pile n'existe pas, et
  // attribute::report y prendrait le verrou et marquerait des attributs. Rien a publier.
  if (lampe < 0 || lampe >= LISTE_CAPACITE || !s_ep_lampe[lampe] || !esp_matter::is_started()) return;
  const uint16_t ep = s_ep_lampe[lampe];
  esp_matter_attr_val_t v = esp_matter_bool(joignable);
  attribute::report(ep, BridgedDeviceBasicInformation::Id, BridgedDeviceBasicInformation::Attributes::Reachable::Id,
                    &v);
  if (!etat) return;
  v = esp_matter_bool(etat->marche);
  attribute::report(ep, OnOff::Id, OnOff::Attributes::OnOff::Id, &v);
  if (etat->intensite == 0) return;  // lampe noire jamais vue allumee : CurrentLevel reste celui de Matter
  uint8_t niveau = lampes_intensite_vers_niveau(etat->intensite);
  if (niveau < PONT_NIVEAU_PLANCHER) niveau = PONT_NIVEAU_PLANCHER;
  v = esp_matter_nullable_uint8(niveau);
  attribute::report(ep, LevelControl::Id, LevelControl::Attributes::CurrentLevel::Id, &v);
}

bool pont_appaire(void) { return s_fabriques > 0; }

bool pont_ble_annonce(void) { return s_ble_annonce; }

bool pont_thread_attache(void) {
  const int r = s_role;
  return r == OT_DEVICE_ROLE_CHILD || r == OT_DEVICE_ROLE_ROUTER || r == OT_DEVICE_ROLE_LEADER;
}

void pont_desappairer(void) {
  if (!esp_matter::is_started()) {
    printf("Matter non demarre : rien a desappairer\n");
    return;
  }
  esp_matter::factory_reset();
}

bool pont_identifie(void) {
  if (s_identifie) return true;
  const uint32_t t = (uint32_t)(esp_timer_get_time() / 1000);
  for (int e = 0; e < EMPLACEMENTS; e++) {
    if (statusled::effectPending(s_effet_fin[e], t)) return true;
  }
  return false;
}

void pont_afficher(void) {
  if (!esp_matter::is_started()) {  // sans la pile, ses fournisseurs n'existent pas (VerifyOrDie)
    printf("Matter non demarre (voir le journal de demarrage)\n");
    return;
  }
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
  for (int i = 0; i < LISTE_CAPACITE; i++) {
    if (s_ep_lampe[i]) printf("  EP%u             : %s\n", (unsigned)s_ep_lampe[i], s_nom_lampe[i]);
  }
}
````

- [ ] **Step 3 : `tache_lampes.h`.**

`firmware/main/tache_lampes.h` (contenu complet) :

````c
// Tache du coeur du pont (spec 4.3) : la seule qui touche l'etat des lampes.
// Elle recoit les ordres (Matter, console) et les evenements du crochet, fait
// tourner lampes_tic() toutes les 50 ms, et fait entrer dans Maison une lampe
// jamais vue a sa premiere reponse (spec N lampes 7).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "lampes.h"
#include "liste.h"

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
// Copie de la liste du demarrage, drapeaux a jour (vue, masquee).
void tache_lampes_lire_liste(liste_t *copie);
// Retire la lampe de Maison (afficher faux), ou l'y remet (vrai, meme jamais vue) ;
// le choix est sauve en NVS. Depuis la console (pas la tache CHIP).
esp_err_t tache_lampes_exposition(int lampe, bool afficher);
// Ecoute detaillee : imprimer aussi chaque etat recu des lampes.
void tache_lampes_ecoute(bool oui);
// Ordres confirmes et abandonnes depuis le demarrage (ne font que croitre).
uint32_t tache_lampes_confirmes(void);
uint32_t tache_lampes_abandons(void);

#ifdef __cplusplus
}
#endif
````

- [ ] **Step 4 : `tache_lampes.c`.**

`firmware/main/tache_lampes.c`, bloc 1 sur 5. Remplacer :

````c

static QueueHandle_t s_file;
static SemaphoreHandle_t s_verrou;  // s_lampes, lu en copie par la console
static lampes_t s_lampes;
static volatile bool s_ecoute;
static volatile uint32_t s_confirmes, s_abandons;
````

par :

````c

static QueueHandle_t s_file;
static SemaphoreHandle_t s_verrou;  // s_lampes et s_liste, lus en copie par la console
static lampes_t s_lampes;
static liste_t s_liste;             // liste du demarrage ; drapeaux tenus a jour
static volatile bool s_ecoute;
static volatile uint32_t s_confirmes, s_abandons;
````

`firmware/main/tache_lampes.c`, bloc 2 sur 5. Remplacer :

````c
  } else {
    s_abandons++;
  }
}
````

par :

````c
  } else {
    s_abandons++;
  }
}

// Relectures manquees (spec N lampes 8) : une ligne a l'entree, une a la sortie.
static void sortie_alerter(void *ctx, int lampe, bool manque, uint8_t pour_cent) {
  (void)ctx;
  if (manque) {
    printf("!! lampe %d : relectures manquees (%u %% sur 10 min) : allonger la periode (mesh releve)\n", lampe + 1,
           (unsigned)pour_cent);
  } else {
    printf("[lampes] lampe %d : relectures de nouveau a %u %% sur 10 min\n", lampe + 1, (unsigned)pour_cent);
  }
}

// Lampe i : la faire entrer dans Maison, puis y publier son etat (son endpoint est
// neuf). Sous s_verrou.
static esp_err_t exposer(int i) {
  const esp_err_t err = pont_exposer(i, &s_liste.lampes[i]);
  if (err == ESP_OK) {
    s_liste.lampes[i].endpoint = pont_endpoint(i);
    lampes_forcer_publication(&s_lampes, i);
  }
  return err;
}

// Premiere reponse d'une lampe jamais vue : elle entre dans Maison (spec N lampes 7).
// Marquee vue d'abord : si l'endpoint echoue, le prochain demarrage la remettra.
static void exposer_les_nouvelles(void) {
  for (int i = 0; i < s_lampes.n; i++) {
    liste_lampe_t *a = &s_liste.lampes[i];
    if (!s_lampes.lampes[i].entendue || !liste_a_exposer_a_l_ecoute(a)) continue;
    liste_marquer_vue(a);
    if (config_maj_drapeaux(a->mac, a->drapeaux) != ESP_OK) printf("!! lampe %d : vue, mais NVS non mise a jour\n", i + 1);
    if (exposer(i) == ESP_OK) {
      printf("[lampes] lampe %d entendue : dans Maison (EP%u)\n", i + 1, (unsigned)pont_endpoint(i));
    } else {
      printf("!! lampe %d entendue, mais pas dans Maison (endpoint Matter)\n", i + 1);
    }
  }
}
````

`firmware/main/tache_lampes.c`, bloc 3 sur 5. Remplacer :

````c
    }
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    lampes_mesh_pret(&s_lampes, mesh_pret(), maintenant_ms());
    lampes_tic(&s_lampes, maintenant_ms());
````

par :

````c
    }
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    exposer_les_nouvelles();
    lampes_mesh_pret(&s_lampes, mesh_pret(), maintenant_ms());
    lampes_tic(&s_lampes, maintenant_ms());
````

`firmware/main/tache_lampes.c`, bloc 4 sur 5. Remplacer :

````c
  s_verrou = xSemaphoreCreateMutex();
  if (!s_file || !s_verrou) return ESP_ERR_NO_MEM;
  uint16_t adresses[LAMPES_CAPACITE];
  for (int i = 0; i < cfg->liste.n; i++) adresses[i] = cfg->liste.lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, NULL, NULL};
  lampes_init(&s_lampes, adresses, cfg->liste.n, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
  return xTaskCreate(tache, "lampes", 4096, NULL, 4, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}

````

par :

````c
  s_verrou = xSemaphoreCreateMutex();
  if (!s_file || !s_verrou) return ESP_ERR_NO_MEM;
  _Static_assert(LAMPES_CAPACITE == LISTE_CAPACITE, "une lampe de la liste par lampe du coeur");
  s_liste = cfg->liste;
  uint16_t adresses[LAMPES_CAPACITE];
  for (int i = 0; i < s_liste.n; i++) adresses[i] = s_liste.lampes[i].adresse;
  const lampes_sorties_t sorties = {sortie_envoyer, sortie_publier, sortie_signaler, sortie_alerter, NULL};
  lampes_init(&s_lampes, adresses, s_liste.n, &sorties, maintenant_ms());
  if (cfg->releve_ms) lampes_regler_releve(&s_lampes, cfg->releve_ms);
  // 6 Ko : exposer une lampe (pont_exposer) fait tourner ici les rappels d'init des
  // clusters Matter (endpoint::enable), sur cette pile.
  return xTaskCreate(tache, "lampes", 6144, NULL, 4, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}

````

`firmware/main/tache_lampes.c`, bloc 5 sur 5. Remplacer :

````c
}

void tache_lampes_ecoute(bool oui) { s_ecoute = oui; }

````

par :

````c
}

void tache_lampes_lire_liste(liste_t *copie) {
  if (!s_verrou) {
    memset(copie, 0, sizeof(*copie));
    return;
  }
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  *copie = s_liste;
  xSemaphoreGive(s_verrou);
}

esp_err_t tache_lampes_exposition(int lampe, bool afficher) {
  if (!s_verrou || lampe < 0 || lampe >= s_liste.n) return ESP_ERR_INVALID_ARG;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  liste_lampe_t *a = &s_liste.lampes[lampe];
  if (afficher) {
    liste_afficher(a);
  } else {
    liste_masquer(a);
  }
  // Une liste chargee depuis le demarrage sans cette lampe : ESP_ERR_NOT_FOUND.
  esp_err_t err = config_maj_drapeaux(a->mac, a->drapeaux);
  if (err == ESP_OK) err = afficher ? exposer(lampe) : pont_masquer(lampe);
  xSemaphoreGive(s_verrou);
  return err;
}

void tache_lampes_ecoute(bool oui) { s_ecoute = oui; }

````

- [ ] **Step 5 : `console_pont.c`.**

`firmware/main/console_pont.c` (contenu complet) :

````c
// Console du pont (spec 7.5 ; spec N lampes 10) : lampes, lampe, mesh (et mesh
// releve, mesh lampe <n> masquer|afficher), matter, decommission, redemarre,
// taches. Les cles ne s'affichent jamais (7.7).
#include "console_pont.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_console.h"
#include "esp_timer.h"

#include "catalogue.h"
#include "lampes.h"
#include "liste.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "telink.h"
#include "texte.h"

static amaran_config_t *s_cfg;
// Copies : trop grosses pour la pile de la console. Une commande a la fois (REPL).
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
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
````

- [ ] **Step 6 : 18 endpoints dynamiques.**

`firmware/sdkconfig.defaults`, bloc 1 sur 1. Remplacer :

````text
CONFIG_ENABLE_OTA_REQUESTOR=n
CONFIG_SUPPORT_GROUPCAST_CLUSTER=n
CONFIG_MBEDTLS_HKDF_C=y

````

par :

````text
CONFIG_ENABLE_OTA_REQUESTOR=n
CONFIG_SUPPORT_GROUPCAST_CLUSTER=n
# Endpoints dynamiques : noeud (EP0), agregateur (EP1) et 16 lampes (LISTE_CAPACITE,
# plan 3a). Un pont deja compile garde l'ancienne valeur : supprimer firmware/sdkconfig.
CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT=18
CONFIG_MBEDTLS_HKDF_C=y

````

- [ ] **Step 7 : compiler, `sdkconfig` régénéré.**

Run: `/usr/bin/grep -rn "PONT_EMPLACEMENTS" firmware/main` : rien.

Run: `rm -f firmware/sdkconfig && export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py build 2>&1 | tail -3) && /usr/bin/grep -n "MAX_DYNAMIC_ENDPOINT_COUNT" firmware/sdkconfig`
Expected : `Project build complete.` ; `CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT=18` ; image d'environ 1,7 Mo (57 % de la partition libre au prototype). Le `sdkconfig` changé fait recompiler presque tout : plusieurs minutes.

Run: `sh tests/hote/lancer.sh` : `tests hote : tout est vert`.

- [ ] **Step 8 : commit.**

```bash
git add firmware/main firmware/sdkconfig.defaults
git commit -m "$(printf "Exposer chaque lampe dans Maison a sa premiere reponse, avec un numero d'endpoint stable ; masquer et afficher\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---
### Task 5: L'outil des clés à N lampes : code du modèle, `mesh lampes`, composition, lampes fictives

**Files:**
- Modify: `outils/cles_amaran.py`, `outils/test_cles_amaran.py`

**Interfaces:**
- Consumes : le protocole de la Task 3 (réponses `ok liste de N lampe(s) ...`, `ok lampe <n> 0x<adresse> modele <code> <nom du modèle> [<capacités>] : <nom>`, `; liste de N lampe(s) enregistree`, `erreur ...`).
- Produces : `CAPACITE` (16), `modeles_sig(composition)`, `capacites_declarees(composition)`, `lire_code(code)`, `ajouter_fictives(r, n)`, `verifier_lampes(reponses, r, sortie)`, option `--fictives N`.

Pourquoi : la spec N lampes, section 10, et les bancs 3 et 4 (Task 7). L'outil ne connaît pas le catalogue. Il compare ce que la lampe déclare dans sa composition (Light CTL `0x1303`, Light HSL `0x1307`) à ce que le pont annonce. La dernière réponse doit dire la liste enregistrée, sinon pas de redémarrage. Seul Claude lance l'outil sur la vraie base.

- [ ] **Step 1 : les tests.**

`outils/test_cles_amaran.py`, bloc 1 sur 6. Remplacer :

````python
NET = "00112233445566778899aabbccddeeff"
APP = "ffeeddccbbaa99887766554433221100"
LAMPES = ((4, "70:3e:97:00:00:02", "Lampe B"), (2, "70:3E:97:00:00:01", "Lampe A"))


def base_factice(dossier, lampes=LAMPES, reseaux=1, net=NET.upper()):
    chemin = os.path.join(dossier, "amaran.db")
    con = sqlite3.connect(chemin)
    con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
    con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
    for i in range(reseaux):
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m%d" % i, net, APP.upper()))
    for adresse, mac, nom in lampes:
        con.execute("insert into fixtures values (?, ?, ?, ?, ?)", ("f%d" % adresse, mac, nom, adresse, "00" * 16))
    con.commit()
    con.close()
````

par :

````python
NET = "00112233445566778899aabbccddeeff"
APP = "ffeeddccbbaa99887766554433221100"
# Composition d'une COB 60d (base du 03/10/2026) : Generic OnOff, Light Lightness, ni CTL ni HSL.
COMPO_60D = "0011020102333369000A0000000A01000002000300001002100410061007100013011311020000"
# La meme, avec Light CTL Server (0x1303) a la place de Light Lightness Setup : un modele bi-color.
COMPO_CTL = "0011020102333369000A0000000A01000002000300001002100410061007100013031311020000"
LAMPES = ((4, "70:3e:97:00:00:02", "Lampe B"), (2, "70:3E:97:00:00:01", "Lampe A"))


def base_factice(dossier, lampes=LAMPES, reseaux=1, net=NET.upper(), code="40065", compo=COMPO_60D):
    chemin = os.path.join(dossier, "amaran.db")
    con = sqlite3.connect(chemin)
    con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
    con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, "
                "device_key text, code text, composition_data text)")
    for i in range(reseaux):
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m%d" % i, net, APP.upper()))
    for adresse, mac, nom in lampes:
        con.execute("insert into fixtures values (?, ?, ?, ?, ?, ?, ?)",
                    ("f%d" % adresse, mac, nom, adresse, "00" * 16, code, compo))
    con.commit()
    con.close()
````

`outils/test_cles_amaran.py`, bloc 2 sur 6. Remplacer :

````python
            ca.lire_reseau(base_factice(self.dossier, reseaux=2))

    def test_refuse_trois_lampes(self):
        trois = LAMPES + ((6, "70:3E:97:00:00:03", "Lampe C"),)
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, lampes=trois))

    def test_refuse_base_sans_lampe(self):
````

par :

````python
            ca.lire_reseau(base_factice(self.dossier, reseaux=2))

    def test_accepte_trois_lampes(self):
        trois = LAMPES + ((6, "70:3E:97:00:00:03", "Lampe C"),)
        r = ca.lire_reseau(base_factice(self.dossier, lampes=trois))
        self.assertEqual([l["adresse"] for l in r["lampes"]], [2, 4, 6])

    def test_refuse_au_dela_de_la_capacite(self):
        trop = tuple((2 * k + 2, "70:3E:97:00:00:%02X" % k, "Lampe %d" % k) for k in range(ca.CAPACITE + 1))
        with self.assertRaises(ca.ErreurCles) as cm:
            ca.lire_reseau(base_factice(self.dossier, lampes=trop))
        self.assertIn("le pont en gere %d" % ca.CAPACITE, str(cm.exception))

    def test_code_et_capacites_lus(self):
        r = ca.lire_reseau(base_factice(self.dossier))
        self.assertEqual(r["lampes"][0]["code"], 40065)
        self.assertEqual(r["lampes"][0]["declare"], set())
        r = ca.lire_reseau(base_factice(tempfile.mkdtemp(), code="x1", compo=COMPO_CTL))
        self.assertEqual(r["lampes"][0]["code"], 0)
        self.assertEqual(r["lampes"][0]["declare"], {"cct"})

    def test_base_sans_code_ni_composition(self):
        chemin = os.path.join(self.dossier, "amaran.db")
        con = sqlite3.connect(chemin)
        con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
        con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer)")
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m0", NET.upper(), APP.upper()))
        con.execute("insert into fixtures values (?, ?, ?, ?)", ("f1", "70:3E:97:00:00:01", "Lampe", 2))
        con.commit()
        con.close()
        r = ca.lire_reseau(chemin)
        self.assertEqual((r["lampes"][0]["code"], r["lampes"][0]["declare"]), (0, set()))

    def test_refuse_base_sans_lampe(self):
````

`outils/test_cles_amaran.py`, bloc 3 sur 6. Remplacer :

````python
        self.assertEqual(ca.commandes(r), [
            "mesh cles %s %s" % (NET.upper(), APP.upper()),
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 Lampe B",
        ])


````

par :

````python
        self.assertEqual(ca.commandes(r), [
            "mesh cles %s %s" % (NET.upper(), APP.upper()),
            "mesh lampes 2",
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 40065 Lampe A",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 40065 Lampe B",
        ])


class TestFictives(unittest.TestCase):
    def test_fictives_apres_les_vraies(self):
        r = ca.ajouter_fictives(ca.lire_reseau(base_factice(tempfile.mkdtemp())), 2)
        self.assertEqual([l["nom"] for l in r["lampes"]], ["Lampe A", "Lampe B", "Fictive 1", "Fictive 2"])
        self.assertEqual([l["adresse"] for l in r["lampes"][2:]], [0x0100, 0x0101])
        self.assertEqual(ca.commandes(r)[1], "mesh lampes 4")
        self.assertEqual(ca.commandes(r)[-1], "mesh lampe 4 0x0101 02:00:00:00:00:02 0 Fictive 2")

    def test_fictives_sautent_une_adresse_prise(self):
        lampes = ((0x0100, "70:3E:97:00:00:01", "Lampe A"),)
        r = ca.ajouter_fictives(ca.lire_reseau(base_factice(tempfile.mkdtemp(), lampes=lampes)), 1)
        self.assertEqual(r["lampes"][1]["adresse"], 0x0101)

    def test_fictives_au_dela_de_la_capacite(self):
        with self.assertRaises(ca.ErreurCles):
            ca.ajouter_fictives(ca.lire_reseau(base_factice(tempfile.mkdtemp())), ca.CAPACITE - 1)


class TestComposition(unittest.TestCase):
    def test_modeles_de_la_60d(self):
        self.assertEqual(ca.modeles_sig(COMPO_60D),
                         {0x0000, 0x0002, 0x0003, 0x1000, 0x1002, 0x1004, 0x1006, 0x1007, 0x1300, 0x1301})
        self.assertEqual(ca.capacites_declarees(COMPO_60D), set())

    def test_ctl_et_hsl(self):
        self.assertEqual(ca.capacites_declarees(COMPO_CTL), {"cct"})
        hsl = COMPO_60D.replace("00130113", "00130713")  # Light HSL Server a la place de Lightness Setup
        self.assertEqual(ca.capacites_declarees(hsl), {"couleur"})

    def test_composition_illisible(self):
        for compo in (None, "", "zz", "0011", COMPO_60D[:-10]):
            self.assertEqual(ca.modeles_sig(compo), set(), compo)


````

`outils/test_cles_amaran.py`, bloc 4 sur 6. Remplacer :

````python
        self.capture = []

    def reponses(self, ok_cles="ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
                 fin=("redemarre", "redemarrage")):
        """Ce que dit le pont : etat (reponse a `mesh`), puis un `ok` par ligne, puis le redemarrage."""
        return ["mesh", "mesh pret : oui", "cles : reseau A8FAED6A, application 811407F1", "amaran>",
                self.cles, ok_cles,
                "ok lampe 1 0x0002 Lampe A (redemarrer pour l'appliquer)",
                "ok lampe 2 0x0004 Lampe B (redemarrer pour l'appliquer)"] + list(fin)

    def charger(self, port, attente=1):
````

par :

````python
        self.capture = []

    LAMPE_1 = "ok lampe 1 0x0002 modele 40065 amaran COB 60d [intensite] : Lampe A"
    LAMPE_2 = ("ok lampe 2 0x0004 modele 40065 amaran COB 60d [intensite] : Lampe B ; liste de 2 lampe(s) "
               "enregistree (redemarrer pour l'appliquer)")

    def reponses(self, ok_cles="ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
                 lampe_2=LAMPE_2, fin=("redemarre", "redemarrage")):
        """Ce que dit le pont : etat (reponse a `mesh`), puis un `ok` par ligne, puis le redemarrage."""
        return ["mesh", "mesh pret : oui", "cles : reseau A8FAED6A, application 811407F1", "amaran>",
                self.cles, ok_cles,
                "ok liste de 2 lampe(s) : envoyer mesh lampe 1 a 2",
                self.LAMPE_1, lampe_2] + list(fin)

    def charger(self, port, attente=1):
````

`outils/test_cles_amaran.py`, bloc 5 sur 6. Remplacer :

````python
            "mesh\r\n",  # d'abord verifier le pont
            self.cles + "\r\n",
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A\r\n",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 Lampe B\r\n",
            "redemarre\r\n",
        ])
        self.assertIn("empreintes du pont identiques aux notres", self.capture)
        self.assertEqual(self.capture[-1], "pont redemarre avec les nouvelles cles")
````

par :

````python
            "mesh\r\n",  # d'abord verifier le pont
            self.cles + "\r\n",
            "mesh lampes 2\r\n",
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 40065 Lampe A\r\n",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 40065 Lampe B\r\n",
            "redemarre\r\n",
        ])
        self.assertFalse(any("cataloguer" in ligne for ligne in self.capture))
        self.assertIn("empreintes du pont identiques aux notres", self.capture)
        self.assertEqual(self.capture[-1], "pont redemarre avec les nouvelles cles")
````

`outils/test_cles_amaran.py`, bloc 6 sur 6. Remplacer :

````python
        self.assertIn("inattendue", str(cm.exception))
        self.assertEqual(port.ecrit, ["mesh\r\n", self.cles + "\r\n"])

    def test_redemarrage_non_confirme_avertit(self):
````

par :

````python
        self.assertIn("inattendue", str(cm.exception))
        self.assertEqual(port.ecrit, ["mesh\r\n", self.cles + "\r\n"])

    def test_liste_non_enregistree_arrete_tout(self):
        port = PortFactice(self.reponses(lampe_2="ok lampe 2 0x0004 modele 40065 amaran COB 60d [intensite] : Lampe B"))
        with self.assertRaises(ca.ErreurCles) as cm:
            self.charger(port, attente=0.3)
        self.assertIn("pas enregistre la liste", str(cm.exception))
        self.assertNotIn("redemarre\r\n", port.ecrit)

    def test_liste_refusee_par_le_pont_arrete_tout(self):
        port = PortFactice(self.reponses(lampe_2="erreur : liste refusee (lampe 2 : MAC deja prise par une autre lampe)"))
        with self.assertRaises(ca.ErreurCles) as cm:
            self.charger(port)
        self.assertIn("liste refusee", str(cm.exception))
        self.assertNotIn("redemarre\r\n", port.ecrit)

    def test_modele_a_cataloguer_signale(self):
        self.r = ca.lire_reseau(base_factice(tempfile.mkdtemp(), compo=COMPO_CTL))
        port = PortFactice(self.reponses())
        self.charger(port)
        signales = [ligne for ligne in self.capture if ligne.startswith("modele a cataloguer")]
        self.assertEqual(len(signales), 2)  # les deux lampes declarent CTL
        self.assertIn("temperature de couleur", signales[0])
        self.assertEqual(port.ecrit[-1], "redemarre\r\n")  # sans gravite : le chargement va au bout

    def test_capacite_connue_du_pont_pas_signalee(self):
        self.r = ca.lire_reseau(base_factice(tempfile.mkdtemp(), compo=COMPO_CTL))
        port = PortFactice(self.reponses())
        port.reponses = [ligne.replace("[intensite]", "[intensite+cct]") for ligne in port.reponses]
        self.charger(port)
        self.assertFalse(any(ligne.startswith("modele a cataloguer") for ligne in self.capture))

    def test_redemarrage_non_confirme_avertit(self):
````

- [ ] **Step 2 : les lancer, pour les voir échouer.**

Run: `python3 -m unittest discover -s outils -p "test_*.py" 2>&1 | tail -1`
Expected : `FAILED (failures=5, errors=10)`.

- [ ] **Step 3 : l'outil.**

`outils/cles_amaran.py`, bloc 1 sur 10. Remplacer :

````python
Lit la base locale d'amaran Desktop, puis envoie par la console du pont :
    mesh cles <reseau> <application>
    mesh lampe <n> <adresse> <mac> <nom>
    redemarre

````

par :

````python
Lit la base locale d'amaran Desktop, puis envoie par la console du pont :
    mesh cles <reseau> <application>
    mesh lampes <N>
    mesh lampe <n> <adresse> <mac> <code> <nom>     (une ligne par lampe)
    redemarre

````

`outils/cles_amaran.py`, bloc 2 sur 10. Remplacer :

````python
    - apres `mesh cles`, les empreintes rendues par le pont doivent etre les
      notres (sinon erreur, et pas de redemarrage) ;
    - apres `redemarre`, le pont doit ecrire `redemarrage` (sinon avertissement).

    python outils/cles_amaran.py                    # montre ce qui serait envoye
    python outils/cles_amaran.py --port /dev/cu.usbmodem1101
"""
import argparse
````

par :

````python
    - apres `mesh cles`, les empreintes rendues par le pont doivent etre les
      notres (sinon erreur, et pas de redemarrage) ;
    - la derniere lampe envoyee, le pont doit dire la liste enregistree (sinon
      erreur, et pas de redemarrage) ;
    - apres `redemarre`, le pont doit ecrire `redemarrage` (sinon avertissement).

Le pont annonce le modele et les capacites de chaque lampe d'apres son
catalogue. Une lampe qui declare la temperature de couleur (Light CTL) ou la
couleur (Light HSL) dans sa composition, sans que le pont lui connaisse ces
capacites, est signalee : modele a cataloguer (marche et intensite seulement).

    python outils/cles_amaran.py                    # montre ce qui serait envoye
    python outils/cles_amaran.py --port /dev/cu.usbmodem1101
    python outils/cles_amaran.py --port ... --fictives 3   # banc : 3 lampes fictives en plus
"""
import argparse
````

`outils/cles_amaran.py`, bloc 3 sur 10. Remplacer :

````python
    "~/Library/Application Support/amaran Desktop/*/amaran.db",
)
LAMPES_MAX = 2
INVITE = "amaran>"
# Reponse du pont a `mesh cles` : ok cles <EMPREINTE RESEAU> <EMPREINTE APPLICATION> (...)
REPONSE_CLES = re.compile(r"ok cles ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8})(?:\s|$)")


````

par :

````python
    "~/Library/Application Support/amaran Desktop/*/amaran.db",
)
CAPACITE = 16  # LISTE_CAPACITE du pont : il refuse lui-meme une liste plus longue
INVITE = "amaran>"
# Reponse du pont a `mesh cles` : ok cles <EMPREINTE RESEAU> <EMPREINTE APPLICATION> (...)
REPONSE_CLES = re.compile(r"ok cles ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8})(?:\s|$)")
# Reponse a `mesh lampe` : ok lampe <n> 0x<adresse> modele <code> <nom du modele> [<capacites>] : <nom>,
# et, pour la derniere, " ; liste de <N> lampe(s) enregistree (...)".
REPONSE_LAMPE = re.compile(r"ok lampe (\d+) 0x[0-9A-Fa-f]{4} modele (\d+) (.+?) \[([a-z+]*)\] : (.*?)"
                           r"(?: ; liste de (\d+) lampe\(s\) enregistree.*)?$")
# Modeles SIG serveurs qui disent une capacite dans la composition d'une lampe.
MODELE_CTL = 0x1303  # Light CTL Server : temperature de couleur
MODELE_HSL = 0x1307  # Light HSL Server : couleur


````

`outils/cles_amaran.py`, bloc 4 sur 10. Remplacer :

````python


def lire_reseau(chemin):
    """Cles et lampes de la base, ouverte en lecture seule."""
````

par :

````python


def modeles_sig(composition):
    """Modeles SIG declares par une lampe (composition_data, page 0, en hexa) ; vide si illisible.

    Page 0 : numero de page, CID, PID, VID, CRPL, fonctions (2 octets chacun),
    puis chaque element : emplacement (2), nombre de modeles SIG (1) et vendeur
    (1), les modeles SIG (2 octets) et vendeur (4 octets).
    """
    try:
        d = bytes.fromhex(composition or "")
    except ValueError:
        return set()
    modeles = set()
    i = 11  # page, puis 5 champs de 2 octets
    while i + 4 <= len(d):
        nb_sig, nb_vendeur = d[i + 2], d[i + 3]
        i += 4
        if i + 2 * nb_sig + 4 * nb_vendeur > len(d):
            return set()
        for k in range(nb_sig):
            modeles.add(d[i + 2 * k] | (d[i + 2 * k + 1] << 8))
        i += 2 * nb_sig + 4 * nb_vendeur
    return modeles


def capacites_declarees(composition):
    """Capacites au-dela de l'intensite que la lampe declare : {"cct", "couleur"}."""
    m = modeles_sig(composition)
    return ({"cct"} if MODELE_CTL in m else set()) | ({"couleur"} if MODELE_HSL in m else set())


def lire_code(code):
    """Code produit Sidus (colonne `code`, texte) ; 0 s'il manque ou n'est pas un nombre."""
    texte = str(code).strip() if code is not None else ""
    return int(texte) if texte.isdigit() and int(texte) < 2 ** 32 else 0


def lire_reseau(chemin):
    """Cles et lampes de la base, ouverte en lecture seule."""
````

`outils/cles_amaran.py`, bloc 5 sur 10. Remplacer :

````python
            reseaux = con.execute(
                "select net_key, app_key from mesh where net_key is not null and app_key is not null").fetchall()
            lignes = con.execute(
                "select node_address, mac_address, name from fixtures "
                "where node_address is not null order by node_address").fetchall()
        finally:
            con.close()
````

par :

````python
            reseaux = con.execute(
                "select net_key, app_key from mesh where net_key is not null and app_key is not null").fetchall()
            # `code` et `composition_data` : absentes d'une base plus ancienne, sans gravite.
            colonnes = {c[1] for c in con.execute("pragma table_info(fixtures)")}
            extra = ", ".join(c if c in colonnes else "null" for c in ("code", "composition_data"))
            lignes = con.execute(
                "select node_address, mac_address, name, %s from fixtures "
                "where node_address is not null order by node_address" % extra).fetchall()
        finally:
            con.close()
````

`outils/cles_amaran.py`, bloc 6 sur 10. Remplacer :

````python
    if not lignes:
        raise ErreurCles("aucune lampe dans la base")
    if len(lignes) > LAMPES_MAX:
        raise ErreurCles("%d lampes, le pont en gere %d" % (len(lignes), LAMPES_MAX))
    lampes = []
    for adresse, mac, nom in lignes:
        try:
            # Valider l'adresse : int, 1..0x7FFF
````

par :

````python
    if not lignes:
        raise ErreurCles("aucune lampe dans la base")
    if len(lignes) > CAPACITE:
        raise ErreurCles("%d lampes, le pont en gere %d" % (len(lignes), CAPACITE))
    lampes = []
    for adresse, mac, nom, code, composition in lignes:
        try:
            # Valider l'adresse : int, 1..0x7FFF
````

`outils/cles_amaran.py`, bloc 7 sur 10. Remplacer :

````python
        except (AttributeError, TypeError):
            raise ErreurCles("lampe illisible dans la base (adresse %r)" % (adresse,))
        lampes.append({"adresse": adresse, "mac": mac.upper(), "nom": nom})
    return {"reseau": reseau, "application": application, "lampes": lampes}

````

par :

````python
        except (AttributeError, TypeError):
            raise ErreurCles("lampe illisible dans la base (adresse %r)" % (adresse,))
        lampes.append({"adresse": adresse, "mac": mac.upper(), "nom": nom, "code": lire_code(code),
                       "declare": capacites_declarees(composition)})
    return {"reseau": reseau, "application": application, "lampes": lampes}

````

`outils/cles_amaran.py`, bloc 8 sur 10. Remplacer :

````python
    lignes = ["cles : reseau %s, application %s" % (empreinte(r["reseau"]), empreinte(r["application"]))]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("lampe %d : 0x%04X %s (%s)" % (i, l["adresse"], l["nom"], l["mac"]))
    return lignes


def commandes(r):
    lignes = ["mesh cles %s %s" % (r["reseau"].hex().upper(), r["application"].hex().upper())]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("mesh lampe %d 0x%04X %s %s" % (i, l["adresse"], l["mac"], l["nom"]))
    return lignes


````

par :

````python
    lignes = ["cles : reseau %s, application %s" % (empreinte(r["reseau"]), empreinte(r["application"]))]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("lampe %d : 0x%04X %s (%s), modele %s" % (i, l["adresse"], l["nom"], l["mac"],
                                                             l["code"] or "inconnu"))
    return lignes


def commandes(r):
    """`mesh cles`, `mesh lampes <N>`, puis une ligne par lampe : le code avant le nom."""
    lignes = ["mesh cles %s %s" % (r["reseau"].hex().upper(), r["application"].hex().upper()),
              "mesh lampes %d" % len(r["lampes"])]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("mesh lampe %d 0x%04X %s %d %s" % (i, l["adresse"], l["mac"], l["code"], l["nom"]))
    return lignes


def ajouter_fictives(r, n):
    """Banc de capacite (plan 3a) : n lampes fictives apres les vraies, qui ne repondront jamais.

    Adresses a partir de 0x0100 (sautant celles des vraies lampes), MAC
    administrees localement (02:00:00:00:00:kk), code 0 (modele non catalogue).
    """
    if n < 0 or len(r["lampes"]) + n > CAPACITE:
        raise ErreurCles("%d lampes et %d fictives : le pont en gere %d" % (len(r["lampes"]), n, CAPACITE))
    prises = {l["adresse"] for l in r["lampes"]}
    adresse = 0x0100
    for k in range(1, n + 1):
        while adresse in prises:
            adresse += 1
        r["lampes"].append({"adresse": adresse, "mac": "02:00:00:00:00:%02X" % k, "nom": "Fictive %d" % k,
                            "code": 0, "declare": set()})
        prises.add(adresse)
    return r


def verifier_lampes(reponses, r, sortie=print):
    """Lit les reponses aux lignes `mesh lampe` : modeles a cataloguer, et liste enregistree.

    Les reponses sont celles des lampes, dans l'ordre. Leve ErreurCles si la
    derniere ne dit pas la liste enregistree.
    """
    for i, (reponse, l) in enumerate(zip(reponses, r["lampes"]), 1):
        m = REPONSE_LAMPE.match(reponse)
        if not m or int(m.group(1)) != i:
            raise ErreurCles("reponse inattendue du pont a mesh lampe %d : %s" % (i, reponse))
        connues = set(m.group(4).split("+"))
        for capacite, modele in (("cct", "temperature de couleur (Light CTL)"), ("couleur", "couleur (Light HSL)")):
            if capacite in l["declare"] and capacite not in connues:
                sortie("modele a cataloguer : lampe %d (%s, code %s) declare la %s, que le pont ne lui connait "
                       "pas : marche et intensite seulement" % (i, l["nom"], l["code"] or "inconnu", modele))
    dernier = REPONSE_LAMPE.match(reponses[-1]) if reponses else None
    if not dernier or dernier.group(6) is None or int(dernier.group(6)) != len(r["lampes"]):
        raise ErreurCles("le pont n'a pas enregistre la liste des lampes : ne pas le redemarrer, relancer l'outil")


````

`outils/cles_amaran.py`, bloc 9 sur 10. Remplacer :

````python
    """Charge les cles et les lampes de r dans le pont, puis le redemarre."""
    verifier_pont(port, attente)
    cles, *lampes = commandes(r)  # `mesh cles` d'abord, puis une ligne par lampe
    verifier_empreintes(envoyer(port, [cles], attente=attente, sortie=sortie)[0], r)
    sortie("empreintes du pont identiques aux notres")
    envoyer(port, lampes, attente=attente, sortie=sortie)
    port.write(b"redemarre\r\n")
    if attendre_redemarrage(port, attente):
````

par :

````python
    """Charge les cles et les lampes de r dans le pont, puis le redemarre."""
    verifier_pont(port, attente)
    cles, liste, *lampes = commandes(r)  # `mesh cles`, `mesh lampes <N>`, puis une ligne par lampe
    verifier_empreintes(envoyer(port, [cles], attente=attente, sortie=sortie)[0], r)
    sortie("empreintes du pont identiques aux notres")
    envoyer(port, [liste], attente=attente, sortie=sortie)
    verifier_lampes(envoyer(port, lampes, attente=attente, sortie=sortie), r, sortie=sortie)
    port.write(b"redemarre\r\n")
    if attendre_redemarrage(port, attente):
````

`outils/cles_amaran.py`, bloc 10 sur 10. Remplacer :

````python
    ap.add_argument("--db", help="base d'amaran Desktop (sinon : la plus recente)")
    ap.add_argument("--port", help="port serie du pont ; sans lui, rien n'est envoye")
    args = ap.parse_args(argv)
    try:
        r = lire_reseau(args.db or trouver_base())
        for ligne in resume(r):
            sortie(ligne)
````

par :

````python
    ap.add_argument("--db", help="base d'amaran Desktop (sinon : la plus recente)")
    ap.add_argument("--port", help="port serie du pont ; sans lui, rien n'est envoye")
    ap.add_argument("--fictives", type=int, default=0,
                    help="banc de capacite : N lampes fictives en plus, qui ne repondront jamais")
    args = ap.parse_args(argv)
    try:
        r = ajouter_fictives(lire_reseau(args.db or trouver_base()), args.fictives)
        for ligne in resume(r):
            sortie(ligne)
````

- [ ] **Step 4 : les tests passent.**

Run: `python3 -m unittest discover -s outils -p "test_*.py" 2>&1 | tail -3`
Expected : `Ran 62 tests`, `OK`.

Les tests suffisent : un sous-agent ne lance jamais l'outil sur la vraie base d'amaran Desktop (contrainte globale).

- [ ] **Step 5 : commit.**

```bash
git add outils/cles_amaran.py outils/test_cles_amaran.py
git commit -m "$(printf "Outil des cles : jusqu'a 16 lampes, code du modele, liste tout ou rien, lampes fictives de banc\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---
### Task 6: La documentation : README et spec du pont

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-09-28-pont-amaran-design.md`

**Interfaces:** aucune.

Pourquoi : dire comment se servir du pont à N lampes, et renvoyer la spec du pont vers celle du plan 3a là où elle a changé (6.1, 7.5, 7.7). Les résultats des bancs viendront en Task 7.

- [ ] **Step 1 : README.**

`README.md`, bloc 1 sur 4. Remplacer :

````markdown
# amaran COB 60d -> Matter

Piloter deux lampes **amaran COB 60d** (Aputure, 1re génération) depuis Apple
Maison, Siri et les automatisations, par **Matter sur Thread**, avec un
ESP32-C6, tout en gardant l'app **amaran Desktop** utilisable.

Projets frères :
````

par :

````markdown
# amaran COB 60d -> Matter

Piloter des lampes **amaran** (Aputure), aujourd'hui deux **COB 60d** (1re
génération), depuis Apple Maison, Siri et les automatisations, par **Matter sur
Thread**, avec un ESP32-C6, tout en gardant l'app **amaran Desktop** utilisable.
Jusqu'à 16 lampes par pont.

Projets frères :
````

`README.md`, bloc 2 sur 4. Remplacer :

````markdown
3. Appairer. `python3 outils/console.py --port /dev/cu.usbmodemXXXX matter` imprime le code manuel. Dans Maison : « + », « Ajouter un accessoire », « Plus d'options… », puis ce code. Le pont utilise les codes de test du SDK Matter : Maison prévient qu'il n'est pas certifié, « Ajouter quand même ».

Une fois appairé, le pont entre dans le réseau des lampes, et elles apparaissent sous leurs noms d'amaran Desktop.

Carte déjà servie : `erase-flash` fait tirer au pont une nouvelle adresse Mesh au hasard (`0x7F00` à `0x7F7F`). Dans environ 1 cas sur 128 par adresse déjà employée, elle retombe sur une adresse que les lampes connaissent, et elles ignorent alors le pont, sans message d'erreur. Si les deux lampes restent muettes (`lampes` : « lue : jamais ») sans autre alerte de la console, taper `mesh adresse suivante` : le pont prend l'adresse voisine, repart de zéro et redémarre.

## Voyant et bouton
````

par :

````markdown
3. Appairer. `python3 outils/console.py --port /dev/cu.usbmodemXXXX matter` imprime le code manuel. Dans Maison : « + », « Ajouter un accessoire », « Plus d'options… », puis ce code. Le pont utilise les codes de test du SDK Matter : Maison prévient qu'il n'est pas certifié, « Ajouter quand même ».

Une fois appairé, le pont entre dans le réseau des lampes. Chaque lampe apparaît dans Maison, sous son nom d'amaran Desktop, à sa première réponse : une lampe déclarée dans amaran Desktop mais absente d'ici n'y apparaît pas.

Carte déjà servie : `erase-flash` fait tirer au pont une nouvelle adresse Mesh au hasard (`0x7F00` à `0x7F7F`). Dans environ 1 cas sur 128 par adresse déjà employée, elle retombe sur une adresse que les lampes connaissent, et elles ignorent alors le pont, sans message d'erreur. Si toutes les lampes restent muettes (`lampes` : « lue jamais ») sans autre alerte de la console, taper `mesh adresse suivante` : le pont prend l'adresse voisine, repart de zéro et redémarre.

## Voyant et bouton
````

`README.md`, bloc 3 sur 4. Remplacer :

````markdown

Sur l'USB, en français (`python3 outils/console.py --port <port> "<commande>"`, ou tout terminal série) :
- `lampes` : état lu, consigne, joignabilité, relectures et ordres de chaque lampe ;
- `lampe <n> on|off|niveau <0-1000>|releve` : le niveau est arrondi au pour cent (la lampe ne garde pas mieux) ;
- `mesh` : réseau, empreintes des clés, compteurs ; `mesh releve <s>`, `mesh balayage`, `mesh ecoute on|off`, `mesh autotest`, etc. ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre`.
````

par :

````markdown

Sur l'USB, en français (`python3 outils/console.py --port <port> "<commande>"`, ou tout terminal série) :
- `lampes` : une ligne par lampe (sa place dans Maison : `EP<n>`, « jamais vue » ou « masquee » ; état lu, joignabilité, relectures répondues), puis les ordres ;
- `lampe <n>` : le détail d'une lampe (adresse, MAC, modèle et capacités, consigne, relectures sur 10 min) ;
- `lampe <n> on|off|niveau <0-1000>|releve` : le niveau est arrondi au pour cent (la lampe ne garde pas mieux) ;
- `mesh lampe <n> masquer|afficher` : retirer la lampe de Maison, ou l'y remettre, avec le même numéro ;
- `mesh` : réseau, empreintes des clés, compteurs ; `mesh releve <s>`, `mesh balayage`, `mesh ecoute on|off`, `mesh autotest`, etc. ;
- `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` : la liste des lampes, tout ou rien (c'est ce qu'envoie `outils/cles_amaran.py`) ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre`.
````

`README.md`, bloc 4 sur 4. Remplacer :

````markdown
- Maison ne montre une lampe « Pas de réponse », puis son retour, qu'après avoir touché sa tuile. Le pont publie pourtant chaque changement.
- Pour la luminosité, taper sur la jauge de Maison est plus fluide que la faire glisser : un glissé envoie une valeur toutes les 150 à 300 ms.
- Bouton BOOT : juste après un appui annulé (tenu de 2 à 8 s, donc sans effet), relâcher net ; un effleurement redémarre le pont, sans conséquence (les clés et l'appairage restent).

````

par :

````markdown
- Maison ne montre une lampe « Pas de réponse », puis son retour, qu'après avoir touché sa tuile. Le pont publie pourtant chaque changement.
- Pour la luminosité, taper sur la jauge de Maison est plus fluide que la faire glisser : un glissé envoie une valeur toutes les 150 à 300 ms.
- Une lampe n'entre dans Maison qu'à sa première réponse, puis y reste : absente, elle y est « Pas de réponse », et garde sa tuile, sa pièce et ses scènes. Pour la retirer de Maison : `mesh lampe <n> masquer` (`afficher` la remet, avec le même numéro).
- Retirer une lampe dans amaran Desktop, puis recharger les clés, lui fait perdre son numéro : remise plus tard, elle revient comme une lampe nouvelle.
- `mesh oublie` efface les clés, mais garde la liste des lampes : leurs tuiles restent, en « Pas de réponse », jusqu'au rechargement des clés.
- Un modèle que le pont ne connaît pas encore est piloté en marche et intensité seulement. `outils/cles_amaran.py` signale une lampe qui déclare la température de couleur ou la couleur : modèle à cataloguer.
- Si une lampe manque plus de 5 % de ses relectures sur 10 minutes, la console le dit (`!! lampe <n> : relectures manquees`) : allonger la période (`mesh releve`).
- Bouton BOOT : juste après un appui annulé (tenu de 2 à 8 s, donc sans effet), relâcher net ; un effleurement redémarre le pont, sans conséquence (les clés et l'appairage restent).

````

- [ ] **Step 2 : spec du pont.**

`docs/superpowers/specs/2026-09-28-pont-amaran-design.md`, bloc 1 sur 3. Remplacer :

````markdown
| 3 | lampe 2 | idem |

- Les numéros d'endpoint sont fixes : les deux emplacements sont toujours
  créés, dans le même ordre (EP2, EP3), sans rien garder en NVS. Recharger les
  clés ne crée donc pas de nouvelles tuiles. Un emplacement sans lampe est
  « Pas de réponse ».
- Maison reprend les noms (T1). Il affiche « Pas de réponse » pour une lampe
  non joignable, mais seulement après qu'on a touché sa tuile (T5, T9), bien
````

par :

````markdown
| 3 | lampe 2 | idem |

- Depuis le plan 3a (spec `2026-10-03-pont-amaran-n-lampes-design.md`, 5 et
  7) : un endpoint par lampe exposée, jusqu'à 16, avec un numéro stable par
  MAC. Les deux lampes du plan 2 gardent EP2 et EP3. Une lampe jamais vue n'est
  pas exposée ; son retrait de Maison est un geste explicite.
- Maison reprend les noms (T1). Il affiche « Pas de réponse » pour une lampe
  non joignable, mais seulement après qu'on a touché sa tuile (T5, T9), bien
````

`docs/superpowers/specs/2026-09-28-pont-amaran-design.md`, bloc 2 sur 3. Remplacer :

````markdown
- `mesh` : adresse, IV Index, compteur de séquence, empreintes des clés,
  compteurs du crochet et de l'émission, part d'écoute du Mesh.
- Réglages : `mesh cles <netkey> <appkey>`, `mesh lampe <n> <adresse> <mac>
  <nom>`, `mesh iv <n> | cherche`, `mesh adresse <a> | suivante`,
  `mesh releve <s>`, `mesh balayage [<fenêtre> <intervalle>]` (part d'écoute
  du Mesh, en ms : 5.8), `mesh ecoute on | off` (écoute détaillée : messages
````

par :

````markdown
- `mesh` : adresse, IV Index, compteur de séquence, empreintes des clés,
  compteurs du crochet et de l'émission, part d'écoute du Mesh.
- Réglages : `mesh cles <netkey> <appkey>`, `mesh lampes <N>` puis
  `mesh lampe <n> <adresse> <mac> <code> <nom>` (plan 3a, spec N lampes 10),
  `mesh lampe <n> masquer | afficher`, `mesh iv <n> | cherche`,
  `mesh adresse <a> | suivante`,
  `mesh releve <s>`, `mesh balayage [<fenêtre> <intervalle>]` (part d'écoute
  du Mesh, en ms : 5.8), `mesh ecoute on | off` (écoute détaillée : messages
````

`docs/superpowers/specs/2026-09-28-pont-amaran-design.md`, bloc 3 sur 3. Remplacer :

````markdown
- Jamais affichées (empreinte seulement), jamais dans un journal ni dans le
  dépôt.
- `decommission` les garde ; `mesh oublie` les efface.

## 8. Phases et bancs
````

par :

````markdown
- Jamais affichées (empreinte seulement), jamais dans un journal ni dans le
  dépôt.
- `decommission` les garde ; `mesh oublie` les efface, et garde la liste des
  lampes (plan 3a).

## 8. Phases et bancs
````

- [ ] **Step 3 : commit.**

Run: `sh tests/hote/lancer.sh` : `tests hote : tout est vert` (règle du dépôt).

```bash
git add README.md docs/superpowers/specs/2026-09-28-pont-amaran-design.md
git commit -m "$(printf "Documenter le pont a N lampes : console, exposition dans Maison, masquer et afficher\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---
### Task 7: Au banc : migration, retrait et retour, lampe jamais vue, capacité (Claude et Djoko)

**Qui :** Claude, le contrôleur, avec Djoko présent. **Pas de sous-agent** : on flashe, on émet vers les lampes, et on lit la base d'amaran Desktop. L'écriture de `docs/BANC.md` peut partir à un sous-agent, avec un fichier de résultats.

**Files:**
- Modify: `docs/BANC.md` (section « Plan 3a »), `README.md` (ligne d'état)

**Interfaces:**
- Consumes : le firmware des Tasks 1 à 4, `outils/cles_amaran.py` de la Task 5, `outils/console.py`.

Pourquoi : la spec N lampes, section 12. Le banc 1 vérifie la migration sur le pont en service : deux tuiles, leur pièce, le groupe d'accessoires de Djoko et ses automatisations. Le banc 2 répond à la question qui décide la Task 8 : ce que Maison garde quand une lampe revient.

- [ ] **Step 1 : flasher, avec l'accord de Djoko, sans effacer.**

Run: `git status --short && sh tests/hote/lancer.sh && python3 -m unittest discover -s outils -p "test_*.py" 2>&1 | tail -1 && export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py build | tail -2 && cd ..`
Expected : `git status` vide ; tout vert ; `OK` ; `Project build complete.`

Reconnaître la carte par son `SER=` (comme au plan 2, Task 8, Step 2 ; ce numéro n'est écrit nulle part dans le dépôt), puis demander à Djoko : « Je flashe le firmware du plan 3a sur la C6 du pont (`<port>`), sans effacer ? ».

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py -p <port> flash && cd ..`

- [ ] **Step 2 : banc 1, la migration.**

La conversion de l'ancien format se fait au premier démarrage, juste après le flash : son message (`liste des lampes convertie : 2 lampe(s), EP2 et EP3 gardes`) passe le plus souvent avant que la capture ne s'ouvre. On vérifie son effet, sur un démarrage capturé en entier :

Run: `python3 outils/console.py --port <port> "redemarre" "@40" "matter" "lampes" "taches"`
Expected, dans le journal :
- `lampe 1 dans Maison : EP2, amaran COB 60d` et `lampe 2 dans Maison : EP3, amaran COB 60d` ;
- `matter` : 2 fabriques, `Thread : child (attache)`, `EP2 : <nom de la lampe 1>`, `EP3 : <nom de la lampe 2>` ;
- `lampes` : `lampe 1 : <nom> [EP2] ...` et `lampe 2 : <nom> [EP3] ...`, joignables ;
- `taches` : `lampes` au-dessus de 2 Ko libres (6 Ko de pile), aucune tâche sous 512 o.

Djoko regarde Maison : les deux tuiles, leur pièce, son groupe d'accessoires et ses automatisations sont **identiques**. Puis T1 rapide : allumer, régler, éteindre chaque lampe depuis Maison.

Puis deux redémarrages de plus (`python3 outils/console.py --port <port> "redemarre" "@40" "lampes"`, deux fois). Après chacun, Djoko confirme que Maison n'a rien perdu : c'est le risque de la recréation des endpoints après `esp_matter::start()` (spec N lampes 7).

- [ ] **Step 3 : banc 2, retrait et retour (ce que Maison garde).**

Avant : Djoko crée dans Maison une scène de test et une automatisation de test qui contiennent la lampe 2. Il note sa pièce et son groupe.

Run: `python3 outils/console.py --port <port> "mesh lampe 2 masquer" "@10" "lampes"`
Expected : `ok lampe 2 retiree de Maison (...)` ; `lampes` : `lampe 2 : <nom> [masquee] ...`. Djoko : la tuile de la lampe 2 disparaît de Maison.

Run (au bout d'une minute) : `python3 outils/console.py --port <port> "mesh lampe 2 afficher" "@10" "lampes" "matter"`
Expected : `ok lampe 2 dans Maison (EP3)` ; `matter` : `EP3`.

Djoko relève, pour la lampe 2 revenue : la pièce, le groupe d'accessoires, la scène de test, l'automatisation de test. Pour chacun : gardé ou perdu. **C'est ce relevé qui décide la Task 8** :
- tout gardé : la Task 8 se fera ;
- sinon : la Task 8 est sautée, et Djoko remet la lampe 2 dans sa pièce et son groupe.

- [ ] **Step 4 : banc 3, une lampe jamais vue.**

Run (Claude seul : l'outil lit la base) : `python3 outils/cles_amaran.py --port <port> --fictives 1`
Expected : `ok lampe 3 0x0100 modele 0 non catalogue [intensite] : Fictive 1 ; liste de 3 lampe(s) enregistree (...)`, puis `pont redemarre avec les nouvelles cles`.

Run: `python3 outils/console.py --port <port> "@40" "lampes" "matter"`
Expected : `lampe 3 : Fictive 1 [jamais vue] lue jamais, ...` ; `matter` ne montre que `EP2` et `EP3`. Djoko : aucune tuile nouvelle dans Maison.

- [ ] **Step 5 : banc 4, la capacité, avec l'accord de Djoko.**

Lui dire avant : « 14 tuiles “Pas de réponse” vont apparaître dans Maison le temps de la mesure, puis disparaître. D'accord ? ». Sans accord, sauter au Step 6 et le noter.

Run (Claude seul) : `python3 outils/cles_amaran.py --port <port> --fictives 14`
Expected : la dernière réponse dit `liste de 16 lampe(s) enregistree`.

Run: `python3 outils/console.py --port <port> "@40" "mesh lampe 3 afficher" "mesh lampe 4 afficher" "mesh lampe 5 afficher" "mesh lampe 6 afficher" "mesh lampe 7 afficher" "mesh lampe 8 afficher" "mesh lampe 9 afficher" "mesh lampe 10 afficher" "mesh lampe 11 afficher" "mesh lampe 12 afficher" "mesh lampe 13 afficher" "mesh lampe 14 afficher" "mesh lampe 15 afficher" "mesh lampe 16 afficher" "@30" "matter" "taches" "lampes"`
Expected : 14 lignes `ok lampe <n> dans Maison (EP<k>)`, avec des numéros neufs (4 et au-delà) ; `matter` : 16 endpoints de lampe, au moins un abonnement ; `taches` : le tas libre au plus bas, et aucune tâche sous 512 o.

Puis : `python3 outils/console.py --port <port> "redemarre" "@60" "cause" "matter" "taches" "lampes"`. Relever le temps jusqu'à `mesh pret : oui` (journal), le tas, les abonnements. Djoko : Maison tient 16 tuiles, et un T1 rapide sur les deux vraies lampes marche.

Enfin, retirer les fictives (Claude seul) : `python3 outils/cles_amaran.py --port <port>`, puis `python3 outils/console.py --port <port> "@40" "matter" "lampes"`. Expected : `matter` ne montre plus que `EP2` et `EP3`. Djoko : les 14 tuiles disparaissent.

Si la mémoire manque (tas au plus bas sous 30 Ko, ou une création refusée), le noter : la capacité sera abaissée à ce que mesure le banc (spec N lampes 13), dans une tâche à part.

- [ ] **Step 6 : consigner.**

À la fin de `docs/BANC.md`, une section `## Plan 3a : N lampes` avec, pour chaque banc, la date, le firmware (`<commit>`), le résultat et les remarques :
- **banc 1** : conversion vue, EP2 et EP3, Maison inchangée, et les redémarrages ;
- **banc 2** : ce que Maison a gardé ;
- **banc 3** ;
- **banc 4** : tas, piles, abonnements, temps de démarrage, 16 tuiles.

Dans `README.md`, sous `## État`, ajouter au tableau la ligne :

```markdown
| P3a | N lampes : liste, catalogue de modèles, numéros d'endpoint stables, exposition à la première réponse | faite (<date>) : bancs 1 à 4 ; <résumé> |
```

```bash
git add docs/BANC.md README.md
git commit -m "$(printf "Consigner les bancs du plan 3a : migration, retrait et retour, lampe jamais vue, capacite\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

- [ ] **Step 7 : pousser, avec l'accord de Djoko.**

Montrer `git log --oneline origin/main..main` et le résumé des bancs. Vérifier qu'aucune donnée sensible ne part : `git diff origin/main..main | /usr/bin/grep -E '^\+' | /usr/bin/grep -cE 'AMARAN-[0-9A-F]{4,}|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'`. Relire chaque ligne trouvée : seules les MAC inventées des tests (`70:3E:97:00:00:0x`) et des lampes fictives (`02:00:00:00:00:..`, administrées localement) sont permises ; aucune vraie MAC ni aucun numéro `AMARAN-…`. Puis demander : « Je pousse sur GitHub ? ». Après son accord seulement :

Run: `git push origin main`

---

### Task 8 (conditionnelle) : l'option « masquer quand absente depuis 5 minutes »

**À ne faire que si le banc 2 (Task 7) a montré que Maison garde tout au retour d'une lampe** (pièce, groupe, scène, automatisation). Sinon, la Task 8 est sautée : le registre et `BANC.md` le disent.

**Files:**
- Modify: `components/liste/include/liste.h`, `components/liste/liste.c`, `tests/hote/test_liste.c`
- Modify: `firmware/main/tache_lampes.h`, `firmware/main/tache_lampes.c`, `firmware/main/console_pont.c`

**Interfaces:**
- Produces : `LISTE_AUTO` (drapeau), `LISTE_AUTO_SILENCE_MS` (300 000), `bool liste_a_cacher(const liste_lampe_t *, uint32_t silence_ms)`, `esp_err_t tache_lampes_auto(int lampe, bool oui)`, console `mesh lampe <n> auto on|off`.

Pourquoi : la décision 6 de la spec N lampes.
- Une lampe avec l'option quitte Maison après 5 minutes de silence, et y revient à sa première réponse avec le même numéro.
- L'état « cachée » ne vit qu'en mémoire ; le choix de l'option est sauvé.
- Un geste explicite (`masquer`, `afficher`) prime sur l'option.

- [ ] **Step 1 : le test.**

`tests/hote/test_liste.c`, bloc 1 sur 2. Remplacer :

````c
}

static void test_nvs_aller_retour(void) {
  liste_t l = deux_lampes();
````

par :

````c
}

static void test_a_cacher(void) {
  liste_lampe_t a = lampe(0x0002, 0x01, "Lampe A");
  liste_marquer_vue(&a);
  VERIFIE(!liste_a_cacher(&a, LISTE_AUTO_SILENCE_MS), "sans l'option : jamais cachee");
  a.drapeaux |= LISTE_AUTO;
  VERIFIE(!liste_a_cacher(&a, LISTE_AUTO_SILENCE_MS - 1), "avec l'option, avant 5 min : non");
  VERIFIE(liste_a_cacher(&a, LISTE_AUTO_SILENCE_MS), "avec l'option, a 5 min : oui");
  liste_masquer(&a);
  VERIFIE(!liste_a_cacher(&a, LISTE_AUTO_SILENCE_MS), "deja masquee : non");
  liste_lampe_t jamais = lampe(0x0004, 0x02, "Jamais vue");
  jamais.drapeaux = LISTE_AUTO;
  VERIFIE(!liste_a_cacher(&jamais, LISTE_AUTO_SILENCE_MS), "jamais vue : pas exposee, rien a cacher");
}

static void test_nvs_aller_retour(void) {
  liste_t l = deux_lampes();
````

`tests/hote/test_liste.c`, bloc 2 sur 2. Remplacer :

````c
  test_fusionner();
  test_exposition();
  test_nvs_aller_retour();
  test_migration_v1();
````

par :

````c
  test_fusionner();
  test_exposition();
  test_a_cacher();
  test_nvs_aller_retour();
  test_migration_v1();
````

- [ ] **Step 2 : le voir échouer.** Run: `sh tests/hote/lancer.sh` : échec de compilation (`LISTE_AUTO` inconnu).

- [ ] **Step 3 : la liste.**

`components/liste/include/liste.h`, bloc 1 sur 2. Remplacer :

````c
#define LISTE_RESERVEE_MAX 0x7F7F
#define LISTE_CODE_V1 40065u        // avant le plan 3a, seules des COB 60d ont pu etre chargees

enum {
  LISTE_VUE = 1u << 0,      // la lampe a repondu au moins une fois : exposee dans Maison
  LISTE_MASQUEE = 1u << 1,  // retiree de Maison par un geste explicite
};

````

par :

````c
#define LISTE_RESERVEE_MAX 0x7F7F
#define LISTE_CODE_V1 40065u        // avant le plan 3a, seules des COB 60d ont pu etre chargees
#define LISTE_AUTO_SILENCE_MS 300000u  // option « absente » : 5 min de silence (decision 6, banc 2)

enum {
  LISTE_VUE = 1u << 0,      // la lampe a repondu au moins une fois : exposee dans Maison
  LISTE_MASQUEE = 1u << 1,  // retiree de Maison par un geste explicite
  LISTE_AUTO = 1u << 2,     // option : retiree de Maison quand absente, revenue a sa reponse
};

````

`components/liste/include/liste.h`, bloc 2 sur 2. Remplacer :

````c
void liste_masquer(liste_lampe_t *l);
void liste_afficher(liste_lampe_t *l);                   // exposee, meme jamais entendue

// Format en NVS : un en-tete, puis n lampes. La taille d'une lampe y est notee : une
````

par :

````c
void liste_masquer(liste_lampe_t *l);
void liste_afficher(liste_lampe_t *l);                   // exposee, meme jamais entendue
// Option « masquer quand absente » (decision 6) : vrai si la lampe, exposee et avec
// l'option, se tait depuis au moins LISTE_AUTO_SILENCE_MS.
bool liste_a_cacher(const liste_lampe_t *l, uint32_t silence_ms);

// Format en NVS : un en-tete, puis n lampes. La taille d'une lampe y est notee : une
````

`components/liste/liste.c`, bloc 1 sur 1. Remplacer :

````c
void liste_afficher(liste_lampe_t *l) { l->drapeaux = (uint8_t)((l->drapeaux | LISTE_VUE) & ~LISTE_MASQUEE); }

uint32_t liste_taille_nvs(const liste_t *l) {
  return (uint32_t)(sizeof(liste_entete_t) + (size_t)l->n * sizeof(liste_lampe_t));
````

par :

````c
void liste_afficher(liste_lampe_t *l) { l->drapeaux = (uint8_t)((l->drapeaux | LISTE_VUE) & ~LISTE_MASQUEE); }

bool liste_a_cacher(const liste_lampe_t *l, uint32_t silence_ms) {
  return (l->drapeaux & LISTE_AUTO) && liste_exposee(l) && silence_ms >= LISTE_AUTO_SILENCE_MS;
}

uint32_t liste_taille_nvs(const liste_t *l) {
  return (uint32_t)(sizeof(liste_entete_t) + (size_t)l->n * sizeof(liste_lampe_t));
````

- [ ] **Step 4 : le test passe.** Run: `sh tests/hote/lancer.sh` : `liste : 55 verifications, 0 echecs`.

- [ ] **Step 5 : la tâche des lampes et la console.**

`firmware/main/tache_lampes.h`, bloc 1 sur 1. Remplacer :

````c
// le choix est sauve en NVS. Depuis la console (pas la tache CHIP).
esp_err_t tache_lampes_exposition(int lampe, bool afficher);
// Ecoute detaillee : imprimer aussi chaque etat recu des lampes.
void tache_lampes_ecoute(bool oui);
````

par :

````c
// le choix est sauve en NVS. Depuis la console (pas la tache CHIP).
esp_err_t tache_lampes_exposition(int lampe, bool afficher);
// Option « masquer quand absente » (decision 6 du plan 3a) : la lampe quitte Maison
// apres 5 min de silence et y revient a sa premiere reponse. Le choix est sauve.
esp_err_t tache_lampes_auto(int lampe, bool oui);
// Ecoute detaillee : imprimer aussi chaque etat recu des lampes.
void tache_lampes_ecoute(bool oui);
````

`firmware/main/tache_lampes.c`, bloc 1 sur 5. Remplacer :

````c
static lampes_t s_lampes;
static liste_t s_liste;             // liste du demarrage ; drapeaux tenus a jour
static volatile bool s_ecoute;
static volatile uint32_t s_confirmes, s_abandons;
````

par :

````c
static lampes_t s_lampes;
static liste_t s_liste;             // liste du demarrage ; drapeaux tenus a jour
static bool s_cachee[LISTE_CAPACITE];  // retiree de Maison par l'option « absente » (en memoire)
static uint32_t s_debut_ms;            // demarrage : le silence d'une lampe jamais entendue part de la
static volatile bool s_ecoute;
static volatile uint32_t s_confirmes, s_abandons;
````

`firmware/main/tache_lampes.c`, bloc 2 sur 5. Remplacer :

````c
  }
  return err;
}

````

par :

````c
  }
  return err;
}

// Option « masquer quand absente » : 5 min de silence, la lampe quitte Maison ; a sa
// premiere reponse, elle revient avec le meme numero. Sous s_verrou.
static void cacher_ou_rendre(uint32_t t) {
  for (int i = 0; i < s_lampes.n; i++) {
    const lampe_t *p = &s_lampes.lampes[i];
    const uint32_t silence = p->entendue ? t - p->reponse_ms : t - s_debut_ms;
    if (!s_cachee[i] && liste_a_cacher(&s_liste.lampes[i], silence)) {
      if (pont_masquer(i) == ESP_OK) {
        s_cachee[i] = true;
        printf("[lampes] lampe %d absente depuis 5 min : retiree de Maison\n", i + 1);
      }
    } else if (s_cachee[i] && p->entendue && silence < 5000) {
      if (exposer(i) == ESP_OK) {
        s_cachee[i] = false;
        printf("[lampes] lampe %d revenue : dans Maison (EP%u)\n", i + 1, (unsigned)pont_endpoint(i));
      }
    }
  }
}

````

`firmware/main/tache_lampes.c`, bloc 3 sur 5. Remplacer :

````c
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    exposer_les_nouvelles();
    lampes_mesh_pret(&s_lampes, mesh_pret(), maintenant_ms());
    lampes_tic(&s_lampes, maintenant_ms());
````

par :

````c
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    exposer_les_nouvelles();
    cacher_ou_rendre(maintenant_ms());
    lampes_mesh_pret(&s_lampes, mesh_pret(), maintenant_ms());
    lampes_tic(&s_lampes, maintenant_ms());
````

`firmware/main/tache_lampes.c`, bloc 4 sur 5. Remplacer :

````c
  _Static_assert(LAMPES_CAPACITE == LISTE_CAPACITE, "une lampe de la liste par lampe du coeur");
  s_liste = cfg->liste;
  uint16_t adresses[LAMPES_CAPACITE];
  for (int i = 0; i < s_liste.n; i++) adresses[i] = s_liste.lampes[i].adresse;
````

par :

````c
  _Static_assert(LAMPES_CAPACITE == LISTE_CAPACITE, "une lampe de la liste par lampe du coeur");
  s_liste = cfg->liste;
  s_debut_ms = maintenant_ms();
  uint16_t adresses[LAMPES_CAPACITE];
  for (int i = 0; i < s_liste.n; i++) adresses[i] = s_liste.lampes[i].adresse;
````

`firmware/main/tache_lampes.c`, bloc 5 sur 5. Remplacer :

````c
  esp_err_t err = config_maj_drapeaux(a->mac, a->drapeaux);
  if (err == ESP_OK) err = afficher ? exposer(lampe) : pont_masquer(lampe);
  xSemaphoreGive(s_verrou);
  return err;
````

par :

````c
  esp_err_t err = config_maj_drapeaux(a->mac, a->drapeaux);
  if (err == ESP_OK) err = afficher ? exposer(lampe) : pont_masquer(lampe);
  if (err == ESP_OK) s_cachee[lampe] = false;  // un geste explicite prime sur l'option
  xSemaphoreGive(s_verrou);
  return err;
}

esp_err_t tache_lampes_auto(int lampe, bool oui) {
  if (!s_verrou || lampe < 0 || lampe >= s_liste.n) return ESP_ERR_INVALID_ARG;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  liste_lampe_t *a = &s_liste.lampes[lampe];
  a->drapeaux = (uint8_t)(oui ? (a->drapeaux | LISTE_AUTO) : (a->drapeaux & ~LISTE_AUTO));
  esp_err_t err = config_maj_drapeaux(a->mac, a->drapeaux);
  if (err == ESP_OK && !oui && s_cachee[lampe]) {  // option retiree : la lampe revient dans Maison
    err = exposer(lampe);
    if (err == ESP_OK) s_cachee[lampe] = false;
  }
  xSemaphoreGive(s_verrou);
  return err;
````

`firmware/main/console_pont.c`, bloc 1 sur 4. Remplacer :

````c
           s_l.releves);
    if (p->alerte) printf(" !! manquees");
    printf("\n");
  }
````

par :

````c
           s_l.releves);
    if (p->alerte) printf(" !! manquees");
    if (s_liste.lampes[i].drapeaux & LISTE_AUTO) printf(" (auto)");
    printf("\n");
  }
````

`firmware/main/console_pont.c`, bloc 2 sur 4. Remplacer :

````c
}

// `mesh` du pont : celle du composant mesh, plus la periode de relecture,
// l'exposition d'une lampe, et l'ecoute detaillee qui imprime aussi les etats.
````

par :

````c
}

// mesh lampe <n> auto on|off : option « masquer quand absente » (5 min de silence).
static int mesh_auto(char **argv) {
  uint32_t n = 0;
  const bool oui = !strcmp(argv[4], "on");
  if (!texte_lire_nombre(argv[2], &n) || n < 1 || n > s_cfg->liste.n) {
    printf("erreur : mesh lampe <1-%u> auto on|off\n", (unsigned)s_cfg->liste.n);
    return 1;
  }
  const esp_err_t err = tache_lampes_auto((int)n - 1, oui);
  if (err != ESP_OK) {
    printf("erreur : auto (%s)\n", esp_err_to_name(err));
    return 1;
  }
  printf("ok lampe %" PRIu32 " : %s\n", n,
         oui ? "retiree de Maison apres 5 min d'absence, revenue a sa reponse" : "reste dans Maison, absente ou non");
  return 0;
}

// `mesh` du pont : celle du composant mesh, plus la periode de relecture,
// l'exposition d'une lampe, et l'ecoute detaillee qui imprime aussi les etats.
````

`firmware/main/console_pont.c`, bloc 3 sur 4. Remplacer :

````c
  if (argc == 4 && !strcmp(argv[1], "lampe") && (!strcmp(argv[3], "masquer") || !strcmp(argv[3], "afficher"))) {
    return mesh_exposition(argc, argv);
  }
  if (argc == 3 && !strcmp(argv[1], "ecoute") && (!strcmp(argv[2], "on") || !strcmp(argv[2], "off"))) {
````

par :

````c
  if (argc == 4 && !strcmp(argv[1], "lampe") && (!strcmp(argv[3], "masquer") || !strcmp(argv[3], "afficher"))) {
    return mesh_exposition(argc, argv);
  }
  if (argc == 5 && !strcmp(argv[1], "lampe") && !strcmp(argv[3], "auto") &&
      (!strcmp(argv[4], "on") || !strcmp(argv[4], "off"))) {
    return mesh_auto(argv);
  }
  if (argc == 3 && !strcmp(argv[1], "ecoute") && (!strcmp(argv[2], "on") || !strcmp(argv[2], "off"))) {
````

`firmware/main/console_pont.c`, bloc 4 sur 4. Remplacer :

````c
      {.command = "mesh",
       .help = "etat ; mesh cles|lampes|lampe|iv|adresse|oublie|ecoute|balayage|autotest|releve ... ; "
               "mesh lampe <n> masquer|afficher",
       .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
````

par :

````c
      {.command = "mesh",
       .help = "etat ; mesh cles|lampes|lampe|iv|adresse|oublie|ecoute|balayage|autotest|releve ... ; "
               "mesh lampe <n> masquer|afficher|auto on|off",
       .func = cmd_mesh},
      {.command = "matter", .help = "mise en service, Thread, abonnements, codes, identite", .func = cmd_matter},
````

- [ ] **Step 6 : compiler.** Run, depuis la racine du dépôt : `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py build 2>&1 | tail -1) && (cd ecoute && idf.py build 2>&1 | tail -1)` : `Project build complete.` deux fois.

- [ ] **Step 7 : commit**, puis le banc de l'option (Claude et Djoko, flash avec son accord) : `mesh lampe 2 auto on` ; couper la lampe 2 à son bouton d'alimentation ; après 5 minutes, sa tuile disparaît (`[lampes] lampe 2 absente depuis 5 min : retiree de Maison`) ; la rallumer : la tuile revient, `EP3`, avec sa pièce et son groupe. Consigner dans `docs/BANC.md`, et ajouter au README (« À savoir ») la commande et son effet.

```bash
git add components/liste tests/hote/test_liste.c firmware/main
git commit -m "$(printf "Option par lampe : retiree de Maison apres 5 min d'absence, revenue a sa reponse\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```
