# Pont amaran, plan 1 : la reconnaissance (phase 0) : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un firmware d'écoute pour ESP32-C6 qui rejoint le réseau Bluetooth Mesh des deux amaran 60d avec les clés d'amaran Desktop, capte leurs états et les pilote depuis une console ; l'outil Mac qui charge les clés et une console de banc ; puis les essais R1 à R6 avec Djoko.

**Architecture:** Deux composants ESP-IDF partagés avec le futur produit :
- `telink` : trames `0x26`, C pur ;
- `mesh` : outils de texte et tri des messages en C pur ; réglages en NVS ; hôte NimBLE ; adhésion au réseau et file d'émission ; crochet de réception posé par `-Wl,--wrap` ; autotest.

Le firmware `ecoute/` y ajoute une console et un journal. Le code pur est testé sur le Mac (clang). Le reste est vérifié par la compilation, puis au banc avec les vraies lampes.

**Tech Stack:** ESP-IDF v5.5.4 (C, FreeRTOS, NimBLE, ESP-BLE-MESH), clang pour les tests natifs, Python 3 (unittest ; pyserial du Python d'ESP-IDF).

**Spec:** `docs/superpowers/specs/2026-09-28-pont-amaran-design.md`, surtout les sections 3, 4.2, 5, 7.5, 8.2, 9 et 10.

## Global Constraints

- ESP-IDF v5.5.4 dans `~/esp/esp-idf`, cible `esp32c6`, flash 4 Mo. Pas d'esp-matter dans ce plan.
- Pile Bluetooth : **NimBLE**, pas Bluedroid. Matter sur Thread l'exigera en phase 1.
- **ESP-IDF n'est jamais modifié** (le SmartButton partage l'installation). Le crochet passe par `-Wl,--wrap`.
- L'adresse Mesh de l'ESP32 est dans `0x7F00`–`0x7F7F`, **jamais `0x0001`** (l'adresse d'amaran Desktop).
- **Aucune clé** dans le dépôt, un journal ou un affichage. L'empreinte d'une clé = les 8 premiers chiffres hexa, en majuscules, de son SHA-256.
- `CONFIG_MBEDTLS_HARDWARE_AES=n`.
- Émission :
  - au moins 70 ms entre deux messages ;
  - un ordre part 2 fois (70 ms d'écart), une demande d'état 1 fois ;
  - 3 copies réseau à 20 ms d'écart, TTL 3.
- Français partout : code, messages de console, commits. Les commentaires du code sont **sans accents** (style du pont Halo).
- Commits : message en français, terminé par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Les sous-agents ne flashent jamais et n'ouvrent jamais de port série.**
  - Claude flashe avec l'accord de Djoko.
  - Djoko est présent dès qu'on émet vers les lampes.
  - Le port série est toujours donné explicitement : les écrans LG apparaissent eux aussi en `usbmodem`.
- Dans les scripts et les commandes, utiliser `/usr/bin/grep` : le `grep` du poste est ugrep.
- Tout `idf.py` se lance dans la même commande shell que `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null`.
  Le `PATH` doit commencer par le Python 3.14 de Homebrew : l'environnement ESP-IDF 5.5 a été créé avec lui, et le Python 3.11 de PlatformIO, souvent en tête, fait échouer `export.sh` (« virtual environment … idf5.5_py3.11_env not found »).
- Tests Python : le `python3` du système (unittest), sans dépendance à installer. Envoi série : le Python d'ESP-IDF, qui fournit pyserial.

## Écarts assumés par rapport à la spec

1. **Adresse initiale tirée au hasard** dans `0x7F00`–`0x7F7F`, au lieu de `0x7F00` fixe. Après un effacement de la flash, cela évite de retomber sur une adresse dont les lampes gardent un compteur plus haut que le nôtre (5.4).
2. **La pile Mesh ne persiste rien** (`CONFIG_BLE_MESH_SETTINGS=n`).
   - L'ESP32 rentre dans le réseau à chaque démarrage, depuis la NVS `amaran`.
   - Le plancher de séquence est tenu par notre code : bloc de 256, toujours sauvé d'avance.
   - Cela remplace le « à vérifier lors du plan » de 5.4.
3. **Les balises aussi sont interceptées** (`bt_mesh_beacon_recv`), pour lire l'IV Index annoncé par les lampes même quand la pile le refuse (5.3).
4. **Outil `outils/console.py`** pour piloter les bancs et en garder le journal.
5. **Autotest :** vecteurs 8.3.1, 8.3.22 et 8.4.3 de la spécification Mesh, confirmés à l'octet près par les tests unitaires de BlueZ (`unit/test-mesh-crypto.c`).

## Carte des fichiers

| fichier | rôle | tâche |
|---|---|---|
| `components/telink/{CMakeLists.txt,include/telink.h,telink.c}` | trames Telink `0x26` (C pur, en-tête MIT d'amaran-bridge) | 1 |
| `tests/hote/{unite.h,lancer.sh,test_telink.c}` | cadre de tests natifs et tests de `telink` | 1 |
| `components/mesh/{include/texte.h,texte.c}` | hexa, MAC, nombres (C pur) | 2 |
| `components/mesh/{include/crochet_tri.h,crochet_tri.c}` | en-têtes réseau, transport, trames de lampe, balises (C pur) | 2 |
| `components/mesh/CMakeLists.txt` | composant `mesh` (grandit tâche après tâche) | 2, 6, 7, 8, 9 |
| `tests/hote/{test_texte.c,test_crochet_tri.c}` | tests natifs | 2 |
| `outils/{serie.py,cles_amaran.py,port_factice.py,test_cles_amaran.py}` | outil des clés | 3 |
| `outils/{console.py,test_serie.py}` | console de banc | 4 |
| `outils/check_sdkconfig.sh` | vérifie les symboles des `sdkconfig.defaults` | 5 |
| `ecoute/{CMakeLists.txt,sdkconfig.defaults,main/CMakeLists.txt,main/app_main.c}` | firmware de reconnaissance | 5, 6, 7, 10 |
| `components/mesh/{include/config_amaran.h,config_amaran.c}` | réglages en NVS | 6 |
| `components/mesh/{hote_ble.h,hote_ble.c}` | hôte NimBLE | 7 |
| `components/mesh/{include/mesh_amaran.h,mesh_amaran.c}` | adhésion, file d'émission, plancher de séquence | 7, 9 |
| `components/mesh/{crochet.h,crochet.c}` | crochet `--wrap`, déchiffrement, événements | 7, 8, 9 |
| `components/mesh/autotest.c` | vecteurs de la spécification Mesh | 9 |
| `ecoute/main/{console_ecoute.h,console_ecoute.c}` | console et journal | 10 |
| `docs/BANC.md`, `docs/PROTOCOLE.md`, `README.md` | bancs, protocole relevé, état | 11, 12 |

---

### Task 1: Tests sur le Mac et trames Telink

**Files:**
- Create: `tests/hote/unite.h`, `tests/hote/test_telink.c`, `tests/hote/lancer.sh`
- Create: `components/telink/CMakeLists.txt`, `components/telink/include/telink.h`, `components/telink/telink.c`

**Interfaces:**
- Produces (`telink.h`) :
  - `TELINK_OPCODE` (0x26), `TELINK_CID` (0x0211), `TELINK_TAILLE` (10), `TELINK_CMD_ETAT` (0x0E), `TELINK_CMD_MARCHE` (0x8C), `TELINK_CMD_INTENSITE` (0x8F), `TELINK_MODE_HSI` (0x01), `TELINK_MODE_CCT` (0x02), `TELINK_INTENSITE_MAX` (1000) ;
  - `typedef struct { bool valide; uint8_t mode; bool marche; uint16_t intensite; } telink_etat_t;` ;
  - `uint8_t telink_somme(const uint8_t t[TELINK_TAILLE]);`
  - `void telink_demande_etat(uint8_t t[TELINK_TAILLE]);`
  - `void telink_marche(bool marche, uint8_t t[TELINK_TAILLE]);`
  - `void telink_intensite(uint16_t intensite, uint8_t t[TELINK_TAILLE]);`
  - `bool telink_lire_etat(const uint8_t t[TELINK_TAILLE], telink_etat_t *etat);`
- Produces (`unite.h`) : `VERIFIE(cond, fmt, ...)`, `int bilan(const char *nom)`.

- [ ] **Step 1 : écrire le cadre de tests et les tests.**

`tests/hote/unite.h` :

```c
// Mini cadre de tests sur le Mac (meme esprit que tools/host_tests du Halo).
#pragma once

#include <stdio.h>

static int g_verifs = 0;
static int g_echecs = 0;

#define VERIFIE(cond, ...)                          \
  do {                                              \
    g_verifs++;                                     \
    if (!(cond)) {                                  \
      g_echecs++;                                   \
      printf("ECHEC %s:%d : ", __FILE__, __LINE__); \
      printf(__VA_ARGS__);                          \
      printf("\n");                                 \
    }                                               \
  } while (0)

static inline int bilan(const char *nom) {
  printf("%s : %d verifications, %d echecs\n", nom, g_verifs, g_echecs);
  return g_echecs ? 1 : 0;
}
```

`tests/hote/test_telink.c` :

```c
// Tests sur le Mac des trames Telink. Lancer : sh tests/hote/lancer.sh
// Vecteurs : spec 3.2 et calcul des octets (somme = octets 1 a 9, mod 256).
#include <string.h>

#include "telink.h"
#include "unite.h"

static void test_demande_etat(void) {
  uint8_t t[TELINK_TAILLE];
  const uint8_t attendu[TELINK_TAILLE] = {0x0E, 0, 0, 0, 0, 0, 0, 0, 0, 0x0E};
  telink_demande_etat(t);
  VERIFIE(memcmp(t, attendu, TELINK_TAILLE) == 0, "demande d'etat");
}

static void test_marche(void) {
  uint8_t t[TELINK_TAILLE];
  const uint8_t on[TELINK_TAILLE] = {0x8D, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x8C};
  const uint8_t off[TELINK_TAILLE] = {0x8C, 0, 0, 0, 0, 0, 0, 0, 0x00, 0x8C};
  telink_marche(true, t);
  VERIFIE(memcmp(t, on, TELINK_TAILLE) == 0, "marche");
  telink_marche(false, t);
  VERIFIE(memcmp(t, off, TELINK_TAILLE) == 0, "arret");
}

static void test_intensite(void) {
  uint8_t t[TELINK_TAILLE];
  const uint8_t v500[TELINK_TAILLE] = {0x0C, 0, 0, 0, 0, 0, 0, 0x00, 0x7D, 0x8F};
  const uint8_t v1000[TELINK_TAILLE] = {0x89, 0, 0, 0, 0, 0, 0, 0x00, 0xFA, 0x8F};
  const uint8_t v1[TELINK_TAILLE] = {0xCF, 0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x8F};
  telink_intensite(500, t);
  VERIFIE(memcmp(t, v500, TELINK_TAILLE) == 0, "intensite 500");
  telink_intensite(1000, t);
  VERIFIE(memcmp(t, v1000, TELINK_TAILLE) == 0, "intensite 1000");
  telink_intensite(1, t);
  VERIFIE(memcmp(t, v1, TELINK_TAILLE) == 0, "intensite 1");
  telink_intensite(1500, t);
  VERIFIE(memcmp(t, v1000, TELINK_TAILLE) == 0, "intensite bornee a 1000");
}

static void test_lire_etat(void) {
  // Etat CCT reconstruit : marche, 93,0 %, 5600 K, G/M neutre.
  const uint8_t cct[TELINK_TAILLE] = {0xCF, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0xE8, 0x02};
  telink_etat_t e;
  VERIFIE(telink_lire_etat(cct, &e), "etat CCT lisible");
  VERIFIE(e.valide && e.mode == TELINK_MODE_CCT, "mode CCT (%u)", (unsigned)e.mode);
  VERIFIE(e.marche, "marche");
  VERIFIE(e.intensite == 930, "intensite 930 (%u)", (unsigned)e.intensite);

  uint8_t faux[TELINK_TAILLE];
  memcpy(faux, cct, TELINK_TAILLE);
  faux[0] ^= 0x01;
  VERIFIE(!telink_lire_etat(faux, &e) && !e.valide, "somme fausse refusee");

  uint8_t inconnu[TELINK_TAILLE] = {0, 0x01, 0, 0, 0, 0, 0, 0, 0, 0x0A};
  inconnu[0] = telink_somme(inconnu);
  VERIFIE(!telink_lire_etat(inconnu, &e), "mode 0x0A refuse");

  uint8_t arret[TELINK_TAILLE];
  memcpy(arret, cct, TELINK_TAILLE);
  arret[1] = 0x00;
  arret[0] = telink_somme(arret);
  VERIFIE(telink_lire_etat(arret, &e) && !e.marche && e.intensite == 930, "arret, intensite gardee");
}

int main(void) {
  test_demande_etat();
  test_marche();
  test_intensite();
  test_lire_etat();
  return bilan("telink");
}
```

`tests/hote/lancer.sh` :

```sh
#!/bin/sh
# Tests sur le Mac, sans carte. Depuis la racine du depot : sh tests/hote/lancer.sh
set -eu
cd "$(dirname "$0")/../.."
SORTIE="${TMPDIR:-/tmp}/amaran-tests-hote"
mkdir -p "$SORTIE"
CC="${CC:-clang}"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Itests/hote"

compiler_et_lancer() {
  nom="$1"
  shift
  # shellcheck disable=SC2086
  "$CC" $CFLAGS "$@" -o "$SORTIE/$nom"
  "$SORTIE/$nom"
}

compiler_et_lancer test_telink components/telink/telink.c tests/hote/test_telink.c
echo "tests hote : tout est vert"
```

- [ ] **Step 2 : vérifier que les tests échouent.**

Run: `sh tests/hote/lancer.sh`
Expected : échec de compilation, `'telink.h' file not found`.

- [ ] **Step 3 : écrire le composant `telink`.**

`components/telink/CMakeLists.txt` :

```cmake
idf_component_register(SRCS "telink.c"
                       INCLUDE_DIRS "include")
```

`components/telink/include/telink.h` :

```c
// Trames Telink des lampes amaran : opcode d'un octet 0x26, charge de 10
// octets, octet 0 = somme des octets 1 a 9 (spec 3.2). Format etabli par
// amaran-bridge (Kevin Schaich, MIT), voir telink.c.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#define TELINK_OPCODE 0x26
#define TELINK_CID 0x0211
#define TELINK_TAILLE 10

#define TELINK_CMD_ETAT 0x0E
#define TELINK_CMD_MARCHE 0x8C
#define TELINK_CMD_INTENSITE 0x8F
#define TELINK_MODE_HSI 0x01
#define TELINK_MODE_CCT 0x02
#define TELINK_INTENSITE_MAX 1000

typedef struct {
  bool valide;         // somme juste et mode connu (CCT ou HSI)
  uint8_t mode;        // octet 9 & 0x7F
  bool marche;         // bit 0 de l'octet 1
  uint16_t intensite;  // 0..1000, pas de 0,1 %
} telink_etat_t;

#ifdef __cplusplus
extern "C" {
#endif

uint8_t telink_somme(const uint8_t t[TELINK_TAILLE]);
void telink_demande_etat(uint8_t t[TELINK_TAILLE]);
void telink_marche(bool marche, uint8_t t[TELINK_TAILLE]);
void telink_intensite(uint16_t intensite, uint8_t t[TELINK_TAILLE]);
bool telink_lire_etat(const uint8_t t[TELINK_TAILLE], telink_etat_t *etat);

#ifdef __cplusplus
}
#endif
```

`components/telink/telink.c` :

```c
// Trames Telink des lampes amaran.
//
// Adapte de main/telink.c d'amaran-bridge :
// https://github.com/kevinschaich/amaran-bridge
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
#include "telink.h"

#include <string.h>

uint8_t telink_somme(const uint8_t t[TELINK_TAILLE]) {
  unsigned s = 0;
  for (int i = 1; i < TELINK_TAILLE; i++) s += t[i];
  return (uint8_t)(s & 0xFF);
}

void telink_demande_etat(uint8_t t[TELINK_TAILLE]) {
  memset(t, 0, TELINK_TAILLE);
  t[9] = TELINK_CMD_ETAT;
  t[0] = telink_somme(t);
}

void telink_marche(bool marche, uint8_t t[TELINK_TAILLE]) {
  memset(t, 0, TELINK_TAILLE);
  t[8] = marche ? 0x01 : 0x00;
  t[9] = TELINK_CMD_MARCHE;
  t[0] = telink_somme(t);
}

void telink_intensite(uint16_t intensite, uint8_t t[TELINK_TAILLE]) {
  const uint16_t v = intensite > TELINK_INTENSITE_MAX ? TELINK_INTENSITE_MAX : intensite;
  memset(t, 0, TELINK_TAILLE);
  t[7] = (uint8_t)((v & 0x03) << 6);
  t[8] = (uint8_t)(v >> 2);
  t[9] = TELINK_CMD_INTENSITE;
  t[0] = telink_somme(t);
}

bool telink_lire_etat(const uint8_t t[TELINK_TAILLE], telink_etat_t *etat) {
  memset(etat, 0, sizeof(*etat));
  if (t[0] != telink_somme(t)) return false;
  etat->mode = t[9] & 0x7F;
  if (etat->mode != TELINK_MODE_CCT && etat->mode != TELINK_MODE_HSI) return false;
  etat->marche = (t[1] & 0x01) != 0;
  const uint16_t v = (uint16_t)((((unsigned)t[8] << 2) | (t[7] >> 6)) & 0x3FF);
  etat->intensite = v > TELINK_INTENSITE_MAX ? TELINK_INTENSITE_MAX : v;
  etat->valide = true;
  return true;
}
```

- [ ] **Step 4 : vérifier que les tests passent.**

Run: `sh tests/hote/lancer.sh`
Expected : `telink : 14 verifications, 0 echecs` puis `tests hote : tout est vert`.

- [ ] **Step 5 : commit.**

```bash
git add components/telink tests/hote
git commit -m "$(printf 'Ajouter les trames Telink et les tests sur le Mac\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 2: Outils de texte et tri du crochet (C pur)

**Files:**
- Create: `components/mesh/include/texte.h`, `components/mesh/texte.c`
- Create: `components/mesh/include/crochet_tri.h`, `components/mesh/crochet_tri.c`
- Create: `components/mesh/CMakeLists.txt`
- Create: `tests/hote/test_texte.c`, `tests/hote/test_crochet_tri.c`
- Modify: `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : `telink.h` (Task 1).
- Produces (`texte.h`) :
  - `bool texte_hex_vers_octets(const char *hex, uint8_t *sortie, size_t n);` : exactement `2*n` chiffres hexa, casse libre ;
  - `void texte_octets_vers_hex(const uint8_t *octets, size_t n, char *sortie);` : `2*n` chiffres majuscules et un NUL ;
  - `bool texte_lire_mac(const char *texte, uint8_t mac[6]);` : forme `AA:BB:CC:DD:EE:FF` ;
  - `bool texte_lire_nombre(const char *texte, uint32_t *sortie);` : décimal ou `0x…`, sans débordement.
- Produces (`crochet_tri.h`) :
  - `TRI_ENTETE_RESEAU` (9) ;
  - `tri_entete_t { bool ctl; uint8_t ttl; uint32_t seq; uint16_t src; uint16_t dst; }` ;
  - `tri_transport_t { bool segmente; bool akf; uint8_t aid; }` ;
  - `tri_balise_t { uint8_t flags; uint8_t net_id[8]; uint32_t iv_index; }` ;
  - `bool tri_lire_entete(const uint8_t *clair, size_t len, tri_entete_t *e);` ;
  - `void tri_lire_transport(uint8_t octet, tri_transport_t *t);` ;
  - `int tri_etat_lampe(uint16_t src, const uint8_t *acces, size_t len, const uint16_t *lampes, size_t nb, uint8_t trame[TELINK_TAILLE]);` : index de la lampe, ou -1 ;
  - `bool tri_lire_balise(const uint8_t *b, size_t len, tri_balise_t *balise);` : balise sécurisée, type `0x01`, 22 octets.

- [ ] **Step 1 : écrire les tests.**

`tests/hote/test_texte.c` :

```c
// Tests sur le Mac des outils de texte. Lancer : sh tests/hote/lancer.sh
#include <string.h>

#include "texte.h"
#include "unite.h"

static void test_hex(void) {
  uint8_t o[4];
  VERIFIE(texte_hex_vers_octets("00a1FF7e", o, 4) && o[0] == 0x00 && o[1] == 0xA1 && o[2] == 0xFF && o[3] == 0x7E,
          "hexa, casse mixte");
  VERIFIE(!texte_hex_vers_octets("00a1FF7", o, 4), "hexa trop court");
  VERIFIE(!texte_hex_vers_octets("00a1FF7e0", o, 4), "hexa trop long");
  VERIFIE(!texte_hex_vers_octets("00g1FF7e", o, 4), "caractere non hexa");
  char s[9];
  const uint8_t valeurs[4] = {0x00, 0xA1, 0xFF, 0x7E};
  texte_octets_vers_hex(valeurs, 4, s);
  VERIFIE(strcmp(s, "00A1FF7E") == 0, "octets vers hexa (%s)", s);
}

static void test_mac(void) {
  uint8_t m[6];
  VERIFIE(texte_lire_mac("70:3E:97:12:34:ab", m) && m[0] == 0x70 && m[3] == 0x12 && m[5] == 0xAB, "MAC");
  VERIFIE(!texte_lire_mac("70:3E:97:12:34", m), "MAC courte");
  VERIFIE(!texte_lire_mac("70-3E-97-12-34-AB", m), "MAC mal separee");
  VERIFIE(!texte_lire_mac("70:3E:97:12:34:AB:00", m), "MAC longue");
}

static void test_nombre(void) {
  uint32_t v = 0;
  VERIFIE(texte_lire_nombre("42", &v) && v == 42, "decimal");
  VERIFIE(texte_lire_nombre("0x2A", &v) && v == 42, "hexa");
  VERIFIE(texte_lire_nombre("0X7f00", &v) && v == 0x7F00, "hexa, X majuscule");
  VERIFIE(texte_lire_nombre("4294967295", &v) && v == 4294967295u, "maximum");
  VERIFIE(!texte_lire_nombre("4294967296", &v), "debordement decimal");
  VERIFIE(!texte_lire_nombre("0x100000000", &v), "debordement hexa");
  VERIFIE(!texte_lire_nombre("", &v), "vide");
  VERIFIE(!texte_lire_nombre("0x", &v), "0x seul");
  VERIFIE(!texte_lire_nombre("12a", &v), "caractere parasite");
  VERIFIE(!texte_lire_nombre("-1", &v), "negatif");
}

int main(void) {
  test_hex();
  test_mac();
  test_nombre();
  return bilan("texte");
}
```

`tests/hote/test_crochet_tri.c` :

```c
// Tests sur le Mac du tri des messages captes. Lancer : sh tests/hote/lancer.sh
// Vecteurs en clair de la specification Mesh (8.3.1, 8.3.22, 8.4.3), releves
// dans unit/test-mesh-crypto.c de BlueZ.
#include <string.h>

#include "crochet_tri.h"
#include "texte.h"
#include "unite.h"

static void test_entete(void) {
  uint8_t c[20];
  texte_hex_vers_octets("68800000011201fffd034b50057e400000010000", c, 20);  // 8.3.1 en clair
  tri_entete_t e;
  VERIFIE(tri_lire_entete(c, 20, &e), "en-tete 8.3.1 lisible");
  VERIFIE(e.ctl && e.ttl == 0 && e.seq == 1 && e.src == 0x1201 && e.dst == 0xFFFD, "champs 8.3.1");
  uint8_t d[22];
  texte_hex_vers_octets("e80307080b1234b529663871b904d431526316ca48a0", d, 22);  // 8.3.22 en clair
  VERIFIE(tri_lire_entete(d, 22, &e) && !e.ctl && e.ttl == 3 && e.seq == 0x07080B && e.src == 0x1234 &&
              e.dst == 0xB529,
          "champs 8.3.22");
  VERIFIE(!tri_lire_entete(d, 8, &e), "en-tete trop courte");
}

static void test_transport(void) {
  tri_transport_t t;
  tri_lire_transport(0x66, &t);
  VERIFIE(!t.segmente && t.akf && t.aid == 0x26, "0x66 : non segmente, AppKey, AID 0x26");
  tri_lire_transport(0x80, &t);
  VERIFIE(t.segmente && !t.akf && t.aid == 0, "0x80 : segmente, cle d'appareil");
}

static void test_etat_lampe(void) {
  const uint16_t lampes[] = {0x0002, 0x0004};
  uint8_t acces[11] = {TELINK_OPCODE, 0xCF, 0x01, 0x00, 0x00, 0x00, 0x40, 0x01, 0xA3, 0xE8, 0x02};
  uint8_t trame[TELINK_TAILLE];
  VERIFIE(tri_etat_lampe(0x0004, acces, 11, lampes, 2, trame) == 1 && memcmp(trame, acces + 1, 10) == 0,
          "lampe 2 reconnue");
  VERIFIE(tri_etat_lampe(0x0003, acces, 11, lampes, 2, trame) == -1, "source inconnue");
  VERIFIE(tri_etat_lampe(0x0002, acces, 10, lampes, 2, trame) == -1, "longueur fausse");
  acces[0] = 0x27;
  VERIFIE(tri_etat_lampe(0x0002, acces, 11, lampes, 2, trame) == -1, "opcode faux");
  acces[0] = TELINK_OPCODE;
  acces[1] ^= 0xFF;
  VERIFIE(tri_etat_lampe(0x0002, acces, 11, lampes, 2, trame) == -1, "somme fausse");
}

static void test_balise(void) {
  uint8_t b[22];
  texte_hex_vers_octets("01003ecaff672f673370123456788ea261582f364f6f", b, 22);  // 8.4.3
  const uint8_t net_id[8] = {0x3E, 0xCA, 0xFF, 0x67, 0x2F, 0x67, 0x33, 0x70};
  tri_balise_t bal;
  VERIFIE(tri_lire_balise(b, 22, &bal) && bal.iv_index == 0x12345678 && bal.flags == 0 &&
              memcmp(bal.net_id, net_id, 8) == 0,
          "balise 8.4.3");
  b[0] = 0x00;
  VERIFIE(!tri_lire_balise(b, 22, &bal), "balise non securisee refusee");
  b[0] = 0x01;
  VERIFIE(!tri_lire_balise(b, 21, &bal), "balise courte refusee");
}

int main(void) {
  test_entete();
  test_transport();
  test_etat_lampe();
  test_balise();
  return bilan("crochet_tri");
}
```

Dans `tests/hote/lancer.sh`, ajouter ces deux lignes avant `echo "tests hote : tout est vert"` :

```sh
compiler_et_lancer test_texte components/mesh/texte.c tests/hote/test_texte.c
compiler_et_lancer test_crochet_tri components/telink/telink.c components/mesh/texte.c components/mesh/crochet_tri.c tests/hote/test_crochet_tri.c
```

- [ ] **Step 2 : vérifier que les nouveaux tests échouent.**

Run: `sh tests/hote/lancer.sh`
Expected : `telink` passe, puis échec de compilation `'texte.h' file not found`.

- [ ] **Step 3 : écrire `texte` et `crochet_tri`.**

`components/mesh/include/texte.h` :

```c
// Petits outils de texte purs (hexa, MAC, nombres), testes sur le Mac.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Exactement 2*n chiffres hexa (casse libre) -> n octets.
bool texte_hex_vers_octets(const char *hex, uint8_t *sortie, size_t n);
// n octets -> 2*n chiffres hexa majuscules suivis d'un NUL (sortie : 2*n+1).
void texte_octets_vers_hex(const uint8_t *octets, size_t n, char *sortie);
// "70:3E:97:12:34:AB" -> 6 octets.
bool texte_lire_mac(const char *texte, uint8_t mac[6]);
// Decimal ou 0x... -> uint32 (refuse vide, signe, parasites, debordement).
bool texte_lire_nombre(const char *texte, uint32_t *sortie);
```

`components/mesh/texte.c` :

```c
#include "texte.h"

#include <string.h>

static int valeur_hexa(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool texte_hex_vers_octets(const char *hex, uint8_t *sortie, size_t n) {
  if (!hex || strlen(hex) != 2 * n) return false;
  for (size_t i = 0; i < n; i++) {
    const int h = valeur_hexa(hex[2 * i]);
    const int l = valeur_hexa(hex[2 * i + 1]);
    if (h < 0 || l < 0) return false;
    sortie[i] = (uint8_t)((h << 4) | l);
  }
  return true;
}

void texte_octets_vers_hex(const uint8_t *octets, size_t n, char *sortie) {
  static const char chiffres[] = "0123456789ABCDEF";
  for (size_t i = 0; i < n; i++) {
    sortie[2 * i] = chiffres[octets[i] >> 4];
    sortie[2 * i + 1] = chiffres[octets[i] & 0x0F];
  }
  sortie[2 * n] = '\0';
}

bool texte_lire_mac(const char *texte, uint8_t mac[6]) {
  if (!texte || strlen(texte) != 17) return false;
  for (int i = 0; i < 6; i++) {
    if (i < 5 && texte[3 * i + 2] != ':') return false;
    const int h = valeur_hexa(texte[3 * i]);
    const int l = valeur_hexa(texte[3 * i + 1]);
    if (h < 0 || l < 0) return false;
    mac[i] = (uint8_t)((h << 4) | l);
  }
  return true;
}

bool texte_lire_nombre(const char *texte, uint32_t *sortie) {
  if (!texte || !*texte) return false;
  const char *p = texte;
  unsigned base = 10;
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
    base = 16;
    p += 2;
    if (!*p) return false;
  }
  uint64_t v = 0;
  for (; *p; p++) {
    const int c = base == 16 ? valeur_hexa(*p) : ((*p >= '0' && *p <= '9') ? *p - '0' : -1);
    if (c < 0) return false;
    v = v * base + (unsigned)c;
    if (v > 0xFFFFFFFFu) return false;
  }
  *sortie = (uint32_t)v;
  return true;
}
```

`components/mesh/include/crochet_tri.h` :

```c
// Tri pur des messages Mesh captes par le crochet (spec 5.5), teste sur le Mac.
// Les en-tetes sont lus APRES dechiffrement du message reseau.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "telink.h"

#define TRI_ENTETE_RESEAU 9  // IVI/NID, CTL/TTL, SEQ (3), SRC (2), DST (2)

typedef struct {
  bool ctl;
  uint8_t ttl;
  uint32_t seq;
  uint16_t src;
  uint16_t dst;
} tri_entete_t;

typedef struct {
  bool segmente;
  bool akf;     // chiffre par une AppKey (sinon cle d'appareil)
  uint8_t aid;  // identifiant de l'AppKey
} tri_transport_t;

typedef struct {
  uint8_t flags;
  uint8_t net_id[8];
  uint32_t iv_index;
} tri_balise_t;

bool tri_lire_entete(const uint8_t *clair, size_t len, tri_entete_t *e);
void tri_lire_transport(uint8_t octet, tri_transport_t *t);
// Charge d'acces dechiffree = opcode 0x26 + 10 octets a la somme juste, d'une
// source presente dans lampes : rend son index et copie la trame, sinon -1.
int tri_etat_lampe(uint16_t src, const uint8_t *acces, size_t len, const uint16_t *lampes, size_t nb,
                   uint8_t trame[TELINK_TAILLE]);
// Balise reseau securisee (type 0x01), octet de type compris : 22 octets.
bool tri_lire_balise(const uint8_t *b, size_t len, tri_balise_t *balise);
```

`components/mesh/crochet_tri.c` :

```c
#include "crochet_tri.h"

#include <string.h>

bool tri_lire_entete(const uint8_t *c, size_t len, tri_entete_t *e) {
  if (len < TRI_ENTETE_RESEAU) return false;
  e->ctl = (c[1] & 0x80) != 0;
  e->ttl = c[1] & 0x7F;
  e->seq = ((uint32_t)c[2] << 16) | ((uint32_t)c[3] << 8) | c[4];
  e->src = (uint16_t)((c[5] << 8) | c[6]);
  e->dst = (uint16_t)((c[7] << 8) | c[8]);
  return true;
}

void tri_lire_transport(uint8_t octet, tri_transport_t *t) {
  t->segmente = (octet & 0x80) != 0;
  t->akf = (octet & 0x40) != 0;
  t->aid = octet & 0x3F;
}

int tri_etat_lampe(uint16_t src, const uint8_t *acces, size_t len, const uint16_t *lampes, size_t nb,
                   uint8_t trame[TELINK_TAILLE]) {
  if (len != 1 + TELINK_TAILLE || acces[0] != TELINK_OPCODE) return -1;
  if (acces[1] != telink_somme(acces + 1)) return -1;
  for (size_t i = 0; i < nb; i++) {
    if (lampes[i] != 0 && lampes[i] == src) {
      memcpy(trame, acces + 1, TELINK_TAILLE);
      return (int)i;
    }
  }
  return -1;
}

bool tri_lire_balise(const uint8_t *b, size_t len, tri_balise_t *balise) {
  if (len < 22 || b[0] != 0x01) return false;
  balise->flags = b[1];
  memcpy(balise->net_id, b + 2, 8);
  balise->iv_index = ((uint32_t)b[10] << 24) | ((uint32_t)b[11] << 16) | ((uint32_t)b[12] << 8) | b[13];
  return true;
}
```

`components/mesh/CMakeLists.txt` (première version ; les tâches 6 à 9 la complètent) :

```cmake
idf_component_register(SRCS "texte.c" "crochet_tri.c"
                       INCLUDE_DIRS "include"
                       REQUIRES telink)
```

- [ ] **Step 4 : vérifier que tout passe.**

Run: `sh tests/hote/lancer.sh`
Expected : `telink : 14 …, 0 echecs`, `texte : 19 …, 0 echecs`, `crochet_tri : 14 …, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 5 : commit.**

```bash
git add components/mesh tests/hote
git commit -m "$(printf 'Ajouter les outils de texte et le tri pur du crochet\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 3: L'outil des clés (`outils/cles_amaran.py`)

**Files:**
- Create: `outils/serie.py`, `outils/cles_amaran.py`, `outils/port_factice.py`, `outils/test_cles_amaran.py`

**Interfaces:**
- Produces (`serie.py`) :
  - `masquer(texte) -> str` : remplace toute suite de 32 chiffres hexa par `<cle masquee>` ;
  - `ouvrir_port(nom, debit=115200, delai=0.2)` : pyserial, DTR et RTS à 0 avant l'ouverture ;
  - `lire_pendant(port, duree, ecrire)`.
- Produces (`cles_amaran.py`) :
  - `ErreurCles` ;
  - `trouver_base(motifs=MOTIFS_BASE) -> str` ;
  - `lire_reseau(chemin) -> {"reseau": bytes, "application": bytes, "lampes": [{"adresse", "mac", "nom"}]}` ;
  - `empreinte(cle) -> str`, `resume(r) -> [str]`, `commandes(r) -> [str]` ;
  - `envoyer(port, lignes, attente=3.0, sortie=print)` ;
  - `main(argv=None, sortie=print) -> int`.
- Produces (`port_factice.py`) : `PortFactice(reponses)`, avec `.write(octets)`, `.readline()` et `.ecrit`.
- Commandes envoyées au pont, exactement celles de la tâche 10 :
  - `mesh cles <RESEAU32HEXA> <APPLI32HEXA>` → `ok cles <EMP> <EMP> …` ;
  - `mesh lampe <n> 0x%04X <MAC> <nom…>` → `ok lampe …` ;
  - puis `redemarre`.

- [ ] **Step 1 : écrire l'aide de test et les tests.**

`outils/port_factice.py` :

```python
"""Imite un port pyserial pour les tests : lignes a rendre, octets ecrits."""


class PortFactice:
    def __init__(self, reponses=()):
        self.reponses = list(reponses)
        self.ecrit = []

    def write(self, octets):
        self.ecrit.append(octets.decode())

    def readline(self):
        return (self.reponses.pop(0) + "\r\n").encode() if self.reponses else b""
```

`outils/test_cles_amaran.py` :

```python
"""Tests de outils/cles_amaran.py, sans carte ni pyserial.

    python3 -m unittest discover -s outils -p "test_*.py" -v
"""
import os
import sqlite3
import tempfile
import time
import unittest

import cles_amaran as ca
from port_factice import PortFactice

NET = "00112233445566778899aabbccddeeff"
APP = "ffeeddccbbaa99887766554433221100"
LAMPES = ((4, "70:3e:97:00:00:02", "Lampe B"), (2, "70:3E:97:00:00:01", "Lampe A"))


def base_factice(dossier, lampes=LAMPES, reseaux=1):
    chemin = os.path.join(dossier, "amaran.db")
    con = sqlite3.connect(chemin)
    con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
    con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
    for i in range(reseaux):
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m%d" % i, NET.upper(), APP.upper()))
    for adresse, mac, nom in lampes:
        con.execute("insert into fixtures values (?, ?, ?, ?, ?)", ("f%d" % adresse, mac, nom, adresse, "00" * 16))
    con.commit()
    con.close()
    return chemin


class TestLecture(unittest.TestCase):
    def setUp(self):
        self.dossier = tempfile.mkdtemp()

    def test_cles_et_lampes_par_adresse(self):
        r = ca.lire_reseau(base_factice(self.dossier))
        self.assertEqual(r["reseau"], bytes.fromhex(NET))
        self.assertEqual(r["application"], bytes.fromhex(APP))
        self.assertEqual([l["adresse"] for l in r["lampes"]], [2, 4])
        self.assertEqual(r["lampes"][1]["mac"], "70:3E:97:00:00:02")

    def test_refuse_deux_reseaux(self):
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, reseaux=2))

    def test_refuse_trois_lampes(self):
        trois = LAMPES + ((6, "70:3E:97:00:00:03", "Lampe C"),)
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, lampes=trois))

    def test_refuse_base_sans_lampe(self):
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, lampes=()))

    def test_refuse_base_absente(self):
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(os.path.join(self.dossier, "absente.db"))

    def test_trouve_la_base_la_plus_recente(self):
        for sous in ("1_secure_id", "2_secure_id"):
            os.makedirs(os.path.join(self.dossier, sous))
        ancienne = base_factice(os.path.join(self.dossier, "1_secure_id"))
        recente = base_factice(os.path.join(self.dossier, "2_secure_id"))
        passe = time.time() - 100
        os.utime(ancienne, (passe, passe))
        motif = os.path.join(self.dossier, "*", "amaran.db")
        self.assertEqual(ca.trouver_base((motif,)), recente)

    def test_base_introuvable(self):
        with self.assertRaises(ca.ErreurCles):
            ca.trouver_base((os.path.join(self.dossier, "*", "amaran.db"),))


class TestEmpreintesEtCommandes(unittest.TestCase):
    def test_empreintes_fixes(self):
        self.assertEqual(ca.empreinte(bytes.fromhex(NET)), "A8FAED6A")
        self.assertEqual(ca.empreinte(bytes.fromhex(APP)), "811407F1")

    def test_commandes(self):
        r = ca.lire_reseau(base_factice(tempfile.mkdtemp()))
        self.assertEqual(ca.commandes(r), [
            "mesh cles %s %s" % (NET.upper(), APP.upper()),
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 Lampe B",
        ])


class TestSortie(unittest.TestCase):
    def test_sans_port_aucune_cle_affichee(self):
        capture = []
        code = ca.main(["--db", base_factice(tempfile.mkdtemp())], sortie=capture.append)
        texte = "\n".join(capture)
        self.assertEqual(code, 0)
        for cle in (NET, APP):
            self.assertNotIn(cle, texte.lower())
        self.assertIn("A8FAED6A", texte)
        self.assertIn("<cle masquee>", texte)

    def test_erreur_rend_1(self):
        capture = []
        absente = os.path.join(tempfile.mkdtemp(), "absente.db")
        self.assertEqual(ca.main(["--db", absente], sortie=capture.append), 1)
        self.assertTrue(capture[-1].startswith("erreur : "))


class TestEnvoi(unittest.TestCase):
    def test_attend_ok_et_masque(self):
        cles = "mesh cles %s %s" % (NET.upper(), APP.upper())
        port = PortFactice([
            cles,  # echo de la console
            "ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
            "amaran> ok lampe 1 0x0002 Lampe A",
        ])
        capture = []
        ca.envoyer(port, [cles, "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A"], attente=1, sortie=capture.append)
        self.assertEqual(len(port.ecrit), 2)
        self.assertTrue(all(l.endswith("\r\n") for l in port.ecrit))
        self.assertEqual(capture, [
            "pont : ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
            "pont : ok lampe 1 0x0002 Lampe A",
        ])

    def test_erreur_du_pont(self):
        with self.assertRaises(ca.ErreurCles):
            ca.envoyer(PortFactice(["erreur : ecriture NVS"]), ["mesh cles X Y"], attente=1, sortie=lambda t: None)

    def test_silence_du_pont(self):
        with self.assertRaises(ca.ErreurCles):
            ca.envoyer(PortFactice([]), ["mesh cles X Y"], attente=0.2, sortie=lambda t: None)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2 : vérifier qu'ils échouent.**

Run: `python3 -m unittest discover -s outils -p "test_*.py" -v`
Expected : `ModuleNotFoundError: No module named 'cles_amaran'`.

- [ ] **Step 3 : écrire `serie.py` et `cles_amaran.py`.**

`outils/serie.py` :

```python
"""Liaison serie avec le pont (USB natif du C6) et masquage des cles.

ouvrir_port() demande pyserial : lancer les outils avec le Python d'ESP-IDF
(`export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh`).
Les tests n'en ont pas besoin.
"""
import re
import time

HEXA_CLE = re.compile(r"[0-9A-Fa-f]{32}")


def masquer(texte):
    """Remplace toute suite de 32 chiffres hexa (une cle) par <cle masquee>."""
    return HEXA_CLE.sub("<cle masquee>", texte)


def ouvrir_port(nom, debit=115200, delai=0.2):
    import serial  # pyserial

    port = serial.Serial()
    port.port = nom
    port.baudrate = debit
    port.timeout = delai
    # Jamais RTS=1/DTR=0 : cette combinaison redemarre le C6 (lecon du Halo).
    port.dtr = False
    port.rts = False
    port.open()
    return port


def lire_pendant(port, duree, ecrire):
    """Passe a ecrire() chaque ligne recue pendant duree secondes, masquee."""
    fin = time.monotonic() + duree
    while time.monotonic() < fin:
        brute = port.readline()
        if brute:
            ecrire(masquer(brute.decode(errors="replace").rstrip()))
```

`outils/cles_amaran.py` :

```python
#!/usr/bin/env python3
"""Charge dans le pont les cles du reseau Bluetooth Mesh d'amaran Desktop.

Lit la base locale d'amaran Desktop, puis envoie par la console du pont :
    mesh cles <reseau> <application>
    mesh lampe <n> <adresse> <mac> <nom>
    redemarre

Les cles ne sont jamais affichees : seulement leurs empreintes (8 premiers
chiffres hexa du SHA-256), les memes que la commande `mesh` du pont.

    python outils/cles_amaran.py                    # montre ce qui serait envoye
    python outils/cles_amaran.py --port /dev/cu.usbmodem1101

Avec --port, lancer avec le Python d'ESP-IDF (pyserial).
"""
import argparse
import glob
import hashlib
import os
import sqlite3
import sys
import time

from serie import masquer, ouvrir_port

MOTIFS_BASE = (
    "~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop/*/amaran.db",
    "~/Library/Application Support/amaran Desktop/*/amaran.db",
)
LAMPES_MAX = 2
INVITE = "amaran>"


class ErreurCles(Exception):
    pass


def trouver_base(motifs=MOTIFS_BASE):
    """La base d'amaran Desktop la plus recente parmi les motifs."""
    trouvees = [c for m in motifs for c in glob.glob(os.path.expanduser(m))]
    if not trouvees:
        raise ErreurCles("base d'amaran Desktop introuvable : passer --db")
    return max(trouvees, key=os.path.getmtime)


def lire_reseau(chemin):
    """Cles et lampes de la base, ouverte en lecture seule."""
    try:
        con = sqlite3.connect("file:%s?mode=ro" % chemin, uri=True)
        try:
            reseaux = con.execute(
                "select net_key, app_key from mesh where net_key is not null and app_key is not null").fetchall()
            lignes = con.execute(
                "select node_address, mac_address, name from fixtures "
                "where node_address is not null order by node_address").fetchall()
        finally:
            con.close()
    except sqlite3.Error as e:
        raise ErreurCles("base illisible (%s)" % e)
    if len(reseaux) != 1:
        raise ErreurCles("%d reseaux dans la base, 1 attendu" % len(reseaux))
    try:
        reseau, application = bytes.fromhex(reseaux[0][0]), bytes.fromhex(reseaux[0][1])
    except ValueError:
        raise ErreurCles("cle illisible dans la base")
    if len(reseau) != 16 or len(application) != 16:
        raise ErreurCles("cle de longueur inattendue")
    if not lignes:
        raise ErreurCles("aucune lampe dans la base")
    if len(lignes) > LAMPES_MAX:
        raise ErreurCles("%d lampes, le pont en gere %d" % (len(lignes), LAMPES_MAX))
    lampes = [{"adresse": a, "mac": m.upper(), "nom": n} for a, m, n in lignes]
    return {"reseau": reseau, "application": application, "lampes": lampes}


def empreinte(cle):
    """8 premiers chiffres hexa (majuscules) du SHA-256, comme le pont."""
    return hashlib.sha256(cle).hexdigest()[:8].upper()


def resume(r):
    lignes = ["cles : reseau %s, application %s" % (empreinte(r["reseau"]), empreinte(r["application"]))]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("lampe %d : 0x%04X %s (%s)" % (i, l["adresse"], l["nom"], l["mac"]))
    return lignes


def commandes(r):
    lignes = ["mesh cles %s %s" % (r["reseau"].hex().upper(), r["application"].hex().upper())]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("mesh lampe %d 0x%04X %s %s" % (i, l["adresse"], l["mac"], l["nom"]))
    return lignes


def envoyer(port, lignes, attente=3.0, sortie=print):
    """Envoie chaque ligne et attend la reponse `ok ...` ou `erreur ...` du pont."""
    for ligne in lignes:
        port.write((ligne + "\r\n").encode())
        fin = time.monotonic() + attente
        while True:
            if time.monotonic() > fin:
                raise ErreurCles("pas de reponse du pont a : %s" % masquer(ligne))
            brute = port.readline()
            if not brute:
                continue
            texte = brute.decode(errors="replace").split(INVITE)[-1].strip()
            if texte.startswith("ok"):
                sortie("pont : " + masquer(texte))
                break
            if texte.startswith("erreur"):
                raise ErreurCles("pont : " + masquer(texte))


def main(argv=None, sortie=print):
    ap = argparse.ArgumentParser(description="Charge les cles d'amaran Desktop dans le pont.")
    ap.add_argument("--db", help="base d'amaran Desktop (sinon : la plus recente)")
    ap.add_argument("--port", help="port serie du pont ; sans lui, rien n'est envoye")
    args = ap.parse_args(argv)
    try:
        r = lire_reseau(args.db or trouver_base())
        for ligne in resume(r):
            sortie(ligne)
        lignes = commandes(r)
        if not args.port:
            sortie("(sans --port : rien n'est envoye)")
            for ligne in lignes:
                sortie("  " + masquer(ligne))
            return 0
        port = ouvrir_port(args.port)
        try:
            time.sleep(0.3)
            port.reset_input_buffer()
            envoyer(port, lignes, sortie=sortie)
            port.write(b"redemarre\r\n")
            sortie("pont redemarre avec les nouvelles cles")
        finally:
            port.close()
        return 0
    except ErreurCles as e:
        sortie("erreur : %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4 : vérifier que les tests passent.**

Run: `python3 -m unittest discover -s outils -p "test_*.py" -v`
Expected : `Ran 14 tests`, `OK`.

- [ ] **Step 5 : vérifier sur la vraie base, sans rien envoyer.**

Run: `python3 outils/cles_amaran.py`
Expected :
- `cles : reseau XXXXXXXX, application XXXXXXXX` (8 chiffres hexa chacun) ;
- `lampe 1 : 0x0002 amaran COB 60d #1 (…:17:2E)` et `lampe 2 : 0x0004 amaran COB 60d #2 (…:62:A8)` ;
- `(sans --port : rien n'est envoye)` ;
- les commandes avec `<cle masquee>`.

**Aucune suite de 32 chiffres hexa ne doit apparaître.** Ne pas recopier les empreintes dans un fichier du dépôt.

- [ ] **Step 6 : commit.**

```bash
git add outils
git commit -m "$(printf "Ajouter l'outil qui charge les cles d'amaran Desktop dans le pont\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 4: Console de banc (`outils/console.py`)

**Files:**
- Create: `outils/console.py`, `outils/test_serie.py`

**Interfaces:**
- Consumes : `serie.masquer`, `serie.lire_pendant`, `serie.ouvrir_port` (Task 3), `PortFactice` (Task 3).
- Produces : `console.executer(port, etapes, ecrire, apres_commande=1.0, avant=0.5)` et la ligne de commande `python outils/console.py --port P [--journal F] "cmd" "@N" …`.

- [ ] **Step 1 : écrire les tests.**

`outils/test_serie.py` :

```python
"""Tests de outils/serie.py et outils/console.py, sans carte ni pyserial."""
import unittest

import console
import serie
from port_factice import PortFactice


class TestMasquer(unittest.TestCase):
    def test_masque_les_cles_seulement(self):
        texte = "cles 00112233445566778899AABBCCDDEEFF empreinte A8FAED6A mac 70:3E:97:12:34:AB"
        self.assertEqual(serie.masquer(texte), "cles <cle masquee> empreinte A8FAED6A mac 70:3E:97:12:34:AB")


class TestConsole(unittest.TestCase):
    def test_executer_envoie_et_journalise(self):
        port = PortFactice([
            "amaran> ok envoi 0x0002 x1 : 0E00000000000000000E",
            "[1234 ms] etat lampe 1 (0x0002 -> 0x0001) : marche, intensite 930",
        ])
        lignes = []
        console.executer(port, ["lampe 1 releve", "@0.1"], lignes.append, apres_commande=0.1, avant=0)
        self.assertEqual(port.ecrit, ["lampe 1 releve\r\n"])
        self.assertEqual(lignes[0], "> lampe 1 releve")
        self.assertTrue(any("etat lampe 1" in l for l in lignes))

    def test_executer_masque_une_commande_a_cle(self):
        lignes = []
        console.executer(PortFactice(), ["mesh cles " + "AB" * 16 + " " + "CD" * 16], lignes.append,
                         apres_commande=0, avant=0)
        self.assertEqual(lignes, ["> mesh cles <cle masquee> <cle masquee>"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2 : vérifier qu'ils échouent.**

Run: `python3 -m unittest discover -s outils -p "test_*.py" -v`
Expected : `ModuleNotFoundError: No module named 'console'`.

- [ ] **Step 3 : écrire `outils/console.py`.**

```python
#!/usr/bin/env python3
"""Console de banc : envoie des commandes au pont et journalise ses reponses.

    python outils/console.py --port /dev/cu.usbmodem1101 "mesh" "@5" "lampe 1 releve" "@3"

"@N" lit pendant N secondes. Tout est copie, horodate, dans
logs/AAAA-MM-JJ-HHMM-console.log (logs/ est ignore par git). Les cles sont
masquees. Lancer avec le Python d'ESP-IDF (pyserial).
"""
import argparse
import os
import sys
import time

from serie import lire_pendant, masquer, ouvrir_port

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def executer(port, etapes, ecrire, apres_commande=1.0, avant=0.5):
    lire_pendant(port, avant, ecrire)
    for etape in etapes:
        if etape.startswith("@"):
            lire_pendant(port, float(etape[1:]), ecrire)
        else:
            ecrire("> " + masquer(etape))
            port.write((etape + "\r\n").encode())
            lire_pendant(port, apres_commande, ecrire)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Console de banc du pont amaran.")
    ap.add_argument("--port", required=True)
    ap.add_argument("--journal", help="fichier journal (defaut : logs/<date>-console.log)")
    ap.add_argument("etapes", nargs="*", help='commandes, ou "@N" pour lire N secondes')
    args = ap.parse_args(argv)
    chemin = args.journal or os.path.join(RACINE, "logs", time.strftime("%Y-%m-%d-%H%M-console.log"))
    os.makedirs(os.path.dirname(os.path.abspath(chemin)), exist_ok=True)
    with open(chemin, "a", encoding="utf-8") as journal:

        def ecrire(texte):
            ligne = time.strftime("%H:%M:%S ") + texte
            print(ligne, flush=True)
            journal.write(ligne + "\n")
            journal.flush()

        port = ouvrir_port(args.port)
        try:
            executer(port, args.etapes, ecrire)
        finally:
            port.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4 : vérifier que tout passe.**

Run: `python3 -m unittest discover -s outils -p "test_*.py" -v`
Expected : `Ran 17 tests`, `OK`.

- [ ] **Step 5 : commit.**

```bash
git add outils
git commit -m "$(printf 'Ajouter la console de banc qui journalise les sessions\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 5: Squelette du firmware `ecoute` et vérification des réglages

**Files:**
- Create: `outils/check_sdkconfig.sh`
- Create: `ecoute/CMakeLists.txt`, `ecoute/sdkconfig.defaults`, `ecoute/main/CMakeLists.txt`, `ecoute/main/app_main.c`

**Interfaces:**
- Consumes : composants `telink` et `mesh` (Tasks 1-2), trouvés par `EXTRA_COMPONENT_DIRS`.
- Produces : le projet ESP-IDF `ecoute` (`build/amaran_ecoute.elf`) ; `outils/check_sdkconfig.sh`, qui vérifie `ecoute/` et, plus tard, `firmware/`.

- [ ] **Step 1 : écrire le vérificateur de réglages.**

`outils/check_sdkconfig.sh`, repris du SmartButton :

```bash
#!/usr/bin/env bash
# Verifie que chaque symbole des sdkconfig.defaults* existe dans les Kconfig
# d'ESP-IDF (et d'esp-matter si ESP_MATTER_PATH est pose). Un symbole inconnu
# est ignore EN SILENCE par idf.py. Repris du SmartButton.
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
exit $rc
```

- [ ] **Step 2 : écrire les réglages et les vérifier.**

`ecoute/sdkconfig.defaults` :

```
# Firmware de reconnaissance (phase 0) : ESP32-C6, Bluetooth Mesh sur NimBLE,
# sans Matter. Chaque symbole est verifie par outils/check_sdkconfig.sh.

CONFIG_IDF_TARGET="esp32c6"
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
CONFIG_PARTITION_TABLE_SINGLE_APP_LARGE=y

# Console et journaux sur l'USB natif : la C6 SuperMini n'a pas de pont USB-serie.
CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y

# Bluetooth : NimBLE, comme l'exigera Matter sur Thread en phase 1.
CONFIG_BT_ENABLED=y
CONFIG_BT_NIMBLE_ENABLED=y
# Annonces 4.2 seulement (les lampes ne font pas de 5.0). Doublons filtres par
# adresse ET donnees, sinon le controleur jette des messages Mesh.
CONFIG_BT_LE_SCAN_DUPL_TYPE_DATA_DEVICE=y
CONFIG_BT_LE_50_FEATURE_SUPPORT=n
CONFIG_BT_NIMBLE_50_FEATURE_SUPPORT=n

# Bluetooth Mesh : noeud qui entre seul dans le reseau des lampes (spec 5.1).
CONFIG_BLE_MESH=y
CONFIG_BLE_MESH_NODE=y
CONFIG_BLE_MESH_PB_ADV=y
CONFIG_BLE_MESH_PB_GATT=n
CONFIG_BLE_MESH_GATT_PROXY_SERVER=n
CONFIG_BLE_MESH_RELAY=n
CONFIG_BLE_MESH_FRIEND=n
CONFIG_BLE_MESH_LOW_POWER=n
# La pile ne persiste rien : on rentre dans le reseau a chaque demarrage depuis
# la NVS "amaran", et le plancher de sequence est tenu par notre code.
CONFIG_BLE_MESH_SETTINGS=n
CONFIG_BLE_MESH_SUBNET_COUNT=1
CONFIG_BLE_MESH_APP_KEY_COUNT=2
CONFIG_BLE_MESH_MODEL_KEY_COUNT=2
CONFIG_BLE_MESH_MODEL_GROUP_COUNT=4
CONFIG_BLE_MESH_CRPL=20
# Chaque emission garde un tampon pendant ses 3 copies : les 60 par defaut ne
# suffisent pas (amaran-bridge : "Out of network buffers").
CONFIG_BLE_MESH_ADV_BUF_COUNT=120
# Accepte l'IV Index +1 annonce sans drapeau de mise a jour (recuperation).
CONFIG_BLE_MESH_IVU_RECOVERY_IVI=y

# AES logiciel : l'AES materiel fait une allocation DMA par bloc, et la pile
# Mesh finit par s'arreter (amaran-bridge : "Encrypt failed").
CONFIG_MBEDTLS_HARDWARE_AES=n

CONFIG_ESP_MAIN_TASK_STACK_SIZE=4096
```

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && bash outils/check_sdkconfig.sh`
Expected : `-- ecoute/sdkconfig.defaults` puis `ok : tous les symboles existent`.

**Si un symbole est déclaré inconnu, ne pas le supprimer au jugé.** Chercher son nom actuel dans ESP-IDF :

```bash
/usr/bin/grep -rn "config <NOM_SANS_CONFIG_>" ~/esp/esp-idf/components
```

Puis remplacer le symbole et noter le changement dans le message de commit. Si aucun équivalent n'existe, s'arrêter et le signaler.

- [ ] **Step 3 : écrire le projet et le compiler.**

`ecoute/CMakeLists.txt` :

```cmake
# Firmware de reconnaissance (phase 0) : Bluetooth Mesh et console, sans Matter.
cmake_minimum_required(VERSION 3.16)
set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../components")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(amaran_ecoute)
```

`ecoute/main/CMakeLists.txt` :

```cmake
# Le composant main depend de tous les autres (regle d'ESP-IDF).
idf_component_register(SRCS "app_main.c"
                       INCLUDE_DIRS ".")
```

`ecoute/main/app_main.c` (squelette ; la tâche 6 le remplace) :

```c
// Firmware de reconnaissance (phase 0) : squelette.
#include "esp_log.h"
#include "nvs_flash.h"

static const char *TAG = "ecoute";

void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_LOGW(TAG, "NVS illisible : effacee (cles a recharger)");
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);
  ESP_LOGI(TAG, "firmware d'ecoute demarre");
}
```

Run (compter quelques minutes pour la première compilation) :

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py set-target esp32c6 && idf.py build
```

Expected : `Project build complete.` et `build/amaran_ecoute.bin` présent.

- [ ] **Step 4 : vérifier que les fichiers générés sont ignorés.**

Run: `git status --short`
Expected : `outils/check_sdkconfig.sh` et `ecoute/` avec ses seuls sources (`CMakeLists.txt`, `sdkconfig.defaults`, `main/…`). Ni `ecoute/build/`, ni `ecoute/sdkconfig`.

- [ ] **Step 5 : commit.**

```bash
chmod +x outils/check_sdkconfig.sh
git add outils/check_sdkconfig.sh ecoute
git commit -m "$(printf "Ajouter le squelette du firmware d'ecoute et le verificateur de reglages\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 6: Réglages en NVS (`config_amaran`)

**Files:**
- Create: `components/mesh/include/config_amaran.h`, `components/mesh/config_amaran.c`
- Modify: `components/mesh/CMakeLists.txt`, `ecoute/main/app_main.c`

**Interfaces:**
- Consumes : `texte_octets_vers_hex` (Task 2).
- Produces (`config_amaran.h`) :
  - `AMARAN_LAMPES_MAX` (2), `AMARAN_NOM_MAX` (32), `AMARAN_ADRESSE_MIN` (0x7F00), `AMARAN_ADRESSE_MAX` (0x7F7F) ;
  - `amaran_lampe_t { uint16_t adresse; uint8_t mac[6]; char nom[AMARAN_NOM_MAX]; }` ;
  - `amaran_config_t { bool cles_presentes; uint8_t netkey[16]; uint8_t appkey[16]; uint8_t devkey[16]; uint32_t iv; uint16_t adresse; uint32_t plancher_seq; uint8_t nb_lampes; amaran_lampe_t lampes[AMARAN_LAMPES_MAX]; }` ;
  - `esp_err_t config_charger(amaran_config_t *c);`
  - `esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]);`
  - `esp_err_t config_sauver_lampe(uint8_t index, const amaran_lampe_t *lampe);`
  - `esp_err_t config_sauver_iv(uint32_t iv);`
  - `esp_err_t config_sauver_adresse(uint16_t adresse);` : remet aussi le plancher à 0 ;
  - `esp_err_t config_sauver_plancher(uint32_t plancher);`
  - `esp_err_t config_oublier_cles(void);` : clés et lampes seulement ;
  - `void config_empreinte(const uint8_t cle[16], char sortie[9]);`

- [ ] **Step 1 : écrire `config_amaran`.**

`components/mesh/include/config_amaran.h` :

```c
// Reglages du pont en NVS, espace "amaran" (spec 5.2 et 5.4) : cles du reseau,
// IV Index, adresse de l'ESP32, plancher de sequence, lampes.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

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
  bool cles_presentes;
  uint8_t netkey[16];
  uint8_t appkey[16];
  uint8_t devkey[16];     // tiree au hasard une fois, jamais utilisee par les lampes
  uint32_t iv;            // IV Index de depart
  uint16_t adresse;       // adresse Mesh de l'ESP32
  uint32_t plancher_seq;  // la sequence repart de la au demarrage
  uint8_t nb_lampes;
  amaran_lampe_t lampes[AMARAN_LAMPES_MAX];
} amaran_config_t;

// Lit la NVS. Tire et sauve l'adresse et la cle d'appareil si elles manquent.
esp_err_t config_charger(amaran_config_t *c);
esp_err_t config_sauver_cles(const uint8_t netkey[16], const uint8_t appkey[16]);
esp_err_t config_sauver_lampe(uint8_t index, const amaran_lampe_t *lampe);
esp_err_t config_sauver_iv(uint32_t iv);
// Nouvelle adresse source : le plancher de sequence repart de 0.
esp_err_t config_sauver_adresse(uint16_t adresse);
esp_err_t config_sauver_plancher(uint32_t plancher);
// Efface les cles et les lampes ; garde adresse, plancher et IV Index.
esp_err_t config_oublier_cles(void);
// 8 premiers chiffres hexa (majuscules) du SHA-256 de la cle, et un NUL.
void config_empreinte(const uint8_t cle[16], char sortie[9]);
```

`components/mesh/config_amaran.c` :

```c
// Reglages du pont en NVS (espace "amaran"). Les cles n'en sortent jamais : la
// console n'affiche que leur empreinte.
#include "config_amaran.h"

#include <string.h>

#include "esp_random.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

#include "texte.h"

#define ESPACE "amaran"

_Static_assert(AMARAN_LAMPES_MAX == 2, "NOMS_LAMPES a completer");
static const char *const NOMS_LAMPES[AMARAN_LAMPES_MAX] = {"lampe0", "lampe1"};

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
  for (uint8_t i = 0; i < AMARAN_LAMPES_MAX; i++) {
    if (!lire_blob(h, NOMS_LAMPES[i], &c->lampes[i], sizeof(amaran_lampe_t))) {
      memset(&c->lampes[i], 0, sizeof(amaran_lampe_t));
    }
    c->lampes[i].nom[AMARAN_NOM_MAX - 1] = '\0';
    if (c->lampes[i].adresse != 0) c->nb_lampes++;
  }
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

esp_err_t config_sauver_lampe(uint8_t index, const amaran_lampe_t *lampe) {
  if (index >= AMARAN_LAMPES_MAX) return ESP_ERR_INVALID_ARG;
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_blob(h, NOMS_LAMPES[index], lampe, sizeof(*lampe)));
}

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
  err = nvs_set_u16(h, "adresse", adresse);
  // Nouvelle adresse source : les lampes n'en connaissent aucun compteur.
  if (err == ESP_OK) err = nvs_set_u32(h, "plancher", 0);
  return fermer(h, err);
}

esp_err_t config_sauver_plancher(uint32_t plancher) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  return fermer(h, nvs_set_u32(h, "plancher", plancher));
}

esp_err_t config_oublier_cles(void) {
  nvs_handle_t h;
  esp_err_t err = ouvrir(&h);
  if (err != ESP_OK) return err;
  err = effacer(h, "netkey");
  if (err == ESP_OK) err = effacer(h, "appkey");
  for (uint8_t i = 0; i < AMARAN_LAMPES_MAX && err == ESP_OK; i++) err = effacer(h, NOMS_LAMPES[i]);
  return fermer(h, err);
}

void config_empreinte(const uint8_t cle[16], char sortie[9]) {
  uint8_t condensat[32];
  mbedtls_sha256(cle, 16, condensat, 0);
  texte_octets_vers_hex(condensat, 4, sortie);
}
```

`components/mesh/CMakeLists.txt` devient :

```cmake
idf_component_register(SRCS "texte.c" "crochet_tri.c" "config_amaran.c"
                       INCLUDE_DIRS "include"
                       REQUIRES telink
                       PRIV_REQUIRES nvs_flash mbedtls)
```

`ecoute/main/app_main.c` devient :

```c
// Firmware de reconnaissance (phase 0) : reglages lus au demarrage.
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"

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
  ESP_ERROR_CHECK(config_charger(&cfg));
  char en[9] = "-", ea[9] = "-";
  if (cfg.cles_presentes) {
    config_empreinte(cfg.netkey, en);
    config_empreinte(cfg.appkey, ea);
  }
  ESP_LOGI(TAG, "adresse 0x%04x, IV 0x%08lx, cles %s/%s, %u lampe(s)", cfg.adresse, (unsigned long)cfg.iv, en, ea,
           (unsigned)cfg.nb_lampes);
}
```

- [ ] **Step 2 : compiler.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build`
Expected : `Project build complete.`, sans avertissement dans `components/mesh`.

- [ ] **Step 3 : les tests du Mac restent verts.**

Run: `sh tests/hote/lancer.sh`
Expected : `tests hote : tout est vert`.

- [ ] **Step 4 : commit.**

```bash
git add components/mesh ecoute/main/app_main.c
git commit -m "$(printf 'Ranger les reglages du pont en NVS, cles sous empreinte\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 7: Adhésion au réseau et file d'émission

> **Note (30/09/2026) : le code du dépôt fait foi.** Les blocs de code des tâches 7 à 10 ont été dépassés par les revues. Par exemple `SEQ_LIMITE` vaut `0x700000` dans `components/mesh/mesh_amaran.c`, et non `0xF00000` comme dans le bloc ci-dessous. Ces blocs restent la trace de la démarche, pas la référence.

**Files:**
- Create: `components/mesh/include/mesh_amaran.h`, `components/mesh/mesh_amaran.c`
- Create: `components/mesh/hote_ble.h`, `components/mesh/hote_ble.c`
- Create: `components/mesh/crochet.h`, `components/mesh/crochet.c` (version minimale, remplacée à la tâche 8)
- Modify: `components/mesh/CMakeLists.txt`, `ecoute/main/app_main.c`

**Interfaces:**
- Consumes : `config_amaran.h` (Task 6), `telink.h` (Task 1).
- Produces (`mesh_amaran.h`) :
  - `MESH_GROUPE_TOUS` (0xC000), `MESH_REPETITIONS_ORDRE` (2), `MESH_REPETITIONS_ETAT` (1) ;
  - `mesh_ev_type_t { MESH_EV_ETAT_LAMPE, MESH_EV_ACCES, MESH_EV_BALISE, MESH_EV_IV_CHANGE }` ;
  - `mesh_evenement_t { mesh_ev_type_t type; int64_t quand_us; uint16_t src; uint16_t dst; int8_t lampe; uint8_t len; uint8_t acces[16]; uint32_t iv; uint8_t flags; }` ;
  - `mesh_stats_t` (champs ci-dessous) ;
  - `esp_err_t mesh_demarrer(const amaran_config_t *cfg);`
  - `bool mesh_pret(void);`
  - `esp_err_t mesh_envoyer(uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions);`
  - `QueueHandle_t mesh_file_evenements(void);`
  - `void mesh_ecoute_detaillee(bool oui);`
  - `void mesh_lire_stats(mesh_stats_t *stats);`
  - `uint32_t mesh_iv_courant(void);`
  - `uint32_t mesh_sequence(void);`
- Produces (privé, `crochet.h`) : `esp_err_t crochet_demarrer(const amaran_config_t *cfg);`, `QueueHandle_t crochet_file(void);`, `void crochet_lire_stats(mesh_stats_t *stats);`, `void crochet_ecoute_detaillee(bool oui);`
- Produces (privé, `hote_ble.h`) : `esp_err_t hote_ble_demarrer(void);`

- [ ] **Step 1 : écrire l'API publique.**

`components/mesh/include/mesh_amaran.h` :

```c
// Pont amaran : adhesion au reseau Bluetooth Mesh des lampes, emission des
// trames Telink et evenements du crochet de reception (spec 5.1 a 5.7).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#include "config_amaran.h"
#include "telink.h"

#define MESH_GROUPE_TOUS 0xC000
#define MESH_REPETITIONS_ORDRE 2
#define MESH_REPETITIONS_ETAT 1

typedef enum {
  MESH_EV_ETAT_LAMPE,  // trame 0x26 d'une de nos lampes
  MESH_EV_ACCES,       // autre message d'acces dechiffre (ecoute detaillee)
  MESH_EV_BALISE,      // balise de notre reseau (ecoute detaillee)
  MESH_EV_IV_CHANGE,   // IV Index change par la pile : a sauver
} mesh_ev_type_t;

typedef struct {
  mesh_ev_type_t type;
  int64_t quand_us;
  uint16_t src;
  uint16_t dst;
  int8_t lampe;       // index 0..AMARAN_LAMPES_MAX-1, ou -1
  uint8_t len;        // octets utiles de acces
  uint8_t acces[16];  // opcode puis charge
  uint32_t iv;        // MESH_EV_BALISE, MESH_EV_IV_CHANGE
  uint8_t flags;      // MESH_EV_BALISE
} mesh_evenement_t;

typedef struct {
  uint32_t annonces;          // messages Mesh vus sur les annonces
  uint32_t nid_reconnu;       // ... portant le NID de notre reseau
  uint32_t nid_inconnu;       // ... d'un autre reseau
  uint32_t netmic_faux;       // notre NID, mais NetMIC faux (IV Index ?)
  uint32_t acces_dechiffres;  // messages d'acces dechiffres avec l'AppKey
  uint32_t etats_lampes;      // dont trames 0x26 de nos lampes
  uint32_t balises_notres;
  uint32_t balises_autres;
  uint32_t file_pleine;       // evenements perdus
  uint32_t emis;              // messages partis (repetitions comptees une fois)
  uint32_t echecs_emission;
  int64_t derniere_balise_us;
  uint32_t derniere_balise_iv;
  uint8_t derniere_balise_flags;
  int64_t derniere_reponse_us[AMARAN_LAMPES_MAX];
} mesh_stats_t;

esp_err_t mesh_demarrer(const amaran_config_t *cfg);
bool mesh_pret(void);
// repetitions : MESH_REPETITIONS_ORDRE pour un ordre, MESH_REPETITIONS_ETAT
// pour une demande d'etat.
esp_err_t mesh_envoyer(uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions);
QueueHandle_t mesh_file_evenements(void);
void mesh_ecoute_detaillee(bool oui);
void mesh_lire_stats(mesh_stats_t *stats);
uint32_t mesh_iv_courant(void);
uint32_t mesh_sequence(void);
```

- [ ] **Step 2 : écrire l'hôte NimBLE et le crochet minimal.**

`components/mesh/hote_ble.h` :

```c
#pragma once

#include "esp_err.h"

// Demarre l'hote NimBLE et attend sa synchronisation avec le controleur.
esp_err_t hote_ble_demarrer(void);
```

`components/mesh/hote_ble.c` :

```c
// Hote NimBLE pour le Bluetooth Mesh, d'apres l'exemple d'ESP-IDF
// examples/bluetooth/esp_ble_mesh/common_components/example_init. Fichier a
// part : les en-tetes NimBLE et ceux de la pile Mesh ne se melangent pas.
#include "hote_ble.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"

static const char *TAG = "hote_ble";
static SemaphoreHandle_t s_synchro;

void ble_store_config_init(void);

static void reinitialise(int raison) { ESP_LOGW(TAG, "hote NimBLE reinitialise (raison %d)", raison); }

static void synchronise(void) {
  const int rc = ble_hs_util_ensure_addr(0);
  if (rc != 0) ESP_LOGE(TAG, "pas d'adresse BLE (%d)", rc);
  xSemaphoreGive(s_synchro);
}

static void tache_hote(void *arg) {
  (void)arg;
  nimble_port_run();
  nimble_port_freertos_deinit();
}

esp_err_t hote_ble_demarrer(void) {
  s_synchro = xSemaphoreCreateBinary();
  if (!s_synchro) return ESP_ERR_NO_MEM;
  const esp_err_t err = nimble_port_init();
  if (err != ESP_OK) return err;
  ble_hs_cfg.reset_cb = reinitialise;
  ble_hs_cfg.sync_cb = synchronise;
  ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
  ble_store_config_init();
  nimble_port_freertos_init(tache_hote);
  xSemaphoreTake(s_synchro, portMAX_DELAY);
  return ESP_OK;
}
```

`components/mesh/crochet.h` (version de la tâche 7) :

```c
// Crochet de reception (prive au composant mesh).
#pragma once

#include <stdbool.h>

#include "config_amaran.h"
#include "mesh_amaran.h"

esp_err_t crochet_demarrer(const amaran_config_t *cfg);
QueueHandle_t crochet_file(void);
void crochet_lire_stats(mesh_stats_t *stats);
void crochet_ecoute_detaillee(bool oui);
```

`components/mesh/crochet.c` (version minimale ; la tâche 8 le remplace entièrement) :

```c
// Crochet de reception : file d'evenements et compteurs. Le dechiffrement et
// l'interception arrivent a la tache 8.
#include "crochet.h"

#include <string.h>

#define FILE_EVENEMENTS 32

static QueueHandle_t s_file;
static mesh_stats_t s_st;
static volatile bool s_detail;

esp_err_t crochet_demarrer(const amaran_config_t *cfg) {
  (void)cfg;
  s_file = xQueueCreate(FILE_EVENEMENTS, sizeof(mesh_evenement_t));
  return s_file ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t crochet_file(void) { return s_file; }

void crochet_lire_stats(mesh_stats_t *stats) { memcpy(stats, &s_st, sizeof(*stats)); }

void crochet_ecoute_detaillee(bool oui) { s_detail = oui; }
```

- [ ] **Step 3 : écrire l'adhésion et la file d'émission.**

`components/mesh/mesh_amaran.c` :

```c
// Adhesion au reseau Bluetooth Mesh des lampes et file d'emission (spec 5.1,
// 5.4, 5.6). Sequence d'adhesion reprise d'amaran-bridge (Kevin Schaich, MIT) :
// role noeud, bt_mesh_provision(), puis AppKey et liaison au modele vendeur a
// la fin du provisionnement.
#include "mesh_amaran.h"

#include <inttypes.h>
#include <string.h>

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
#include "local.h"      // bt_mesh_node_local_app_key_add, bt_mesh_node_bind_app_key_to_model
#include "mesh/main.h"  // bt_mesh_provision
#include "net.h"        // bt_mesh : seq, iv_index

#include "crochet.h"
#include "hote_ble.h"

static const char *TAG = "mesh";

#define NET_IDX 0x0000
#define APP_IDX 0x0000
#define TTL 3
#define ECART_MS 70          // entre deux messages et entre deux repetitions
#define FILE_TX 16
#define BLOC_SEQ 256         // le plancher sauve devance toujours la sequence
#define SEQ_LIMITE 0xF00000  // au-dela : adresse suivante (spec 5.4)

typedef struct {
  uint16_t dst;
  uint8_t repetitions;
  uint8_t trame[TELINK_TAILLE];
} message_tx_t;

static amaran_config_t s_cfg;
static QueueHandle_t s_tx;
static volatile bool s_pret;
static uint32_t s_plancher_sauve;
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
  // La sequence repart au-dessus de tout ce qui a pu partir avant (5.4).
  bt_mesh.seq = s_cfg.plancher_seq;
  s_plancher_sauve = s_cfg.plancher_seq + BLOC_SEQ;
  config_sauver_plancher(s_plancher_sauve);
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

static void verifier_plancher(uint32_t a_consommer) {
  if (bt_mesh.seq + a_consommer >= s_plancher_sauve) {
    s_plancher_sauve = bt_mesh.seq + a_consommer + BLOC_SEQ;
    config_sauver_plancher(s_plancher_sauve);
  }
}

static void tache_tx(void *arg) {
  (void)arg;
  message_tx_t m;
  for (;;) {
    if (xQueueReceive(s_tx, &m, portMAX_DELAY) != pdTRUE) continue;
    while (!s_pret) vTaskDelay(pdMS_TO_TICKS(100));
    verifier_plancher(m.repetitions);
    esp_ble_mesh_msg_ctx_t ctx = {
        .net_idx = NET_IDX,
        .app_idx = APP_IDX,
        .addr = m.dst,
        .send_ttl = TTL,
    };
    esp_err_t err = ESP_OK;
    for (uint8_t r = 0; r < m.repetitions; r++) {
      err = esp_ble_mesh_server_model_send_msg(&s_vendeur[0], &ctx, TELINK_OPCODE, TELINK_TAILLE, m.trame);
      if (err != ESP_OK) break;
      if (r + 1 < m.repetitions) vTaskDelay(pdMS_TO_TICKS(ECART_MS));
    }
    if (err == ESP_OK) {
      s_emis++;
    } else {
      s_echecs++;
      ESP_LOGW(TAG, "envoi vers 0x%04x refuse : %s", m.dst, esp_err_to_name(err));
    }
    vTaskDelay(pdMS_TO_TICKS(ECART_MS));
  }
}

// --- API

esp_err_t mesh_demarrer(const amaran_config_t *cfg) {
  if (!cfg->cles_presentes) return ESP_ERR_INVALID_STATE;
  s_cfg = *cfg;
  if (s_cfg.plancher_seq > SEQ_LIMITE) {
    const uint16_t suivante =
        s_cfg.adresse >= AMARAN_ADRESSE_MAX ? AMARAN_ADRESSE_MIN : (uint16_t)(s_cfg.adresse + 1);
    ESP_LOGW(TAG, "sequence 0x%06" PRIx32 " presque epuisee : adresse 0x%04x", s_cfg.plancher_seq, suivante);
    config_sauver_adresse(suivante);
    esp_restart();
  }
  s_tx = xQueueCreate(FILE_TX, sizeof(message_tx_t));
  if (!s_tx) return ESP_ERR_NO_MEM;
  esp_err_t err = crochet_demarrer(&s_cfg);
  if (err != ESP_OK) return err;
  err = hote_ble_demarrer();
  if (err != ESP_OK) return err;
  esp_read_mac(s_uuid, ESP_MAC_BT);
  // Relais coupe : la pile avertirait pour chaque message qu'elle ne relaie pas.
  esp_log_level_set("BLE_MESH", ESP_LOG_ERROR);
  esp_ble_mesh_register_prov_callback(rappel_prov);
  esp_ble_mesh_register_config_server_callback(rappel_cfg_srv);
  esp_ble_mesh_register_custom_model_callback(rappel_modele);
  err = esp_ble_mesh_init(&s_prov, &s_composition);
  if (err != ESP_OK) return err;
  if (xTaskCreate(tache_tx, "amaran_tx", 3072, NULL, 5, NULL) != pdPASS) return ESP_ERR_NO_MEM;
  // Le role noeud doit etre actif pour que bt_mesh_provision() tienne.
  err = esp_ble_mesh_node_prov_enable(ESP_BLE_MESH_PROV_ADV);
  if (err != ESP_OK) return err;
  const int rc = bt_mesh_provision(s_cfg.netkey, NET_IDX, 0, s_cfg.iv, s_cfg.adresse, s_cfg.devkey);
  esp_ble_mesh_node_prov_disable(ESP_BLE_MESH_PROV_ADV);
  if (rc) {
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
```

`components/mesh/CMakeLists.txt` devient :

```cmake
idf_component_register(
    SRCS "texte.c" "crochet_tri.c" "config_amaran.c" "hote_ble.c" "crochet.c" "mesh_amaran.c"
    INCLUDE_DIRS "include"
    PRIV_INCLUDE_DIRS
        "."
        # En-tetes internes de la pile Bluetooth Mesh : aucune API publique ne
        # permet d'entrer dans un reseau existant ni de dechiffrer a cote.
        "${IDF_PATH}/components/bt/esp_ble_mesh/core/include"
        "${IDF_PATH}/components/bt/esp_ble_mesh/core"
        "${IDF_PATH}/components/bt/esp_ble_mesh/common/include"
    REQUIRES telink
    PRIV_REQUIRES nvs_flash mbedtls bt esp_timer)
```

`ecoute/main/app_main.c` devient :

```c
// Firmware de reconnaissance (phase 0) : reglages, puis entree dans le reseau.
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"
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
  ESP_ERROR_CHECK(config_charger(&cfg));
  if (!cfg.cles_presentes) {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
    return;
  }
  err = mesh_demarrer(&cfg);
  if (err != ESP_OK) ESP_LOGE(TAG, "Bluetooth Mesh non demarre : %s", esp_err_to_name(err));
}
```

- [ ] **Step 4 : compiler et mesurer.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build && idf.py size`
Expected : `Project build complete.`, puis une taille d'image sous 1,5 Mo (`SINGLE_APP_LARGE`).

Si un en-tête interne est introuvable (`fatal error: xxx.h: No such file`) :
1. le trouver : `find ~/esp/esp-idf/components/bt/esp_ble_mesh -name xxx.h` ;
2. ajouter son dossier à `PRIV_INCLUDE_DIRS` ;
3. le noter dans le commit.

**Ne rien modifier dans `~/esp/esp-idf`.**

- [ ] **Step 5 : commit.**

```bash
git add components/mesh ecoute/main/app_main.c
git commit -m "$(printf 'Entrer dans le reseau des lampes et emettre au bon rythme\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 8: Crochet de réception (`--wrap`) et déchiffrement

> Voir la note de la tâche 7 : le code du dépôt fait foi, pas les blocs de cette tâche.

**Files:**
- Modify: `components/mesh/crochet.h`, `components/mesh/CMakeLists.txt`
- Replace: `components/mesh/crochet.c`

**Interfaces:**
- Consumes : `crochet_tri.h` (Task 2), structures internes `bt_mesh`, `struct bt_mesh_subnet` (`keys[k].nid`, `.enc`, `.privacy`, `.net_id`, `kr_phase`, `net_idx`), `struct bt_mesh_app_key` (`net_idx`, `updated`, `keys[k].id`, `.val`) ; fonctions `bt_mesh_net_obfuscate`, `bt_mesh_net_decrypt`, `bt_mesh_app_decrypt`, `bt_mesh_rx_netkey_size/get`, `bt_mesh_rx_appkey_size/get`.
- Produces (`crochet.h`) :
  - `int crochet_dechiffrer_reseau(const uint8_t enc[16], const uint8_t privacy[16], uint32_t iv, uint8_t *pdu, size_t *len);` : en place, 0 si OK ; `*len` perd le NetMIC ;
  - `int crochet_dechiffrer_acces(const uint8_t appkey[16], const uint8_t *clair, size_t len, uint32_t iv, const uint8_t *ad, uint8_t *acces, size_t *acces_len);` : 0 si OK.
- Produces (édition de liens) : `__wrap_bt_mesh_generic_net_recv` et `__wrap_bt_mesh_beacon_recv`.

- [ ] **Step 1 : déclarer le déchiffrement partagé.**

Dans `components/mesh/crochet.h`, ajouter `#include <stddef.h>` et `#include <stdint.h>` sous `#include <stdbool.h>`, puis à la fin :

```c
// Dechiffrement a cles explicites, partage avec l'autotest (tache 9).
// Reseau : en place ; *len perd le NetMIC. Rend 0 si le NetMIC est bon.
int crochet_dechiffrer_reseau(const uint8_t enc[16], const uint8_t privacy[16], uint32_t iv, uint8_t *pdu,
                              size_t *len);
// Acces (message non segmente) d'un message reseau en clair ; ad = Label UUID
// pour une adresse virtuelle, NULL sinon. Rend 0 si le TransMIC est bon.
int crochet_dechiffrer_acces(const uint8_t appkey[16], const uint8_t *clair, size_t len, uint32_t iv,
                             const uint8_t *ad, uint8_t *acces, size_t *acces_len);
```

- [ ] **Step 2 : remplacer `components/mesh/crochet.c`.**

```c
// Crochet de reception (spec 5.5). Les lampes adressent leurs etats a 0x0001
// (amaran Desktop), et la pile jette ces messages. On intercepte ses deux
// points d'entree par l'editeur de liens (-Wl,--wrap, voir CMakeLists.txt) :
// la pile traite le message comme d'habitude, puis on dechiffre une COPIE a
// cote. Ne jamais rappeler bt_mesh_net_decode() : il inscrit le message dans
// le cache anti-doublon, et la pile rejetterait l'original.
#include "crochet.h"

#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#include "access.h"  // bt_mesh_rx_netkey_*, bt_mesh_rx_appkey_*
#include "crypto.h"  // bt_mesh_net_obfuscate, bt_mesh_net_decrypt, bt_mesh_app_decrypt
#include "mesh/buf.h"
#include "net.h"

#include "crochet_tri.h"

#define FILE_EVENEMENTS 32
#define PDU_MAX 32
#define BALISE_MAX 24
#define ECHANTILLONS 4
#define MIC_ACCES 4

static QueueHandle_t s_file;
static uint16_t s_lampes[AMARAN_LAMPES_MAX];
static volatile bool s_detail;
static mesh_stats_t s_st;
static uint32_t s_iv_connu;

// Messages de notre reseau au NetMIC faux : matiere de `mesh iv cherche`.
static struct {
  uint8_t pdu[PDU_MAX];
  size_t len;
} s_echantillons[ECHANTILLONS];
static int s_echantillon_suivant;

static void publier(const mesh_evenement_t *ev) {
  if (xQueueSend(s_file, ev, 0) != pdTRUE) s_st.file_pleine++;
}

esp_err_t crochet_demarrer(const amaran_config_t *cfg) {
  for (int i = 0; i < AMARAN_LAMPES_MAX; i++) s_lampes[i] = cfg->lampes[i].adresse;
  s_iv_connu = cfg->iv;
  s_file = xQueueCreate(FILE_EVENEMENTS, sizeof(mesh_evenement_t));
  return s_file ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t crochet_file(void) { return s_file; }

void crochet_lire_stats(mesh_stats_t *stats) { memcpy(stats, &s_st, sizeof(*stats)); }

void crochet_ecoute_detaillee(bool oui) { s_detail = oui; }

int crochet_dechiffrer_reseau(const uint8_t enc[16], const uint8_t privacy[16], uint32_t iv, uint8_t *pdu,
                              size_t *len) {
  struct net_buf_simple buf;
  if (bt_mesh_net_obfuscate(pdu, iv, privacy)) return -1;
  net_buf_simple_init_with_data(&buf, pdu, *len);
  if (bt_mesh_net_decrypt(enc, &buf, iv, false, false)) return -2;
  *len = buf.len;
  return 0;
}

int crochet_dechiffrer_acces(const uint8_t appkey[16], const uint8_t *clair, size_t len, uint32_t iv,
                             const uint8_t *ad, uint8_t *acces, size_t *acces_len) {
  tri_entete_t e = {0};
  if (!tri_lire_entete(clair, len, &e) || len < TRI_ENTETE_RESEAU + 1 + 1 + MIC_ACCES) return -1;
  const size_t n = len - TRI_ENTETE_RESEAU - 1 - MIC_ACCES;
  if (n > *acces_len) return -1;
  // La pile lit le TransMIC juste apres les n octets chiffres.
  struct net_buf_simple in, out;
  net_buf_simple_init_with_data(&in, (void *)(clair + TRI_ENTETE_RESEAU + 1), n);
  net_buf_simple_init_with_data(&out, acces, *acces_len);
  out.len = 0;
  if (bt_mesh_app_decrypt(appkey, false, 0, &in, &out, ad, e.src, e.dst, e.seq, iv)) return -2;
  *acces_len = out.len;
  return 0;
}

static uint32_t iv_du_message(uint8_t ivi) {
  const uint32_t iv = bt_mesh.iv_index;
  return (ivi != (iv & 0x01)) ? iv - 1 : iv;
}

static void garder_echantillon(const uint8_t *pdu, size_t len) {
  memcpy(s_echantillons[s_echantillon_suivant].pdu, pdu, len);
  s_echantillons[s_echantillon_suivant].len = len;
  s_echantillon_suivant = (s_echantillon_suivant + 1) % ECHANTILLONS;
}

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
    ev.lampe = (int8_t)l;
    s_st.etats_lampes++;
    s_st.derniere_reponse_us[l] = ev.quand_us;
    publier(&ev);
  } else if (s_detail) {
    publier(&ev);
  }
}

static void traiter(const uint8_t *pdu, size_t len) {
  s_st.annonces++;
  const uint8_t nid = pdu[0] & 0x7F;
  const uint32_t iv = iv_du_message(pdu[0] >> 7);
  bool reconnu = false;
  for (size_t i = 0; i < bt_mesh_rx_netkey_size(); i++) {
    struct bt_mesh_subnet *sub = bt_mesh_rx_netkey_get(i);
    if (!sub || sub->net_idx == BLE_MESH_KEY_UNUSED) continue;
    for (int k = 0; k < 2; k++) {
      if (k == 1 && sub->kr_phase == BLE_MESH_KR_NORMAL) break;
      if (sub->keys[k].nid != nid) continue;
      if (!reconnu) {
        reconnu = true;
        s_st.nid_reconnu++;
      }
      uint8_t clair[PDU_MAX];
      size_t n = len;
      memcpy(clair, pdu, len);
      if (crochet_dechiffrer_reseau(sub->keys[k].enc, sub->keys[k].privacy, iv, clair, &n)) {
        s_st.netmic_faux++;
        garder_echantillon(pdu, len);
        continue;
      }
      tri_entete_t e = {0};
      if (!tri_lire_entete(clair, n, &e) || e.ctl || n <= TRI_ENTETE_RESEAU) return;
      tri_transport_t t;
      tri_lire_transport(clair[TRI_ENTETE_RESEAU], &t);
      if (t.segmente || !t.akf) return;
      for (size_t j = 0; j < bt_mesh_rx_appkey_size(); j++) {
        struct bt_mesh_app_key *cle = bt_mesh_rx_appkey_get(j);
        if (!cle || cle->net_idx != sub->net_idx) continue;
        const struct bt_mesh_app_keys *ak = (k == 1 && cle->updated) ? &cle->keys[1] : &cle->keys[0];
        if (ak->id != t.aid) continue;
        uint8_t acces[16];
        size_t na = sizeof(acces);
        if (crochet_dechiffrer_acces(ak->val, clair, n, iv, NULL, acces, &na) == 0) {
          traiter_acces(&e, acces, na);
          return;
        }
      }
      return;
    }
  }
  if (!reconnu) s_st.nid_inconnu++;
}

void __real_bt_mesh_generic_net_recv(struct net_buf_simple *data, struct bt_mesh_net_rx *rx,
                                     enum bt_mesh_net_if net_if);

void __wrap_bt_mesh_generic_net_recv(struct net_buf_simple *data, struct bt_mesh_net_rx *rx,
                                     enum bt_mesh_net_if net_if) {
  uint8_t copie[PDU_MAX];
  const size_t n = data->len;
  const bool garder = s_file && net_if == BLE_MESH_NET_IF_ADV && n >= TRI_ENTETE_RESEAU + 1 + MIC_ACCES &&
                      n <= sizeof(copie);
  if (garder) memcpy(copie, data->data, n);
  __real_bt_mesh_generic_net_recv(data, rx, net_if);
  if (garder) traiter(copie, n);
}

void __real_bt_mesh_beacon_recv(struct net_buf_simple *buf, int8_t rssi);

void __wrap_bt_mesh_beacon_recv(struct net_buf_simple *buf, int8_t rssi) {
  uint8_t copie[BALISE_MAX];
  const size_t n = buf->len;
  const bool garder = s_file && n <= sizeof(copie);
  if (garder) memcpy(copie, buf->data, n);
  __real_bt_mesh_beacon_recv(buf, rssi);
  if (!garder) return;
  tri_balise_t b;
  if (tri_lire_balise(copie, n, &b)) {
    struct bt_mesh_subnet *sub = bt_mesh_rx_netkey_size() ? bt_mesh_rx_netkey_get(0) : NULL;
    if (sub && sub->net_idx != BLE_MESH_KEY_UNUSED && memcmp(sub->keys[0].net_id, b.net_id, sizeof(b.net_id)) == 0) {
      s_st.balises_notres++;
      s_st.derniere_balise_us = esp_timer_get_time();
      s_st.derniere_balise_iv = b.iv_index;
      s_st.derniere_balise_flags = b.flags;
      if (s_detail) {
        mesh_evenement_t ev = {
            .type = MESH_EV_BALISE, .quand_us = s_st.derniere_balise_us, .lampe = -1, .iv = b.iv_index,
            .flags = b.flags,
        };
        publier(&ev);
      }
    } else {
      s_st.balises_autres++;
    }
  }
  if (bt_mesh.iv_index != s_iv_connu) {
    s_iv_connu = bt_mesh.iv_index;
    mesh_evenement_t ev = {.type = MESH_EV_IV_CHANGE, .quand_us = esp_timer_get_time(), .lampe = -1, .iv = s_iv_connu};
    publier(&ev);
  }
}
```

- [ ] **Step 3 : poser l'interception.**

À la fin de `components/mesh/CMakeLists.txt`, ajouter :

```cmake
# Crochet de reception (spec 5.5) : la pile appelle nos enveloppes a la place
# de ses propres fonctions, sans que rien ne soit modifie dans ESP-IDF.
target_link_libraries(${COMPONENT_LIB} INTERFACE
    "-Wl,--wrap=bt_mesh_generic_net_recv"
    "-Wl,--wrap=bt_mesh_beacon_recv")
```

- [ ] **Step 4 : compiler et vérifier l'interception dans le binaire.**

Run :

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build && \
riscv32-esp-elf-objdump -d build/amaran_ecoute.elf > "${TMPDIR:-/tmp}/ecoute.dis" && \
for f in bt_mesh_generic_net_recv bt_mesh_beacon_recv; do
  echo "$f : enveloppe $(/usr/bin/grep -c "<__wrap_$f>" "${TMPDIR:-/tmp}/ecoute.dis"), original $(/usr/bin/grep -c "<$f>" "${TMPDIR:-/tmp}/ecoute.dis")"
done
```

Chaque compte inclut l'étiquette de la fonction (`… <nom>:`). Les renvois comptent quelle que soit la forme de l'appel : `jal`, saut `j`, ou `jalr` annoté.

Expected, pour chacune des deux fonctions :
- enveloppe ≥ 2 : son étiquette, plus au moins un appel depuis `scan.c` ;
- original ≥ 2 : son étiquette, plus au moins un appel depuis notre enveloppe.

Si l'enveloppe n'est jamais appelée, le crochet est muet : s'arrêter et le signaler. Le repli est le patch d'amaran-bridge, sur une copie d'ESP-IDF propre au projet ; c'est une décision à prendre avec Djoko.

- [ ] **Step 5 : commit.**

```bash
git add components/mesh
git commit -m "$(printf "Capter les etats des lampes par un crochet --wrap sans toucher ESP-IDF\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 9: Recherche d'IV Index et autotest

> Voir la note de la tâche 7 : le code du dépôt fait foi, pas les blocs de cette tâche.

**Files:**
- Create: `components/mesh/autotest.c`
- Modify: `components/mesh/crochet.h`, `components/mesh/crochet.c`, `components/mesh/include/mesh_amaran.h`, `components/mesh/mesh_amaran.c`, `components/mesh/CMakeLists.txt`

**Interfaces:**
- Consumes : `crochet_dechiffrer_reseau`, `crochet_dechiffrer_acces` (Task 8) ; `bt_mesh_k2`, `bt_mesh_k3`, `bt_mesh_app_id` (`crypto.h`) ; `tri_lire_balise` (Task 2) ; `texte_hex_vers_octets` (Task 2).
- Produces :
  - `int crochet_chercher_iv(uint32_t max, uint32_t *trouve);` : 0 trouvé, 1 hors de la plage, 2 aucun échantillon, -1 pas de clé ;
  - `int mesh_iv_chercher(uint32_t max, uint32_t *trouve);`
  - `int mesh_autotest(void);` : nombre d'échecs.

- [ ] **Step 1 : la recherche d'IV Index.**

Dans `components/mesh/crochet.h`, ajouter à la fin :

```c
// Cherche l'IV Index de 0 a max (max <= 0xFFFFFF) sur les messages au NetMIC
// faux gardes par le crochet. 0 : trouve ; 1 : hors de la plage ; 2 : aucun
// message garde ; -1 : pas de cle reseau.
int crochet_chercher_iv(uint32_t max, uint32_t *trouve);
```

Dans `components/mesh/crochet.c`, ajouter `#include "freertos/task.h"` après `#include "freertos/queue.h"`, puis à la fin du fichier :

```c
int crochet_chercher_iv(uint32_t max, uint32_t *trouve) {
  struct bt_mesh_subnet *sub = bt_mesh_rx_netkey_size() ? bt_mesh_rx_netkey_get(0) : NULL;
  if (!sub || sub->net_idx == BLE_MESH_KEY_UNUSED) return -1;
  for (int e = 0; e < ECHANTILLONS; e++) {
    const size_t len = s_echantillons[e].len;
    if (len == 0) continue;
    const uint8_t ivi = s_echantillons[e].pdu[0] >> 7;
    uint32_t essais = 0;
    for (uint32_t iv = ivi; iv <= max; iv += 2) {  // meme parite que le bit IVI
      uint8_t essai[PDU_MAX];
      size_t n = len;
      memcpy(essai, s_echantillons[e].pdu, len);
      if (crochet_dechiffrer_reseau(sub->keys[0].enc, sub->keys[0].privacy, iv, essai, &n) == 0) {
        *trouve = iv;
        return 0;
      }
      if (++essais % 1024 == 0) vTaskDelay(1);  // laisser tourner les autres taches
    }
    return 1;
  }
  return 2;
}
```

Dans `components/mesh/include/mesh_amaran.h`, ajouter à la fin :

```c
// Cherche l'IV Index du reseau de 0 a max (max <= 0xFFFFFF), voir crochet.h.
int mesh_iv_chercher(uint32_t max, uint32_t *trouve);
// Passe les exemples chiffres de la specification Mesh ; rend le nombre d'echecs.
int mesh_autotest(void);
```

Dans `components/mesh/mesh_amaran.c`, ajouter à la fin :

```c
int mesh_iv_chercher(uint32_t max, uint32_t *trouve) { return crochet_chercher_iv(max, trouve); }
```

- [ ] **Step 2 : l'autotest.**

`components/mesh/autotest.c` :

```c
// Autotest du dechiffrement avec les exemples chiffres de la specification
// Bluetooth Mesh (8.3.1, 8.3.22, 8.4.3), releves dans les tests unitaires de
// BlueZ (unit/test-mesh-crypto.c). Passe par les memes fonctions que le crochet.
#include <stdio.h>
#include <string.h>

#include "crypto.h"  // bt_mesh_k2, bt_mesh_k3, bt_mesh_app_id

#include "crochet.h"
#include "crochet_tri.h"
#include "mesh_amaran.h"
#include "texte.h"

static int s_echecs;

static void verifie(bool ok, const char *quoi) {
  printf("  %s %s\n", ok ? "ok   " : "ECHEC", quoi);
  if (!ok) s_echecs++;
}

static void hexa(const char *h, uint8_t *sortie, size_t n) {
  if (!texte_hex_vers_octets(h, sortie, n)) memset(sortie, 0, n);
}

int mesh_autotest(void) {
  s_echecs = 0;
  uint8_t netkey[16], appkey[16], enc[16], privacy[16], attendu[32], pdu[32], nid = 0;
  hexa("7dd7364cd842ad18c17c2b820c84c3d6", netkey, 16);
  hexa("63964771734fbd76e3b40519d1d94a48", appkey, 16);

  const uint8_t p = 0x00;
  verifie(bt_mesh_k2(netkey, &p, 1, &nid, enc, privacy) == 0 && nid == 0x68, "k2 : NID 0x68");
  hexa("0953fa93e7caac9638f58820220a398e", attendu, 16);
  verifie(memcmp(enc, attendu, 16) == 0, "k2 : cle de chiffrement");
  hexa("8b84eedec100067d670971dd2aa700cf", attendu, 16);
  verifie(memcmp(privacy, attendu, 16) == 0, "k2 : cle d'obfuscation");

  // 8.3.1, message #1 : controle, IV 0x12345678, NetMIC de 64 bits.
  size_t n = 28;
  hexa("68eca487516765b5e5bfdacbaf6cb7fb6bff871f035444ce83a670df", pdu, n);
  bool ok = crochet_dechiffrer_reseau(enc, privacy, 0x12345678, pdu, &n) == 0;
  hexa("68800000011201fffd034b50057e400000010000", attendu, 20);
  verifie(ok && n == 20 && memcmp(pdu, attendu, 20) == 0, "8.3.1 : message reseau");

  // 8.3.22, message #22 : acces par AppKey (AID 0x26), IV 0x12345677, vers une
  // adresse virtuelle (le Label UUID entre dans le chiffrement).
  n = 26;
  hexa("e8d85caecef1e3ed31f3fdcf88a411135fea55df730b6b28e255", pdu, n);
  ok = crochet_dechiffrer_reseau(enc, privacy, 0x12345677, pdu, &n) == 0;
  hexa("e80307080b1234b529663871b904d431526316ca48a0", attendu, 22);
  verifie(ok && n == 22 && memcmp(pdu, attendu, 22) == 0, "8.3.22 : message reseau");
  uint8_t aid = 0;
  verifie(bt_mesh_app_id(appkey, &aid) == 0 && aid == 0x26, "k4 : AID 0x26");
  uint8_t uuid[16], acces[16];
  hexa("0073e7e4d8b9440faf8415df4c56c0e1", uuid, 16);
  size_t na = sizeof(acces);
  ok = crochet_dechiffrer_acces(appkey, pdu, n, 0x12345677, uuid, acces, &na) == 0;
  hexa("d50a0048656c6c6f", attendu, 8);
  verifie(ok && na == 8 && memcmp(acces, attendu, 8) == 0, "8.3.22 : message d'acces");

  // 8.4.3 : balise reseau securisee.
  uint8_t balise[22], net_id[8];
  hexa("01003ecaff672f673370123456788ea261582f364f6f", balise, 22);
  tri_balise_t b;
  verifie(tri_lire_balise(balise, 22, &b) && b.iv_index == 0x12345678, "8.4.3 : IV Index");
  verifie(bt_mesh_k3(netkey, net_id) == 0 && memcmp(net_id, b.net_id, 8) == 0, "8.4.3 : NetID (k3)");

  printf("autotest : %d echec(s)\n", s_echecs);
  return s_echecs;
}
```

Dans `components/mesh/CMakeLists.txt`, ajouter `"autotest.c"` à la fin de la liste `SRCS`.

- [ ] **Step 3 : compiler.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build`
Expected : `Project build complete.` (l'autotest ne tourne que sur la carte, à la tâche 11).

- [ ] **Step 4 : commit.**

```bash
git add components/mesh
git commit -m "$(printf "Chercher l'IV Index et verifier le dechiffrement sur les exemples Mesh\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 10: Console et journal du firmware `ecoute`

> Voir la note de la tâche 7 : le code du dépôt fait foi, pas les blocs de cette tâche.

**Files:**
- Create: `ecoute/main/console_ecoute.h`, `ecoute/main/console_ecoute.c`
- Modify: `ecoute/main/CMakeLists.txt`, `ecoute/main/app_main.c`

**Interfaces:**
- Consumes : tout `mesh_amaran.h` (Tasks 7 et 9), `config_amaran.h` (Task 6), `telink.h` (Task 1), `texte.h` (Task 2).
- Produces : les commandes de console de la spec 7.5, en version phase 0.
  - `mesh` : état et compteurs.
  - `mesh cles <32hexa> <32hexa>` → `ok cles <EMP> <EMP> (redemarrer pour les appliquer)`.
  - `mesh lampe <n> <adresse> <mac> <nom…>` → `ok lampe …`.
  - `mesh iv <n>` (sauve et redémarre) ; `mesh iv cherche [max]`.
  - `mesh adresse <0x7F00-0x7F7F>|suivante` (sauve, compteur remis à 0, redémarre).
  - `mesh oublie` (redémarre) ; `mesh ecoute on|off` ; `mesh autotest`.
  - `lampe <n> releve|on|off|niveau <0-1000>` → `ok envoi …` ; `groupe releve` ; `redemarre`.
  - Lignes du journal : `[<ms> ms] etat lampe <n> (0x…. -> 0x….) : marche|arret, intensite <v> (<v/10>,<v%10> %), mode CCT|HSI, trame <hexa>`.

- [ ] **Step 1 : écrire la console et le journal.**

`ecoute/main/console_ecoute.h` :

```c
// Console et journal du firmware de reconnaissance (phase 0).
#pragma once

#include "config_amaran.h"

// Demarre la console sur l'USB natif. cfg reste la propriete de l'appelant.
void console_demarrer(amaran_config_t *cfg);
// Demarre la tache qui imprime les evenements du crochet.
void journal_demarrer(amaran_config_t *cfg);
```

`ecoute/main/console_ecoute.c` :

```c
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
         " (plancher 0x%06" PRIx32 ")\n",
         s_cfg->adresse, mesh_iv_courant(), s_cfg->iv, mesh_sequence(), s_cfg->plancher_seq);
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
    printf("recherche de 0 a 0x%06" PRIx32 "...\n", max);
    const int r = mesh_iv_chercher(max, &trouve);
    if (r == 0) {
      printf("ok IV Index 0x%08" PRIx32 " (mesh iv 0x%08" PRIx32 " pour l'adopter)\n", trouve, trouve);
      return 0;
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
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
```

`ecoute/main/CMakeLists.txt` devient :

```cmake
# Le composant main depend de tous les autres (regle d'ESP-IDF).
idf_component_register(SRCS "app_main.c" "console_ecoute.c"
                       INCLUDE_DIRS ".")
```

`ecoute/main/app_main.c` devient (version finale) :

```c
// Firmware de reconnaissance (phase 0) : rejoint le reseau Bluetooth Mesh des
// lampes et donne une console pour les essais R1 a R6 (docs/BANC.md).
#include "esp_log.h"
#include "nvs_flash.h"

#include "config_amaran.h"
#include "console_ecoute.h"
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
  ESP_ERROR_CHECK(config_charger(&cfg));
  if (cfg.cles_presentes) {
    err = mesh_demarrer(&cfg);
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

- [ ] **Step 2 : compiler.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py build`
Expected : `Project build complete.`

- [ ] **Step 3 : toutes les vérifications hors carte.**

Run :

```bash
sh tests/hote/lancer.sh && python3 -m unittest discover -s outils -p "test_*.py" && \
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && bash outils/check_sdkconfig.sh
```

Expected : `tests hote : tout est vert`, `OK`, puis `ok : tous les symboles existent`.

- [ ] **Step 4 : commit.**

```bash
git add ecoute/main
git commit -m "$(printf "Ajouter la console et le journal du firmware d'ecoute\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

---

### Task 11: Flash, clés, autotest et R1 (avec Djoko, pas en sous-agent)

**Files:**
- Create: `docs/BANC.md`

**Interfaces:**
- Consumes : le firmware `ecoute` (Task 10), `outils/cles_amaran.py` (Task 3), `outils/console.py` (Task 4).
- Produces : `docs/BANC.md`, avec la procédure des essais et le résultat de R1.

- [ ] **Step 1 : écrire la procédure des bancs.**

`docs/BANC.md` :

````markdown
# Bancs d'essai

Règles :
- Djoko est présent dès qu'on émet vers les lampes (`lampe …`, `groupe …`).
- Le port série est toujours donné explicitement : les écrans LG apparaissent eux aussi en `usbmodem`. La C6 est celle marquée `303A:1001` dans `python -m serial.tools.list_ports -v`.
- Les sous-agents ne flashent pas et n'ouvrent pas de port série.
- Sessions : `python outils/console.py --port <port> …`, avec le Python d'ESP-IDF. Le journal part dans `logs/`, ignoré par git.
- Les clés n'apparaissent nulle part. On compare seulement les empreintes.

## Phase 0 : reconnaissance (firmware `ecoute`)

### Préparation

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh
cd ecoute && idf.py -p <port> flash && cd ..
python outils/cles_amaran.py --port <port>
python outils/console.py --port <port> "mesh autotest" "mesh" "@30" "mesh"
```

Attendu :
- `autotest : 0 echec(s)` ;
- `mesh pret : oui` ;
- les empreintes de `mesh` égales à celles de `cles_amaran.py`.

### R1 : IV Index

Lire les compteurs de `mesh` après 30 s d'écoute :

| constat | décision |
|---|---|
| `IV Index … adopte et sauve` au journal, ou IV courant = IV de la dernière balise | IV trouvé par la pile |
| balises « notres » dont l'IV dépasse l'IV courant de plus de 42 | `mesh iv <IV de la balise>` (sauve et redémarre) |
| aucune balise, mais `NetMIC faux` > 0 | `mesh iv cherche` puis `mesh iv <valeur trouvée>` |
| `NID reconnu` = 0 | clés, ou lampes hors de portée : s'arrêter et en parler |

Réussi si, après `lampe 1 releve`, une ligne `etat lampe 1` apparaît au journal.

### R2 : réponse captée

`lampe 1 releve` 10 fois, à 2 s d'écart, puis de même pour la lampe 2. Réussi si chaque demande fait apparaître un `etat lampe <n> (0x000<2|4> -> 0x0001)`.

### R3 : ordres depuis notre adresse

Djoko regarde la lampe. Chaque ordre est suivi de `lampe <n> releve` :
- `niveau 500`, `niveau 100`, `off`, `on` ;
- depuis l'arrêt : `niveau 300` puis `on`. La lampe s'allume-t-elle directement à 30 % ?

Réussi si la lampe obéit et que l'état lu le confirme, 10 fois sur 10.

### R4 : molette

Faire `mesh ecoute on`, puis lire 2 min pendant que Djoko manipule, sans aucune commande :
- molette d'intensité ;
- bouton marche ;
- une lampe à la fois.

Noter tout message spontané d'une lampe : type, destination, trame.

### R5 : groupe « All »

`groupe releve` 10 fois, à 3 s d'écart. Réussi si les deux lampes répondent à chaque fois.

### R6 : amaran Desktop ouvert

Seulement si amaran Desktop fonctionne (tâche à part, spec 8.1).
- Un changement dans l'app est-il vu par l'ESP32, et en combien de temps ?
- Un ordre de l'ESP32 suivi d'un `releve` met-il l'app à jour ?
- L'app fonctionne-t-elle normalement pendant les essais ?

## Résultats

| essai | date | résultat | remarques |
|---|---|---|---|
| R1 | | | |
| R2 | | | |
| R3 | | | |
| R4 | | | |
| R5 | | | |
| R6 | | | |
````

- [ ] **Step 2 : identifier la carte et demander le feu vert à Djoko.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && python -m serial.tools.list_ports -v`
Expected : un port `usbmodem` avec `VID:PID=303A:1001`. Demander à Djoko de confirmer la carte et d'autoriser le flash.

- [ ] **Step 3 : flasher, charger les clés, autotest.**

Run :

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && cd ecoute && idf.py -p <port> flash && cd .. && \
python outils/cles_amaran.py --port <port> && sleep 5 && \
python outils/console.py --port <port> "mesh autotest" "mesh" "@30" "mesh"
```

Expected :
- `autotest : 0 echec(s)` ;
- `mesh pret : oui` ;
- les empreintes égales à celles de `cles_amaran.py`.

Si l'autotest échoue, s'arrêter : le déchiffrement est faux, et R1 ne dirait rien.

- [ ] **Step 4 : R1 (IV Index).**

Suivre le tableau R1 de `docs/BANC.md`, avec `python outils/console.py --port <port> …`. Puis, **Djoko présent** :

```bash
python outils/console.py --port <port> "lampe 1 releve" "@3" "mesh"
```

Expected : une ligne `etat lampe 1 (0x0002 -> 0x0001) : …` au journal. Noter le résultat dans le tableau.

- [ ] **Step 5 : commit.**

```bash
git add docs/BANC.md
git commit -m "$(printf 'Consigner la procedure des bancs et le resultat de R1\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 12: R2 à R6, protocole relevé, publication (avec Djoko, pas en sous-agent)

**Files:**
- Modify: `docs/BANC.md`, `README.md`
- Create: `docs/PROTOCOLE.md`

- [ ] **Step 1 : R2 et R5 (demandes d'état seules).**

Run (Djoko prévenu : seules des demandes d'état partent) :

```bash
python outils/console.py --port <port> $(for i in 1 2 3 4 5 6 7 8 9 10; do printf '"lampe 1 releve" "@2" '; done)
```

Répéter pour `lampe 2`, puis R5 avec `"groupe releve" "@3"` × 10.

Compter les `etat lampe` dans le journal du jour : `/usr/bin/grep -c "etat lampe 1" logs/<fichier>.log`. Noter les chiffres dans `docs/BANC.md`.

- [ ] **Step 2 : R3 (ordres), Djoko regarde la lampe.**

Pour chaque ordre de `docs/BANC.md` R3 :

```bash
python outils/console.py --port <port> "lampe 1 <ordre>" "@1" "lampe 1 releve" "@2"
```

Djoko dit ce qu'il voit, et on compare avec l'état lu. Même chose pour la lampe 2. Noter surtout la réponse sur l'enchaînement « intensité puis marche ».

- [ ] **Step 3 : R4 (molette).**

Run: `python outils/console.py --port <port> "mesh ecoute on" "@120" "mesh ecoute off"`
Djoko manipule, sans commande. Noter les messages spontanés : trame, source, destination. Ce résultat fixe le rythme de relecture (spec 5.7).

- [ ] **Step 4 : R6.**

Si amaran Desktop fonctionne, dérouler R6. Sinon, noter « reporté : amaran Desktop plante sur macOS 27 (spec 3.3) ».

- [ ] **Step 5 : écrire `docs/PROTOCOLE.md`.**

Contenu :
- le tableau des trames de la spec 3.2, avec pour chacune une colonne « vu au banc (date) » ;
- les états réellement reçus : les deux trames complètes, marche et arrêt, en hexa, avec la lecture `mode/marche/intensité` ;
- la destination des réponses ;
- ce que fait la molette (R4) ;
- l'IV Index du réseau (R1) ;
- l'effet de l'enchaînement « intensité puis marche » (R3).

Toute différence avec la spec 3.2 est signalée en tête, en gras.

- [ ] **Step 6 : mettre à jour l'état du projet.**

Dans `README.md`, tableau « État » :
- la ligne P0 passe à « faite (date) », avec en une phrase ce que les bancs ont établi ;
- sous le tableau, un lien vers `docs/BANC.md` et `docs/PROTOCOLE.md`.

- [ ] **Step 7 : commit, puis pousser avec l'accord de Djoko.**

```bash
git add docs README.md
git commit -m "$(printf 'Consigner la reconnaissance : bancs R2 a R6 et protocole releve\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
git push
```

Ensuite, écrire le plan 2 (phases 1 et 2) à partir des résultats (spec 8).
