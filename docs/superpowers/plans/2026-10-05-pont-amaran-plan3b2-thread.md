# Pont amaran, plan 3b-2 : l'app compagnon par Thread : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le pont s'ouvre au réseau Thread de la maison (UDP 5480, enveloppe H1 signée de Halo, liste blanche des commandes), et l'app Amaran Compagnon le supervise et le pilote à distance : source « Réseau », clé UDP créée par l'USB et rangée dans le trousseau du Mac, réglages « Accès réseau Thread », graphiques, trames du Bluetooth Mesh décodées.

**Architecture:**
- Firmware :
  - un composant neuf, `h1` (C++ pur, repris de Halo, testé sur le Mac) : enveloppe, poignée de main SALUT/DEFI, sessions, fenêtre anti-rejeu, limites ;
  - le composant `protocole` gagne la part à distance : liste blanche jugée sur les mots découpés comme la console les découpe, profil distant, cache des réponses, messages `texte`, `trame` et bloc `ip` ;
  - `firmware/main/net_udp` : la socket UDP sur OpenThread, sans jamais prendre le verrou d'OpenThread (tout passe par la file de tâches d'OpenThread), la table H1, un anneau d'émission plafonné en débit qui laisse ses tampons à Matter, la clé UDP en NVS ;
  - `json_pont` tient une session (un « puits ») par origine : l'USB et deux sessions H1. Les événements vont à chaque session en mode machine ; l'issue d'un ordre ne porte que les `id` de la session qui l'a donné. Une tâche `distant` exécute les commandes à texte venues de Thread, leur sortie changée en messages `texte` ;
  - la tâche des lampes range l'origine de chaque `id` et décode les trames qu'elle émet et reçoit.
- App (`apps/macos`) :
  - `AmaranProtocole` : enveloppe H1 et transport UDP (Network.framework), création de la clé, messages à distance, politique réseau du corrélateur et du moteur de session, miroir de la liste blanche, masquage de la clé UDP, courbes, répertoire des ponts ;
  - `AmaranCompagnon` : source « Réseau », trousseau des ponts (local), création de la clé par l'USB, alertes (route absente : `halo-routes` de Halo), écrans Graphiques et Trames, réglages « Accès réseau Thread », mode démo étendu.

```
Amaran Compagnon ──USB (3b-1)──────────────────────────► console du pont ─┐
   │  trousseau des ponts (cle UDP)                                       │
   └──Thread : UDP 5480, H1 (SALUT/DEFI, HMAC) ──► net_udp (tache udp) ───┤
                                                     │ file de taches OT  ▼
                                                 OpenThread       json_pont : un puits par origine
                                                                  (USB, session 1, session 2)
                                                                  tache distant : texte -> messages
                                                                              ▲
                                       etat, ordres (id par origine), trames ─┘ tache lampes, mesh, Matter
```

**Tech Stack:** ESP-IDF v5.5.4 (C11, C++17, FreeRTOS, OpenThread, mbedTLS), esp-matter `c5b9ea8` ; clang et clang++ pour les tests natifs (CommonCrypto pour le HMAC des tests de `h1`) ; Swift 6, SwiftUI, Swift Charts, Network.framework, CryptoKit, Swift Testing, XcodeGen 2.46, Xcode 27, macOS 15 ou plus.

**Spec:** `docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md` : c'est l'autorité de ce plan (sections 7 à 12, la part 3b-2 ; section 5 pour les clés). La part 3b-1 est faite (plan `docs/superpowers/plans/2026-10-05-pont-amaran-plan3b1-compagnon-usb.md`). Le protocole lui-même : `docs/PROTOCOLE-JSON.md`, section 10 (Task 2).

**Modèle :** le pont Halo et Halo Compagnon, au commit `e114cd5` de `~/Documents/Dev/esp32/benq` (lecture seule) : `src/h1_proto.*`, `src/h1_crypto.cpp`, `tools/host_tests/test_h1.cpp`, `src/net_udp.*` ; `apps/macos/HaloProtocole/{Reseau,Transport/TransportUDP.swift,Courbes}`, `apps/macos/HaloCompagnon/{Reseau,Vues/Graphiques.swift,Vues/TramesEnDirect.swift,Vues/ReglagesAccesReseau.swift}`. Chaque fichier repris le dit en tête.

## Global Constraints

- ESP-IDF v5.5.4 dans `~/esp/esp-idf`, esp-matter commit `c5b9ea8` dans `~/esp/esp-matter`. Cible `esp32c6`, flash 4 Mo, une seule application.
- **ESP-IDF et esp-matter ne sont jamais modifiés.** Une fonction privée d'ESP-IDF peut être déclarée à la main (c'est le cas de `esp_openthread_task_queue_post`), jamais un fichier d'ESP-IDF modifié.
- **Jamais le verrou d'OpenThread depuis nos tâches** : chaque appel à OpenThread passe par `esp_openthread_task_queue_post` (il s'exécute dans la tâche d'OpenThread, verrou tenu) ; la réception arrive déjà dans cette tâche.
- L'adresse Mesh de l'ESP32 est dans `0x7F00`–`0x7F7F`, **jamais `0x0001`**. Aucune lampe ne peut avoir une adresse de cette plage.
- **Aucune clé** dans le dépôt, un journal ou un affichage. L'empreinte d'une clé = les 8 premiers chiffres hexa, en majuscules, de son SHA-256.
  - La clé UDP (32 octets) ne se crée que par l'USB (`json cle nouvelle`) ; le pont ne la rend qu'une fois, en mode machine ; la console texte n'en montre que l'empreinte.
  - L'app la range dans son trousseau des ponts (local, jamais iCloud) et ne la montre, ne la journalise ni ne la copie jamais : chaque ligne reçue passe par le masque avant tout journal.
  - Rien de secret ne passe par Thread : les messages y sont signés, pas chiffrés.
- Le dépôt est public : ni MAC complète, ni numéro de série USB, ni numéro `AMARAN-…`, ni empreinte réelle de clé, **ni adresse IPv6 ni nom SRP du réseau de Djoko**. Les exemples, les tests et le mode démo n'utilisent que des valeurs inventées (adresses `fd12:34:5678:…`, `fd00:aaaa:bbbb:…`, `fd00:cccc:dddd:…`, `fe80::200:…`, nom SRP `1A2B3C4D5E6F7081`, MAC `02:00:…`, empreintes `1A2B3C4D`).
- **L'icône M2 (le A d'Aputure) n'est jamais versionnée** : `apps/macos/AmaranCompagnon/Ressources/AppIconM2.icon` est ignoré par git.
- Firmware : français partout (console, commits, docs) ; les commentaires du code sont **sans accents**. App : mêmes règles ; les textes de l'interface portent leurs accents. Français seulement.
- App : Swift 6, concurrence stricte complète, avertissements traités comme des erreurs, macOS 15 ou plus, sandbox (`device.serial`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, et `network.client` à partir de ce plan, rien d'autre) et runtime durci. `project.yml` fait foi : le projet Xcode est généré (`xcodegen generate`) et ignoré par git.
- Commits : directement sur `main`, message en français, terminé par une ligne `Co-Authored-By: Claude …` (le modèle qui écrit le commit). **Aucun push sans l'accord de Djoko.**
- **Les sous-agents ne flashent jamais, n'ouvrent jamais de port série, ne connectent jamais l'app au vrai pont (ni par l'USB, ni par Thread).** Le mode démo, les tests et le pair UDP local des tests sont permis.
  - Claude flashe avec l'accord de Djoko.
  - Djoko est présent dès qu'on émet vers les lampes.
- La carte du pont se reconnaît au champ `SER=` de `python -m serial.tools.list_ports -v`, jamais au nom du port. Le port est toujours donné explicitement. Ne jamais ouvrir ni flasher la C6 du maillage Thread BenQ, ni un écran LG (eux aussi en `usbmodem`).
- **Seul Claude lit la base d'amaran Desktop** (`~/Library/Containers/com.sidus.amaran-desktop`), jamais un sous-agent.
- **Le vrai trousseau du Mac n'est jamais touché par un sous-agent** (ni `fr.djoko.amaran.reseau`, ni `fr.djoko.amaran.pont`) : les tests utilisent des trousseaux en mémoire ; les tests du vrai trousseau ne tournent qu'avec `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1`.
- Chaque firmware se vérifie aussi **sur un chargeur secteur**, pas seulement branché au Mac : sans hôte USB, ESP-IDF rend une lecture de la console en échec immédiat (correctif `692bff9`).
- Dans les scripts et les commandes, utiliser `/usr/bin/grep` : le `grep` du poste est ugrep.
- Environnement, dans la même commande shell que `idf.py` : `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null`, suivi, pour le firmware du pont, de `&& source ~/esp/esp-matter/export.sh >/dev/null`. Le `PATH` d'abord : le Python 3.11 de PlatformIO, souvent en tête, fait échouer `export.sh`. Jamais `set -u` dans un script qui source `export.sh` d'esp-matter.
- `SRC_DIRS "."` : un fichier ajouté à `firmware/main` n'est compilé qu'après `idf.py reconfigure`. Un composant neuf dans `components/` aussi, et dans les deux firmwares (`ecoute/main` dépend de tous les composants).
- Tests natifs : `sh tests/hote/lancer.sh`, tout vert avant chaque commit. Tests de l'app : depuis `apps/macos`, `xcodegen generate` puis `xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test`.

## Choix fixés en préparant le plan

Le code de ce plan a été écrit, compilé (les deux firmwares et l'app), testé sur le Mac et essayé avec le vrai pont (par l'USB et par Thread) dans une copie de travail avant d'être recopié ici. Trois relectures (le pont, la sécurité de l'app, la conformité de l'app à la spec) l'ont ensuite corrigé. Ce prototype a fixé les choix suivants (la Task 10 les reporte dans la spec) :

1. **Jamais le verrou d'OpenThread** : la socket UDP s'ouvre, se ferme, émet et relève le nom SRP et les adresses par `esp_openthread_task_queue_post` (fonction privée d'ESP-IDF, déclarée à la main : elle exécute la fonction dans la tâche d'OpenThread, verrou tenu). La réception arrive dans cette tâche : le rappel copie le datagramme dans une file FreeRTOS, sans verrou ni impression. Socket liée à l'interface Thread interne d'OpenThread (`OT_NETIF_THREAD_INTERNAL`), pas à lwIP. Essai radio du 05/10 : cohabite avec Matter (20 échos sur 20 à 42 ms ; salve de 1 Ko trois fois par seconde pendant 60 s avec 56 ordres de Maison : 178 échos sur 180, aucun ordre abandonné, tampons d'OpenThread jamais sous 34).
2. **Émission** : un anneau de 12 datagrammes (en-tête H1 et 1 022 octets de ligne au plus) ; 3 000 octets par seconde en moyenne, rafale de 2 400 ; un DEFI passe en tête, hors plafond, et une place lui reste toujours ; un datagramme qui n'est pas parti en 4 s est perdu et compté ; 2 datagrammes au plus par passage dans la tâche d'OpenThread, et seulement s'il reste 24 tampons d'OpenThread pour Matter ; nos messages ont la priorité basse.
3. **Débit réglé vers une session distante** (comme Halo) : une ligne périodique ne quitte la file que s'il reste 7 places dans l'anneau, une réponse différée 2 ; un événement rare (`ordre`, alerte, `lampe`, `led`) part s'il reste 2 places, une `trame` ou un `log` 7, sinon il est compté perdu pour cette session ; il reste ainsi 6 places pour une rafale de réponses et d'événements (au banc : deux sessions qui donnent au même instant un ordre déjà tenu, perdues avec un anneau de 6 places, passent avec 12) ; les deux sessions avancent à tour de rôle ; une ligne périodique distante encore en file 10 s après sa demande est perdue. L'instantané complet de `json 1` arrive ainsi sans perte (simulation : 0,75 s à 2 lampes, 3,6 s à 16 ; deux instantanés de 16 lampes à la fois, un peu plus de 8 s).
4. **Un « puits » par origine** dans `json_pont` : l'USB (origine 0) et les deux places H1 (origines 1 et 2), chacun avec son mode machine, ses réglages, son bail, sa file, son compteur `n`, ses réponses différées, sa commande en cours, son cache, ses plafonds (annonces : 20 par seconde par l'USB, 10 à distance ; trames : 50 et 10).
5. **Identité d'une session distante** : une place H1 porte une génération, changée à chaque nouvelle session, nouvelle clé ou oubli ; une ligne, une réponse, une fin de session ou l'`id` d'un ordre d'une génération passée ne touche jamais la session suivante.
6. **La liste blanche se juge sur les mots que la console exécuterait** (`esp_console_split_argv`), jamais sur la ligne brute : chez Halo, `json 1 "bail" 0` passait. Les tests du Mac découpent avec le vrai `split_argv.c` d'ESP-IDF (lu, jamais modifié). L'app en a le miroir exact (un fuzz différentiel de 960 961 lignes : aucun écart).
7. **Ligne distante** : `id` obligatoire (sans `id` : ignorée et comptée) ; même `id` qu'une réponse gardée (8 par session) : la même réponse, sans rien exécuter ; `id` encore en cours : ignoré, sa réponse viendra ; `id` plus ancien : `deja_traite` (réponse oubliée), que l'app traite comme une fin.
8. **Commandes à texte à distance** : la tâche `distant` (pile de 6 Ko) les exécute, une à la fois avec la console ; sa sortie standard, changée par `fopencookie`, va dans un tampon de 4 Ko sans verrou ni attente ; les lignes `texte` partent après la commande. (La première version prenait le verrou de `json_pont` dans la sortie : `mesh lampe <n> masquer`, dont un journal part sous le verrou des lampes, figeait le pont.)
9. **Clé UDP** : `json cle nouvelle <64 hexa>`, par l'USB seulement ; clé = HMAC-SHA256(aléa de l'app, aléa du pont), calculée sous le verrou de `net_udp` (la crypto de `h1` n'a qu'un contexte) ; NVS (espace `amaran_udp`) ; rendue une fois en mode machine, empreinte seule en mode texte. `json cle efface`, `decommission` et BOOT tenu 8 s l'effacent. Le port 5480 ne s'ouvre qu'avec une clé (relance si l'ouverture échoue).
10. **Rien de secret par Thread** : les messages y sont signés, pas chiffrés ; la clé UDP n'y passe jamais ; `code_manuel` et `qr` valent `null` dans `reseau matter` à distance.
11. **Profil distant** : état toutes les 2 s, lampes toutes les 30 s (et à chaque changement), réseau toutes les 30 s, compteurs coupés (l'app peut les demander, toutes les 5 s au plus vite), trames coupées seules au bout de 60 s ; bail de 10 à 120 s, jamais 0.
12. **App, politique réseau** (Halo) : renvoi du même `id` à 2 s puis 4 s, sans réponse à 6 s ; ordres 10 s ; `json 1 bail 60` ; la fin de `json 1`, `json etat` et `json hello`, qui suit un instantané, est attendue 12 s ; ping toutes les 10 s ; silence jugé à 6 s ; nouvelle poignée de main après 30 s sans `hello`. Un événement `ordre` clôt aussi une commande dont l'`accepte` s'est perdu. La première ligne reçue par UDP n'est pas jetée (Halo jetait le `hello` et perdait 4 s à chaque connexion).
13. **App, trousseau des ponts** : service `fr.djoko.amaran.pont`, compte = nom SRP, local au Mac (comme celui des clés du Mesh) ; la clé n'en sort que pour ouvrir une session. Le masque des clés s'applique à chaque élément reçu avant tout journal, et se juge aussi sur les mots de la commande (après `mesh cles` ou `json cle nouvelle`, tout est masqué, échappements et guillemets compris) ; les règles de la console par l'USB se jugent sur les mêmes mots que le pont.
14. **App, route absente** : la console et le panneau de connexion pointent vers `halo-routes` (l'assistant du pont Halo, même réseau Thread, servi tel quel) ; pas de bandeau (comme Halo).
15. **Console sans hôte USB** : ESP-IDF 5.5.4 rend la lecture de la console en échec immédiat sans hôte USB (chargeur, port du Mac en veille) ; la console de 3b-1 rebouclait et affamait le démarrage (pont bleu, Matter jamais lancé). Corrigé sur `main` (`692bff9`) avant ce plan ; chaque banc vérifie désormais le pont sur secteur.

## Carte des fichiers

| fichier | rôle | tâche |
|---|---|---|
| `components/h1/{CMakeLists.txt,include/h1_proto.h,h1_proto.cpp,h1_crypto.cpp}`, `tests/hote/test_h1.cpp` | enveloppe H1 (C++ pur, repris de Halo) | 1 |
| `tests/hote/lancer.sh` | tests de `h1`, découpage par `split_argv.c` d'ESP-IDF | 1, 2 |
| `components/protocole/{json_ligne.cpp,include/json_amaran.h,json_amaran.cpp}`, `docs/PROTOCOLE-JSON.md` | protocole à distance | 2 |
| `components/protocole/include/json_ligne.h`, `tests/hote/test_json.cpp` | protocole à distance (2) ; bloc `ip` en file, 11 tâches suivies (3) | 2, 3 |
| `firmware/main/{net_udp.h,net_udp.cpp}` | socket UDP sur OpenThread, table H1, anneau, clé UDP | 3 |
| `firmware/main/{json_pont.h,json_pont.cpp}` | puits par origine, tâche `distant`, débit, clé | 3 |
| `firmware/main/{tache_lampes.h,tache_lampes.c,pont_matter.h,pont_matter.cpp,app_main.cpp,console_pont.h,console_pont.c}` | origine des `id`, trames, effacement de la clé, `matter` à distance, démarrage, tâches suivies | 3 |
| `docs/BANC.md` | résultats des bancs | 4, 11 |
| `apps/macos/AmaranProtocole/{Reseau/EnveloppeH1.swift,Reseau/ErreurReseau.swift,Transport/TransportUDP.swift}` | H1 et transport UDP (repris de Halo) | 5 |
| `apps/macos/AmaranProtocole/Reseau/CleReseau.swift` | création de la clé (5), état de l'accès réseau (7) | 5, 7 |
| `apps/macos/AmaranProtocole/{Messages,Etat,Interpretation}` | messages à distance | 5, 6 |
| `apps/macos/AmaranProtocole/{Commandes,Session,Transport/Transport.swift}` | liste blanche, masque, politique réseau | 5, 6 |
| `apps/macos/AmaranProtocole/{Courbes/Courbes.swift,Reseau/RepertoirePonts.swift}` | courbes, répertoire | 7 |
| `apps/macos/AmaranProtocoleTests/*` | tests du protocole | 5, 6, 7 |
| `apps/macos/AmaranCompagnon/{Modele,Reseau,Demo}`, `AmaranCompagnon.entitlements`, `AmaranCompagnonApp.swift`, `apps/macos/project.yml` | modèle, trousseau des ponts, alertes, démo, droits | 8 |
| `apps/macos/AmaranCompagnon/Vues` | écrans | 8 (une ligne), 9 |
| `apps/macos/AmaranCompagnonTests/*` | tests du modèle (8), tests de fumée des écrans (9) | 8, 9 |
| `README.md`, `apps/macos/README.md`, `docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md` | documentation | 10, 11 |

---

### Task 1: Le composant `h1`, enveloppe du transport réseau (C++ pur, repris de Halo, testé sur le Mac)

**Files:**
- Create: `components/h1/CMakeLists.txt`, `components/h1/include/h1_proto.h`, `components/h1/h1_proto.cpp`, `components/h1/h1_crypto.cpp`
- Create: `tests/hote/test_h1.cpp`
- Modify: `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : rien du pont ; mbedTLS d'ESP-IDF (`h1_crypto.cpp`, sur la carte) ; CommonCrypto du Mac (`test_h1.cpp`, sur le Mac).
- Produces (espace de noms `h1`, la Task 3 s'en sert telle quelle) :
  - constantes : `kKeyLen` (32), `kNonceLen` (16), `kMacLen` (16), `kKidHex` (8), `kSidHex` (8), `kWindow` (32), `kForgetMs` (600 000), `kProvisionalMs` (30 000), `kDefiPerSecond` (2), `kSlots` (2), `kEvictIdleMs` (30 000), `kSeenNa` (16), `kHeaderMax` (56), `kDefiLen` (82), `kSalutLen` (83) ;
  - crypto de la plateforme (`h1_crypto.cpp` sur la carte) : `struct Part { const void *p; size_t n; }`, `bool hmacSha256(key, keyLen, parts, nParts, out[32])`, `bool sha256(p, n, out[32])` ;
  - outils : `equalCt`, `wipe(p, n)`, `toHex(p, n, out)`, `fromHex(s, n, out)`, `bool keyId(psk, char kid[9])` (empreinte de la clé), `salutMac`, `defiMac`, `sessionKey`, `messageMac` ;
  - lecture d'un datagramme : `enum class Kind { Invalid, Salut, Defi, Data }`, `struct Parsed` (`kind`, `sid`, `ctr`, `payload`, `payloadLen`…), `Parsed parse(d, n)` ;
  - `struct Peer { uint8_t ip[16]; uint16_t port; uint8_t local[16]; }`, `struct Session` (`used`, `sid`, `sidHex`, `ks`, `rx`, `tx`, `since`, `lastAt`, `ended`, `peer`), `enum class Verdict { Ok, Invalid, NoKey, WrongKid, Limited, UnknownSid, BadMac, Replay, Full }`, `const char *verdictText(Verdict)` ;
  - `class Table` : `setKey(psk | nullptr)`, `hasKey()`, `kid()`, `onSalut(p, rnd, from, now, out[kDefiLen])`, `onData(p, from, now, &slot, &fresh)`, `seal(slot, payload, n, hdr[kHeaderMax + 1])` (longueur de l'en-tête, 0 si impossible), `end(slot)`, `resume(slot)`, `expire(now)` et `clear()` (masques des places libérées), `slot(i)`, `provisional()`, `established()`.

Pourquoi : la spec 3b, section 7, et la décision 8 (les modules purs de Halo, avec une fine couche pour ESP-IDF). L'enveloppe H1 est celle de Halo, octet pour octet : l'app la parlera telle quelle (Task 5). Les tests de Halo viennent avec : vecteurs calculés indépendamment (Python, `hmac` et `hashlib`), lecture stricte des datagrammes, fenêtre anti-rejeu, poignée de main, promotion, éviction et oubli des sessions. Sur le Mac, la crypto vient de CommonCrypto ; sur la carte, de mbedTLS (SHA matériel du C6).

Repris de Halo (commit `e114cd5`) : `src/h1_proto.h`, `src/h1_proto.cpp`, `src/h1_crypto.cpp`, `tools/host_tests/test_h1.cpp`. Adapté : le chemin des fichiers, et les appels à la crypto qui se font ici sous le verrou de `net_udp` (Task 3) au lieu de la boucle Arduino.

- [ ] **Step 1 : les tests.**

`tests/hote/test_h1.cpp` (contenu complet) :

````cpp
// Tests sur le Mac de l'enveloppe H1 du transport reseau (components/h1). Repris
// du pont Halo (commit e114cd5, tools/host_tests/test_h1.cpp) : vecteurs
// calcules independamment (Python : hmac, hashlib ; les memes que ceux du Halo),
// lecture stricte des datagrammes, fenetre contre le rejeu, poignee de main,
// promotion et oubli des sessions.
// Lancer : sh tests/hote/lancer.sh
//
// La crypto de la plateforme vient ici de CommonCrypto (macOS) ; sur la carte,
// de mbedTLS (components/h1/h1_crypto.cpp).
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <stdio.h>
#include <string.h>

#include <string>

#include "h1_proto.h"

using namespace h1;

namespace h1 {
bool hmacSha256(const uint8_t *key, size_t keyLen, const Part *parts, size_t nParts, uint8_t out[32]) {
  CCHmacContext c;
  CCHmacInit(&c, kCCHmacAlgSHA256, key, keyLen);
  for (size_t i = 0; i < nParts; i++) CCHmacUpdate(&c, parts[i].p, parts[i].n);
  CCHmacFinal(&c, out);
  return true;
}
bool sha256(const void *p, size_t n, uint8_t out[32]) {
  CC_SHA256(p, (CC_LONG)n, out);
  return true;
}
}  // namespace h1

static int gChecks = 0, gFails = 0;

#define CHECK(cond, ...)                              \
  do {                                                \
    gChecks++;                                        \
    if (!(cond)) {                                    \
      if (++gFails <= 40) {                           \
        printf("ECHEC %s:%d : ", __FILE__, __LINE__); \
        printf(__VA_ARGS__);                          \
        printf("\n");                                 \
      }                                               \
    }                                                 \
  } while (0)

// --- Vecteurs (Python, 24/09/2026) -------------------------------------------

static const char *kPskHex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
static const char *kKid = "630DCD29";
static const char *kNa = "A0A1A2A3A4A5A6A7A8A9AAABACADAEAF";
static const char *kNcHex = "505152535455565758595A5B5C5D5E5F";
static const uint32_t kSid = 0x1234ABCD;
static const char *kSalut = "H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D";
static const char *kDefi = "H1 DEFI 1234ABCD 505152535455565758595A5B5C5D5E5F BFF13F71B42243E6017D2807F8E6171F";
static const char *kKsHex = "20D6D83D97ED44F2BBF8CE56389BD475CBE2B625CE6CE24768B6B4C1C625012F";
static const char *kMsgA = "H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE id=1 json 1";
static const char *kJsonC = "{\"v\":1,\"t\":\"hb\",\"n\":7,\"ms\":1234}";
static const char *kHdrC = "H1 1234ABCD 1 347A2E6A129BC822ECFF39BEC910451C ";
static const char *kMacAMax = "62CA08CFED5A5FE89EB9AAE8CC3D9CB7";  // A, ctr 4294967295, charge "x"

static uint8_t gPsk[32], gNc[16];

static Parsed P(const char *s) { return parse((const uint8_t *)s, strlen(s)); }

static Peer peer(uint8_t tag) {
  Peer p;
  p.ip[0] = 0xFD;
  p.ip[15] = tag;
  p.port = (uint16_t)(50000 + tag);
  p.local[0] = 0xFD;
  p.local[15] = 0x77;
  return p;
}


// Aleatoire de la plateforme, scripte : nc puis sid (octets dans l'ordre de la memoire).
static uint8_t gRnd[64];
static size_t gRndLen = 0, gRndPos = 0;
static uint32_t gRndCalls = 0;
static void setRnd(const uint8_t *nc, uint32_t sid) {
  memcpy(gRnd, nc, 16);
  memcpy(gRnd + 16, &sid, 4);
  gRndLen = 20;
  gRndPos = 0;
}
static void rnd(void *p, size_t n) {
  gRndCalls++;
  for (size_t i = 0; i < n; i++) ((uint8_t *)p)[i] = gRndPos < gRndLen ? gRnd[gRndPos++] : 0x5A;
}

// SALUT signe avec la cle de test, na tire d'un compteur (un na neuf par appel).
static std::string salut(uint32_t tag, const uint8_t *key = nullptr) {
  uint8_t na[16] = {};
  memcpy(na, &tag, 4);
  na[15] = 0xA5;
  char naHex[33], kid[9];
  toHex(na, 16, naHex);
  keyId(key ? key : gPsk, kid);
  uint8_t mac[16];
  salutMac(key ? key : gPsk, kid, naHex, mac);
  char mh[33];
  toHex(mac, 16, mh);
  return std::string("H1 SALUT ") + kid + " " + naHex + " " + mh;
}

static Verdict salutV(Table &t, const std::string &m, uint32_t sid, uint32_t now, uint8_t tag = 1) {
  setRnd(gNc, sid);
  char defi[kDefiLen + 1] = {};
  return t.onSalut(parse((const uint8_t *)m.data(), m.size()), rnd, peer(tag), now, defi);
}

static std::string hex(const uint8_t *p, size_t n) {
  char b[129];
  toHex(p, n, b);
  return b;
}

// Message A signe pour la session s (tests sans vecteur fige).
static std::string msgA(const Session &s, uint32_t ctr, const char *payload) {
  uint8_t mac[kMacLen];
  messageMac(s.ks, 'A', s.sidHex, ctr, (const uint8_t *)payload, strlen(payload), mac);
  char b[256];
  snprintf(b, sizeof(b), "H1 %s %u %s %s", s.sidHex, ctr, hex(mac, kMacLen).c_str(), payload);
  return b;
}

static Verdict data(Table &t, const std::string &m, uint32_t now, uint8_t *slot, bool *fresh, uint8_t tag = 1) {
  const Parsed p = parse((const uint8_t *)m.data(), m.size());
  return t.onData(p, peer(tag), now, slot, fresh);
}

// Poignee de main complete : SALUT, DEFI, premier message. Rend l'emplacement.
static int establish(Table &t, uint32_t sid, uint32_t now, uint8_t tag) {
  if (salutV(t, salut(sid), sid, now, tag) != Verdict::Ok) return -1;
  const Session s = t.provisional();
  uint8_t slot = 0xFF;
  bool fresh = false;
  if (data(t, msgA(s, 1, "id=1 json 1"), now, &slot, &fresh, tag) != Verdict::Ok || !fresh) return -1;
  return slot;
}

// --- Tests -----------------------------------------------------------------------

static void testVectors() {
  CHECK(fromHex(kPskHex, 32, gPsk), "cle de test");
  CHECK(fromHex(kNcHex, 16, gNc), "nc de test");
  char kid[9];
  CHECK(keyId(gPsk, kid) && !strcmp(kid, kKid), "kid : %s", kid);

  uint8_t ks[32];
  CHECK(sessionKey(gPsk, kNa, kNcHex, "1234ABCD", ks) && hex(ks, 32) == kKsHex, "Ks : %s", hex(ks, 32).c_str());
  uint8_t mac[16];
  CHECK(messageMac(ks, 'A', "1234ABCD", 4294967295u, (const uint8_t *)"x", 1, mac) && hex(mac, 16) == kMacAMax,
        "MAC ctr max : %s", hex(mac, 16).c_str());

  Table t;
  CHECK(t.setKey(gPsk) && t.hasKey() && !strcmp(t.kid(), kKid), "setKey");
  char defi[kDefiLen + 1] = {};
  const Parsed ps = P(kSalut);
  uint8_t ms[16];
  CHECK(ps.kind == Kind::Salut && salutMac(gPsk, kKid, kNa, ms) && equalCt(ms, ps.mac, 16), "MAC du SALUT");
  setRnd(gNc, kSid);
  const Verdict v = t.onSalut(ps, rnd, peer(1), 1000, defi);
  CHECK(v == Verdict::Ok && std::string(defi, kDefiLen) == kDefi, "DEFI : %s (%s)", defi, verdictText(v));
  CHECK(t.onSalut(ps, rnd, peer(1), 1100, defi) == Verdict::Replay, "SALUT rejoue (meme na) : ignore");
  CHECK(!memcmp(t.provisional().ks, ks, 32), "Ks de la session provisoire");
  CHECK(t.established() == 0, "rien d'etabli avant le premier message");

  // Le DEFI se relit (cote app) et son MAC se verifie.
  const Parsed d = P(kDefi);
  uint8_t md[16];
  CHECK(d.kind == Kind::Defi && d.sid == kSid && !strcmp(d.nc, kNcHex), "lecture du DEFI");
  CHECK(defiMac(gPsk, kKid, kNa, d.nc, d.sidHex, md) && equalCt(md, d.mac, 16), "MAC du DEFI");

  uint8_t slot = 0xFF;
  bool fresh = false;
  const Verdict va = data(t, kMsgA, 1100, &slot, &fresh, 2);
  CHECK(va == Verdict::Ok && slot == 0 && fresh, "premier message : %s slot %u", verdictText(va), slot);
  CHECK(t.established() == 1 && !t.provisional().used, "session promue");
  CHECK(t.slot(0).peer.port == peer(2).port, "adresse du dernier message au MAC juste");
  const Parsed a = P(kMsgA);
  CHECK(a.payloadLen == 11 && !memcmp(a.payload, "id=1 json 1", 11), "charge");

  char hdr[kHeaderMax + 1];
  const size_t n = t.seal(0, (const uint8_t *)kJsonC, strlen(kJsonC), hdr);
  CHECK(n == strlen(kHdrC) && !strcmp(hdr, kHdrC), "en-tete C : %s", hdr);
  const size_t n2 = t.seal(0, (const uint8_t *)kJsonC, strlen(kJsonC), hdr);
  CHECK(n2 && !strncmp(hdr, "H1 1234ABCD 2 ", 14), "ctr C suivant : %s", hdr);
  CHECK(t.seal(1, (const uint8_t *)"x", 1, hdr) == 0, "emplacement vide : rien");
}

static void testParse() {
  CHECK(P(kSalut).kind == Kind::Salut, "SALUT");
  CHECK(!strcmp(P(kSalut).na, kNa) && !strcmp(P(kSalut).kid, kKid), "SALUT : champs");
  CHECK(strlen(kSalut) == kSalutLen, "longueur du SALUT");
  CHECK(P("H1 SALUT 630dcd29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D").kind ==
            Kind::Invalid,
        "minuscules refusees");
  CHECK(P("H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D ").kind ==
            Kind::Invalid,
        "espace finale");
  CHECK(P("H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF").kind == Kind::Invalid, "SALUT sans MAC (v0)");
  CHECK(P("H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEA 52D853E3FFE9E9CCEFFA98BB5304B32D").kind == Kind::Invalid,
        "na court");
  CHECK(P("H1 SALUT 630DCD29  A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D").kind ==
            Kind::Invalid,
        "double espace");
  CHECK(P("h1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D").kind ==
            Kind::Invalid,
        "prefixe");
  CHECK(P("").kind == Kind::Invalid && P("H1").kind == Kind::Invalid && P("H1 ").kind == Kind::Invalid, "vide");

  const Parsed m = P(kMsgA);
  CHECK(m.kind == Kind::Data && m.sid == kSid && m.ctr == 1, "message");
  CHECK(P("H1 1234ABCD 01 FD97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "ctr : zero de tete");
  CHECK(P("H1 1234ABCD 0 FD97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "ctr 0");
  CHECK(P("H1 1234ABCD 4294967296 FD97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "ctr > 2^32-1");
  CHECK(P("H1 1234ABCD 99999999999 FD97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "ctr 11 chiffres");
  const Parsed mx = P("H1 1234ABCD 4294967295 62CA08CFED5A5FE89EB9AAE8CC3D9CB7 x");
  CHECK(mx.kind == Kind::Data && mx.ctr == 4294967295u, "ctr max");
  CHECK(P("H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE").kind == Kind::Invalid, "sans espace avant la charge");
  const Parsed e = P("H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE ");
  CHECK(e.kind == Kind::Data && e.payloadLen == 0, "charge vide lisible (refusee plus haut)");
  CHECK(P("H1 1234abcd 1 FD97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "sid minuscule");
  CHECK(P("H1 1234ABCD 1 fd97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "mac minuscule");
  CHECK(P("H1 1234ABCD 1a FD97A0C9E604524B49C763452D0310CE x").kind == Kind::Invalid, "ctr non decimal");
  const Parsed sp = P("H1 1234ABCD 3 FD97A0C9E604524B49C763452D0310CE id=2 lampe  on ");
  CHECK(sp.kind == Kind::Data && sp.payloadLen == 15, "charge : octet pour octet, espaces compris");
}

static void testWindow() {
  Window w;
  CHECK(!w.fresh(0), "ctr 0");
  CHECK(w.fresh(1), "1");
  w.commit(1);
  CHECK(!w.fresh(1), "1 rejoue");
  w.commit(40);
  CHECK(!w.fresh(8) && w.fresh(9), "fenetre de 32 : 8 hors, 9 dedans");
  w.commit(9);
  CHECK(!w.fresh(9) && w.fresh(10), "9 vu, 10 pas");
  CHECK(!w.fresh(40) && w.fresh(41), "haut de fenetre");
  w.commit(100);
  CHECK(!w.fresh(40) && !w.fresh(68) && w.fresh(69) && w.fresh(99), "saut de 60");
  w.commit(4294967295u);
  CHECK(!w.fresh(4294967295u) && w.fresh(4294967294u), "ctr max");
}

static void testSessions() {
  Table t;
  CHECK(salutV(t, salut(1), 11, 0) == Verdict::NoKey, "sans cle");
  t.setKey(gPsk);
  uint8_t other[32];
  for (uint8_t i = 0; i < 32; i++) other[i] = (uint8_t)(0xFF - i);
  CHECK(salutV(t, salut(2, other), 11, 0) == Verdict::WrongKid, "autre cle");
  // MAC faux : refuse, et aucun aleatoire tire (le cout d'un SALUT sans la cle reste nul).
  std::string bad = salut(3);
  bad[bad.size() - 1] = bad[bad.size() - 1] == '0' ? '1' : '0';
  const uint32_t calls = gRndCalls;
  CHECK(salutV(t, bad, 11, 0) == Verdict::BadMac && gRndCalls == calls, "SALUT au MAC faux");
  // sid tire nul : retire.
  CHECK(salutV(t, salut(4), 0, 100) == Verdict::Ok && t.provisional().sid == 0x5A5A5A5Au, "sid nul retire");

  // Limite globale : 2 DEFI par seconde ; un SALUT limite ne remplace rien.
  t.clear();
  CHECK(salutV(t, salut(10), 11, 5000) == Verdict::Ok, "DEFI 1");
  CHECK(salutV(t, salut(11), 12, 5300) == Verdict::Ok, "DEFI 2");
  CHECK(salutV(t, salut(12), 13, 5900) == Verdict::Limited, "DEFI 3 dans la seconde");
  CHECK(t.provisional().sid == 12, "la limite ne remplace pas la provisoire");
  CHECK(salutV(t, salut(13), 14, 6000) == Verdict::Ok, "seconde suivante");
  CHECK(salutV(t, salut(13), 15, 7000) == Verdict::Replay, "SALUT rejoue plus tard : ignore");

  // Une nouvelle poignee de main remplace la provisoire : l'ancienne n'aboutit plus.
  t.clear();
  salutV(t, salut(20), 21, 10000);
  const Session old = t.provisional();
  salutV(t, salut(21), 22, 10100, 2);
  uint8_t slot;
  bool fresh;
  CHECK(data(t, msgA(old, 1, "id=1 json 1"), 10200, &slot, &fresh) == Verdict::UnknownSid, "provisoire remplacee");

  // MAC faux : refuse, et la fenetre n'avance pas.
  const Session cur = t.provisional();
  std::string badMsg = msgA(cur, 5, "id=1 json 1");
  badMsg[badMsg.size() - 1] = '2';
  CHECK(data(t, badMsg, 10300, &slot, &fresh) == Verdict::BadMac, "charge modifiee");
  CHECK(t.established() == 0, "rien de promu sur un MAC faux");
  CHECK(data(t, msgA(cur, 5, "id=1 json 1"), 10400, &slot, &fresh, 2) == Verdict::Ok && fresh && slot == 0, "promue");
  CHECK(data(t, msgA(cur, 5, "id=1 json 1"), 10500, &slot, &fresh) == Verdict::Replay, "rejeu");
  CHECK(data(t, msgA(cur, 4, "id=2 json ping"), 10600, &slot, &fresh) == Verdict::Ok && !fresh, "desordre accepte");
  const Session s0 = t.slot(0);
  CHECK(data(t, msgA(s0, 6, "x").replace(3, 8, "DEADBEEF"), 10700, &slot, &fresh) == Verdict::UnknownSid,
        "sid inconnu");

  // Adresse des reponses : celle du plus recent message seulement.
  CHECK(data(t, msgA(s0, 10, "id=3 json ping"), 10800, &slot, &fresh, 3) == Verdict::Ok &&
            t.slot(0).peer.port == peer(3).port,
        "message le plus recent : adresse suivie");
  CHECK(data(t, msgA(s0, 9, "id=4 json ping"), 10900, &slot, &fresh, 4) == Verdict::Ok &&
            t.slot(0).peer.port == peer(3).port,
        "message plus ancien (retarde, rejoue d'ailleurs) : adresse inchangee");

  // Deux sessions etablies ; une troisieme ne chasse qu'une session muette depuis 30 s.
  CHECK(establish(t, 31, 20000, 5) == 1, "seconde session, emplacement libre");
  CHECK(t.established() == 2, "deux etablies");
  const Session s1 = t.slot(1);
  CHECK(data(t, msgA(s0, 11, "id=5 json ping"), 30000, &slot, &fresh) == Verdict::Ok && slot == 0, "0 active");
  CHECK(salutV(t, salut(40), 41, 40000, 6) == Verdict::Ok, "troisieme client : poignee de main");
  const Session s2 = t.provisional();
  const std::string first = msgA(s2, 1, "id=1 json 1");
  CHECK(data(t, first, 40000, &slot, &fresh, 6) == Verdict::Full, "deux places actives : complet");
  CHECK(t.provisional().used && t.established() == 2, "rien de change");
  CHECK(data(t, msgA(s1, 2, "id=2 json ping"), 45000, &slot, &fresh) == Verdict::Ok && slot == 1, "1 toujours la");
  // Ce message ne peut plus servir (ctr brule : pas de promotion vers l'adresse d'un rejoueur).
  CHECK(data(t, first, 60000, &slot, &fresh, 9) == Verdict::Replay && t.provisional().used, "message refuse rejoue");
  // 30 s plus tard, la 0 (dernier message a 30 s) est muette depuis 30 s : le renvoi (ctr neuf) passe.
  CHECK(data(t, msgA(s2, 2, "id=1 json 1"), 60000, &slot, &fresh, 6) == Verdict::Ok && fresh && slot == 0 &&
            t.slot(0).peer.port == peer(6).port,
        "0 remplacee apres 30 s");
  CHECK(data(t, msgA(s0, 12, "id=6 json ping"), 60100, &slot, &fresh) == Verdict::UnknownSid, "0 evincee");
  CHECK(data(t, msgA(s1, 3, "id=3 json ping"), 60200, &slot, &fresh) == Verdict::Ok && slot == 1, "1 intacte");

  // Oubli : 10 min sans message valide ; provisoire apres 30 s.
  salutV(t, salut(50), 51, 60300, 7);
  CHECK(t.expire(60300 + kProvisionalMs - 1) == 0 && t.provisional().used, "provisoire encore la");
  CHECK(t.expire(60300 + kProvisionalMs) == 0 && !t.provisional().used, "provisoire oubliee");
  CHECK(t.expire(60000 + kForgetMs - 1) == 0, "rien a 10 min moins 1 ms");
  CHECK(t.expire(60200 + kForgetMs) == 0x03, "les deux oubliees (derniers messages a 60,0 et 60,2 s)");
  CHECK(t.established() == 0, "table vide");

  // Nouvelle cle : tout tombe ; sans cle, plus rien ne passe.
  CHECK(establish(t, 61, 700000, 8) == 0, "session");
  CHECK(t.setKey(nullptr) && !t.hasKey() && t.established() == 0, "cle effacee");
  CHECK(salutV(t, salut(62), 62, 700100) == Verdict::NoKey, "sans cle apres effacement");
  t.setKey(gPsk);
  CHECK(establish(t, 63, 700200, 8) == 0, "cle remise");
  CHECK(t.clear() == 0x01 && t.established() == 0, "clear rend le masque");

  // 'json 0' (end) : la place revient au client suivant sans attendre 30 s.
  // Poignees de main espacees d'une seconde (2 DEFI par seconde au plus).
  CHECK(establish(t, 80, 800000, 1) == 0 && establish(t, 81, 801000, 2) == 1, "deux sessions actives");
  const Session e0 = t.slot(0);
  t.end(0);
  CHECK(t.slot(0).ended && !t.slot(1).ended, "seule la 0 est terminee");
  CHECK(data(t, msgA(e0, 2, "id=9 json 0"), 802000, &slot, &fresh) == Verdict::Ok && slot == 0 && t.slot(0).ended,
        "terminee : ses messages passent encore (renvoi du json 0), la marque reste");
  CHECK(salutV(t, salut(82), 82, 803000, 3) == Verdict::Ok, "troisieme client : poignee de main");
  const Session e2 = t.provisional();
  CHECK(data(t, msgA(e2, 1, "id=1 json 1"), 803100, &slot, &fresh, 3) == Verdict::Ok && fresh && slot == 0,
        "session terminee : sa place tout de suite, meme active il y a 1 s");
  CHECK(!t.slot(0).ended && t.slot(0).sid == 82 && t.slot(1).sid == 81, "la nouvelle a la place, l'autre intacte");
  CHECK(data(t, msgA(e0, 3, "id=10 json ping"), 803200, &slot, &fresh) == Verdict::UnknownSid, "l'ancienne est partie");
  CHECK(salutV(t, salut(83), 83, 804000, 4) == Verdict::Ok, "quatrieme client");
  CHECK(data(t, msgA(t.provisional(), 1, "id=1 json 1"), 804100, &slot, &fresh, 4) == Verdict::Full,
        "aucune terminee, les deux actives : complet, comme avant");
  // Une place libre passe avant une session terminee ; entre deux terminees,
  // la moins recemment active cede.
  t.clear();
  CHECK(establish(t, 84, 900000, 1) == 0, "une session");
  t.end(0);
  CHECK(establish(t, 85, 901000, 2) == 1 && t.slot(0).ended, "place libre d'abord : la terminee reste");
  t.end(1);
  CHECK(establish(t, 86, 902000, 3) == 0 && t.slot(1).ended, "deux terminees : la plus ancienne cede");
  t.end(7);  // hors bornes : sans effet
  CHECK(t.established() == 2, "end hors bornes : rien ne change");
  // Une terminee passe avant une muette depuis 30 s, meme plus ancienne.
  t.clear();
  CHECK(establish(t, 87, 1000000, 1) == 0 && establish(t, 88, 1001000, 2) == 1, "deux sessions");
  const Session f1 = t.slot(1);
  CHECK(data(t, msgA(f1, 2, "id=2 json ping"), 1040000, &slot, &fresh, 2) == Verdict::Ok && slot == 1, "1 active");
  t.end(1);  // 0 muette depuis 40 s, 1 terminee mais active a l'instant
  CHECK(establish(t, 89, 1040100, 3) == 1 && t.slot(0).sid == 87, "la terminee avant la muette");
  // Nouvelle commande de la session terminee : elle sert de nouveau.
  t.clear();
  CHECK(establish(t, 90, 1100000, 1) == 0 && establish(t, 91, 1101000, 2) == 1, "deux sessions");
  t.end(0);
  t.resume(0);
  CHECK(!t.slot(0).ended, "resume leve la marque");
  CHECK(salutV(t, salut(92), 92, 1102000, 3) == Verdict::Ok, "troisieme client");
  CHECK(data(t, msgA(t.provisional(), 1, "id=1 json 1"), 1102100, &slot, &fresh, 3) == Verdict::Full,
        "session reprise : sa place est protegee comme les autres");
  // Egalite d'age entre deux terminees : l'emplacement le plus bas.
  t.clear();
  CHECK(establish(t, 93, 1200000, 1) == 0, "0");
  CHECK(establish(t, 94, 1201000, 2) == 1, "1");
  CHECK(data(t, msgA(t.slot(0), 2, "id=2 json ping"), 1202000, &slot, &fresh, 1) == Verdict::Ok, "0 a 1202 s");
  CHECK(data(t, msgA(t.slot(1), 2, "id=2 json ping"), 1202000, &slot, &fresh, 2) == Verdict::Ok, "1 a 1202 s");
  t.end(0);
  t.end(1);
  CHECK(establish(t, 95, 1203000, 3) == 0, "egalite : l'emplacement 0");
  // end() sur une place libre, oubli et clear : la marque ne survit pas.
  t.clear();
  t.end(0);
  CHECK(!t.slot(0).used && !t.slot(0).ended, "end sur une place libre : rien");
  CHECK(establish(t, 96, 1300000, 1) == 0, "session");
  t.end(0);
  CHECK(t.expire(1300000 + kForgetMs) == 0x01 && !t.slot(0).ended, "oubliee : marque effacee");
  CHECK(establish(t, 97, 1400000, 1) == 0, "session");
  t.end(0);
  CHECK(t.clear() == 0x01 && !t.slot(0).ended, "clear : marque effacee");

  // wipe
  uint8_t secret[8] = {1, 2, 3, 4, 5, 6, 7, 8};
  wipe(secret, sizeof(secret));
  uint8_t zero[8] = {};
  CHECK(!memcmp(secret, zero, 8), "wipe");
}

int main() {
  testVectors();
  testParse();
  testWindow();
  testSessions();
  printf("h1 : %d verifications, %d echecs\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
````

`tests/hote/lancer.sh`, bloc 1 sur 1. Remplacer :

````sh
"$SORTIE/test_json"

echo "tests hote : tout est vert"
````

par :

````sh
"$SORTIE/test_json"

# Enveloppe H1 du transport reseau (components/h1) : C++17, crypto de CommonCrypto.
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/h1/include components/h1/h1_proto.cpp \
  tests/hote/test_h1.cpp -o "$SORTIE/test_h1"
"$SORTIE/test_h1"

echo "tests hote : tout est vert"
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `sh tests/hote/lancer.sh`
Expected: FAIL : `clang++: error: no such file or directory: 'components/h1/h1_proto.cpp'` (les autres tests passent avant)

- [ ] **Step 3 : le composant.**

`components/h1/CMakeLists.txt` (contenu complet) :

````cmake
# Enveloppe H1 du transport reseau, reprise du pont Halo (commit e114cd5) :
# h1_proto.cpp est pur (teste sur le Mac, tests/hote/test_h1.cpp), h1_crypto.cpp
# fournit HMAC-SHA256 et SHA-256 par mbedTLS (SHA materiel du C6).
idf_component_register(SRCS "h1_proto.cpp" "h1_crypto.cpp"
                       INCLUDE_DIRS "include"
                       PRIV_REQUIRES mbedtls)
````

`components/h1/include/h1_proto.h` (contenu complet) :

````c
#pragma once
// Repris du pont Halo (commit e114cd5) : enveloppe H1 du transport reseau, briques pures.
// ===========================================================================
//  Enveloppe H1 du transport reseau : briques pures
//
//  Datagrammes UDP entre l'app et la carte, a travers les routeurs de bordure
//  Thread. Integrite et authenticite par une cle partagee de 32 octets (PSK)
//  et HMAC-SHA256 ; pas de confidentialite en v1.
//
//    app  -> carte : H1 SALUT <kid> <na> <mac_salut>
//    carte -> app  : H1 DEFI <sid> <nc> <mac_defi>
//    puis, dans les deux sens : H1 <sid> <ctr> <mac> <charge>
//
//  Textes canoniques (le MAC porte sur eux, octet pour octet) : hexadecimal
//  en MAJUSCULES seulement, ctr en decimal sans zero de tete (1..4294967295).
//  Toute autre forme est refusee a la lecture.
//
//  Pur C++17, sans ESP-IDF ni Arduino : teste sur l'hote (tests/hote/test_h1.cpp). Le
//  HMAC et le SHA-256 viennent de la plateforme : mbedTLS (SHA materiel du C6,
//  h1_crypto.cpp) sur la carte, CommonCrypto dans les tests.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

namespace h1 {

constexpr size_t kKeyLen = 32;     // PSK et cle de session
constexpr size_t kNonceLen = 16;   // na, nc
constexpr size_t kMacLen = 16;     // MAC tronque
constexpr size_t kKidHex = 8;      // empreinte de la cle
constexpr size_t kSidHex = 8;
constexpr size_t kNonceHex = 32;
constexpr size_t kMacHex = 32;
constexpr uint32_t kWindow = 32;               // fenetre glissante des ctr, par sens
constexpr uint32_t kForgetMs = 600000;         // session oubliee apres 10 min sans message valide
constexpr uint32_t kProvisionalMs = 30000;     // poignee de main sans premier message : oubliee
constexpr uint8_t kDefiPerSecond = 2;          // DEFI emis au plus, EN TOUT
constexpr uint8_t kSlots = 2;                  // sessions etablies
// Une session etablie active depuis moins longtemps n'est jamais evincee par
// une nouvelle (sauf terminee par 'json 0' : Table::end) : trois clients pour
// deux places ne se chassent pas en boucle.
constexpr uint32_t kEvictIdleMs = 30000;
constexpr uint8_t kSeenNa = 16;                // na des derniers SALUT acceptes (rejeu d'un SALUT)
// "H1 " sid " " ctr " " mac " " : 3 + 8 + 1 + 10 + 1 + 32 + 1
constexpr size_t kHeaderMax = 56;
// "H1 DEFI " sid " " nc " " mac : 8 + 8 + 1 + 32 + 1 + 32
constexpr size_t kDefiLen = 82;
// "H1 SALUT " kid " " na " " mac : 9 + 8 + 1 + 32 + 1 + 32 (plus long que le DEFI : aucune amplification)
constexpr size_t kSalutLen = 83;

// --- Crypto de la plateforme -------------------------------------------------

struct Part {
  const void *p;
  size_t n;
};
// HMAC-SHA256(key, concatenation des parts). false : echec de la plateforme
// (memoire) ; out est alors indefini et tout calcul qui en depend echoue
// (jamais de MAC par defaut : un MAC nul serait devinable).
bool hmacSha256(const uint8_t *key, size_t keyLen, const Part *parts, size_t nParts, uint8_t out[32]);
bool sha256(const void *p, size_t n, uint8_t out[32]);

// --- Outils ------------------------------------------------------------------

// Comparaison en temps constant (aucune sortie anticipee).
bool equalCt(const uint8_t *a, const uint8_t *b, size_t n);
// Mise a zero que l'optimiseur ne retire pas (cles et secrets sur la pile).
void wipe(void *p, size_t n);
// 2n chiffres majuscules, puis un 0 final.
void toHex(const uint8_t *p, size_t n, char *out);
// Exactement 2n chiffres MAJUSCULES : false sinon (out est alors indefini).
bool fromHex(const char *s, size_t n, uint8_t *out);

// kid : 8 premiers chiffres (majuscules) de SHA-256(psk).
bool keyId(const uint8_t psk[kKeyLen], char kid[kKidHex + 1]);

// mac_salut = HMAC-SHA256(psk, "H1|SALUT|" kid "|" na), 16 premiers octets : seul
// qui a la cle peut faire depenser un DEFI ou remplacer la poignee de main en cours.
bool salutMac(const uint8_t psk[kKeyLen], const char *kid, const char *naHex, uint8_t out[kMacLen]);
// mac_defi = HMAC-SHA256(psk, "H1|DEFI|" kid "|" na "|" nc "|" sid), 16 premiers octets.
bool defiMac(const uint8_t psk[kKeyLen], const char *kid, const char *naHex, const char *ncHex, const char *sidHex,
             uint8_t out[kMacLen]);
// Ks = HMAC-SHA256(psk, "H1|SESSION|" na "|" nc "|" sid).
bool sessionKey(const uint8_t psk[kKeyLen], const char *naHex, const char *ncHex, const char *sidHex,
                uint8_t ks[kKeyLen]);
// mac = HMAC-SHA256(Ks, sens "|" sid "|" ctr "|" charge), 16 premiers octets ; sens 'A'
// (app -> carte) ou 'C' (carte -> app).
bool messageMac(const uint8_t ks[kKeyLen], char dir, const char *sidHex, uint32_t ctr, const uint8_t *payload,
                size_t n, uint8_t out[kMacLen]);

// --- Lecture d'un datagramme -------------------------------------------------

enum class Kind : uint8_t { Invalid, Salut, Defi, Data };

struct Parsed {
  Kind kind = Kind::Invalid;
  char kid[kKidHex + 1] = {};     // Salut
  char na[kNonceHex + 1] = {};    // Salut
  char nc[kNonceHex + 1] = {};    // Defi
  char sidHex[kSidHex + 1] = {};  // Defi, Data
  uint32_t sid = 0;
  uint32_t ctr = 0;               // Data
  uint8_t mac[kMacLen] = {};      // Salut, Defi, Data
  const uint8_t *payload = nullptr;  // Data : tout ce qui suit la quatrieme espace
  size_t payloadLen = 0;
};
Parsed parse(const uint8_t *d, size_t n);

// --- Fenetre contre le rejeu et le desordre ---------------------------------

// top : plus grand ctr accepte ; bits : bit i = top - i deja vu.
struct Window {
  uint32_t top = 0, bits = 0;
  bool fresh(uint32_t ctr) const;  // acceptable (jamais vu, dans la fenetre)
  void commit(uint32_t ctr);       // apres un MAC juste seulement
};

// --- Sessions (cote carte) ----------------------------------------------------

// Adresses du plus recent message au MAC juste (ctr le plus haut vu) : l'app
// (adresse et port, qui changent avec les adresses temporaires de l'iPhone)
// et l'adresse locale qu'elle a visee (source des reponses). Un message plus
// ancien, retarde ou rejoue d'ailleurs, ne detourne pas les reponses.
struct Peer {
  uint8_t ip[16] = {};
  uint16_t port = 0;
  uint8_t local[16] = {};
};

struct Session {
  bool used = false;
  uint32_t sid = 0;
  char sidHex[kSidHex + 1] = {};
  uint8_t ks[kKeyLen] = {};
  Window rx;             // ctr de l'app
  uint32_t tx = 0;       // dernier ctr emis par la carte
  uint32_t since = 0;    // creation (provisoire) ou promotion (etablie)
  uint32_t lastAt = 0;   // dernier message au MAC juste (ou SALUT pour la provisoire)
  bool ended = false;    // 'json 0' execute : place reprenable tout de suite (end, resume)
  Peer peer;
};

enum class Verdict : uint8_t {
  Ok,          // Data : message accepte ; Salut : DEFI a emettre
  Invalid,     // forme refusee
  NoKey,       // pas de cle : transport coupe
  WrongKid,    // SALUT pour une autre cle
  Limited,     // plus de kDefiPerSecond DEFI dans la seconde
  UnknownSid,  // aucune session ne porte ce sid
  BadMac,
  Replay,      // ctr deja vu ou hors fenetre ; SALUT deja vu (meme na)
  Full,        // premier message, mais les deux places sont actives (kEvictIdleMs) et aucune terminee
};
const char *verdictText(Verdict v);

class Table {
 public:
  // Cle en vigueur (nullptr : aucune). Changer de cle fait tout tomber. false :
  // empreinte incalculable, le transport reste coupe (hasKey() faux).
  bool setKey(const uint8_t *psk);
  bool hasKey() const { return hasKey_; }
  const char *kid() const { return kid_; }

  // Aleatoire de la plateforme (nc, sid), tire seulement pour un SALUT admis :
  // kid, MAC, na jamais vu, limite des DEFI.
  typedef void (*Random)(void *p, size_t n);
  // SALUT : session provisoire (une seule place, la precedente est remplacee)
  // et texte du DEFI dans out (kDefiLen octets, sans 0 final).
  Verdict onSalut(const Parsed &p, Random rnd, const Peer &from, uint32_t now, char out[kDefiLen]);
  bool sidInUse(uint32_t sid) const;

  // Message de l'app. Ok : *slot = session etablie (0..kSlots-1) ; *fresh vrai si
  // elle vient d'y etre promue (premier message au MAC juste de la poignee de
  // main) : l'etat de session JSON de cet emplacement repart de zero. La session
  // provisoire promue prend un emplacement libre, sinon celui d'une session
  // terminee (end), sinon celui de la session la moins recemment active, si
  // elle est muette depuis kEvictIdleMs ; sinon Full (rien n'est promu ; ce ctr
  // est brule, l'app renvoie avec un ctr neuf).
  Verdict onData(const Parsed &p, const Peer &from, uint32_t now, uint8_t *slot, bool *fresh);

  // L'app a termine la session slot ('json 0') : elle reste etablie (ses
  // dernieres lignes partent tant que sa place n'est pas reprise, un renvoi du
  // json 0 recoit sa reponse), mais sa place revient au prochain client sans
  // attendre kEvictIdleMs.
  void end(uint8_t slot);
  // Nouvelle commande admise de la session slot (jamais un renvoi servi par le
  // cache) : elle sert de nouveau, sa place est protegee comme les autres
  // (un client qui envoie "json 0" puis "json 1").
  void resume(uint8_t slot);

  // En-tete d'un message de la carte pour l'emplacement slot, MAC calcule sur
  // payload : "H1 <sid> <ctr> <mac> " dans hdr, longueur rendue (0 : pas de
  // session, ou compteur epuise).
  size_t seal(uint8_t slot, const uint8_t *payload, size_t n, char hdr[kHeaderMax + 1]);

  // Oubli des sessions inactives. Rend le masque des emplacements liberes
  // (bit i : emplacement i).
  uint8_t expire(uint32_t now);
  // Tout tombe (cle changee ou effacee). Rend le masque des emplacements liberes.
  uint8_t clear();

  const Session &slot(uint8_t i) const { return est_[i < kSlots ? i : 0]; }
  const Session &provisional() const { return prov_; }
  uint8_t established() const;

 private:
  bool hasKey_ = false;
  uint8_t psk_[kKeyLen] = {};
  char kid_[kKidHex + 1] = {};
  Session est_[kSlots];
  Session prov_;
  uint32_t defiAt_ = 0;
  uint8_t defiN_ = 0;
  bool defiStarted_ = false;
  uint8_t seen_[kSeenNa][kNonceLen] = {};
  uint8_t seenN_ = 0, seenNext_ = 0;
};

}  // namespace h1
````

`components/h1/h1_proto.cpp` (contenu complet) :

````cpp
// Repris du pont Halo (commit e114cd5) : enveloppe H1 du transport reseau (voir h1_proto.h).
#include "h1_proto.h"

#include <string.h>

namespace h1 {

// ===========================================================================
//  Outils
// ===========================================================================

static const char kHex[] = "0123456789ABCDEF";

bool equalCt(const uint8_t *a, const uint8_t *b, size_t n) {
  uint8_t d = 0;
  for (size_t i = 0; i < n; i++) d |= (uint8_t)(a[i] ^ b[i]);
  return d == 0;
}

void wipe(void *p, size_t n) {
  volatile uint8_t *v = (volatile uint8_t *)p;
  while (n--) *v++ = 0;
}

void toHex(const uint8_t *p, size_t n, char *out) {
  for (size_t i = 0; i < n; i++) {
    out[2 * i] = kHex[p[i] >> 4];
    out[2 * i + 1] = kHex[p[i] & 0x0F];
  }
  out[2 * n] = 0;
}

static int nibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;  // minuscules refusees : un seul texte canonique
}

bool fromHex(const char *s, size_t n, uint8_t *out) {
  for (size_t i = 0; i < n; i++) {
    const int hi = nibble(s[2 * i]), lo = nibble(s[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = (uint8_t)(hi << 4 | lo);
  }
  return true;
}

static void hex32(uint32_t v, char out[kSidHex + 1]) {
  for (int i = 7; i >= 0; i--) {
    out[i] = kHex[v & 0x0F];
    v >>= 4;
  }
  out[8] = 0;
}

// Decimal sans zero de tete ; rend la longueur (1..10).
static size_t decimal(uint32_t v, char out[11]) {
  char t[10];
  size_t n = 0;
  do {
    t[n++] = (char)('0' + v % 10);
    v /= 10;
  } while (v);
  for (size_t i = 0; i < n; i++) out[i] = t[n - 1 - i];
  out[n] = 0;
  return n;
}

bool keyId(const uint8_t psk[kKeyLen], char kid[kKidHex + 1]) {
  uint8_t d[32];
  const bool ok = sha256(psk, kKeyLen, d);
  if (ok) toHex(d, kKidHex / 2, kid);
  wipe(d, sizeof(d));
  return ok;
}

bool salutMac(const uint8_t psk[kKeyLen], const char *kid, const char *naHex, uint8_t out[kMacLen]) {
  const Part parts[] = {{"H1|SALUT|", 9}, {kid, kKidHex}, {"|", 1}, {naHex, kNonceHex}};
  uint8_t full[32];
  const bool ok = hmacSha256(psk, kKeyLen, parts, sizeof(parts) / sizeof(parts[0]), full);
  if (ok) memcpy(out, full, kMacLen);
  wipe(full, sizeof(full));
  return ok;
}

bool defiMac(const uint8_t psk[kKeyLen], const char *kid, const char *naHex, const char *ncHex, const char *sidHex,
             uint8_t out[kMacLen]) {
  const Part parts[] = {{"H1|DEFI|", 8}, {kid, kKidHex},   {"|", 1}, {naHex, kNonceHex},
                        {"|", 1},        {ncHex, kNonceHex}, {"|", 1}, {sidHex, kSidHex}};
  uint8_t full[32];
  const bool ok = hmacSha256(psk, kKeyLen, parts, sizeof(parts) / sizeof(parts[0]), full);
  if (ok) memcpy(out, full, kMacLen);
  wipe(full, sizeof(full));
  return ok;
}

bool sessionKey(const uint8_t psk[kKeyLen], const char *naHex, const char *ncHex, const char *sidHex,
                uint8_t ks[kKeyLen]) {
  const Part parts[] = {{"H1|SESSION|", 11}, {naHex, kNonceHex}, {"|", 1},
                        {ncHex, kNonceHex},  {"|", 1},           {sidHex, kSidHex}};
  return hmacSha256(psk, kKeyLen, parts, sizeof(parts) / sizeof(parts[0]), ks);
}

bool messageMac(const uint8_t ks[kKeyLen], char dir, const char *sidHex, uint32_t ctr, const uint8_t *payload,
                size_t n, uint8_t out[kMacLen]) {
  char c[11];
  const size_t cn = decimal(ctr, c);
  const char d[2] = {dir, '|'};
  const Part parts[] = {{d, 2}, {sidHex, kSidHex}, {"|", 1}, {c, cn}, {"|", 1}, {payload, n}};
  uint8_t full[32];
  const bool ok = hmacSha256(ks, kKeyLen, parts, sizeof(parts) / sizeof(parts[0]), full);
  if (ok) memcpy(out, full, kMacLen);
  wipe(full, sizeof(full));
  return ok;
}

// ===========================================================================
//  Lecture
// ===========================================================================

// Jeton de len caracteres exactement a d[*i], suivi d'une espace (ou de la fin
// si last) ; *i passe apres l'espace.
static bool token(const uint8_t *d, size_t n, size_t *i, size_t len, bool last) {
  if (*i + len > n) return false;
  const size_t end = *i + len;
  if (last ? end != n : (end >= n || d[end] != ' ')) return false;
  *i = end + (last ? 0 : 1);
  return true;
}

static bool hexToken(const uint8_t *d, size_t at, size_t hexLen, char *text, uint8_t *bytes) {
  memcpy(text, d + at, hexLen);
  text[hexLen] = 0;
  uint8_t tmp[kMacLen];
  uint8_t *out = bytes ? bytes : tmp;
  return fromHex(text, hexLen / 2, out);
}

Parsed parse(const uint8_t *d, size_t n) {
  Parsed p;
  if (n < 3 || memcmp(d, "H1 ", 3)) return p;
  size_t i = 3;
  if (n - i >= 6 && !memcmp(d + i, "SALUT ", 6)) {
    i += 6;
    size_t at = i;
    if (!token(d, n, &i, kKidHex, false) || !hexToken(d, at, kKidHex, p.kid, nullptr)) return p;
    at = i;
    uint8_t na[kNonceLen];
    if (!token(d, n, &i, kNonceHex, false)) return p;
    memcpy(p.na, d + at, kNonceHex);
    p.na[kNonceHex] = 0;
    if (!fromHex(p.na, kNonceLen, na)) return p;
    at = i;
    char mac[kMacHex + 1];
    if (!token(d, n, &i, kMacHex, true) || !hexToken(d, at, kMacHex, mac, p.mac)) return p;
    p.kind = Kind::Salut;
    return p;
  }
  if (n - i >= 5 && !memcmp(d + i, "DEFI ", 5)) {
    i += 5;
    size_t at = i;
    uint8_t sid[4];
    if (!token(d, n, &i, kSidHex, false) || !hexToken(d, at, kSidHex, p.sidHex, sid)) return p;
    p.sid = (uint32_t)sid[0] << 24 | (uint32_t)sid[1] << 16 | (uint32_t)sid[2] << 8 | sid[3];
    at = i;
    uint8_t nc[kNonceLen];
    if (!token(d, n, &i, kNonceHex, false)) return p;
    memcpy(p.nc, d + at, kNonceHex);
    p.nc[kNonceHex] = 0;
    if (!fromHex(p.nc, kNonceLen, nc)) return p;
    at = i;
    char mac[kMacHex + 1];
    if (!token(d, n, &i, kMacHex, true) || !hexToken(d, at, kMacHex, mac, p.mac)) return p;
    p.kind = Kind::Defi;
    return p;
  }
  // Message : sid, ctr, mac, charge.
  size_t at = i;
  uint8_t sid[4];
  if (!token(d, n, &i, kSidHex, false) || !hexToken(d, at, kSidHex, p.sidHex, sid)) return p;
  p.sid = (uint32_t)sid[0] << 24 | (uint32_t)sid[1] << 16 | (uint32_t)sid[2] << 8 | sid[3];
  // ctr : 1 a 10 chiffres, sans zero de tete, au plus 4294967295.
  uint64_t ctr = 0;
  size_t digits = 0;
  while (i < n && d[i] >= '0' && d[i] <= '9' && digits < 11) {
    ctr = ctr * 10 + (uint64_t)(d[i] - '0');
    i++;
    digits++;
  }
  if (!digits || digits > 10 || d[i - digits] == '0' || ctr > 0xFFFFFFFFull || i >= n || d[i] != ' ') return p;
  p.ctr = (uint32_t)ctr;
  i++;
  at = i;
  char mac[kMacHex + 1];
  if (!token(d, n, &i, kMacHex, false) || !hexToken(d, at, kMacHex, mac, p.mac)) return p;
  p.payload = d + i;
  p.payloadLen = n - i;
  p.kind = Kind::Data;
  return p;
}

// ===========================================================================
//  Fenetre
// ===========================================================================

bool Window::fresh(uint32_t ctr) const {
  if (ctr == 0) return false;
  if (ctr > top) return true;
  const uint32_t back = top - ctr;
  if (back >= kWindow) return false;
  return !(bits & (1u << back));
}

void Window::commit(uint32_t ctr) {
  if (ctr > top) {
    const uint32_t shift = ctr - top;
    bits = shift >= kWindow ? 0 : bits << shift;
    bits |= 1u;
    top = ctr;
  } else if (top - ctr < kWindow) {
    bits |= 1u << (top - ctr);
  }
}

// ===========================================================================
//  Sessions
// ===========================================================================

const char *verdictText(Verdict v) {
  switch (v) {
    case Verdict::Ok: return "ok";
    case Verdict::Invalid: return "forme";
    case Verdict::NoKey: return "sans_cle";
    case Verdict::WrongKid: return "autre_cle";
    case Verdict::Limited: return "limite";
    case Verdict::UnknownSid: return "sid_inconnu";
    case Verdict::BadMac: return "mac_faux";
    case Verdict::Replay: return "rejeu";
    case Verdict::Full: return "complet";
  }
  return "?";
}

bool Table::setKey(const uint8_t *psk) {
  clear();
  hasKey_ = false;
  wipe(psk_, sizeof(psk_));
  kid_[0] = 0;
  wipe(seen_, sizeof(seen_));
  seenN_ = seenNext_ = 0;
  if (!psk) return true;
  if (!keyId(psk, kid_)) {
    kid_[0] = 0;
    return false;
  }
  memcpy(psk_, psk, kKeyLen);
  hasKey_ = true;
  return true;
}

bool Table::sidInUse(uint32_t sid) const {
  for (const Session &s : est_)
    if (s.used && s.sid == sid) return true;
  return prov_.used && prov_.sid == sid;
}

Verdict Table::onSalut(const Parsed &p, Random rnd, const Peer &from, uint32_t now, char out[kDefiLen]) {
  if (p.kind != Kind::Salut) return Verdict::Invalid;
  if (!hasKey_) return Verdict::NoKey;
  if (memcmp(p.kid, kid_, kKidHex)) return Verdict::WrongKid;
  // Limite globale : pas par source (adresses usurpables), pas d'amplification.
  // Jugee avant le HMAC (un SALUT de trop ne coute rien) ; seul un SALUT servi
  // la consomme.
  if (!defiStarted_ || now - defiAt_ >= 1000) {
    defiStarted_ = true;
    defiAt_ = now;
    defiN_ = 0;
  }
  if (defiN_ >= kDefiPerSecond) return Verdict::Limited;
  // Seul qui a la cle passe : ni DEFI depense, ni poignee de main remplacee.
  uint8_t mac[kMacLen];
  if (!salutMac(psk_, kid_, p.na, mac) || !equalCt(mac, p.mac, kMacLen)) return Verdict::BadMac;
  // Un SALUT rejoue (meme na) n'est plus servi. L'app tire un na neuf a chaque essai.
  uint8_t na[kNonceLen];
  fromHex(p.na, kNonceLen, na);  // deja verifie par parse()
  for (uint8_t i = 0; i < seenN_; i++)
    if (!memcmp(seen_[i], na, kNonceLen)) return Verdict::Replay;

  uint8_t nc[kNonceLen];
  rnd(nc, sizeof(nc));
  uint32_t sid = 0;
  for (uint8_t i = 0; i < 4 && (!sid || sidInUse(sid)); i++) rnd(&sid, sizeof(sid));
  if (!sid || sidInUse(sid)) return Verdict::Invalid;

  Session s;
  s.used = true;
  s.sid = sid;
  hex32(sid, s.sidHex);
  char ncHex[kNonceHex + 1];
  toHex(nc, kNonceLen, ncHex);
  const bool ok = sessionKey(psk_, p.na, ncHex, s.sidHex, s.ks) && defiMac(psk_, kid_, p.na, ncHex, s.sidHex, mac);
  if (!ok) {  // echec de la plateforme : aucune session, aucun DEFI
    wipe(&s, sizeof(s));
    return Verdict::Invalid;
  }
  defiN_++;
  memcpy(seen_[seenNext_], na, kNonceLen);
  seenNext_ = (uint8_t)((seenNext_ + 1) % kSeenNa);
  if (seenN_ < kSeenNa) seenN_++;
  s.since = s.lastAt = now;
  s.peer = from;
  prov_ = s;
  wipe(&s, sizeof(s));

  char macHex[kMacHex + 1];
  toHex(mac, kMacLen, macHex);
  memcpy(out, "H1 DEFI ", 8);
  memcpy(out + 8, prov_.sidHex, kSidHex);
  out[16] = ' ';
  memcpy(out + 17, ncHex, kNonceHex);
  out[49] = ' ';
  memcpy(out + 50, macHex, kMacHex);
  return Verdict::Ok;
}

Verdict Table::onData(const Parsed &p, const Peer &from, uint32_t now, uint8_t *slot, bool *fresh) {
  *fresh = false;
  if (p.kind != Kind::Data) return Verdict::Invalid;
  if (!hasKey_) return Verdict::NoKey;
  Session *s = nullptr;
  int idx = -1;
  for (uint8_t i = 0; i < kSlots; i++)
    if (est_[i].used && est_[i].sid == p.sid) {
      s = &est_[i];
      idx = i;
    }
  if (!s && prov_.used && prov_.sid == p.sid) s = &prov_;
  if (!s) return Verdict::UnknownSid;
  uint8_t mac[kMacLen];
  if (!messageMac(s->ks, 'A', s->sidHex, p.ctr, p.payload, p.payloadLen, mac) || !equalCt(mac, p.mac, kMacLen))
    return Verdict::BadMac;  // echec de la plateforme compris : jamais accepte
  // Le rejeu se juge apres le MAC : un ctr forge ne pousse jamais la fenetre.
  if (!s->rx.fresh(p.ctr)) return Verdict::Replay;
  // Seul le plus recent message fixe l'adresse des reponses.
  const bool newest = p.ctr > s->rx.top;
  if (idx >= 0) {
    s->rx.commit(p.ctr);
    s->lastAt = now;
    if (newest) s->peer = from;
    *slot = (uint8_t)idx;
    return Verdict::Ok;
  }
  // Premier message au MAC juste de la poignee de main : la session devient
  // etablie, dans un emplacement libre, sinon a la place d'une session
  // terminee par 'json 0', sinon a celle de la moins recemment active si elle
  // est muette depuis kEvictIdleMs. Des SALUT du LAN (sans la cle) ne touchent
  // a rien ; trois clients pour deux places ne se chassent pas en boucle.
  uint8_t k = 0;
  bool found = false;
  for (uint8_t i = 0; i < kSlots && !found; i++)
    if (!est_[i].used) {
      k = i;
      found = true;
    }
  if (!found) {
    // Une session terminee ('json 0') d'abord, la moins recemment active parmi
    // elles ; sinon la moins recemment active de toutes.
    uint32_t oldest = 0;
    bool ended = false;
    for (uint8_t i = 0; i < kSlots; i++) {
      const uint32_t age = now - est_[i].lastAt;
      if (i == 0 || (est_[i].ended && !ended) || (est_[i].ended == ended && age > oldest)) {
        oldest = age;
        ended = est_[i].ended;
        k = i;
      }
    }
    if (!ended && oldest < kEvictIdleMs) {
      // Rien de promu, mais ce ctr est brule : un rejeu de ce message ne
      // promouvra jamais la session vers l'adresse d'un autre. L'app renvoie
      // avec un ctr neuf.
      prov_.rx.commit(p.ctr);
      return Verdict::Full;
    }
  }
  prov_.rx.commit(p.ctr);
  prov_.lastAt = now;
  prov_.peer = from;
  est_[k] = prov_;
  est_[k].since = now;
  prov_ = Session();
  *slot = k;
  *fresh = true;
  return Verdict::Ok;
}

size_t Table::seal(uint8_t slot, const uint8_t *payload, size_t n, char hdr[kHeaderMax + 1]) {
  if (slot >= kSlots) return 0;
  Session &s = est_[slot];
  if (!s.used || s.tx == 0xFFFFFFFFu) return 0;
  uint8_t mac[kMacLen];
  if (!messageMac(s.ks, 'C', s.sidHex, s.tx + 1, payload, n, mac)) return 0;
  s.tx++;
  size_t k = 0;
  memcpy(hdr, "H1 ", 3);
  k = 3;
  memcpy(hdr + k, s.sidHex, kSidHex);
  k += kSidHex;
  hdr[k++] = ' ';
  k += decimal(s.tx, hdr + k);
  hdr[k++] = ' ';
  toHex(mac, kMacLen, hdr + k);
  k += kMacHex;
  hdr[k++] = ' ';
  hdr[k] = 0;
  return k;
}

void Table::end(uint8_t slot) {
  if (slot < kSlots && est_[slot].used) est_[slot].ended = true;
}

void Table::resume(uint8_t slot) {
  if (slot < kSlots) est_[slot].ended = false;
}

uint8_t Table::expire(uint32_t now) {
  uint8_t mask = 0;
  for (uint8_t i = 0; i < kSlots; i++)
    if (est_[i].used && now - est_[i].lastAt >= kForgetMs) {
      est_[i] = Session();
      mask |= (uint8_t)(1u << i);
    }
  if (prov_.used && now - prov_.lastAt >= kProvisionalMs) prov_ = Session();
  return mask;
}

uint8_t Table::clear() {
  uint8_t mask = 0;
  for (uint8_t i = 0; i < kSlots; i++) {
    if (est_[i].used) mask |= (uint8_t)(1u << i);
    est_[i] = Session();
  }
  prov_ = Session();
  return mask;
}

uint8_t Table::established() const {
  uint8_t n = 0;
  for (const Session &s : est_) n += s.used ? 1 : 0;
  return n;
}

}  // namespace h1
````

`components/h1/h1_crypto.cpp` (contenu complet) :

````cpp
// Repris du pont Halo (commit e114cd5) : crypto de l'enveloppe H1.
// Crypto de l'enveloppe H1 sur la carte : mbedTLS, SHA-256 materiel du C6
// (CONFIG_MBEDTLS_HARDWARE_SHA). Les tests hote fournissent la leur
// (tests/hote/test_h1.cpp, CommonCrypto).
//
// Appels sous le verrou de net_udp seulement (firmware/main/net_udp.cpp : poignee
// de main, scellement, verification, 'json cle nouvelle'), depuis plusieurs taches :
// un seul contexte HMAC, prepare une fois (mbedtls_md_setup alloue), puis remis a
// zero par chaque mbedtls_md_hmac_starts. sha256 n'a pas d'etat partage.
#include <mbedtls/md.h>
#include <mbedtls/sha256.h>
#include <string.h>

#include "h1_proto.h"

namespace h1 {

static mbedtls_md_context_t sCtx;
static bool sReady = false;

static bool ready() {
  if (sReady) return true;
  mbedtls_md_init(&sCtx);
  const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!info || mbedtls_md_setup(&sCtx, info, 1) != 0) {
    mbedtls_md_free(&sCtx);
    return false;  // nouvel essai au prochain appel
  }
  sReady = true;
  return true;
}

bool hmacSha256(const uint8_t *key, size_t keyLen, const Part *parts, size_t nParts, uint8_t out[32]) {
  if (!ready() || mbedtls_md_hmac_starts(&sCtx, key, keyLen) != 0) return false;
  for (size_t i = 0; i < nParts; i++)
    if (parts[i].n && mbedtls_md_hmac_update(&sCtx, (const unsigned char *)parts[i].p, parts[i].n) != 0)
      return false;
  return mbedtls_md_hmac_finish(&sCtx, out) == 0;
}

bool sha256(const void *p, size_t n, uint8_t out[32]) {
  return mbedtls_sha256((const unsigned char *)p, n, out, 0) == 0;
}

}  // namespace h1
````

- [ ] **Step 4 : lancer les tests, tout est vert.**

Run: `sh tests/hote/lancer.sh`
Expected: `h1 : 121 verifications, 0 echecs` (et `json : 283 verifications, 0 echecs`, inchangé), puis `tests hote : tout est vert`.

- [ ] **Step 5 : le composant compile aussi pour la carte.** Il est neuf : `reconfigure` d'abord, dans les deux firmwares (le `main` de l'écoute dépend de tous les composants). Rien ne l'appelle encore : c'est l'épreuve de gcc, des options d'ESP-IDF et de mbedTLS.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py reconfigure >/dev/null && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader") && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py reconfigure >/dev/null && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader")`
Expected : pour chaque firmware, sa taille (`amaran_ecoute.bin binary size …`, puis `amaran_pont.bin binary size …`) et `Project build complete. To flash, run:` ; aucune ligne `warning:` ni `error:`.

- [ ] **Step 6 : commit.**

```bash
git add components/h1 tests/hote/test_h1.cpp tests/hote/lancer.sh
git commit -m "$(printf "Composant h1 : enveloppe H1 du transport reseau, reprise du pont Halo, et ses tests\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 2: Le protocole à distance dans le composant `protocole` et dans `docs/PROTOCOLE-JSON.md` (C++ pur, testé sur le Mac)

**Files:**
- Modify: `components/protocole/include/json_ligne.h`, `components/protocole/json_ligne.cpp`
- Modify: `components/protocole/include/json_amaran.h`, `components/protocole/json_amaran.cpp`
- Modify: `tests/hote/test_json.cpp`, `tests/hote/lancer.sh`, `docs/PROTOCOLE-JSON.md`

**Interfaces:**
- Consumes : le composant `protocole` du plan 3b-1 (`Writer`, `Reply`, `maskCmd`, `Session`, `HelloBase`…).
- Produces (espace de noms `jsonp`, la Task 3 s'en sert) :
  - `json_ligne.h` : `Reply::key` et `Reply::kid` (réponse de `json cle nouvelle` : la clé, 64 hexa, et son empreinte) ; `textLine(w, n, ms, id, txt)` (message `texte`) ; `class ReplyCache` (8 places : `clear`, `put(r)`, `find(id)`, sans `msg` ni clé gardés) ; `class OutputLines` (4 096 octets : `clear`, `write(buf, n)`, `flush`, `next(&pos)`, `lost`) ; `Queue::frontReady(libres)`, `kPlacesLigne` (2), `kPlacesPeriodique` (7) ; `maskCmd` masque aussi `json cle nouvelle <alea>` ; `kRev` (1) ;
  - `json_amaran.h` : `Session::transport` (`"usb"`, `"udp"`) et `Session::trames` ; `Session sessionDistante()` (profil à distance : état 2 s, lampes 30 s, compteurs coupés, réseau 30 s) ; `const char *refusDistant(int argc, const char *const *argv)` (nul : permise ; sinon la raison, code `interdite`) ; `void ip6Texte(const uint8_t a[16], char out[40])` (RFC 5952) ; `struct AdresseIp`, `struct ReseauIp`, `reseauIp(w, n, ms, r)` (bloc `ip`) ; `struct Trame`, `trame(w, n, ms, t)` ; les capacités `trames`, `udp`, `cle`, `texte`.

Pourquoi : la spec 3b, section 7 (liste blanche, profil à distance, clé UDP) et le protocole, sections 5.1, 5.5, 6.3, 7.6 et 10. La liste blanche se juge sur les mots que la console exécuterait (`argv`, après `esp_console_split_argv`), jamais sur la ligne brute : chez Halo, `json 1 "bail" 0` passait. Les tests la jugent sur le découpage de la vraie fonction d'ESP-IDF : `lancer.sh` compile `split_argv.c` d'ESP-IDF tel quel (il n'inclut que `stdio`, `ctype` et `string` ; ESP-IDF n'est pas modifié). Tout ce qui forme une ligne se teste ici, sur le Mac : `test_json.cpp` vérifie chaque exemple du document, dans les deux sens, et le pire cas des nouveaux messages. Le composant gagne aussi les briques pures dont la Task 3 se sert : `OutputLines` (la sortie d'une commande, gardée sans verrou), `Queue::frontReady` et `kPlacesLigne`/`kPlacesPeriodique` (le débit vers une session distante).

- [ ] **Step 1 : le document du protocole.**

`docs/PROTOCOLE-JSON.md`, bloc 1 sur 13. Remplacer :

````markdown
# Protocole JSON du pont amaran (v1)

Le protocole machine entre le pont (ESP32-C6, `firmware/`) et l'app Amaran Compagnon (`apps/macos/`), par l'USB. Il reprend la version 1 du protocole du pont Halo (`~/Documents/Dev/esp32/benq/docs/PROTOCOLE-JSON.md`) : même tramage, même session, mêmes réponses. Seuls les messages propres au pont changent (sections 5 et 7). Le transport par Thread viendra au plan 3b-2.

Chaque exemple de la section 9 est formé tel quel par `tests/hote/test_json.cpp`, et chaque message que ce test forme figure dans la section 9 : le document et le firmware ne peuvent pas diverger.

## 0. Décisions en bref
````

par :

````markdown
# Protocole JSON du pont amaran (v1)

Le protocole machine entre le pont (ESP32-C6, `firmware/`) et l'app Amaran Compagnon (`apps/macos/`), par l'USB et par Thread. Il reprend la version 1 du protocole du pont Halo (`~/Documents/Dev/esp32/benq/docs/PROTOCOLE-JSON.md`) : même tramage, même session, mêmes réponses, même enveloppe H1 par Thread. Seuls les messages propres au pont changent (sections 5 et 7). Le canal par Thread est décrit à la section 10.

Chaque exemple des sections 9 et 10 est formé tel quel par `tests/hote/test_json.cpp`, et chaque message que ce test forme y figure : le document et le firmware ne peuvent pas diverger.

## 0. Décisions en bref
````

`docs/PROTOCOLE-JSON.md`, bloc 2 sur 13. Remplacer :

````markdown
| État | `etat` (blocs `pont` et `sante` chaque seconde ; une ligne par lampe à chaque changement, et toutes les 10 s), `compteurs` (chaque seconde), `reseau` (toutes les 5 s). Les événements sont des indices ; la vérité est dans l'état périodique. |
| Compatibilité | `v` dans chaque ligne ; les ajouts ne changent pas `v` ; l'app ignore les champs, types et valeurs qu'elle ne connaît pas. |
| Clés | Jamais dans une ligne machine : seulement leurs empreintes (8 premiers chiffres hexa, en majuscules, du SHA-256). `reponse.cmd` d'un `mesh cles` ne cite pas les clés, et le pont ne renvoie pas d'écho en mode machine. |

## 1. Vocabulaire et principes
````

par :

````markdown
| État | `etat` (blocs `pont` et `sante` chaque seconde ; une ligne par lampe à chaque changement, et toutes les 10 s), `compteurs` (chaque seconde), `reseau` (toutes les 5 s). Les événements sont des indices ; la vérité est dans l'état périodique. |
| Compatibilité | `v` dans chaque ligne ; les ajouts ne changent pas `v` ; l'app ignore les champs, types et valeurs qu'elle ne connaît pas. |
| Clés | Jamais dans une ligne machine : seulement leurs empreintes (8 premiers chiffres hexa, en majuscules, du SHA-256). `reponse.cmd` d'un `mesh cles` ne cite pas les clés, et le pont ne renvoie pas d'écho en mode machine. Seule exception : la clé UDP, rendue une fois, par l'USB, à sa création (10.2). |
| Thread | Les mêmes lignes, dans des datagrammes UDP signés (enveloppe H1 de Halo), port 5480 ; deux sessions à la fois au plus ; une liste blanche de commandes (10.5). |

## 1. Vocabulaire et principes
````

`docs/PROTOCOLE-JSON.md`, bloc 3 sur 13. Remplacer :

````markdown

Principes :
1. **Le pont n'attend jamais l'app.** Une ligne machine qui ne tient pas dans le tampon d'émission de l'USB est perdue et comptée (`json_perdus`) ; `json_perdus` compte aussi les événements perdus parce que leur file interne était pleine (ils n'ont pas de `n`).
2. **L'état est périodique, les événements sont des indices.** Une ligne perdue ou abîmée ne fausse rien durablement : l'instantané suivant corrige. L'app ne reconstruit jamais un état en cumulant des événements.
3. **Rien de nouveau ne part vers les lampes** à cause du protocole : l'app passe par les mêmes ordres que Maison et la console (`tache_lampes_ordre`).
````

par :

````markdown

Principes :
1. **Le pont n'attend jamais l'app.** Une ligne machine qui ne tient pas dans le tampon d'émission de l'USB est perdue et comptée (`json_perdus`) ; `json_perdus` compte aussi les événements perdus parce que leur file interne était pleine (ils n'ont pas de `n`). Chaque session compte ses propres lignes perdues : l'USB les siennes, chaque session distante les siennes (10.4).
2. **L'état est périodique, les événements sont des indices.** Une ligne perdue ou abîmée ne fausse rien durablement : l'instantané suivant corrige. L'app ne reconstruit jamais un état en cumulant des événements.
3. **Rien de nouveau ne part vers les lampes** à cause du protocole : l'app passe par les mêmes ordres que Maison et la console (`tache_lampes_ordre`).
````

`docs/PROTOCOLE-JSON.md`, bloc 4 sur 13. Remplacer :

````markdown
| `json reseau <ms>` | période des `reseau` | 0 ou 1 000 à 60 000 ; 5 000 par défaut |
| `json log 0\|1` | annonces du pont en messages `log` au lieu de texte | 0 par défaut |

Un argument hors bornes : `reponse` `usage`, avec les bornes dans `msg`.
````

par :

````markdown
| `json reseau <ms>` | période des `reseau` | 0 ou 1 000 à 60 000 ; 5 000 par défaut |
| `json log 0\|1` | annonces du pont en messages `log` au lieu de texte | 0 par défaut |
| `json trames 0\|1` | trafic Bluetooth Mesh en messages `trame` (7.6) ; à distance, coupé seul au bout de 60 s | 0 par défaut |
| `json cle nouvelle <64 hexa>` | crée la clé UDP (10.2) ; USB seulement | |
| `json cle efface` | efface la clé UDP : les sessions distantes tombent, le port 5480 se ferme | |

Un argument hors bornes : `reponse` `usage`, avec les bornes dans `msg`.
````

`docs/PROTOCOLE-JSON.md`, bloc 5 sur 13. Remplacer :

````markdown
| Champ | Sens |
|---|---|
| `rev` | révision mineure du protocole (0) |
| `fw` | version du firmware (`0.1.0-<commit>`) |
| `date`, `heure` | compilation |
````

par :

````markdown
| Champ | Sens |
|---|---|
| `rev` | révision mineure du protocole (1 : Thread, `trame`, `texte`) |
| `fw` | version du firmware (`0.1.0-<commit>`) |
| `date`, `heure` | compilation |
````

`docs/PROTOCOLE-JSON.md`, bloc 6 sur 13. Remplacer :

````markdown
| `reset`, `reset_n` | cause du démarrage : `mise_sous_tension`, `broche`, `logiciel`, `panique`, `chien_int`, `chien_tache`, `chien`, `baisse_tension`, `usb`, `inconnue` ; et la valeur de `esp_reset_reason()` |
| `up_s` | secondes depuis le démarrage |
| `session` | réglages en vigueur : `periode_ms`, `lampes_ms`, `compteurs_ms`, `reseau_ms`, `bail_s`, `log` |
| `limites` | `ligne_max` (1 024), `cmd_max` (127) |

**Bloc `identite`** : `boot` ; `mac` (MAC de la puce) ; `id` (`fabricant`, `produit`, `serie` = `AMARAN-<MAC>`, `nom`) ; `caps`, les capacités : `matter`, `thread`, `mesh`, `catalogue`, `ordres` (ordres de lampe asynchrones), `led`, `log`. L'app se règle sur `caps`, pas sur la version du firmware.

### 5.2 `config`
````

par :

````markdown
| `reset`, `reset_n` | cause du démarrage : `mise_sous_tension`, `broche`, `logiciel`, `panique`, `chien_int`, `chien_tache`, `chien`, `baisse_tension`, `usb`, `inconnue` ; et la valeur de `esp_reset_reason()` |
| `up_s` | secondes depuis le démarrage |
| `session` | réglages en vigueur : `transport` (`usb` ou `udp`), `periode_ms`, `lampes_ms`, `compteurs_ms`, `reseau_ms`, `bail_s`, `log`, `trames` |
| `limites` | `ligne_max` (1 024), `cmd_max` (127) |

**Bloc `identite`** : `boot` ; `mac` (MAC de la puce) ; `id` (`fabricant`, `produit`, `serie` = `AMARAN-<MAC>`, `nom`) ; `caps`, les capacités : `matter`, `thread`, `mesh`, `catalogue`, `ordres` (ordres de lampe asynchrones), `led`, `log`, `trames`, `udp` (canal par Thread), `cle` (`json cle`), `texte` (texte des commandes à distance). L'app se règle sur `caps`, pas sur la version du firmware.

### 5.2 `config`
````

`docs/PROTOCOLE-JSON.md`, bloc 7 sur 13. Remplacer :

````markdown
Une lampe lue en marche à l'intensité 0 est noire : Maison la montre éteinte. Sa place dans Maison se déduit de `maison` : un `endpoint` ; sinon `masquee` ; sinon jamais vue ; sinon (vue, non masquée, sans endpoint) hors de Maison après un échec.

**Bloc `sante`** (toutes les `periode_ms`) : `boot`, `up_s` ; `commande` : l'`id` de la commande de la console en cours, ou `null` (6.2) ; `led` (`motif` du voyant, `test`, `depuis_ms` : âge de la phase du motif) ; `matter` (`en_service`, `thread` attaché, `identifie`, `ble` : annonce de mise en service en cours) ; `sys` (`heap`, `heap_min`, `heap_bloc`, `piles` : octets jamais utilisés de chaque tâche, `null` si elle n'existe pas, `json_perdus` : lignes perdues, et événements perdus file pleine, `json_trop_longs`, `rejets` : lignes refusées pour longueur ou cadence).

### 5.4 `compteurs`
````

par :

````markdown
Une lampe lue en marche à l'intensité 0 est noire : Maison la montre éteinte. Sa place dans Maison se déduit de `maison` : un `endpoint` ; sinon `masquee` ; sinon jamais vue ; sinon (vue, non masquée, sans endpoint) hors de Maison après un échec.

**Bloc `sante`** (toutes les `periode_ms`) : `boot`, `up_s` ; `commande` : l'`id` de la commande de la console en cours, ou `null` (6.2) ; `led` (`motif` du voyant, `test`, `depuis_ms` : âge de la phase du motif) ; `matter` (`en_service`, `thread` attaché, `identifie`, `ble` : annonce de mise en service en cours) ; `sys` (`heap`, `heap_min`, `heap_bloc`, `piles` : octets jamais utilisés de chaque tâche, `null` si elle n'existe pas, `json_perdus` : lignes perdues de cette session, et événements perdus file pleine, `json_trop_longs`, `rejets` : lignes refusées pour longueur ou cadence).

### 5.4 `compteurs`
````

`docs/PROTOCOLE-JSON.md`, bloc 8 sur 13. Remplacer :

````markdown
### 5.5 `reseau`

**Bloc `matter`** (toutes les `reseau_ms`) : `demarre`, `fabriques`, `ble`, `identifie` ; `abonnements` (`demandes`, `plafonnes`, `etablis`, `termines`, `plafond_s`) ; `code_manuel` et `qr` (charge `MT:…`), pour ajouter le pont à Maison, ou `null`. Les abonnements actifs valent à peu près `etablis − termines`.

**Bloc `thread`** : `role` (`disabled`, `detached`, `child`, `router`, `leader`), tel que l'annonce le dernier événement d'OpenThread ; `attache`. Le pont ne prend jamais le verrou d'OpenThread depuis ses tâches : rien de plus en 3b-1.

### 5.6 `hb` et `fin`

`hb` : battement quand les `etat` sont coupés ou lents (3.5) : `boot`, `up_s`, `json_perdus` (comme dans le bloc `sante` : lignes et événements perdus), et `commande` comme le bloc `sante`.

`fin` : dernier message d'une session machine. `cause` : `commande` (`json 0`) ou `bail`.
````

par :

````markdown
### 5.5 `reseau`

**Bloc `matter`** (toutes les `reseau_ms`) : `demarre`, `fabriques`, `ble`, `identifie` ; `abonnements` (`demandes`, `plafonnes`, `etablis`, `termines`, `plafond_s`) ; `code_manuel` et `qr` (charge `MT:…`), pour ajouter le pont à Maison, ou `null` ; toujours `null` vers une session distante (10.1). Les abonnements actifs valent à peu près `etablis − termines`.

**Bloc `thread`** : `role` (`disabled`, `detached`, `child`, `router`, `leader`), tel que l'annonce le dernier événement d'OpenThread ; `attache`. Le pont ne prend jamais le verrou d'OpenThread depuis ses tâches : ce qu'il lui demande passe par la file de tâches d'OpenThread.

**Bloc `ip`** : `srp`, le nom que le pont publie par SRP (16 hexa ; l'app le résout en `<srp>.local`), ou `null` ; `adresses`, ses adresses (`type` : `omr`, `ml_eid`, `autre` ; `adresse`) ; `udp` : `port` (5480), `cle` (une clé UDP existe), `empreinte` (8 hexa, ou `null`), `ouvert` (le port écoute), `sessions` (sessions H1 établies), `recus`, `emis`, `rejets` (datagrammes refusés en silence : 10.3), `perdus`.

### 5.6 `hb` et `fin`

`hb` : battement quand les `etat` sont coupés ou lents (3.5) : `boot`, `up_s`, `json_perdus` (comme dans le bloc `sante` : lignes de cette session et événements perdus), et `commande` comme le bloc `sante`.

`fin` : dernier message d'une session machine. `cause` : `commande` (`json 0`) ou `bail`.
````

`docs/PROTOCOLE-JSON.md`, bloc 9 sur 13. Remplacer :

````markdown
| `lampe` | numéro de la lampe d'un ordre |
| `bail_s`, `up_s` | `json 1`, `json ping` |

| Code | ok | Sens |
````

par :

````markdown
| `lampe` | numéro de la lampe d'un ordre |
| `bail_s`, `up_s` | `json 1`, `json ping` |
| `cle`, `empreinte` | `json cle nouvelle` : la clé UDP (64 hexa), une seule fois, et son empreinte |

| Code | ok | Sens |
````

`docs/PROTOCOLE-JSON.md`, bloc 10 sur 13. Remplacer :

````markdown
| `trop_long` | non | ligne de plus de 127 octets : rien n'est exécuté |
| `cadence` | non | plus de 20 lignes par seconde en mode machine : rien n'est exécuté |

### 6.4 Commandes utilisées par l'app
````

par :

````markdown
| `trop_long` | non | ligne de plus de 127 octets : rien n'est exécuté |
| `cadence` | non | plus de 20 lignes par seconde en mode machine : rien n'est exécuté |
| `interdite` | non | à distance, commande hors de la liste blanche (10.5) : rien n'est exécuté |
| `deja_traite` | non | à distance, `id` plus ancien que les 8 dernières réponses gardées (10.4) |

### 6.4 Commandes utilisées par l'app
````

`docs/PROTOCOLE-JSON.md`, bloc 11 sur 13. Remplacer :

````markdown
Seulement avec `json log 1` : les annonces de la tâche des lampes (`[lampes] …`, `!! …`, `[mesh] …`) et du bouton BOOT (`[bouton] …`) partent alors en `log` **au lieu** du texte. Champs : `src` (`lampes`, `mesh`, `bouton`), `niv` (`notice` ou `alerte`), `txt` (127 octets au plus). Au plus 20 par seconde ; au-delà, le suivant porte `sautes`. Les journaux d'ESP-IDF et le texte des commandes ne passent jamais par `log`.

## 8. Versionnage et débit

- `v` change seulement pour une rupture. Tout le reste est additif et garde `v` ; `rev` augmente à chaque ajout.
- L'app ignore les champs, types et blocs inconnus, et range une valeur d'énumération inconnue sous « inconnu ».
- Au repos, deux lampes, réglages par défaut : environ 1,8 Ko/s (`etat` `pont` et `sante`, `compteurs` chaque seconde ; une ligne par lampe toutes les 10 s ; `reseau` toutes les 5 s). À 16 lampes : environ 2,3 Ko/s. Un instantané complet à 16 lampes fait 42 lignes, environ 11 Ko, émises en un peu plus de 0,4 s.

## 9. Exemples

`<RS>` note l'octet `0x1E` ; le LF final est omis. Les MAC, le numéro de série et les empreintes sont inventés.
````

par :

````markdown
Seulement avec `json log 1` : les annonces de la tâche des lampes (`[lampes] …`, `!! …`, `[mesh] …`) et du bouton BOOT (`[bouton] …`) partent alors en `log` **au lieu** du texte. Champs : `src` (`lampes`, `mesh`, `bouton`), `niv` (`notice` ou `alerte`), `txt` (127 octets au plus). Au plus 20 par seconde ; au-delà, le suivant porte `sautes`. Les journaux d'ESP-IDF et le texte des commandes ne passent jamais par `log`.

### 7.6 `trame` : trafic Bluetooth Mesh

Seulement avec `json trames 1` : chaque message de lampe que le pont émet ou reçoit, décodé. `sens` (`tx`, `rx`) ; `quoi` : `ordre` (marche ou intensité vers une lampe), `demande` (demande d'état au groupe des lampes), `etat` (état renvoyé par une lampe) ; `lampe` (`null` pour le groupe) ; `marche`, `intensite` (`null` si absents) ; `essai` (ordre, 1 à 3) ; `sautes` : trames non émises depuis la précédente (au plus 50 par seconde par l'USB, 10 à distance). À distance, `json trames 1` se coupe seul au bout de 60 s.

## 8. Versionnage et débit

- `v` change seulement pour une rupture. Tout le reste est additif et garde `v` ; `rev` augmente à chaque ajout.
- L'app ignore les champs, types et blocs inconnus, et range une valeur d'énumération inconnue sous « inconnu ».
- Au repos, deux lampes, réglages par défaut : environ 1,8 Ko/s (`etat` `pont` et `sante`, `compteurs` chaque seconde ; une ligne par lampe toutes les 10 s ; `reseau` toutes les 5 s). À 16 lampes : environ 2,3 Ko/s. Un instantané complet à 16 lampes fait 43 lignes, environ 11 Ko, émises en un peu plus de 0,4 s. À distance, le débit est plafonné (10.3).

## 9. Exemples (USB)

`<RS>` note l'octet `0x1E` ; le LF final est omis. Les MAC, le numéro de série et les empreintes sont inventés.
````

`docs/PROTOCOLE-JSON.md`, bloc 12 sur 13. Remplacer :

````markdown

```
<RS>{"v":1,"t":"hello","n":0,"ms":83512,"bloc":"base","rev":0,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"3FA2C901","reset":"logiciel","reset_n":3,"up_s":83,"session":{"periode_ms":1000,"lampes_ms":10000,"compteurs_ms":1000,"reseau_ms":5000,"bail_s":30,"log":false},"limites":{"ligne_max":1024,"cmd_max":127}}
<RS>{"v":1,"t":"hello","n":1,"ms":83522,"bloc":"identite","boot":"3FA2C901","mac":"F0F5BD0A0B0C","id":{"fabricant":"TEST_VENDOR","produit":"TEST_PRODUCT","serie":"AMARAN-F0F5BD0A0B0C","nom":"Pont amaran"},"caps":["matter","thread","mesh","catalogue","ordres","led","log"]}
<RS>{"v":1,"t":"config","n":2,"ms":83532,"bloc":"catalogue","modeles":[{"code":40065,"nom":"amaran COB 60d","capacites":["intensite"],"type":"variable","cct_k":null}],"repli":{"nom":"modele non catalogue","capacites":["intensite"],"type":"variable","cct_k":null}}
<RS>{"v":1,"t":"config","n":3,"ms":83542,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":0,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}
````

par :

````markdown

```
<RS>{"v":1,"t":"hello","n":0,"ms":83512,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"3FA2C901","reset":"logiciel","reset_n":3,"up_s":83,"session":{"transport":"usb","periode_ms":1000,"lampes_ms":10000,"compteurs_ms":1000,"reseau_ms":5000,"bail_s":30,"log":false,"trames":false},"limites":{"ligne_max":1024,"cmd_max":127}}
<RS>{"v":1,"t":"hello","n":1,"ms":83522,"bloc":"identite","boot":"3FA2C901","mac":"F0F5BD0A0B0C","id":{"fabricant":"TEST_VENDOR","produit":"TEST_PRODUCT","serie":"AMARAN-F0F5BD0A0B0C","nom":"Pont amaran"},"caps":["matter","thread","mesh","catalogue","ordres","led","log","trames","udp","cle","texte"]}
<RS>{"v":1,"t":"config","n":2,"ms":83532,"bloc":"catalogue","modeles":[{"code":40065,"nom":"amaran COB 60d","capacites":["intensite"],"type":"variable","cct_k":null}],"repli":{"nom":"modele non catalogue","capacites":["intensite"],"type":"variable","cct_k":null}}
<RS>{"v":1,"t":"config","n":3,"ms":83542,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":0,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}
````

`docs/PROTOCOLE-JSON.md`, bloc 13 sur 13. Remplacer :

````markdown
amaran>
```
````

par :

````markdown
amaran>
```

## 10. À distance (Thread)

### 10.1 Le canal

Les mêmes lignes qu'à l'USB, dans des datagrammes UDP sur le réseau Thread, port 5480. L'app apprend par l'USB le nom SRP du pont (bloc `reseau` `ip`) et le résout en `<srp>.local` (mDNS, IPv6) : le nom suit les changements de préfixe. L'enveloppe est celle de Halo, octet pour octet :
- poignée de main : l'app envoie `H1 SALUT <kid> <na> <mac>` ; le pont répond `H1 DEFI <sid> <nc> <mac>` (plus court que le SALUT : aucune amplification). `kid` : empreinte de la clé UDP ; `na`, `nc` : aléas de 16 octets ; les `mac` : HMAC-SHA256 de la clé UDP. La clé de session dérive de la clé UDP, de `na`, `nc` et `sid` ;
- messages : `H1 <sid> <ctr> <mac> <ligne>`, une ligne par datagramme. `mac` : 16 octets du HMAC-SHA256 de la clé de session sur le sens (`A` : app → pont, `C` : pont → app), `sid`, `ctr` et la ligne ; `ctr` compte de 1 par sens ; une fenêtre de 32 refuse les rejeux ;
- intégrité seulement, pas de confidentialité : rien de secret ne passe par Thread. Vers une session distante, `code_manuel` et `qr` valent `null` dans le bloc `reseau` `matter`, et la commande `matter` n'imprime pas les codes d'appairage.

### 10.2 La clé UDP

32 octets, créés par l'USB seulement : l'app tire un aléa de 32 octets et envoie `json cle nouvelle <64 hexa>` ; le pont dérive la clé de cet aléa et du sien, l'écrit en NVS, ouvre le port 5480 et la rend **une seule fois**, dans la `reponse` (`cle`, `empreinte`). `reponse.cmd` ne cite jamais l'aléa. L'app la range dans le trousseau du Mac. `json cle efface`, `decommission` ou le bouton BOOT tenu 8 s l'effacent ; une nouvelle clé fait tomber les sessions en cours. Sans clé, le port 5480 est fermé. Si l'accès par Thread n'a pas démarré (Matter non démarré), `json cle nouvelle` répond `erreur` et rien ne change ; `json cle efface`, `decommission` et BOOT effacent quand même la clé de la NVS. Si la NVS refuse l'effacement, la clé quitte la mémoire (sessions tombées, port fermé) mais reviendrait au redémarrage : `json cle efface` répond `erreur`, et son `msg` le dit.

### 10.3 Limites du pont

Deux sessions établies au plus, et une en cours de poignée de main (oubliée au bout de 30 s) ; une session est oubliée après 10 min sans rien. Deux DEFI par seconde au plus ; un SALUT dont l'aléa a déjà servi est ignoré. Débit moyen vers l'app : 3 000 octets par seconde au plus, en priorité basse (devant un manque de tampons, OpenThread évince nos messages avant ceux de Matter). Un datagramme reçu de plus de 256 octets n'est pas lu. Un datagramme refusé est ignoré en silence et compté (`reseau` `ip` `udp.rejets`).

Le débit se règle sur la file d'émission du pont : 12 datagrammes, partagés par les sessions, dont une place toujours gardée pour un DEFI.
- Une ligne de la file d'une session (instantané, lignes périodiques, réponse différée de `json 1`, `json etat`, `json hello`) attend sa place : 7 places libres pour une ligne périodique, 2 pour une réponse ; il en reste ainsi 6 pour une rafale de réponses et d'événements (deux sessions, deux ordres au même instant). Les deux sessions avancent à tour de rôle. Une ligne périodique encore en file 10 s après sa demande est perdue et comptée ; une réponse ne l'est jamais.
- Un événement rare (`ordre`, `alerte`, `lampe`, `led`) part s'il reste 2 places ; une `trame` ou un `log`, fréquents, s'il en reste 7, pour ne pas prendre la place d'une réponse. Sinon il est perdu pour cette session : `n` saute, `json_perdus` le compte.
- Une réponse immédiate (famille `json`, ordre de lampe, refus) part s'il reste 2 places, sinon elle est perdue et comptée ; une `fin` reste dans le cache (10.4) : l'app la retrouve en renvoyant le même `id`.
- Une commande à texte : sa `reponse` `debut`, chacune de ses lignes `texte` et sa `reponse` `fin` attendent leur place, 1 s au plus chacune, puis sont perdues et comptées.

Ainsi, l'instantané de `json 1` arrive entier : 14 lignes et environ 4,6 Ko, en-têtes H1 compris, en 0,8 s avec 2 lampes ; 42 lignes et environ 13 Ko en 3,6 s avec 16 lampes (simulation, tampons d'OpenThread libres). Deux `json 1` simultanés à 16 lampes (environ 26 Ko à 3 Ko/s) arrivent aussi entiers, en un peu plus de 8 s.

### 10.4 Une session distante

- Toute ligne porte un `id` ; une ligne sans `id` est ignorée.
- `n` est propre à chaque session (l'USB, et chaque session distante) : un trou dans `n` dit une perte sur ce canal. `json_perdus` aussi (blocs `sante` et `hb`) : chaque session y lit ses propres pertes, plus les événements perdus file pleine.
- Le pont garde les 8 dernières réponses `fin` de chaque session : une ligne dont l'`id` est déjà connu reçoit la même réponse sans être exécutée de nouveau (l'app renvoie une commande restée sans réponse, avec le même `id`) ; un `id` encore en cours (sa réponse `fin` n'est pas encore partie : `json 1`, `json etat`, une commande à texte) est ignoré, sa réponse viendra ; un `id` plus ancien que ces 8 reçoit `deja_traite`.
- Les commandes qui impriment du texte (les lectures de 10.5, `mesh lampe <n> masquer|afficher`) : `reponse` `debut`, puis une ligne `texte` par ligne que la console imprimerait (`id`, `txt` : 127 octets au plus), puis `reponse` `fin`. Le texte part une fois la commande finie : au-delà de 4 096 octets, la suite n'est pas gardée, et une dernière ligne `texte` dit `(sortie tronquee)`.
- Les événements (`ordre`, `alerte`, `lampe`, `led`, `log`, `trame`) partent vers chaque session qui les demande ; un `ordre` ne porte que les `id` de la session qui l'a envoyé : une session qui a pris la place d'une autre ne reçoit ni ses `id`, ni ses réponses, ni ses lignes.

### 10.5 Liste blanche et profil

Permises à distance, jugées sur la ligne découpée comme la console la découpe (guillemets et échappements ne la contournent pas) ; toute autre commande reçoit `interdite` :
- `json 1` (bail de 10 à 120 s ; jamais 0), `json 0`, `json etat`, `json hello`, `json ping`, `json trames 0|1`, `json log 0|1` ; `json periode` 0 ou 2 000 à 60 000 ms, `json lampes` 0 ou 10 000 à 60 000, `json compteurs` 0 ou 5 000 à 60 000, `json reseau` 0 ou 10 000 à 60 000 ;
- `lampe <n>`, `lampe <n> on|off|releve`, `lampe <n> niveau <v>` ;
- `mesh lampe <n> masquer|afficher` ;
- `led test|stop` ;
- les lectures `lampes`, `mesh`, `matter`, `taches`, `cause`.

Interdites, entre autres : `mesh cles`, `mesh lampes`, `mesh lampe <n> <adresse> …`, `mesh oublie`, `mesh adresse`, `mesh iv`, `mesh releve`, `json cle …`, `decommission`, `redemarre`.

Profil d'une session distante, après `json 1` : `etat` `pont` et `sante` toutes les 2 s, toutes les lignes `etat` `lampe` toutes les 30 s (et une lampe à chaque changement), `reseau` toutes les 30 s, ni `compteurs` ni `trame`.

### 10.6 Exemples

`hello` d'une session distante, puis le bloc `ip` (par l'USB comme à distance), avec et sans clé UDP :

```
<RS>{"v":1,"t":"hello","n":0,"ms":900120,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"3FA2C901","reset":"logiciel","reset_n":3,"up_s":900,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false},"limites":{"ligne_max":1024,"cmd_max":127}}
<RS>{"v":1,"t":"reseau","n":14,"ms":83642,"bloc":"ip","srp":"1A2B3C4D5E6F7081","adresses":[{"type":"omr","adresse":"fd00:aaaa:bbbb:0:1111:2222:3333:4444"},{"type":"ml_eid","adresse":"fd00:cccc:dddd:1:5555:6666:7777:8888"}],"udp":{"port":5480,"cle":true,"empreinte":"CA2A4FE7","ouvert":true,"sessions":1,"recus":412,"emis":980,"rejets":3,"perdus":0}}
<RS>{"v":1,"t":"reseau","n":14,"ms":83642,"bloc":"ip","srp":"1A2B3C4D5E6F7081","adresses":[],"udp":{"port":5480,"cle":false,"empreinte":null,"ouvert":false,"sessions":0,"recus":0,"emis":0,"rejets":0,"perdus":0}}
```

Création de la clé UDP, par l'USB (`id=5 json cle nouvelle <64 hexa>`) :

```
<RS>{"v":1,"t":"reponse","n":60,"ms":860000,"id":5,"etape":"fin","cmd":"json cle nouvelle","ok":true,"code":"ok","duree_ms":12,"cle":"404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F","empreinte":"CA2A4FE7"}
```

Refus à distance, et un `id` oublié :

```
<RS>{"v":1,"t":"reponse","n":101,"ms":912000,"id":31,"etape":"fin","cmd":"redemarre","ok":false,"code":"interdite","msg":"interdite a distance : USB seulement","duree_ms":0}
<RS>{"v":1,"t":"reponse","n":102,"ms":912010,"id":29,"etape":"fin","cmd":"lampe 1 on","ok":false,"code":"deja_traite","msg":"id deja traite : reponse oubliee","duree_ms":0}
```

Une lecture à distance (`id=32 lampe 1`) :

```
<RS>{"v":1,"t":"reponse","n":103,"ms":913000,"id":32,"etape":"debut","cmd":"lampe 1","ok":true,"code":"en_cours"}
<RS>{"v":1,"t":"texte","n":104,"ms":913004,"id":32,"txt":"lampe 1 : Lampe bureau"}
<RS>{"v":1,"t":"texte","n":105,"ms":913005,"id":32,"txt":"  Maison    : EP2"}
<RS>{"v":1,"t":"reponse","n":106,"ms":913006,"id":32,"etape":"fin","cmd":"lampe 1","ok":true,"code":"ok","duree_ms":6}
```

Trames, avec `json trames 1` : un ordre, une demande d'état au groupe, un état reçu (deux trames non émises avant lui) :

```
<RS>{"v":1,"t":"trame","n":210,"ms":95012,"sens":"tx","quoi":"ordre","lampe":1,"marche":true,"intensite":500,"essai":1,"sautes":0}
<RS>{"v":1,"t":"trame","n":211,"ms":96000,"sens":"tx","quoi":"demande","lampe":null,"marche":null,"intensite":null,"sautes":0}
<RS>{"v":1,"t":"trame","n":212,"ms":96140,"sens":"rx","quoi":"etat","lampe":1,"marche":true,"intensite":500,"sautes":2}
```
````

- [ ] **Step 2 : les tests.**

`tests/hote/test_json.cpp`, bloc 1 sur 8. Remplacer :

````cpp
// messages du pont amaran : chaque exemple de docs/PROTOCOLE-JSON.md (ligne qui
// commence par <RS>) doit sortir tel quel d'ici, chaque message forme ici doit y
// figurer, et le pire cas de chacun tient dans le budget de 896 octets.
// Lancer : sh tests/hote/lancer.sh. Avec --exemples : imprime les lignes formees.
#include <stdio.h>
````

par :

````cpp
// messages du pont amaran : chaque exemple de docs/PROTOCOLE-JSON.md (ligne qui
// commence par <RS>) doit sortir tel quel d'ici, chaque message forme ici doit y
// figurer, et le pire cas de chacun tient dans le budget de 896 octets. La liste
// blanche a distance est jugee sur la ligne decoupee par la vraie fonction de la
// console d'ESP-IDF (split_argv.c, que lancer.sh compile sans la modifier).
// Lancer : sh tests/hote/lancer.sh. Avec --exemples : imprime les lignes formees.
#include <stdio.h>
````

`tests/hote/test_json.cpp`, bloc 2 sur 8. Remplacer :

````cpp
}

// ---------------------------------------------------------------------------
//  Debit, cadence, file, bail
````

par :

````cpp
}

// Toutes les lignes gardees, separees par '|'.
static std::string lignesGardees(const OutputLines &s) {
  std::string m;
  size_t pos = 0;
  bool premiere = true;
  for (const char *l = s.next(&pos); l; l = s.next(&pos)) {
    m += (premiere ? "" : "|") + std::string(l);
    premiere = false;
  }
  return m;
}

// Sortie d'une commande a distance (10.4) : ce que le crochet de la sortie standard
// garde, ecrit par morceaux comme newlib le vide.
static void testOutputLines() {
  static OutputLines s;  // 4 Ko : hors de la pile
  s.clear();
  const char a[] = "lampe 1 : Lampe bureau\r\n  Maison    : EP2\n\nsans fin";
  s.write(a, 10);
  s.write(a + 10, sizeof(a) - 1 - 10);
  CHECK(lignesGardees(s) == "lampe 1 : Lampe bureau|  Maison    : EP2|", "CR retire, ligne vide gardee : '%s'",
        lignesGardees(s).c_str());
  s.flush();
  CHECK(lignesGardees(s) == "lampe 1 : Lampe bureau|  Maison    : EP2||sans fin" && !s.lost(),
        "fin de commande : la ligne commencee part");
  s.flush();
  CHECK(lignesGardees(s) == "lampe 1 : Lampe bureau|  Maison    : EP2||sans fin", "rien de plus sans ligne commencee");
  // Une ligne coupee a kLogTextMax octets, comme log.txt.
  s.clear();
  const std::string longue(200, 'x');
  s.write(longue.c_str(), longue.size());
  s.write("\n", 1);
  CHECK(lignesGardees(s) == std::string(kLogTextMax, 'x'), "ligne coupee a %zu octets", kLogTextMax);
  // 4 096 octets tout juste (chaque ligne avec son 0) : tout est garde ; un octet de
  // plus, la ligne est perdue, et plus aucune ne l'est ensuite.
  for (int extra = 0; extra < 2; extra++) {
    s.clear();
    const std::string l99(99, 'a');  // 100 octets gardes avec son 0
    for (int i = 0; i < 40; i++) s.write((l99 + "\n").c_str(), 100);
    const std::string reste(OutputLines::kMax - 4000 - 1 + (size_t)extra, 'b');
    s.write((reste + "\n").c_str(), reste.size() + 1);
    s.write("court\n", 6);
    size_t pos = 0, n = 0;
    while (s.next(&pos)) n++;
    CHECK(n == (extra ? 40u : 41u) && s.lost() == (extra ? 2u : 1u), "capacite (extra %d) : %zu lignes, %u perdues",
          extra, n, (unsigned)s.lost());
  }
  s.clear();
  CHECK(lignesGardees(s).empty() && !s.lost(), "remise a zero");
}

// ---------------------------------------------------------------------------
//  Debit, cadence, file, bail
````

`tests/hote/test_json.cpp`, bloc 3 sur 8. Remplacer :

````cpp
  CHECK(order, "ordre FIFO a travers le tour de l'anneau");
  // Un instantane complet a 16 lampes tient dans la file : hello (2), catalogue,
  // mesh, 16 config, pont, 16 etat, sante, compteurs, reseau (2), reponse.
  q.clear();
  int n = 0;
````

par :

````cpp
  CHECK(order, "ordre FIFO a travers le tour de l'anneau");
  // Un instantane complet a 16 lampes tient dans la file : hello (2), catalogue,
  // mesh, 16 config, pont, 16 etat, sante, compteurs, reseau (3), reponse.
  q.clear();
  int n = 0;
````

`tests/hote/test_json.cpp`, bloc 4 sur 8. Remplacer :

````cpp
       q.push(Item::NetThread, 0, true) + q.push(Item::Reply, 0, false, 0);
  CHECK(n == 42 && q.size() == 42, "instantane a 16 lampes : %d lignes en file", n);
}

````

par :

````cpp
       q.push(Item::NetThread, 0, true) + q.push(Item::Reply, 0, false, 0);
  CHECK(n == 42 && q.size() == 42, "instantane a 16 lampes : %d lignes en file", n);
}

// A distance (10.3) : la tete part avec 7 places libres dans la file de net_udp (une
// periodique), 2 (une reponse) ; sinon elle attend, et rien ne sort de la file.
static void testFrontReady() {
  Queue q;
  CHECK(!q.frontReady(12), "file vide : rien a sortir");
  q.push(Item::EtatPont, 0, true);
  q.push(Item::Reply, 0, false, 0);
  CHECK(!q.frontReady(0) && !q.frontReady(2) && !q.frontReady(6) && q.frontReady(7) && q.frontReady(12),
        "periodique : 7 places libres, il en reste 6 apres elle");
  CHECK(q.size() == 2 && q.front()->item == Item::EtatPont, "attendre ne retire rien");
  q.pop();
  CHECK(!q.frontReady(1) && q.frontReady(2), "reponse : 2 places libres, celle du DEFI reste");
  CHECK(kPlacesLigne == 2 && kPlacesPeriodique == kPlacesLigne + 5, "cinq places de plus pour une periodique");
}

````

`tests/hote/test_json.cpp`, bloc 5 sur 8. Remplacer :

````cpp
  CHECK(!leaseExpired(9999, 0, 0, 10) && leaseExpired(600000, 0, 0, 600), "bornes 10 et 600 s");
  CHECK(!leaseExpired(5000, 5003, 0, 30), "dernier octet recu apres l'echantillon de now : pas expire");
}

````

par :

````cpp
  CHECK(!leaseExpired(9999, 0, 0, 10) && leaseExpired(600000, 0, 0, 600), "bornes 10 et 600 s");
  CHECK(!leaseExpired(5000, 5003, 0, 30), "dernier octet recu apres l'echantillon de now : pas expire");
}

// ---------------------------------------------------------------------------
//  Distant (10.4, 10.5) : liste blanche, cache des reponses, masque de la cle UDP
// ---------------------------------------------------------------------------

// La vraie fonction de la console d'ESP-IDF (components/console/split_argv.c, compilee
// par lancer.sh) : dans une ligne, une barre oblique inverse devant un octet autre
// que \, " ou espace disparait avec lui ; des guillemets font un seul mot.
extern "C" size_t esp_console_split_argv(char *line, char **argv, size_t argv_size);

static char gCopie[kCmdMax + 1];
static char *gArgv[8];

// Decoupe comme json_pont_distant_ligne (copie de 127 octets, 8 places : 7 mots au
// plus) ; rend argc.
static int decouper(const char *ligne) {
  snprintf(gCopie, sizeof(gCopie), "%s", ligne);
  return (int)esp_console_split_argv(gCopie, gArgv, sizeof(gArgv) / sizeof(gArgv[0]));
}

// Les mots que la console executera, separes par '|'.
static std::string mots(const char *ligne) {
  const int argc = decouper(ligne);
  std::string m;
  for (int i = 0; i < argc; i++) m += (i ? "|" : "") + std::string(gArgv[i]);
  return m;
}

// Le verdict de la liste blanche sur la ligne decoupee ; nullptr : permise.
static const char *refus(const char *ligne) {
  const int argc = decouper(ligne);
  return refusDistant(argc, gArgv);
}

static void testDistant() {
  static const char *const kPermises[] = {
      "json 1", "json 1 bail 10", "json 1 bail 120", "json 0", "json etat", "json hello", "json ping",
      "json periode 2000", "json periode 0", "json periode 60000", "json lampes 10000", "json lampes 0",
      "json compteurs 0", "json compteurs 5000", "json reseau 10000", "json reseau 0", "json trames 1",
      "json trames 0", "json log 1", "lampe 1", "lampe 2 on", "lampe 16 off", "lampe 1 niveau 500",
      "lampe 3 releve", "mesh", "mesh lampe 2 masquer", "mesh lampe 2 afficher", "led test", "led stop",
      "lampes", "matter", "taches", "cause"};
  for (const char *c : kPermises) CHECK(!refus(c), "permise a distance : '%s' (%s)", c, refus(c));
  static const char *const kInterdites[] = {
      "json 1 bail 0", "json 1 bail 9", "json 1 bail 121", "json 1 bail", "json 1 xyz 30", "json periode 1999",
      "json periode 60001", "json lampes 9999", "json compteurs 4999", "json reseau 9999", "json trames 2",
      "json cle nouvelle 00", "json cle efface", "json", "json periode", "json periode 2000 3000",
      "lampe", "lampe x on", "lampe 1 clignote", "lampe 1 niveau", "lampe 1 niveau x", "lampe 1 on 2",
      "mesh cles 00 11", "mesh lampes 2", "mesh lampe 1 0x0002 02:00:00:00:00:01 40065 nom", "mesh oublie",
      "mesh adresse suivante", "mesh iv 5", "mesh releve 2", "mesh balayage", "mesh lampe 2 masquer x",
      "decommission", "redemarre", "led", "led test x", "taches x", "help", ""};
  for (const char *c : kInterdites) CHECK(refus(c), "interdite a distance : '%s'", c);
  CHECK(!strcmp(refus("json 1 bail 0"), "json 1 : bail de 10 a 120 s a distance"), "raison du bail");
  CHECK(!strcmp(refus("json periode 100"), "json periode : 0 ou 2000..60000 ms a distance"), "raison de periode");
  // Guillemets et barres obliques inverses : la liste blanche juge les mots que la
  // console executera (esp_console_split_argv), jamais la ligne brute.
  static const struct {
    const char *ligne, *mots;
    bool permise;
  } kDecoupes[] = {
      {"json \"1\" \"bail\" 0", "json|1|bail|0", false},
      {"re\\xdemarre", "redemarre", false},
      {"json c\\xle efface", "json|cle|efface", false},
      {"l\\xampe 1 on", "lampe|1|on", true},
      {"\"lampe\" 1 on", "lampe|1|on", true},
      {"lampe 1 \"on\"", "lampe|1|on", true},
      {"json 1 bail 1\\x0", "json|1|bail|10", true},
      {"\"mesh lampe\" 1 masquer", "mesh lampe|1|masquer", false},
      {"mesh\\ lampe 1 masquer", "mesh lampe|1|masquer", false},
      {"lampe \"1 on\"", "lampe|1 on", false},
      {"\"lampe 1 on", "lampe 1 on", false},
      {"json \"\" 1", "json||1", false},
      {"lampe 1 on a b c d e", "lampe|1|on|a|b|c|d", false},
  };
  for (const auto &d : kDecoupes) {
    const std::string m = mots(d.ligne);
    CHECK(m == d.mots, "'%s' decoupee : '%s', attendu '%s'", d.ligne, m.c_str(), d.mots);
    CHECK((refus(d.ligne) == nullptr) == d.permise, "'%s' : %s attendue", d.ligne, d.permise ? "permise" : "interdite");
  }

  Session d = sessionDistante();
  CHECK(!strcmp(d.transport, "udp") && d.periodeMs == 2000 && d.lampesMs == 30000 && d.compteursMs == 0 &&
            d.reseauMs == 30000 && !d.log && !d.trames,
        "profil a distance");

  ReplyCache cache;
  Reply r;
  r.id = 7;
  r.cmd = "lampe 1 on";
  r.code = "accepte";
  r.msg = "message";
  r.key = "CLE";
  cache.put(r);
  const Reply *t = cache.find(7);
  CHECK(t && !strcmp(t->cmd, "lampe 1 on") && !strcmp(t->code, "accepte") && !t->msg && !t->key,
        "cache : la reponse, sans msg ni cle");
  CHECK(!cache.find(8) && !cache.find(0), "cache : id absent");
  Reply debut = r;
  debut.id = 9;
  debut.fin = false;
  cache.put(debut);
  CHECK(!cache.find(9), "cache : une reponse debut n'est pas gardee");
  for (uint32_t i = 100; i < 100 + ReplyCache::kN; i++) {
    r.id = i;
    cache.put(r);
  }
  CHECK(!cache.find(7) && cache.find(100) && cache.find(100 + ReplyCache::kN - 1), "cache : 8 au plus, la plus ancienne sort");
  r.id = 100;
  r.code = "ok";
  cache.put(r);
  CHECK(!strcmp(cache.find(100)->code, "ok"), "cache : un id repete garde la reponse la plus recente");
  cache.clear();
  CHECK(!cache.find(100), "cache vide");

  char a[] = "json cle nouvelle 000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
  maskCmd(a);
  CHECK(!strcmp(a, "json cle nouvelle"), "json cle nouvelle : l'alea ne revient jamais ('%s')", a);

  uint8_t ip[16] = {0xfd, 0x12, 0x00, 0x34, 0x56, 0x78, 0, 0, 0xaa, 0xaa, 0xbb, 0xbb, 0x0c, 0xcc, 0xdd, 0xdd};
  char tx[40];
  ip6Texte(ip, tx);
  CHECK(!strcmp(tx, "fd12:34:5678:0:aaaa:bbbb:ccc:dddd"), "ip6, un seul groupe nul : '%s'", tx);
  uint8_t zero[16] = {};
  ip6Texte(zero, tx);
  CHECK(!strcmp(tx, "::"), "ip6 nulle : '%s'", tx);
  uint8_t fin[16] = {};
  fin[15] = 1;
  ip6Texte(fin, tx);
  CHECK(!strcmp(tx, "::1"), "ip6 ::1 : '%s'", tx);
  uint8_t lien[16] = {0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0x02, 0x00, 0x00, 0x00, 0x0a, 0x0b, 0x0c, 0x0d};
  ip6Texte(lien, tx);
  CHECK(!strcmp(tx, "fe80::200:0:a0b:c0d"), "ip6 de lien : '%s'", tx);
  uint8_t un[16] = {0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1};
  ip6Texte(un, tx);
  CHECK(!strcmp(tx, "2001:db8:0:1:1:1:1:1"), "un seul groupe nul n'est pas abrege : '%s'", tx);
  uint8_t deux[16] = {0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1};
  ip6Texte(deux, tx);
  CHECK(!strcmp(tx, "2001:db8::1:0:0:1"), "la premiere suite la plus longue : '%s'", tx);
}

````

`tests/hote/test_json.cpp`, bloc 6 sur 8. Remplacer :

````cpp
  exemple(gW, "fin");

  // Chaque exemple du document a ete forme ici.
  for (const std::string &d : gDoc) CHECK(gVues.count(d), "exemple du document jamais forme :\n  <RS>%s", d.c_str());
````

par :

````cpp
  exemple(gW, "fin");

  // 10. A distance (Thread) : hello d'une session distante, bloc ip, cle, refus,
  // texte d'une lecture, trames.
  hb.session = sessionDistante();
  hb.session.bailS = 60;
  hb.upS = 900;
  helloBase(gW, 0, 900120, hb);
  exemple(gW, "hello base distante");
  ReseauIp ip;
  ip.srp = "1A2B3C4D5E6F7081";
  const uint8_t omr[16] = {0xfd, 0x00, 0xaa, 0xaa, 0xbb, 0xbb, 0, 0, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33, 0x44, 0x44};
  const uint8_t mleid[16] = {0xfd, 0x00, 0xcc, 0xcc, 0xdd, 0xdd, 0, 1, 0x55, 0x55, 0x66, 0x66, 0x77, 0x77, 0x88, 0x88};
  memcpy(ip.adresses[0].a, omr, 16);
  ip.adresses[0].type = "omr";
  memcpy(ip.adresses[1].a, mleid, 16);
  ip.adresses[1].type = "ml_eid";
  ip.n = 2;
  ip.cle = true;
  ip.empreinte = "CA2A4FE7";
  ip.ouvert = true;
  ip.sessions = 1;
  ip.recus = 412;
  ip.emis = 980;
  ip.rejets = 3;
  reseauIp(gW, 14, 83642, ip);
  exemple(gW, "reseau ip");
  ReseauIp sansCle;
  sansCle.srp = "1A2B3C4D5E6F7081";
  reseauIp(gW, 14, 83642, sansCle);
  exemple(gW, "reseau ip sans cle");
  Reply rc;
  rc.id = 5;
  rc.cmd = "json cle nouvelle";
  rc.durMs = 12;
  rc.key = "404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F";
  rc.kid = "CA2A4FE7";
  reply(gW, 60, 860000, rc);
  exemple(gW, "reponse cle nouvelle");
  Reply rd;
  rd.id = 31;
  rd.cmd = "redemarre";
  rd.ok = false;
  rd.code = "interdite";
  rd.msg = refus("redemarre");
  reply(gW, 101, 912000, rd);
  exemple(gW, "reponse interdite");
  rd.id = 29;
  rd.cmd = "lampe 1 on";
  rd.code = "deja_traite";
  rd.msg = "id deja traite : reponse oubliee";
  reply(gW, 102, 912010, rd);
  exemple(gW, "reponse deja traite");
  Reply rl;
  rl.id = 32;
  rl.cmd = "lampe 1";
  rl.fin = false;
  rl.code = "en_cours";
  reply(gW, 103, 913000, rl);
  exemple(gW, "reponse debut lampe a distance");
  textLine(gW, 104, 913004, 32, "lampe 1 : Lampe bureau");
  exemple(gW, "texte 1");
  textLine(gW, 105, 913005, 32, "  Maison    : EP2");
  exemple(gW, "texte 2");
  rl.fin = true;
  rl.code = "ok";
  rl.durMs = 6;
  reply(gW, 106, 913006, rl);
  exemple(gW, "reponse fin lampe a distance");
  Trame tr;
  tr.lampe = 0;
  tr.marche = 1;
  tr.intensite = 500;
  tr.essai = 1;
  trame(gW, 210, 95012, tr);
  exemple(gW, "trame ordre");
  Trame td;
  td.quoi = "demande";
  trame(gW, 211, 96000, td);
  exemple(gW, "trame demande");
  Trame te;
  te.sens = "rx";
  te.quoi = "etat";
  te.lampe = 0;
  te.marche = 1;
  te.intensite = 500;
  te.sautes = 2;
  trame(gW, 212, 96140, te);
  exemple(gW, "trame etat");

  // Chaque exemple du document a ete forme ici.
  for (const std::string &d : gDoc) CHECK(gVues.count(d), "exemple du document jamais forme :\n  <RS>%s", d.c_str());
````

`tests/hote/test_json.cpp`, bloc 7 sur 8. Remplacer :

````cpp
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reponse : %zu octets", s.size());
  std::string txt(300, '"');
  logLine(gW, M, M, "lampes", "alerte", txt.c_str(), M);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "log : %zu octets", s.size());
}

````

par :

````cpp
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reponse : %zu octets", s.size());
  // La meme, avec la cle UDP et son empreinte (json cle nouvelle) : cumul impossible
  // en pratique, borne superieure.
  std::string cle(64, 'F');
  r.key = cle.c_str();
  r.kid = "FFFFFFFF";
  reply(gW, M, M, r);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reponse avec cle : %zu octets", s.size());
  std::string txt(300, '"');
  logLine(gW, M, M, "lampes", "alerte", txt.c_str(), M);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "log : %zu octets", s.size());
  // Texte d'une commande a distance : 127 octets gardes, tous a echapper.
  textLine(gW, M, M, kIdMax, txt.c_str());
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "texte : %zu octets", s.size());
  // Bloc ip : 4 adresses de 39 caracteres (aucun groupe nul), le nom SRP le plus long
  // garde (63 octets), tout a echapper, compteurs au maximum.
  ReseauIp ip;
  std::string srp(63, '"');
  ip.srp = srp.c_str();
  for (int i = 0; i < 4; i++) {
    memset(ip.adresses[i].a, 0xAB, 16);
    ip.adresses[i].type = "ml_eid";
  }
  char a39[40];
  ip6Texte(ip.adresses[0].a, a39);
  CHECK(strlen(a39) == 39, "adresse de 39 caracteres : '%s'", a39);
  ip.n = 4;
  ip.cle = true;
  ip.empreinte = "FFFFFFFF";
  ip.ouvert = true;
  ip.sessions = 255;
  ip.recus = ip.emis = ip.rejets = ip.perdus = M;
  reseauIp(gW, M, M, ip);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reseau ip : %zu octets", s.size());
  // Trame : valeurs extremes (ordre : avec essai).
  Trame tr;
  tr.sens = "rx";
  tr.quoi = "ordre";
  tr.lampe = LISTE_CAPACITE - 1;
  tr.marche = 1;
  tr.intensite = 2147483647;
  tr.essai = 255;
  tr.sautes = M;
  trame(gW, M, M, tr);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "trame : %zu octets", s.size());
}

````

`tests/hote/test_json.cpp`, bloc 8 sur 8. Remplacer :

````cpp
  testMask();
  testAssembler();
  testRate();
  testQueue();
  testQueueDrain();
  testLease();
  testExemples();
  testPiresCas();
````

par :

````cpp
  testMask();
  testAssembler();
  testOutputLines();
  testRate();
  testQueue();
  testFrontReady();
  testQueueDrain();
  testLease();
  testDistant();
  testExemples();
  testPiresCas();
````

`tests/hote/lancer.sh`, bloc 1 sur 1. Remplacer :

````sh

# Protocole JSON (components/protocole) : C++17, avec le catalogue (C) ; lit les exemples
# de docs/PROTOCOLE-JSON.md.
"$CC" $CFLAGS -c components/liste/catalogue.c -o "$SORTIE/catalogue.o"
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/protocole/include -Icomponents/liste/include \
  -Icomponents/lampes/include -Icomponents/telink/include components/protocole/json_ligne.cpp \
  components/protocole/json_amaran.cpp tests/hote/test_json.cpp "$SORTIE/catalogue.o" -o "$SORTIE/test_json"
"$SORTIE/test_json"

````

par :

````sh

# Protocole JSON (components/protocole) : C++17, avec le catalogue (C) ; lit les exemples
# de docs/PROTOCOLE-JSON.md. La liste blanche est jugee sur la ligne decoupee par la vraie
# fonction de la console d'ESP-IDF (split_argv.c, compilee ici, jamais modifiee).
SPLIT_ARGV="${IDF_PATH:-$HOME/esp/esp-idf}/components/console/split_argv.c"
if [ ! -f "$SPLIT_ARGV" ]; then
  echo "introuvable : $SPLIT_ARGV (ESP-IDF 5.5.4 dans ~/esp/esp-idf, ou IDF_PATH)" >&2
  exit 1
fi
"$CC" $CFLAGS -c components/liste/catalogue.c -o "$SORTIE/catalogue.o"
"$CC" -std=c11 -Wall -Wextra -Werror -c "$SPLIT_ARGV" -o "$SORTIE/split_argv.o"
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/protocole/include -Icomponents/liste/include \
  -Icomponents/lampes/include -Icomponents/telink/include components/protocole/json_ligne.cpp \
  components/protocole/json_amaran.cpp tests/hote/test_json.cpp "$SORTIE/catalogue.o" "$SORTIE/split_argv.o" \
  -o "$SORTIE/test_json"
"$SORTIE/test_json"

````

- [ ] **Step 3 : lancer les tests, ils échouent.**

Run: `sh tests/hote/lancer.sh`
Expected: FAIL à la compilation de `test_json.cpp` : `unknown type name 'OutputLines'`, `no member named 'frontReady' in 'jsonp::Queue'`…

- [ ] **Step 4 : le composant.**

`components/protocole/include/json_ligne.h`, bloc 1 sur 7. Remplacer :

````c

constexpr uint8_t kVersion = 1;         // v : version majeure
constexpr uint8_t kRev = 0;             // hello.rev : revision mineure (ajouts)
constexpr size_t kLineMax = 1024;       // RS et LF compris
constexpr size_t kBudget = 896;         // pire cas vise par message (marge de 128 pour les ajouts)
````

par :

````c

constexpr uint8_t kVersion = 1;         // v : version majeure
constexpr uint8_t kRev = 1;             // hello.rev : revision mineure (ajouts)
constexpr size_t kLineMax = 1024;       // RS et LF compris
constexpr size_t kBudget = 896;         // pire cas vise par message (marge de 128 pour les ajouts)
````

`components/protocole/include/json_ligne.h`, bloc 2 sur 7. Remplacer :

````c
void led(Writer &w, uint32_t n, uint32_t ms, const char *motif, const char *before, bool test, uint32_t depuisMs);
void logLine(Writer &w, uint32_t n, uint32_t ms, const char *src, const char *niv, const char *txt, uint32_t skipped);

// Message reponse (section 6.3).
````

par :

````c
void led(Writer &w, uint32_t n, uint32_t ms, const char *motif, const char *before, bool test, uint32_t depuisMs);
void logLine(Writer &w, uint32_t n, uint32_t ms, const char *src, const char *niv, const char *txt, uint32_t skipped);
// Ligne de texte d'une commande executee a distance (10.4) : le texte que la console
// imprimerait, ligne par ligne, tronque a kLogTextMax.
void textLine(Writer &w, uint32_t n, uint32_t ms, uint32_t id, const char *txt);

// Message reponse (section 6.3).
````

`components/protocole/include/json_ligne.h`, bloc 3 sur 7. Remplacer :

````c
  bool hasLease = false;        // bail_s, up_s (json 1, json ping)
  uint32_t leaseS = 0, upS = 0;
};
void reply(Writer &w, uint32_t n, uint32_t ms, const Reply &r);

// ---------------------------------------------------------------------------
````

par :

````c
  bool hasLease = false;        // bail_s, up_s (json 1, json ping)
  uint32_t leaseS = 0, upS = 0;
  const char *key = nullptr;    // json cle nouvelle : la cle UDP, 64 hexa, une seule fois
  const char *kid = nullptr;    // et son empreinte, 8 hexa
};
void reply(Writer &w, uint32_t n, uint32_t ms, const Reply &r);

// Dernieres reponses fin d'une session distante, par id (10.4) : un id repete
// recoit la meme reponse sans etre execute de nouveau. Ni msg, ni cle gardes.
class ReplyCache {
 public:
  static constexpr uint8_t kN = 8;
  void clear();
  void put(const Reply &r);              // etape fin avec id ; remplace la plus ancienne
  const Reply *find(uint32_t id) const;  // r.cmd pointe dans le cache
 private:
  struct Entry {
    bool used = false;
    Reply r;
    char cmd[kCmdTextMax + 1] = {};
  };
  Entry e_[kN];
  uint8_t next_ = 0;
};

// ---------------------------------------------------------------------------
````

`components/protocole/include/json_ligne.h`, bloc 4 sur 7. Remplacer :

````c
void copyCmd(char out[kCmdTextMax + 1], const char *cmd);
// reponse.cmd ne renvoie jamais une cle : 'mesh cles <reseau> <application>'
// devient 'mesh cles'.
void maskCmd(char *shown);

````

par :

````c
void copyCmd(char out[kCmdTextMax + 1], const char *cmd);
// reponse.cmd ne renvoie jamais une cle : 'mesh cles <reseau> <application>'
// devient 'mesh cles', 'json cle nouvelle <alea>' devient 'json cle nouvelle'.
void maskCmd(char *shown);

````

`components/protocole/include/json_ligne.h`, bloc 5 sur 7. Remplacer :

````c
  uint8_t len_ = 0;
  bool tooLong_ = false;
};

````

par :

````c
  uint8_t len_ = 0;
  bool tooLong_ = false;
};

// Sortie d'une commande a texte venue de Thread (10.4), gardee ligne par ligne
// pendant qu'elle tourne, pour partir ensuite en messages texte : write() est le
// crochet de sa sortie standard, sans verrou ni attente. CR ignore ; une ligne
// coupee a kLogTextMax octets ; au-dela de kMax octets gardes (chaque ligne avec
// son 0 final), plus aucune ligne ne l'est, et lost() les compte.
class OutputLines {
 public:
  static constexpr size_t kMax = 4096;
  void clear();
  void write(const char *buf, size_t n);
  void flush();  // fin de la commande : la ligne commencee, s'il y en a une
  // Lignes gardees, dans l'ordre : *pos part de 0 ; nullptr apres la derniere.
  const char *next(size_t *pos) const;
  uint32_t lost() const { return lost_; }

 private:
  void endLine();
  char lines_[kMax] = {};
  size_t len_ = 0;
  char line_[kLogTextMax] = {};
  size_t lineLen_ = 0;
  uint32_t lost_ = 0;
};

````

`components/protocole/include/json_ligne.h`, bloc 6 sur 7. Remplacer :

````c
constexpr uint32_t kLateMs = 500;  // ligne periodique perdue apres ce retard

// Une ligne a former a son tour. arg : la lampe (0..15) pour ConfigLampe et
// EtatLampe, la place de la reponse differee pour Reply.
````

par :

````c
constexpr uint32_t kLateMs = 500;  // ligne periodique perdue apres ce retard

// A distance (10.3), le debit se regle sur la file d'emission de net_udp : 12
// datagrammes, dont une place toujours gardee pour un DEFI. Reglage de Halo
// (json_mode.cpp : room, frontReady, eventRoom), une place de plus pour le DEFI :
// - une reponse, un evenement rare (ordre, alerte, lampe, led), une ligne texte demandent
//   2 places libres (net_udp n'en prend aucune avec moins) ;
// - une ligne periodique, une trame ou un log (frequents) en demandent 7 : apres eux, il
//   en reste 6 pour une rafale de reponses et d'evenements rares (deux sessions, deux
//   ordres au meme instant : deux reponses et quatre evenements).
constexpr uint8_t kPlacesLigne = 2;
constexpr uint8_t kPlacesPeriodique = 7;

// Une ligne a former a son tour. arg : la lampe (0..15) pour ConfigLampe et
// EtatLampe, la place de la reponse differee pour Reply.
````

`components/protocole/include/json_ligne.h`, bloc 7 sur 7. Remplacer :

````c
  // retard : elle arrete le balayage, les lignes derriere elle attendent.
  uint8_t dropLate(uint32_t now, uint32_t lateMs = kLateMs);
  // Retire les elements de session ; ceux qui restent gardent leur ordre.
  uint8_t dropSession();
````

par :

````c
  // retard : elle arrete le balayage, les lignes derriere elle attendent.
  uint8_t dropLate(uint32_t now, uint32_t lateMs = kLateMs);
  // A distance : la tete peut partir avec `libres` places libres dans la file
  // d'emission de net_udp (kPlacesLigne pour une reponse, kPlacesPeriodique pour
  // le reste) ; sinon elle attend le tic suivant. false aussi pour une file vide.
  bool frontReady(uint8_t libres) const;
  // Retire les elements de session ; ceux qui restent gardent leur ordre.
  uint8_t dropSession();
````

`components/protocole/json_ligne.cpp`, bloc 1 sur 4. Remplacer :

````cpp
    w.u32("up_s", r.upS);
  }
}

````

par :

````cpp
    w.u32("up_s", r.upS);
  }
  if (r.key) w.str("cle", r.key, 64);
  if (r.kid) w.str("empreinte", r.kid, 8);
}

void textLine(Writer &w, uint32_t n, uint32_t ms, uint32_t id, const char *txt) {
  w.begin("texte", n, ms);
  w.u32("id", id);
  w.str("txt", txt ? txt : "", kLogTextMax);
}

void ReplyCache::clear() {
  for (Entry &e : e_) e.used = false;
  next_ = 0;
}

void ReplyCache::put(const Reply &r) {
  if (!r.fin || !r.id) return;
  // Une seule entree par id : la plus recente.
  for (Entry &e : e_)
    if (e.used && e.r.id == r.id) e.used = false;
  Entry &e = e_[next_];
  next_ = (uint8_t)((next_ + 1) % kN);
  e.used = true;
  e.r = r;
  copyCmd(e.cmd, r.cmd ? r.cmd : "");
  e.r.cmd = e.cmd;
  e.r.msg = nullptr;
  e.r.key = nullptr;
  e.r.kid = nullptr;
}

const Reply *ReplyCache::find(uint32_t id) const {
  if (!id) return nullptr;
  for (const Entry &e : e_)
    if (e.used && e.r.id == id) return &e.r;
  return nullptr;
}

````

`components/protocole/json_ligne.cpp`, bloc 2 sur 4. Remplacer :

````cpp
  const char *w0 = word(shown, 0, &n0), *w1 = word(shown, 1, &n1);
  if (wordIs(w0, n0, "mesh") && wordIs(w1, n1, "cles")) strcpy(shown, "mesh cles");
}

````

par :

````cpp
  const char *w0 = word(shown, 0, &n0), *w1 = word(shown, 1, &n1);
  if (wordIs(w0, n0, "mesh") && wordIs(w1, n1, "cles")) strcpy(shown, "mesh cles");
  size_t n2;
  const char *w2 = word(shown, 2, &n2);
  if (wordIs(w0, n0, "json") && wordIs(w1, n1, "cle") && wordIs(w2, n2, "nouvelle")) strcpy(shown, "json cle nouvelle");
}

````

`components/protocole/json_ligne.cpp`, bloc 3 sur 4. Remplacer :

````cpp
  buf_[len_] = 0;
  return buf_;
}

````

par :

````cpp
  buf_[len_] = 0;
  return buf_;
}

void OutputLines::clear() {
  len_ = lineLen_ = 0;
  lost_ = 0;
}

void OutputLines::endLine() {
  if (!lost_ && len_ + lineLen_ + 1 <= kMax) {
    memcpy(lines_ + len_, line_, lineLen_);
    len_ += lineLen_;
    lines_[len_++] = 0;
  } else {
    lost_++;  // plein : plus aucune ligne n'est gardee
  }
  lineLen_ = 0;
}

void OutputLines::write(const char *buf, size_t n) {
  for (size_t i = 0; i < n; i++) {
    if (buf[i] == '\n') {
      endLine();
    } else if (buf[i] != '\r' && lineLen_ < kLogTextMax) {
      line_[lineLen_++] = buf[i];
    }
  }
}

void OutputLines::flush() {
  if (lineLen_) endLine();
}

const char *OutputLines::next(size_t *pos) const {
  if (*pos >= len_) return nullptr;
  const char *l = lines_ + *pos;
  *pos += strlen(l) + 1;
  return l;
}

````

`components/protocole/json_ligne.cpp`, bloc 4 sur 4. Remplacer :

````cpp
}

uint8_t Queue::dropSession() {
  Queued keep[kN];
````

par :

````cpp
}

bool Queue::frontReady(uint8_t libres) const {
  if (!n_) return false;
  return libres >= (q_[head_].item == Item::Reply ? kPlacesLigne : kPlacesPeriodique);
}

uint8_t Queue::dropSession() {
  Queued keep[kN];
````

`components/protocole/include/json_amaran.h`, bloc 1 sur 4. Remplacer :

````c

struct Session {
  uint32_t periodeMs = 1000;    // etat : blocs pont et sante
  uint32_t lampesMs = 10000;    // etat : toutes les lampes (une lampe part aussi a chaque changement)
````

par :

````c

struct Session {
  const char *transport = "usb";  // usb, udp
  uint32_t periodeMs = 1000;    // etat : blocs pont et sante
  uint32_t lampesMs = 10000;    // etat : toutes les lampes (une lampe part aussi a chaque changement)
````

`components/protocole/include/json_amaran.h`, bloc 2 sur 4. Remplacer :

````c
  uint16_t bailS = 30;
  bool log = false;
};

struct HelloBase {
````

par :

````c
  uint16_t bailS = 30;
  bool log = false;
  bool trames = false;
};
// Profil a distance (10.5) : l'etat toutes les 2 s, toutes les lampes toutes les
// 30 s, le reseau toutes les 30 s, ni compteurs ni trames.
Session sessionDistante();

// Liste blanche a distance (10.5), jugee sur la ligne decoupee comme la console
// la decoupe (esp_console_split_argv) : guillemets et echappements ne la
// contournent pas. nullptr : permise ; sinon la raison (code interdite).
const char *refusDistant(int argc, const char *const *argv);

struct HelloBase {
````

`components/protocole/include/json_amaran.h`, bloc 3 sur 4. Remplacer :

````c
void reseauThread(Writer &w, uint32_t n, uint32_t ms, const char *role, bool attache);

// --- evenements (7)

````

par :

````c
void reseauThread(Writer &w, uint32_t n, uint32_t ms, const char *role, bool attache);

// Adresse IPv6 en texte (RFC 5952 : minuscules, zeros de tete omis, plus longue
// suite de groupes nuls remplacee par ::). out : 40 octets.
void ip6Texte(const uint8_t a[16], char out[40]);

struct AdresseIp {
  uint8_t a[16] = {};
  const char *type = "autre";   // omr, ml_eid, autre
};
struct ReseauIp {
  const char *srp = nullptr;    // nom SRP (sans .local) ; nul : inconnu
  AdresseIp adresses[4];
  uint8_t n = 0;
  bool cle = false;
  const char *empreinte = nullptr;  // 8 hexa de la cle UDP ; nul sans cle
  bool ouvert = false;          // socket UDP ouverte
  uint8_t sessions = 0;         // sessions H1 etablies
  uint32_t recus = 0, emis = 0, rejets = 0, perdus = 0;
};
void reseauIp(Writer &w, uint32_t n, uint32_t ms, const ReseauIp &r);

// --- evenements (7)

````

`components/protocole/include/json_amaran.h`, bloc 4 sur 4. Remplacer :

````c
void lampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const char *quoi, uint16_t endpoint);

// Codes du protocole.
const char *phaseCode(lampe_phase_t p);  // repos, trames, attente
````

par :

````c
void lampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const char *quoi, uint16_t endpoint);

// Trafic Bluetooth Mesh decode (7.6), sur demande (json trames 1).
struct Trame {
  const char *sens = "tx";      // tx, rx
  const char *quoi = "ordre";   // ordre, demande, etat
  int lampe = -1;               // index ; -1 : le groupe des lampes (demande d'etat)
  int8_t marche = -1;           // -1 : absent
  int32_t intensite = -1;       // -1 : absent
  uint8_t essai = 0;            // ordre : 1 a 3
  uint32_t sautes = 0;          // trames non emises (plafond) depuis la precedente
};
void trame(Writer &w, uint32_t n, uint32_t ms, const Trame &t);

// Codes du protocole.
const char *phaseCode(lampe_phase_t p);  // repos, trames, attente
````

`components/protocole/json_amaran.cpp`, bloc 1 sur 5. Remplacer :

````cpp
// Messages du pont amaran (voir json_amaran.h).
#include "json_amaran.h"

#include <initializer_list>
````

par :

````cpp
// Messages du pont amaran (voir json_amaran.h).
#include "json_amaran.h"

#include <stdio.h>
#include <string.h>

#include <initializer_list>
````

`components/protocole/json_amaran.cpp`, bloc 2 sur 5. Remplacer :

````cpp
  w.u32("up_s", h.upS);
  w.obj("session");
  w.u32("periode_ms", h.session.periodeMs);
  w.u32("lampes_ms", h.session.lampesMs);
````

par :

````cpp
  w.u32("up_s", h.upS);
  w.obj("session");
  w.str("transport", h.session.transport);
  w.u32("periode_ms", h.session.periodeMs);
  w.u32("lampes_ms", h.session.lampesMs);
````

`components/protocole/json_amaran.cpp`, bloc 3 sur 5. Remplacer :

````cpp
  w.u32("bail_s", h.session.bailS);
  w.boolean("log", h.session.log);
  w.end();
  w.obj("limites");
````

par :

````cpp
  w.u32("bail_s", h.session.bailS);
  w.boolean("log", h.session.log);
  w.boolean("trames", h.session.trames);
  w.end();
  w.obj("limites");
````

`components/protocole/json_amaran.cpp`, bloc 4 sur 5. Remplacer :

````cpp
  w.end();
  w.arr("caps");
  for (const char *c : {"matter", "thread", "mesh", "catalogue", "ordres", "led", "log"}) w.str(nullptr, c);
  w.end();
}
````

par :

````cpp
  w.end();
  w.arr("caps");
  for (const char *c : {"matter", "thread", "mesh", "catalogue", "ordres", "led", "log", "trames", "udp", "cle", "texte"})
    w.str(nullptr, c);
  w.end();
}
````

`components/protocole/json_amaran.cpp`, bloc 5 sur 5. Remplacer :

````cpp
}

// --- evenements

````

par :

````cpp
}

void ip6Texte(const uint8_t a[16], char out[40]) {
  uint16_t g[8];
  for (int i = 0; i < 8; i++) g[i] = (uint16_t)(a[2 * i] << 8 | a[2 * i + 1]);
  // Plus longue suite d'au moins deux groupes nuls (la premiere a egalite).
  int debut = -1, lon = 0;
  for (int i = 0; i < 8;) {
    if (g[i]) {
      i++;
      continue;
    }
    int j = i;
    while (j < 8 && !g[j]) j++;
    if (j - i > lon && j - i >= 2) {
      debut = i;
      lon = j - i;
    }
    i = j;
  }
  char *p = out;
  for (int i = 0; i < 8; i++) {
    if (i == debut) {
      *p++ = ':';
      if (i == 0) *p++ = ':';
      i += lon - 1;
      continue;
    }
    p += snprintf(p, 6, "%x", g[i]);
    if (i < 7) *p++ = ':';
  }
  *p = 0;
}

void reseauIp(Writer &w, uint32_t n, uint32_t ms, const ReseauIp &r) {
  w.begin("reseau", n, ms);
  w.str("bloc", "ip");
  if (r.srp) w.str("srp", r.srp, 63);
  else w.null("srp");
  w.arr("adresses");
  for (uint8_t i = 0; i < r.n && i < 4; i++) {
    char t[40];
    ip6Texte(r.adresses[i].a, t);
    w.obj(nullptr);
    w.str("type", r.adresses[i].type);
    w.str("adresse", t);
    w.end();
  }
  w.end();
  w.obj("udp");
  w.u32("port", 5480);
  w.boolean("cle", r.cle);
  if (r.empreinte) w.str("empreinte", r.empreinte, 8);
  else w.null("empreinte");
  w.boolean("ouvert", r.ouvert);
  w.u32("sessions", r.sessions);
  w.u32("recus", r.recus);
  w.u32("emis", r.emis);
  w.u32("rejets", r.rejets);
  w.u32("perdus", r.perdus);
  w.end();
}

Session sessionDistante() {
  Session s;
  s.transport = "udp";
  s.periodeMs = 2000;
  s.lampesMs = 30000;
  s.compteursMs = 0;
  s.reseauMs = 30000;
  return s;
}

// Entier decimal (chiffres seulement, au plus 9) : false sinon.
static bool nombre(const char *s, uint32_t *v) {
  uint32_t x = 0;
  int n = 0;
  for (; s[n]; n++) {
    if (s[n] < '0' || s[n] > '9' || n >= 9) return false;
    x = x * 10 + (uint32_t)(s[n] - '0');
  }
  if (!n) return false;
  *v = x;
  return true;
}

const char *refusDistant(int argc, const char *const *argv) {
  static const char kInterdite[] = "interdite a distance : USB seulement";
  auto est = [&](int i, const char *k) { return i < argc && !strcmp(argv[i], k); };
  uint32_t v = 0;
  if (argc < 1) return kInterdite;
  if (est(0, "json")) {
    if (argc == 2 && (est(1, "0") || est(1, "etat") || est(1, "hello") || est(1, "ping"))) return nullptr;
    if (est(1, "1")) {
      // Jamais de bail 0 a distance : le pont emettrait sur Thread pour un
      // hote parti, jusqu'a l'oubli de la session.
      if (argc == 2) return nullptr;
      if (argc == 4 && est(2, "bail") && nombre(argv[3], &v) && v >= 10 && v <= 120) return nullptr;
      return "json 1 : bail de 10 a 120 s a distance";
    }
    if (argc == 3 && (est(1, "trames") || est(1, "log")) && (est(2, "0") || est(2, "1"))) return nullptr;
    static const struct {
      const char *k;
      uint32_t min;
      const char *msg;
    } kBornes[] = {
        {"periode", 2000, "json periode : 0 ou 2000..60000 ms a distance"},
        {"lampes", 10000, "json lampes : 0 ou 10000..60000 ms a distance"},
        {"compteurs", 5000, "json compteurs : 0 ou 5000..60000 ms a distance"},
        {"reseau", 10000, "json reseau : 0 ou 10000..60000 ms a distance"},
    };
    for (const auto &b : kBornes) {
      if (!est(1, b.k)) continue;
      if (argc == 3 && nombre(argv[2], &v) && (v == 0 || (v >= b.min && v <= 60000))) return nullptr;
      return b.msg;
    }
    return kInterdite;  // 'json' seul, 'json cle ...'
  }
  if (est(0, "lampe")) {
    if (argc >= 2 && !nombre(argv[1], &v)) return kInterdite;
    if (argc == 2) return nullptr;  // detail
    if (argc == 3 && (est(2, "on") || est(2, "off") || est(2, "releve"))) return nullptr;
    if (argc == 4 && est(2, "niveau") && nombre(argv[3], &v)) return nullptr;
    return kInterdite;
  }
  if (est(0, "mesh")) {
    if (argc == 1) return nullptr;  // lecture
    if (argc == 4 && est(1, "lampe") && nombre(argv[2], &v) && (est(3, "masquer") || est(3, "afficher")))
      return nullptr;
    return kInterdite;
  }
  if (argc == 2 && est(0, "led") && (est(1, "test") || est(1, "stop"))) return nullptr;
  if (argc == 1 && (est(0, "lampes") || est(0, "matter") || est(0, "taches") || est(0, "cause"))) return nullptr;
  return kInterdite;
}

void trame(Writer &w, uint32_t n, uint32_t ms, const Trame &t) {
  w.begin("trame", n, ms);
  w.str("sens", t.sens);
  w.str("quoi", t.quoi);
  if (t.lampe >= 0) w.u32("lampe", (uint32_t)t.lampe + 1);
  else w.null("lampe");
  if (t.marche >= 0) w.boolean("marche", t.marche != 0);
  else w.null("marche");
  if (t.intensite >= 0) w.u32("intensite", (uint32_t)t.intensite);
  else w.null("intensite");
  if (!strcmp(t.quoi, "ordre")) w.u32("essai", t.essai);
  w.u32("sautes", t.sautes);
}

// --- evenements

````

- [ ] **Step 5 : lancer les tests, tout est vert.**

Run: `sh tests/hote/lancer.sh`
Expected: `json : 465 verifications, 0 echecs`, `h1 : 121 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 6 : les deux firmwares compilent encore.** Rien ne s'y sert encore des ajouts.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader") && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader")`
Expected : comme à la Task 1 : deux tailles, deux `Project build complete. To flash, run:`, aucune ligne `warning:` ni `error:`.

- [ ] **Step 7 : commit.**

```bash
git add components/protocole tests/hote/test_json.cpp tests/hote/lancer.sh docs/PROTOCOLE-JSON.md
git commit -m "$(printf "Protocole a distance : liste blanche sur les mots de la console, profil distant, cache des reponses, texte, bloc ip, trame, cle UDP\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 3: Le pont par Thread : socket UDP, sessions par origine, tâche `distant`, trames, clé UDP

**Files:**
- Create: `firmware/main/net_udp.h`, `firmware/main/net_udp.cpp`
- Modify (réécrits) : `firmware/main/json_pont.h`, `firmware/main/json_pont.cpp`
- Modify: `firmware/main/tache_lampes.h`, `firmware/main/tache_lampes.c`
- Modify: `firmware/main/pont_matter.h`, `firmware/main/pont_matter.cpp`, `firmware/main/app_main.cpp`, `firmware/main/console_pont.h`, `firmware/main/console_pont.c`
- Modify: `components/protocole/include/json_ligne.h`, `tests/hote/test_json.cpp`

**Interfaces:**
- Consumes : le composant `h1` (Task 1) ; `refusDistant`, `sessionDistante`, `ReplyCache`, `OutputLines`, `Queue::frontReady`, `kPlacesLigne`, `kPlacesPeriodique`, `textLine`, `reseauIp`, `trame`, `Reply::key`/`kid` (Task 2) ; `esp_openthread_get_instance`, `esp_openthread_task_queue_post` (fonction privée d'ESP-IDF, déclarée à la main) ; l'API `otUdp*`, `otMessage*`, `otIp6*`, `otSrpClientGetHostInfo` d'OpenThread ; `telink_lire_etat` et les codes `TELINK_CMD_*`.
- Produces :
  - `net_udp.h` (C) : `NET_UDP_PORT` (5480), `NET_UDP_SESSIONS` (2), `NET_UDP_ADRESSES` (4), `NET_UDP_PLACES_LIGNE` (2), `net_udp_type_t`, `net_udp_etat_t` ; `net_udp_demarrer()`, `bool net_udp_envoyer(slot, gen, ligne, n)`, `uint8_t net_udp_libres()`, `net_udp_finir(slot, gen)`, `net_udp_reprendre(slot, gen)`, `net_udp_cle_nouvelle(alea_app, cle_hex, empreinte)`, `net_udp_cle_effacer()`, `net_udp_lire(etat)` ;
  - `json_pont.h` (C) : `JSON_PONT_USB` (0 ; les sessions distantes sont les origines 1 et 2) ; `json_pont_distant_ligne(slot, gen, ligne, n)`, `json_pont_distant_fin(slot, gen)`, `bool json_pont_tache_distante()` ; `json_pont_ordre(lampe, signal, delai_ms, essai, ids, origines, n_ids, ids_perdus)` ; `json_pont_trames_actives()`, `json_pont_trame(rx, quoi, lampe, marche, intensite, essai)` ; le reste comme au plan 3b-1 ;
  - `tache_lampes.h` : `tache_lampes_ordre_id(lampe, marche, intensite, id, origine)` (l'octet `origine` porte l'origine en 2 bits bas et 6 bits de la génération de la session) ;
  - `pont_matter.h` : `pont_afficher(bool distant)` (sans les codes d'appairage à distance) ;
  - `console_pont.h` : `CONSOLE_PONT_TACHES` passe à 11 tâches (`udp` et `distant` s'ajoutent) ;
  - `json_ligne.h` : `Item::NetIp` (le bloc `ip` dans la file des lignes).

Pourquoi : la spec 3b, section 7, et les choix 1 à 11 de ce plan.
- **OpenThread** : CHIP possède la pile. `net_udp` ne prend jamais son verrou : ouvrir et fermer la socket (`accorder_ot`, qui suit la présence de la clé et se relance si besoin), émettre, relever le nom SRP et les adresses passent par `esp_openthread_task_queue_post`, qui exécute la fonction dans la tâche d'OpenThread, verrou tenu. Seule la tâche `udp` (priorité 1, pile de 4 Ko) y poste : `net_udp_envoyer` la réveille (`xTaskNotifyGive`) au lieu de poster lui-même, car ce poste peut attendre 100 ms puis journaliser. La réception arrive dans la tâche d'OpenThread : le rappel copie le datagramme dans une file FreeRTOS, sans verrou ni impression, et réveille la tâche `udp`, qui tient la table H1 sous son verrou et rappelle `json_pont` sans le tenir.
- **Émission** : un anneau de 12 datagrammes, plafonné à 3 000 octets par seconde (rafale de 2 400) ; un DEFI passe en tête, hors plafond, et une place lui reste toujours ; un datagramme qui n'est pas parti en 4 s est perdu et compté. Chaque passage dans la tâche d'OpenThread remet 2 datagrammes au plus, et seulement s'il reste 24 tampons d'OpenThread pour Matter ; nos messages ont la priorité basse. Les compteurs sont atomiques (plusieurs tâches les touchent).
- **Débit vers une session distante** (réglage de Halo) : une ligne périodique ne quitte la file de sa session que s'il reste 7 places dans l'anneau (`frontReady`), une réponse différée 2 ; un événement rare 2, une trame ou un `log` 7, sinon il est compté perdu pour cette session ; les deux sessions avancent à tour de rôle ; une ligne périodique distante encore en file 10 s après sa demande est perdue.
- **Sessions** : `json_pont` tient un « puits » par origine (l'USB, et les deux places H1) : mode machine, réglages, bail, file, compteur `n`, réponses différées, commande en cours, cache des réponses, pertes, génération. Chaque place H1 a une génération, changée par `net_udp` à chaque nouvelle session, nouvelle clé ou oubli : une ligne, une fin, un envoi ou l'`id` d'un ordre d'une génération passée est refusé. Les événements vont à chaque puits en mode machine ; l'événement `ordre` ne porte que les `id` de la session (origine et génération) qui a donné l'ordre.
- **Lignes distantes** : `id` obligatoire ; même `id` qu'une réponse gardée : la même réponse, sans rien exécuter ; `id` encore en cours : ignoré ; `id` plus ancien : `deja_traite` ; un `id` neuf reprend la session (`net_udp_reprendre`) avant d'être jugé : cadence, puis liste blanche. Une commande à texte permise passe à la tâche `distant` (pile de 6 Ko), qui l'exécute, une à la fois avec la console : sa sortie standard, changée par `fopencookie`, va dans un tampon (`OutputLines`) sans verrou ni attente ; une fois la commande finie et la sortie rendue, les lignes `texte` partent une à une, chacune attendant sa place dans l'anneau (1 s au plus), puis la `fin`.
- **Verrous** : `json_pont` peut appeler `net_udp` sous son verrou (`net_udp_envoyer`, `net_udp_finir`, `net_udp_libres`, `net_udp_lire`, `net_udp_reprendre`) ; `net_udp` n'appelle jamais `json_pont` en tenant le sien. `json cle nouvelle` et `json cle efface` se traitent donc hors du verrou de `json_pont` : `net_udp` y annonce les fins de session, qui le prennent. Rien ne s'imprime ni ne se journalise sous le verrou de `json_pont` depuis la tâche `distant` (une commande peut tenir un autre verrou, celui des lampes par exemple, pendant qu'elle journalise : la première version du prototype s'y figeait).
- **Clé UDP** : `json cle nouvelle <64 hexa>`, par l'USB seulement : clé = HMAC-SHA256(aléa de l'app, aléa du pont), calculée sous le verrou de `net_udp` (la crypto de `h1` n'a qu'un contexte), gardée en NVS (espace `amaran_udp`, clé `cle`) ; rendue une fois, avec son empreinte, en mode machine ; la console texte n'en montre que l'empreinte. Le port 5480 ne s'ouvre qu'avec une clé. `json cle efface`, `decommission` et BOOT tenu 8 s (`pont_desappairer`) l'effacent, de la NVS même si l'accès par Thread n'a pas démarré. À distance, `reseau matter` porte `code_manuel` et `qr` à `null`, et `matter` n'imprime pas les codes.
- **Trames** : avec `json trames 1`, la tâche des lampes décode ce qu'elle émet (ordre de marche ou d'intensité avec son essai, demande d'état, à une lampe ou au groupe) et ce qu'elle reçoit (état) ; plafond de 50 trames par seconde par l'USB, 10 à distance, où elles se coupent seules au bout de 60 s.

Repris de Halo (commit `e114cd5`) : la forme de `src/net_udp.cpp` (anneau, plafond, poignée de main) et de `src/json_mode.cpp` (cache des réponses, ligne distante). Neuf ici : le passage par la file de tâches d'OpenThread (Halo était en Arduino), les puits, la tâche `distant`, les trames.

- [ ] **Step 1 : l'interface de `net_udp`.**

`firmware/main/net_udp.h` (contenu complet) :

````c
// Canal du pont par Thread (spec 3b, section 7 ; docs/PROTOCOLE-JSON.md, section 10) :
// socket UDP 5480 sur OpenThread, enveloppe H1 (components/h1), cle UDP en NVS.
//
// Chaque emplacement de session (0 ou 1) a une generation, qui change a chaque session
// neuve, oubli ou cle changee ; json_pont l'apprend par json_pont_distant_fin avant toute
// ligne de la session, et la rend a chaque appel ci-dessous : un appel d'une generation
// perimee (une autre session a pris la place) ne touche a rien.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NET_UDP_PORT 5480
#define NET_UDP_SESSIONS 2  // h1::kSlots
#define NET_UDP_ADRESSES 4
#define NET_UDP_PLACES_LIGNE 2  // places libres qu'une ligne demande : la derniere reste au DEFI

typedef enum { NET_UDP_OMR, NET_UDP_ML_EID, NET_UDP_AUTRE } net_udp_type_t;

typedef struct {
  bool cle;
  char empreinte[9];  // 8 hexa ; vide sans cle
  bool ouvert;        // port 5480 ouvert
  uint8_t sessions;   // sessions H1 etablies
  uint32_t recus, emis, rejets, perdus;
  char srp[64];       // nom SRP (sans .local) ; vide : inconnu
  uint8_t n;
  struct {
    uint8_t a[16];
    net_udp_type_t type;
  } adresses[NET_UDP_ADRESSES];
} net_udp_etat_t;

// Apres pont_demarrer (la file de taches d'OpenThread existe) : lit la cle en NVS,
// ouvre le port si elle existe, lance la tache udp.
esp_err_t net_udp_demarrer(void);

// Une ligne machine (JSON, sans RS ni LF) vers la session `slot` de generation `gen`,
// scellee et mise en file, sans attendre : la tache udp la remet a OpenThread. Une
// place de la file reste toujours pour un DEFI : la ligne n'entre que s'il en reste
// au moins NET_UDP_PLACES_LIGNE. false : session partie (generation perimee), ou file
// pleine (ligne perdue, a compter).
bool net_udp_envoyer(uint8_t slot, uint32_t gen, const uint8_t *ligne, size_t n);

// Places libres de la file d'emission (6, partagees par les sessions et les DEFI) ;
// 0 si net_udp n'est pas demarre ou si le port est ferme.
uint8_t net_udp_libres(void);

// Fin de la session machine (json 0, bail echu) : l'emplacement peut resservir.
void net_udp_finir(uint8_t slot, uint32_t gen);
// Nouvelle commande admise de la session (jamais un renvoi servi par le cache) : elle
// sert de nouveau, meme apres json 0 (h1::Table::resume).
void net_udp_reprendre(uint8_t slot, uint32_t gen);

// json cle nouvelle (10.2) : cle = HMAC-SHA256(alea de l'app, alea du pont), gardee
// en NVS ; rend la cle (64 hexa) une seule fois, et son empreinte (8 hexa).
// ESP_ERR_INVALID_STATE : net_udp n'est pas demarre (Matter non demarre), rien ne
// change, NVS comprise ; une erreur de la NVS : rien ne change.
esp_err_t net_udp_cle_nouvelle(const uint8_t alea_app[32], char cle_hex[65], char empreinte[9]);
// json cle efface, decommission, BOOT 8 s : cle effacee, sessions tombees, port ferme.
// ESP_ERR_INVALID_STATE : net_udp n'est pas demarre, rien ne change. Une erreur de la
// NVS est rendue : la cle a quitte la memoire, mais elle reviendra au redemarrage.
esp_err_t net_udp_cle_effacer(void);

// Releve pour le bloc reseau ip (adresses et nom SRP relus toutes les 5 s).
void net_udp_lire(net_udp_etat_t *e);

#ifdef __cplusplus
}
#endif
````

- [ ] **Step 2 : `net_udp`.**

`firmware/main/net_udp.cpp` (contenu complet) :

````cpp
// Canal du pont par Thread (voir net_udp.h). Sur le modele de net_udp.cpp du pont Halo
// (commit e114cd5), avec une difference : jamais le verrou d'OpenThread depuis nos
// taches (IDF 5.5.4 : un essai rate le laisse pris). Tout appel OpenThread passe par
// la file de taches de la tache d'OpenThread, qui l'execute verrou tenu ; la reception
// arrive deja dans cette tache.
//
// Taches :
// - OpenThread : rappel de reception (copie dans s_recus), envoi (anneau -> otUdpSend),
//   ouverture et fermeture du port, releve des adresses ;
// - udp (la notre) : enveloppe H1 (poignee de main, verification), lignes recues vers
//   json_pont, expiration des sessions, port remis d'accord avec la cle. Elle seule
//   poste l'envoi a OpenThread (la poste peut attendre 100 ms, puis journaliser) : les
//   autres taches mettent en file, sans attendre, sous le verrou de json_pont ;
// - json, distant, console : net_udp_envoyer (scelle, met en file, reveille la tache udp).
// s_verrou garde la table H1, les generations, l'anneau d'emission et le releve, et le
// contexte HMAC de components/h1 : tout calcul H1 se fait sous lui. Jamais pris par la
// tache d'OpenThread autrement que sans attente.
#include "net_udp.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_openthread.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "h1_proto.h"
#include "json_ligne.h"
#include "json_pont.h"
#include "nvs.h"
#include "openthread/ip6.h"
#include "openthread/message.h"
#include "openthread/srp_client.h"
#include "openthread/thread.h"
#include "openthread/udp.h"

// Fonction privee d'ESP-IDF (private_include/esp_openthread_task_queue.h), liee telle
// quelle : execute `tache(arg)` dans la tache d'OpenThread, verrou tenu.
extern "C" esp_err_t esp_openthread_task_queue_post(void (*tache)(void *), void *arg);

static_assert(NET_UDP_SESSIONS == h1::kSlots, "une session JSON par emplacement H1");

static const char *TAG = "udp";
static const char *const NVS_ESPACE = "amaran_udp";
static const char *const NVS_CLE = "cle";

// Commande de 127 octets et son en-tete de 56 : 256 laisse de la marge ; au-dela, le
// datagramme n'est pas pour nous (compte, jete).
static constexpr size_t RX_MAX = 256;
static constexpr int RX_N = 4;
// En-tete H1 et ligne machine sans RS ni LF : 56 + 1022 octets.
static constexpr size_t TX_MAX = h1::kHeaderMax + 1022;
// 12 places : les lignes periodiques n'en prennent que 5 (kPlacesPeriodique), le reste
// absorbe une rafale de reponses et d'evenements (deux sessions, ordres simultanes).
static constexpr int TX_N = 12;
static_assert(TX_N > jsonp::kPlacesPeriodique, "la file doit garder de la place apres une periodique");
static constexpr uint32_t TX_PERIME_MS = 4000;  // pas parti dans ce delai : perdu
static constexpr int TX_PAR_TOUR = 2;           // datagrammes remis a OpenThread par appel
// Debit moyen plafonne (10.3) : 3000 octets/s, credit de 2400 (deux lignes d'un Ko).
static constexpr uint32_t TX_OCTETS_S = 3000;
static constexpr uint32_t TX_RAFALE = 2400;
// Tampons OpenThread (65, partages avec Matter) laisses libres apres un envoi.
static constexpr uint16_t TAMPONS_RESERVE = 24;
static constexpr uint32_t RELEVE_MS = 5000;
static constexpr uint32_t EXPIRE_MS = 1000;
static constexpr uint8_t BRUT = 0xFF;  // DEFI : sans session

struct recu_t {
  uint16_t lon;
  uint16_t port;
  uint8_t pair[16];
  uint8_t local[16];
  uint8_t donnees[RX_MAX];
};

struct emis_t {
  uint32_t a;     // mis en file a
  uint8_t slot;   // session qui l'a scelle ; BRUT : DEFI
  uint16_t lon;
  uint16_t port;
  uint8_t pair[16];
  uint8_t local[16];
  uint8_t donnees[TX_MAX];
};

static SemaphoreHandle_t s_verrou;
static QueueHandle_t s_recus;
static TaskHandle_t s_tache;    // tache udp
static volatile bool s_demarre;  // net_udp_demarrer a reussi
static recu_t s_recu_ot;  // tampon du rappel (tache d'OpenThread seulement)
static h1::Table s_table;
// Generation de chaque emplacement (s_verrou) : change a chaque session neuve, oubli
// ou cle changee, et json_pont l'apprend par json_pont_distant_fin (annoncer_fins).
static uint32_t s_gen[h1::kSlots];
static otUdpSocket s_socket;
// s_voulu : une cle existe, le port doit etre ouvert (ecrit sous s_verrou) ; s_ouvert :
// il l'est (tache d'OpenThread).
static volatile bool s_voulu, s_ouvert, s_envoi_poste;

// Anneau d'emission (s_verrou) ; s_emis_ot : copie de la tete, tache d'OpenThread.
static emis_t s_emis[TX_N];
static uint8_t s_tete, s_nb;
static emis_t s_emis_ot;
static uint32_t s_credit = TX_RAFALE, s_credit_a;

// Compteurs du bloc reseau ip, touches par la tache d'OpenThread et par les autres
// taches, avec ou sans s_verrou : increments atomiques.
static struct {
  uint32_t trop_grands, file_pleine, recus, rejets, emis, perdus, erreurs;
} s_st;

static void compter(uint32_t &c) { __atomic_fetch_add(&c, 1, __ATOMIC_RELAXED); }
static uint32_t lire(const uint32_t &c) { return __atomic_load_n(&c, __ATOMIC_RELAXED); }

// Releve des adresses et du nom SRP (tache d'OpenThread), lu sous s_verrou.
static net_udp_etat_t s_releve;

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static bool poster(void (*t)(void *)) { return esp_openthread_task_queue_post(t, nullptr) == ESP_OK; }

// ===========================================================================
//  Tache d'OpenThread (verrou d'OpenThread tenu)
// ===========================================================================

// Jamais de verrou ni d'impression ici : copie dans la file, reveil de la tache udp.
static void sur_reception(void *, otMessage *m, const otMessageInfo *info) {
  const uint16_t off = otMessageGetOffset(m), total = otMessageGetLength(m);
  if (total < off || (size_t)(total - off) > RX_MAX) {
    compter(s_st.trop_grands);
    return;
  }
  s_recu_ot.lon = otMessageRead(m, off, s_recu_ot.donnees, (uint16_t)(total - off));
  s_recu_ot.port = info->mPeerPort;
  memcpy(s_recu_ot.pair, info->mPeerAddr.mFields.m8, 16);
  memcpy(s_recu_ot.local, info->mSockAddr.mFields.m8, 16);
  if (xQueueSend(s_recus, &s_recu_ot, 0) != pdTRUE) {
    compter(s_st.file_pleine);
    return;
  }
  xTaskNotifyGive(s_tache);
}

// Le port suit la cle : s_voulu est lu quand la demande s'execute, une demande
// perimee (cle changee entre-temps) ne defait donc rien. Un echec (otUdpOpen,
// otUdpBind) est repris par la tache udp tous les RELEVE_MS.
static void accorder_ot(void *) {
  otInstance *ot = esp_openthread_get_instance();
  if (!s_voulu) {
    if (s_ouvert) {
      otUdpClose(ot, &s_socket);
      s_ouvert = false;
    }
    return;
  }
  if (s_ouvert) return;
  memset(&s_socket, 0, sizeof(s_socket));
  if (otUdpOpen(ot, &s_socket, sur_reception, nullptr) != OT_ERROR_NONE) return;
  otSockAddr a;
  memset(&a, 0, sizeof(a));
  a.mPort = NET_UDP_PORT;
  // Interne a OpenThread : pas de socket lwIP en double ; un port tenu par OpenThread
  // n'est plus remis a lwIP.
  if (otUdpBind(ot, &s_socket, &a, OT_NETIF_THREAD_INTERNAL) == OT_ERROR_NONE) {
    s_ouvert = true;
  } else {
    otUdpClose(ot, &s_socket);
  }
}

// La tete de l'anneau, si le credit et les tampons le permettent, copiee sous s_verrou
// pris sans attente ; envoyee ensuite, sans lui. Un datagramme sorti de l'anneau et
// non remis a OpenThread est perdu, et compte.
static void envoyer_ot(void *) {
  s_envoi_poste = false;
  otInstance *ot = esp_openthread_get_instance();
  for (int envoyes = 0; envoyes < TX_PAR_TOUR; envoyes++) {
    if (xSemaphoreTake(s_verrou, 0) != pdTRUE) return;  // la tache udp relancera
    const uint32_t t = maintenant_ms();
    while (s_nb && (int32_t)(t - s_emis[s_tete].a) > (int32_t)TX_PERIME_MS) {
      s_tete = (uint8_t)((s_tete + 1) % TX_N);
      s_nb--;
      compter(s_st.perdus);
    }
    const uint32_t ecoule = t - s_credit_a;
    s_credit_a = t;
    const uint32_t ajout = (ecoule > 10000 ? 10000 : ecoule) * TX_OCTETS_S / 1000;
    s_credit = s_credit + ajout > TX_RAFALE ? TX_RAFALE : s_credit + ajout;
    bool pris = false;
    if (s_nb && s_ouvert) {
      const emis_t &e = s_emis[s_tete];
      otBufferInfo bi;
      otMessageGetBufferInfo(ot, &bi);
      const bool tampons = bi.mFreeBuffers == 0xFFFF || bi.mFreeBuffers >= (uint16_t)(e.lon / 100 + 2) + TAMPONS_RESERVE;
      const bool credit = e.slot == BRUT || s_credit >= e.lon;
      if (tampons && credit) {
        s_emis_ot = e;
        if (e.slot != BRUT) s_credit -= e.lon;
        s_tete = (uint8_t)((s_tete + 1) % TX_N);
        s_nb--;
        pris = true;
      }
    }
    xSemaphoreGive(s_verrou);
    if (!pris) return;
    // Priorite basse : devant un manque de tampons, OpenThread evince nos messages
    // avant ceux de Matter.
    otMessageSettings ms;
    ms.mLinkSecurityEnabled = true;
    ms.mPriority = OT_MESSAGE_PRIORITY_LOW;
    otMessage *m = otUdpNewMessage(ot, &ms);
    if (!m || otMessageAppend(m, s_emis_ot.donnees, s_emis_ot.lon) != OT_ERROR_NONE) {
      if (m) otMessageFree(m);
      compter(s_st.erreurs);
      compter(s_st.perdus);
      continue;
    }
    otMessageInfo mi;
    memset(&mi, 0, sizeof(mi));
    memcpy(mi.mPeerAddr.mFields.m8, s_emis_ot.pair, 16);
    mi.mPeerPort = s_emis_ot.port;
    // Reponse depuis l'adresse que l'app a visee, si elle est encore a nous.
    otIp6Address local;
    memcpy(local.mFields.m8, s_emis_ot.local, 16);
    if (!otIp6IsAddressUnspecified(&local) && otIp6HasUnicastAddress(ot, &local)) mi.mSockAddr = local;
    mi.mSockPort = NET_UDP_PORT;
    if (otUdpSend(ot, &s_socket, m, &mi) != OT_ERROR_NONE) {
      otMessageFree(m);
      compter(s_st.erreurs);
      compter(s_st.perdus);
    } else {
      compter(s_st.emis);
    }
  }
}

static void relever_ot(void *) {
  otInstance *ot = esp_openthread_get_instance();
  net_udp_etat_t r = {};
  const otSrpClientHostInfo *h = otSrpClientGetHostInfo(ot);
  if (h && h->mName) snprintf(r.srp, sizeof(r.srp), "%s", h->mName);
  const otMeshLocalPrefix *ml = otThreadGetMeshLocalPrefix(ot);
  for (const otNetifAddress *a = otIp6GetUnicastAddresses(ot); a && r.n < NET_UDP_ADRESSES; a = a->mNext) {
    const uint8_t *b = a->mAddress.mFields.m8;
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) continue;  // lien local
    const bool maillage = ml && !memcmp(b, ml->m8, 8);
    // RLOC et ALOC : 0000:00ff:fe00:xxxx, sans interet pour l'app.
    if (maillage && b[8] == 0 && b[9] == 0 && b[10] == 0 && b[11] == 0xff && b[12] == 0xfe && b[13] == 0) continue;
    memcpy(r.adresses[r.n].a, b, 16);
    r.adresses[r.n].type = maillage ? NET_UDP_ML_EID : a->mPreferred ? NET_UDP_OMR : NET_UDP_AUTRE;
    r.n++;
  }
  if (xSemaphoreTake(s_verrou, 0) != pdTRUE) return;  // releve suivant dans 5 s
  memcpy(s_releve.srp, r.srp, sizeof(r.srp));
  memcpy(s_releve.adresses, r.adresses, sizeof(r.adresses));
  s_releve.n = r.n;
  xSemaphoreGive(s_verrou);
}

// ===========================================================================
//  Tache udp, et les autres taches
// ===========================================================================

static void aleatoire(void *p, size_t n) { esp_fill_random(p, n); }

// Sous s_verrou. Datagramme brut (DEFI) en tete de file, hors plafond de debit : une
// poignee de main n'attend pas derriere l'instantane d'une autre session.
static void mettre_brut(const h1::Peer &vers, const char *d, size_t n) {
  if (s_nb >= TX_N || n > TX_MAX) {
    compter(s_st.perdus);
    return;
  }
  s_tete = (uint8_t)((s_tete + TX_N - 1) % TX_N);
  s_nb++;
  emis_t &e = s_emis[s_tete];
  e.a = maintenant_ms();
  e.slot = BRUT;
  e.lon = (uint16_t)n;
  e.port = vers.port;
  memcpy(e.pair, vers.ip, 16);
  memcpy(e.local, vers.local, 16);
  memcpy(e.donnees, d, n);
}

// Sous s_verrou. Les datagrammes deja scelles d'une session partie ne prennent plus
// le debit de la suivante.
static void oublier_emis(uint8_t slot) {
  uint8_t gardes = 0;
  for (uint8_t i = 0; i < s_nb; i++) {
    const uint8_t de = (uint8_t)((s_tete + i) % TX_N);
    if (s_emis[de].slot == slot) {
      compter(s_st.perdus);
      continue;
    }
    const uint8_t vers = (uint8_t)((s_tete + gardes) % TX_N);
    if (vers != de) s_emis[vers] = s_emis[de];
    gardes++;
  }
  s_nb = gardes;
}

// Sous s_verrou : les sessions du masque sont parties (oubliees, remplacees, cle
// changee). Leurs datagrammes en file sont perdus, leur generation change ; gens
// recoit la nouvelle, a annoncer hors de s_verrou (annoncer_fins).
static void terminer(uint8_t masque, uint32_t gens[h1::kSlots]) {
  for (uint8_t s = 0; s < h1::kSlots; s++) {
    if (!(masque & (1u << s))) continue;
    oublier_emis(s);
    gens[s] = ++s_gen[s];
  }
}

// Tache udp seulement : la poste peut attendre 100 ms (file d'OpenThread pleine), puis
// journaliser.
static void relancer_envoi(void) {
  if (s_envoi_poste || !s_nb) return;
  s_envoi_poste = true;
  if (!poster(envoyer_ot)) s_envoi_poste = false;
}

// Fins de session (masque d'emplacements, et leurs generations) : sans s_verrou, la
// tache json prend le sien.
static void annoncer_fins(uint8_t masque, const uint32_t gens[h1::kSlots]) {
  for (uint8_t s = 0; s < h1::kSlots; s++)
    if (masque & (1u << s)) json_pont_distant_fin(s, gens[s]);
}

static void traiter(const recu_t &r) {
  static uint8_t ligne[RX_MAX + 1];
  const h1::Parsed p = h1::parse(r.donnees, r.lon);
  h1::Peer de;
  memcpy(de.ip, r.pair, 16);
  de.port = r.port;
  memcpy(de.local, r.local, 16);
  const uint32_t t = maintenant_ms();
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  compter(s_st.recus);
  if (p.kind == h1::Kind::Salut) {
    // Sans place pour le DEFI, la poignee de main en cours (celle d'un autre client
    // peut-etre) n'est pas remplacee.
    char defi[h1::kDefiLen];
    if (s_nb < TX_N && s_table.onSalut(p, aleatoire, de, t, defi) == h1::Verdict::Ok) {
      mettre_brut(de, defi, sizeof(defi));
    } else {
      compter(s_st.rejets);
    }
    xSemaphoreGive(s_verrou);
    relancer_envoi();
    return;
  }
  if (p.kind != h1::Kind::Data) {
    compter(s_st.rejets);
    xSemaphoreGive(s_verrou);
    return;
  }
  uint8_t slot = 0;
  bool neuve = false;
  uint32_t gens[h1::kSlots] = {};
  const h1::Verdict v = s_table.onData(p, de, t, &slot, &neuve);
  size_t n = 0;
  if (v == h1::Verdict::Ok) {
    n = p.payloadLen;
    memcpy(ligne, p.payload, n);
    ligne[n] = 0;
    if (neuve) terminer((uint8_t)(1u << slot), gens);  // l'emplacement servait peut-etre a une session partie
  } else {
    compter(s_st.rejets);
  }
  const uint32_t gen = s_gen[slot];
  xSemaphoreGive(s_verrou);
  if (v != h1::Verdict::Ok) return;
  if (neuve) json_pont_distant_fin(slot, gen);  // session neuve : son puits repart de zero
  // json_pont reprend la session (h1::Table::resume) s'il admet une nouvelle commande.
  json_pont_distant_ligne(slot, gen, (char *)ligne, n);
}

static void tache_udp(void *) {
  static recu_t r;
  uint32_t prochain_expire = 0, prochain_releve = 0;
  for (;;) {
    // Reveillee par un datagramme recu ou une ligne mise en file ; sinon toutes les
    // 20 ms tant que l'anneau attend du credit ou des tampons, 250 ms au repos.
    ulTaskNotifyTake(pdTRUE, s_nb ? pdMS_TO_TICKS(20) : pdMS_TO_TICKS(250));
    while (xQueueReceive(s_recus, &r, 0) == pdTRUE) traiter(r);
    const uint32_t t = maintenant_ms();
    if ((int32_t)(t - prochain_expire) >= 0) {
      prochain_expire = t + EXPIRE_MS;
      uint32_t gens[h1::kSlots] = {};
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      const uint8_t parties = s_table.expire(t);
      terminer(parties, gens);
      xSemaphoreGive(s_verrou);
      annoncer_fins(parties, gens);
    }
    if ((int32_t)(t - prochain_releve) >= 0) {
      prochain_releve = t + RELEVE_MS;
      poster(relever_ot);
      // Port et cle en desaccord (file d'OpenThread pleine, otUdpOpen ou otUdpBind en
      // echec) : nouvel essai.
      if (s_voulu != s_ouvert) poster(accorder_ot);
    }
    relancer_envoi();
  }
}

bool net_udp_envoyer(uint8_t slot, uint32_t gen, const uint8_t *ligne, size_t n) {
  if (!s_demarre || slot >= h1::kSlots || n + h1::kHeaderMax > TX_MAX) return false;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  bool ok = false;
  if (s_gen[slot] == gen && s_table.slot(slot).used && TX_N - s_nb >= NET_UDP_PLACES_LIGNE) {
    emis_t &e = s_emis[(s_tete + s_nb) % TX_N];
    char tete[h1::kHeaderMax + 1];
    const size_t hn = s_table.seal(slot, ligne, n, tete);
    if (hn) {
      const h1::Peer &vers = s_table.slot(slot).peer;
      e.a = maintenant_ms();
      e.slot = slot;
      e.lon = (uint16_t)(hn + n);
      e.port = vers.port;
      memcpy(e.pair, vers.ip, 16);
      memcpy(e.local, vers.local, 16);
      memcpy(e.donnees, tete, hn);
      memcpy(e.donnees + hn, ligne, n);
      s_nb++;
      ok = true;
    }
  }
  if (!ok) compter(s_st.perdus);
  xSemaphoreGive(s_verrou);
  if (ok) xTaskNotifyGive(s_tache);  // la tache udp la remet a OpenThread
  return ok;
}

uint8_t net_udp_libres(void) {
  if (!s_demarre) return 0;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  const uint8_t libres = s_ouvert ? (uint8_t)(TX_N - s_nb) : 0;
  xSemaphoreGive(s_verrou);
  return libres;
}

void net_udp_finir(uint8_t slot, uint32_t gen) {
  if (!s_demarre || slot >= h1::kSlots) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (s_gen[slot] == gen) s_table.end(slot);
  xSemaphoreGive(s_verrou);
}

void net_udp_reprendre(uint8_t slot, uint32_t gen) {
  if (!s_demarre || slot >= h1::kSlots) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (s_gen[slot] == gen) s_table.resume(slot);
  xSemaphoreGive(s_verrou);
}

// Sous s_verrou : nouvelle cle (ou aucune) ; les sessions tombent (masque rendu, gens
// recoit leurs generations), le port suit la cle.
static uint8_t poser_cle(const uint8_t *cle, uint32_t gens[h1::kSlots]) {
  const uint8_t parties = s_table.clear();
  terminer(parties, gens);
  s_table.setKey(cle);
  s_voulu = s_table.hasKey();
  return parties;
}

esp_err_t net_udp_cle_nouvelle(const uint8_t alea_app[32], char cle_hex[65], char empreinte[9]) {
  if (!s_demarre) return ESP_ERR_INVALID_STATE;
  uint8_t alea_pont[32], cle[32];
  esp_fill_random(alea_pont, sizeof(alea_pont));
  const h1::Part parts[] = {{alea_pont, sizeof(alea_pont)}};
  xSemaphoreTake(s_verrou, portMAX_DELAY);  // contexte HMAC partage (h1_crypto.cpp)
  const bool calculee = h1::hmacSha256(alea_app, 32, parts, 1, cle);
  xSemaphoreGive(s_verrou);
  h1::wipe(alea_pont, sizeof(alea_pont));
  if (!calculee) {
    h1::wipe(cle, sizeof(cle));
    return ESP_FAIL;
  }
  nvs_handle_t h;
  esp_err_t err = nvs_open(NVS_ESPACE, NVS_READWRITE, &h);
  if (err == ESP_OK) {
    err = nvs_set_blob(h, NVS_CLE, cle, sizeof(cle));
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
  }
  if (err != ESP_OK) {
    h1::wipe(cle, sizeof(cle));
    return err;
  }
  uint32_t gens[h1::kSlots] = {};
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  const uint8_t parties = poser_cle(cle, gens);
  xSemaphoreGive(s_verrou);
  annoncer_fins(parties, gens);
  h1::toHex(cle, sizeof(cle), cle_hex);
  h1::keyId(cle, empreinte);  // SHA-256 seul : pas de contexte partage
  h1::wipe(cle, sizeof(cle));
  poster(accorder_ot);  // en echec : la tache udp reessaie
  return ESP_OK;
}

esp_err_t net_udp_cle_effacer(void) {
  // La NVS d'abord, toujours, meme avant le demarrage de l'acces par Thread (Matter non
  // demarre, ou pas encore) : decommission et BOOT 8 s doivent la retirer pour de bon.
  nvs_handle_t h;
  esp_err_t err = nvs_open(NVS_ESPACE, NVS_READWRITE, &h);
  if (err == ESP_OK) {
    err = nvs_erase_key(h, NVS_CLE);
    if (err == ESP_ERR_NVS_NOT_FOUND) err = ESP_OK;  // deja sans cle
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
  }
  if (!s_demarre) return err;  // rien en memoire : ni table, ni port
  // En memoire, la cle part quoi qu'il arrive (sessions tombees, port ferme) ; l'erreur
  // de la NVS est rendue : la cle y est peut-etre encore.
  uint32_t gens[h1::kSlots] = {};
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  const uint8_t parties = poser_cle(nullptr, gens);
  s_nb = 0;
  xSemaphoreGive(s_verrou);
  annoncer_fins(parties, gens);
  poster(accorder_ot);  // en echec : la tache udp reessaie
  return err;
}

void net_udp_lire(net_udp_etat_t *e) {
  memset(e, 0, sizeof(*e));
  if (!s_demarre) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  *e = s_releve;
  e->cle = s_table.hasKey();
  if (e->cle) snprintf(e->empreinte, sizeof(e->empreinte), "%s", s_table.kid());
  e->ouvert = s_ouvert;
  // Les sessions finies par json 0 gardent leur place (reprenable) : pas comptees.
  for (uint8_t i = 0; i < h1::kSlots; i++) e->sessions += s_table.slot(i).used && !s_table.slot(i).ended;
  e->recus = lire(s_st.recus);
  e->emis = lire(s_st.emis);
  e->rejets = lire(s_st.rejets) + lire(s_st.trop_grands) + lire(s_st.file_pleine);
  e->perdus = lire(s_st.perdus);
  xSemaphoreGive(s_verrou);
}

esp_err_t net_udp_demarrer(void) {
  s_verrou = xSemaphoreCreateMutex();
  s_recus = xQueueCreate(RX_N, sizeof(recu_t));
  if (!s_verrou || !s_recus) return ESP_ERR_NO_MEM;
  uint8_t cle[32];
  size_t lon = sizeof(cle);
  nvs_handle_t h;
  bool avec_cle = false;
  if (nvs_open(NVS_ESPACE, NVS_READONLY, &h) == ESP_OK) {
    avec_cle = nvs_get_blob(h, NVS_CLE, cle, &lon) == ESP_OK && lon == sizeof(cle);
    nvs_close(h);
  }
  if (avec_cle) {
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    s_table.setKey(cle);
    s_voulu = s_table.hasKey();
    xSemaphoreGive(s_verrou);
  }
  h1::wipe(cle, sizeof(cle));
  if (xTaskCreate(tache_udp, "udp", 4096, nullptr, 1, &s_tache) != pdPASS) return ESP_ERR_NO_MEM;
  s_demarre = true;
  if (s_voulu && !poster(accorder_ot)) {
    ESP_LOGW(TAG, "port %u pas encore ouvert : nouvel essai dans %u s", NET_UDP_PORT, (unsigned)(RELEVE_MS / 1000));
  }
  return ESP_OK;
}
````

- [ ] **Step 3 : l'interface du mode JSON (réécrite).**

`firmware/main/json_pont.h` (contenu complet) :

````c
// Mode JSON du pont (docs/PROTOCOLE-JSON.md), par l'USB et par Thread : une session
// par origine (l'USB, et chaque session H1 de net_udp), la tache json qui forme et
// ecrit les lignes, l'execution des lignes (prefixe id=, reponses, ordres
// asynchrones, liste blanche a distance). Les briques pures sont dans
// components/protocole.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#include "config_amaran.h"
#include "diagnostic.h"
#include "lampes.h"

#ifdef __cplusplus
extern "C" {
#endif

#define JSON_PONT_CMD_MAX 127  // ligne de l'hote, prefixe id= compris (2.5)
#define JSON_PONT_IDS_MAX 4    // id en attente par lampe (evenement ordre)
#define JSON_PONT_USB 0        // origine de l'USB ; 1 et 2 : sessions distantes

// Avant le socle, la console et la tache des lampes, qui lui envoient leurs
// evenements : tire le numero de demarrage, cree les files et les taches json et
// distant. cfg reste a l'appelant (empreintes des cles, adresse, liste).
esp_err_t json_pont_demarrer(const amaran_config_t *cfg);
// Mode machine en cours par l'USB : la console lit l'USB sans echo ni invite.
bool json_pont_machine(void);
// Mode machine : lit l'USB (200 ms au plus), sans echo, et execute chaque ligne
// complete. Tache de la console seulement.
void json_pont_lire(void);
// Une ligne de la console, sans son LF, en mode texte comme en mode machine :
// prefixe id=, cadence, puis la commande et ses reponses. trop_long : la ligne
// depassait JSON_PONT_CMD_MAX octets ; rien n'est execute. Tache de la console.
void json_pont_executer(char *ligne, bool trop_long);
// La commande `json` de la console (aide, et ligne sans id).
int json_pont_commande(int argc, char **argv);

// Par Thread (net_udp) : une ligne verifiee de la session H1 `slot` (0 ou 1) de
// generation `gen` (tache udp) ; la fin d'une session (oubliee, remplacee, cle
// changee : tache udp, ou tache qui change la cle), qui remet son puits a zero et
// lui donne la generation `gen` de la suivante. net_udp annonce chaque generation
// par json_pont_distant_fin avant toute ligne : une ligne d'une autre generation
// que celle du puits, ou une fin plus ancienne que la sienne, est ignoree.
void json_pont_distant_ligne(uint8_t slot, uint32_t gen, char *ligne, size_t n);
void json_pont_distant_fin(uint8_t slot, uint32_t gen);
// La tache courante execute une commande venue de Thread : sa sortie part par
// Thread, rien de secret ne doit s'y imprimer (codes d'appairage, 10.1).
bool json_pont_tache_distante(void);

// Evenements (section 7), depuis n'importe quelle tache, sans bloquer ; ignores
// hors du mode machine.
// Fin d'un ordre de lampe : ids, les id des ordres de l'app qu'il couvre, et la
// marque de chacun (origine et generation de la session qui l'a donne, rendue
// par tache_lampes telle quelle : une session ne recoit que les siens).
void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     const uint8_t *origines, uint8_t n_ids, uint32_t ids_perdus);
void json_pont_alerte_releves(int lampe, bool manque, uint8_t pour_cent);
void json_pont_alerte_mesh(diagnostic_t etat);
typedef enum { JSON_LAMPE_ENTREE, JSON_LAMPE_MASQUEE, JSON_LAMPE_REMISE, JSON_LAMPE_ECHEC } json_lampe_t;
void json_pont_lampe(int lampe, json_lampe_t quoi, uint16_t endpoint);
// Le voyant change de motif (codes de status_led.h : patternCode).
void json_pont_led(const char *motif, const char *avant, bool test, uint32_t depuis_ms);
// Trafic Bluetooth Mesh (7.6), seulement si une session l'a demande (json trames 1).
// rx : etat recu, sinon emis ; quoi : "ordre", "demande", "etat" ; lampe -1 : le groupe ;
// marche, intensite : -1 si absents.
bool json_pont_trames_actives(void);
void json_pont_trame(bool rx, const char *quoi, int lampe, int8_t marche, int32_t intensite, uint8_t essai);
// Annonce du pont (une ligne, sans LF) : message log en mode machine avec
// `json log 1`, sinon texte. src : "lampes", "mesh", "bouton".
void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) __attribute__((format(printf, 3, 4)));

#ifdef __cplusplus
}
#endif
````

- [ ] **Step 4 : le mode JSON à plusieurs sessions (réécrit).**

`firmware/main/json_pont.cpp` (contenu complet) :

````cpp
// Mode JSON du pont (voir json_pont.h). Sur le modele de json_mode.cpp du pont
// Halo (commit e114cd5), pour ESP-IDF : une session (un « puits ») par origine,
// l'USB et chaque session H1 de net_udp. La console lit et execute les lignes de
// l'USB dans sa tache ; la tache udp, celles de Thread ; la tache distant execute
// les commandes a texte venues de Thread, sa sortie standard changee en messages
// texte ; la tache json forme les lignes periodiques et les evenements. Une ligne
// se forme et s'ecrit sous s_verrou, d'un seul appel au pilote de l'USB, ou
// scellee dans la file de net_udp, sans attendre (2.3). A distance, le debit se
// regle sur la place de cette file (10.3, json_ligne.h : kPlacesLigne) : une ligne
// de la file attend sa place, un evenement sans place est perdu et compte.
#include "json_pont.h"

#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bootloader_random.h"
#include "driver/usb_serial_jtag.h"
#include "esp_app_desc.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_idf_version.h"
#include "esp_mac.h"
#include "esp_random.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "sdkconfig.h"

#include "console_pont.h"
#include "json_amaran.h"
#include "json_ligne.h"
#include "liste.h"
#include "mesh_amaran.h"
#include "net_udp.h"
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "texte.h"

using namespace jsonp;

static_assert(JSON_PONT_CMD_MAX == kCmdMax, "json_pont.h et json_ligne.h : meme longueur de ligne");
static_assert(NET_UDP_PLACES_LIGNE == kPlacesLigne, "net_udp.h et json_ligne.h : meme place pour une ligne");
static_assert(JSON_PONT_IDS_MAX == kIdsMax, "json_pont.h et json_amaran.h : meme nombre d'id par ordre");

#define ORIGINES (1 + NET_UDP_SESSIONS)  // l'USB, puis les sessions H1
#define USB JSON_PONT_USB
#define TIC_MS 10            // une ligne de la file par tic et par puits (2.3)
#define REGARD_MS 100        // changements des lampes
#define BATTEMENT_MS 2000    // hb, quand les etat sont coupes ou lents (3.5)
#define FILE_EVENEMENTS 32   // 32 x sizeof(evenement_t) en RAM
#define FILE_JOURNAL 6
#define FILE_TRAVAUX 2       // commandes a texte venues de Thread, en attente
#define DIFFEREES 4          // reponses qui attendent la fin d'un instantane
#define RETARD_USB_MS 500    // ligne periodique perdue au-dela (2.3)
#define RETARD_DISTANT_MS 10000  // deux instantanes de 16 lampes a la fois tiennent (3 Ko/s)
#define TRAMES_DISTANT_MS 60000  // json trames 1 a distance : coupe seul (7.6)
#define PLAFOND_DISTANT 10       // a distance : 10 log et 10 trames par seconde au plus (7.5, 7.6)

typedef enum { EV_ORDRE, EV_RELEVES, EV_MESH, EV_LAMPE, EV_LED, EV_TRAME } ev_type_t;

typedef struct {
  ev_type_t type;
  int8_t lampe;
  uint8_t a, b;         // ordre : signal, essai ; releves : manque, part ; mesh : diag ; lampe : quoi ;
                        // trame : rx, essai
  uint8_t n_ids;
  uint16_t endpoint;
  uint32_t delai_ms;    // ordre ; led : depuis_ms
  uint32_t ids[kIdsMax];
  uint8_t origines[kIdsMax];
  uint32_t ids_perdus;
  const char *motif, *avant;  // led ; trame : motif = quoi
  int8_t marche;        // trame
  int32_t intensite;    // trame
} evenement_t;

typedef struct {
  const char *src;
  bool alerte;
  char txt[kLogTextMax + 1];
} journal_t;

typedef struct {
  bool utilisee;
  uint32_t id, debut_ms;
  bool bail;
  char cmd[kCmdTextMax + 1];
} differee_t;

// Ce qu'une ligne etat lampe montre : une ligne part quand cela change (REGARD_MS).
typedef struct {
  bool entendue, connu, marche, joignable, alerte, veut_marche, veut_intensite, consigne_marche;
  uint8_t phase, essai, drapeaux;
  uint16_t intensite, consigne_intensite, endpoint;
} resume_t;

// Une session : sous s_verrou ; machine, log et trames se lisent aussi sans lui.
struct puits_t {
  volatile bool machine, log, trames;
  Session reglages;
  // Distant : generation de la session H1 de net_udp, posee par remettre. Une ligne
  // ou un travail d'une autre generation est ignore ; net_udp refuse un envoi qui
  // n'est pas de la sienne. L'USB : toujours 0.
  uint32_t generation;
  uint32_t dernier_rx, derniere_cmd;
  // Commande en cours : le bail ne court pas, et le bloc sante porte son id (6.2).
  bool en_commande;
  uint32_t cmd_id;
  uint32_t prochain_etat, prochain_lampes, prochain_compteurs, prochain_reseau, prochain_hb, prochain_regard,
      fin_trames;
  Queue file;
  differee_t differees[DIFFEREES];
  resume_t resumes[LISTE_CAPACITE];
  uint32_t n, perdus;
  Cadence cadence;
  RateCap plafond_journal{20}, plafond_trames{50};
  ReplyCache cache;  // distant : reponses deja donnees, par id (10.4)
  uint32_t id_max;
  // distant : id acceptes dont la reponse fin n'est pas encore partie (json 1, json etat,
  // commande a texte) ; un renvoi de l'un d'eux est ignore, sa reponse viendra.
  uint32_t en_attente[4];
};

// Distant : la reponse fin de l'id part ; elle entre dans le cache. Sous s_verrou.
static void garder_reponse(puits_t &P, const Reply &r) {
  if (!r.fin || !r.id) return;
  P.cache.put(r);
  for (uint32_t &a : P.en_attente)
    if (a == r.id) a = 0;
}

static bool en_attente(const puits_t &P, uint32_t id) {
  for (uint32_t a : P.en_attente)
    if (a == id) return true;
  return false;
}

// Commande a texte venue de Thread, executee par la tache distant.
typedef struct {
  uint8_t origine;
  uint32_t generation, id, debut_ms;
  char cmd[kCmdMax + 1];
  char vue[kCmdTextMax + 1];
} travail_t;

static const amaran_config_t *s_cfg;
static SemaphoreHandle_t s_verrou;   // puits, ecrivain
static SemaphoreHandle_t s_commande; // une commande a texte a la fois (console, distant)
static QueueHandle_t s_evenements, s_journal, s_travaux;
static TaskHandle_t s_tache_distant;
static uint32_t s_boot;
static puits_t s_puits[ORIGINES];
static volatile bool s_trames_actives, s_log_actif;

// Ecrivain : une ligne a la fois, sous s_verrou.
static Writer s_w;
static uint32_t s_trop_longs, s_rejets;
// Evenements refuses par une file pleine, postes depuis plusieurs taches : increment atomique.
static volatile uint32_t s_evenements_perdus;

// Copies de l'etat des lampes, relues sous s_verrou quand une ligne en a besoin.
static lampes_t s_lampes;
static liste_t s_liste;

static LineAssembler s_assembleur;  // tache de la console

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
static bool echu(uint32_t t, uint32_t echeance) { return (int32_t)(t - echeance) >= 0; }

// Drapeaux lus sans verrou par les autres taches. Sous s_verrou.
static void recompter(void) {
  bool trames = false, log = false;
  for (const puits_t &p : s_puits) {
    trames = trames || (p.machine && p.trames);
    log = log || (p.machine && p.log);
  }
  s_trames_actives = trames;
  s_log_actif = log;
}

// --- Ecriture (2.3)

// Tout ou rien, sans attendre ; une seconde chance une milliseconde plus tard, si
// une autre tache tenait le pilote (son verrou d'emission).
static bool ecrire(const void *p, size_t n) {
  if (usb_serial_jtag_write_bytes(p, n, 0) == (int)n) return true;
  vTaskDelay(1);
  return usb_serial_jtag_write_bytes(p, n, 0) == (int)n;
}

// La ligne formee dans s_w vers l'origine o : n consomme, ecrite ou comptee
// perdue. A distance, sans RS ni LF : un datagramme est une ligne, pour la session
// de la generation du puits seulement. Sous s_verrou.
static void envoyer(int o) {
  puits_t &P = s_puits[o];
  P.n++;
  if (!s_w.finish()) {
    s_trop_longs++;
    return;
  }
  const bool ok = o == USB ? ecrire(s_w.data(), s_w.size())
                           : net_udp_envoyer((uint8_t)(o - 1), P.generation, s_w.data() + 1, s_w.size() - 2);
  if (!ok) P.perdus++;
}

// Distant : un evenement ne part que si la file d'emission de net_udp a encore `places`
// places libres (kPlacesLigne ; kPlacesPeriodique pour les trames et les log, frequents) ;
// sinon il est perdu pour cette session, n
// consomme (le trou le dit) et compte. Sous s_verrou.
static bool place_evenement(int o, uint8_t places) {
  if (o == USB || net_udp_libres() >= places) return true;
  s_puits[o].n++;
  s_puits[o].perdus++;
  return false;
}

// Marque d'un ordre de lampe (tache_lampes.h) : l'origine en 2 bits bas, puis 6 bits
// de la generation du puits. L'USB, dont la generation reste 0, a JSON_PONT_USB.
static_assert(ORIGINES <= 4 && JSON_PONT_USB == 0, "marque d'un ordre : 2 bits d'origine");
static uint8_t marque(int o) { return (uint8_t)((o & 0x03) | ((s_puits[o].generation & 0x3F) << 2)); }

// Texte du protocole (fin de session), par l'USB seulement. Sous s_verrou.
static void texte(int o, const char *t) {
  if (o == USB && !ecrire(t, strlen(t))) s_puits[USB].perdus++;
}

static void reponse(int o, const Reply &r) {
  reply(s_w, s_puits[o].n, maintenant_ms(), r);
  if (o != USB) garder_reponse(s_puits[o], r);
  envoyer(o);
}

static void repondre(int o, uint32_t id, const char *cmd, bool ok, const char *code, const char *msg,
                     uint32_t debut_ms) {
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.ok = ok;
  r.code = code;
  r.msg = msg;
  r.durMs = maintenant_ms() - debut_ms;
  reponse(o, r);
}

// --- Releves

static const char *code_reset(esp_reset_reason_t r) {
  switch (r) {
    case ESP_RST_POWERON: return "mise_sous_tension";
    case ESP_RST_EXT: return "broche";
    case ESP_RST_SW: return "logiciel";
    case ESP_RST_PANIC: return "panique";
    case ESP_RST_INT_WDT: return "chien_int";
    case ESP_RST_TASK_WDT: return "chien_tache";
    case ESP_RST_WDT: return "chien";
    case ESP_RST_BROWNOUT: return "baisse_tension";
    case ESP_RST_USB: return "usb";
    default: return "inconnue";
  }
}

static const char *code_diag(diagnostic_t d) {
  switch (d) {
    case DIAG_CLES_ABSENTES: return "cles_absentes";
    case DIAG_PAS_ENTRE: return "pas_entre";
    case DIAG_CLES_PERIMEES: return "cles_perimees";
    case DIAG_IV_FAUX: return "iv_faux";
    case DIAG_OK:
    default: return "ok";
  }
}

static uint32_t up_s(void) { return (uint32_t)(esp_timer_get_time() / 1000000); }

// json_perdus des blocs sante et hb : les lignes perdues de cette session (l'USB
// et chaque session distante comptent les leurs), plus les evenements perdus par
// leur file interne pleine, communs a toutes.
static uint32_t perdus_de(int o) {
  return __atomic_load_n(&s_evenements_perdus, __ATOMIC_RELAXED) + s_puits[o].perdus;
}

static void relire_lampes(void) {
  tache_lampes_lire(&s_lampes);
  tache_lampes_lire_liste(&s_liste);
}

static void resumer(int i, resume_t *r) {
  const lampe_t *p = &s_lampes.lampes[i];
  memset(r, 0, sizeof(*r));
  r->entendue = p->entendue;
  r->connu = p->connu;
  r->marche = p->lu.marche;
  r->intensite = p->lu.intensite;
  r->joignable = p->joignable;
  r->alerte = p->alerte;
  r->phase = (uint8_t)p->phase;
  r->essai = p->essai;
  r->veut_marche = p->veut_marche;
  r->veut_intensite = p->veut_intensite;
  r->consigne_marche = p->consigne.marche;
  r->consigne_intensite = p->consigne.intensite;
  r->drapeaux = s_liste.lampes[i].drapeaux;
  r->endpoint = pont_endpoint(i);
}

// --- Lignes de la file : formees a l'envoi, rien n'est perime. Sous s_verrou.

static void former(int o, const Queued &q) {
  puits_t &P = s_puits[o];
  const uint32_t ms = maintenant_ms();
  pont_infos_t pont;
  switch (q.item) {
    case Item::HelloBase: {
      const esp_app_desc_t *app = esp_app_get_description();
      HelloBase h;
      h.fw = app->version;
      h.date = app->date;
      h.heure = app->time;
      h.idf = esp_get_idf_version();
      h.puce = CONFIG_IDF_TARGET;
      h.boot = s_boot;
      const esp_reset_reason_t r = esp_reset_reason();
      h.reset = code_reset(r);
      h.resetN = (uint8_t)r;
      h.upS = up_s();
      h.session = P.reglages;
      helloBase(s_w, P.n, ms, h);
      break;
    }
    case Item::HelloId: {
      HelloId h;
      h.boot = s_boot;
      uint8_t mac[8] = {0};  // 8 octets : lecon du Halo (certaines lectures rendent un EUI-64 sur le C6)
      esp_read_mac(mac, ESP_MAC_BASE);
      memcpy(h.mac, mac, 6);
      pont_lire(&pont);
      h.fabricant = pont.fabricant;
      h.produit = pont.produit;
      h.serie = pont.serie;
      h.nom = PONT_NOM;
      helloId(s_w, P.n, ms, h);
      break;
    }
    case Item::ConfigCatalogue:
      configCatalogue(s_w, P.n, ms);
      break;
    case Item::ConfigMesh: {
      relire_lampes();
      ConfigMesh c;
      char en[9], ea[9];
      c.cles = s_cfg->cles_presentes;
      if (c.cles) {
        config_empreinte(s_cfg->netkey, en);
        config_empreinte(s_cfg->appkey, ea);
        c.empReseau = en;
        c.empApp = ea;
      }
      c.adresse = s_cfg->adresse;
      c.ivNvs = s_cfg->iv;
      mesh_balayage(&c.fenetreMs, &c.intervalleMs);
      c.lampes = s_liste.n;
      c.releveMs = s_lampes.periode_ms;
      configMesh(s_w, P.n, ms, c);
      break;
    }
    case Item::ConfigLampe:
      relire_lampes();
      if (q.arg >= s_liste.n) return;
      configLampe(s_w, P.n, ms, q.arg, s_liste.lampes[q.arg]);
      break;
    case Item::EtatPont: {
      relire_lampes();
      EtatPont e;
      e.boot = s_boot;
      e.upS = up_s();
      e.meshPret = s_lampes.mesh_pret;
      e.diag = code_diag(tache_lampes_diagnostic());
      e.ordres = s_lampes.ordres;
      e.confirmes = s_lampes.confirmes;
      e.abandons = s_lampes.abandons;
      e.tenus = s_lampes.tenus;
      e.delaiTotalMs = s_lampes.delai_total_ms;
      e.delaiMaxMs = s_lampes.delai_max_ms;
      e.lents = s_lampes.lents;
      e.releves = s_lampes.releves;
      e.trames = s_lampes.trames_recues;
      etatPont(s_w, P.n, ms, e);
      break;
    }
    case Item::EtatLampe: {
      relire_lampes();
      const int i = q.arg;
      if (i >= s_lampes.n || i >= s_liste.n) return;
      resumer(i, &P.resumes[i]);
      etatLampe(s_w, P.n, ms, i, s_lampes.lampes[i], s_liste.lampes[i], P.resumes[i].endpoint,
                lampes_part_repondue(&s_lampes, i));
      break;
    }
    case Item::EtatSante: {
      EtatSante e;
      e.boot = s_boot;
      e.upS = up_s();
      e.cmdId = P.cmd_id;
      socle_voyant_t v;
      socle_voyant(&v);
      e.motif = v.motif;
      e.test = v.test;
      e.depuisMs = v.depuis_ms;
      pont_lire(&pont);
      e.enService = pont.fabriques > 0;
      e.threadAttache = pont.thread_attache;
      e.identifie = pont.identifie;
      e.ble = pont.ble_annonce;
      e.heap = esp_get_free_heap_size();
      e.heapMin = esp_get_minimum_free_heap_size();
      e.heapBloc = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
      Pile piles[CONSOLE_PONT_NB_TACHES];
      for (int i = 0; i < CONSOLE_PONT_NB_TACHES; i++) {
        const TaskHandle_t t = xTaskGetHandle(CONSOLE_PONT_TACHES[i]);
        piles[i] = Pile{CONSOLE_PONT_TACHES[i], t ? (int32_t)uxTaskGetStackHighWaterMark(t) : -1};
      }
      e.piles = piles;
      e.nPiles = CONSOLE_PONT_NB_TACHES;
      e.perdus = perdus_de(o);
      e.tropLongs = s_trop_longs;
      e.rejets = s_rejets;
      etatSante(s_w, P.n, ms, e);
      break;
    }
    case Item::CptMesh: {
      mesh_stats_t st;
      mesh_lire_stats(&st);
      CompteursMesh c;
      c.annonces = st.annonces;
      c.nidReconnu = st.nid_reconnu;
      c.nidInconnu = st.nid_inconnu;
      c.netmicFaux = st.netmic_faux;
      c.accesDechiffres = st.acces_dechiffres;
      c.etatsLampes = st.etats_lampes;
      c.doublons = st.doublons;
      c.balisesNotres = st.balises_notres;
      c.balisesAutres = st.balises_autres;
      c.balisesFausses = st.balises_fausses;
      c.baliseVue = st.derniere_balise_us != 0;
      c.baliseIv = st.derniere_balise_iv;
      c.baliseMs = (uint32_t)(st.derniere_balise_us / 1000);
      c.baliseDrapeaux = st.derniere_balise_flags;
      c.emis = st.emis;
      c.echecsEmission = st.echecs_emission;
      c.filePleine = st.file_pleine;
      c.iv = mesh_iv_courant();
      c.seq = mesh_sequence();
      c.plancher = mesh_pret() ? mesh_plancher() : s_cfg->plancher_seq;
      compteursMesh(s_w, P.n, ms, c);
      break;
    }
    case Item::NetMatter: {
      pont_lire(&pont);
      ReseauMatter r;
      r.demarre = pont.demarre;
      r.fabriques = pont.fabriques;
      r.ble = pont.ble_annonce;
      r.identifie = pont.identifie;
      r.demandes = pont.abo_demandes;
      r.plafonnes = pont.abo_plafonnes;
      r.etablis = pont.abo_etablis;
      r.termines = pont.abo_termines;
      r.plafondS = PONT_PLAFOND_ABONNEMENT_S;
      // Les codes d'appairage ne passent jamais par Thread (10.1) : null a distance.
      r.codeManuel = o == USB ? pont.code_manuel : nullptr;
      r.qr = o == USB ? pont.qr : nullptr;
      reseauMatter(s_w, P.n, ms, r);
      break;
    }
    case Item::NetThread:
      pont_lire(&pont);
      reseauThread(s_w, P.n, ms, pont.role, pont.thread_attache);
      break;
    case Item::NetIp: {
      net_udp_etat_t u;
      net_udp_lire(&u);
      ReseauIp r;
      r.srp = u.srp[0] ? u.srp : nullptr;
      static const char *const TYPES[] = {"omr", "ml_eid", "autre"};
      for (uint8_t i = 0; i < u.n && i < 4; i++) {
        memcpy(r.adresses[i].a, u.adresses[i].a, 16);
        r.adresses[i].type = TYPES[u.adresses[i].type % 3];
      }
      r.n = u.n;
      r.cle = u.cle;
      r.empreinte = u.cle ? u.empreinte : nullptr;
      r.ouvert = u.ouvert;
      r.sessions = u.sessions;
      r.recus = u.recus;
      r.emis = u.emis;
      r.rejets = u.rejets;
      r.perdus = u.perdus;
      reseauIp(s_w, P.n, ms, r);
      break;
    }
    case Item::Heartbeat:
      heartbeat(s_w, P.n, ms, s_boot, up_s(), perdus_de(o), P.cmd_id);
      break;
    case Item::Reply: {
      differee_t *d = &P.differees[q.arg % DIFFEREES];
      if (!d->utilisee) return;
      Reply r;
      r.id = d->id;
      r.cmd = d->cmd;
      r.durMs = ms - d->debut_ms;
      r.hasLease = d->bail;
      r.leaseS = P.reglages.bailS;
      r.upS = up_s();
      d->utilisee = false;
      reply(s_w, P.n, ms, r);
      if (o != USB) garder_reponse(P, r);
      break;
    }
  }
  envoyer(o);
}

// --- Session. Sous s_verrou.

static void pousser_hello(int o, uint32_t t, bool session) {
  Queue &f = s_puits[o].file;
  f.push(Item::HelloBase, t, session);
  f.push(Item::HelloId, t, session);
  f.push(Item::ConfigCatalogue, t, session);
  f.push(Item::ConfigMesh, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) f.push(Item::ConfigLampe, t, session, i);
}

static void pousser_reseau(int o, uint32_t t, bool session) {
  Queue &f = s_puits[o].file;
  f.push(Item::NetMatter, t, session);
  f.push(Item::NetThread, t, session);
  f.push(Item::NetIp, t, session);
}

static void pousser_etat(int o, uint32_t t, bool session) {
  Queue &f = s_puits[o].file;
  f.push(Item::EtatPont, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) f.push(Item::EtatLampe, t, session, i);
  f.push(Item::EtatSante, t, session);
  if (s_puits[o].reglages.compteursMs || o == USB) f.push(Item::CptMesh, t, session);
  pousser_reseau(o, t, session);
}

// Reponse fin apres les lignes en file. Sans place : tout de suite.
static void differer(int o, uint32_t id, const char *cmd, bool bail, uint32_t debut_ms) {
  puits_t &P = s_puits[o];
  for (uint8_t k = 0; k < DIFFEREES; k++) {
    differee_t *d = &P.differees[k];
    if (d->utilisee) continue;
    d->utilisee = true;
    d->id = id;
    d->debut_ms = debut_ms;
    d->bail = bail;
    copyCmd(d->cmd, cmd);
    if (P.file.push(Item::Reply, maintenant_ms(), false, k)) return;
    d->utilisee = false;
    break;
  }
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.durMs = maintenant_ms() - debut_ms;
  r.hasLease = bail;
  r.leaseS = P.reglages.bailS;
  r.upS = up_s();
  reponse(o, r);
}

static void entrer(int o, uint16_t bail_s, uint32_t t) {
  puits_t &P = s_puits[o];
  P.file.dropSession();
  P.reglages = o == USB ? Session() : sessionDistante();
  P.reglages.bailS = bail_s;
  P.log = false;
  P.trames = false;
  P.dernier_rx = P.derniere_cmd = t;
  P.prochain_etat = t + P.reglages.periodeMs;
  P.prochain_lampes = t + P.reglages.lampesMs;
  P.prochain_compteurs = t + P.reglages.compteursMs;
  P.prochain_reseau = t + P.reglages.reseauMs;
  P.prochain_hb = P.prochain_regard = t;
  memset(P.resumes, 0, sizeof(P.resumes));
  if (o == USB) s_assembleur.reset();
  P.machine = true;
  recompter();
  pousser_hello(o, t, true);
  pousser_etat(o, t, true);
}

static void sortir(int o, const char *cause, const char *message) {
  puits_t &P = s_puits[o];
  sessionEnd(s_w, P.n, maintenant_ms(), cause);
  envoyer(o);
  P.machine = false;
  P.log = false;
  P.trames = false;
  P.file.dropSession();
  recompter();
  texte(o, message);
  if (o != USB) net_udp_finir((uint8_t)(o - 1), P.generation);
}

// Les lignes etat lampe dont ce qu'elles montrent a change, pour chaque puits.
static void regarder(uint32_t t) {
  relire_lampes();
  for (int i = 0; i < s_lampes.n && i < s_liste.n; i++) {
    resume_t r;
    resumer(i, &r);
    for (int o = 0; o < ORIGINES; o++) {
      puits_t &P = s_puits[o];
      if (P.machine && memcmp(&r, &P.resumes[i], sizeof(r)) != 0) P.file.push(Item::EtatLampe, t, true, (uint8_t)i);
    }
  }
}

static void programmer(int o, uint32_t t) {
  puits_t &P = s_puits[o];
  if (!P.en_commande && leaseExpired(t, P.dernier_rx, P.derniere_cmd, P.reglages.bailS)) {
    char m[80];
    snprintf(m, sizeof(m), "json : mode machine coupe (hote muet depuis %u s)\r\n", (unsigned)P.reglages.bailS);
    sortir(o, "bail", m);
    return;
  }
  if (o != USB && P.trames && echu(t, P.fin_trames)) {
    P.trames = P.reglages.trames = false;
    recompter();
  }
  if (P.reglages.periodeMs && echu(t, P.prochain_etat)) {
    P.file.push(Item::EtatPont, t, true);
    P.file.push(Item::EtatSante, t, true);
    P.prochain_etat = t + P.reglages.periodeMs;
  }
  if (P.reglages.lampesMs && echu(t, P.prochain_lampes)) {
    for (uint8_t i = 0; i < s_cfg->liste.n; i++) P.file.push(Item::EtatLampe, t, true, i);
    P.prochain_lampes = t + P.reglages.lampesMs;
  }
  if (P.reglages.compteursMs && echu(t, P.prochain_compteurs)) {
    P.file.push(Item::CptMesh, t, true);
    P.prochain_compteurs = t + P.reglages.compteursMs;
  }
  if (P.reglages.reseauMs && echu(t, P.prochain_reseau)) {
    pousser_reseau(o, t, true);
    P.prochain_reseau = t + P.reglages.reseauMs;
  }
  if ((P.reglages.periodeMs == 0 || P.reglages.periodeMs > BATTEMENT_MS) && echu(t, P.prochain_hb)) {
    P.file.push(Item::Heartbeat, t, true);
    P.prochain_hb = t + BATTEMENT_MS;
  }
}

// --- Evenements. Sous s_verrou.

static void evenement(const evenement_t &e) {
  const uint32_t ms = maintenant_ms();
  for (int o = 0; o < ORIGINES; o++) {
    puits_t &P = s_puits[o];
    if (!P.machine) continue;
    if (e.type == EV_TRAME) {
      if (!P.trames) continue;
      if (!P.plafond_trames.available(ms)) {
        P.plafond_trames.skip();
        continue;
      }
    }
    // Trames : frequentes, elles ne prennent pas la place d'une reponse (eventRoom de Halo).
    if (!place_evenement(o, e.type == EV_TRAME ? kPlacesPeriodique : kPlacesLigne)) continue;
    switch (e.type) {
      case EV_ORDRE: {
        Ordre r;
        r.lampe = e.lampe;
        r.issue = e.a == LAMPES_SIGNAL_CONFIRME ? "confirme" : e.a == LAMPES_SIGNAL_ABANDON ? "abandon" : "tenu";
        r.delaiMs = e.delai_ms;
        r.essai = e.b;
        // Les id de cette session seulement : son origine et sa generation.
        for (uint8_t i = 0; i < e.n_ids; i++)
          if (e.origines[i] == marque(o)) r.ids[r.nIds++] = e.ids[i];
        r.idsPerdus = e.ids_perdus;
        ordre(s_w, P.n, ms, r);
        break;
      }
      case EV_RELEVES:
        alerteReleves(s_w, P.n, ms, e.lampe, e.a != 0, e.b);
        break;
      case EV_MESH:
        alerteMesh(s_w, P.n, ms, code_diag((diagnostic_t)e.a));
        break;
      case EV_LAMPE: {
        static const char *const QUOI[] = {"entree", "masquee", "remise", "echec"};
        lampe(s_w, P.n, ms, e.lampe, QUOI[e.a % 4], e.endpoint);
        break;
      }
      case EV_LED:
        led(s_w, P.n, ms, e.motif, e.avant, e.a != 0, e.delai_ms);
        break;
      case EV_TRAME: {
        P.plafond_trames.take();
        Trame t;
        t.sens = e.a ? "rx" : "tx";
        t.quoi = e.motif;
        t.lampe = e.lampe;
        t.marche = e.marche;
        t.intensite = e.intensite;
        t.essai = e.b;
        t.sautes = P.plafond_trames.takeSkipped();
        trame(s_w, P.n, ms, t);
        break;
      }
    }
    envoyer(o);
  }
}

static void journal(const journal_t &j) {
  const uint32_t t = maintenant_ms();
  for (int o = 0; o < ORIGINES; o++) {
    puits_t &P = s_puits[o];
    if (!P.machine || !P.log) continue;
    if (!P.plafond_journal.available(t)) {
      P.plafond_journal.skip();
      continue;
    }
    if (!place_evenement(o, kPlacesPeriodique)) continue;  // frequents, comme les trames
    P.plafond_journal.take();
    logLine(s_w, P.n, t, j.src, j.alerte ? "alerte" : "notice", j.txt, P.plafond_journal.takeSkipped());
    envoyer(o);
  }
}

static bool une_session(void) {
  for (const puits_t &p : s_puits)
    if (p.machine) return true;
  return false;
}

static void tache_json(void *arg) {
  (void)arg;
  uint32_t prochain_tic = maintenant_ms();
  uint8_t tour = 0;
  for (;;) {
    const int32_t attente = (int32_t)(prochain_tic - maintenant_ms());
    evenement_t e;
    if (xQueueReceive(s_evenements, &e, attente > 0 ? pdMS_TO_TICKS(attente) : 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      evenement(e);
      xSemaphoreGive(s_verrou);
      // Les evenements d'abord (ils ne passent pas par la file), mais le tic a son heure.
      if (!echu(maintenant_ms(), prochain_tic)) continue;
    }
    journal_t j;
    while (xQueueReceive(s_journal, &j, 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      journal(j);
      xSemaphoreGive(s_verrou);
    }
    const uint32_t t = maintenant_ms();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    bool regard = false;
    for (int o = 0; o < ORIGINES; o++) {
      puits_t &P = s_puits[o];
      if (P.machine) {
        programmer(o, t);
        if (echu(t, P.prochain_regard)) {
          regard = true;
          P.prochain_regard = t + REGARD_MS;
        }
      }
    }
    if (regard && une_session()) regarder(t);
    // L'USB, puis les sessions distantes, qui partagent la file d'emission de net_udp
    // et son debit, a tour de role : deux instantanes simultanes avancent ensemble.
    tour = (uint8_t)(tour + 1);
    for (int k = 0; k < ORIGINES; k++) {
      const int o = k == 0 ? USB : 1 + (k - 1 + tour) % NET_UDP_SESSIONS;
      puits_t &P = s_puits[o];
      P.perdus += P.file.dropLate(t, o == USB ? RETARD_USB_MS : RETARD_DISTANT_MS);
      const Queued *q = P.file.front();
      if (!q) continue;
      // A distance, la ligne attend sa place dans la file de net_udp (10.3) : 7 places
      // libres pour une periodique, 2 pour une reponse ; sinon au tic suivant.
      if (o != USB && !P.file.frontReady(net_udp_libres())) continue;
      const Queued copie = *q;
      P.file.pop();
      former(o, copie);
    }
    xSemaphoreGive(s_verrou);
    prochain_tic = t + TIC_MS;
  }
}

// --- Commandes

static bool lire_ms(const char *texte, uint32_t min, uint32_t max, uint32_t *v) {
  return texte_lire_nombre(texte, v) && (*v == 0 || (*v >= min && *v <= max));
}

static bool hexa(const char *s, uint8_t *out, size_t n) {
  if (strlen(s) != 2 * n) return false;
  for (size_t i = 0; i < n; i++) {
    unsigned v = 0;
    for (int k = 0; k < 2; k++) {
      const char c = s[2 * i + k];
      const unsigned d = c >= '0' && c <= '9' ? (unsigned)(c - '0')
                         : c >= 'A' && c <= 'F' ? (unsigned)(c - 'A' + 10)
                         : c >= 'a' && c <= 'f' ? (unsigned)(c - 'a' + 10)
                                                : 16u;
      if (d > 15) return false;
      v = v << 4 | d;
    }
    out[i] = (uint8_t)v;
  }
  return true;
}

// Pourquoi `json cle` a echoue, pour la reponse (msg, 120 octets au plus) et la
// console texte.
static const char *raison_cle(bool efface, esp_err_t err, char *t, size_t n) {
  if (err == ESP_ERR_INVALID_STATE) return "acces par Thread non demarre (Matter non demarre) : rien n'a change";
  if (efface) {
    snprintf(t, n, "cle effacee de la memoire, pas de la NVS (%s) : elle reviendra au redemarrage",
             esp_err_to_name(err));
  } else {
    snprintf(t, n, "cle non creee (%s) : rien n'a change", esp_err_to_name(err));
  }
  return t;
}

// `json cle nouvelle <64 hexa>` et `json cle efface` (10.2), par l'USB seulement :
// hors de s_verrou (net_udp annonce les fins de session, qui le prennent). true : traitee.
static bool commande_cle(int o, uint32_t id, const char *vue, int argc, char **argv, uint32_t debut_ms) {
  if (argc < 2 || strcmp(argv[0], "json") || strcmp(argv[1], "cle")) return false;
  const bool nouvelle = argc == 4 && !strcmp(argv[2], "nouvelle");
  const bool efface = argc == 3 && !strcmp(argv[2], "efface");
  uint8_t alea[32];
  char cle[65] = {}, emp[9] = {}, raison[kMsgMax + 1];
  const char *erreur = nullptr;
  esp_err_t err = ESP_OK;
  if (o != USB) {
    erreur = "USB seulement";
  } else if (nouvelle && id && !s_puits[USB].machine) {
    // json cle nouvelle avec id : en mode machine seulement. Rien ne change.
    erreur = "json cle nouvelle avec id : en mode machine seulement (json 1)";
  } else if (nouvelle && hexa(argv[3], alea, sizeof(alea))) {
    err = net_udp_cle_nouvelle(alea, cle, emp);
    memset(alea, 0, sizeof(alea));
  } else if (efface) {
    err = net_udp_cle_effacer();
  } else {
    erreur = "json cle nouvelle <64 hexa> | json cle efface";
  }
  if (!erreur && err != ESP_OK) erreur = raison_cle(efface, err, raison, sizeof(raison));
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (id) {
    Reply r;
    r.id = id;
    r.cmd = vue;
    r.durMs = maintenant_ms() - debut_ms;
    if (erreur) {
      r.ok = false;
      r.code = err == ESP_OK ? "usage" : "erreur";
      r.msg = erreur;
    } else if (nouvelle) {
      r.key = cle;
      r.kid = emp;
    }
    reponse(o, r);
  } else if (erreur) {
    printf("erreur : %s\n", erreur);
  } else {
    // A la console, jamais la cle : seulement son empreinte.
    printf(nouvelle ? "ok cle UDP %s, port %u ouvert\n" : "ok cle UDP effacee%s, port %u ferme\n", emp, NET_UDP_PORT);
  }
  s_puits[o].derniere_cmd = maintenant_ms();
  xSemaphoreGive(s_verrou);
  memset(cle, 0, sizeof(cle));
  return true;
}

// La famille `json` (3.3). id 0 : sans reponse, texte pour un humain. Sous s_verrou.
static void commande_json(int o, uint32_t id, const char *vue, int argc, char **argv, uint32_t debut_ms) {
  static const char USAGE[] =
      "json [1 [bail <s>]|0|etat|hello|ping|periode|lampes|compteurs|reseau <ms>|log 0|1|trames 0|1|cle ...]";
  puits_t &P = s_puits[o];
  const uint32_t t = maintenant_ms();
  const char *sous = argc >= 2 ? argv[1] : "";
  uint32_t v = 0;
  const char *erreur = nullptr;
  if (argc == 1) {
    printf("json : mode %s, bail %u s, etat %" PRIu32 " ms, lampes %" PRIu32 " ms, compteurs %" PRIu32
           " ms, reseau %" PRIu32 " ms, log %s, trames %s ; lignes %" PRIu32 ", perdues %" PRIu32
           ", refusees %" PRIu32 "\n",
           P.machine ? "machine" : "texte", (unsigned)P.reglages.bailS, P.reglages.periodeMs, P.reglages.lampesMs,
           P.reglages.compteursMs, P.reglages.reseauMs, P.reglages.log ? "oui" : "non",
           P.reglages.trames ? "oui" : "non", P.n, perdus_de(o), s_rejets);
    for (int k = 1; k < ORIGINES; k++)
      if (s_puits[k].machine)
        printf("json : session distante %d en mode machine ; lignes %" PRIu32 ", perdues %" PRIu32 "\n", k,
               s_puits[k].n, s_puits[k].perdus);
  } else if (!strcmp(sous, "1")) {
    if (argc == 2 || (argc == 4 && !strcmp(argv[2], "bail") && lire_ms(argv[3], 10, 600, &v))) {
      entrer(o, argc == 4 ? (uint16_t)v : 30, t);
      if (id) {
        differer(o, id, vue, true, debut_ms);
        return;
      }
    } else {
      erreur = "json 1 [bail 0|10-600]";
    }
  } else if (!strcmp(sous, "0") && argc == 2) {
    if (id) repondre(o, id, vue, true, "ok", nullptr, debut_ms);
    if (P.machine) sortir(o, "commande", "json : mode machine coupe\r\n");
    return;
  } else if ((!strcmp(sous, "etat") || !strcmp(sous, "hello")) && argc == 2) {
    if (!strcmp(sous, "etat")) pousser_etat(o, t, false);
    else pousser_hello(o, t, false);
    if (id) {
      differer(o, id, vue, false, debut_ms);
      return;
    }
  } else if (!strcmp(sous, "ping") && argc == 2) {
    P.dernier_rx = t;
    if (id) {
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.durMs = t - debut_ms;
      r.hasLease = true;
      r.leaseS = P.reglages.bailS;
      r.upS = up_s();
      reponse(o, r);
      return;
    }
  } else if (argc == 3 && !strcmp(sous, "periode")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      P.reglages.periodeMs = v;
      P.prochain_etat = P.prochain_hb = t;
    } else {
      erreur = "json periode <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "lampes")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      P.reglages.lampesMs = v;
      P.prochain_lampes = t;
    } else {
      erreur = "json lampes <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "compteurs")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      P.reglages.compteursMs = v;
      P.prochain_compteurs = t;
    } else {
      erreur = "json compteurs <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "reseau")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      P.reglages.reseauMs = v;
      P.prochain_reseau = t;
    } else {
      erreur = "json reseau <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "log") && (!strcmp(argv[2], "0") || !strcmp(argv[2], "1"))) {
    P.reglages.log = !strcmp(argv[2], "1");
    P.log = P.reglages.log;
    recompter();
  } else if (argc == 3 && !strcmp(sous, "trames") && (!strcmp(argv[2], "0") || !strcmp(argv[2], "1"))) {
    P.reglages.trames = !strcmp(argv[2], "1");
    P.trames = P.reglages.trames;
    P.fin_trames = t + TRAMES_DISTANT_MS;
    recompter();
  } else {
    erreur = USAGE;
  }
  if (id) {
    repondre(o, id, vue, !erreur, erreur ? "usage" : "ok", erreur, debut_ms);
  } else if (erreur) {
    printf("erreur : %s\n", erreur);
  } else if (argc > 1) {
    printf("ok json %s\n", sous);
  }
}

int json_pont_commande(int argc, char **argv) {
  if (commande_cle(USB, 0, "", argc, argv, maintenant_ms())) return 0;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  commande_json(USB, 0, "", argc, argv, maintenant_ms());
  xSemaphoreGive(s_verrou);
  return 0;
}

// `lampe <n> on|off|niveau <0-1000>` : true et l'ordre rempli ; *usage : la
// ligne en a la forme, mais un argument est invalide.
static bool ordre_de_lampe(int argc, char **argv, int *lampe, int8_t *marche, int32_t *intensite, bool *usage) {
  *usage = false;
  if (argc < 3 || strcmp(argv[0], "lampe")) return false;
  const bool on_off = argc == 3 && (!strcmp(argv[2], "on") || !strcmp(argv[2], "off"));
  const bool niveau = argc == 4 && !strcmp(argv[2], "niveau");
  if (!on_off && !niveau) return false;
  uint32_t n = 0, v = 0;
  if (!texte_lire_nombre(argv[1], &n) || n < 1 || n > s_cfg->liste.n ||
      (niveau && (!texte_lire_nombre(argv[3], &v) || v > TELINK_INTENSITE_MAX))) {
    *usage = true;
    return true;
  }
  *lampe = (int)n - 1;
  *marche = on_off ? !strcmp(argv[2], "on") : -1;
  *intensite = niveau ? (int32_t)v : -1;
  return true;
}

// La commande telle que la reponse la cite : jamais une cle (mesh cles, json cle
// nouvelle, avec ou sans guillemets), puis tronquee. Jugee sur les mots decoupes.
static void citer(const char *cmd, int argc, char **argv, char vue[kCmdTextMax + 1]) {
  char masquee[kCmdMax + 1];
  snprintf(masquee, sizeof(masquee), "%s", cmd);
  maskCmd(masquee);
  if (argc >= 1 && (!strncmp(argv[0], "mesh cles", 9) || (!strcmp(argv[0], "mesh") && argc >= 2 && !strncmp(argv[1], "cles", 4))))
    snprintf(masquee, sizeof(masquee), "mesh cles");
  if (argc >= 1 && (!strncmp(argv[0], "json cle", 8) || (!strcmp(argv[0], "json") && argc >= 2 && !strncmp(argv[1], "cle", 3))))
    snprintf(masquee, sizeof(masquee), argc >= 3 && !strcmp(argv[2], "nouvelle") ? "json cle nouvelle" : "json cle");
  copyCmd(vue, masquee);
}

// Ordre de lampe asynchrone (6.2), avec un id. Sous s_verrou. true : traite.
static bool ordre_asynchrone(int o, uint32_t id, const char *vue, int argc, char **argv, uint32_t debut) {
  int lampe = 0;
  int8_t marche = -1;
  int32_t intensite = -1;
  bool usage = false;
  if (!ordre_de_lampe(argc, argv, &lampe, &marche, &intensite, &usage)) return false;
  if (usage) {
    char msg[64];
    snprintf(msg, sizeof(msg), "lampe <1-%u> on|off|niveau <0-1000>", (unsigned)s_cfg->liste.n);
    repondre(o, id, vue, false, "usage", msg, debut);
  } else {
    // L'id part avec l'ordre, et la marque de cette session (origine, generation) :
    // l'evenement ordre qui le finira le portera, vers elle seulement (7.1), pas vers
    // une session qui aurait pris sa place entre-temps.
    const bool m = marche == 1;
    const uint16_t v = (uint16_t)intensite;
    if (tache_lampes_ordre_id(lampe, marche >= 0 ? &m : nullptr, intensite >= 0 ? &v : nullptr, id, marque(o))) {
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.code = "accepte";
      r.suite = Reply::SuiteOrder;
      r.lampe = (uint8_t)(lampe + 1);
      r.durMs = maintenant_ms() - debut;
      reponse(o, r);
    } else {
      repondre(o, id, vue, false, "erreur", "file des lampes pleine", debut);
    }
  }
  s_puits[o].derniere_cmd = maintenant_ms();
  return true;
}

void json_pont_executer(char *ligne, bool trop_long) {
  const uint32_t debut = maintenant_ms();
  uint32_t id = 0;
  char *cmd = ligne;
  const bool a_id = parseIdPrefix(ligne, &id, &cmd);
  // Ligne vide (l'effacement 0x15 + LF que l'app envoie a l'ouverture) : rien a faire.
  if (!a_id && !trop_long && strspn(cmd, " ") == strlen(cmd)) return;
  // Les mots de la commande (esp_console_run decoupe une copie de son cote). Decoupes avant
  // la reponse : les guillemets sont retires ici comme par la console, et la commande citee
  // se juge sur ses mots, pas sur la ligne brute. Tache de la console seulement.
  static char copie[kCmdMax + 1];
  static char *argv[8];
  snprintf(copie, sizeof(copie), "%s", cmd);
  const int argc = (int)esp_console_split_argv(copie, argv, sizeof(argv) / sizeof(argv[0]));
  char vue[kCmdTextMax + 1];
  citer(cmd, argc, argv, vue);
  puits_t &P = s_puits[USB];
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  P.dernier_rx = debut;
  const char *refus = nullptr, *code = nullptr;
  if (trop_long) {
    refus = "ligne de plus de 127 octets : rien n'est execute";
    code = "trop_long";
  } else if (P.machine && !P.cadence.allow(debut)) {
    refus = "plus de 20 lignes par seconde : rien n'est execute";
    code = "cadence";
  }
  if (refus) {
    s_rejets++;
    if (a_id) repondre(USB, id, vue, false, code, refus, debut);
    xSemaphoreGive(s_verrou);
    if (!a_id) printf("erreur : %s\n", refus);
    return;
  }
  xSemaphoreGive(s_verrou);
  if (commande_cle(USB, a_id ? id : 0, vue, argc, argv, debut)) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (argc >= 1 && !strcmp(argv[0], "json")) {
    commande_json(USB, a_id ? id : 0, vue, argc, argv, debut);
    P.derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  if (a_id && ordre_asynchrone(USB, id, vue, argc, argv, debut)) {
    xSemaphoreGive(s_verrou);
    return;
  }
  xSemaphoreGive(s_verrou);
  // Toute autre commande : debut, son texte, fin (6.2), une commande a texte a la fois.
  // Rien sous s_verrou pendant qu'elle tourne : la tache json continue d'emettre. L'id
  // de la commande entre dans le bloc sante avec le debut, et en sort avec la fin.
  xSemaphoreTake(s_commande, portMAX_DELAY);
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  P.en_commande = true;
  if (a_id) {
    P.cmd_id = id;
    Reply r;
    r.id = id;
    r.fin = false;
    r.cmd = vue;
    r.code = "en_cours";
    reponse(USB, r);
  }
  xSemaphoreGive(s_verrou);
  int ret = 0;
  const esp_err_t err = argc >= 1 ? esp_console_run(cmd, &ret) : ESP_ERR_INVALID_ARG;
  if (err == ESP_ERR_NOT_FOUND) printf("Commande inconnue : \"%s\" (help)\n", argv[0]);
  fflush(stdout);  // le texte de la commande passe avant la reponse fin
  xSemaphoreGive(s_commande);
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  P.derniere_cmd = maintenant_ms();
  P.en_commande = false;
  P.cmd_id = 0;
  if (a_id) {
    const bool inconnue = err != ESP_OK;
    const bool ok = !inconnue && ret == 0;
    repondre(USB, id, vue, ok, inconnue ? "inconnue" : ok ? "ok" : "erreur", nullptr, debut);
  }
  // Une commande mesh reussie a pu changer la configuration du Mesh (5.2).
  if (err == ESP_OK && ret == 0 && argc >= 1 && !strcmp(argv[0], "mesh"))
    for (puits_t &p : s_puits)
      if (p.machine) p.file.push(Item::ConfigMesh, maintenant_ms(), false);
  xSemaphoreGive(s_verrou);
}

void json_pont_lire(void) {
  uint8_t octets[64];
  const int n = usb_serial_jtag_read_bytes(octets, sizeof(octets), pdMS_TO_TICKS(200));
  if (n <= 0) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_puits[USB].dernier_rx = maintenant_ms();
  xSemaphoreGive(s_verrou);
  for (int i = 0; i < n; i++) {
    if (s_assembleur.feed(octets[i]) != LineAssembler::Ev::Line) continue;
    json_pont_executer(s_assembleur.text(), s_assembleur.tooLong());
    s_assembleur.reset();
  }
}

bool json_pont_machine(void) { return s_puits[USB].machine; }

// --- A distance (10.4)

// Puits remis a zero, a la generation gen de net_udp (session neuve, oubliee, cle
// changee) : rien de la session d'avant ne lui reste. Sous s_verrou.
static void remettre(int o, uint32_t gen) {
  puits_t &P = s_puits[o];
  P.machine = P.log = P.trames = false;
  P.reglages = sessionDistante();
  P.generation = gen;
  P.en_commande = false;
  P.cmd_id = 0;
  P.file.clear();
  memset(P.differees, 0, sizeof(P.differees));
  P.cache.clear();
  P.id_max = 0;
  memset(P.en_attente, 0, sizeof(P.en_attente));
  P.n = P.perdus = 0;
  P.cadence = Cadence();
  P.plafond_journal = RateCap(PLAFOND_DISTANT);
  P.plafond_trames = RateCap(PLAFOND_DISTANT);
  recompter();
}

void json_pont_distant_fin(uint8_t slot, uint32_t gen) {
  if (slot >= NET_UDP_SESSIONS || !s_verrou) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  // Une fin plus ancienne que la generation du puits (annoncee par une autre tache,
  // arrivee apres la suivante) ne defait pas la session neuve.
  if ((int32_t)(gen - s_puits[1 + slot].generation) > 0) remettre(1 + slot, gen);
  xSemaphoreGive(s_verrou);
}

void json_pont_distant_ligne(uint8_t slot, uint32_t gen, char *ligne, size_t n) {
  if (slot >= NET_UDP_SESSIONS) return;
  const int o = 1 + slot;
  puits_t &P = s_puits[o];
  const uint32_t debut = maintenant_ms();
  uint32_t id = 0;
  char *cmd = ligne;
  const bool a_id = parseIdPrefix(ligne, &id, &cmd);
  char copie[kCmdMax + 1];
  char *argv[8];
  snprintf(copie, sizeof(copie), "%s", cmd);
  const int argc = (int)esp_console_split_argv(copie, argv, sizeof(argv) / sizeof(argv[0]));
  char vue[kCmdTextMax + 1];
  citer(cmd, argc, argv, vue);
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (P.generation != gen) {  // session deja remplacee ou tombee : plus pour ce puits
    xSemaphoreGive(s_verrou);
    return;
  }
  P.dernier_rx = debut;
  if (!a_id) {  // a distance, toute ligne porte un id (10.4)
    s_rejets++;
    xSemaphoreGive(s_verrou);
    return;
  }
  // Un id deja traite : la meme reponse, sans executer de nouveau ; plus ancien que
  // le cache : deja_traite.
  const Reply *deja = P.cache.find(id);
  if (deja) {
    Reply r = *deja;
    reply(s_w, P.n, maintenant_ms(), r);
    envoyer(o);
    xSemaphoreGive(s_verrou);
    return;
  }
  if (en_attente(P, id)) {  // renvoi d'une commande encore en cours : sa reponse viendra
    xSemaphoreGive(s_verrou);
    return;
  }
  if (id <= P.id_max) {
    repondre(o, id, vue, false, "deja_traite", "id deja traite : reponse oubliee", debut);
    xSemaphoreGive(s_verrou);
    return;
  }
  P.id_max = id;
  // Nouvelle commande admise, permise ou refusee ensuite : la session sert de nouveau,
  // meme apres json 0 (qui, s'il est cette commande, la termine ensuite a son tour).
  // Jamais pour un renvoi, ni pour une ligne sans id.
  net_udp_reprendre(slot, gen);
  uint32_t *place = &P.en_attente[0];  // la plus ancienne attente cede la place
  for (uint32_t &a : P.en_attente)
    if (!a || a < *place) place = &a;
  *place = id;
  const char *refus = nullptr, *code = nullptr;
  if (n > kCmdMax) {
    refus = "ligne de plus de 127 octets : rien n'est execute";
    code = "trop_long";
  } else if (!P.cadence.allow(debut)) {
    refus = "plus de 20 lignes par seconde : rien n'est execute";
    code = "cadence";
  } else if ((refus = refusDistant(argc, argv)) != nullptr) {
    code = "interdite";
  }
  if (refus) {
    s_rejets++;
    repondre(o, id, vue, false, code, refus, debut);
    xSemaphoreGive(s_verrou);
    return;
  }
  if (!strcmp(argv[0], "json")) {
    commande_json(o, id, vue, argc, argv, debut);
    P.derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  if (ordre_asynchrone(o, id, vue, argc, argv, debut)) {
    xSemaphoreGive(s_verrou);
    return;
  }
  // Commande a texte permise (lectures, masquer, led) : la tache distant l'execute.
  travail_t w = {};
  w.origine = (uint8_t)o;
  w.generation = P.generation;
  w.id = id;
  w.debut_ms = debut;
  snprintf(w.cmd, sizeof(w.cmd), "%s", cmd);
  memcpy(w.vue, vue, sizeof(w.vue));
  if (xQueueSend(s_travaux, &w, 0) != pdTRUE) repondre(o, id, vue, false, "erreur", "commande deja en cours", debut);
  xSemaphoreGive(s_verrou);
}

// Sortie standard de la tache distant pendant esp_console_run, gardee ici ligne par
// ligne (OutputLines, json_ligne.h : 4 096 octets, lignes coupees a kLogTextMax). Le
// crochet ne prend aucun verrou et n'attend jamais : la commande tient peut-etre un
// verrou (celui des lampes dans mesh lampe <n> masquer, celui de la pile Matter), et
// son journal (ESP_LOG, par vprintf) passe par cette sortie ; or la tache json prend
// le verrou des lampes en tenant s_verrou. Les lignes partent apres la commande,
// sortie rendue ; au-dela de 4 096 octets, une derniere ligne dit que la suite manque.
// Tache distant seulement.
static OutputLines s_sortie;

static ssize_t sortie_ecrire(void *cookie, const char *buf, size_t n) {
  ((OutputLines *)cookie)->write(buf, n);
  return (ssize_t)n;
}

// La tache distant attend une place dans la file d'emission de net_udp (1 s au plus)
// avant chacune de ses lignes : la sortie d'une commande va plus vite que le debit de
// Thread. Jamais sous s_verrou.
static void attendre_place(void) {
  for (int k = 0; k < 100 && net_udp_libres() < kPlacesLigne; k++) vTaskDelay(pdMS_TO_TICKS(10));
}

// Une ligne texte du travail w : sa place d'abord, puis formee et envoyee sous
// s_verrou si la session est encore la sienne. false : session partie.
static bool texte_distant(const travail_t &w, const char *txt) {
  attendre_place();
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  puits_t &P = s_puits[w.origine];
  const bool vivante = P.generation == w.generation;
  if (vivante) {
    textLine(s_w, P.n, maintenant_ms(), w.id, txt);
    envoyer(w.origine);
  }
  xSemaphoreGive(s_verrou);
  return vivante;
}

// Les commandes a texte venues de Thread, une a la fois avec la console : reponse
// debut, la commande (sa sortie gardee dans s_sortie), une ligne texte par ligne
// gardee, puis reponse fin. La sortie standard n'est changee que pendant
// esp_console_run, hors de s_verrou ; sous s_verrou, rien ne s'imprime ni ne se
// journalise (net_udp_envoyer ne poste rien a OpenThread).
static void tache_distant(void *arg) {
  (void)arg;
  static travail_t w;
  for (;;) {
    if (xQueueReceive(s_travaux, &w, portMAX_DELAY) != pdTRUE) continue;
    const int o = w.origine;
    xSemaphoreTake(s_commande, portMAX_DELAY);
    attendre_place();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    puits_t &P = s_puits[o];
    bool vivante = P.generation == w.generation;
    if (vivante) {
      P.en_commande = true;
      P.cmd_id = w.id;
      Reply r;
      r.id = w.id;
      r.fin = false;
      r.cmd = w.vue;
      r.code = "en_cours";
      reponse(o, r);
    }
    xSemaphoreGive(s_verrou);
    int ret = 0;
    esp_err_t err = ESP_FAIL;
    s_sortie.clear();
    if (vivante) {
      // La sortie standard est propre a chaque tache (ESP-IDF) : seule celle-ci change.
      cookie_io_functions_t f = {};
      f.write = sortie_ecrire;
      FILE *flux = fopencookie(&s_sortie, "w", f);
      FILE *ancien = stdout;
      if (flux) {
        setvbuf(flux, NULL, _IOLBF, 128);
        stdout = flux;
      }
      err = esp_console_run(w.cmd, &ret);
      if (flux) {
        fflush(flux);
        stdout = ancien;
        fclose(flux);
      }
      s_sortie.flush();
    }
    xSemaphoreGive(s_commande);
    // Le texte, la commande sortie de ses verrous ; plus rien vers une session partie.
    size_t pos = 0;
    for (const char *l = s_sortie.next(&pos); vivante && l; l = s_sortie.next(&pos)) vivante = texte_distant(w, l);
    if (vivante && s_sortie.lost()) vivante = texte_distant(w, "(sortie tronquee)");
    if (vivante) attendre_place();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    if (vivante && P.generation == w.generation) {
      P.derniere_cmd = maintenant_ms();
      P.en_commande = false;
      P.cmd_id = 0;
      const bool inconnue = err != ESP_OK;
      const bool ok = !inconnue && ret == 0;
      repondre(o, w.id, w.vue, ok, inconnue ? "inconnue" : ok ? "ok" : "erreur", nullptr, w.debut_ms);
    }
    xSemaphoreGive(s_verrou);
  }
}

bool json_pont_tache_distante(void) { return s_tache_distant && xTaskGetCurrentTaskHandle() == s_tache_distant; }

// --- Evenements, depuis les autres taches

static void poster(const evenement_t &e) {
  if (!s_evenements) return;
  bool session = false;
  for (const puits_t &p : s_puits) session = session || p.machine;
  if (session && xQueueSend(s_evenements, &e, 0) != pdTRUE) __atomic_fetch_add(&s_evenements_perdus, 1, __ATOMIC_RELAXED);
}

void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     const uint8_t *origines, uint8_t n_ids, uint32_t ids_perdus) {
  evenement_t e = {};
  e.type = EV_ORDRE;
  e.lampe = (int8_t)lampe;
  e.a = (uint8_t)signal;
  e.b = essai;
  e.delai_ms = delai_ms;
  e.n_ids = n_ids > kIdsMax ? kIdsMax : n_ids;
  for (uint8_t i = 0; i < e.n_ids; i++) {
    e.ids[i] = ids[i];
    e.origines[i] = origines[i];
  }
  e.ids_perdus = ids_perdus;
  poster(e);
}

void json_pont_alerte_releves(int lampe, bool manque, uint8_t pour_cent) {
  evenement_t e = {};
  e.type = EV_RELEVES;
  e.lampe = (int8_t)lampe;
  e.a = manque;
  e.b = pour_cent;
  poster(e);
}

void json_pont_alerte_mesh(diagnostic_t etat) {
  evenement_t e = {};
  e.type = EV_MESH;
  e.a = (uint8_t)etat;
  poster(e);
}

void json_pont_lampe(int lampe, json_lampe_t quoi, uint16_t endpoint) {
  evenement_t e = {};
  e.type = EV_LAMPE;
  e.lampe = (int8_t)lampe;
  e.a = (uint8_t)quoi;
  e.endpoint = endpoint;
  poster(e);
}

void json_pont_led(const char *motif, const char *avant, bool test, uint32_t depuis_ms) {
  evenement_t e = {};
  e.type = EV_LED;
  e.motif = motif;
  e.avant = avant;
  e.a = test;
  e.delai_ms = depuis_ms;
  poster(e);
}

bool json_pont_trames_actives(void) { return s_trames_actives; }

void json_pont_trame(bool rx, const char *quoi, int lampe, int8_t marche, int32_t intensite, uint8_t essai) {
  if (!s_trames_actives) return;
  evenement_t e = {};
  e.type = EV_TRAME;
  e.lampe = (int8_t)lampe;
  e.a = rx;
  e.b = essai;
  e.motif = quoi;
  e.marche = marche;
  e.intensite = intensite;
  poster(e);
}

void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) {
  char txt[192];
  va_list ap;
  va_start(ap, format);
  vsnprintf(txt, sizeof(txt), format, ap);
  va_end(ap);
  // En message log pour chaque session qui l'a demande ; en texte sur l'USB tant que
  // l'USB n'est pas lui-meme en mode machine avec json log 1.
  const bool usb_log = s_puits[USB].machine && s_puits[USB].log;
  if (s_log_actif && s_journal) {
    journal_t j;
    j.src = src;
    j.alerte = alerte;
    const size_t n = strnlen(txt, sizeof(j.txt) - 1);  // log.txt : 127 octets au plus (7.5)
    memcpy(j.txt, txt, n);
    j.txt[n] = 0;
    if (xQueueSend(s_journal, &j, 0) != pdTRUE) __atomic_fetch_add(&s_evenements_perdus, 1, __ATOMIC_RELAXED);
  }
  if (!usb_log) printf("%s\n", txt);
}

esp_err_t json_pont_demarrer(const amaran_config_t *cfg) {
  s_cfg = cfg;
  // Aucune radio n'est encore active : le generateur tire de vrai bruit (comme Halo).
  bootloader_random_enable();
  s_boot = esp_random();
  bootloader_random_disable();
  s_verrou = xSemaphoreCreateMutex();
  s_commande = xSemaphoreCreateMutex();
  s_evenements = xQueueCreate(FILE_EVENEMENTS, sizeof(evenement_t));
  s_journal = xQueueCreate(FILE_JOURNAL, sizeof(journal_t));
  s_travaux = xQueueCreate(FILE_TRAVAUX, sizeof(travail_t));
  if (!s_verrou || !s_commande || !s_evenements || !s_journal || !s_travaux) return ESP_ERR_NO_MEM;
  for (int o = 0; o < ORIGINES; o++) {
    s_puits[o].reglages = o == USB ? Session() : sessionDistante();
    if (o != USB) {
      s_puits[o].plafond_journal = RateCap(PLAFOND_DISTANT);
      s_puits[o].plafond_trames = RateCap(PLAFOND_DISTANT);
    }
  }
  // Basse priorite : les lampes, Matter et la console passent avant.
  if (xTaskCreate(tache_json, "json", 4096, NULL, 1, NULL) != pdPASS) return ESP_ERR_NO_MEM;
  return xTaskCreate(tache_distant, "distant", 6144, NULL, 1, &s_tache_distant) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
````

- [ ] **Step 5 : la tâche des lampes : origine des `id`, trames.**

`firmware/main/tache_lampes.h`, bloc 1 sur 1. Remplacer :

````c
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Ordre de l'app (mode JSON) : son id reviendra dans l'evenement ordre qui le finira.
// Rend false si l'ordre n'a pas pu entrer dans la file (pleine, ou lampe inconnue).
bool tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
````

par :

````c
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Ordre de l'app (mode JSON) : son id reviendra dans l'evenement ordre qui le finira,
// avec l'octet origine tel quel. json_pont y met la session qui l'a donne : son
// origine (2 bits bas : JSON_PONT_USB, ou session distante) et 6 bits de sa
// generation, pour qu'une session qui a pris la place d'une autre ne recoive pas ses
// id. Rend false si l'ordre n'a pas pu entrer dans la file (pleine, ou lampe inconnue).
bool tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id, uint8_t origine);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
````

`firmware/main/tache_lampes.c`, bloc 1 sur 8. Remplacer :

````c
  uint32_t releve_ms;
  uint32_t id;  // ordre de l'app (mode JSON) ; 0 : aucun
} message_t;

````

par :

````c
  uint32_t releve_ms;
  uint32_t id;  // ordre de l'app (mode JSON) ; 0 : aucun
  uint8_t origine;  // session de l'app qui l'a donne, marquee par json_pont (tache_lampes.h)
} message_t;

````

`firmware/main/tache_lampes.c`, bloc 2 sur 8. Remplacer :

````c
// porte (un ordre arrive pendant un autre se fond dans le sien). Tache lampes.
static uint32_t s_ids[LAMPES_CAPACITE][JSON_PONT_IDS_MAX];
static uint8_t s_nb_ids[LAMPES_CAPACITE];
static uint32_t s_ids_perdus[LAMPES_CAPACITE];
````

par :

````c
// porte (un ordre arrive pendant un autre se fond dans le sien). Tache lampes.
static uint32_t s_ids[LAMPES_CAPACITE][JSON_PONT_IDS_MAX];
static uint8_t s_origines[LAMPES_CAPACITE][JSON_PONT_IDS_MAX];  // octet origine de chaque id, tel quel
static uint8_t s_nb_ids[LAMPES_CAPACITE];
static uint32_t s_ids_perdus[LAMPES_CAPACITE];
````

`firmware/main/tache_lampes.c`, bloc 3 sur 8. Remplacer :

````c
static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static bool sortie_envoyer(void *ctx, uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions) {
  (void)ctx;
  return mesh_envoyer(dst, trame, repetitions) == ESP_OK;
}
````

par :

````c
static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

// Index de la lampe a cette adresse ; -1 : aucune (le groupe). Sous s_verrou.
static int lampe_a(uint16_t adresse) {
  for (int i = 0; i < s_lampes.n; i++)
    if (s_lampes.lampes[i].adresse == adresse) return i;
  return -1;
}

// Trafic Bluetooth Mesh decode, pour json trames 1 (7.6). Sous s_verrou.
static void montrer_emise(uint16_t dst, const uint8_t t[TELINK_TAILLE]) {
  if (!json_pont_trames_actives()) return;
  const int i = lampe_a(dst);
  const uint8_t essai = i >= 0 ? s_lampes.lampes[i].essai : 0;
  switch (t[9]) {
    case TELINK_CMD_ETAT:
      json_pont_trame(false, "demande", i, -1, -1, 0);
      break;
    case TELINK_CMD_MARCHE:
      json_pont_trame(false, "ordre", i, (int8_t)(t[8] & 0x01), -1, essai);
      break;
    case TELINK_CMD_INTENSITE:
      json_pont_trame(false, "ordre", i, -1, (int32_t)((((unsigned)t[8] << 2) | (t[7] >> 6)) & 0x3FF), essai);
      break;
    default:
      break;
  }
}

static void montrer_recue(uint16_t src, const uint8_t t[TELINK_TAILLE]) {
  if (!json_pont_trames_actives()) return;
  telink_etat_t e;
  if (!telink_lire_etat(t, &e)) return;
  json_pont_trame(true, "etat", lampe_a(src), e.marche, e.intensite, 0);
}

static bool sortie_envoyer(void *ctx, uint16_t dst, const uint8_t trame[TELINK_TAILLE], uint8_t repetitions) {
  (void)ctx;
  montrer_emise(dst, trame);
  return mesh_envoyer(dst, trame, repetitions) == ESP_OK;
}
````

`firmware/main/tache_lampes.c`, bloc 4 sur 8. Remplacer :

````c
  const lampe_t *p = &s_lampes.lampes[lampe];
  json_pont_ordre(lampe, signal, p->dernier_delai_ms, signal == LAMPES_SIGNAL_TENU ? 0 : p->essai, s_ids[lampe],
                  s_nb_ids[lampe], s_ids_perdus[lampe]);
  s_nb_ids[lampe] = 0;
  s_ids_perdus[lampe] = 0;
````

par :

````c
  const lampe_t *p = &s_lampes.lampes[lampe];
  json_pont_ordre(lampe, signal, p->dernier_delai_ms, signal == LAMPES_SIGNAL_TENU ? 0 : p->essai, s_ids[lampe],
                  s_origines[lampe], s_nb_ids[lampe], s_ids_perdus[lampe]);
  s_nb_ids[lampe] = 0;
  s_ids_perdus[lampe] = 0;
````

`firmware/main/tache_lampes.c`, bloc 5 sur 8. Remplacer :

````c
    if (s_nb_ids[i] == JSON_PONT_IDS_MAX) {  // le plus ancien sort
      memmove(s_ids[i], s_ids[i] + 1, (JSON_PONT_IDS_MAX - 1) * sizeof(s_ids[i][0]));
      s_nb_ids[i]--;
      s_ids_perdus[i]++;
    }
    s_ids[i][s_nb_ids[i]++] = m->id;
  }
````

par :

````c
    if (s_nb_ids[i] == JSON_PONT_IDS_MAX) {  // le plus ancien sort
      memmove(s_ids[i], s_ids[i] + 1, (JSON_PONT_IDS_MAX - 1) * sizeof(s_ids[i][0]));
      memmove(s_origines[i], s_origines[i] + 1, (JSON_PONT_IDS_MAX - 1) * sizeof(s_origines[i][0]));
      s_nb_ids[i]--;
      s_ids_perdus[i]++;
    }
    s_origines[i][s_nb_ids[i]] = m->origine;
    s_ids[i][s_nb_ids[i]++] = m->id;
  }
````

`firmware/main/tache_lampes.c`, bloc 6 sur 8. Remplacer :

````c
      if (ev.type == MESH_EV_ETAT_LAMPE) {
        xSemaphoreTake(s_verrou, portMAX_DELAY);
        lampes_trame_recue(&s_lampes, ev.src, ev.acces + 1, maintenant_ms());
        xSemaphoreGive(s_verrou);
````

par :

````c
      if (ev.type == MESH_EV_ETAT_LAMPE) {
        xSemaphoreTake(s_verrou, portMAX_DELAY);
        montrer_recue(ev.src, ev.acces + 1);
        lampes_trame_recue(&s_lampes, ev.src, ev.acces + 1, maintenant_ms());
        xSemaphoreGive(s_verrou);
````

`firmware/main/tache_lampes.c`, bloc 7 sur 8. Remplacer :

````c
}

static bool envoyer_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter, uint32_t id) {
  if (!s_file || lampe < 0 || lampe >= LAMPES_CAPACITE) return false;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter, .id = id};
  if (marche) {
    m.a_marche = true;
````

par :

````c
}

static bool envoyer_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter, uint32_t id,
                          uint8_t origine) {
  if (!s_file || lampe < 0 || lampe >= LAMPES_CAPACITE) return false;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter, .id = id, .origine = origine};
  if (marche) {
    m.a_marche = true;
````

`firmware/main/tache_lampes.c`, bloc 8 sur 8. Remplacer :

````c

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  envoyer_ordre(lampe, marche, intensite, depuis_matter, 0);
}

bool tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id) {
  return envoyer_ordre(lampe, marche, intensite, false, id);
}

````

par :

````c

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  envoyer_ordre(lampe, marche, intensite, depuis_matter, 0, JSON_PONT_USB);
}

bool tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id, uint8_t origine) {
  return envoyer_ordre(lampe, marche, intensite, false, id, origine);
}

````

- [ ] **Step 6 : le démarrage, le retrait de Maison, la console.**

`firmware/main/app_main.cpp`, bloc 1 sur 2. Remplacer :

````cpp
#include "json_pont.h"
#include "mesh_amaran.h"
#include "pont_matter.h"
#include "socle.h"
````

par :

````cpp
#include "json_pont.h"
#include "mesh_amaran.h"
#include "net_udp.h"
#include "pont_matter.h"
#include "socle.h"
````

`firmware/main/app_main.cpp`, bloc 2 sur 2. Remplacer :

````cpp
    return;
  }
  if (!cfg.cles_presentes) {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
````

par :

````cpp
    return;
  }
  if (net_udp_demarrer() != ESP_OK) ESP_LOGE(TAG, "socket UDP non ouverte");
  if (!cfg.cles_presentes) {
    ESP_LOGW(TAG, "cles absentes : lancer outils/cles_amaran.py");
````

`firmware/main/console_pont.c`, bloc 1 sur 3. Remplacer :

````c
  (void)argc;
  (void)argv;
  pont_afficher();
  return 0;
}
````

par :

````c
  (void)argc;
  (void)argv;
  pont_afficher(json_pont_tache_distante());  // par Thread : sans les codes d'appairage
  return 0;
}
````

`firmware/main/console_pont.c`, bloc 2 sur 3. Remplacer :

````c
    return 1;
  }
  printf("Retrait de toutes les fabriques Matter, puis redemarrage (cles et lampes gardees)...\n");
  pont_desappairer();
  return 0;
````

par :

````c
    return 1;
  }
  printf("Retrait de toutes les fabriques Matter et de la cle UDP, puis redemarrage (cles Mesh et lampes gardees)...\n");
  pont_desappairer();
  return 0;
````

`firmware/main/console_pont.c`, bloc 3 sur 3. Remplacer :

````c

const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES] = {
    "lampes", "socle", "json", "console", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP", "ot_task"};

static void tache_console(void *arg) {
````

par :

````c

const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES] = {
    "lampes", "socle", "json", "console", "udp", "distant", "amaran_tx", "nimble_host", "mesh_adv_task", "CHIP", "ot_task"};

static void tache_console(void *arg) {
````

`firmware/main/console_pont.h`, bloc 1 sur 1. Remplacer :

````c

// Taches dont `taches` et le bloc sante du protocole JSON donnent la marge de pile.
#define CONSOLE_PONT_NB_TACHES 9
extern const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES];

````

par :

````c

// Taches dont `taches` et le bloc sante du protocole JSON donnent la marge de pile.
#define CONSOLE_PONT_NB_TACHES 11
extern const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES];

````

`firmware/main/pont_matter.cpp`, bloc 1 sur 5. Remplacer :

````cpp
// part).
#include "pont_matter.h"

#include <inttypes.h>
````

par :

````cpp
// part).
#include "pont_matter.h"
#include "net_udp.h"

#include <inttypes.h>
````

`firmware/main/pont_matter.cpp`, bloc 2 sur 5. Remplacer :

````cpp

void pont_desappairer(void) {
  if (!esp_matter::is_started()) {
    printf("Matter non demarre : rien a desappairer\n");
````

par :

````cpp

void pont_desappairer(void) {
  // L'acces par Thread ne survit pas au retrait : la cle UDP part avec les fabriques.
  // La NVS s'efface meme si l'acces par Thread n'a pas demarre (net_udp_cle_effacer).
  const esp_err_t err = net_udp_cle_effacer();
  if (err != ESP_OK) {
    printf("erreur : cle UDP pas effacee de la NVS (%s) : elle reviendra au redemarrage\n", esp_err_to_name(err));
  }
  if (!esp_matter::is_started()) {
    printf("Matter non demarre : rien a desappairer\n");
````

`firmware/main/pont_matter.cpp`, bloc 3 sur 5. Remplacer :

````cpp
}

void pont_afficher(void) {
  if (!esp_matter::is_started()) {  // sans la pile, ses fournisseurs n'existent pas (VerifyOrDie)
    printf("Matter non demarre (voir le journal de demarrage)\n");
````

par :

````cpp
}

void pont_afficher(bool distant) {
  if (!esp_matter::is_started()) {  // sans la pile, ses fournisseurs n'existent pas (VerifyOrDie)
    printf("Matter non demarre (voir le journal de demarrage)\n");
````

`firmware/main/pont_matter.cpp`, bloc 4 sur 5. Remplacer :

````cpp
    if (!infos || infos->GetProductName(produit, sizeof(produit)) != CHIP_NO_ERROR) snprintf(produit, sizeof(produit), "?");
    if (!infos || infos->GetSerialNumber(serie, sizeof(serie)) != CHIP_NO_ERROR) snprintf(serie, sizeof(serie), "?");
    if (fabriques == 0) {
      // Codes d'appairage montres seulement avant la mise en service (lecon du Halo).
      chip::MutableCharSpan qr_span(qr), manuel_span(manuel);
      const chip::RendezvousInformationFlags ble(chip::RendezvousInformationFlag::kBLE);
````

par :

````cpp
    if (!infos || infos->GetProductName(produit, sizeof(produit)) != CHIP_NO_ERROR) snprintf(produit, sizeof(produit), "?");
    if (!infos || infos->GetSerialNumber(serie, sizeof(serie)) != CHIP_NO_ERROR) snprintf(serie, sizeof(serie), "?");
    if (fabriques == 0 && !distant) {
      // Codes d'appairage montres seulement avant la mise en service (lecon du Halo),
      // et jamais par Thread.
      chip::MutableCharSpan qr_span(qr), manuel_span(manuel);
      const chip::RendezvousInformationFlags ble(chip::RendezvousInformationFlag::kBLE);
````

`firmware/main/pont_matter.cpp`, bloc 5 sur 5. Remplacer :

````cpp
    printf("  code manuel     : %s\n", manuel);
    printf("  QR code         : %s\n", qr);
  }
  printf("  identite        : %s, %s, n/s %s\n", fabricant, produit, serie);
````

par :

````cpp
    printf("  code manuel     : %s\n", manuel);
    printf("  QR code         : %s\n", qr);
  } else if (fabriques == 0 && distant) {
    printf("  codes           : par l'USB seulement\n");
  }
  printf("  identite        : %s, %s, n/s %s\n", fabricant, produit, serie);
````

`firmware/main/pont_matter.h`, bloc 1 sur 1. Remplacer :

````c
bool pont_thread_attache(void);
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
void pont_afficher(void);
// Releve pour le protocole JSON, depuis n'importe quelle tache, sans verrou.
void pont_lire(pont_infos_t *infos);
````

par :

````c
bool pont_thread_attache(void);
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
// distant : la sortie part par Thread (json_pont_tache_distante) ; jamais les codes
// d'appairage (docs/PROTOCOLE-JSON.md, 10.1).
void pont_afficher(bool distant);
// Releve pour le protocole JSON, depuis n'importe quelle tache, sans verrou.
void pont_lire(pont_infos_t *infos);
````

- [ ] **Step 7 : le bloc `ip` dans la file des lignes, les 11 tâches suivies (protocole et tests).**

`components/protocole/include/json_ligne.h`, bloc 1 sur 2. Remplacer :

````c
enum class Item : uint8_t {
  HelloBase, HelloId, ConfigCatalogue, ConfigMesh, ConfigLampe, EtatPont, EtatLampe, EtatSante, CptMesh,
  NetMatter, NetThread, Heartbeat, Reply
};
struct Queued {
````

par :

````c
enum class Item : uint8_t {
  HelloBase, HelloId, ConfigCatalogue, ConfigMesh, ConfigLampe, EtatPont, EtatLampe, EtatSante, CptMesh,
  NetMatter, NetThread, NetIp, Heartbeat, Reply
};
struct Queued {
````

`components/protocole/include/json_ligne.h`, bloc 2 sur 2. Remplacer :

````c
class Queue {
 public:
  static constexpr uint8_t kN = 48;  // un instantane complet a 16 lampes : 42 lignes
  // Ajoute en queue. Un element deja en file (meme item et meme arg, hors
  // Reply) n'est pas double ; une demande explicite (session faux) fondue
````

par :

````c
class Queue {
 public:
  static constexpr uint8_t kN = 48;  // un instantane complet a 16 lampes : 43 lignes
  // Ajoute en queue. Un element deja en file (meme item et meme arg, hors
  // Reply) n'est pas double ; une demande explicite (session faux) fondue
````

`tests/hote/test_json.cpp`, bloc 1 sur 3. Remplacer :

````cpp
  for (uint8_t i = 0; i < LISTE_CAPACITE; i++) n += q.push(Item::EtatLampe, 0, true, i);
  n += q.push(Item::EtatSante, 0, true) + q.push(Item::CptMesh, 0, true) + q.push(Item::NetMatter, 0, true) +
       q.push(Item::NetThread, 0, true) + q.push(Item::Reply, 0, false, 0);
  CHECK(n == 42 && q.size() == 42, "instantane a 16 lampes : %d lignes en file", n);
}

````

par :

````cpp
  for (uint8_t i = 0; i < LISTE_CAPACITE; i++) n += q.push(Item::EtatLampe, 0, true, i);
  n += q.push(Item::EtatSante, 0, true) + q.push(Item::CptMesh, 0, true) + q.push(Item::NetMatter, 0, true) +
       q.push(Item::NetThread, 0, true) + q.push(Item::NetIp, 0, true) + q.push(Item::Reply, 0, false, 0);
  CHECK(n == 43 && q.size() == 43, "instantane a 16 lampes : %d lignes en file", n);
}

````

`tests/hote/test_json.cpp`, bloc 2 sur 3. Remplacer :

````cpp
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat pont : %zu octets", s.size());
  Pile piles[9];
  const char *noms[9] = {"lampes", "json", "console", "socle", "CHIP", "ot_task", "nimble_host", "mesh_adv_task",
                         "amaran_tx"};
  for (int i = 0; i < 9; i++) piles[i] = Pile{noms[i], 2147483647};
  EtatSante e;
  e.boot = e.upS = e.depuisMs = e.heap = e.heapMin = e.heapBloc = e.perdus = e.tropLongs = e.rejets = M;
````

par :

````cpp
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat pont : %zu octets", s.size());
  Pile piles[11];
  const char *noms[11] = {"lampes", "json", "console", "socle", "udp", "distant", "CHIP", "ot_task", "nimble_host",
                          "mesh_adv_task", "amaran_tx"};
  for (int i = 0; i < 11; i++) piles[i] = Pile{noms[i], 2147483647};
  EtatSante e;
  e.boot = e.upS = e.depuisMs = e.heap = e.heapMin = e.heapBloc = e.perdus = e.tropLongs = e.rejets = M;
````

`tests/hote/test_json.cpp`, bloc 3 sur 3. Remplacer :

````cpp
  e.motif = "identification";
  e.piles = piles;
  e.nPiles = 9;
  etatSante(gW, M, M, e);
  s = finish(gW, &ok);
````

par :

````cpp
  e.motif = "identification";
  e.piles = piles;
  e.nPiles = 11;
  etatSante(gW, M, M, e);
  s = finish(gW, &ok);
````

- [ ] **Step 8 : lancer les tests, tout est vert.**

Run: `sh tests/hote/lancer.sh`
Expected: `json : 465 verifications, 0 echecs`, `h1 : 121 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 9 : les deux firmwares compilent.** `net_udp.cpp` est neuf : `reconfigure` d'abord pour le pont.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader") && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py reconfigure >/dev/null && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader")`
Expected : `amaran_ecoute.bin binary size 0xc0f60 bytes…`, puis `amaran_pont.bin binary size 0x1b0380 bytes. Smallest app partition is 0x3e0000 bytes. 0x22fc80 bytes (56%) free.` (à quelques octets près) ; deux `Project build complete. To flash, run:` ; aucune ligne `warning:` ni `error:`.

- [ ] **Step 10 : commit.**

```bash
git add firmware/main components/protocole/include/json_ligne.h tests/hote/test_json.cpp
git commit -m "$(printf "Pont par Thread : socket UDP sur OpenThread, une session par origine, tache distant, trames, cle UDP\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 4: Banc A : le pont par l'USB, la clé UDP, les trames, le secteur (Claude et Djoko)

**Files:**
- Modify: `docs/BANC.md` (une section « Plan 3b-2 : banc A », écrite après le banc)

Cette tâche est faite par Claude, avec Djoko : flasher, ouvrir le port, émettre vers les lampes. Aucun sous-agent.

**Interfaces:**
- Consumes : le firmware de la Task 3 ; `outils/console.py` (il envoie chaque étape suivie de CR LF, et journalise tout dans `logs/`, ignoré par git).
- Produces : les faits du banc dans `docs/BANC.md` ; un ruling dans le registre si un point échoue.

Pourquoi : avant de bâtir l'app sur ce firmware, vérifier sur la carte ce qui ne passe pas par Thread : la console et le mode machine n'ont pas régressé, la clé UDP se crée et s'efface par l'USB sans jamais s'afficher, les trames décodées sont justes, le pont démarre sur un chargeur, les nouvelles tâches ont leur marge. Le canal H1 lui-même se vérifie avec l'app, au banc B (Task 11).

- [ ] **Step 1 : flasher, avec l'accord de Djoko.** Le port du pont se reconnaît à son `SER=` ; le donner explicitement. Mise à jour sans `erase-flash` (Maison garde tout).

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py -p <port du pont> flash
```

- [ ] **Step 2 : la console texte.**

Run: `python3 outils/console.py --port <port> "help" "taches" "json" "matter"`
Expected : `help` liste `json` ; `taches` cite `udp` et `distant` avec leur marge de pile ; `json` décrit le mode texte ; `matter` montre la mise en service faite et Thread attaché.

- [ ] **Step 3 : le mode machine, révision 1.**

Run: `python3 outils/console.py --port <port> "id=1 json 1" "@4" "id=2 json 0"`
Expected, dans le journal : `hello` `base` avec `"rev":1` et `session` (`"transport":"usb"`, `"trames":false`) ; `hello` `identite` dont les `caps` contiennent `trames`, `udp`, `cle`, `texte` ; un bloc `reseau` `ip` : `srp` (16 hexa), des `adresses` (`omr`, `ml_eid`), `udp` avec `"port":5480` et l'état de la clé ; `reponse` `id` 1 `ok`. Rien de ce journal ne part dans le dépôt (adresses et nom du réseau de Djoko).

- [ ] **Step 4 : la clé UDP par l'USB, sans l'afficher.** L'aléa n'est pas la clé : la clé est un HMAC de cet aléa par un aléa du pont, qui ne quitte pas la carte. En mode texte, le pont ne montre que l'empreinte.

Run: `python3 outils/console.py --port <port> "json cle nouvelle $(python3 -c 'import secrets; print(secrets.token_hex(32))')" "id=1 json 1" "@4" "id=2 json 0" "json cle efface" "id=3 json 1" "@4" "id=4 json 0"`
Expected : `ok cle UDP <8 hexa>, port 5480 ouvert` ; le bloc `ip` suivant porte `"cle":true`, la même empreinte, `"ouvert":true` ; puis `ok cle UDP effacee, port 5480 ferme` ; le dernier bloc `ip` porte `"cle":false` et `"ouvert":false`. Aucune suite de 64 chiffres hexa du journal n'est autre que l'aléa envoyé (la console texte renvoie la commande en écho : l'aléa peut y figurer deux fois, la clé jamais) :

```bash
/usr/bin/grep -oE "[0-9A-Fa-f]{64}" logs/<journal> | sort -u | wc -l
```

(1 attendu : l'aléa. Relevé au banc A : 0, l'écho de la console masque aussi l'aléa ; une suite trouvée est à examiner.)

Puis, en mode texte, `id=9 json cle nouvelle <64 hexa>` : refusée (`usage`, « en mode machine seulement ») avant toute création, la commande citée masquée : sans le mode machine, la réponse s'écrirait en texte, clé comprise (correction faite à la relecture de la Task 3, `c5128fa`).

- [ ] **Step 5 : les trames (Djoko présent, lampe 1).**

Run: `python3 outils/console.py --port <port> "id=1 json 1" "@3" "id=2 json trames 1" "@1" "id=3 lampe 1 on" "@4" "id=4 lampe 1 off" "@4" "id=5 json trames 0" "@1" "id=6 json 0"`
Expected : après `id=3`, `trame` `tx` `ordre` (`lampe` 1, `marche` true, `essai` 1), `tx` `demande` (`lampe` 1), puis `rx` `etat` (`lampe` 1, `marche` true, son intensité) et l'`ordre` `confirme` `ids` [3] ; de même pour `id=4` ; entre les ordres, les relectures : `tx` `demande` au groupe (`lampe` null) et un `rx` `etat` par lampe. Après `id=5`, plus aucune `trame`. Djoko voit la lampe s'allumer puis s'éteindre, et Maison suivre. Si la lampe est déjà allumée, `on` est « tenu » (`ids` [3], rien n'est émis) : seul `off` montre les trames de l'ordre (vu au banc A).

- [ ] **Step 6 : le secteur.** Djoko branche le pont sur un chargeur USB (pas sur le Mac). Expected : au bout d'une minute au plus, le voyant est éteint avec une brève lueur blanche toutes les 10 s, et une lampe répond à Maison. Puis, de retour sur le Mac : `"cause" "matter"` : mise en service faite ; la cause est « réinitialisation par l'USB » quand l'ouverture du port par `outils/console.py` redémarre la carte (vu au banc A), sinon `mise sous tension`.

- [ ] **Step 7 : les marges.** En texte, `taches`. Expected : au moins 1 Ko de pile libre pour `udp`, `distant`, `json` et `console` ; tas au plus bas proche du plan 3b-1.

- [ ] **Step 8 : consigner.** Ajouter à `docs/BANC.md` une section `## Plan 3b-2 : banc A, le pont par l'USB (<date>)` : les étapes 2 à 7, ce qui a été vu, les marges relevées, et tout écart, sans adresse ni nom SRP du réseau de Djoko, sans empreinte réelle. Puis commit :

```bash
git add docs/BANC.md
git commit -m "$(printf "Banc A du plan 3b-2 : le pont par l'USB, la cle UDP, les trames, le secteur\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

Si un point échoue : le noter, ruling dans le registre, correction avant la Task 5.

### Task 5: Les messages à distance, la liste blanche, le masque des clés, la session par le réseau, l'enveloppe H1 et la création de la clé (Swift, testé sur le Mac)

**Files:**
- Create: `apps/macos/AmaranProtocole/Reseau/EnveloppeH1.swift`, `apps/macos/AmaranProtocole/Reseau/CleReseau.swift`
- Modify: `apps/macos/AmaranProtocole/Commandes/Commandes.swift`, `apps/macos/AmaranProtocole/Messages/Enumerations.swift`, `apps/macos/AmaranProtocole/Messages/Session.swift`, `apps/macos/AmaranProtocole/Messages/Etat.swift`, `apps/macos/AmaranProtocole/Messages/Evenements.swift`, `apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, `apps/macos/AmaranProtocole/Etat/EtatPont.swift`, `apps/macos/AmaranProtocole/Interpretation/Interpretation.swift`, `apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, `apps/macos/AmaranProtocole/Session/MoteurSession.swift`
- Create: `apps/macos/AmaranProtocoleTests/CleReseauTests.swift`, `apps/macos/AmaranProtocoleTests/EnveloppeH1Tests.swift`, `apps/macos/AmaranProtocoleTests/ListeBlancheTests.swift`, `apps/macos/AmaranProtocoleTests/MasquageCleTests.swift`, `apps/macos/AmaranProtocoleTests/ReseauSessionTests.swift`
- Modify: `apps/macos/AmaranProtocoleTests/ClesTests.swift`, `apps/macos/AmaranProtocoleTests/CouvertureClesTests.swift`, `apps/macos/AmaranProtocoleTests/ExemplesSpecTests.swift`

**Interfaces:**
- Consumes : `AmaranProtocole` du plan 3b-1 (`Reponse`, `Correlateur`, `MoteurSession`, `LigneCommande`, `PolitiqueCommandes`, `MessageCarte`, `EtatPont`) ; `docs/PROTOCOLE-JSON.md` à jour (Task 2) : les tests de l'app relisent chacun de ses exemples.
- Produces (les Tasks 6 à 9 s'en servent telles quelles) :
  - `GenreTransport.udp` ;
  - messages : `TexteCommande` (`texte`), `Trame` (`trame` : `SensTrame`, `QuoiTrame`, lampe ou groupe), `ReseauIp` (bloc `ip` : `srp`, `adresses` avec `TypeAdresse`, `udp` ; `hote`, `adresseOmr`), `CapPont`, `TransportSession` ; `HelloBase.ReglagesSession` gagne `transport` et `trames` ; `CodeReponse.interdite` et `.dejaTraite` ; `Reponse.cle`, `Reponse.empreinte`, `Reponse.sansCle` ; `MessageCarte` gagne `.reseauIp`, `.trame`, `.texte` ; `MessageCarte.sansCle`, `LigneMachine.sansCle`, `ElementRecu.sansCle` ;
  - `EtatPont` : `ip`, `rev`, `transport`, `mac`, `srp`, `a(_:)` ; `Interpretation.trame(_:)` ;
  - commandes : `LigneCommande.argv(_:maxArguments:)` (portage d'`esp_console_split_argv`), `PolitiqueCommandes.autoriseeADistance(_:)` (nil : permise ; sinon la raison du pont), `bornesDistantes`, `verdictConsole(_:transport:)`, `masquerCle(_:)`, `masquerCleStricte(_:)`, `repondApresInstantane(_:)` ;
  - session : `PolitiqueDelais.reseau`, `pour(_:)`, `delaiInstantane` et `delaiReponse(pour:)`, `Correlateur.renvoisDus(maintenant:)`, `Correlateur.texte(_:id:maintenant:)` ; `MoteurSession.ouvert(maintenant:genre:)`, `ligneJson1`, `reglagesParDefaut(_:bailDistantS:)`, `bornes(_:genre:)`, `ligneCadence(_:ms:)`, `Note.reseauSansHello` ;
  - `enum H1` : `hexa(_:)`, `octets(hexa:)`, `aleatoire(_:)`, `kid(cle:)`, `salut(cle:na:)`, `verifierDefi(_:cle:na:)`, `cleSession(cle:na:nc:sid:)` ; `struct FenetreAntiRejeu` ; `struct SessionH1` (`sceller(_:)`, `ouvrir(_:)`, `ecartes`) ;
  - `enum CleReseau` : `alea()`, `commande(alea:)` (`json cle nouvelle <64 HEX>`), `verifier(_:)` (`Creee` : clé et empreinte vérifiées).

Pourquoi : la spec 3b, sections 5 et 7, et le protocole, section 10. Le document du protocole porte les exemples de la section 10 depuis la Task 2, et les tests de l'app du plan 3b-1 relisent chacun de ses exemples : l'app apprend donc les messages à distance dès sa première tâche.
- **Messages** : `texte`, `trame`, le bloc `ip`, la session du `hello` (`transport`, `trames`), les capacités, les codes `interdite` et `deja_traite`, la clé et son empreinte dans une `reponse`.
- **Liste blanche** : `autoriseeADistance` est le miroir exact de `refusDistant` du pont, jugé sur les mots que la console exécuterait (`LigneCommande.argv`, portage octet pour octet d'`esp_console_split_argv`) : `json "1" "bail" 0` y est refusé comme sur le pont. Les règles de la console par l'USB (refus de `json cle nouvelle`, confirmations) se jugent sur les mêmes mots.
- **Masquage** : aucune clé (Mesh ou UDP) n'apparaît dans une ligne gardée : `json cle nouvelle <hexa>` et `"cle":"…"` sont masqués ; le masque se juge aussi sur les mots de la commande (après `mesh cles` ou `json cle nouvelle`, tout est masqué, échappements et guillemets compris ; seule une citation de l'app, après `«`, finit à `»`) ; un masque strict couvre les lignes abîmées, les fragments et les débordements ; chaque élément reçu passe par `sansCle` avant tout journal ; une commande que le masque change est soumise comme secrète.
- **Session par le réseau** (politique de Halo) : sans réponse, la même ligne (même `id`) repart à 2 s puis à 4 s, et la commande est déclarée sans réponse à 6 s (12 s pour `json 1`, `json etat` et `json hello`, dont la fin suit un instantané) ; `deja_traite` (réponse oubliée par le pont) clôt la commande, puis l'état est redemandé ; un événement `ordre` clôt aussi une commande dont l'`accepte` s'est perdu. Le moteur ouvre par `json 1 bail 60`, pingue toutes les 10 s, ne demande que des cadences permises à distance, et refait la poignée de main après 30 s sans `hello`.
- **L'enveloppe H1 et la clé** : le canal H1 de Halo, octet pour octet, que le pont parle depuis la Task 1 (les vecteurs des tests sont ceux de `tests/hote/test_h1.cpp`) ; `CleReseau` forme la commande de création de la clé et vérifie la réponse (64 hexa, empreinte = SHA-256).

Repris de Halo Compagnon (commit `e114cd5`) : `HaloProtocole/Reseau/{EnveloppeH1,CleReseau}.swift`, la politique réseau de `HaloProtocole/Commandes/Correlateur.swift` et de `HaloProtocole/Session/MoteurSession.swift`, et leurs tests. Neuf ici : la liste blanche jugée sur les mots, le masque jugé sur les mots, le traitement de `deja_traite` et des instantanés à distance.

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranProtocoleTests/CleReseauTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : creation et verification de la cle UDP.
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Cle du transport reseau ")
struct CleReseauTests {
    static func reponseCle(ok: Bool = true, code: CodeReponse = .ok, cle: String?, empreinte: String?) -> Reponse {
        Reponse(id: 7, etape: .fin, cmd: "json cle nouvelle", ok: ok, code: code, msg: ok ? nil : "tampon USB occupe",
                dureeMs: 1, cle: cle, empreinte: empreinte)
    }

    @Test func commande() {
        let c = CleReseau.commande(alea: Data(repeating: 0xAB, count: 32))
        #expect(c == "json cle nouvelle " + String(repeating: "AB", count: 32))
        if case .failure(let e) = LigneCommande.valider(c, id: LigneCommande.idMax) { Issue.record("\(e)") }
        #expect(CleReseau.alea().count == 32)
    }

    @Test func verifierUneBonneCle() throws {
        let r = Self.reponseCle(cle: H1.hexa(VecteursH1.psk), empreinte: "630DCD29")
        let c = try CleReseau.verifier(r).get()
        #expect(c.cle == VecteursH1.psk)
        #expect(c.empreinte == "630DCD29")
    }

    @Test func refus() {
        #expect(CleReseau.verifier(Self.reponseCle(ok: false, code: .erreur, cle: nil, empreinte: nil))
                == .failure(.refusee("tampon USB occupe")))
        #expect(CleReseau.verifier(Self.reponseCle(cle: nil, empreinte: "630DCD29")) == .failure(.cleIllisible))
        #expect(CleReseau.verifier(Self.reponseCle(cle: H1.hexa(VecteursH1.psk).lowercased(), empreinte: "630DCD29"))
                == .failure(.cleIllisible))
        #expect(CleReseau.verifier(Self.reponseCle(cle: H1.hexa(VecteursH1.psk), empreinte: "00000000"))
                == .failure(.empreinteIncoherente))
    }

    @Test func laCleNestJamaisRangeeDansLeSuivi() {
        var c = Correlateur()
        let a = c.soumettre(CleReseau.commande(alea: Data(repeating: 1, count: 32)), origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(Self.reponseCle(cle: H1.hexa(VecteursH1.psk), empreinte: "630DCD29").avecId(1), maintenant: 0.1)
        // La cle ne va que dans le trousseau : jamais dans un suivi de commande, meme un instant (5.2).
        #expect(c.suivi(a)?.fin?.cle == nil)
        #expect(c.suivi(a)?.fin?.empreinte == "630DCD29", "l'empreinte reste")
    }
}

extension Reponse {
    func avecId(_ n: Int) -> Reponse {
        var r = self
        r.id = n
        return r
    }
}
````

`apps/macos/AmaranProtocoleTests/ClesTests.swift`, bloc 1 sur 1. Remplacer :

````swift
        let c = Factice.reseau().commandes()[0]
        #expect(PolitiqueCommandes.masquerCle(c) == "mesh cles •••••••• ••••••••")
        #expect(PolitiqueCommandes.masquerCle("id=7 MESH  Cles 00112233445566778899aabbccddeeff x")
                == "id=7 MESH  Cles •••••••• •••••••• x")
        #expect(PolitiqueCommandes.masquerCle("ok cles 1A2B3C4D 5E6F7A8B (redemarrer)") == "ok cles 1A2B3C4D 5E6F7A8B (redemarrer)",
                "les empreintes restent visibles")
````

par :

````swift
        let c = Factice.reseau().commandes()[0]
        #expect(PolitiqueCommandes.masquerCle(c) == "mesh cles •••••••• ••••••••")
        // Apres `mesh cles`, tout ce qui suit est masque, un masque par mot (ici la cle et « x »).
        #expect(PolitiqueCommandes.masquerCle("id=7 MESH  Cles 00112233445566778899aabbccddeeff x")
                == "id=7 MESH  Cles •••••••• ••••••••")
        #expect(PolitiqueCommandes.masquerCle("ok cles 1A2B3C4D 5E6F7A8B (redemarrer)") == "ok cles 1A2B3C4D 5E6F7A8B (redemarrer)",
                "les empreintes restent visibles")
````

`apps/macos/AmaranProtocoleTests/CouvertureClesTests.swift`, bloc 1 sur 4. Remplacer :

````swift
        case .reseauMatter(let v): return try e.encode(v)
        case .reseauThread(let v): return try e.encode(v)
        case .battement(let v): return try e.encode(v)
        case .fin(let v): return try e.encode(v)
````

par :

````swift
        case .reseauMatter(let v): return try e.encode(v)
        case .reseauThread(let v): return try e.encode(v)
        case .reseauIp(let v): return try e.encode(v)
        case .battement(let v): return try e.encode(v)
        case .fin(let v): return try e.encode(v)
````

`apps/macos/AmaranProtocoleTests/CouvertureClesTests.swift`, bloc 2 sur 4. Remplacer :

````swift
        case .led(let v): return try e.encode(v)
        case .log(let v): return try e.encode(v)
        case .inconnu: return nil
        }
````

par :

````swift
        case .led(let v): return try e.encode(v)
        case .log(let v): return try e.encode(v)
        case .trame(let v): return try e.encode(v)
        case .texte(let v): return try e.encode(v)
        case .inconnu: return nil
        }
````

`apps/macos/AmaranProtocoleTests/CouvertureClesTests.swift`, bloc 3 sur 4. Remplacer :

````swift
        #"{"v":1,"t":"alerte","n":10,"ms":10,"quoi":"releves","lampe":4,"manque":false,"part":96}"#,
        #"{"v":1,"t":"lampe","n":11,"ms":11,"lampe":5,"quoi":"echec","endpoint":null}"#,
        // Reponse complete : msg, suite aucune, lampe, bail.
        #"{"v":1,"t":"reponse","n":12,"ms":12,"id":17,"etape":"fin","cmd":"json ping","ok":true,"code":"ok","msg":"bail renouvele","duree_ms":1,"suite":"aucune","lampe":3,"bail_s":30,"up_s":90}"#,
````

par :

````swift
        #"{"v":1,"t":"alerte","n":10,"ms":10,"quoi":"releves","lampe":4,"manque":false,"part":96}"#,
        #"{"v":1,"t":"lampe","n":11,"ms":11,"lampe":5,"quoi":"echec","endpoint":null}"#,
        // Trame d'ordre eteint par Thread, avec trames non emises ; adresse d'un autre type.
        #"{"v":1,"t":"trame","n":13,"ms":13,"sens":"tx","quoi":"ordre","lampe":16,"marche":false,"intensite":null,"essai":3,"sautes":9}"#,
        #"{"v":1,"t":"reseau","n":14,"ms":14,"bloc":"ip","srp":null,"adresses":[{"type":"autre","adresse":"fd12:34:5678:0:aaaa:bbbb:ccc:dddd"}],"udp":{"port":5480,"cle":true,"empreinte":"1A2B3C4D","ouvert":false,"sessions":2,"recus":1,"emis":2,"rejets":0,"perdus":5}}"#,
        // Session distante en trames et journal.
        #"{"v":1,"t":"hello","n":15,"ms":15,"bloc":"base","rev":1,"session":{"transport":"udp","periode_ms":0,"lampes_ms":0,"compteurs_ms":5000,"reseau_ms":0,"bail_s":120,"log":true,"trames":true}}"#,
        // Reponse complete : msg, suite aucune, lampe, bail.
        #"{"v":1,"t":"reponse","n":12,"ms":12,"id":17,"etape":"fin","cmd":"json ping","ok":true,"code":"ok","msg":"bail renouvele","duree_ms":1,"suite":"aucune","lampe":3,"bail_s":30,"up_s":90}"#,
````

`apps/macos/AmaranProtocoleTests/CouvertureClesTests.swift`, bloc 4 sur 4. Remplacer :

````swift
    func chaqueChampHorsExemplesEstLu(_ json: String) throws {
        let perdus = try CouvertureCles.perdus(json)
        #expect(perdus.isEmpty, "champs perdus au decodage : \(perdus)")
    }

````

par :

````swift
    func chaqueChampHorsExemplesEstLu(_ json: String) throws {
        let perdus = try CouvertureCles.perdus(json)
        #expect(perdus.isEmpty, "champs perdus au decodage : \(perdus)")
    }

    /// A distance, le bloc `matter` porte `code_manuel` et `qr` a null (5.5, 10.1) : rien de
    /// secret ne passe par Thread. Le bloc se decode, et le reste de ses champs avec.
    @Test func matterADistanceSansCodes() throws {
        let json = #"{"v":1,"t":"reseau","n":15,"ms":83622,"bloc":"matter","demarre":true,"fabriques":1,"ble":false,"identifie":false,"abonnements":{"demandes":2,"plafonnes":2,"etablis":2,"termines":1,"plafond_s":20},"code_manuel":null,"qr":null}"#
        #expect(try CouvertureCles.perdus(json).isEmpty)
        var r = RecepteurLignes()
        guard case .machine(let l)? = r.alimenter(ligneMachine(json)).first, case .reseauMatter(let m) = l.message else {
            Issue.record("bloc matter attendu")
            return
        }
        #expect(m.codeManuel == nil && m.qr == nil)
        #expect(m.fabriques == 1 && m.abonnements?.actifs == 1)
        var e = EtatPont()
        e.appliquer(l, recueA: Date())
        #expect(e.enService == true)
        #expect(e.matter?.valeur.codeManuel == nil)
    }

````

`apps/macos/AmaranProtocoleTests/EnveloppeH1Tests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : vecteurs et cas de l'enveloppe H1 (memes octets que le firmware du pont).
import CryptoKit
import Foundation
import Testing
@testable import AmaranProtocole

/// Vecteurs H1 de Halo (spec 3b, section 7) : les memes que ceux du firmware.
enum VecteursH1 {
    static let psk = Data((0..<32).map { UInt8($0) })
    static let na = Data((0xA0...0xAF).map { UInt8($0) })
    static let nc = "505152535455565758595A5B5C5D5E5F"
    static let sid = "1234ABCD"
    static let ks = "20D6D83D97ED44F2BBF8CE56389BD475CBE2B625CE6CE24768B6B4C1C625012F"
    static let salut = "H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D"
    static let defi = "H1 DEFI 1234ABCD 505152535455565758595A5B5C5D5E5F BFF13F71B42243E6017D2807F8E6171F"
    static let a1 = "H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE id=1 json 1"
    static let chargeC1 = #"{"v":1,"t":"hb","n":7,"ms":1234}"#
    static let c1 = "H1 1234ABCD 1 347A2E6A129BC822ECFF39BEC910451C " + chargeC1

    static func session() -> SessionH1 {
        SessionH1(sid: sid, ks: H1.cleSession(cle: psk, na: na, nc: nc, sid: sid))
    }
}

func octets(_ s: String) -> Data { Data(s.utf8) }

@Suite("Enveloppe H1")
struct EnveloppeH1Tests {
    @Test func kidEtSalut() {
        #expect(H1.kid(cle: VecteursH1.psk) == "630DCD29")
        #expect(H1.salut(cle: VecteursH1.psk, na: VecteursH1.na) == octets(VecteursH1.salut))
    }

    @Test func hexa() {
        #expect(H1.hexa([0x00, 0xAB, 0x0F]) == "00AB0F")
        #expect(H1.octets(hexa: "00AB0F") == Data([0x00, 0xAB, 0x0F]))
        #expect(H1.octets(hexa: "00ab0f") == nil, "majuscules seulement")
        #expect(H1.octets(hexa: "ABC") == nil, "longueur impaire")
        #expect(H1.aleatoire(16).count == 16)
        #expect(H1.aleatoire(32) != H1.aleatoire(32))
    }

    @Test func defiEtCleDeSession() throws {
        let r = try #require(H1.verifierDefi(octets(VecteursH1.defi), cle: VecteursH1.psk, na: VecteursH1.na))
        #expect(r.sid == VecteursH1.sid)
        #expect(r.nc == VecteursH1.nc)
        let ks = H1.cleSession(cle: VecteursH1.psk, na: VecteursH1.na, nc: r.nc, sid: r.sid)
        #expect(ks.withUnsafeBytes { H1.hexa($0) } == VecteursH1.ks)
    }

    @Test func defiRefuse() {
        let autreNa = Data(repeating: 0x11, count: 16)
        #expect(H1.verifierDefi(octets(VecteursH1.defi), cle: VecteursH1.psk, na: autreNa) == nil, "autre na")
        let minuscules = VecteursH1.defi.replacingOccurrences(of: "BFF13F71B42243E6017D2807F8E6171F",
                                                              with: "bff13f71b42243e6017d2807f8e6171f")
        #expect(H1.verifierDefi(octets(minuscules), cle: VecteursH1.psk, na: VecteursH1.na) == nil, "minuscules")
        var faux = Array(VecteursH1.defi.utf8)
        faux[faux.count - 1] = UInt8(ascii: "E")
        #expect(H1.verifierDefi(Data(faux), cle: VecteursH1.psk, na: VecteursH1.na) == nil, "MAC faux")
        #expect(H1.verifierDefi(octets(VecteursH1.salut), cle: VecteursH1.psk, na: VecteursH1.na) == nil, "pas un DEFI")
    }

    @Test func scellerCommeLeFirmware() {
        var s = VecteursH1.session()
        #expect(s.sceller(octets("id=1 json 1")) == octets(VecteursH1.a1))
        #expect(s.ctrEmis == 1)
    }

    @Test func ouvrirUnMessageDeLaCarte() {
        var s = VecteursH1.session()
        #expect(s.ouvrir(octets(VecteursH1.c1)) == octets(VecteursH1.chargeC1))
        #expect(s.ouvrir(octets(VecteursH1.c1)) == nil, "rejeu")
        #expect(s.ecartes == 1)
    }

    @Test func formeCanonique() {
        var s = VecteursH1.session()
        let mac = "347A2E6A129BC822ECFF39BEC910451C"
        let c = VecteursH1.chargeC1
        let faux = [
            "H1 1234ABCD 01 \(mac) \(c)",              // zero de tete
            "H1 1234ABCD 0 \(mac) \(c)",               // ctr nul
            "H1 1234abcd 1 \(mac) \(c)",               // sid en minuscules
            "H1 1234ABCD 1 \(mac.lowercased()) \(c)",  // MAC en minuscules
            "H1 9999ABCD 1 \(mac) \(c)",               // autre session
            "H1 1234ABCD 1 \(mac)",                    // charge absente
        ]
        for f in faux { #expect(s.ouvrir(octets(f)) == nil, "\(f)") }
        #expect(s.ecartes == faux.count)
        #expect(s.ouvrir(octets(VecteursH1.c1)) != nil, "le vrai passe ensuite")
    }

    @Test func messageDeLAppNeSOuvrePasCommeMessageDeLaCarte() {
        var s = VecteursH1.session()
        #expect(s.ouvrir(octets(VecteursH1.a1)) == nil, "sens A presente comme C")
    }

    @Test func fenetre() {
        // Comparaison explicite (pas d'appel nu) : le macro #expect decompose
        // un appel a une methode mutante en `{ $0.accepter($1) }`, ou `$0` est
        // immuable, ce qui ne compile pas ; comparer le Bool rendu evite ca.
        var f = FenetreAntiRejeu()
        #expect(f.accepter(0) == false)
        #expect(f.accepter(1) == true)
        #expect(f.accepter(3) == true)
        #expect(f.accepter(2) == true, "desordre admis")
        #expect(f.accepter(2) == false, "rejeu")
        #expect(f.accepter(40) == true, "saut")
        #expect(f.accepter(8) == false, "trop ancien : 40 - 8 >= 32")
        #expect(f.accepter(9) == true, "dans la fenetre : 40 - 9 = 31")
        #expect(f.haut == 40)
    }

    @Test func macFauxNePoussePasLaFenetre() {
        var s = VecteursH1.session()
        #expect(s.ouvrir(octets("H1 1234ABCD 1000 00000000000000000000000000000000 {}")) == nil)
        #expect(s.ouvrir(octets(VecteursH1.c1)) != nil, "ctr 1 encore admis : la fenetre n'a pas bouge")
    }
}
````

`apps/macos/AmaranProtocoleTests/ExemplesSpecTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : les exemples sont ceux de
// docs/PROTOCOLE-JSON.md du pont amaran, que tests/hote/test_json.cpp forme tels quels.
import Foundation
import Testing
@testable import AmaranProtocole

/// Les lignes `<RS>{...}` de docs/PROTOCOLE-JSON.md, lues dans le document lui-meme :
/// le protocole du firmware, sa specification et l'app ne divergent pas.
enum ExemplesSpec {
    static let chemin = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AmaranProtocoleTests
        .deletingLastPathComponent()  // macos
        .deletingLastPathComponent()  // apps
        .deletingLastPathComponent()  // racine du depot
        .appendingPathComponent("docs/PROTOCOLE-JSON.md")

    static func lignes() throws -> [String] {
        let texte = try String(contentsOf: chemin, encoding: .utf8)
        return texte.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("<RS>") }
            .map { String($0.dropFirst(4)) }
    }

    /// Decode toutes les lignes dans un meme recepteur, comme sur le fil.
    static func decoder() throws -> [LigneMachine] {
        var r = RecepteurLignes()
        var octets: [UInt8] = []
        for l in try lignes() { octets += [Octets.rs] + Array(l.utf8) + [Octets.lf] }
        return r.alimenter(octets).compactMap {
            if case .machine(let l) = $0 { return l }
            return nil
        }
    }
}

@Suite("Exemples de la specification (sections 9 et 10)")
struct ExemplesSpecTests {
    @Test func toutesLesLignesSontLues() throws {
        #expect(try ExemplesSpec.lignes().count == 60)
    }

    @Test(arguments: (try? ExemplesSpec.lignes()) ?? [])
    func chaqueLigneSeDecode(_ json: String) throws {
        var r = RecepteurLignes()
        let e = r.alimenter([Octets.rs] + Array(json.utf8) + [Octets.lf])
        try #require(e.count == 1, "un element attendu : \(e)")
        guard case .machine(let l) = e[0] else {
            Issue.record("ligne rejetee : \(e[0])")
            return
        }
        #expect(l.message != .inconnu, "type non gere : \(l.enveloppe.t) \(l.enveloppe.bloc ?? "")")
        #expect(l.enveloppe.v == 1)
        #expect(json.utf8.count + 2 <= 896, "au-dela du budget de 896 octets")
        #expect(r.compteurs.lignesAbimees == 0)
    }

    @Test func connexion() throws {
        let l = try ExemplesSpec.decoder()
        guard case .helloBase(let h) = l[0].message else { Issue.record("hello base"); return }
        #expect(h.fw == "0.1.0-d569f01")
        #expect(h.boot == "3FA2C901")
        #expect(h.reset == "logiciel")
        #expect(h.rev == 1)
        #expect(h.session?.transport == .usb)
        #expect(h.session?.lampesMs == 10000)
        #expect(h.session?.bailS == 30)
        #expect(h.session?.trames == false)
        #expect(h.limites?.cmdMax == 127)

        guard case .helloIdentite(let i) = l[1].message else { Issue.record("identite"); return }
        #expect(i.id?.serie == "AMARAN-F0F5BD0A0B0C")
        #expect(i.caps?.contains("ordres") == true)
        var e = EtatPont()
        e.appliquer(l[1], recueA: Date())
        #expect(CapPont.allCases.allSatisfy { e.a($0) }, "rev 1 : trames, udp, cle, texte en plus")

        guard case .configCatalogue(let c) = l[2].message else { Issue.record("catalogue"); return }
        #expect(c.modeles?.first?.code == 40065)
        #expect(c.modeles?.first?.capacites == [.intensite])
        #expect(c.repli?.type == .variable)

        guard case .configMesh(let m) = l[3].message else { Issue.record("mesh"); return }
        #expect(m.empreintes?.reseau == "1A2B3C4D")
        #expect(m.adresse == "7F38")
        #expect(m.lampes == 2)
        #expect(m.releveMs == 2000)

        guard case .configLampe(let l2) = l[5].message else { Issue.record("config lampe 2"); return }
        #expect(l2.lampe == 2)
        #expect(l2.nom == "Lumière fenêtre")
        #expect(l2.mac == "020000000002")

        guard case .etatPont(let p) = l[6].message else { Issue.record("etat pont"); return }
        #expect(p.mesh?.diag == .ok)
        #expect(p.ordres?.delaiMoyenMs == 430)

        guard case .etatLampe(let e1) = l[7].message else { Issue.record("etat lampe 1"); return }
        #expect(e1.maison?.endpoint == 2)
        #expect(e1.lue == EtatLu(marche: true, intensite: 430))
        #expect(e1.part10Min == 97)
        #expect(e1.consigne == nil)

        guard case .etatSante(let s) = l[9].message else { Issue.record("sante"); return }
        #expect(s.commande == nil)
        #expect(s.led?.motif == .operationnel)
        #expect(s.sys?.piles?["ot_task"] == 1536)

        guard case .reseauMatter(let r) = l[11].message else { Issue.record("matter"); return }
        #expect(r.abonnements?.actifs == 1)
        #expect(r.codeManuel == "34970112332")
    }

    @Test func ordreEtEvenements() throws {
        let tout = try ExemplesSpec.decoder()
        let ordres = tout.compactMap { if case .ordre(let o) = $0.message { return o } else { return nil } }
        #expect(ordres.map(\.issue) == [.confirme, .tenu, .abandon])
        #expect(ordres.first?.ids == [2])
        let lampes = tout.compactMap { if case .lampe(let e) = $0.message { return e } else { return nil } }
        #expect(lampes.map(\.quoi) == [.masquee, .remise, .entree])
        #expect(lampes.first?.endpoint == nil)
        let alertes = tout.compactMap { if case .alerte(let a) = $0.message { return a } else { return nil } }
        #expect(alertes.map(\.quoi) == [.releves, .mesh, .mesh])
        #expect(alertes[1].diag == .clesPerimees)
        let sante = tout.compactMap { if case .etatSante(let s) = $0.message { return s } else { return nil } }
        #expect(sante.map(\.commande) == [nil, 7], "le bloc sante porte la commande en cours")
    }

    /// Un ordre refuse faute de Bluetooth Mesh (essai 0) n'accuse pas la lampe.
    @Test func abandonSansEssaiDitMeshPasPret() {
        let refuse = EvenementOrdre(lampe: 1, issue: .abandon, delaiMs: 0, essai: 0, ids: [4], idsPerdus: 0)
        #expect(Interpretation.ordre(refuse).contains("Bluetooth Mesh pas prêt"))
        #expect(!Interpretation.ordre(refuse).contains("ne répond pas"))
        let abandon = EvenementOrdre(lampe: 1, issue: .abandon, delaiMs: 3700, essai: 3, ids: [4], idsPerdus: 0)
        #expect(Interpretation.ordre(abandon) == "abandonné après 3 essai(s), 3700 ms : la lampe ne répond pas")
    }

    /// Section 10.6 : chaque champ des exemples a distance.
    @Test func aDistance() throws {
        let tout = try ExemplesSpec.decoder()
        let hellos = tout.compactMap { if case .helloBase(let h) = $0.message { return h } else { return nil } }
        let h = try #require(hellos.last)
        #expect(h.session == HelloBase.ReglagesSession(transport: .udp, periodeMs: 2000, lampesMs: 30000, compteursMs: 0,
                                                       reseauMs: 30000, bailS: 60, log: false, trames: false))
        #expect(h.upS == 900)

        let ips = tout.compactMap { if case .reseauIp(let r) = $0.message { return r } else { return nil } }
        #expect(ips.count == 2)
        let ip = ips[0]
        #expect(ip.srp == "1A2B3C4D5E6F7081")
        #expect(ip.hote == "1A2B3C4D5E6F7081.local")
        #expect(ip.adresses?.map(\.type) == [.omr, .mlEid])
        #expect(ip.adresseOmr == "fd00:aaaa:bbbb:0:1111:2222:3333:4444")
        #expect(ip.adresses?.last?.adresse == "fd00:cccc:dddd:1:5555:6666:7777:8888")
        #expect(ip.udp?.port == 5480)
        #expect(ip.udp?.cle == true)
        #expect(ip.udp?.empreinte == "CA2A4FE7")
        #expect(ip.udp?.ouvert == true)
        #expect(ip.udp?.sessions == 1)
        #expect(ip.udp?.recus == 412 && ip.udp?.emis == 980 && ip.udp?.rejets == 3 && ip.udp?.perdus == 0)
        let sans = ips[1]
        #expect(sans.adresses == [] && sans.adresseOmr == nil)
        #expect(sans.udp?.cle == false && sans.udp?.empreinte == nil && sans.udp?.ouvert == false)

        let reponses = tout.compactMap { if case .reponse(let r) = $0.message { return r } else { return nil } }
        let cle = try #require(reponses.first { $0.cle != nil })
        #expect(cle.cmd == "json cle nouvelle", "le pont ne cite jamais l'alea")
        #expect(cle.empreinte == "CA2A4FE7")
        #expect(CleReseau.verifier(cle).map(\.empreinte) == .success("CA2A4FE7"), "empreinte = SHA-256 de la cle")
        #expect(cle.sansCle.cle == nil && cle.sansCle.empreinte == "CA2A4FE7")
        let interdite = try #require(reponses.first { $0.code == .interdite })
        #expect(interdite.cmd == "redemarre" && !interdite.ok)
        #expect(interdite.msg == PolitiqueCommandes.autoriseeADistance("redemarre"), "meme raison que le miroir de l'app")
        let deja = try #require(reponses.first { $0.code == .dejaTraite })
        #expect(deja.id == 29 && deja.etape == .fin && deja.msg == "id deja traite : reponse oubliee")

        let textes = tout.compactMap { if case .texte(let t) = $0.message { return t } else { return nil } }
        #expect(textes == [TexteCommande(id: 32, txt: "lampe 1 : Lampe bureau"), TexteCommande(id: 32, txt: "  Maison    : EP2")])

        let trames = tout.compactMap { if case .trame(let t) = $0.message { return t } else { return nil } }
        #expect(trames == [
            Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: true, intensite: 500, essai: 1, sautes: 0),
            Trame(sens: .tx, quoi: .demande, lampe: nil, marche: nil, intensite: nil, essai: nil, sautes: 0),
            Trame(sens: .rx, quoi: .etat, lampe: 1, marche: true, intensite: 500, essai: nil, sautes: 2),
        ])
        #expect(trames.map(Interpretation.trame) == [
            "→ lampe 1 : ordre allumée, 50 % (essai 1)",
            "→ groupe : demande d'état",
            "← lampe 1 : état allumée, 50 % — 2 trame(s) non émise(s) avant",
        ])
    }

    /// La lecture a distance (`id=32 lampe 1`) se deroule dans le correlateur comme par
    /// l'USB : `debut`, le texte rattache a la commande, puis `fin`.
    @Test func lectureADistanceCorrelee() throws {
        let tout = try ExemplesSpec.decoder()
        let premiere = try #require(tout.firstIndex {
            if case .reponse(let r) = $0.message { r.id == 32 && r.cmd == "lampe 1" } else { false }
        })
        var c = Correlateur()
        c.politique = .reseau
        // Le correlateur numerote lui-meme : amener le prochain numero a 32.
        for _ in 1..<32 { _ = c.reserverNumero() }
        let a = c.soumettre("lampe 1", origine: .console, maintenant: 0)
        let p = c.prochainEnvoi(maintenant: 0)
        #expect(p.map { texte($0.octets) } == "id=32 lampe 1\n")
        for l in tout[premiere...] {
            switch l.message {
            case .reponse(let r) where r.id == 32: _ = c.recevoir(r, maintenant: 1)
            case .texte(let t): c.texte(t.txt ?? "", id: t.id, maintenant: 1)
            default: break
            }
        }
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.texte == ["lampe 1 : Lampe bureau", "  Maison    : EP2"])
        #expect(c.suivi(a)?.fin?.dureeMs == 6)
    }
}
````

`apps/macos/AmaranProtocoleTests/ListeBlancheTests.swift` (contenu complet) :

````swift
// Liste blanche a distance (docs/PROTOCOLE-JSON.md 10.5) : miroir de `refusDistant`
// (components/protocole/json_amaran.cpp), avec tous les cas de `testDistant`
// (tests/hote/test_json.cpp).
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Decoupage comme esp_console_split_argv")
struct DecoupageArgvTests {
    @Test func motsSimples() {
        #expect(LigneCommande.argv("json 1 bail 60") == ["json", "1", "bail", "60"])
        #expect(LigneCommande.argv("  lampe   1  on ") == ["lampe", "1", "on"])
        #expect(LigneCommande.argv("") == [])
        #expect(LigneCommande.argv("   ") == [])
    }

    @Test func guillemetsEtEchappements() {
        #expect(LigneCommande.argv(#"json "1" "bail" 0"#) == ["json", "1", "bail", "0"])
        #expect(LigneCommande.argv(#""mesh lampe" 1 masquer"#) == ["mesh lampe", "1", "masquer"])
        #expect(LigneCommande.argv(#""mesh"cles a"#) == ["mesh", "cles", "a"], "le guillemet fermant finit le mot")
        #expect(LigneCommande.argv(#"json\ 1"#) == ["json 1"], "espace echappee : un seul mot")
        #expect(LigneCommande.argv(#"a\"b"#) == [#"a"b"#])
        #expect(LigneCommande.argv(#"a\\b"#) == [#"a\b"#])
        #expect(LigneCommande.argv(#"le\d"#) == ["le"], "echappement inconnu : les deux octets oublies")
        #expect(LigneCommande.argv(#""x\"y" z"#) == [#"x"y"#, "z"])
        #expect(LigneCommande.argv(#""" x"#) == ["", "x"], "guillemets vides : un mot vide")
        #expect(LigneCommande.argv(#""non ferme"#) == ["non ferme"])
        #expect(LigneCommande.argv("json\t1") == ["json\t1"], "la tabulation fait partie du mot")
        #expect(LigneCommande.argv("Lumière fenêtre") == ["Lumière", "fenêtre"], "UTF-8 intact")
    }

    @Test func septArgumentsAuPlus() {
        #expect(LigneCommande.argv("1 2 3 4 5 6 7 8 9") == ["1", "2", "3", "4", "5", "6", "7"])
        #expect(LigneCommande.argv("1 2 3 4 5 6 7") == ["1", "2", "3", "4", "5", "6", "7"])
    }
}

@Suite("Liste blanche a distance (10.5)")
struct ListeBlancheTests {
    /// `kPermises` de testDistant.
    static let permises = [
        "json 1", "json 1 bail 10", "json 1 bail 120", "json 0", "json etat", "json hello", "json ping",
        "json periode 2000", "json periode 0", "json periode 60000", "json lampes 10000", "json lampes 0",
        "json compteurs 0", "json compteurs 5000", "json reseau 10000", "json reseau 0", "json trames 1",
        "json trames 0", "json log 1", "lampe 1", "lampe 2 on", "lampe 16 off", "lampe 1 niveau 500",
        "lampe 3 releve", "mesh", "mesh lampe 2 masquer", "mesh lampe 2 afficher", "led test", "led stop",
        "lampes", "matter", "taches", "cause",
    ]

    /// `kInterdites` de testDistant.
    static let interdites = [
        "json 1 bail 0", "json 1 bail 9", "json 1 bail 121", "json 1 bail", "json 1 xyz 30", "json periode 1999",
        "json periode 60001", "json lampes 9999", "json compteurs 4999", "json reseau 9999", "json trames 2",
        "json cle nouvelle 00", "json cle efface", "json", "json periode", "json periode 2000 3000",
        "lampe", "lampe x on", "lampe 1 clignote", "lampe 1 niveau", "lampe 1 niveau x", "lampe 1 on 2",
        "mesh cles 00 11", "mesh lampes 2", "mesh lampe 1 0x0002 02:00:00:00:00:01 40065 nom", "mesh oublie",
        "mesh adresse suivante", "mesh iv 5", "mesh releve 2", "mesh balayage", "mesh lampe 2 masquer x",
        "decommission", "redemarre", "led", "led test x", "taches x", "help", "",
    ]

    @Test(arguments: permises)
    func permise(_ c: String) {
        #expect(PolitiqueCommandes.autoriseeADistance(c) == nil)
    }

    @Test(arguments: interdites)
    func interdite(_ c: String) {
        #expect(PolitiqueCommandes.autoriseeADistance(c) != nil)
        if case .interdite = PolitiqueCommandes.verdictConsole(c, transport: .udp) {} else {
            Issue.record("\(c) doit etre refusee a distance")
        }
    }

    @Test func raisonsDuPont() {
        #expect(PolitiqueCommandes.autoriseeADistance("json 1 bail 0") == "json 1 : bail de 10 a 120 s a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json periode 100") == "json periode : 0 ou 2000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json lampes 1") == "json lampes : 0 ou 10000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json compteurs 1") == "json compteurs : 0 ou 5000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("json reseau 1") == "json reseau : 0 ou 10000..60000 ms a distance")
        #expect(PolitiqueCommandes.autoriseeADistance("redemarre") == "interdite a distance : USB seulement")
    }

    /// Un mot entre guillemets reste un seul mot une fois decoupe : la liste blanche le
    /// voit tel que la console l'executera.
    @Test func guillemetsEtEchappementsNeLaContournentPas() {
        for c in [#"json "1" "bail" 0"#, #"json 1 "bail" "0""#, #""json" 1 bail 0"#] {
            #expect(PolitiqueCommandes.autoriseeADistance(c) == "json 1 : bail de 10 a 120 s a distance", "\(c)")
        }
        #expect(PolitiqueCommandes.autoriseeADistance(#""mesh lampe" 1 masquer"#) != nil, "un seul mot 'mesh lampe'")
        #expect(PolitiqueCommandes.autoriseeADistance(#""json"cle efface"#) != nil)
        #expect(PolitiqueCommandes.autoriseeADistance(#"json\ 1"#) != nil, "un seul mot 'json 1'")
        #expect(PolitiqueCommandes.autoriseeADistance("JSON 1") != nil, "la console distingue la casse")
        #expect(PolitiqueCommandes.autoriseeADistance("json\t1") != nil, "la tabulation ne separe pas")
        #expect(PolitiqueCommandes.autoriseeADistance("lampe 1 niveau 1234567890") != nil, "10 chiffres : pas un nombre")
        #expect(PolitiqueCommandes.autoriseeADistance("lampe 1 niveau 123456789") == nil, "9 chiffres : un nombre")
        #expect(PolitiqueCommandes.autoriseeADistance("lampe 1 niveau -5") != nil)
        // Les guillemets autour d'un mot permis ne changent rien : decoupe identique.
        #expect(PolitiqueCommandes.autoriseeADistance(#""lampe" "1" "on""#) == nil)
        #expect(PolitiqueCommandes.autoriseeADistance("  led test  ") == nil, "espaces de bord retires a l'envoi")
    }

    @Test func consoleADistance() {
        #expect(PolitiqueCommandes.verdictConsole("lampe 1 on", transport: .udp) == .autorisee)
        #expect(PolitiqueCommandes.verdictConsole("mesh lampe 2 masquer", transport: .udp)
                == PolitiqueCommandes.verdictConsole("mesh lampe 2 masquer"), "permise : confirmation inchangee")
        // La raison du pont, citee une seule fois, telle quelle.
        #expect(PolitiqueCommandes.verdictConsole("redemarre", transport: .udp)
                == .interdite("Commande non envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »)."))
        #expect(PolitiqueCommandes.verdictConsole("redemarre")
                == .confirmation("Redémarre le pont (le port USB va se ré-énumérer)."), "USB : inchange")
    }

    /// La cle UDP ne se cree que par le geste de l'app (elle doit etre rangee).
    @Test func cleUDPParLaConsole() {
        let nouvelle = CleReseau.commande(alea: Data((0x40...0x5F).map { UInt8($0) }))
        if case .interdite(let raison) = PolitiqueCommandes.verdictConsole(nouvelle) {
            #expect(raison.contains("Nouvelle clé"))
        } else {
            Issue.record("json cle nouvelle doit etre refusee dans la console")
        }
        if case .confirmation = PolitiqueCommandes.verdictConsole("json cle efface") {} else {
            Issue.record("json cle efface demande confirmation")
        }
        #expect(PolitiqueCommandes.autoriseeADistance(nouvelle) != nil)
    }

    /// Par l'USB aussi, les regles de la console jugent la ligne decoupee comme la console
    /// du pont la decoupe : une barre oblique inverse devant un autre octet que `\`, `"` ou
    /// une espace disparait avec lui (split_argv.c d'ESP-IDF), et des guillemets autour d'un
    /// mot ne le changent pas. Ni refus ni confirmation ne se contournent ainsi.
    @Test func reglesDeLaConsoleJugeesSurArgv() {
        let alea = String(repeating: "AB", count: 32)
        #expect(LigneCommande.argv(#"re\xdemarre"#) == ["redemarre"])
        #expect(PolitiqueCommandes.verdictConsole(#"re\xdemarre"#)
                == PolitiqueCommandes.verdictConsole("redemarre"), "confirmation de redemarre")
        #expect(PolitiqueCommandes.verdictConsole(#"json c\xle efface"#)
                == PolitiqueCommandes.verdictConsole("json cle efface"), "confirmation de json cle efface")
        if case .interdite(let raison) = PolitiqueCommandes.verdictConsole(#"js\xon cle nouvelle "# + alea) {
            #expect(raison.contains("Nouvelle clé"))
        } else {
            Issue.record("js\\xon cle nouvelle : refusee comme json cle nouvelle")
        }
        for (ligne, pareille) in [(#"decommi\xssion"#, "decommission"), (#"mesh oub\xlie"#, "mesh oublie"),
                                  (#""mesh" "cles" 00 11"#, "mesh cles 00 11"), (#"js\xon 0"#, "json 0")] {
            #expect(LigneCommande.argv(ligne) == LigneCommande.argv(pareille), "\(ligne)")
            #expect(PolitiqueCommandes.verdictConsole(pareille) != .autorisee)
            #expect(PolitiqueCommandes.verdictConsole(ligne) == PolitiqueCommandes.verdictConsole(pareille), "\(ligne)")
        }
        #expect(PolitiqueCommandes.verdictConsole(#""mesh lampe" 1 masquer"#) == .autorisee,
                "un seul mot « mesh lampe » : le pont ne connait pas cette commande")
        // Sensible a la casse, comme la console : le pont ne connait pas REDEMARRE.
        #expect(PolitiqueCommandes.verdictConsole("REDEMARRE") == .autorisee)
        #expect(PolitiqueCommandes.attendReenumeration(#"re\xdemarre"#))
        #expect(PolitiqueCommandes.attendReenumeration(#""decommission""#))
        #expect(!PolitiqueCommandes.attendReenumeration("REDEMARRE"))
    }

    /// Confirmation de `decommission` : la cle de l'acces par Thread est effacee (10.2).
    @Test func decommissionDitLaCleThreadEffacee() {
        guard case .confirmation(let texte) = PolitiqueCommandes.verdictConsole("decommission") else {
            Issue.record("decommission demande confirmation")
            return
        }
        #expect(texte.contains("clés du Mesh et lampes gardées"))
        #expect(texte.contains("la clé de l'accès par Thread est effacée"))
    }

    @Test func bornesDuMoteurEtDeLaListe() {
        for (k, min) in PolitiqueCommandes.bornesDistantes {
            let c = MoteurSession.Cadence(rawValue: k)
            #expect(c != nil)
            #expect(c.map { MoteurSession.bornes($0, genre: .udp) } == min...60_000)
            #expect(PolitiqueCommandes.autoriseeADistance("json \(k) \(min)") == nil)
            #expect(PolitiqueCommandes.autoriseeADistance("json \(k) \(min - 1)") != nil)
        }
    }
}
````

`apps/macos/AmaranProtocoleTests/MasquageCleTests.swift` (contenu complet) :

````swift
// Masquage de la cle UDP (docs/PROTOCOLE-JSON.md 10.2) : aucune cle ne survit dans une
// ligne journalisee, entiere, coupee ou abimee. Cle inventee : les octets 0x40 a 0x5F.
import Foundation
import Testing
@testable import AmaranProtocole

enum CleInventee {
    static let octets = Data((0x40...0x5F).map { UInt8($0) })
    static let hexa = "404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F"
    /// La reponse de 10.6 qui rend la cle.
    static let reponse = #"{"v":1,"t":"reponse","n":60,"ms":860000,"id":5,"etape":"fin","cmd":"json cle nouvelle","ok":true,"code":"ok","duree_ms":12,"cle":"404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F","empreinte":"CA2A4FE7"}"#

    /// Vrai si un morceau de 6 hexa de la cle (casse quelconque) figure dans le texte.
    static func fuit(_ texte: String) -> Bool {
        let t = texte.uppercased()
        let h = Array(hexa)
        return (0...(h.count - 6)).contains { t.contains(String(h[$0..<($0 + 6)])) }
    }
}

@Suite("Masquage de la cle UDP (10.2)")
struct MasquageCleTests {
    @Test func commandeDeCreation() {
        let c = CleReseau.commande(alea: CleReseau.alea())
        #expect(PolitiqueCommandes.masquerCle(c) == "json cle nouvelle ••••••••")
        #expect(PolitiqueCommandes.masquerCle("id=5 " + CleReseau.commande(alea: CleInventee.octets))
                == "id=5 json cle nouvelle ••••••••")
        #expect(PolitiqueCommandes.masquerCle("JSON  Cle nouvelle " + CleInventee.hexa.lowercased())
                == "JSON  Cle nouvelle ••••••••")
        #expect(PolitiqueCommandes.masquerCle("json \"cle\" \"nouvelle\" \"\(CleInventee.hexa)\"")
                == "json \"cle\" \"nouvelle\" ••••••••")
        #expect(PolitiqueCommandes.masquerCle("json cle nouvelle 0011") == "json cle nouvelle ••••••••",
                "un alea court aussi")
        #expect(PolitiqueCommandes.masquerCle("‹ id=5 « json cle nouvelle » : ok (12 ms)")
                == "‹ id=5 « json cle nouvelle » : ok (12 ms)", "la commande citee par le pont ne porte rien")
        // Le suivi d'une commande secrete n'en garde que le masque.
        var c2 = Correlateur()
        let a = c2.soumettre(c, origine: .interface, secret: PolitiqueCommandes.masquerCle(c) != c, maintenant: 0)
        #expect(c2.suivi(a)?.commande == "json cle nouvelle ••••••••")
    }

    @Test func champCleDUneReponse() {
        let m = PolitiqueCommandes.masquerCle(CleInventee.reponse)
        #expect(!CleInventee.fuit(m))
        #expect(m.contains(#""cle":"••••••••","empreinte":"CA2A4FE7""#), "l'empreinte reste visible")
        #expect(PolitiqueCommandes.masquerCle(#"{"v":1,"t":"reseau","n":1,"bloc":"ip","srp":"1A2B3C4D5E6F7081","udp":{"cle":true,"empreinte":"CA2A4FE7"}}"#)
                == #"{"v":1,"t":"reseau","n":1,"bloc":"ip","srp":"1A2B3C4D5E6F7081","udp":{"cle":true,"empreinte":"CA2A4FE7"}}"#,
                "le bloc ip ne porte pas la cle : intact")
    }

    @Test func ligneMachineSansCle() throws {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(CleInventee.reponse))
        guard case .machine(let l) = try #require(e.first) else {
            Issue.record("ligne machine attendue")
            return
        }
        guard case .reponse(let brute) = l.message else { Issue.record("reponse attendue"); return }
        #expect(brute.cle == CleInventee.hexa, "decodee, la cle est la (pour le trousseau)")
        let propre = l.sansCle
        #expect(!CleInventee.fuit(propre.json))
        #expect(!CleInventee.fuit(String(describing: propre)))
        guard case .reponse(let rep) = propre.message else { Issue.record("reponse attendue"); return }
        #expect(rep.cle == nil && rep.empreinte == "CA2A4FE7")
        #expect(propre.enveloppe == l.enveloppe)
        #expect(!CleInventee.fuit(String(describing: l.message.sansCle)))
        #expect(!CleInventee.fuit(String(describing: try #require(e.first).sansCle)))
        // Une ligne sans cle passe telle quelle.
        let autre = r.alimenter(ligneMachine(#"{"v":1,"t":"hb","n":61,"ms":1,"boot":"3FA2C901","up_s":1,"json_perdus":0,"commande":null}"#))
        if case .machine(let h) = autre.first { #expect(h.sansCle == h) } else { Issue.record("hb attendu") }
    }

    /// La reponse coupee en deux a chaque octet (un LF perdu au milieu) : la premiere
    /// part est abimee, la seconde un fragment ; ou le debut perdu : un texte seul.
    @Test func ligneCoupeeAChaqueOctet() {
        let json = Array(CleInventee.reponse.utf8)
        for k in 1..<json.count {
            var r = RecepteurLignes()
            let coupee = r.alimenter([Octets.rs] + json[..<k] + [Octets.lf] + json[k...] + [Octets.lf])
            var seule = RecepteurLignes()
            let finSeule = seule.alimenter(Array(json[k...]) + [Octets.lf])
            for e in coupee + finSeule {
                let vu = String(describing: e.sansCle)
                #expect(!CleInventee.fuit(vu), "coupe a \(k) : \(vu)")
            }
        }
    }

    /// Un journal intercale au milieu de la ligne, sans LF : une seule ligne abimee.
    @Test func journalIntercale() {
        let json = Array(CleInventee.reponse.utf8)
        let journal = Array("E (12345) wifi: cafe".utf8)
        for k in 1..<json.count {
            var r = RecepteurLignes()
            for e in r.alimenter([Octets.rs] + json[..<k] + journal + json[k...] + [Octets.lf]) {
                let vu = String(describing: e.sansCle)
                #expect(!CleInventee.fuit(vu), "journal a \(k) : \(vu)")
            }
        }
    }

    @Test func debordement() {
        var r = RecepteurLignes()
        let long = Array(String(repeating: "x", count: 2100).utf8) + Array(CleInventee.reponse.utf8)
        let e = r.alimenter(long)
        #expect(!e.isEmpty)
        for x in e { #expect(!CleInventee.fuit(String(describing: x.sansCle))) }
    }

    /// Cles du Mesh inventees, et les memes ecrites avec un `\x` tous les 4 hexa : la console
    /// du pont oublie chaque barre oblique inverse et l'octet qui la suit (split_argv.c).
    static let k1 = "404142434445464748494A4B4C4D4E4F"
    static let k2 = "505152535455565758595A5B5C5D5E5F"
    static func echappee(_ k: String) -> String {
        stride(from: 0, to: k.count, by: 4).map { i in
            String(k.dropFirst(i).prefix(4))
        }.joined(separator: #"\x"#)
    }

    /// Vrai si un morceau de 6 hexa d'une cle se lit encore dans le texte, une fois decoupe
    /// comme le pont le decoupe (echappements et guillemets retires).
    static func fuiteLue(_ texte: String, _ cles: [String]) -> Bool {
        let lu = LigneCommande.arguments(Array(texte.utf8)).map { String(decoding: $0.valeur, as: UTF8.self) }
            .joined().uppercased()
        return cles.contains { cle in
            let h = Array(cle.uppercased())
            return (0...(h.count - 6)).contains { lu.contains(String(h[$0..<($0 + 6)])) }
        }
    }

    /// Relecture (reste du rapport) : guillemets et echappements que la console du pont
    /// retire ne cachent aucune cle au masque, ni dans la commande, ni la ou elle est citee
    /// (journal des envois, echo de la console, citation de l'app).
    @Test func echappementsEtGuillemetsNeCachentPasLaCle() {
        let (k1, k2) = (Self.k1, Self.k2)
        let (e1, e2) = (Self.echappee(k1), Self.echappee(k2))
        #expect(e1 == #"4041\x4243\x4445\x4647\x4849\x4A4B\x4C4D\x4E4F"#)
        #expect(LigneCommande.argv("mesh cles \(e1) \(e2)") == ["mesh", "cles", k1, k2], "le pont lit bien les cles")
        let cas: [(String, String)] = [
            ("mesh cles \(e1) \(e2)", "mesh cles •••••••• ••••••••"),
            (#"mesh cles "\#(k1)" "\#(k2)""#, "mesh cles •••••••• ••••••••"),
            (#"mesh cles "\#(e1)" \#(k2)"#, "mesh cles •••••••• ••••••••"),
            (#"me\xsh c\xles \#(k1) \#(k2)"#, #"me\xsh c\xles •••••••• ••••••••"#),
            (#""mesh" "cles" "\#(e1)" "\#(e2)""#, #""mesh" "cles" •••••••• ••••••••"#),
            (#""mesh cles \#(k1) \#(k2)""#, "mesh cles •••••••• ••••••••"),
            (#"mesh\ cles \#(e1) \#(e2)"#, #"mesh\ cles •••••••• ••••••••"#),
            ("json cle nouvelle \(e1)\(e2)", "json cle nouvelle ••••••••"),
            (#"js\xon cle nouvelle "\#(k1)\#(k2)""#, #"js\xon cle nouvelle ••••••••"#),
            ("› id=12 mesh cles \(e1) \(e2)", "› id=12 mesh cles •••••••• ••••••••"),
            ("› mesh cles \(e1) \(e2)", "› mesh cles •••••••• ••••••••"),
            ("amaran> mesh cles \(e1) \(e2)", "amaran> mesh cles •••••••• ••••••••"),
            // Un `»` tape n'arrete pas le masque : seule une citation de l'app (apres `«`) finit a `»`.
            ("mesh cles » \(e1) \(e2)", "mesh cles •••••••• •••••••• ••••••••"),
            ("› id=2 mesh cles » \(e1) \(e2)", "› id=2 mesh cles •••••••• •••••••• ••••••••"),
            ("json cle nouvelle » \(e1)\(e2)", "json cle nouvelle •••••••• ••••••••"),
            ("« mesh cles \(e1) \(e2) » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).",
             "« mesh cles •••••••• •••••••• » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »)."),
        ]
        for (ligne, attendue) in cas {
            let m = PolitiqueCommandes.masquerCle(ligne)
            #expect(m == attendue, "\(ligne)")
            #expect(!Self.fuiteLue(m, [k1, k2]), "\(ligne) -> \(m)")
            #expect(PolitiqueCommandes.masquerCle(m) == m, "le masque est stable : \(m)")
            #expect(!Self.fuiteLue(PolitiqueCommandes.masquerCleStricte(ligne), [k1, k2]), "\(ligne)")
            #expect(!Self.fuiteLue(String(describing: ElementRecu.texte(ClasseurTexte.classer(ligne)).sansCle), [k1, k2]),
                    "texte recu du pont (echo) : \(ligne)")
        }
    }

    /// La regle ne masque que la commande : le texte d'usage du pont, une commande citee sans
    /// argument, ou toute autre commande, restent tels quels.
    @Test func lesAutresTextesRestentLisibles() {
        for t in ["erreur : mesh cles <reseau 32 hexa> <application 32 hexa>",
                  "‹ id=5 « json cle » : arguments invalides — json cle nouvelle <64 hexa> | json cle efface (0 ms)",
                  "‹ id=12 « mesh cles » : ok (12 ms)", "ok cles 1A2B3C4D 5E6F7A8B (redemarrer pour les appliquer)",
                  "mesh cles", "json cle efface", "json cle nouvelle", "mesh lampes 2", #""mesh lampe" 1 masquer"#,
                  "lampe 1 on", #"re\xdemarre"#, "etat ; mesh cles|lampes|lampe|iv|adresse|oublie ... ; "] {
            #expect(PolitiqueCommandes.masquerCle(t) == t, "\(t)")
        }
    }

    /// Le suivi d'une commande dont le masque change ne garde que le masque, meme si
    /// l'appelant ne l'a pas dite secrete ; la ligne envoyee, elle, porte les cles.
    @Test func leSuiviNeGardeJamaisLaCle() throws {
        let ligne = "mesh cles \(Self.echappee(Self.k1)) \(Self.echappee(Self.k2))"
        var c = Correlateur()
        let a = c.soumettre(ligne, origine: .console, maintenant: 0)
        #expect(c.suivi(a)?.commande == "mesh cles •••••••• ••••••••")
        let envoi = c.prochainEnvoi(maintenant: 0)
        let p = try #require(envoi)
        #expect(texte(p.octets) == "id=1 " + ligne + "\n", "le pont recoit la ligne telle quelle")
        #expect(!c.suivis.contains { Self.fuiteLue($0.commande, [Self.k1, Self.k2]) })
    }

    @Test func strictNeTouchePasAuTexteOrdinaire() {
        // Le texte d'une commande garde son nom SRP (16 hexa) et ses empreintes.
        let t = "srp : 1A2B3C4D5E6F7081, cle CA2A4FE7"
        #expect(PolitiqueCommandes.masquerCle(t) == t)
        let e = ElementRecu.texte(ClasseurTexte.classer(t))
        #expect(e.sansCle == e)
        // Les cles du Mesh (32 hexa) restent masquees partout.
        let mesh = "mesh cles 00112233445566778899aabbccddeeff ffeeddccbbaa99887766554433221100"
        #expect(PolitiqueCommandes.masquerCle(mesh) == "mesh cles •••••••• ••••••••")
        #expect(PolitiqueCommandes.masquerCleStricte(mesh) == "mesh cles •••••••• ••••••••")
    }
}
````

`apps/macos/AmaranProtocoleTests/ReseauSessionTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (HaloProtocoleTests/ReseauSessionTests.swift) : les regles du
// reseau (docs/PROTOCOLE-JSON.md 10.4, 10.5) pour le pont amaran : json 1 avec un bail
// permis a distance, texte en messages `texte`, reponse `deja_traite` (reponse oubliee),
// `ordre` arrive sans son `accepte`.
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Correlation a distance (10.4)")
struct CorrelationReseauTests {
    @Test func renvoisDuMemeIdPuisSansReponse() throws {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let p = c.prochainEnvoi(maintenant: 0)
        let e = try #require(p)
        #expect(texte(e.octets) == "id=1 lampe 1 on\n")
        #expect(c.renvoisDus(maintenant: 1.9).isEmpty)
        #expect(c.renvoisDus(maintenant: 2.0).map(texte) == ["id=1 lampe 1 on\n"])
        #expect(c.renvoisDus(maintenant: 3.9).isEmpty)
        #expect(c.renvoisDus(maintenant: 4.0).map(texte) == ["id=1 lampe 1 on\n"])
        #expect(c.renvoisDus(maintenant: 5.9).isEmpty, "deux renvois au plus")
        #expect(c.verifierDelais(maintenant: 5.9).isEmpty)
        #expect(c.verifierDelais(maintenant: 6.0).map(\.id) == [a])
        #expect(c.suivi(a)?.etat == .sansReponse)
        #expect(c.suivi(a)?.renvois == 2)
    }

    @Test func reponseArreteLesRenvoisEtDoublonIgnore() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("json ping", origine: .session, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.renvoisDus(maintenant: 2)
        #expect(c.recevoir(reponse(1), maintenant: 2.3) == .fin(a, ordreAttendu: false))
        #expect(c.renvoisDus(maintenant: 4).isEmpty)
        #expect(c.recevoir(reponse(1), maintenant: 2.4) == .inattendue, "reponse rendue de nouveau par le pont : ignoree")
    }

    /// Un renvoi croise la reponse `accepte` : le pont rend la reponse gardee, sans
    /// executer l'ordre une seconde fois. Le doublon ne relance pas l'attente de l'ordre.
    @Test func doublonDAccepteSansEffet() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 2 niveau 300", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.renvoisDus(maintenant: 2)
        let accepte = reponse(1, code: .accepte, suite: .ordre, lampe: 2)
        #expect(c.recevoir(accepte, maintenant: 2.1) == .fin(a, ordreAttendu: true))
        #expect(c.recevoir(accepte, maintenant: 2.2) == .inattendue)
        #expect(c.suivi(a)?.termineeA == 2.1)
        #expect(c.verifierOrdres(maintenant: 12.1).map(\.id) == [a], "l'ordre garde son delai de 10 s")
    }

    static let dejaTraite = Reponse(id: 1, etape: .fin, cmd: "lampe 1 on", ok: false, code: .dejaTraite,
                                    msg: "id deja traite : reponse oubliee", dureeMs: 0)

    /// `deja_traite` (10.4) : le pont a oublie la reponse de cet `id`, la vraie ne viendra
    /// jamais (le renvoi d'un `id` encore en cours, lui, est ignore en silence). Le suivi
    /// se clot comme sur une `fin`, la place en vol se libere, plus aucun renvoi.
    @Test func dejaTraiteClotLeSuivi() throws {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let b = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.renvoisDus(maintenant: 2).count == 1)
        #expect(c.recevoir(Self.dejaTraite, maintenant: 2.2) == .fin(a, ordreAttendu: false))
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.fin?.code == .dejaTraite)
        #expect(c.enVol == nil, "la file repart : aucune autre reponse ne viendra pour cet id")
        #expect(c.renvoisDus(maintenant: 2.25).isEmpty, "plus de renvoi")
        let p = c.prochainEnvoi(maintenant: 2.3)
        #expect(try #require(p).id == b, "la commande suivante part aussitot")
        #expect(c.recevoir(Self.dejaTraite, maintenant: 2.4) == .inattendue, "un second deja_traite : ignore")
        _ = c.verifierDelais(maintenant: 8.3)
        #expect(c.suivi(a)?.etat == .terminee, "jamais « sans reponse » ensuite")
    }

    /// Un `deja_traite` qui arrive apres le verdict « sans reponse » clot aussi le suivi.
    @Test func dejaTraiteApresSansReponseClotLeSuivi() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("json ping", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.verifierDelais(maintenant: 6)
        #expect(c.suivi(a)?.etat == .sansReponse)
        let deja = Reponse(id: 1, etape: .fin, ok: false, code: .dejaTraite)
        #expect(c.recevoir(deja, maintenant: 6.5) == .fin(a, ordreAttendu: false))
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.fin?.code == .dejaTraite)
    }

    /// Une reponse `accepte` perdue sur Thread : l'evenement `ordre` qui porte l'`id` prouve
    /// l'acceptation. Il finit la commande encore `envoyee` et libere la place en vol ; la
    /// reponse gardee, rendue plus tard a un renvoi qui a croise l'evenement, est ignoree.
    @Test func ordreSansAccepteFinitLaCommande() throws {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let b = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(ordre(lampe: 1, .confirme, ids: [1]), maintenant: 0.4) == [a])
        #expect(c.suivi(a)?.etat == .confirmee)
        #expect(c.suivi(a)?.lampe == 1)
        #expect(c.enVol == nil)
        #expect(c.renvoisDus(maintenant: 2).isEmpty, "rien a renvoyer")
        let p = c.prochainEnvoi(maintenant: 0.5)
        #expect(try #require(p).id == b)
        #expect(c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 2.1) == .inattendue)
        #expect(c.suivi(a)?.etat == .confirmee)
        #expect(c.verifierOrdres(maintenant: 12.5).isEmpty, "jamais « issue perdue »")
        // Un evenement ne finit que les commandes dont il porte l'id.
        #expect(c.recevoir(ordre(lampe: 2, .abandon, ids: [7]), maintenant: 3).isEmpty)
        #expect(c.suivi(b)?.etat == .envoyee)
    }

    /// Meme chose apres le verdict « sans reponse » : l'evenement donne la vraie issue.
    @Test func ordreApresSansReponseFinitLaCommande() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampe 3 niveau 200", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.verifierDelais(maintenant: 6)
        #expect(c.suivi(a)?.etat == .sansReponse)
        #expect(c.recevoir(ordre(lampe: 3, .abandon, ids: [1]), maintenant: 6.2) == [a])
        #expect(c.suivi(a)?.etat == .abandonnee)
        #expect(c.suivi(a)?.ordre?.issue == .abandon)
    }

    /// Le texte d'une commande a distance arrive en messages `texte` qui portent son id.
    @Test func texteADistanceRattacheParId() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 0.1) == .debut(a))
        #expect(c.texte("mesh pret : oui", id: 1, maintenant: 0.2) == a)
        #expect(c.texte("autre commande", id: 7, maintenant: 0.2) == nil, "id inconnu : ignore")
        _ = c.recevoir(reponse(1), maintenant: 0.3)
        #expect(c.suivi(a)?.texte == ["mesh pret : oui"])
        #expect(c.texte("apres la fin", id: 1, maintenant: 0.4) == nil)
    }

    /// `debut` perdu : le premier `texte` en tient lieu. Le pont execute la commande :
    /// ni renvoi (il l'ignorerait : la commande est en cours), ni "sans reponse".
    @Test func texteSansDebutTientLieuDeDebut() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("lampes", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.texte("lampe 1 : Lampe bureau", id: 1, maintenant: 0.5) == a)
        #expect(c.suivi(a)?.etat == .enCours)
        #expect(c.suivi(a)?.debutA == 0.5)
        #expect(c.renvoisDus(maintenant: 2).isEmpty)
        #expect(c.verifierDelais(maintenant: 6).isEmpty)
        #expect(c.commandeDeBanc?.id == a)
        _ = c.recevoir(reponse(1), maintenant: 6.5)
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.suivi(a)?.texte == ["lampe 1 : Lampe bureau"])
    }

    @Test func texteTardifApresSansReponse() {
        var c = Correlateur()
        c.politique = .reseau
        let a = c.soumettre("taches", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.verifierDelais(maintenant: 6)
        #expect(c.texte("json 1460", id: 1, maintenant: 7) == a)
        #expect(c.suivi(a)?.etat == .enCours, "comme un debut tardif : la commande tourne")
        #expect(c.suivi(a)?.termineeA == nil)
    }

    /// La ligne d'une commande secrete est oubliee des son envoi : elle ne repart jamais
    /// (le masque partirait a sa place).
    @Test func commandeSecreteJamaisRenvoyee() throws {
        var c = Correlateur()
        c.politique = .reseau
        let cles = "mesh cles 404142434445464748494A4B4C4D4E4F 505152535455565758595A5B5C5D5E5F"
        _ = c.soumettre(cles, origine: .interface, secret: true, maintenant: 0)
        let p = c.prochainEnvoi(maintenant: 0)
        #expect(try #require(p).numero == 1)
        #expect(c.renvoisDus(maintenant: 2).isEmpty)
        #expect(c.renvoisDus(maintenant: 4).isEmpty)
    }

    @Test func usbSansRenvoi() {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.renvoisDus(maintenant: 2.5).isEmpty)
        #expect(c.verifierDelais(maintenant: 3).map(\.id) == [a])
    }

    @Test func politiques() {
        #expect(PolitiqueDelais.pour(.udp) == .reseau)
        #expect(PolitiqueDelais.pour(.usb) == .usb)
        #expect(PolitiqueDelais.pour(.demo) == .usb)
        #expect(PolitiqueDelais.reseau.delaiOrdre == PolitiqueDelais.usb.delaiOrdre, "les ordres gardent leur delai")
        #expect(PolitiqueDelais.reseau.delaiInstantane == 12)
        #expect(MoteurSession.Parametres().delaiFinJson1Reseau == PolitiqueDelais.reseau.delaiInstantane,
                "json 1, json etat et json hello : meme attente a distance")
        #expect(PolitiqueDelais.usb.delaiReponse(pour: "json etat") == 3, "par l'USB, l'instantane part en moins d'une demi-seconde")
    }

    /// `json 1`, `json etat`, `json hello` : leur `fin` suit l'instantane (6.2), lu comme le
    /// pont decoupe la ligne ; aucune autre commande.
    @Test func commandesQuiRepondentApresLInstantane() {
        for c in ["json etat", "json hello", "json 1", "json 1 bail 60", #""json" etat"#, #"js\xon hello"#, "  json etat  "] {
            #expect(PolitiqueCommandes.repondApresInstantane(c), "\(c)")
        }
        for c in ["json ping", "json etat x", "json", "lampe 1 on", "JSON etat", "json trames 1", "mesh"] {
            #expect(!PolitiqueCommandes.repondApresInstantane(c), "\(c)")
        }
    }

    /// A distance, la `fin` de `json etat` part apres l'instantane : attendue 12 s, comme
    /// celle du `json 1`. Les renvois du meme `id` a 2 s et 4 s restent (le pont ignore le
    /// renvoi d'un `id` encore en cours). Une autre commande garde ses 6 s.
    @Test func instantaneAttenduDouzeSecondesADistance() {
        for commande in ["json etat", "json hello", "json 1 bail 60"] {
            var c = Correlateur()
            c.politique = .reseau
            let a = c.soumettre(commande, origine: .console, maintenant: 0)
            _ = c.prochainEnvoi(maintenant: 0)
            #expect(c.renvoisDus(maintenant: 2).count == 1, "\(commande) : renvoi a 2 s")
            #expect(c.renvoisDus(maintenant: 4).count == 1, "\(commande) : renvoi a 4 s")
            #expect(c.verifierDelais(maintenant: 6).isEmpty, "\(commande) : pas « sans reponse » a 6 s")
            #expect(c.verifierDelais(maintenant: 11.9).isEmpty)
            #expect(c.verifierDelais(maintenant: 12).map(\.id) == [a], "\(commande) : « sans reponse » a 12 s")
        }
        var autre = Correlateur()
        autre.politique = .reseau
        let b = autre.soumettre("lampes", origine: .console, maintenant: 0)
        _ = autre.prochainEnvoi(maintenant: 0)
        #expect(autre.verifierDelais(maintenant: 6).map(\.id) == [b], "une lecture garde ses 6 s")
        var usb = Correlateur()
        let u = usb.soumettre("json etat", origine: .interface, maintenant: 0)
        _ = usb.prochainEnvoi(maintenant: 0)
        #expect(usb.verifierDelais(maintenant: 3).map(\.id) == [u], "USB : inchange, 3 s")
    }
}

@Suite("Session par le reseau (10.4, 10.5)")
struct ReseauSessionTests {
    typealias M = MoteurSessionTests

    static let helloDistant = #"{"v":1,"t":"hello","n":0,"ms":900120,"bloc":"base","rev":1,"boot":"3FA2C901","up_s":900,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false}}"#

    static func finJson1(_ id: Int = 1, n: Int = 11, code: String = "ok") -> ElementRecu {
        let ok = code == "ok" ? "true" : "false"
        return M.element(#"{"v":1,"t":"reponse","n":\#(n),"ms":900200,"id":\#(id),"etape":"fin","cmd":"json 1 bail 60","ok":\#(ok),"code":"\#(code)","duree_ms":80,"bail_s":60,"up_s":900}"#)
    }

    static func connecte() -> MoteurSession {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(M.element(helloDistant), maintenant: 0.1)
        _ = m.recu(finJson1(), maintenant: 0.2)
        return m
    }

    @Test func ouvertureReseauSansCtrlUAvecUnBailPermis() {
        var m = MoteurSession()
        #expect(M.envois(m.ouvert(maintenant: 0, genre: .udp)) == ["id=1 json 1 bail 60\n"])
        #expect(PolitiqueCommandes.autoriseeADistance("json 1 bail 60") == nil)
        #expect(m.correlateur.politique == .reseau)
        #expect(m.genre == .udp)
        #expect(m.reglages == HelloBase.ReglagesSession(transport: .udp, periodeMs: 2000, lampesMs: 30000, compteursMs: 0,
                                                        reseauMs: 30000, bailS: 60, log: false, trames: false),
                "profil distant (10.5) avant le hello")
        var u = MoteurSession()
        #expect(M.envois(u.ouvert(maintenant: 0)) == ["\u{15}\n", "id=1 json 1\n"])
        #expect(u.correlateur.politique == .usb)
        #expect(u.reglages.transport == .usb && u.reglages.periodeMs == 1000)
    }

    @Test func bailDistantToujoursDansLesBornes() {
        for (demande, attendu) in [(0, 10), (5, 10), (60, 60), (120, 120), (600, 120)] {
            var m = MoteurSession()
            m.parametres.bailDistantS = demande
            #expect(M.envois(m.ouvert(maintenant: 0, genre: .udp)) == ["id=1 json 1 bail \(attendu)\n"])
            #expect(PolitiqueCommandes.autoriseeADistance(m.ligneJson1) == nil)
        }
    }

    @Test func sessionDistanteEtablie() {
        var m = Self.connecte()
        #expect(m.phase == .connecte)
        #expect(!m.instantaneEnCours)
        #expect(m.bailS == 60)
        #expect(m.reglages.transport == .udp)
        let (_, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.3)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
    }

    @Test func json1RenvoyeAvecLeMemeIdADistance() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        #expect(M.envois(m.tic(maintenant: 2.0)) == ["id=1 json 1 bail 60\n"], "le pont ne refait pas l'instantane")
        var u = MoteurSession()
        _ = u.ouvert(maintenant: 0)
        #expect(M.envois(u.tic(maintenant: 2.0)) == ["id=2 json 1\n"], "USB : inchange")
    }

    /// `deja_traite` au json 1, avant le hello : la reponse est oubliee (10.4), le meme id
    /// ne rendrait plus rien. Le renvoi suivant prend un id neuf, pour un nouvel instantane.
    @Test func json1DejaTraiteRepartAvecUnIdNeuf() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        #expect(M.envois(m.tic(maintenant: 2.0)) == ["id=1 json 1 bail 60\n"], "renvoi du meme id")
        _ = m.recu(Self.finJson1(code: "deja_traite"), maintenant: 2.5)
        #expect(m.phase == .attenteHello(essai: 2))
        #expect(M.envois(m.tic(maintenant: 4.0)) == ["id=2 json 1 bail 60\n"], "id neuf")
        #expect(M.envois(m.tic(maintenant: 6.0)) == ["id=2 json 1 bail 60\n"], "puis ce nouvel id est renvoye tel quel")
    }

    /// Apres le hello, `deja_traite` au json 1 est sa fin : la file repart, sans attendre
    /// les 12 s du verdict « reponse au json 1 perdue ».
    @Test func json1DejaTraiteApresLeHelloLibereLaFile() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 0.5)
        let (_, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.6)
        #expect(M.envois(e).isEmpty, "l'instantane d'abord")
        #expect(M.envois(m.recu(Self.finJson1(code: "deja_traite"), maintenant: 2.5)) == ["id=2 lampe 1 on\n"])
        #expect(!m.instantaneEnCours)
        #expect(!m.tic(maintenant: 12.5).contains(.note(.reponseJson1Perdue)))
    }

    /// Reste du rapport : un `json etat` a distance dont la `fin` arrive 8 s apres l'envoi
    /// (deux instantanes de 16 lampes en meme temps) est conclu « ok », sans verdict « sans
    /// reponse » ni second `json etat`.
    @Test func jsonEtatADistanceAttendSonInstantane() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("json etat", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 json etat\n"])
        var effets: [MoteurSession.Effet] = []
        var t = 1.0
        while t < 9 {
            t += 0.25
            if Int(t * 4) % 6 == 0 { _ = m.recu(M.element(Self.helloDistant), maintenant: t) }  // l'instantane arrive
            effets += m.tic(maintenant: t)
        }
        #expect(M.envois(effets) == ["id=2 json etat\n", "id=2 json etat\n"], "renvois du meme id a 2 s et 4 s, rien d'autre")
        #expect(!effets.contains(.commandeSansReponse(a)))
        effets += m.recu(M.element(#"{"v":1,"t":"reponse","n":90,"ms":908000,"id":2,"etape":"fin","cmd":"json etat","ok":true,"code":"ok","duree_ms":7900}"#), maintenant: 9)
        effets += m.tic(maintenant: 9.25)
        #expect(m.correlateur.suivi(a)?.etat == .terminee)
        #expect(m.correlateur.suivi(a)?.fin?.code == .ok)
        #expect(!effets.contains(.commandeSansReponse(a)))
        #expect(M.envois(effets).filter { $0.hasSuffix(" json etat\n") }.count == 2, "pas de second json etat")
        #expect(m.statistiques.sansReponse == 0)
    }

    /// `deja_traite` d'une commande : sa reponse est oubliee, l'etat a pu changer sans que
    /// l'app le voie ; le moteur demande un instantane, comme Halo.
    @Test func dejaTraiteDemandeUnEtat() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
        _ = m.recu(M.element(Self.helloDistant), maintenant: 2.5)
        #expect(M.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"])
        let deja = M.element(#"{"v":1,"t":"reponse","n":40,"ms":912010,"id":2,"etape":"fin","cmd":"lampe 1 on","ok":false,"code":"deja_traite","msg":"id deja traite : reponse oubliee","duree_ms":0}"#)
        #expect(M.envois(m.recu(deja, maintenant: 3.2)) == ["id=3 json etat\n"])
        #expect(m.correlateur.suivi(a)?.etat == .terminee)
        #expect(m.correlateur.suivi(a)?.fin?.code == .dejaTraite)
    }

    /// Scenario de la relecture : `accepte` perdu, `ordre` (confirme) a 1,4 s. La commande
    /// est confirmee aussitot, la place en vol libre ; ni renvoi, ni « issue perdue », meme
    /// si l'`accepte` garde par le pont arrive ensuite (rendu a un renvoi qui a croise).
    @Test func ordreSansAccepteJamaisPerdu() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
        let ordre = M.element(#"{"v":1,"t":"ordre","n":20,"ms":901400,"lampe":1,"issue":"confirme","delai_ms":350,"essai":1,"ids":[2],"ids_perdus":0}"#)
        _ = m.recu(ordre, maintenant: 1.4)
        #expect(m.correlateur.suivi(a)?.etat == .confirmee)
        var t = 1.4
        var envois: [String] = []
        var effets: [MoteurSession.Effet] = []
        while t < 14 {
            t += 0.25
            if Int(t * 4) % 6 == 0 { _ = m.recu(M.element(Self.helloDistant), maintenant: t) }  // pas de silence
            if abs(t - 3.4) < 0.01 {
                // L'accepte garde, rendu a un renvoi : ignore.
                _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":21,"ms":903300,"id":2,"etape":"fin","cmd":"lampe 1 on","ok":true,"code":"accepte","duree_ms":0,"suite":"ordre","lampe":1}"#), maintenant: t)
            }
            let x = m.tic(maintenant: t)
            effets += x
            envois += M.envois(x)
        }
        #expect(!envois.contains("id=2 lampe 1 on\n"), "aucun renvoi : la commande est finie")
        #expect(!effets.contains(.ordrePerdu(a)))
        #expect(!effets.contains(.commandeSansReponse(a)))
        #expect(m.correlateur.suivi(a)?.etat == .confirmee)
    }

    /// Variante : l'`ordre` arrive apres le renvoi de 2 s, dont l'`accepte` se perd aussi.
    @Test func ordreApresLeRenvoiFinitLaCommande() {
        var m = Self.connecte()
        let (a, _) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 2.5)
        #expect(M.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"])
        _ = m.recu(M.element(#"{"v":1,"t":"ordre","n":20,"ms":903200,"lampe":1,"issue":"abandon","delai_ms":3100,"essai":3,"ids":[2],"ids_perdus":0}"#), maintenant: 3.2)
        #expect(m.correlateur.suivi(a)?.etat == .abandonnee)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 4.5)
        #expect(M.envois(m.tic(maintenant: 5.0)).isEmpty, "plus de renvoi a 4 s")
    }

    /// Hello perdu, `fin` recue : renvoyer le meme id ne rendrait que la reponse gardee,
    /// sans instantane. Le renvoi suivant prend un id neuf.
    @Test func finSansHelloRenvoiAvecUnIdNeuf() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(Self.finJson1(), maintenant: 1)
        #expect(m.phase == .attenteHello(essai: 1))
        #expect(M.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1 bail 60\n"])
        #expect(M.envois(m.tic(maintenant: 4.0)) == ["id=2 json 1 bail 60\n"])
    }

    /// Sans `hello`, a distance : le pont n'a ouvert qu'une session H1 provisoire,
    /// oubliee 30 s apres le SALUT (10.3). La relance de 30 s est donc une nouvelle
    /// poignee de main (`.rouvrir`), jamais un `json 1` scelle pour une session que le
    /// pont ne connait plus.
    @Test func sansHelloADistanceRouvreApres30s() {
        var m = MoteurSession()
        #expect(M.envois(m.ouvert(maintenant: 0, genre: .udp)) == ["id=1 json 1 bail 60\n"])
        for t in [2.0, 4.0, 6.0] {
            #expect(M.envois(m.tic(maintenant: t)) == ["id=1 json 1 bail 60\n"], "renvoi du meme id a \(t) s")
        }
        let e8 = m.tic(maintenant: 8.0)
        #expect(m.phase == .sansReponse)
        #expect(e8 == [.note(.aucuneReponse)])
        #expect(m.tic(maintenant: 35.9).isEmpty)
        let e36 = m.tic(maintenant: 36.0)
        #expect(e36 == [.rouvrir(.reseauSansHello)], "nouvelle poignee de main, aucun json 1")
        #expect(!MoteurSession.Note.reseauSansHello.grave, "note de console, pas de bandeau de plus")
        #expect(m.statistiques.reouvertures == 1)
        #expect(m.tic(maintenant: 36.25).isEmpty, "pas de second .rouvrir avant la fermeture")
        m.ferme(maintenant: 36.5)
        #expect(M.envois(m.ouvert(maintenant: 37, genre: .udp)) == ["id=2 json 1 bail 60\n"])
        #expect(m.phase == .attenteHello(essai: 1))
    }

    @Test func sansHelloParUSBEtDemoInchange() {
        for genre in [GenreTransport.usb, .demo] {
            var u = MoteurSession()
            _ = u.ouvert(maintenant: 0, genre: genre)
            for t in [2.0, 4.0, 6.0, 8.0] { _ = u.tic(maintenant: t) }
            #expect(u.phase == .sansReponse)
            let e = u.tic(maintenant: 36.0)
            #expect(e == [.envoyer(LigneCommande.effacement), .envoyer(Data("id=5 json 1\n".utf8))],
                    "\(genre) : Ctrl-U et json 1 d'un id neuf, sur le meme port")
            #expect(u.statistiques.reouvertures == 0)
        }
    }

    @Test func reessayerADistanceRouvre() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        for t in [2.0, 4.0, 6.0, 8.0] { _ = m.tic(maintenant: t) }
        #expect(m.reessayer(maintenant: 10) == [.rouvrir(.reseauSansHello)])
        #expect(m.tic(maintenant: 36).isEmpty, "la relance de 30 s repart de cet essai")
    }

    @Test func finDuJson1AttendPlusLongtempsADistance() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0, genre: .udp)
        _ = m.recu(M.element(Self.helloDistant), maintenant: 0.3)
        #expect(!m.tic(maintenant: 3.5).contains(.note(.reponseJson1Perdue)), "instantane de ~11 Ko sur Thread")
        #expect(m.instantaneEnCours)
        for t in stride(from: 2.0, through: 11.0, by: 1.5) {
            _ = m.recu(M.element(Self.helloDistant), maintenant: t)  // le pont parle : pas de silence
        }
        #expect(!m.tic(maintenant: 11.9).contains(.note(.reponseJson1Perdue)))
        #expect(m.tic(maintenant: 12.0).contains(.note(.reponseJson1Perdue)))
    }

    @Test func renvoiDUneCommandeParLeTic() {
        var m = Self.connecte()
        let (a, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 1)
        #expect(M.envois(e) == ["id=2 lampe 1 on\n"])
        _ = m.recu(M.element(Self.helloDistant), maintenant: 2.5)
        #expect(M.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"], "meme id, a 2 s")
        _ = m.recu(M.element(Self.helloDistant), maintenant: 4.5)
        #expect(M.envois(m.tic(maintenant: 5.0)) == ["id=2 lampe 1 on\n"], "puis a 4 s")
        _ = m.recu(M.element(Self.helloDistant), maintenant: 6.5)
        let e7 = m.tic(maintenant: 7.0)
        #expect(e7.contains(.commandeSansReponse(a)), "sans reponse a 6 s")
        #expect(M.envois(e7) == ["id=3 json etat\n"])
    }

    @Test func texteRattacheParLeMoteur() {
        var m = Self.connecte()
        let (a, _) = m.soumettre("lampe 1", origine: .console, maintenant: 1)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":20,"ms":913000,"id":2,"etape":"debut","cmd":"lampe 1","ok":true,"code":"en_cours"}"#), maintenant: 1.1)
        _ = m.recu(M.element(#"{"v":1,"t":"texte","n":21,"ms":913004,"id":2,"txt":"lampe 1 : Lampe bureau"}"#), maintenant: 1.2)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":22,"ms":913006,"id":2,"etape":"fin","cmd":"lampe 1","ok":true,"code":"ok","duree_ms":6}"#), maintenant: 1.3)
        #expect(m.correlateur.suivi(a)?.texte == ["lampe 1 : Lampe bureau"])
        #expect(m.correlateur.suivi(a)?.etat == .terminee)
    }

    @Test func pingADistance() {
        var m = Self.connecte()
        #expect(m.intervallePing == 10, "bail de 60 s : ping toutes les 10 s")
        _ = m.recu(M.element(Self.helloDistant), maintenant: 9)
        #expect(M.envois(m.tic(maintenant: 9.9)).isEmpty)
        #expect(M.envois(m.tic(maintenant: 10.0)) == ["id=2 json ping\n"])
    }

    @Test func reglagesDistantsSuivis() {
        var m = Self.connecte()
        let (_, e) = m.soumettre("json trames 1", origine: .console, maintenant: 1)
        #expect(M.envois(e) == ["id=2 json trames 1\n"])
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":30,"ms":1,"id":2,"etape":"fin","cmd":"json trames 1","ok":true,"code":"ok","duree_ms":0}"#), maintenant: 1.1)
        #expect(m.reglages.trames == true)
        _ = m.recu(M.element(#"{"v":1,"t":"hello","n":31,"ms":2,"bloc":"base","boot":"3FA2C901","up_s":901,"session":{"transport":"udp","trames":false}}"#), maintenant: 1.2)
        #expect(m.reglages.trames == false, "le hello fait foi")
    }

    /// Les reglages suivent la commande telle que la console du pont la decoupe (argv) :
    /// `js\xon compteurs 5000` est `json compteurs 5000` pour le pont (10.5, split_argv.c).
    @Test func reglagesLusCommeLePontDecoupeLaCommande() {
        var m = Self.connecte()
        #expect(m.reglages.compteursMs == 0)
        _ = m.soumettre(#"js\xon compteurs 5000"#, origine: .console, maintenant: 1)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":30,"ms":1,"id":2,"etape":"fin","cmd":"json compteurs 5000","ok":true,"code":"ok","duree_ms":0}"#), maintenant: 1.1)
        #expect(m.reglages.compteursMs == 5000)
        _ = m.soumettre(#"json "log" 1"#, origine: .console, maintenant: 2)
        _ = m.recu(M.element(#"{"v":1,"t":"reponse","n":31,"ms":2,"id":3,"etape":"fin","cmd":"json log 1","ok":true,"code":"ok","duree_ms":0}"#), maintenant: 2.1)
        #expect(m.reglages.log == true)
    }

    /// Le moteur ne demande jamais a distance une ligne que la liste blanche refuserait :
    /// ouverture, ping, instantane apres "sans reponse", liberation, cadences.
    @Test func toutesLesLignesDuMoteurSontPermisesADistance() {
        var m = MoteurSession()
        var lignes = M.envois(m.ouvert(maintenant: 0, genre: .udp))
        lignes += M.envois(m.recu(M.element(Self.helloDistant), maintenant: 0.1))
        lignes += M.envois(m.recu(Self.finJson1(), maintenant: 0.2))
        // Une commande sans reponse : renvois, puis l'instantane demande par le moteur.
        lignes += M.envois(m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.5).1)
        var t = 0.5
        while t < 40 {
            t += 0.5
            if Int(t * 2) % 3 == 0 { _ = m.recu(M.element(Self.helloDistant), maintenant: t) }
            lignes += M.envois(m.tic(maintenant: t))
        }
        lignes += M.envois(m.liberer(maintenant: t))
        #expect(lignes.contains("id=1 json 1 bail 60\n"))
        #expect(lignes.contains { $0.hasSuffix(" json ping\n") })
        #expect(lignes.contains { $0.hasSuffix(" json etat\n") })
        #expect(lignes.contains { $0.hasSuffix(" json 0\n") })
        for l in lignes {
            let commande = l.drop { $0 != " " }.dropFirst().trimmingCharacters(in: .newlines)
            #expect(PolitiqueCommandes.autoriseeADistance(commande) == nil, "\(l)")
        }
        var u = MoteurSession()
        _ = u.ouvert(maintenant: 0, genre: .udp)
        for c in MoteurSession.Cadence.allCases {
            for ms in [-5, 0, 1, 199, 200, 999, 1_000, 2_000, 4_999, 5_000, 9_999, 10_000, 30_000, 60_000, 60_001, 999_999] {
                let l = u.ligneCadence(c, ms: ms)
                #expect(PolitiqueCommandes.autoriseeADistance(l) == nil, "\(l)")
            }
        }
    }

    @Test func cadencesBorneesSelonLeTransport() {
        var u = MoteurSession()
        _ = u.ouvert(maintenant: 0)
        #expect(u.ligneCadence(.periode, ms: 100) == "json periode 200")
        #expect(u.ligneCadence(.lampes, ms: 500) == "json lampes 1000")
        #expect(u.ligneCadence(.compteurs, ms: 0) == "json compteurs 0")
        #expect(u.ligneCadence(.reseau, ms: 90_000) == "json reseau 60000")
        var r = MoteurSession()
        _ = r.ouvert(maintenant: 0, genre: .udp)
        #expect(r.ligneCadence(.periode, ms: 1_000) == "json periode 2000")
        #expect(r.ligneCadence(.lampes, ms: 1_000) == "json lampes 10000")
        #expect(r.ligneCadence(.compteurs, ms: 1_000) == "json compteurs 5000")
        #expect(r.ligneCadence(.reseau, ms: 5_000) == "json reseau 10000")
        #expect(r.ligneCadence(.compteurs, ms: 0) == "json compteurs 0")
        #expect(MoteurSession.bornes(.periode, genre: .udp) == 2_000...60_000)
        #expect(MoteurSession.bornes(.periode, genre: .usb) == 200...60_000)
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `TEST FAILED` à la compilation des tests : `type 'MessageCarte' has no member 'reseauIp'`, `cannot find type 'SessionH1' in scope`, `cannot find 'H1' in scope`, `extra argument 'transport' in call`…

- [ ] **Step 3 : le code.**

`apps/macos/AmaranProtocole/Commandes/Commandes.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : regles et commandes du pont amaran.
import Foundation

/// Genre de transport.
public enum GenreTransport: String, Sendable, Equatable {
    case usb
    /// UDP sur Thread (`TransportUDP`, port 5480).
    case udp
    /// Pont simule (mode demo) : se comporte comme l'USB.
    case demo
}

/// Erreur de construction d'une ligne vers le pont (section 2.5).
public enum ErreurLigne: Error, Sendable, Equatable, CustomStringConvertible {
    case vide
    case tropLongue(octets: Int, max: Int)
    case caractereInterdit
    case prefixeId
    case json

    public var description: String {
        switch self {
        case .vide: "Ligne vide."
        case .tropLongue(let o, let m): "Ligne trop longue : \(o) octets, \(m) au plus avec le préfixe id=."
        case .caractereInterdit: "Aucun caractère de contrôle n'est permis."
        case .prefixeId: "L'app ajoute elle-même le préfixe id=<n>."
        case .json: "Jamais de JSON ni d'octet RS vers le pont."
        }
    }
}

/// Lignes app -> pont : texte de la console prefixe par `id=<n> ` (6.1).
public enum LigneCommande {
    /// 127 octets au plus, prefixe compris (2.5).
    public static let octetsMax = 127
    public static let idMax = 999_999_999

    /// Octets envoyes a l'ouverture : Ctrl-U puis LF (3.2).
    public static let effacement = Data([Octets.ctrlU, Octets.lf])

    /// Normalise une commande (espaces de bord) et verifie les regles de 2.5 : les
    /// noms des lampes peuvent porter des accents (UTF-8), jamais un caractere de controle.
    public static func valider(_ commande: String, id: Int?) -> Result<String, ErreurLigne> {
        let c = commande.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return .failure(.vide) }
        guard c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0x7F...0x9F).contains($0.value) }) else {
            return .failure(c.unicodeScalars.contains { $0.value == 0x1E } ? .json : .caractereInterdit)
        }
        if c.hasPrefix("{") { return .failure(.json) }
        if c.lowercased().hasPrefix("id=") { return .failure(.prefixeId) }
        let ligne = id.map { "id=\($0) \(c)" } ?? c
        guard ligne.utf8.count <= octetsMax else {
            return .failure(.tropLongue(octets: ligne.utf8.count, max: octetsMax))
        }
        return .success(ligne)
    }

    /// Ligne complete, terminee par LF.
    public static func octets(_ commande: String, id: Int?) -> Result<Data, ErreurLigne> {
        valider(commande, id: id).map { Data(($0 + "\n").utf8) }
    }

    /// Numero suivant : 1..999999999, repart a 1.
    public static func suivant(_ id: Int) -> Int {
        id >= idMax ? 1 : id + 1
    }

    /// Mots d'une commande, en minuscules. Un guillemet coupe le mot, comme dans la
    /// console du pont (esp_console_split_argv) : `"redemarre"` est `redemarre`, et
    /// `"mesh"cles` est `mesh cles`.
    public static func mots(_ commande: String) -> [String] {
        commande.lowercased().replacingOccurrences(of: "\"", with: " ").split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }
    /// Arguments d'une commande, decoupes exactement comme `esp_console_split_argv`
    /// d'ESP-IDF (components/console/split_argv.c) les decoupe dans le pont : separes
    /// par des espaces (la tabulation fait partie du mot), guillemets doubles, barre
    /// oblique inverse devant `\`, `"` ou une espace (devant un autre octet, les deux
    /// sont oublies), un guillemet fermant finit le mot ; au plus `maxArguments`
    /// (le pont passe 8 places : 7 arguments), un octet nul arrete tout. Sensible a la
    /// casse, comme la console. Sert a juger la liste blanche comme le pont (10.5).
    public static func argv(_ commande: String, maxArguments: Int = 7) -> [String] {
        // Les premiers arguments ne dependent pas de la suite de la ligne : couper apres
        // `maxArguments` revient a s'arreter la, comme le pont.
        arguments(Array(commande.utf8)).prefix(max(maxArguments, 0)).map { String(decoding: $0.valeur, as: UTF8.self) }
    }

    /// Tous les arguments d'une ligne, decoupes comme `argv` (meme automate, sans limite de
    /// nombre), avec leur place dans la ligne : octets `debut..<fin`, guillemets et barres
    /// obliques compris. Sert a masquer les cles la ou elles sont ecrites.
    static func arguments(_ octets: [UInt8]) -> [(valeur: [UInt8], debut: Int, fin: Int)] {
        enum Etat { case espace, mot, guillemets, motEchappe, guillemetsEchappe }
        let espace = UInt8(ascii: " "), guillemet = UInt8(ascii: "\""), barre = UInt8(ascii: "\\")
        var args: [(valeur: [UInt8], debut: Int, fin: Int)] = []
        var courant: [UInt8] = []
        var debut = 0
        var fin = octets.count
        var etat = Etat.espace
        for (i, b) in octets.enumerated() {
            if b == 0 {
                fin = i
                break
            }
            switch etat {
            case .espace:
                if b == espace { continue }
                courant = []
                debut = i
                if b == guillemet {
                    etat = .guillemets
                } else if b == barre {
                    etat = .motEchappe
                } else {
                    courant.append(b)
                    etat = .mot
                }
            case .guillemets:
                if b == guillemet {
                    args.append((courant, debut, i + 1))
                    etat = .espace
                } else if b == barre {
                    etat = .guillemetsEchappe
                } else {
                    courant.append(b)
                }
            case .motEchappe, .guillemetsEchappe:
                if b == barre || b == guillemet || b == espace { courant.append(b) }
                etat = etat == .motEchappe ? .mot : .guillemets
            case .mot:
                if b == espace {
                    args.append((courant, debut, i))
                    etat = .espace
                } else if b == barre {
                    etat = .motEchappe
                } else {
                    courant.append(b)
                }
            }
        }
        if etat != .espace { args.append((courant, debut, fin)) }
        return args
    }
}

/// Ce que la console fait d'une ligne tapee (6.4).
public enum VerdictConsole: Sendable, Equatable {
    case autorisee
    /// Demander confirmation avant d'envoyer.
    case confirmation(String)
    case interdite(String)
}

public enum PolitiqueCommandes {
    /// Commandes qui demandent confirmation (6.4) ; a distance, la liste blanche (10.5)
    /// d'abord. Toutes ces regles jugent la ligne decoupee comme la console du pont la
    /// decoupe (`LigneCommande.argv`, sensible a la casse) : guillemets et echappements
    /// ne les contournent pas (`re\xdemarre` est `redemarre` pour le pont, et demande la
    /// meme confirmation).
    public static func verdictConsole(_ commande: String, transport: GenreTransport = .usb) -> VerdictConsole {
        // Longueur jugee avec le plus long id possible : la ligne partira quel que soit son numero.
        if case .failure(let e) = LigneCommande.valider(commande, id: LigneCommande.idMax) {
            return .interdite(e.description)
        }
        if transport == .udp, let raison = autoriseeADistance(commande) {
            return .interdite("Commande non envoyée : \(refusDistant(raison)).")
        }
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        func est(_ i: Int, _ mot: String) -> Bool { i < a.count && a[i] == mot }
        if a.count == 2, est(0, "json"), est(1, "0") {
            return .interdite("Utiliser « Libérer le port » : l'app enverra json 0 et fermera le port.")
        }
        // Le pont changerait de cle, mais la cle rendue ne serait rangee nulle part :
        // seul le geste de l'app la range dans le trousseau (10.2).
        if est(0, "json"), est(1, "cle"), est(2, "nouvelle") {
            return .interdite("Utiliser « Nouvelle clé… » : la clé rendue doit être rangée dans le trousseau.")
        }
        if est(0, "json"), est(1, "cle"), est(2, "efface") {
            return .confirmation("Efface la clé du réseau Thread : les sessions par le réseau tombent et le port 5480 se ferme.")
        }
        if est(0, "redemarre") {
            return .confirmation("Redémarre le pont (le port USB va se ré-énumérer).")
        }
        if est(0, "decommission") {
            return .confirmation("Retire le pont de Maison et de tout autre contrôleur Matter (clés du Mesh et lampes gardées ; la clé de l'accès par Thread est effacée).")
        }
        if est(0, "mesh") {
            if est(1, "cles") {
                return .confirmation("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes.")
            }
            if est(1, "oublie") {
                return .confirmation("Efface les clés du réseau des lampes dans le pont.")
            }
            if est(1, "adresse") {
                return .confirmation("Change l'adresse Bluetooth Mesh du pont.")
            }
            if est(1, "iv") {
                return .confirmation(est(2, "cherche")
                    ? "Cherche l'IV Index : la console du pont reste occupée pendant la recherche."
                    : "Change l'IV Index du réseau des lampes.")
            }
            if est(1, "lampes") {
                return .confirmation("Ouvre une nouvelle liste de lampes (effet au redémarrage, une fois complète).")
            }
            if a.count == 4, est(1, "lampe"), est(3, "masquer") {
                return .confirmation("Retire la lampe de Maison : remise, elle y reviendra comme un nouvel accessoire, sans son nom, ses scènes ni ses automatisations.")
            }
        }
        return .autorisee
    }

    /// Refus de la liste blanche, en francais : la raison du pont (celle que rend
    /// `autoriseeADistance`, mot pour mot le `msg` de sa reponse `interdite`) n'est citee
    /// qu'une fois, entre guillemets, telle quelle. « la » : la commande refusee.
    public static func refusDistant(_ raison: String) -> String {
        "la liste blanche du pont la refuse (« \(raison) »)"
    }

    /// `json 1`, `json etat`, `json hello` : la `fin` part apres la derniere ligne de
    /// l'instantane (6.2), et non aussitot. Jugee sur la ligne decoupee comme le pont la
    /// decoupe (`json 1 bail 60` compris).
    public static func repondApresInstantane(_ commande: String) -> Bool {
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        guard a.count >= 2, a[0] == "json" else { return false }
        return a[1] == "1" || (a.count == 2 && (a[1] == "etat" || a[1] == "hello"))
    }

    /// Apres ces commandes, l'app attend la re-enumeration de l'USB (3.1) ; jugees,
    /// comme `verdictConsole`, sur la ligne decoupee comme la console du pont la decoupe.
    public static func attendReenumeration(_ commande: String) -> Bool {
        let premier = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces)).first
        return premier == "redemarre" || premier == "decommission"
    }

    /// Liste blanche a distance (10.5) : miroir exact de `refusDistant`
    /// (components/protocole/json_amaran.cpp), juge sur les arguments decoupes comme le
    /// pont les decoupe (`LigneCommande.argv`) : guillemets et echappements ne la
    /// contournent pas (`json "1" "bail" 0` est refusee). `ligne` : la commande sans
    /// le prefixe `id=`. Rend nil si la commande est permise, sinon la raison, telle
    /// que le pont la donnerait dans le `msg` de sa reponse `interdite`.
    public static func autoriseeADistance(_ ligne: String) -> String? {
        let interdite = "interdite a distance : USB seulement"
        // La ligne part sans ses espaces de bord (LigneCommande.valider).
        let a = LigneCommande.argv(ligne.trimmingCharacters(in: .whitespaces))
        func est(_ i: Int, _ k: String) -> Bool { i < a.count && a[i] == k }
        // Entier decimal : chiffres seulement, 9 au plus (`nombre` du pont).
        func nombre(_ i: Int) -> Int? {
            guard i < a.count else { return nil }
            let u = Array(a[i].utf8)
            guard !u.isEmpty, u.count <= 9, u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            return Int(a[i])
        }
        guard !a.isEmpty else { return interdite }
        if est(0, "json") {
            if a.count == 2, est(1, "0") || est(1, "etat") || est(1, "hello") || est(1, "ping") { return nil }
            if est(1, "1") {
                // Jamais de bail 0 a distance : le pont emettrait pour un hote parti.
                if a.count == 2 { return nil }
                if a.count == 4, est(2, "bail"), let v = nombre(3), (10...120).contains(v) { return nil }
                return "json 1 : bail de 10 a 120 s a distance"
            }
            if a.count == 3, est(1, "trames") || est(1, "log"), est(2, "0") || est(2, "1") { return nil }
            for (k, min) in bornesDistantes where est(1, k) {
                if a.count == 3, let v = nombre(2), v == 0 || (v >= min && v <= 60_000) { return nil }
                return "json \(k) : 0 ou \(min)..60000 ms a distance"
            }
            return interdite  // 'json' seul, 'json cle ...'
        }
        if est(0, "lampe") {
            if a.count >= 2, nombre(1) == nil { return interdite }
            if a.count == 2 { return nil }  // detail
            if a.count == 3, est(2, "on") || est(2, "off") || est(2, "releve") { return nil }
            if a.count == 4, est(2, "niveau"), nombre(3) != nil { return nil }
            return interdite
        }
        if est(0, "mesh") {
            if a.count == 1 { return nil }  // lecture
            if a.count == 4, est(1, "lampe"), nombre(2) != nil, est(3, "masquer") || est(3, "afficher") { return nil }
            return interdite
        }
        if a.count == 2, est(0, "led"), est(1, "test") || est(1, "stop") { return nil }
        if a.count == 1, est(0, "lampes") || est(0, "matter") || est(0, "taches") || est(0, "cause") { return nil }
        return interdite
    }

    /// Cadences permises a distance, hors 0 (10.5) : `json <k> <ms>`, minimum, jusqu'a 60 000.
    public static let bornesDistantes: [(String, Int)] = [
        ("periode", 2_000), ("lampes", 10_000), ("compteurs", 5_000), ("reseau", 10_000),
    ]

    /// Masque les cles d'une ligne affichee : la commande `mesh cles <reseau>
    /// <application>` (casse, espaces et guillemets quelconques, comme la console les lit),
    /// l'alea de `json cle nouvelle <64 hexa>`, le champ `"cle":"..."` d'une reponse
    /// (la cle UDP, 10.2), et toute suite de 32 chiffres hexa ou plus (une cle tapee
    /// ailleurs). Les empreintes (8 hexa) et le nom SRP (16 hexa) restent visibles.
    /// Les deux commandes sont aussi jugees sur la ligne decoupee comme la console du pont
    /// la decoupe (`masquerArgumentsSecrets`) : guillemets et echappements ne cachent
    /// aucune cle au masque. Sert partout ou une commande ou un texte du pont s'affiche
    /// ou se garde : console, journal des envois, citations, suivis, historique de saisie.
    public static func masquerCle(_ texte: String) -> String {
        // Une barre oblique inverse peut couper « cle » (`c\xle`) : le pont l'oublie.
        guard texte.utf8.count >= 32 || texte.range(of: "cle", options: .caseInsensitive) != nil
              || texte.contains("\\") else { return texte }
        var s = masquerArgumentsSecrets(texte)
        s.replace(/(?i)("?mesh"?[ \t]+"?cles"?)([ \t]+"?[0-9a-f]+"?)+/) { m in m.output.1 + " " + masque + " " + masque }
        s.replace(/(?i)("?json"?[ \t]+"?cle"?[ \t]+"?nouvelle"?[ \t]+)[0-9a-f\\"]+/) { m in m.output.1 + masque }
        s.replace(/("cle"[ ]*:[ ]*")[^"]*"/) { m in m.output.1 + masque + "\"" }
        s.replace(/[0-9A-Fa-f]{32,}/) { _ in masque }
        return s
    }

    /// Masque plus strict, pour une ligne abimee, un fragment ou un debordement : un
    /// journal d'ESP-IDF qui coupe la reponse a `json cle nouvelle` y laisse une part
    /// de la cle, sans guillemet fermant ni 32 hexa d'un bloc. En plus de `masquerCle` :
    /// le champ `"cle":"<hexa>` meme sans guillemet fermant, toute suite d'au moins 2
    /// hexa suivie d'un guillemet (la fin d'une cle coupee, ou reprise apres un journal
    /// intercale ; les empreintes aussi, tant pis), et toute suite de 16 hexa ou plus.
    /// Jamais sur une ligne de console ordinaire : le nom SRP fait 16 hexa.
    public static func masquerCleStricte(_ texte: String) -> String {
        var s = masquerCle(texte)
        s.replace(/("cle"\s*:\s*")[0-9A-Fa-f]+/) { m in m.output.1 + masque }
        s.replace(/[0-9A-Fa-f]{2,}(?=")/) { _ in masque }
        s.replace(/[0-9A-Fa-f]{16,}/) { _ in masque }
        return s
    }

    /// Masque juge sur la ligne decoupee comme la console du pont la decoupe
    /// (`LigneCommande.arguments`) : apres `mesh cles` ou `json cle nouvelle` (casse
    /// quelconque), tout ce qui suit est masque, quelle que soit sa forme (guillemets,
    /// echappements comme `4041\x42` que le pont retire) : un masque par mot ; les mots de
    /// la commande restent tels qu'ecrits. La commande commence la ligne, ou suit
    /// l'invite `amaran>` (echo de la console en mode texte), `›`, `«` ou `id=<n>`
    /// (journal des envois, citations de l'app) ; une citation (commande qui suit `«`) finit
    /// a `»` ; sinon, tout jusqu'au bout du texte est masque (un `»` tape n'arrete rien). Ailleurs, rien :
    /// le texte d'usage du pont (`erreur : mesh cles <reseau 32 hexa> ...`) reste lisible.
    /// Sans rien a masquer, le texte est rendu tel quel.
    static func masquerArgumentsSecrets(_ texte: String) -> String {
        let octets = Array(texte.utf8)
        let args = LigneCommande.arguments(octets)
        // Mots de chaque argument : entre guillemets, ou avec `\ `, un argument en porte plusieurs.
        var mots: [(valeur: [UInt8], arg: Int, premier: Bool)] = []
        for (j, a) in args.enumerated() {
            for (k, m) in a.valeur.split(whereSeparator: { $0 == 0x20 || $0 == 0x09 }).enumerated() {
                mots.append((Array(m), j, k == 0))
            }
        }
        func est(_ i: Int, _ mot: [UInt8]) -> Bool {
            i < mots.count && mots[i].valeur.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 } == mot
        }
        func apresUnPrefixe(_ i: Int) -> Bool {
            guard mots[i].premier else { return false }
            guard mots[i].arg > 0 else { return true }
            let avant = args[mots[i].arg - 1].valeur
            if prefixesDeCommande.contains(avant) { return true }
            return avant.count > 3 && avant.starts(with: Array("id=".utf8)) && avant.dropFirst(3).allSatisfy { (0x30...0x39).contains($0) }
        }
        var sortie: [UInt8] = []
        var copie = 0
        var aMasque = false
        var i = 0
        while i < mots.count {
            let longueur = est(i, Array("mesh".utf8)) && est(i + 1, Array("cles".utf8)) ? 2
                : est(i, Array("json".utf8)) && est(i + 1, Array("cle".utf8)) && est(i + 2, Array("nouvelle".utf8)) ? 3 : 0
            guard longueur > 0, apresUnPrefixe(i) else {
                i += 1
                continue
            }
            // Seule une citation de l'app (la commande suit `«`) finit a `»` : la commande y est
            // deja masquee seule avant d'etre citee. Un `»` tape dans une commande n'arrete rien.
            let cite = mots[i].arg > 0 && args[mots[i].arg - 1].valeur == debutDeCitation
            var fin = i + longueur
            while fin < mots.count, !(cite && mots[fin].premier && args[mots[fin].arg].valeur == finDeCitation) { fin += 1 }
            let caches = fin - i - longueur
            guard caches > 0 else {
                i = fin
                continue
            }
            // Les mots de la commande restent tels qu'ecrits (guillemets, casse, espaces) ;
            // si la suite partage leur argument (`"mesh cles <cle>"`), ils sont recrits.
            let dernier = i + longueur - 1
            if dernier + 1 < mots.count, mots[dernier + 1].arg == mots[dernier].arg {
                sortie += octets[copie..<args[mots[i].arg].debut]
                sortie += Array(mots[i...dernier].map { $0.valeur }.joined(separator: [0x20]))
            } else {
                sortie += octets[copie..<args[mots[dernier].arg].fin]
            }
            for _ in 0..<caches { sortie += [0x20] + Array(masque.utf8) }
            if fin < mots.count {
                sortie.append(0x20)
                copie = args[mots[fin].arg].debut
            } else {
                copie = octets.count
            }
            aMasque = true
            i = fin
        }
        guard aMasque else { return texte }
        sortie += octets[copie...]
        return String(decoding: sortie, as: UTF8.self)
    }

    /// Ce qui precede une commande dans un texte : l'invite de la console, le journal des
    /// envois (`›`, `id=<n>`), une citation (`«`).
    private static let prefixesDeCommande: [[UInt8]] = ["amaran>", "›", "«"].map { Array($0.utf8) }
    private static let debutDeCitation = Array("«".utf8)
    private static let finDeCitation = Array("»".utf8)

    private static let masque = String(repeating: "•", count: 8)
}

extension ElementRecu {
    /// L'element tel qu'il peut entrer dans un journal, une console ou un affichage :
    /// sans cle (Mesh ou UDP). Ligne machine : `LigneMachine.sansCle`. Ligne abimee,
    /// fragment, debordement : masque strict (une cle coupee n'a plus ses 32 hexa
    /// d'un bloc). Texte : masque ordinaire, strict s'il finit par `}` (la fin d'une
    /// ligne machine dont le debut s'est perdu).
    public var sansCle: ElementRecu {
        switch self {
        case .machine(let l):
            return .machine(l.sansCle)
        case .texte(var t):
            t.texte = t.texte.hasSuffix("}") ? PolitiqueCommandes.masquerCleStricte(t.texte)
                                              : PolitiqueCommandes.masquerCle(t.texte)
            return .texte(t)
        case .fragment(let s):
            return .fragment(PolitiqueCommandes.masquerCleStricte(s))
        case .abimee(let raison, let brut):
            return .abimee(raison: raison, brut: PolitiqueCommandes.masquerCleStricte(brut))
        case .debordement(let s):
            return .debordement(PolitiqueCommandes.masquerCleStricte(s))
        case .versionInconnue, .invalide:
            return self
        }
    }
}
````

`apps/macos/AmaranProtocole/Messages/Enumerations.swift`, bloc 1 sur 2. Remplacer :

````swift
    case tropLong = "trop_long"
    case cadence
    case inconnu
}
````

par :

````swift
    case tropLong = "trop_long"
    case cadence
    /// A distance, commande hors de la liste blanche (10.5) : rien n'est execute.
    case interdite
    /// A distance, `id` plus ancien que les 8 dernieres reponses gardees : sa reponse est
    /// oubliee, aucune autre ne viendra (10.4). Le renvoi d'un `id` encore en cours, lui,
    /// est ignore en silence.
    case dejaTraite = "deja_traite"
    case inconnu
}
````

`apps/macos/AmaranProtocole/Messages/Enumerations.swift`, bloc 2 sur 2. Remplacer :

````swift
    case notice, alerte, inconnu
}
````

par :

````swift
    case notice, alerte, inconnu
}

/// `hello.base.session.transport` (5.1).
public enum TransportSession: String, EnumeTolerante {
    case usb, udp, inconnu
}

/// `trame.sens` (7.6) : emise ou recue par le pont.
public enum SensTrame: String, EnumeTolerante {
    case tx, rx, inconnu
}

/// `trame.quoi` (7.6).
public enum QuoiTrame: String, EnumeTolerante {
    /// Marche ou intensite vers une lampe.
    case ordre
    /// Demande d'etat au groupe des lampes.
    case demande
    /// Etat renvoye par une lampe.
    case etat
    case inconnu
}

/// Type d'une adresse du bloc `reseau` `ip` (5.5).
public enum TypeAdresse: String, EnumeTolerante {
    /// Joignable du reseau local, par le routeur de bordure.
    case omr
    /// Interne au maillage Thread.
    case mlEid = "ml_eid"
    case autre
    case inconnu
}

/// Capacites annoncees par `hello` `identite` (`caps`, 5.1). L'app se regle sur
/// elles, pas sur la version du firmware ; une capacite inconnue est ignoree.
public enum CapPont: String, Sendable, CaseIterable {
    case matter, thread, mesh, catalogue, ordres, led, log
    /// Messages `trame` (7.6).
    case trames
    /// Canal par Thread (section 10).
    case udp
    /// `json cle` (10.2).
    case cle
    /// Texte des commandes a distance, en messages `texte` (10.4).
    case texte
}
````

`apps/macos/AmaranProtocole/Messages/Session.swift`, bloc 1 sur 5. Remplacer :

````swift
public struct HelloBase: Codable, Sendable, Equatable {
    public struct ReglagesSession: Codable, Sendable, Equatable {
        public var periodeMs: Int?
        public var lampesMs: Int?
````

par :

````swift
public struct HelloBase: Codable, Sendable, Equatable {
    public struct ReglagesSession: Codable, Sendable, Equatable {
        /// `usb` ou `udp` (rev 1).
        public var transport: TransportSession?
        public var periodeMs: Int?
        public var lampesMs: Int?
````

`apps/macos/AmaranProtocole/Messages/Session.swift`, bloc 2 sur 5. Remplacer :

````swift
        public var bailS: Int?
        public var log: Bool?

        public init(periodeMs: Int? = nil, lampesMs: Int? = nil, compteursMs: Int? = nil, reseauMs: Int? = nil,
                    bailS: Int? = nil, log: Bool? = nil) {
            self.periodeMs = periodeMs
            self.lampesMs = lampesMs
````

par :

````swift
        public var bailS: Int?
        public var log: Bool?
        /// Messages `trame` demandes (`json trames 1`, rev 1).
        public var trames: Bool?

        public init(transport: TransportSession? = nil, periodeMs: Int? = nil, lampesMs: Int? = nil,
                    compteursMs: Int? = nil, reseauMs: Int? = nil, bailS: Int? = nil, log: Bool? = nil,
                    trames: Bool? = nil) {
            self.transport = transport
            self.periodeMs = periodeMs
            self.lampesMs = lampesMs
````

`apps/macos/AmaranProtocole/Messages/Session.swift`, bloc 3 sur 5. Remplacer :

````swift
            self.bailS = bailS
            self.log = log
        }
    }
````

par :

````swift
            self.bailS = bailS
            self.log = log
            self.trames = trames
        }
    }
````

`apps/macos/AmaranProtocole/Messages/Session.swift`, bloc 4 sur 5. Remplacer :

````swift
    public var bailS: Int?
    public var upS: Int?

    public init(id: Int, etape: EtapeReponse, cmd: String? = nil, ok: Bool, code: CodeReponse, msg: String? = nil,
                dureeMs: Int? = nil, suite: SuiteReponse? = nil, lampe: Int? = nil, bailS: Int? = nil, upS: Int? = nil) {
        self.id = id
        self.etape = etape
````

par :

````swift
    public var bailS: Int?
    public var upS: Int?
    /// `json cle nouvelle` : la cle, rendue une seule fois (jamais gardee, voir `sansCle`).
    public var cle: String?
    /// `json cle nouvelle` : empreinte de la cle (8 premiers hexa majuscules de son SHA-256).
    public var empreinte: String?

    public init(id: Int, etape: EtapeReponse, cmd: String? = nil, ok: Bool, code: CodeReponse, msg: String? = nil,
                dureeMs: Int? = nil, suite: SuiteReponse? = nil, lampe: Int? = nil, bailS: Int? = nil, upS: Int? = nil,
                cle: String? = nil, empreinte: String? = nil) {
        self.id = id
        self.etape = etape
````

`apps/macos/AmaranProtocole/Messages/Session.swift`, bloc 5 sur 5. Remplacer :

````swift
        self.bailS = bailS
        self.upS = upS
    }
}
````

par :

````swift
        self.bailS = bailS
        self.upS = upS
        self.cle = cle
        self.empreinte = empreinte
    }

    /// La meme reponse, sans la cle : aucun historique (suivis de commandes, journal des
    /// trames) ne doit jamais la garder, seule l'empreinte y a sa place.
    public var sansCle: Reponse {
        var r = self
        r.cle = nil
        return r
    }
}
````

`apps/macos/AmaranProtocole/Messages/Etat.swift`, bloc 1 sur 1. Remplacer :

````swift
    public var attache: Bool?
}
````

par :

````swift
    public var attache: Bool?
}

/// `reseau`, bloc `ip` (5.5) : le nom SRP, les adresses et le canal UDP du pont.
public struct ReseauIp: Codable, Sendable, Equatable {
    public struct Adresse: Codable, Sendable, Equatable {
        public var type: TypeAdresse?
        public var adresse: String?

        public init(type: TypeAdresse?, adresse: String?) {
            self.type = type
            self.adresse = adresse
        }
    }

    public struct Udp: Codable, Sendable, Equatable {
        public var port: Int?
        /// Une cle UDP existe (jamais la cle elle-meme : seulement son empreinte).
        public var cle: Bool?
        /// 8 hexa majuscules, ou nil sans cle.
        public var empreinte: String?
        /// Le port ecoute.
        public var ouvert: Bool?
        /// Sessions H1 etablies.
        public var sessions: Int?
        public var recus: Int?
        public var emis: Int?
        /// Datagrammes refuses en silence (10.3).
        public var rejets: Int?
        public var perdus: Int?
    }

    /// Nom que le pont publie par SRP (16 hexa) ; l'app le resout en `<srp>.local`.
    public var srp: String?
    public var adresses: [Adresse]?
    public var udp: Udp?

    /// Adresse joignable du reseau local (OMR), la premiere.
    public var adresseOmr: String? {
        adresses?.first { $0.type == .omr }?.adresse
    }

    /// Nom a resoudre pour la session par le reseau : `<srp>.local`.
    public var hote: String? {
        guard let srp, !srp.isEmpty else { return nil }
        return srp + ".local"
    }
}
````

`apps/macos/AmaranProtocole/Messages/Evenements.swift`, bloc 1 sur 1. Remplacer :

````swift
    public var sautes: Int?
}
````

par :

````swift
    public var sautes: Int?
}

/// `trame` (7.6) : un message de lampe que le pont emet ou recoit, decode
/// (seulement avec `json trames 1`).
public struct Trame: Codable, Sendable, Equatable {
    public var sens: SensTrame?
    public var quoi: QuoiTrame?
    /// Numero de la lampe ; nil : le groupe des lampes (demande d'etat).
    public var lampe: Int?
    public var marche: Bool?
    public var intensite: Int?
    /// Ordre seulement : essai 1 a 3.
    public var essai: Int?
    /// Trames non emises depuis la precedente (plafond de debit).
    public var sautes: Int?

    public init(sens: SensTrame? = nil, quoi: QuoiTrame? = nil, lampe: Int? = nil, marche: Bool? = nil,
                intensite: Int? = nil, essai: Int? = nil, sautes: Int? = nil) {
        self.sens = sens
        self.quoi = quoi
        self.lampe = lampe
        self.marche = marche
        self.intensite = intensite
        self.essai = essai
        self.sautes = sautes
    }
}

/// `texte` (10.4) : a distance, une ligne que la console imprimerait pour la
/// commande `id`, entre sa `reponse` `debut` et sa `reponse` `fin`.
public struct TexteCommande: Codable, Sendable, Equatable {
    public var id: Int
    /// 127 octets au plus.
    public var txt: String?

    public init(id: Int, txt: String?) {
        self.id = id
        self.txt = txt
    }
}
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, bloc 1 sur 6. Remplacer :

````swift
    case reseauMatter(ReseauMatter)
    case reseauThread(ReseauThread)
    case battement(Battement)
    case fin(FinSession)
````

par :

````swift
    case reseauMatter(ReseauMatter)
    case reseauThread(ReseauThread)
    case reseauIp(ReseauIp)
    case battement(Battement)
    case fin(FinSession)
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, bloc 2 sur 6. Remplacer :

````swift
    case led(ChangementLed)
    case log(MessageLog)
    /// Type ou bloc inconnu : ignore (section 8).
    case inconnu
````

par :

````swift
    case led(ChangementLed)
    case log(MessageLog)
    case trame(Trame)
    case texte(TexteCommande)
    /// Type ou bloc inconnu : ignore (section 8).
    case inconnu
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, bloc 3 sur 6. Remplacer :

````swift
        switch self {
        case .helloBase, .helloIdentite, .configCatalogue, .configMesh, .configLampe, .etatPont, .etatLampe,
             .etatSante, .compteursMesh, .reseauMatter, .reseauThread, .battement:
            true
        default:
            false
        }
    }
}
````

par :

````swift
        switch self {
        case .helloBase, .helloIdentite, .configCatalogue, .configMesh, .configLampe, .etatPont, .etatLampe,
             .etatSante, .compteursMesh, .reseauMatter, .reseauThread, .reseauIp, .battement:
            true
        default:
            false
        }
    }

    /// La meme valeur, sans la cle si c'est une `reponse` a `json cle nouvelle` (6.3, 10.2) :
    /// pour tout historique qui garde le message entier (journal des trames).
    public var sansCle: MessageCarte {
        if case .reponse(let r) = self { return .reponse(r.sansCle) }
        return self
    }
}
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, bloc 4 sur 6. Remplacer :

````swift
        self.message = message
        self.json = json
    }
}
````

par :

````swift
        self.message = message
        self.json = json
    }

    /// La meme ligne, sans la cle UDP : ni dans le message (`sansCle`), ni dans le JSON
    /// garde (`"cle":"<hexa>"` masque). A appliquer avant tout journal.
    public var sansCle: LigneMachine {
        // Une reponse a `json cle nouvelle` porte la cle dans un champ "cle" (6.3) ; une
        // ligne alteree mais encore valide la porterait sous un autre nom : le JSON passe
        // toujours par le masque (32 hexa d'un bloc compris).
        LigneMachine(enveloppe: enveloppe, message: message.sansCle, json: PolitiqueCommandes.masquerCle(json))
    }
}
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, bloc 5 sur 6. Remplacer :

````swift
        case ("reseau", "matter"): return .reseauMatter(try d.decode(ReseauMatter.self, from: json))
        case ("reseau", "thread"): return .reseauThread(try d.decode(ReseauThread.self, from: json))
        case ("hb", _): return .battement(try d.decode(Battement.self, from: json))
        case ("fin", _): return .fin(try d.decode(FinSession.self, from: json))
````

par :

````swift
        case ("reseau", "matter"): return .reseauMatter(try d.decode(ReseauMatter.self, from: json))
        case ("reseau", "thread"): return .reseauThread(try d.decode(ReseauThread.self, from: json))
        case ("reseau", "ip"): return .reseauIp(try d.decode(ReseauIp.self, from: json))
        case ("hb", _): return .battement(try d.decode(Battement.self, from: json))
        case ("fin", _): return .fin(try d.decode(FinSession.self, from: json))
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift`, bloc 6 sur 6. Remplacer :

````swift
        case ("led", _): return .led(try d.decode(ChangementLed.self, from: json))
        case ("log", _): return .log(try d.decode(MessageLog.self, from: json))
        default: return .inconnu
        }
````

par :

````swift
        case ("led", _): return .led(try d.decode(ChangementLed.self, from: json))
        case ("log", _): return .log(try d.decode(MessageLog.self, from: json))
        case ("trame", _): return .trame(try d.decode(Trame.self, from: json))
        case ("texte", _): return .texte(try d.decode(TexteCommande.self, from: json))
        default: return .inconnu
        }
````

`apps/macos/AmaranProtocole/Etat/EtatPont.swift`, bloc 1 sur 3. Remplacer :

````swift
    public private(set) var matter: Instantane<ReseauMatter>?
    public private(set) var thread: Instantane<ReseauThread>?
    public private(set) var battement: Instantane<Battement>?

````

par :

````swift
    public private(set) var matter: Instantane<ReseauMatter>?
    public private(set) var thread: Instantane<ReseauThread>?
    /// Bloc `reseau` `ip` (5.5) : nom SRP, adresses, canal UDP.
    public private(set) var ip: Instantane<ReseauIp>?
    public private(set) var battement: Instantane<Battement>?

````

`apps/macos/AmaranProtocole/Etat/EtatPont.swift`, bloc 2 sur 3. Remplacer :

````swift
        case .reseauMatter(let v): matter = inst(v)
        case .reseauThread(let v): thread = inst(v)
        case .battement(let v): battement = inst(v)
        case .led(let v):
````

par :

````swift
        case .reseauMatter(let v): matter = inst(v)
        case .reseauThread(let v): thread = inst(v)
        case .reseauIp(let v): ip = inst(v)
        case .battement(let v): battement = inst(v)
        case .led(let v):
````

`apps/macos/AmaranProtocole/Etat/EtatPont.swift`, bloc 3 sur 3. Remplacer :

````swift
    public var capacites: Set<String> { Set(identite?.valeur.caps ?? []) }

    /// Numeros des lampes connues, dans l'ordre (liste du pont).
    public var numerosLampes: [Int] {
````

par :

````swift
    public var capacites: Set<String> { Set(identite?.valeur.caps ?? []) }

    /// Capacite annoncee par le dernier `hello` `identite` (5.1).
    public func a(_ c: CapPont) -> Bool { capacites.contains(c.rawValue) }

    /// Revision mineure du protocole (0 avant Thread, `trame` et `texte`).
    public var rev: Int? { helloBase?.valeur.rev }

    /// Transport de la session, tel que le dernier `hello` l'annonce.
    public var transport: TransportSession? { helloBase?.valeur.session?.transport }

    /// MAC de la puce (`hello` `identite`), 12 hexa majuscules.
    public var mac: String? { identite?.valeur.mac }

    /// Nom SRP publie par le pont (bloc `ip`), sans `.local`.
    public var srp: String? { ip?.valeur.srp }

    /// Numeros des lampes connues, dans l'ordre (liste du pont).
    public var numerosLampes: [Int] {
````

`apps/macos/AmaranProtocole/Interpretation/Interpretation.swift`, bloc 1 sur 2. Remplacer :

````swift
        case .tropLong: "ligne trop longue"
        case .cadence: "trop de lignes par seconde"
        case .inconnu: "code inconnu"
        }
````

par :

````swift
        case .tropLong: "ligne trop longue"
        case .cadence: "trop de lignes par seconde"
        case .interdite: "interdite à distance"
        case .dejaTraite: "déjà traitée"
        case .inconnu: "code inconnu"
        }
````

`apps/macos/AmaranProtocole/Interpretation/Interpretation.swift`, bloc 2 sur 2. Remplacer :

````swift
            return "issue inconnue"
        }
    }

````

par :

````swift
            return "issue inconnue"
        }
    }

    /// `trame` (7.6) : « → lampe 1 : ordre allumée, 50 % (essai 1) », « → groupe : demande
    /// d'état », « ← lampe 1 : état allumée, 50 % ».
    public static func trame(_ t: Trame) -> String {
        let sens = switch t.sens {
        case .tx: "→"
        case .rx: "←"
        case .inconnu, nil: "?"
        }
        let qui = t.lampe.map { "lampe \($0)" } ?? "groupe"
        var texte = "\(sens) \(qui) : "
        switch t.quoi {
        case .ordre: texte += "ordre"
        case .demande: texte += "demande d'état"
        case .etat: texte += "état"
        case .inconnu, nil: texte += "trame inconnue"
        }
        if t.marche != nil || t.intensite != nil {
            var champs: [String] = []
            if let m = t.marche { champs.append(m ? "allumée" : "éteinte") }
            if let i = t.intensite { champs.append(intensite(i)) }
            texte += " " + champs.joined(separator: ", ")
        }
        if let e = t.essai, t.quoi == .ordre { texte += " (essai \(e))" }
        if let s = t.sautes, s > 0 { texte += " — \(s) trame(s) non émise(s) avant" }
        return texte
    }

````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 1 sur 13. Remplacer :

````swift
// Repris de Halo Compagnon (commit e114cd5) : l'evenement ordre du pont amaran remplace
// la livraison, et le bloc sante dit la commande en cours (docs/PROTOCOLE-JSON.md 6.2).
import Foundation

````

par :

````swift
// Repris de Halo Compagnon (commit e114cd5) : l'evenement ordre du pont amaran remplace
// la livraison, et le bloc sante dit la commande en cours (docs/PROTOCOLE-JSON.md 6.2) ;
// a distance, la politique reseau de Halo (renvoi du meme id), le texte en messages
// `texte` et la reponse `deja_traite` (10.4).
import Foundation

````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 2 sur 13. Remplacer :

````swift
    /// Aucun evenement `ordre` sous le delai de la politique : il s'est perdu.
    case ordrePerdu
    /// Pas de `reponse` sous 3 s, sans `debut` (pas de reemission).
    case sansReponse
    /// `debut` recu, puis un bloc `sante` (ou un `hb`) qui ne porte plus son id :
````

par :

````swift
    /// Aucun evenement `ordre` sous le delai de la politique : il s'est perdu.
    case ordrePerdu
    /// Pas de `reponse` sous le delai de la politique, sans `debut` (par l'USB, 3 s sans
    /// reemission ; a distance, 6 s apres deux renvois du meme `id`).
    case sansReponse
    /// `debut` recu, puis un bloc `sante` (ou un `hb`) qui ne porte plus son id :
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 3 sur 13. Remplacer :

````swift
    public internal(set) var debutA: TimeInterval?
    public internal(set) var termineeA: TimeInterval?
}

/// Delais de la correlation par l'USB (6.4) : "sans reponse" a 3 s, pas de
/// renvoi ; un ordre accepte sans evenement `ordre` sous 10 s (un abandon prend
/// moins de 4 s) est tenu pour perdu. Thread viendra au plan 3b-2.
public struct PolitiqueDelais: Sendable, Equatable {
    public var delaiReponse: TimeInterval
    public var delaiOrdre: TimeInterval

    public static let usb = PolitiqueDelais(delaiReponse: 3, delaiOrdre: 10)
}

````

par :

````swift
    public internal(set) var debutA: TimeInterval?
    public internal(set) var termineeA: TimeInterval?
    /// Renvois du meme `id` (reseau, 10.4).
    public internal(set) var renvois = 0
}

/// Delais de la correlation selon le transport (6.4, 10.4). L'USB ne perd rien :
/// pas de renvoi, "sans reponse" a 3 s. Le reseau perd : une commande sans aucune
/// reponse repart avec le meme `id` a 2 s puis 4 s (le pont rend la reponse gardee
/// sans executer de nouveau, ou ignore le renvoi d'une commande encore en cours),
/// "sans reponse" a 6 s, ou a 12 s pour une commande dont la `fin` suit un instantane
/// (`delaiInstantane`). Dans les deux cas, un ordre accepte sans evenement `ordre`
/// sous 10 s (un abandon prend moins de 4 s) est tenu pour perdu.
public struct PolitiqueDelais: Sendable, Equatable {
    public var delaiReponse: TimeInterval
    /// `json 1`, `json etat`, `json hello` : la `fin` part apres la derniere ligne de
    /// l'instantane (6.2). Par l'USB, il part en moins d'une demi-seconde : le delai
    /// ordinaire suffit. A distance, il passe a 3 000 octets par seconde au plus, partages
    /// entre les sessions (10.3) : 3,6 s seul a 16 lampes, un peu plus de 8 s a deux.
    public var delaiInstantane: TimeInterval
    public var delaiOrdre: TimeInterval
    /// Premier renvoi a `delaiRenvoi`, le suivant a 2 x `delaiRenvoi`...
    public var delaiRenvoi: TimeInterval
    public var renvois: Int

    /// `delaiInstantane` : `delaiReponse` s'il n'est pas donne.
    public init(delaiReponse: TimeInterval, delaiOrdre: TimeInterval, delaiRenvoi: TimeInterval = 0, renvois: Int = 0,
                delaiInstantane: TimeInterval? = nil) {
        self.delaiReponse = delaiReponse
        self.delaiInstantane = delaiInstantane ?? delaiReponse
        self.delaiOrdre = delaiOrdre
        self.delaiRenvoi = delaiRenvoi
        self.renvois = renvois
    }

    public static let usb = PolitiqueDelais(delaiReponse: 3, delaiOrdre: 10)
    public static let reseau = PolitiqueDelais(delaiReponse: 6, delaiOrdre: 10, delaiRenvoi: 2, renvois: 2, delaiInstantane: 12)

    public static func pour(_ genre: GenreTransport) -> PolitiqueDelais {
        genre == .udp ? .reseau : .usb
    }

    /// Delai de la reponse de `commande` : celui de l'instantane pour `json 1`, `json etat`
    /// et `json hello` (`PolitiqueCommandes.repondApresInstantane`), sinon l'ordinaire.
    public func delaiReponse(pour commande: String) -> TimeInterval {
        PolitiqueCommandes.repondApresInstantane(commande) ? delaiInstantane : delaiReponse
    }
}

````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 4 sur 13. Remplacer :

````swift
    public static let intervalleMin: TimeInterval = 0.05

    public var politique = PolitiqueDelais.usb

````

par :

````swift
    public static let intervalleMin: TimeInterval = 0.05

    /// Delais en vigueur : USB par defaut ; le moteur de session regle le reseau.
    public var politique = PolitiqueDelais.usb

````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 5 sur 13. Remplacer :

````swift
    private var secrets: [UUID: String] = [:]
    public private(set) var enVol: UUID?
    private var prochainNumero = 1
    public private(set) var dernierEnvoiA: TimeInterval?
````

par :

````swift
    private var secrets: [UUID: String] = [:]
    public private(set) var enVol: UUID?
    /// La commande en vol etait secrete : sa ligne est oubliee, elle ne repart pas.
    private var enVolSecret = false
    private var prochainNumero = 1
    public private(set) var dernierEnvoiA: TimeInterval?
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 6 sur 13. Remplacer :

````swift
    }

    /// `secret` : la commande porte des cles ; seul son masque reste dans le suivi.
    @discardableResult
    public mutating func soumettre(_ commande: String, origine: OrigineCommande, fusion: String? = nil,
                                   secret: Bool = false, maintenant: TimeInterval) -> UUID {
        if let fusion {
            var gardees: [UUID] = []
````

par :

````swift
    }

    /// `secret` : la commande porte des cles ; seul son masque reste dans le suivi. Une
    /// commande que le masque change (`PolitiqueCommandes.masquerCle` : `mesh cles`,
    /// `json cle nouvelle`, sous toutes leurs formes) est secrete aussi, quel que soit
    /// l'appelant : un suivi ne garde jamais de cle.
    @discardableResult
    public mutating func soumettre(_ commande: String, origine: OrigineCommande, fusion: String? = nil,
                                   secret: Bool = false, maintenant: TimeInterval) -> UUID {
        let secret = secret || PolitiqueCommandes.masquerCle(commande) != commande
        if let fusion {
            var gardees: [UUID] = []
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 7 sur 13. Remplacer :

````swift
            guard let i = index(id) else { continue }
            let numero = prochainNumero
            switch LigneCommande.octets(secrets.removeValue(forKey: id) ?? suivis[i].commande, id: numero) {
            case .failure:
                suivis[i].etat = .terminee
````

par :

````swift
            guard let i = index(id) else { continue }
            let numero = prochainNumero
            let secret = secrets.removeValue(forKey: id)
            switch LigneCommande.octets(secret ?? suivis[i].commande, id: numero) {
            case .failure:
                suivis[i].etat = .terminee
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 8 sur 13. Remplacer :

````swift
                suivis[i].envoyeeA = maintenant
                enVol = id
                dernierEnvoiA = maintenant
                return (id, numero, octets)
````

par :

````swift
                suivis[i].envoyeeA = maintenant
                enVol = id
                enVolSecret = secret != nil
                dernierEnvoiA = maintenant
                return (id, numero, octets)
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 9 sur 13. Remplacer :

````swift
        case inattendue
        case debut(UUID)
        /// `fin` : `ordreAttendu` si `suite` vaut `ordre`.
        case fin(UUID, ordreAttendu: Bool)
    }
````

par :

````swift
        case inattendue
        case debut(UUID)
        /// `fin` : `ordreAttendu` si `suite` vaut `ordre`. A distance, `deja_traite` est
        /// une `fin` aussi (10.4) : la reponse de cet `id` est oubliee, rien d'autre ne viendra.
        case fin(UUID, ordreAttendu: Bool)
    }
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 10 sur 13. Remplacer :

````swift
            return .debut(id)
        case .fin:
            suivis[i].fin = r
            suivis[i].termineeA = maintenant
            suivis[i].lampe = r.lampe
````

par :

````swift
            return .debut(id)
        case .fin:
            // Doublon (une reponse gardee rendue a un renvoi qui a croise la premiere) :
            // la fin est deja tenue, rien ne change.
            if suivis[i].fin != nil, suivis[i].etat != .sansReponse { return .inattendue }
            // `deja_traite` (10.4) clot le suivi comme une autre `fin`, comme sur Halo : le
            // pont a oublie la reponse de cet `id` (plus ancien que les 8 qu'il garde), et
            // la vraie ne viendra jamais. Le renvoi d'un `id` encore en cours, lui, est
            // ignore en silence (sa reponse viendra). Le moteur redemande `json etat`.
            suivis[i].fin = r.sansCle
            suivis[i].termineeA = maintenant
            suivis[i].lampe = r.lampe
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 11 sur 13. Remplacer :

````swift
    /// ordre arrive pendant un autre s'y est fondu (6.2). Les ordres plus anciens
    /// de la meme lampe, encore en attente, sont sortis de la liste du pont
    /// (`ids_perdus`) : ils prennent la meme issue.
    @discardableResult
    public mutating func recevoir(_ o: EvenementOrdre, maintenant: TimeInterval) -> [UUID] {
````

par :

````swift
    /// ordre arrive pendant un autre s'y est fondu (6.2). Les ordres plus anciens
    /// de la meme lampe, encore en attente, sont sortis de la liste du pont
    /// (`ids_perdus`) : ils prennent la meme issue. A distance, la reponse `accepte`
    /// peut s'etre perdue : l'evenement prouve l'acceptation, et finit aussi la commande
    /// encore `envoyee` (ou deja dite sans reponse) dont il porte l'`id` ; sa place en
    /// vol se libere (un renvoi ne ramenerait que l'`accepte` garde par le pont).
    @discardableResult
    public mutating func recevoir(_ o: EvenementOrdre, maintenant: TimeInterval) -> [UUID] {
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 12 sur 13. Remplacer :

````swift
        }
        var touches: [UUID] = []
        for i in suivis.indices where suivis[i].etat == .attenteOrdre && suivis[i].lampe == o.lampe {
            guard let n = suivis[i].numero, n <= plusGrand else { continue }
            suivis[i].etat = etat
            suivis[i].ordre = o
            suivis[i].termineeA = maintenant
            touches.append(suivis[i].id)
        }
        return touches
    }

````

par :

````swift
        }
        var touches: [UUID] = []
        for i in suivis.indices {
            guard let n = suivis[i].numero else { continue }
            let attendu = suivis[i].etat == .attenteOrdre && suivis[i].lampe == o.lampe && n <= plusGrand
            let sansAccepte = (suivis[i].etat == .envoyee || suivis[i].etat == .sansReponse) && ids.contains(n)
            guard attendu || sansAccepte else { continue }
            suivis[i].etat = etat
            suivis[i].ordre = o
            suivis[i].lampe = suivis[i].lampe ?? o.lampe
            suivis[i].termineeA = maintenant
            if enVol == suivis[i].id { enVol = nil }
            touches.append(suivis[i].id)
        }
        return touches
    }

    /// Message `texte` d'une session distante (10.4) : la ligne va a la commande de
    /// son `id`, comme le texte de la console par l'USB. Sans `debut` recu (perdu), il
    /// en tient lieu : le pont execute la commande, elle ne repart plus et n'est pas
    /// "sans reponse" ; un texte tardif (apres "sans reponse") rouvre de meme le suivi.
    @discardableResult
    public mutating func texte(_ ligne: String, id: Int, maintenant: TimeInterval) -> UUID? {
        guard let i = suivis.lastIndex(where: { $0.numero == id }) else { return nil }
        switch suivis[i].etat {
        case .enCours:
            break
        case .envoyee, .sansReponse:
            suivis[i].etat = .enCours
            suivis[i].debutA = suivis[i].debutA ?? maintenant
            suivis[i].termineeA = nil
        default:
            return nil
        }
        suivis[i].texte.append(ligne)
        if suivis[i].texte.count > 400 { suivis[i].texte.removeFirst() }
        return suivis[i].id
    }

````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift`, bloc 13 sur 13. Remplacer :

````swift
    }

    /// Commandes sans `reponse` sous le delai de la politique (et sans `debut`) : marquees, pas reemises ici.
    public mutating func verifierDelais(maintenant: TimeInterval) -> [SuiviCommande] {
        guard let id = enVol, let i = index(id), suivis[i].etat == .envoyee,
              let t = suivis[i].envoyeeA, maintenant - t >= politique.delaiReponse else { return [] }
        suivis[i].etat = .sansReponse
        suivis[i].termineeA = maintenant
        enVol = nil
        return [suivis[i]]
    }

````

par :

````swift
    }

    /// Commandes sans `reponse` sous le delai de la politique (et sans `debut`) : marquees,
    /// pas reemises ici. Le delai est celui de la commande : plus long a distance pour une
    /// commande dont la `fin` suit un instantane (`PolitiqueDelais.delaiReponse(pour:)`).
    public mutating func verifierDelais(maintenant: TimeInterval) -> [SuiviCommande] {
        guard let id = enVol, let i = index(id), suivis[i].etat == .envoyee,
              let t = suivis[i].envoyeeA, maintenant - t >= politique.delaiReponse(pour: suivis[i].commande)
        else { return [] }
        suivis[i].etat = .sansReponse
        suivis[i].termineeA = maintenant
        enVol = nil
        return [suivis[i]]
    }

    /// A distance (10.4) : la commande en vol sans aucune `reponse` repart, memes
    /// octets (meme `id`), a `delaiRenvoi` puis a 2 x `delaiRenvoi`. Jamais une
    /// commande secrete : sa ligne est oubliee des son envoi.
    public mutating func renvoisDus(maintenant: TimeInterval) -> [Data] {
        guard politique.renvois > 0, !enVolSecret, let id = enVol, let i = index(id), suivis[i].etat == .envoyee,
              suivis[i].renvois < politique.renvois, let t = suivis[i].envoyeeA, let n = suivis[i].numero,
              maintenant - t >= politique.delaiRenvoi * Double(suivis[i].renvois + 1),
              case .success(let octets) = LigneCommande.octets(suivis[i].commande, id: n)
        else { return [] }
        suivis[i].renvois += 1
        dernierEnvoiA = maintenant
        return [octets]
    }

````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 1 sur 18. Remplacer :

````swift
// Repris de Halo Compagnon (commit e114cd5) : par l'USB seulement (Thread au plan 3b-2),
// avec les blocs et l'evenement ordre du pont amaran (docs/PROTOCOLE-JSON.md 3 et 6).
import Foundation

````

par :

````swift
// Repris de Halo Compagnon (commit e114cd5) : par l'USB et par Thread (cas UDP de Halo),
// avec les blocs et l'evenement ordre du pont amaran (docs/PROTOCOLE-JSON.md 3, 6 et 10).
import Foundation

````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 2 sur 18. Remplacer :

````swift
        /// ... 3 fois.
        public var renvoisHello = 3
        /// Puis `\x15\n` et `json 1` toutes les 30 s, pas plus souvent.
        public var relanceLente: TimeInterval = 30
        /// `json ping` apres 10 s sans autre commande (bail de 30 s) ; plus tot
````

par :

````swift
        /// ... 3 fois.
        public var renvoisHello = 3
        /// Puis `\x15\n` et `json 1` toutes les 30 s, pas plus souvent. A
        /// distance, une nouvelle poignee de main a la place (voir `tic`).
        public var relanceLente: TimeInterval = 30
        /// `json ping` apres 10 s sans autre commande (bail de 30 s) ; plus tot
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 3 sur 18. Remplacer :

````swift
        /// elle est tenue pour perdue et la file repart.
        public var delaiFinJson1: TimeInterval = 3
        /// Silence : aucune ligne depuis 3 x max(periode, 2 s).
        public var facteurSilence: Double = 3
````

par :

````swift
        /// elle est tenue pour perdue et la file repart.
        public var delaiFinJson1: TimeInterval = 3
        /// A distance : l'instantane de `json 1` (42 lignes, ~11 Ko a 16 lampes) passe a
        /// 3 000 octets par seconde au plus sur Thread, partages entre deux sessions
        /// (10.3) : 3,6 s seul, un peu plus de 8 s a deux ; sa `fin` est attendue 12 s,
        /// comme celle de `json etat` et `json hello` (`PolitiqueDelais.delaiInstantane`).
        public var delaiFinJson1Reseau: TimeInterval = PolitiqueDelais.reseau.delaiInstantane
        /// Bail demande a distance (`json 1 bail <s>`, 10 a 120 s permis, 10.5) : plus
        /// long que par l'USB, Thread perd des datagrammes ; le ping part au plus tard
        /// toutes les 10 s.
        public var bailDistantS = 60
        /// Silence : aucune ligne depuis 3 x max(periode, 2 s).
        public var facteurSilence: Double = 3
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 4 sur 18. Remplacer :

````swift
        /// `Unrecognized command` : firmware sans mode JSON.
        case ancienFirmware
        /// Aucune reponse : ecoute, `json 1` toutes les 30 s.
        case sansReponse
        /// `hello` d'une version majeure non geree : console seule.
````

par :

````swift
        /// `Unrecognized command` : firmware sans mode JSON.
        case ancienFirmware
        /// Aucune reponse : ecoute, `json 1` toutes les 30 s (a distance :
        /// nouvelle poignee de main toutes les 30 s).
        case sansReponse
        /// `hello` d'une version majeure non geree : console seule.
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 5 sur 18. Remplacer :

````swift
        /// `fin` `bail` : `json 1` renvoye.
        case bailEchu

        /// Montree en bandeau (echec de la connexion).
````

par :

````swift
        /// `fin` `bail` : `json 1` renvoye.
        case bailEchu
        /// A distance, toujours aucun `hello` (relance de 30 s ou "Reessayer") :
        /// nouvelle poignee de main. Le pont a oublie la session H1 provisoire (30 s
        /// sans premier message, 10.3) : un `json 1` scelle pour elle serait ecarte
        /// sans bruit.
        case reseauSansHello

        /// Montree en bandeau (echec de la connexion).
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 6 sur 18. Remplacer :

````swift
            case .bailEchu:
                "Le pont a quitté le mode machine (bail échu) : json 1 renvoyé."
            }
        }
````

par :

````swift
            case .bailEchu:
                "Le pont a quitté le mode machine (bail échu) : json 1 renvoyé."
            case .reseauSansHello:
                "Aucune réponse au json 1 par le réseau : nouvelle poignée de main."
            }
        }
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 7 sur 18. Remplacer :

````swift

    public var parametres = Parametres()
    public private(set) var phase: Phase = .ferme
    public private(set) var correlateur = Correlateur()
    public private(set) var statistiques = StatistiquesLien()
    /// Reglages de session en vigueur : ceux du `hello`, puis ceux des
    /// commandes `json periode|lampes|compteurs|reseau|log` acceptees (3.3).
    /// Valeurs par defaut de `json 1` tant qu'aucun `hello` n'est arrive.
    public private(set) var reglages = HelloBase.ReglagesSession(
        periodeMs: 1000, lampesMs: 10000, compteursMs: 1000, reseauMs: 5000, bailS: 30, log: false)
    public var periodeMs: Int { reglages.periodeMs ?? 1000 }
    public var bailS: Int? { reglages.bailS }
````

par :

````swift

    public var parametres = Parametres()
    /// Transport de la connexion en cours (regles du reseau, 10.4).
    public private(set) var genre: GenreTransport = .usb
    public private(set) var phase: Phase = .ferme
    public private(set) var correlateur = Correlateur()
    public private(set) var statistiques = StatistiquesLien()
    /// Reglages de session en vigueur : ceux du `hello`, puis ceux des
    /// commandes `json periode|lampes|compteurs|reseau|log|trames` acceptees (3.3).
    /// Valeurs par defaut de `json 1` (profil USB ou distant) tant qu'aucun `hello`
    /// n'est arrive.
    public private(set) var reglages = Self.reglagesParDefaut(.usb, bailDistantS: 60)
    public var periodeMs: Int { reglages.periodeMs ?? 1000 }
    public var bailS: Int? { reglages.bailS }
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 8 sur 18. Remplacer :

````swift
    public var instantaneEnCours: Bool { json1 != nil }

    private var json1: (numero: Int, envoyeA: TimeInterval)?
    private var dernierEssaiA: TimeInterval = 0
    private var dernierRecuA: TimeInterval = 0
````

par :

````swift
    public var instantaneEnCours: Bool { json1 != nil }

    /// `json 1` en attente de sa `reponse` `fin` ; `repondu` : une `fin` est arrivee
    /// sans le `hello` de cette tentative, ou `deja_traite` (reponse oubliee) : le renvoi
    /// prend alors un id neuf.
    private var json1: (numero: Int, envoyeA: TimeInterval, repondu: Bool)?
    private var dernierEssaiA: TimeInterval = 0
    private var dernierRecuA: TimeInterval = 0
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 9 sur 18. Remplacer :

````swift
    // MARK: - Entrees

    /// Transport ouvert : `\x15\n` puis `id=1 json 1` (3.2).
    public mutating func ouvert(maintenant: TimeInterval) -> [Effet] {
        correlateur.reinitialiser(maintenant: maintenant)
        statistiques.connexions += 1
````

par :

````swift
    // MARK: - Entrees

    /// Reglages qu'annonce `json 1` (3.3) : profil de l'USB, ou profil distant (10.5).
    public static func reglagesParDefaut(_ genre: GenreTransport, bailDistantS: Int) -> HelloBase.ReglagesSession {
        genre == .udp
            ? HelloBase.ReglagesSession(transport: .udp, periodeMs: 2000, lampesMs: 30000, compteursMs: 0, reseauMs: 30000,
                                        bailS: bailDistantS, log: false, trames: false)
            : HelloBase.ReglagesSession(transport: .usb, periodeMs: 1000, lampesMs: 10000, compteursMs: 1000,
                                        reseauMs: 5000, bailS: 30, log: false, trames: false)
    }

    /// Transport ouvert : `\x15\n` puis `id=1 json 1` (3.2). A distance, pas de
    /// Ctrl-U (pas de ligne en cours a effacer ; le pont ignore une ligne sans id),
    /// la politique reseau du correlateur, et un bail permis a distance.
    public mutating func ouvert(maintenant: TimeInterval, genre: GenreTransport = .usb) -> [Effet] {
        self.genre = genre
        correlateur.politique = .pour(genre)
        reglages = Self.reglagesParDefaut(genre, bailDistantS: parametres.bailDistantS)
        correlateur.reinitialiser(maintenant: maintenant)
        statistiques.connexions += 1
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 10 sur 18. Remplacer :

````swift
    }

    private var effacement: [Effet] { [.envoyer(LigneCommande.effacement)] }

    /// Transport ferme (cable, re-enumeration, liberation du port).
````

par :

````swift
    }

    private var effacement: [Effet] { genre == .udp ? [] : [.envoyer(LigneCommande.effacement)] }

    /// Transport ferme (cable, re-enumeration, liberation du port).
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 11 sur 18. Remplacer :

````swift

    /// Relance manuelle apres un echec (firmware flashe depuis, bouton "Reessayer").
    public mutating func reessayer(maintenant: TimeInterval) -> [Effet] {
        guard phase != .ferme else { return [] }
        phase = .attenteHello(essai: 1)
        return effacement + envoyerJson1(maintenant: maintenant)
````

par :

````swift

    /// Relance manuelle apres un echec (firmware flashe depuis, bouton "Reessayer").
    /// A distance : nouvelle poignee de main, comme la relance de 30 s.
    public mutating func reessayer(maintenant: TimeInterval) -> [Effet] {
        guard phase != .ferme else { return [] }
        if genre == .udp { return rouvrirADistance(maintenant: maintenant) }
        phase = .attenteHello(essai: 1)
        return effacement + envoyerJson1(maintenant: maintenant)
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 12 sur 18. Remplacer :

````swift
                if essai <= parametres.renvoisHello {
                    phase = .attenteHello(essai: essai + 1)
                    effets += envoyerJson1(maintenant: maintenant)
                } else {
                    phase = .sansReponse
````

par :

````swift
                if essai <= parametres.renvoisHello {
                    phase = .attenteHello(essai: essai + 1)
                    effets += envoyerJson1(maintenant: maintenant, renvoi: true)
                } else {
                    phase = .sansReponse
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 13 sur 18. Remplacer :

````swift
        case .sansReponse:
            if maintenant - dernierEssaiA >= parametres.relanceLente {
                effets += effacement
                effets += envoyerJson1(maintenant: maintenant)
            }
        case .connecte:
            if let j = json1, maintenant - j.envoyeA >= parametres.delaiFinJson1 {
                // hello recu mais pas la reponse fin (ligne perdue ou abimee) : la file repart.
                json1 = nil
````

par :

````swift
        case .sansReponse:
            if maintenant - dernierEssaiA >= parametres.relanceLente {
                if genre == .udp {
                    effets += rouvrirADistance(maintenant: maintenant)
                } else {
                    effets += effacement
                    effets += envoyerJson1(maintenant: maintenant)
                }
            }
        case .connecte:
            let delaiFin = genre == .udp ? parametres.delaiFinJson1Reseau : parametres.delaiFinJson1
            if let j = json1, maintenant - j.envoyeA >= delaiFin {
                // hello recu mais pas la reponse fin (ligne perdue ou abimee) : la file repart.
                json1 = nil
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 14 sur 18. Remplacer :

````swift

        if phase.modeMachine {
            for s in correlateur.verifierOrdres(maintenant: maintenant) { effets.append(.ordrePerdu(s.id)) }
            for s in correlateur.verifierDelais(maintenant: maintenant) {
````

par :

````swift

        if phase.modeMachine {
            for d in correlateur.renvoisDus(maintenant: maintenant) { effets.append(.envoyer(d)) }
            for s in correlateur.verifierOrdres(maintenant: maintenant) { effets.append(.ordrePerdu(s.id)) }
            for s in correlateur.verifierDelais(maintenant: maintenant) {
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 15 sur 18. Remplacer :

````swift
    }

    /// `json 1`, idempotent : chaque renvoi a son propre `id`.
    private mutating func envoyerJson1(maintenant: TimeInterval) -> [Effet] {
        let n = correlateur.reserverNumero()
        json1 = (n, maintenant)
        dernierEssaiA = maintenant
        correlateur.noterEnvoiHorsFile(maintenant: maintenant)
        return [.envoyer(Data("id=\(n) json 1\n".utf8))]
    }

````

par :

````swift
    }

    /// Ligne `json 1` : par l'USB, le bail par defaut (30 s) ; a distance, `json 1
    /// bail <bailDistantS>`, ramene dans les bornes permises (10 a 120 s, 10.5).
    public var ligneJson1: String {
        genre == .udp ? "json 1 bail \(min(max(parametres.bailDistantS, 10), 120))" : "json 1"
    }

    /// `json 1`, idempotent : par l'USB, chaque renvoi a son propre `id`. A distance,
    /// un renvoi garde son `id` (10.4) : si le premier est arrive, le pont ne refait
    /// pas l'instantane (il ignore le renvoi tant qu'il l'envoie, puis rend sa
    /// reponse gardee) ; mais un `json 1` dont la `fin` est arrivee sans `hello`
    /// (hello perdu), ou dont la reponse est oubliee (`deja_traite`), repart avec un
    /// id neuf, pour un nouvel instantane.
    private mutating func envoyerJson1(maintenant: TimeInterval, renvoi: Bool = false) -> [Effet] {
        let n: Int
        if renvoi, genre == .udp, let j = json1, !j.repondu { n = j.numero } else { n = correlateur.reserverNumero() }
        json1 = (n, maintenant, false)
        dernierEssaiA = maintenant
        correlateur.noterEnvoiHorsFile(maintenant: maintenant)
        return [.envoyer(Data("id=\(n) \(ligneJson1)\n".utf8))]
    }

    /// A distance, relancer c'est refaire la poignee de main : le pont oublie la
    /// session H1 provisoire 30 s apres son SALUT (10.3). `dernierEssaiA` repousse la
    /// relance suivante : pas de second `.rouvrir` avant que la fermeture ne remette
    /// le moteur a `.ferme` (puis `ouvert` au transport suivant).
    private mutating func rouvrirADistance(maintenant: TimeInterval) -> [Effet] {
        dernierEssaiA = maintenant
        statistiques.reouvertures += 1
        return [.rouvrir(.reseauSansHello)]
    }

````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 16 sur 18. Remplacer :

````swift
                // reponse sans hello (hello perdu, coupe par un log, ok:false,
                // cadence) laisse json1 pose et le minuteur renvoie json 1
                // (idempotent). Apres le hello, la reponse fin libere la file.
                if r.etape == .fin, phase == .connecte { json1 = nil }
            } else if case .fin(let id, _) = correlateur.recevoir(r, maintenant: maintenant) {
                if r.ok, let s = correlateur.suivi(id) { appliquerReglage(s.commande) }
            }
        case .ordre(let o):
            correlateur.recevoir(o, maintenant: maintenant)
````

par :

````swift
                // reponse sans hello (hello perdu, coupe par un log, ok:false,
                // cadence) laisse json1 pose et le minuteur renvoie json 1
                // (idempotent ; a distance, avec un id neuf). Apres le hello, la reponse
                // fin libere la file. `deja_traite` (10.4) est une fin comme les autres :
                // la reponse est oubliee, aucune autre ne viendra pour cet id.
                if r.etape == .fin {
                    if phase == .connecte { json1 = nil } else { json1?.repondu = true }
                }
            } else if case .fin(let id, _) = correlateur.recevoir(r, maintenant: maintenant) {
                if r.ok, let s = correlateur.suivi(id) { appliquerReglage(s.commande) }
                // A distance, `deja_traite` : le pont a oublie la reponse (10.4), l'etat a
                // pu changer sans que l'app le sache : instantane, comme Halo.
                if r.code == .dejaTraite { correlateur.soumettre("json etat", origine: .session, maintenant: maintenant) }
            }
        case .texte(let t):
            correlateur.texte(t.txt ?? "", id: t.id, maintenant: maintenant)
        case .ordre(let o):
            correlateur.recevoir(o, maintenant: maintenant)
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 17 sur 18. Remplacer :

````swift
    /// Reglages annonces par un `hello` (les champs absents gardent leur valeur).
    private mutating func adopterReglages(_ s: HelloBase.ReglagesSession) {
        if let v = s.periodeMs { reglages.periodeMs = v }
        if let v = s.lampesMs { reglages.lampesMs = v }
````

par :

````swift
    /// Reglages annonces par un `hello` (les champs absents gardent leur valeur).
    private mutating func adopterReglages(_ s: HelloBase.ReglagesSession) {
        if let v = s.transport { reglages.transport = v }
        if let v = s.periodeMs { reglages.periodeMs = v }
        if let v = s.lampesMs { reglages.lampesMs = v }
````

`apps/macos/AmaranProtocole/Session/MoteurSession.swift`, bloc 18 sur 18. Remplacer :

````swift
        if let v = s.bailS { reglages.bailS = v }
        if let v = s.log { reglages.log = v }
    }

    /// `json periode|lampes|compteurs|reseau <ms>`, `json log 0|1` acceptes (y
    /// compris tapes dans la console) : les reglages suivent, et le seuil de
    /// silence avec la periode.
    private mutating func appliquerReglage(_ commande: String) {
        let m = LigneCommande.mots(commande)
        guard m.count == 3, m[0] == "json" else { return }
        switch m[1] {
        case "periode": if let v = Int(m[2]) { reglages.periodeMs = v }
        case "lampes": if let v = Int(m[2]) { reglages.lampesMs = v }
        case "compteurs": if let v = Int(m[2]) { reglages.compteursMs = v }
        case "reseau": if let v = Int(m[2]) { reglages.reseauMs = v }
        case "log" where m[2] == "0" || m[2] == "1": reglages.log = m[2] == "1"
        default: break
        }
    }
}
````

par :

````swift
        if let v = s.bailS { reglages.bailS = v }
        if let v = s.log { reglages.log = v }
        if let v = s.trames { reglages.trames = v }
    }

    /// `json periode|lampes|compteurs|reseau <ms>`, `json log|trames 0|1` acceptes (y
    /// compris tapes dans la console) : les reglages suivent, et le seuil de
    /// silence avec la periode. La commande est lue comme la console du pont la
    /// decoupe (`LigneCommande.argv`, sensible a la casse) : `js\xon compteurs 5000`,
    /// que le pont execute comme `json compteurs 5000`, regle bien les compteurs.
    private mutating func appliquerReglage(_ commande: String) {
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        guard a.count == 3, a[0] == "json" else { return }
        switch a[1] {
        case "periode": if let v = Int(a[2]) { reglages.periodeMs = v }
        case "lampes": if let v = Int(a[2]) { reglages.lampesMs = v }
        case "compteurs": if let v = Int(a[2]) { reglages.compteursMs = v }
        case "reseau": if let v = Int(a[2]) { reglages.reseauMs = v }
        case "log" where a[2] == "0" || a[2] == "1": reglages.log = a[2] == "1"
        case "trames" where a[2] == "0" || a[2] == "1": reglages.trames = a[2] == "1"
        default: break
        }
    }

    // MARK: - Cadences (3.3, 10.5)

    /// Les cadences de session que l'app peut demander.
    public enum Cadence: String, Sendable, CaseIterable {
        /// Blocs `etat` `pont` et `sante`.
        case periode
        /// Toutes les lignes `etat` `lampe`.
        case lampes
        case compteurs
        case reseau
    }

    /// Bornes d'une cadence non nulle (0 la coupe) : celles de la commande `json`
    /// (3.3) par l'USB, celles de la liste blanche (10.5) a distance.
    public static func bornes(_ c: Cadence, genre: GenreTransport) -> ClosedRange<Int> {
        if genre == .udp, let min = PolitiqueCommandes.bornesDistantes.first(where: { $0.0 == c.rawValue })?.1 {
            return min...60_000
        }
        switch c {
        case .periode, .compteurs: return 200...60_000
        case .lampes, .reseau: return 1_000...60_000
        }
    }

    /// Ligne `json <cadence> <ms>` ramenee dans les bornes du transport en cours :
    /// le moteur ne demande jamais a distance une cadence que la liste blanche
    /// refuserait (0 reste 0 : coupe).
    public func ligneCadence(_ c: Cadence, ms: Int) -> String {
        let b = Self.bornes(c, genre: genre)
        let v = ms <= 0 ? 0 : min(max(ms, b.lowerBound), b.upperBound)
        return "json \(c.rawValue) \(v)"
    }
}
````

`apps/macos/AmaranProtocole/Reseau/EnveloppeH1.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : enveloppe H1 du transport reseau, octet pour octet (le pont est un port du meme code H1).
import CryptoKit
import Foundation

/// Enveloppe H1 du transport reseau (spec 3b, section 7), code pur.
/// MAC = 16 premiers octets de HMAC-SHA256, ecrits en 32 hexa MAJUSCULES ;
/// seuls les textes canoniques passent (hexa majuscule, `ctr` decimal sans
/// zero de tete).
public enum H1 {
    /// Hexa MAJUSCULE.
    public static func hexa<S: Sequence>(_ octets: S) -> String where S.Element == UInt8 {
        let chiffres = Array("0123456789ABCDEF".utf8)
        var s: [UInt8] = []
        for o in octets {
            s.append(chiffres[Int(o >> 4)])
            s.append(chiffres[Int(o & 0x0F)])
        }
        return String(decoding: s, as: UTF8.self)
    }

    /// Octets d'un texte hexa MAJUSCULE de longueur paire ; nil sinon.
    public static func octets(hexa: String) -> Data? {
        let u = Array(hexa.utf8)
        guard u.count % 2 == 0 else { return nil }
        func valeur(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x37
            default: return nil
            }
        }
        var d = Data(capacity: u.count / 2)
        for i in stride(from: 0, to: u.count, by: 2) {
            guard let h = valeur(u[i]), let l = valeur(u[i + 1]) else { return nil }
            d.append(h << 4 | l)
        }
        return d
    }

    /// `n` octets d'un generateur cryptographique.
    public static func aleatoire(_ n: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: n * 8)).withUnsafeBytes { Data($0) }
    }

    /// `kid` : 8 premiers hexa de SHA-256(cle).
    public static func kid(cle: Data) -> String {
        String(hexa(SHA256.hash(data: cle)).prefix(8))
    }

    static func mac(_ cle: SymmetricKey, _ message: Data) -> String {
        hexa(HMAC<SHA256>.authenticationCode(for: message, using: cle).prefix(16))
    }

    /// SALUT signe (83 octets) : `H1 SALUT <kid> <na> <mac_salut>`.
    public static func salut(cle: Data, na: Data) -> Data {
        let k = kid(cle: cle), n = hexa(na)
        let m = mac(SymmetricKey(data: cle), Data("H1|SALUT|\(k)|\(n)".utf8))
        return Data("H1 SALUT \(k) \(n) \(m)".utf8)
    }

    /// DEFI au MAC juste pour ce `na` : `(sid, nc)`. Sinon nil (DEFI d'un
    /// essai precedent, faux, ou autre datagramme).
    public static func verifierDefi(_ datagramme: Data, cle: Data, na: Data) -> (sid: String, nc: String)? {
        let champs = datagramme.split(separator: 0x20, omittingEmptySubsequences: false)
        guard champs.count == 5, champs[0].elementsEqual("H1".utf8), champs[1].elementsEqual("DEFI".utf8),
              estHexa(champs[2], longueur: 8), estHexa(champs[3], longueur: 32), estHexa(champs[4], longueur: 32)
        else { return nil }
        let sid = String(decoding: champs[2], as: UTF8.self)
        let nc = String(decoding: champs[3], as: UTF8.self)
        let attendu = mac(SymmetricKey(data: cle), Data("H1|DEFI|\(kid(cle: cle))|\(hexa(na))|\(nc)|\(sid)".utf8))
        guard egaux(Data(attendu.utf8), champs[4]) else { return nil }
        return (sid, nc)
    }

    /// Ks = HMAC-SHA256(PSK, `"H1|SESSION|" na "|" nc "|" sid`).
    public static func cleSession(cle: Data, na: Data, nc: String, sid: String) -> SymmetricKey {
        let code = HMAC<SHA256>.authenticationCode(for: Data("H1|SESSION|\(hexa(na))|\(nc)|\(sid)".utf8),
                                                  using: SymmetricKey(data: cle))
        return SymmetricKey(data: Data(code))
    }

    static func estHexa(_ s: Data, longueur: Int) -> Bool {
        s.count == longueur && s.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x46).contains($0) }
    }

    /// Comparaison en temps constant (les longueurs sont publiques).
    static func egaux(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var d: UInt8 = 0
        for (x, y) in zip(a, b) { d |= x ^ y }
        return d == 0
    }
}

/// Fenetre anti-rejeu de 32 : `ctr` strictement croissant, desordre
/// admis sur 32. A juger APRES le MAC : un `ctr` forge ne la pousse jamais.
public struct FenetreAntiRejeu: Sendable, Equatable {
    public private(set) var haut: UInt32 = 0
    private var bits: UInt32 = 0

    public init() {}

    public mutating func accepter(_ ctr: UInt32) -> Bool {
        guard ctr != 0 else { return false }
        if ctr > haut {
            let saut = ctr - haut
            bits = saut >= 32 ? 0 : bits << saut
            bits |= 1
            haut = ctr
            return true
        }
        let recul = haut - ctr
        guard recul < 32, bits & (1 << recul) == 0 else { return false }
        bits |= 1 << recul
        return true
    }
}

/// Session H1 etablie : scelle les lignes de l'app (sens `A`), ouvre les
/// datagrammes de la carte (sens `C`).
public struct SessionH1: Sendable {
    public let sid: String
    /// Ks, gardee en octets (valeur `Sendable`).
    private let ks: Data
    public private(set) var ctrEmis: UInt32 = 0
    /// Datagrammes ecartes (forme, sid, MAC, rejeu) depuis l'ouverture.
    public private(set) var ecartes = 0
    private var fenetre = FenetreAntiRejeu()

    public init(sid: String, ks: SymmetricKey) {
        self.sid = sid
        self.ks = ks.withUnsafeBytes { Data($0) }
    }

    /// `H1 <sid> <ctr> <mac> <ligne>`, `ctr` +1 a chaque appel (4 milliards
    /// de messages par session : jamais atteint, la session dure 10 min sans message).
    public mutating func sceller(_ ligne: Data) -> Data {
        ctrEmis &+= 1
        let m = H1.mac(SymmetricKey(data: ks), Data("A|\(sid)|\(ctrEmis)|".utf8) + ligne)
        return Data("H1 \(sid) \(ctrEmis) \(m) ".utf8) + ligne
    }

    /// Charge d'un message `C` valide (forme canonique, `sid`, MAC, fenetre) ;
    /// sinon nil, et `ecartes` +1.
    public mutating func ouvrir(_ datagramme: Data) -> Data? {
        guard let charge = verifier(datagramme) else {
            ecartes += 1
            return nil
        }
        return charge
    }

    private mutating func verifier(_ d: Data) -> Data? {
        // H1 <sid> <ctr> <mac> <charge> : les 4 premieres espaces separent les champs.
        let champs = d.split(separator: 0x20, maxSplits: 4, omittingEmptySubsequences: false)
        guard champs.count == 5, champs[0].elementsEqual("H1".utf8), champs[1].elementsEqual(sid.utf8),
              let ctr = Self.ctrCanonique(champs[2]), H1.estHexa(champs[3], longueur: 32)
        else { return nil }
        let charge = champs[4]
        let attendu = H1.mac(SymmetricKey(data: ks), Data("C|\(sid)|\(ctr)|".utf8) + charge)
        guard H1.egaux(Data(attendu.utf8), champs[3]), fenetre.accepter(ctr) else { return nil }
        return Data(charge)
    }

    /// `ctr` decimal sans zero de tete, 1..4294967295.
    static func ctrCanonique(_ s: Data) -> UInt32? {
        guard (1...10).contains(s.count), s.first != 0x30, s.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return UInt32(String(decoding: s, as: UTF8.self))
    }
}
````

`apps/macos/AmaranProtocole/Reseau/CleReseau.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : cle UDP de 32 octets creee par l'USB, code pur (sans le bloc `ip`, hors plan 3b-2).
import Foundation

/// Cle partagee du transport reseau, creee par l'USB (spec 3b, section 7) : l'app fournit
/// un alea, la carte calcule `cle = HMAC-SHA256(alea_app, alea_carte)` et la
/// rend une seule fois dans la reponse.
public enum CleReseau {
    /// Alea de l'app : 32 octets d'un generateur cryptographique.
    public static func alea() -> Data { H1.aleatoire(32) }

    /// `json cle nouvelle <64 HEXA>` (USB seulement ; la carte la refuse a distance).
    public static func commande(alea: Data) -> String {
        "json cle nouvelle \(H1.hexa(alea))"
    }

    public struct Creee: Sendable, Equatable {
        public var cle: Data
        public var empreinte: String
    }

    public enum Erreur: Error, Sendable, Equatable, CustomStringConvertible {
        /// `ok` faux (tampon USB occupe...) : rien n'a change sur la carte.
        case refusee(String)
        case cleIllisible
        case empreinteIncoherente

        public var description: String {
            switch self {
            case .refusee(let msg): "La carte refuse la nouvelle clé : \(msg)"
            case .cleIllisible: "Réponse sans clé lisible (64 hexa majuscules attendus) : clé non rangée."
            case .empreinteIncoherente: "Empreinte incohérente avec la clé reçue : clé non rangée."
            }
        }
    }

    /// Reponse `fin` a `json cle nouvelle` : la cle et son empreinte, verifiees.
    public static func verifier(_ r: Reponse) -> Result<Creee, Erreur> {
        guard r.ok else { return .failure(.refusee(r.msg ?? r.code.rawValue)) }
        guard let texte = r.cle, let cle = H1.octets(hexa: texte), cle.count == 32 else { return .failure(.cleIllisible) }
        guard let e = r.empreinte, e == H1.kid(cle: cle) else { return .failure(.empreinteIncoherente) }
        return .success(Creee(cle: cle, empreinte: e))
    }
}
````

- [ ] **Step 4 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `Test run with 166 tests in 20 suites passed` (`AmaranProtocoleTests`) et `Test run with 12 tests in 4 suites passed` (`AmaranCompagnonTests`) ; aucune ligne `error:` ni `warning:`.

- [ ] **Step 5 : commit.**

```bash
git add apps/macos/AmaranProtocole apps/macos/AmaranProtocoleTests
git commit -m "$(printf "App compagnon, protocole a distance : messages texte, trame et bloc ip, liste blanche miroir, masque des cles, politique reseau, enveloppe H1 et creation de la cle\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 6: Le transport UDP (Swift, Network.framework, repris de Halo, testé sur le Mac)

**Files:**
- Create: `apps/macos/AmaranProtocole/Reseau/ErreurReseau.swift`, `apps/macos/AmaranProtocole/Transport/TransportUDP.swift`
- Modify: `apps/macos/AmaranProtocole/Transport/Transport.swift`
- Create: `apps/macos/AmaranProtocoleTests/TransportUDPTests.swift`

**Interfaces:**
- Consumes : la Task 5 (`H1`, `SessionH1`, `GenreTransport.udp`) ; `Transport` et `EvenementTransport` du plan 3b-1.
- Produces (les Tasks 8 et 9 s'en servent) :
  - `final class TransportUDP: Transport` : `init(hote:cle:reglages:)`, genre `.udp` ;
  - `enum ErreurTransportReseau` (`reseauLocalRefuse`, `pasDeRoute`, `nomIntrouvable`, `portInjoignable`, `aucunDefi`, `cheminPerdu`, `autre`) avec `repriseAutomatique`, `bandeau`, `depuis(_:chemin:hote:)` (le nom `ErreurReseau` sert déjà aux clés du Mesh).

Pourquoi : la spec 3b, sections 7 et 9. `TransportUDP` (Network.framework) vise `<nom SRP>.local`, port 5480 : poignée de main SALUT/DEFI (un `na` neuf à chaque essai, seul le DEFI du dernier `na` compte, 2 s par essai, 3 essais), lignes scellées dans le sens `A`, datagrammes du pont ouverts dans le sens `C` après le MAC et la fenêtre anti-rejeu ; un datagramme est une ligne : le transport ajoute RS et LF à chaque datagramme reçu, pour que le tramage du plan 3b-1 serve tel quel. Ses erreurs sont classées pour le modèle (Task 8) : reprise seule ou non, bandeau ou non ; une route absente renvoie à `halo-routes`. Les tests jouent le pont avec un pair UDP local (`[::1]`) qui sait déformer le DEFI ; `AmaranProtocoleTests` n'est pas hébergé par l'app : sa sandbox interdirait cette socket.

Repris de Halo Compagnon (commit `e114cd5`) : `HaloProtocole/Transport/TransportUDP.swift`, `HaloProtocole/Reseau/ErreurReseau.swift` et leurs tests. Adapté : le nom `ErreurTransportReseau`, les textes en français sans `tr()`.

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranProtocoleTests/TransportUDPTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : poignee de main et dialogue contre un pont local sur [::1].
import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing
@testable import AmaranProtocole

/// Pont local sur [::1] : repond au SALUT par un DEFI, ouvre les messages A,
/// scelle des lignes C. `muet` : ne repond jamais. `mode` : deformations
/// volontaires du DEFI pour verifier que l'app les rejette.
final class PontLocal: Sendable {
    /// Deformations volontaires du DEFI (le SALUT reste verifie normalement : kid, MAC).
    enum Mode: Sendable, Equatable {
        case normal
        /// DEFI calcule pour le `na` de l'essai PRECEDENT (jamais celui de l'essai en cours).
        case defiNaPerime
        /// DEFI au bon kid/sid/nc/na, mais au MAC faux.
        case defiMacFaux
    }

    let port: UInt16
    private let fd: Int32
    private let cle: Data
    private let muet: Bool
    private let mode: Mode
    private struct Etat {
        var saluts = 0
        /// `na` de chaque SALUT recu (meme mute ou de mauvaise cle) : verifie qu'il est neuf a chaque essai.
        var nas: [Data] = []
        var naPrecedent: Data?
        var recues: [String] = []
        /// `ctr` de chaque message A accepte, dans le meme ordre que `recues`.
        var ctrsRecus: [UInt32] = []
        var session: (sid: String, ks: SymmetricKey, ctr: UInt32)?
        var pair: sockaddr_in6?
        var fini = false
    }
    private let etat = Mutex(Etat())

    init(cle: Data, muet: Bool = false, mode: Mode = .normal) throws {
        self.cle = cle
        self.muet = muet
        self.mode = mode
        // Descripteur garde dans un `let` local : une fermeture qui lirait la
        // propriete `fd` capturerait `self`, refuse avant que `port` le soit.
        let descripteur = socket(AF_INET6, SOCK_DGRAM, 0)
        fd = descripteur
        var a = sockaddr_in6()
        a.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        a.sin6_family = sa_family_t(AF_INET6)
        a.sin6_addr = in6addr_loopback
        let lie = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descripteur, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } }
        try #require(lie == 0)
        var l = socklen_t(MemoryLayout<sockaddr_in6>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descripteur, $0, &l) } }
        port = UInt16(bigEndian: a.sin6_port)
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let moi = self
        Thread.detachNewThread { moi.boucle() }
    }

    var saluts: Int { etat.withLock { $0.saluts } }
    var nas: [Data] { etat.withLock { $0.nas } }
    var recues: [String] { etat.withLock { $0.recues } }
    var ctrsRecus: [UInt32] { etat.withLock { $0.ctrsRecus } }

    func arreter() {
        etat.withLock { $0.fini = true }
    }

    /// Scelle une ligne de la carte (sens C) et l'envoie a l'app.
    func envoyer(_ json: String) {
        let (datagramme, pair): (Data?, sockaddr_in6?) = etat.withLock { e in
            guard var s = e.session else { return (nil, nil) }
            s.ctr += 1
            e.session = s
            let charge = Data(json.utf8)
            let m = H1.mac(s.ks, Data("C|\(s.sid)|\(s.ctr)|".utf8) + charge)
            return (Data("H1 \(s.sid) \(s.ctr) \(m) ".utf8) + charge, e.pair)
        }
        guard let datagramme, var pair else { return }
        _ = datagramme.withUnsafeBytes { b in withUnsafePointer(to: &pair) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, b.baseAddress, b.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } } }
    }

    private func boucle() {
        var tampon = [UInt8](repeating: 0, count: 2048)
        while !etat.withLock({ $0.fini }) {
            var de = sockaddr_in6()
            var l = socklen_t(MemoryLayout<sockaddr_in6>.size)
            let n = withUnsafeMutablePointer(to: &de) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &tampon, tampon.count, 0, $0, &l) } }
            guard n > 0 else { continue }
            recu(Data(tampon[0..<n]), de: de)
        }
        close(fd)
    }

    private func recu(_ d: Data, de: sockaddr_in6) {
        let champs = d.split(separator: 0x20, maxSplits: 4, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        if champs.count == 5, champs[1] == "SALUT" {
            salut(kid: champs[2], naHexa: champs[3], macSalut: champs[4], de: de)
            return
        }
        // Message A : MAC verifie avec Ks, charge et ctr gardes.
        etat.withLock { e in
            guard let s = e.session, champs.count == 5, champs[1] == s.sid, let ctr = UInt32(champs[2]) else { return }
            let attendu = H1.mac(s.ks, Data("A|\(s.sid)|\(champs[2])|".utf8) + Data(champs[4].utf8))
            if attendu == champs[3] {
                e.recues.append(champs[4])
                e.ctrsRecus.append(ctr)
                e.pair = de
            }
        }
    }

    private func salut(kid: String, naHexa: String, macSalut: String, de: sockaddr_in6) {
        let na = H1.octets(hexa: naHexa)
        etat.withLock { e in
            e.saluts += 1
            if let na { e.nas.append(na) }
        }
        guard !muet, let na, kid == H1.kid(cle: cle) else { return }
        // Le vrai pont ne repond qu'a un SALUT au MAC juste.
        let macAttendu = H1.mac(SymmetricKey(data: cle), Data("H1|SALUT|\(kid)|\(naHexa)".utf8))
        guard macAttendu == macSalut else { return }
        let sid = "5A5A0001", nc = H1.hexa(H1.aleatoire(16))
        let naPrecedent = etat.withLock { e -> Data? in
            let p = e.naPrecedent
            e.naPrecedent = na
            return p
        }
        if mode == .defiNaPerime, naPrecedent == nil { return }  // 1er essai : rien a perimer encore
        let naDuDefi = mode == .defiNaPerime ? (naPrecedent ?? na) : na
        var mac = H1.mac(SymmetricKey(data: cle), Data("H1|DEFI|\(kid)|\(H1.hexa(naDuDefi))|\(nc)|\(sid)".utf8))
        if mode == .defiMacFaux { mac = Self.abimer(mac) }
        etat.withLock { $0.session = (sid, H1.cleSession(cle: cle, na: na, nc: nc, sid: sid), 0); $0.pair = de }
        var pair = de
        let defi = Data("H1 DEFI \(sid) \(nc) \(mac)".utf8)
        _ = defi.withUnsafeBytes { b in withUnsafePointer(to: &pair) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, b.baseAddress, b.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } } }
    }

    /// Un hexa MAJUSCULE valide change en un autre, tout aussi valide (MAC faux, meme forme).
    private static func abimer(_ hexa: String) -> String {
        var c = Array(hexa)
        c[0] = c[0] == "A" ? "B" : "A"
        return String(c)
    }
}

/// Attend une condition, au plus `delai`.
func attendreQue(_ delai: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + delai
    while ContinuousClock.now < fin {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Premier evenement du flux, au plus `delai`.
func premier(_ flux: AsyncStream<EvenementTransport>, _ delai: Duration = .seconds(5)) async -> EvenementTransport? {
    await withTaskGroup(of: EvenementTransport?.self) { g in
        g.addTask { for await e in flux { return e }; return nil }
        g.addTask { try? await Task.sleep(for: delai); return nil }
        let r = await g.next() ?? nil
        g.cancelAll()
        return r
    }
}

@Suite("Transport UDP", .serialized)
struct TransportUDPTests {
    static func rapides(_ port: UInt16) -> TransportUDP.Reglages {
        var r = TransportUDP.Reglages()
        r.port = port
        r.attentePret = .seconds(2)
        r.attenteDefi = .milliseconds(300)
        return r
    }

    @Test func poigneeDeMainEtDialogue() async throws {
        let pont = try PontLocal(cle: VecteursH1.psk)
        defer { pont.arreter() }
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(pont.port))
        let flux = try await t.ouvrir()
        try t.envoyer(Data([0x15, 0x0A]) + Data("id=1 json 1\n".utf8))
        #expect(await attendreQue { pont.recues == ["id=1 json 1"] }, "Ctrl-U ecarte, ligne scellee")
        // Renvoi (renvoi) : memes octets renvoyes (meme id) ; ctr strictement croissant a chaque envoi.
        try t.envoyer(Data("id=1 json 1\n".utf8))
        #expect(await attendreQue { pont.recues == ["id=1 json 1", "id=1 json 1"] }, "meme ligne renvoyee, recue deux fois")
        #expect(pont.ctrsRecus.count == 2)
        #expect(pont.ctrsRecus[0] < pont.ctrsRecus[1], "ctr neuf a chaque envoi, meme ligne renvoyee")
        pont.envoyer(#"{"v":1,"t":"hb","n":0,"ms":1}"#)
        let e = await premier(flux)
        #expect(e == .donnees(Data([0x1E]) + Data(#"{"v":1,"t":"hb","n":0,"ms":1}"#.utf8) + Data([0x0A])))
        try t.envoyer(Data("id=2 json 0\n".utf8))
        t.fermerApresVidage(synchrone: false)
        #expect(await attendreQue { pont.recues.last == "id=2 json 0" }, "json 0 part avant la fermeture")
    }

    @Test func pontMuet() async throws {
        let pont = try PontLocal(cle: VecteursH1.psk, muet: true)
        defer { pont.arreter() }
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(pont.port))
        await #expect(throws: ErreurTransportReseau.aucunDefi) { _ = try await t.ouvrir() }
        #expect(pont.saluts == 3, "trois SALUT, na neuf a chaque essai")
        #expect(Set(pont.nas).count == 3, "les 3 na sont distincts")
    }

    @Test func autreCle() async throws {
        let pont = try PontLocal(cle: Data(repeating: 7, count: 32))
        defer { pont.arreter() }
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(pont.port))
        await #expect(throws: ErreurTransportReseau.aucunDefi) { _ = try await t.ouvrir() }
    }

    @Test func defiPourUnNaPerime() async throws {
        // Le pair repond, mais toujours avec le DEFI de l'essai precedent (jamais l'essai en cours) :
        // H1.verifierDefi le rejette a chaque fois (mac du DEFI juge sur le na courant).
        let pont = try PontLocal(cle: VecteursH1.psk, mode: .defiNaPerime)
        defer { pont.arreter() }
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(pont.port))
        await #expect(throws: ErreurTransportReseau.aucunDefi) { _ = try await t.ouvrir() }
    }

    @Test func defiAuMacFaux() async throws {
        // Le pair repond avec le bon kid/sid/nc/na mais un MAC de DEFI faux : rejete a chaque essai.
        let pont = try PontLocal(cle: VecteursH1.psk, mode: .defiMacFaux)
        defer { pont.arreter() }
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(pont.port))
        await #expect(throws: ErreurTransportReseau.aucunDefi) { _ = try await t.ouvrir() }
    }

    // Sur ce SDK, ::1 ne remonte PAS l'ICMPv6 "port injoignable" pendant les essais
    // (connexion .ready, les send de SALUT se terminent sans erreur, aucun changement
    // d'etat) : le `receiveMessage` deja pose ne recoit "Connection refused" que
    // 6 a 8 ms APRES `c.cancel()`, une fois les 3 essais deja epuises. D'ou
    // TransportUDP.echecPoignee : apres le dernier essai, annuler puis attendre
    // brievement (10 ms x 15, 150 ms au plus) l'erreur portee par ce receive en
    // attente. Fiable ici : 3/3 seul, 5/5 dans cette suite serialisee.
    @Test func portFerme() async throws {
        // Un port libre puis ferme : l'ICMPv6 "port injoignable" remonte (apres annulation).
        let libre = try PontLocal(cle: VecteursH1.psk)
        let port = libre.port
        libre.arreter()
        try await Task.sleep(for: .milliseconds(300))  // la boucle du pair ferme sa socket
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(port))
        await #expect(throws: ErreurTransportReseau.portInjoignable) { _ = try await t.ouvrir() }
    }

    /// Course de l'ouverture : un `.failed` ou une erreur de reception arrive
    /// apres le dernier coup d'oeil de la poignee de main, avant que le flux
    /// soit pose. `echec` n'avait alors aucun flux a fermer : le poser quand
    /// meme rendrait un flux qui ne recevrait jamais `.ferme`.
    @Test func echecAvantLaPoseDuFluxLaRefuse() throws {
        let session = SessionH1(sid: "5A5A0001", ks: SymmetricKey(data: VecteursH1.psk))
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk)
        t.echec(.pasDeRoute)
        let (_, suite) = AsyncStream.makeStream(of: EvenementTransport.self)
        #expect(throws: ErreurTransportReseau.pasDeRoute) { try t.adopter(session, suite) }
        // Fermeture demandee pendant l'ouverture, sans erreur gardee : refusee aussi.
        let f = TransportUDP(hote: "::1", cle: VecteursH1.psk)
        f.fermerApresVidage(synchrone: true)
        let (_, suiteF) = AsyncStream.makeStream(of: EvenementTransport.self)
        #expect(throws: ErreurTransport.self) { try f.adopter(session, suiteF) }
        // Sans echec ni fermeture : la session et le flux sont poses.
        let o = TransportUDP(hote: "::1", cle: VecteursH1.psk)
        let (_, suiteO) = AsyncStream.makeStream(of: EvenementTransport.self)
        try o.adopter(session, suiteO)
        o.fermerApresVidage(synchrone: true)
    }

    /// Session perdue apres l'ouverture (`.failed`, erreur de reception :
    /// ENETDOWN...) : le flux se ferme sur "Connexion réseau perdue : <cause>",
    /// pas sur le texte brut de la cause (4.6).
    @Test func perteEnSessionFermeSurConnexionPerdue() async throws {
        let pont = try PontLocal(cle: VecteursH1.psk)
        defer { pont.arreter() }
        let t = TransportUDP(hote: "::1", cle: VecteursH1.psk, reglages: Self.rapides(pont.port))
        let flux = try await t.ouvrir()
        t.echec(.pasDeRoute)
        let attendu = ErreurTransportReseau.cheminPerdu(ErreurTransportReseau.pasDeRoute.description).description
        #expect(await premier(flux) == .ferme(raison: attendu))
        #expect(TransportUDP.raisonPerte(.pasDeRoute) == attendu)
        #expect(attendu != ErreurTransportReseau.pasDeRoute.description)
    }

    /// Sans route, pas d'attente de 5 s : la connexion ne repartirait pas seule
    /// au retour de la route (banc du 25/09) ; le refus du reseau local, lui,
    /// attend (la reautorisation relance la connexion en attente).
    @Test func sansRouteAbandonneAvantOuverture() {
        #expect(TransportUDP.abandonAvantOuverture(.pasDeRoute))
        #expect(!TransportUDP.abandonAvantOuverture(.reseauLocalRefuse))
        #expect(!TransportUDP.abandonAvantOuverture(.nomIntrouvable("x.local")))
        #expect(!TransportUDP.abandonAvantOuverture(.autre("?")))
    }

    @Test func textes() {
        #expect(!ErreurTransportReseau.portInjoignable.repriseAutomatique)
        // Reseau local refuse : bandeau, mais la reconnexion reessaie (banc R7).
        #expect(ErreurTransportReseau.reseauLocalRefuse.repriseAutomatique)
        #expect(ErreurTransportReseau.pasDeRoute.repriseAutomatique)
        #expect(ErreurTransportReseau.reseauLocalRefuse.bandeau)
        #expect(ErreurTransportReseau.portInjoignable.bandeau)
        #expect(!ErreurTransportReseau.pasDeRoute.bandeau)
        #expect(!ErreurTransportReseau.nomIntrouvable("x.local").bandeau)
        #expect(ErreurTransportReseau.depuis(.posix(.EHOSTUNREACH), chemin: nil, hote: "x.local") == .pasDeRoute)
        #expect(ErreurTransportReseau.depuis(.posix(.ENETUNREACH), chemin: nil, hote: "x.local") == .pasDeRoute)
        #expect(ErreurTransportReseau.depuis(.posix(.ENETDOWN), chemin: nil, hote: "x.local") == .pasDeRoute)
        // ICMPv6 "adresse injoignable" : le noeud ne repond pas, la route n'y est pour rien.
        #expect(ErreurTransportReseau.depuis(.posix(.EHOSTDOWN), chemin: nil, hote: "x.local") == .nomIntrouvable("x.local"))
        #expect(ErreurTransportReseau.depuis(.posix(.ECONNREFUSED), chemin: nil, hote: "x.local") == .portInjoignable)
        // NoSuchRecord aussitot pour un nom .local : refus du reseau local
        // (banc R7) ; hors .local, c'est un vrai nom absent.
        #expect(ErreurTransportReseau.depuis(.dns(-65554), chemin: nil, hote: "x.local") == .reseauLocalRefuse)
        #expect(ErreurTransportReseau.depuis(.dns(-65554), chemin: nil, hote: "X.LOCAL.") == .reseauLocalRefuse)
        #expect(ErreurTransportReseau.depuis(.dns(-65554), chemin: nil, hote: "pont.example.org") == .nomIntrouvable("pont.example.org"))
        #expect(ErreurTransportReseau.depuis(.dns(-65537), chemin: nil, hote: "x.local") == .nomIntrouvable("x.local"))
        #expect(ErreurTransportReseau.depuis(.dns(-65570), chemin: nil, hote: "x.local") == .reseauLocalRefuse)
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `TEST FAILED` : `cannot find type 'TransportUDP' in scope`…

- [ ] **Step 3 : le code.**

`apps/macos/AmaranProtocole/Transport/Transport.swift`, bloc 1 sur 2. Remplacer :

````swift
// Repris de Halo Compagnon (commit e114cd5) : sans le transport UDP (plan 3b-2).
import Foundation

````

par :

````swift
// Repris de Halo Compagnon (commit e114cd5) : le transport UDP est dans Transport/TransportUDP.swift.
import Foundation

````

`apps/macos/AmaranProtocole/Transport/Transport.swift`, bloc 2 sur 2. Remplacer :

````swift
}

/// Transport d'octets : port serie USB, rejeu de demonstration (Thread viendra
/// au plan 3b-2). La couche protocole (tramage, session, correlation) ne connait
/// que ce protocole.
public protocol Transport: AnyObject, Sendable {
    var genre: GenreTransport { get }
````

par :

````swift
}

/// Transport d'octets : port serie USB, rejeu de demonstration, UDP sur Thread
/// (`TransportUDP`). La couche protocole (tramage, session, correlation) ne connait
/// que ce protocole.
///
/// Pour UDP, un datagramme = un message sans RS ni LF : `TransportUDP` ajoute RS et LF
/// a chaque datagramme recu et scelle chaque ligne envoyee dans son propre datagramme
/// (enveloppe H1), pour que `RecepteurLignes` serve tel quel.
public protocol Transport: AnyObject, Sendable {
    var genre: GenreTransport { get }
````

`apps/macos/AmaranProtocole/Reseau/ErreurReseau.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : erreurs du transport reseau, textes en francais seulement. Renomme ErreurTransportReseau : ErreurReseau est deja la faute des pre-controles du mesh.
import Foundation
import Network
import dnssd

/// Echec du transport reseau (spec 3b, section 7), avec son texte et sa reprise.
public enum ErreurTransportReseau: Error, Sendable, Equatable, CustomStringConvertible {
    /// Autorisation "reseau local" refusee (Reglages Systeme) : macOS refuse
    /// la resolution du nom `.local` du pont.
    case reseauLocalRefuse
    /// Pas de route IPv6 vers le reseau Thread (bug du noyau de macOS).
    case pasDeRoute
    /// `<nom>.local` introuvable, ou le noeud ne repond pas (`EHOSTDOWN`).
    case nomIntrouvable(String)
    /// ICMPv6 "port injoignable" : le pont n'a plus de cle (port 5480 ferme).
    case portInjoignable
    /// Aucun DEFI juste apres les essais du SALUT (autre cle, pont muet).
    case aucunDefi
    /// Connexion perdue apres son ouverture (`.waiting`, `.failed`, erreur de
    /// reception) : son texte est la raison de fermeture du flux, la cause
    /// ensuite (`TransportUDP.raisonPerte`).
    case cheminPerdu(String)
    case autre(String)

    /// Vrai : la reconnexion reessaie seule ; faux : il faut l'utilisateur
    /// (ou un changement du reseau). "Reseau local refuse" reessaie : le
    /// refus se leve dans Reglages Systeme sans rien signaler a l'app, et un
    /// essai refuse ne sort pas du Mac (banc R7).
    public var repriseAutomatique: Bool {
        if case .portInjoignable = self { return false }
        return true
    }

    /// Vrai : l'utilisateur doit agir (Reglages Systeme, USB) ; montre en
    /// bandeau, essais en cours ou non.
    public var bandeau: Bool {
        switch self {
        case .reseauLocalRefuse, .portInjoignable: true
        default: false
        }
    }

    public var description: String {
        switch self {
        case .reseauLocalRefuse:
            "Accès au réseau local refusé : Réglages Système › Confidentialité et sécurité › Réseau local › Amaran Compagnon."
        case .pasDeRoute:
            "Pas de route IPv6 vers le réseau Thread (bug du noyau de macOS)."
        case .nomIntrouvable(let hote):
            "Pont introuvable (\(hote)) : éteint, hors du réseau Thread, ou routeurs de bordure injoignables."
        case .portInjoignable:
            "Le pont n'a plus de clé : le brancher en USB, puis « Activer l'accès réseau… »."
        case .aucunDefi:
            "Aucune réponse du pont : clé différente de la sienne, ou pont sans clé ? (vérifier par l'USB, carte Thread et Matter)"
        case .cheminPerdu(let raison):
            "Connexion réseau perdue : \(raison)"
        case .autre(let raison):
            "Erreur réseau : \(raison)"
        }
    }

    /// Erreur de Network.framework ; `chemin` : dernier chemin connu de la connexion.
    public static func depuis(_ e: NWError, chemin: NWPath?, hote: String) -> ErreurTransportReseau {
        if chemin?.unsatisfiedReason == .localNetworkDenied { return .reseauLocalRefuse }
        switch e {
        case .posix(let code):
            switch code {
            case .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN: return .pasDeRoute
            // ICMPv6 "adresse injoignable" : la route existe, c'est le noeud
            // qui ne repond pas (eteint, hors du reseau Thread).
            case .EHOSTDOWN: return .nomIntrouvable(hote)
            case .ECONNREFUSED: return .portInjoignable
            default: return .autre(String(describing: code))
            }
        case .dns(let code):
            // Reseau local refuse : `PolicyDenied` selon la documentation ;
            // macOS repond en fait `NoSuchRecord`, aussitot, a la resolution
            // d'un nom `.local` (banc R7). Un nom `.local` absent, lui, reste
            // sans reponse (aucune erreur) : l'attente de `attentePret` le
            // classe introuvable.
            switch Int(code) {
            case kDNSServiceErr_PolicyDenied: return .reseauLocalRefuse
            case kDNSServiceErr_NoSuchRecord where estLocal(hote): return .reseauLocalRefuse
            default: return .nomIntrouvable(hote)
            }
        default:
            return .autre(String(describing: e))
        }
    }

    /// Nom mDNS (`.local`, avec ou sans point final).
    static func estLocal(_ hote: String) -> Bool {
        let h = hote.lowercased()
        return h.hasSuffix(".local") || h.hasSuffix(".local.")
    }
}
````

`apps/macos/AmaranProtocole/Transport/TransportUDP.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : transport UDP sur Thread (port 5480, enveloppe H1), meme octets que Halo.
import Foundation
import Network
import Synchronization

/// Transport reseau (spec 3b, section 7) : UDP sur Thread vers `<nom>.local:5480`,
/// enveloppe H1. Pour le reste de l'app, un port de plus : chaque datagramme
/// valide recu devient une ligne RS + JSON + LF ; chaque ligne envoyee, un
/// datagramme scelle (les lignes vides ou de controle seul sont ecartees).
public final class TransportUDP: Transport {
    public struct Reglages: Sendable {
        public var port: UInt16 = 5480
        /// Connexion prete (resolution du nom, route) : au plus.
        public var attentePret: Duration = .seconds(5)
        /// DEFI juste apres chaque SALUT : au plus.
        public var attenteDefi: Duration = .seconds(2)
        public var essais = 3
        public init() {}
    }

    public let genre: GenreTransport = .udp
    public let hote: String
    public var nom: String { hote }
    private let cle: Data
    private let reglages: Reglages
    private let file = DispatchQueue(label: "fr.djoko.amaran.udp", qos: .userInitiated)

    private struct Etat {
        var connexion: NWConnection?
        var pret = false
        var echoue = false
        var erreur: ErreurTransportReseau?
        /// Datagrammes arrives pendant la poignee de main (16 au plus).
        var recus: [Data] = []
        var session: SessionH1?
        var suite: AsyncStream<EvenementTransport>.Continuation?
        var envoisEnCours = 0
        var fini = false
    }
    private let etat = Mutex(Etat())

    public init(hote: String, cle: Data, reglages: Reglages = Reglages()) {
        self.hote = hote
        self.cle = cle
        self.reglages = reglages
    }

    /// Datagrammes ecartes (forme, sid, MAC, rejeu) depuis l'ouverture.
    public var ecartes: Int { etat.withLock { $0.session?.ecartes ?? 0 } }

    public func ouvrir() async throws -> AsyncStream<EvenementTransport> {
        let parametres = NWParameters.udp
        if let ip = parametres.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v6 }
        guard let port = NWEndpoint.Port(rawValue: reglages.port) else { throw ErreurTransportReseau.autre("port") }
        let c = NWConnection(host: NWEndpoint.Host(hote), port: port, using: parametres)
        etat.withLock { $0.connexion = c }
        c.stateUpdateHandler = { [weak self] s in self?.changement(s, c) }
        if Self.traces {
            c.pathUpdateHandler = { [weak self] p in self?.tracer("chemin \(Self.decrire(p))") }
        }
        c.start(queue: file)
        do {
            try await attendrePret()
            recevoir(c)
            let session = try await poigneeDeMain(c)
            let (flux, suite) = AsyncStream.makeStream(of: EvenementTransport.self, bufferingPolicy: .unbounded)
            try adopter(session, suite)
            suite.onTermination = { [weak self] _ in self?.fermer() }
            return flux
        } catch {
            etat.withLock { e in
                e.fini = true
                e.connexion = nil
            }
            c.cancel()
            throw error
        }
    }

    /// Pose la session et le flux, sauf si un echec (`.failed`, erreur de
    /// reception) ou une fermeture est arrive entre le dernier coup d'oeil de
    /// la poignee de main et ce verrou : `echec` et `terminer` n'avaient alors
    /// aucun flux a fermer, et celui-ci ne recevrait jamais `.ferme`. L'erreur
    /// gardee est levee (ou, pour une fermeture, une erreur de transport) ;
    /// `ouvrir` annule alors la connexion.
    func adopter(_ session: SessionH1, _ suite: AsyncStream<EvenementTransport>.Continuation) throws {
        let refus: (any Error)? = etat.withLock { e in
            guard !e.fini, !e.echoue else {
                if let erreur = e.erreur { return erreur }
                return ErreurTransport("session réseau fermée par l'app")
            }
            e.session = session
            e.suite = suite
            e.recus.removeAll()
            return nil
        }
        if let refus { throw refus }
    }

    /// Raison de fermeture d'une session perdue apres son ouverture  :
    /// "Connexion réseau perdue : <cause>".
    static func raisonPerte(_ cause: ErreurTransportReseau) -> String {
        ErreurTransportReseau.cheminPerdu(cause.description).description
    }

    // MARK: - Connexion (file du transport)

    /// `.waiting` avant l'ouverture : sans route (ENETDOWN, EHOSTUNREACH...),
    /// la connexion en attente ne repart pas quand la route revient (aucun
    /// evenement de chemin, banc du 25/09 : reprise 8 s apres son retour) ;
    /// on abandonne tout de suite, la reconnexion reessaie a son rythme. Les
    /// autres attentes vont jusqu'a `attentePret` : une reautorisation du
    /// reseau local, elle, relance la connexion en attente.
    static func abandonAvantOuverture(_ e: ErreurTransportReseau) -> Bool { e == .pasDeRoute }

    /// Journal de mise au point (variable d'environnement AMARAN_DEBUG_RESEAU=1) :
    /// etats de la connexion et chemins, sur la sortie d'erreur.
    static let traces = ProcessInfo.processInfo.environment["AMARAN_DEBUG_RESEAU"] == "1"

    func tracer(_ texte: @autoclosure () -> String) {
        guard Self.traces else { return }
        let date = Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        FileHandle.standardError.write(Data("[udp \(hote)] \(date) \(texte())\n".utf8))
    }

    static func decrire(_ p: NWPath?) -> String {
        guard let p else { return "aucun" }
        return "\(p.status) raison=\(p.unsatisfiedReason) interfaces=\(p.availableInterfaces.map(\.name))"
    }

    private func changement(_ s: NWConnection.State, _ c: NWConnection) {
        tracer("etat \(s) chemin \(Self.decrire(c.currentPath))")
        switch s {
        case .ready:
            etat.withLock { $0.pret = true }
        case .waiting(let e):
            // Avant .ready : cause candidate, la connexion peut encore aboutir
            // (sauf sans route : abandonAvantOuverture).
            let err = ErreurTransportReseau.depuis(e, chemin: c.currentPath, hote: hote)
            let ouverte = etat.withLock { et -> Bool in
                et.erreur = err
                return et.suite != nil
            }
            if ouverte {
                terminer(Self.raisonPerte(err))
            } else if Self.abandonAvantOuverture(err) {
                echec(err)
            }
        case .failed(let e):
            echec(ErreurTransportReseau.depuis(e, chemin: c.currentPath, hote: hote))
        default:
            break
        }
    }

    private func attendrePret() async throws {
        let limite = ContinuousClock.now + reglages.attentePret
        while ContinuousClock.now < limite {
            let (pret, echoue, erreur) = etat.withLock { ($0.pret, $0.echoue, $0.erreur) }
            if pret { return }
            if echoue, let erreur { throw erreur }
            try await Task.sleep(for: .milliseconds(10))
        }
        let gardee = etat.withLock { $0.erreur }
        tracer("pas pret en \(reglages.attentePret), erreur gardee : \(String(describing: gardee))")
        throw gardee ?? ErreurTransportReseau.nomIntrouvable(hote)
    }

    private func recevoir(_ c: NWConnection) {
        c.receiveMessage { [weak self] donnees, _, _, erreur in
            guard let self else { return }
            if let erreur {
                self.tracer("reception : \(erreur) chemin \(Self.decrire(c.currentPath))")
                self.echec(ErreurTransportReseau.depuis(erreur, chemin: c.currentPath, hote: self.hote))
                return
            }
            if let donnees, !donnees.isEmpty { self.arrivee(donnees) }
            if !self.etat.withLock({ $0.fini }) { self.recevoir(c) }
        }
    }

    private func arrivee(_ d: Data) {
        let charge: Data? = etat.withLock { e in
            guard var s = e.session else {
                if e.recus.count < 16 { e.recus.append(d) }
                return nil
            }
            let c = s.ouvrir(d)
            e.session = s
            return c
        }
        guard let charge else { return }
        var ligne = Data([Octets.rs])
        ligne.append(charge)
        ligne.append(Octets.lf)
        _ = etat.withLock { $0.suite?.yield(.donnees(ligne)) }
    }

    /// Interne (et non privee) : les tests y simulent un `.failed` ou une
    /// erreur de reception, sans reseau.
    func echec(_ err: ErreurTransportReseau) {
        let ouverte = etat.withLock { e -> Bool in
            e.erreur = err
            e.echoue = true
            return e.suite != nil
        }
        if ouverte { terminer(Self.raisonPerte(err)) }
    }

    // MARK: - Poignee de main

    private func poigneeDeMain(_ c: NWConnection) async throws -> SessionH1 {
        for _ in 0..<reglages.essais {
            let na = H1.aleatoire(16)
            c.send(content: H1.salut(cle: cle, na: na), completion: .contentProcessed { _ in })
            let limite = ContinuousClock.now + reglages.attenteDefi
            while ContinuousClock.now < limite {
                let (recu, echoue, erreur) = etat.withLock { e -> (Data?, Bool, ErreurTransportReseau?) in
                    (e.recus.isEmpty ? nil : e.recus.removeFirst(), e.echoue, e.erreur)
                }
                if echoue, let erreur { throw erreur }
                if let recu {
                    if let d = H1.verifierDefi(recu, cle: cle, na: na) {
                        return SessionH1(sid: d.sid, ks: H1.cleSession(cle: cle, na: na, nc: d.nc, sid: d.sid))
                    }
                    continue  // DEFI d'un essai precedent, ou autre datagramme
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        throw try await echecPoignee(c)
    }

    /// Aucun DEFI apres tous les essais : cle differente, ou pont sans cle
    /// (spec 3b, section 7). Sur ce SDK, `::1` ne remonte pas toujours tout de suite
    /// l'ICMPv6 "port injoignable" d'un port ferme (lwIP) : annuler la
    /// connexion la fait parfois apparaitre, portee par le `receiveMessage`
    /// deja en attente, quelques ms plus tard. On annule donc ici et on
    /// attend une derniere fois, brievement, avant de conclure `aucunDefi`.
    private func echecPoignee(_ c: NWConnection) async throws -> ErreurTransportReseau {
        c.cancel()
        etat.withLock { $0.fini = true }
        let limite = ContinuousClock.now + .milliseconds(150)
        while ContinuousClock.now < limite {
            let (echoue, erreur) = etat.withLock { ($0.echoue, $0.erreur) }
            if echoue { return erreur == .portInjoignable ? .portInjoignable : .aucunDefi }
            try await Task.sleep(for: .milliseconds(10))
        }
        return .aucunDefi
    }

    // MARK: - Transport

    public func envoyer(_ donnees: Data) throws {
        let (c, datagrammes): (NWConnection?, [Data]) = etat.withLock { e in
            guard !e.fini, let c = e.connexion, var s = e.session else { return (nil, []) }
            var sortie: [Data] = []
            for ligne in donnees.split(separator: Octets.lf) where ligne.contains(where: { $0 >= 0x20 }) {
                sortie.append(s.sceller(Data(ligne)))
            }
            e.session = s
            e.envoisEnCours += sortie.count
            return (c, sortie)
        }
        guard let c else { throw ErreurTransport("session réseau fermée") }
        for d in datagrammes {
            c.send(content: d, completion: .contentProcessed { [weak self] _ in
                self?.etat.withLock { $0.envoisEnCours -= 1 }
            })
        }
    }

    public func fermer() {
        file.async { [weak self] in self?.terminer("session réseau fermée par l'app") }
    }

    /// Laisse partir ce qui est confie (`json 0`), 300 ms au plus, puis ferme.
    /// Hors de la file du transport : les confirmations d'envoi y arrivent.
    public func fermerApresVidage(synchrone: Bool) {
        let travail: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            let limite = ContinuousClock.now + .milliseconds(300)
            while ContinuousClock.now < limite, self.etat.withLock({ $0.envoisEnCours }) > 0 { usleep(5_000) }
            self.terminer("session réseau fermée par l'app")
        }
        if synchrone { travail() } else { DispatchQueue.global(qos: .userInitiated).async(execute: travail) }
    }

    private func terminer(_ raison: String) {
        let (c, suite) = etat.withLock { e -> (NWConnection?, AsyncStream<EvenementTransport>.Continuation?) in
            guard !e.fini else { return (nil, nil) }
            e.fini = true
            let r = (e.connexion, e.suite)
            e.connexion = nil
            e.suite = nil
            return r
        }
        c?.cancel()
        suite?.yield(.ferme(raison: raison))
        suite?.finish()
    }
}
````

- [ ] **Step 4 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `Test run with 176 tests in 21 suites passed` (`AmaranProtocoleTests`) et `Test run with 12 tests in 4 suites passed` (`AmaranCompagnonTests`) ; aucune ligne `error:` ni `warning:`.

- [ ] **Step 5 : commit.**

```bash
git add apps/macos/AmaranProtocole apps/macos/AmaranProtocoleTests
git commit -m "$(printf "App compagnon : transport UDP sur Thread (Network.framework), repris de Halo\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 7: Les courbes, le répertoire des ponts, l'état de l'accès réseau (Swift, testé sur le Mac)

**Files:**
- Create: `apps/macos/AmaranProtocole/Courbes/Courbes.swift`, `apps/macos/AmaranProtocole/Reseau/RepertoirePonts.swift`
- Modify: `apps/macos/AmaranProtocole/Reseau/CleReseau.swift`
- Create: `apps/macos/AmaranProtocoleTests/CourbesTests.swift`, `apps/macos/AmaranProtocoleTests/RepertoirePontsTests.swift`
- Modify: `apps/macos/AmaranProtocoleTests/CleReseauTests.swift`

**Interfaces:**
- Consumes : la Task 5 (`MessageCarte`, `EtatPont`, `ReseauIp`, `H1`, `CleReseau`).
- Produces :
  - `Courbes/Courbes.swift` : `Grandeur`, `Echantillon`, `Difference`, `PointMesure`, `PointOrdre`, `enum Courbes` (segments, ruptures, différences par fenêtre, parts du Mesh), `struct SeriesCourbes` (`ajouter(_:date:)`, `vider()`, séries par lampe, Mesh, tas) ;
  - `struct RepertoirePonts` (Codable ; clé de réglages `repertoirePonts` ; `noter(mac:serie:srp:)`, `noter(_:)`, `oublier(mac:)`, `mac(pourSrp:)`, `pontsReseau`, `titre(mac:)`) ;
  - `enum EtatAccesReseau` (`inconnu`, `sansCle(nom:)`, `cleConnue(nom:empreinte:)`, `cleInconnue(nom:empreinte:)` ; `depuis(ip:empreinteDuMac:)`, `nom`).

Pourquoi : la spec 3b, section 8. Les graphiques se tirent des différences de compteurs successifs, par fenêtre : un redémarrage du pont (`boot`) ouvre un nouveau segment, un retour à zéro ou un trou trop long coupe la courbe. La part des NetMIC faux se rapporte aux annonces de notre réseau (`nid_reconnu`) : un IV Index faux la fait monter vers 100 %, des clés périmées font tomber à zéro les annonces de notre réseau. Le répertoire retient, pour chaque pont vu par l'USB, son modèle et son nom SRP (jamais une clé) ; l'état de l'accès réseau compare l'empreinte de la clé du pont (bloc `ip`) à celle que ce Mac garde.

Repris de Halo Compagnon (commit `e114cd5`) : `HaloProtocole/Courbes/Courbes.swift`, `HaloProtocole/Reseau/RepertoirePonts.swift` et leurs tests, adaptés aux compteurs du pont amaran.

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranProtocoleTests/CleReseauTests.swift`, bloc 1 sur 1. Remplacer :

````swift
}

extension Reponse {
    func avecId(_ n: Int) -> Reponse {
````

par :

````swift
}

@Suite("Etat de l'acces reseau")
struct EtatAccesReseauTests {
    static let nom = "1A2B3C4D5E6F7081"

    static func ip(srp: String? = nom, cle: Bool? = true, empreinte: String? = "CA2A4FE7", ouvert: Bool? = true,
                  sansUdp: Bool = false) -> ReseauIp {
        var u = ReseauIp.Udp()
        u.port = 5480
        u.cle = cle
        u.empreinte = empreinte
        u.ouvert = ouvert
        var r = ReseauIp()
        r.srp = srp
        r.udp = sansUdp ? nil : u
        return r
    }

    @Test func etats() {
        let connue: (String) -> String? = { $0 == Self.nom ? "CA2A4FE7" : nil }
        let autre: (String) -> String? = { _ in "11111111" }
        let aucune: (String) -> String? = { _ in nil }
        #expect(EtatAccesReseau.depuis(ip: nil, empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(srp: nil), empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(srp: ""), empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(sansUdp: true), empreinteDuMac: connue) == .inconnu)
        #expect(EtatAccesReseau.depuis(ip: Self.ip(cle: false, empreinte: nil, ouvert: false), empreinteDuMac: connue)
                == .sansCle(nom: Self.nom))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(), empreinteDuMac: connue) == .cleConnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(), empreinteDuMac: autre) == .cleInconnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(), empreinteDuMac: aucune) == .cleInconnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        // Sans le champ `cle` (firmware plus ancien) : le port ouvert dit la cle.
        #expect(EtatAccesReseau.depuis(ip: Self.ip(cle: nil), empreinteDuMac: connue) == .cleConnue(nom: Self.nom, empreinte: "CA2A4FE7"))
        #expect(EtatAccesReseau.depuis(ip: Self.ip(cle: nil, ouvert: false), empreinteDuMac: connue) == .sansCle(nom: Self.nom))
        #expect(EtatAccesReseau.cleConnue(nom: Self.nom, empreinte: "CA2A4FE7").nom == Self.nom)
        #expect(EtatAccesReseau.inconnu.nom == nil)
    }
}

extension Reponse {
    func avecId(_ n: Int) -> Reponse {
````

`apps/macos/AmaranProtocoleTests/CourbesTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (HaloProtocoleTests/CourbesTests.swift) : differences par
// fenetre et segments ; series du pont amaran (Mesh, relectures, ordres, tas).
import Foundation
import Testing
@testable import AmaranProtocole

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)  // multiple de 10

private func ech(_ s: Double, boot: String = "A", _ v: [Grandeur: Int]) -> Echantillon {
    Echantillon(date: t0.addingTimeInterval(s), boot: boot, valeurs: v)
}

private func message(_ json: String) -> MessageCarte {
    var r = RecepteurLignes()
    guard case .machine(let l) = r.alimenter(ligneMachine(json)).first else { return .inconnu }
    return l.message
}

@Suite("Courbes")
struct CourbesTests {
    @Test func segmentsSurDifferenceNegativeEtBoot() {
        let e = [
            ech(0, [.annonces: 10]),
            ech(1, [.annonces: 12]),
            ech(2, [.annonces: 3]),               // difference negative
            ech(3, [.annonces: 5]),
            ech(4, boot: "B", [.annonces: 6]),    // redemarrage
        ]
        #expect(Courbes.segmenter(e).map(\.count) == [2, 2, 1])
    }

    @Test func differencesParFenetre() {
        // Un echantillon par seconde pendant 30 s, 3 annonces par seconde.
        let e = (0...30).map { ech(Double($0), [.annonces: 3 * $0, .netmicFaux: $0 / 5]) }
        let d = Courbes.differences(e, fenetre: 10)
        #expect(d.count == 4)
        #expect(d[0].debut == t0 && d[0].fin == t0.addingTimeInterval(9))
        #expect(d[0][.annonces] == 27)
        #expect(d[1][.annonces] == 30)
        #expect(d[3][.annonces] == 3)
        #expect(d.allSatisfy { $0.segment == 0 })
        #expect(d.compactMap { $0[.annonces] }.reduce(0, +) == 90, "sans trou ni double compte")
    }

    @Test func pasDeValeurAberranteAuRedemarrage() {
        let e = [ech(0, [.netmicFaux: 100]), ech(5, [.netmicFaux: 110]), ech(12, boot: "B", [.netmicFaux: 2]),
                 ech(15, boot: "B", [.netmicFaux: 4])]
        let d = Courbes.differences(e, fenetre: 10)
        #expect(d.map { $0[.netmicFaux] } == [10, 2])
        #expect(d.map(\.segment) == [0, 1])
    }

    @Test func unTrouDEchantillonsOuvreUnSegment() {
        let e = [ech(0, [.annonces: 0]), ech(1, [.annonces: 10]), ech(591, [.annonces: 5910]), ech(592, [.annonces: 5920])]
        #expect(Courbes.segmenter(e).map(\.count) == [2, 2])
        #expect(Courbes.ecartMax(periodeMs: 1000) == 30)
        #expect(Courbes.ecartMax(periodeMs: 60000) == 180)
        #expect(Courbes.ecartMax(periodeMs: 0) == 30)
        let lent = [ech(0, [.annonces: 0]), ech(60, [.annonces: 6]), ech(120, [.annonces: 12])]
        #expect(Courbes.segmenter(lent, ecartMax: Courbes.ecartMax(periodeMs: 60000)).count == 1)
    }

    @Test func partsDuMesh() {
        let d = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                           deltas: [.annonces: 200, .nidReconnu: 100, .netmicFaux: 25, .emis: 18, .echecsEmission: 2,
                                    .confirmes: 9, .abandons: 1])
        #expect(Courbes.partNetmicFaux(d) == 0.25, "rapportee aux annonces de notre reseau, pas a toutes")
        #expect(Courbes.partRefusEmission(d) == 0.1)
        #expect(Courbes.partAbandons(d) == 0.1)
        #expect(Courbes.parMinute(d, .annonces) == 200)
        let vide = Difference(debut: t0, fin: t0.addingTimeInterval(10), segment: 0,
                              deltas: [.annonces: 0, .nidReconnu: 0, .emis: 0, .echecsEmission: 0])
        #expect(Courbes.partNetmicFaux(vide) == nil, "pas de division par zero")
        #expect(Courbes.partRefusEmission(vide) == nil)
    }

    /// Les deux pannes que le graphique « NetMIC faux » doit montrer, aux proportions de
    /// l'exemple 9.1 (5 120 annonces, dont 1 630 de notre reseau et 3 402 d'un autre). Le
    /// pont ne verifie le NetMIC que d'un message qui porte notre NID (crochet.c).
    @Test func netmicFauxDistingueIVFauxEtClesPerimees() {
        // IV Index faux : chaque message de notre reseau a un NetMIC faux.
        let ivFaux = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                                deltas: [.annonces: 5120, .nidReconnu: 1630, .nidInconnu: 3402, .netmicFaux: 1630])
        #expect(Courbes.partNetmicFaux(ivFaux) == 1, "IV Index faux : 100 %")
        // Cles perimees (reseau recree dans amaran Desktop) : plus aucun message ne porte
        // notre NID. Les annonces de notre reseau tombent a zero, sans NetMIC faux.
        let perimees = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                                  deltas: [.annonces: 5120, .nidReconnu: 0, .nidInconnu: 5120, .netmicFaux: 0])
        #expect(perimees[.nidReconnu] == 0, "graphique des annonces : « de notre réseau » a zero")
        #expect(Courbes.partNetmicFaux(perimees) == nil, "pas de part sans annonce de notre reseau")
        // Sain : quelques NetMIC faux seulement.
        let sain = Difference(debut: t0, fin: t0.addingTimeInterval(60), segment: 0,
                              deltas: [.annonces: 5120, .nidReconnu: 1630, .nidInconnu: 3402, .netmicFaux: 0])
        #expect(Courbes.partNetmicFaux(sain) == 0)
        // Pendant un renouvellement des cles, un message peut compter deux NetMIC faux :
        // la part reste bornee a 100 %.
        let renouvellement = Difference(debut: t0, fin: t0.addingTimeInterval(10), segment: 0,
                                        deltas: [.nidReconnu: 10, .netmicFaux: 12])
        #expect(Courbes.partNetmicFaux(renouvellement) == 1)
    }

    @Test func cumul() {
        let e = [ech(0, [.emis: 1]), ech(1, [.emis: 3]), ech(2, boot: "B", [.emis: 0])]
        #expect(Courbes.cumul(e, .emis).map(\.valeur) == [1, 3, 0])
        #expect(Courbes.cumul(e, .emis).map(\.segment) == [0, 0, 1])
    }
}

@Suite("Series des graphiques")
struct SeriesCourbesTests {
    /// Les lignes des exemples de la specification nourrissent toutes les series.
    @Test func seriesDesExemples() throws {
        var s = SeriesCourbes()
        for (i, l) in try ExemplesSpec.decoder().enumerated() {
            s.ajouter(l.message, date: t0.addingTimeInterval(Double(i)))
        }
        #expect(s.mesh.count == 1)
        #expect(s.mesh.first?.valeurs[.annonces] == 5120)
        #expect(s.mesh.first?.valeurs[.echecsEmission] == 0)
        #expect(s.pont.first?.valeurs[.releves] == 41)
        #expect(s.pont.first?.valeurs[.confirmes] == 5)
        #expect(s.parts[1]?.map(\.valeur) == [97, 97, 97])
        #expect(s.parts[2]?.first?.valeur == 100)
        #expect(s.tas.map(\.valeur) == [112640, 112640])
        #expect(s.tasMin.first?.valeur == 103424)
        #expect(s.ordres[1]?.map(\.issue) == [.confirme])
        #expect(s.ordres[2]?.map(\.issue) == [.tenu, .abandon])
        #expect(s.delaisConfirmes(lampe: 1).map(\.valeur) == [410])
        #expect(s.delaisConfirmes(lampe: 2).isEmpty, "tenu et abandon n'ont pas de delai de confirmation")
        #expect(s.lampes == [1, 2])
        #expect(s.segment == 0, "un seul boot dans les exemples")
    }

    @Test func nouveauBootNouveauSegment() {
        var s = SeriesCourbes()
        s.ajouter(message(#"{"v":1,"t":"etat","n":1,"ms":1,"bloc":"sante","boot":"3FA2C901","up_s":1,"sys":{"heap":1000,"heap_min":900}}"#), date: t0)
        s.ajouter(message(#"{"v":1,"t":"etat","n":2,"ms":2,"bloc":"lampe","lampe":1,"part_10min":null}"#), date: t0.addingTimeInterval(1))
        s.ajouter(message(#"{"v":1,"t":"hello","n":0,"ms":5,"bloc":"base","boot":"0B0C0D0E","up_s":0}"#), date: t0.addingTimeInterval(2))
        s.ajouter(message(#"{"v":1,"t":"etat","n":3,"ms":6,"bloc":"sante","boot":"0B0C0D0E","up_s":1,"sys":{"heap":2000}}"#), date: t0.addingTimeInterval(3))
        s.ajouter(message(#"{"v":1,"t":"compteurs","n":4,"ms":7,"bloc":"mesh","annonces":3}"#), date: t0.addingTimeInterval(4))
        s.ajouter(message(#"{"v":1,"t":"ordre","n":5,"ms":8,"lampe":1,"issue":"confirme","delai_ms":350,"essai":1,"ids":[],"ids_perdus":0}"#), date: t0.addingTimeInterval(5))
        #expect(s.segment == 1)
        #expect(s.boot == "0B0C0D0E")
        #expect(s.tas.map(\.segment) == [0, 1])
        #expect(s.tas.map(\.valeur) == [1000, 2000])
        #expect(s.parts[1]?.first?.valeur == nil, "part inconnue : un point sans valeur")
        #expect(s.mesh.first?.boot == "0B0C0D0E")
        #expect(s.ordres[1]?.first?.segment == 1)
        s.vider()
        #expect(s == SeriesCourbes())
    }

    @Test func seriesBornees() {
        var s = SeriesCourbes(capacite: 3)
        for i in 0..<5 {
            s.ajouter(.etatSante(BlocSante(boot: "A", sys: BlocSante.Systeme(heap: i))), date: t0.addingTimeInterval(Double(i)))
        }
        #expect(s.tas.map(\.valeur) == [2, 3, 4])
    }
}
````

`apps/macos/AmaranProtocoleTests/RepertoirePontsTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (HaloProtocoleTests/RepertoirePontsTests.swift) : numero de
// serie AMARAN-<MAC> ; MAC et noms SRP inventes.
import Foundation
import Testing
@testable import AmaranProtocole

@Suite("Repertoire des ponts (noms du menu Source)")
struct RepertoirePontsTests {
    static let mac = "F0F5BD0A0B0C"
    static let autre = "020000AABBCC"
    static let srp = "1A2B3C4D5E6F7081"

    @Test func mac() {
        #expect(RepertoirePonts.mac("F0:F5:BD:0A:0B:0C") == Self.mac, "numero de serie USB")
        #expect(RepertoirePonts.mac("f0f5bd0a0b0c") == Self.mac, "hello identite")
        #expect(RepertoirePonts.mac("F0-F5-BD-0A-0B-0C") == Self.mac)
        #expect(RepertoirePonts.mac("F0:F5:BD:0A:0B") == nil)
        #expect(RepertoirePonts.mac("ABCDEFGHIJKL") == nil, "pas de l'hexa")
        #expect(RepertoirePonts.mac(nil) == nil)
        #expect(RepertoirePonts.macLisible(Self.mac) == "F0:F5:BD:0A:0B:0C")
    }

    @Test func modele() {
        #expect(RepertoirePonts.modele(serie: "AMARAN-F0F5BD0A0B0C", mac: Self.mac) == "AMARAN")
        #expect(RepertoirePonts.modele(serie: "AMARAN-2-F0F5BD0A0B0C", mac: Self.mac) == "AMARAN-2")
        #expect(RepertoirePonts.modele(serie: "AMARAN-020000AABBCC", mac: Self.mac) == nil, "autre MAC")
        #expect(RepertoirePonts.modele(serie: "-F0F5BD0A0B0C", mac: Self.mac) == nil)
        #expect(RepertoirePonts.modele(serie: "AMARAN", mac: Self.mac) == nil)
        #expect(RepertoirePonts.modele(serie: nil, mac: Self.mac) == nil)
    }

    @Test func noterEtNommer() {
        var r = RepertoirePonts()
        #expect(r.titre(mac: Self.mac) == "ESP32 · F0:F5:BD:0A:0B:0C", "jamais connecte")
        let change1 = r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: nil)
        #expect(change1)
        #expect(r.titre(mac: Self.mac) == "AMARAN · F0:F5:BD:0A:0B:0C")
        let change2 = r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        #expect(change2)
        let change3 = r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        #expect(!change3, "rien de neuf")
        #expect(r.mac(pourSrp: Self.srp) == Self.mac)
        #expect(r.pontsReseau.map(\.srp) == [Self.srp])
        let change4 = r.noter(mac: nil, serie: "AMARAN-F0F5BD0A0B0C", srp: "X")
        #expect(!change4, "sans MAC : rien")
        let change5 = r.noter(mac: Self.mac, serie: nil, srp: nil)
        #expect(!change5, "le modele appris reste")
        #expect(r.titre(mac: Self.mac) == "AMARAN · F0:F5:BD:0A:0B:0C")
        r.oublier(mac: "F0:F5:BD:0A:0B:0C")
        #expect(r.parMac.isEmpty)
    }

    /// Un nom SRP n'appartient qu'a un pont : le pont qui le reprend l'emporte.
    @Test func nomSrpRepris() {
        var r = RepertoirePonts()
        r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        let change = r.noter(mac: Self.autre, serie: "AMARAN-020000AABBCC", srp: Self.srp)
        #expect(change)
        #expect(r.mac(pourSrp: Self.srp) == Self.autre)
        #expect(r.parMac[Self.mac]?.srp == nil && r.parMac[Self.mac]?.modele == "AMARAN")
    }

    /// Ce que dit l'etat du pont : `hello` `identite` et bloc `ip` des exemples.
    @Test func depuisLEtatDuPont() throws {
        var e = EtatPont()
        for l in try ExemplesSpec.decoder() { e.appliquer(l, recueA: Date()) }
        #expect(e.srp == Self.srp)
        #expect(e.ip?.valeur.udp?.cle == false, "le dernier bloc ip des exemples : sans cle")
        #expect(e.transport == .udp, "le dernier hello des exemples : session distante")
        var r = RepertoirePonts()
        let change = r.noter(e)
        #expect(change)
        #expect(r.parMac[Self.mac] == RepertoirePonts.Entree(modele: "AMARAN", srp: Self.srp))
    }

    @Test func codablePourLesReglages() throws {
        var r = RepertoirePonts()
        r.noter(mac: Self.mac, serie: "AMARAN-F0F5BD0A0B0C", srp: Self.srp)
        let relu = try JSONDecoder().decode(RepertoirePonts.self, from: try JSONEncoder().encode(r))
        #expect(relu == r)
        let d = try #require(r.donnees)
        #expect(RepertoirePonts(donnees: d) == r)
        #expect(RepertoirePonts(donnees: Data("pas du json".utf8)) == nil)
        #expect(RepertoirePonts.cleReglages == "repertoirePonts")
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `TEST FAILED` : `cannot find 'EtatAccesReseau' in scope`, `cannot find type 'Grandeur' in scope`, `cannot find 'RepertoirePonts' in scope`…

- [ ] **Step 3 : le code.**

`apps/macos/AmaranProtocole/Courbes/Courbes.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (Courbes/Courbes.swift) : differences de compteurs cumulatifs
// par fenetre, segments ; adapte au pont amaran : compteurs du Bluetooth Mesh (5.4) et
// du bloc `etat` `pont` (5.3), jauges par lampe (part des relectures repondues), delais
// des ordres (7.1), tas libre (bloc `sante`). Pas de `raz` : seul un redemarrage (un
// autre `boot`) remet les compteurs a zero.
import Foundation

/// Compteurs cumulatifs suivis pour les courbes.
public enum Grandeur: String, CaseIterable, Sendable, Hashable {
    // bloc compteurs.mesh (5.4)
    case annonces, nidReconnu, nidInconnu, netmicFaux, accesDechiffres, etatsLampes, doublons
    case emis, echecsEmission, filePleine
    // bloc etat.pont (5.3)
    case releves, trames, ordres, confirmes, abandons, tenus, lents
}

/// Un bloc de compteurs date : les valeurs cumulatives presentes.
public struct Echantillon: Sendable, Equatable {
    public var date: Date
    public var boot: String?
    public var valeurs: [Grandeur: Int]

    public init(date: Date, boot: String?, valeurs: [Grandeur: Int]) {
        self.date = date
        self.boot = boot
        self.valeurs = valeurs
    }

    /// `compteurs` `mesh` (5.4).
    public static func mesh(_ c: CompteursMesh, date: Date, boot: String?) -> Echantillon {
        var v: [Grandeur: Int] = [:]
        v[.annonces] = c.annonces
        v[.nidReconnu] = c.nidReconnu
        v[.nidInconnu] = c.nidInconnu
        v[.netmicFaux] = c.netmicFaux
        v[.accesDechiffres] = c.accesDechiffres
        v[.etatsLampes] = c.etatsLampes
        v[.doublons] = c.doublons
        v[.emis] = c.emis
        v[.echecsEmission] = c.echecsEmission
        v[.filePleine] = c.filePleine
        return Echantillon(date: date, boot: boot, valeurs: v)
    }

    /// `etat` `pont` (5.3) : relectures envoyees, trames recues, ordres.
    public static func pont(_ p: BlocPont, date: Date, boot: String?) -> Echantillon {
        var v: [Grandeur: Int] = [:]
        v[.releves] = p.releves
        v[.trames] = p.trames
        v[.ordres] = p.ordres?.total
        v[.confirmes] = p.ordres?.confirmes
        v[.abandons] = p.ordres?.abandons
        v[.tenus] = p.ordres?.tenus
        v[.lents] = p.ordres?.lents
        return Echantillon(date: date, boot: boot ?? p.boot, valeurs: v)
    }
}

/// Differences entre deux echantillons d'un meme segment.
public struct Difference: Sendable, Equatable {
    public var debut: Date
    public var fin: Date
    public var segment: Int
    public var deltas: [Grandeur: Int]

    public init(debut: Date, fin: Date, segment: Int, deltas: [Grandeur: Int]) {
        self.debut = debut
        self.fin = fin
        self.segment = segment
        self.deltas = deltas
    }

    public var duree: TimeInterval { fin.timeIntervalSince(debut) }

    public subscript(_ g: Grandeur) -> Int? { deltas[g] }
}

/// Point d'une courbe cumulative (escalier).
public struct PointCumul: Sendable, Equatable {
    public var date: Date
    public var segment: Int
    public var valeur: Int
}

/// Point d'une jauge (valeur instantanee) ; `valeur` nil : inconnue (`part_10min` nul).
public struct PointMesure: Sendable, Equatable {
    public var date: Date
    /// Change a chaque redemarrage du pont : la courbe ne relie pas deux segments.
    public var segment: Int
    public var valeur: Double?

    public init(date: Date, segment: Int, valeur: Double?) {
        self.date = date
        self.segment = segment
        self.valeur = valeur
    }
}

/// Fin d'un ordre de lampe (evenement `ordre`, 7.1), pour la courbe des delais.
public struct PointOrdre: Sendable, Equatable {
    public var date: Date
    public var segment: Int
    public var lampe: Int
    public var issue: IssueOrdre?
    public var delaiMs: Int?
    public var essai: Int?

    public init(date: Date, segment: Int, lampe: Int, issue: IssueOrdre?, delaiMs: Int?, essai: Int?) {
        self.date = date
        self.segment = segment
        self.lampe = lampe
        self.issue = issue
        self.delaiMs = delaiMs
        self.essai = essai
    }
}

/// Differences par fenetre de 10 s ou 1 min ; une difference negative, un `boot`
/// qui change ou un trou dans les echantillons (app suspendue, veille du Mac, lien
/// perdu) ouvre un nouveau segment (pas de valeur aberrante).
public enum Courbes {
    /// Plus grand ecart tolere entre deux echantillons d'un meme segment.
    public static let ecartMaxDefaut: TimeInterval = 30

    /// Ecart maximal pour une periode d'emission (`compteurs_ms`, `periode_ms`) :
    /// 3 periodes, 30 s au moins.
    public static func ecartMax(periodeMs: Int?) -> TimeInterval {
        guard let p = periodeMs, p > 0 else { return ecartMaxDefaut }
        return max(ecartMaxDefaut, 3 * Double(p) / 1000)
    }

    /// Decoupe en segments continus.
    public static func segmenter(_ echantillons: [Echantillon],
                                 ecartMax: TimeInterval = ecartMaxDefaut) -> [[Echantillon]] {
        var segments: [[Echantillon]] = []
        var courant: [Echantillon] = []
        for e in echantillons {
            if let p = courant.last, rupture(p, e, ecartMax: ecartMax) {
                segments.append(courant)
                courant = []
            }
            courant.append(e)
        }
        if !courant.isEmpty { segments.append(courant) }
        return segments
    }

    /// Vrai si `b` ne peut pas suivre `a` dans un meme segment. Un trou de plus de
    /// `ecartMax` en ferait une seule difference geante, tracee comme une valeur
    /// "par fenetre".
    public static func rupture(_ a: Echantillon, _ b: Echantillon, ecartMax: TimeInterval = ecartMaxDefaut) -> Bool {
        if a.boot != nil, b.boot != nil, a.boot != b.boot { return true }
        if b.date < a.date { return true }
        if b.date.timeIntervalSince(a.date) > ecartMax { return true }
        for (g, v) in b.valeurs {
            if let w = a.valeurs[g], v < w { return true }
        }
        return false
    }

    /// Differences par fenetre alignee sur l'horloge (`fenetre` secondes) : pour
    /// chaque fenetre, dernier echantillon de la fenetre moins dernier echantillon
    /// de la fenetre precedente du meme segment (ou le premier echantillon du segment).
    public static func differences(_ echantillons: [Echantillon], fenetre: TimeInterval,
                                   ecartMax: TimeInterval = ecartMaxDefaut) -> [Difference] {
        precondition(fenetre > 0)
        var sortie: [Difference] = []
        for (numero, segment) in segmenter(echantillons, ecartMax: ecartMax).enumerated() {
            guard var reference = segment.first else { continue }
            var i = 0
            while i < segment.count {
                let seau = floor(segment[i].date.timeIntervalSinceReferenceDate / fenetre)
                var dernier = segment[i]
                var j = i + 1
                while j < segment.count, floor(segment[j].date.timeIntervalSinceReferenceDate / fenetre) == seau {
                    dernier = segment[j]
                    j += 1
                }
                if dernier.date > reference.date {
                    sortie.append(Difference(debut: reference.date, fin: dernier.date, segment: numero,
                                             deltas: soustraire(dernier, reference)))
                }
                reference = dernier
                i = j
            }
        }
        return sortie
    }

    static func soustraire(_ b: Echantillon, _ a: Echantillon) -> [Grandeur: Int] {
        var d: [Grandeur: Int] = [:]
        for (g, v) in b.valeurs {
            if let w = a.valeurs[g] { d[g] = v - w }
        }
        return d
    }

    /// Valeurs cumulatives brutes, avec leur segment.
    public static func cumul(_ echantillons: [Echantillon], _ g: Grandeur,
                             ecartMax: TimeInterval = ecartMaxDefaut) -> [PointCumul] {
        var sortie: [PointCumul] = []
        for (numero, segment) in segmenter(echantillons, ecartMax: ecartMax).enumerated() {
            for e in segment {
                if let v = e.valeurs[g] { sortie.append(PointCumul(date: e.date, segment: numero, valeur: v)) }
            }
        }
        return sortie
    }

    // MARK: - Courbes du Bluetooth Mesh et des ordres

    /// Une grandeur ramenee a la minute.
    public static func parMinute(_ d: Difference, _ g: Grandeur) -> Double? {
        guard let v = d[g], d.duree > 0 else { return nil }
        return Double(v) * 60 / d.duree
    }

    /// Part des annonces de notre reseau dont le NetMIC est faux : `d netmic_faux /
    /// d nid_reconnu`, nil sans annonce de notre reseau dans la fenetre. Le pont ne
    /// verifie le NetMIC que d'un message qui porte notre NID (components/mesh/crochet.c) :
    /// un IV Index faux la fait monter vers 100 % ; des cles perimees (reseau recree) font
    /// tomber a zero les annonces de notre reseau, sans NetMIC faux. Bornee a 1 : pendant
    /// un renouvellement des cles, un message peut echouer avec l'ancienne et la nouvelle.
    public static func partNetmicFaux(_ d: Difference) -> Double? {
        guard let n = d[.nidReconnu], n > 0, let f = d[.netmicFaux] else { return nil }
        return min(1, Double(f) / Double(n))
    }

    /// Part des emissions refusees : `d echecs_emission / (d emis + d echecs_emission)`.
    public static func partRefusEmission(_ d: Difference) -> Double? {
        guard let e = d[.emis], let r = d[.echecsEmission], e + r > 0 else { return nil }
        return Double(r) / Double(e + r)
    }

    /// Part des ordres abandonnes parmi ceux qui ont fini par confirme ou abandon.
    public static func partAbandons(_ d: Difference) -> Double? {
        guard let c = d[.confirmes], let a = d[.abandons], c + a > 0 else { return nil }
        return Double(a) / Double(c + a)
    }
}

/// Series tirees des messages successifs du pont, pour les graphiques : compteurs du
/// Mesh et du bloc `pont` (differences par `Courbes`), part des relectures repondues
/// et delais des ordres par lampe, tas libre. Chaque serie est bornee ; un changement
/// de `boot` ouvre un nouveau segment (`segment`).
///
/// Code pur : la date de chaque message est passee en argument (celle d'`EtatPont`).
public struct SeriesCourbes: Sendable, Equatable {
    /// Points gardes par serie : 2 h a une ligne par seconde.
    public static let capaciteDefaut = 7200

    public var capacite: Int
    /// `compteurs` `mesh` (absents a distance tant que `json compteurs` vaut 0).
    public private(set) var mesh: [Echantillon] = []
    /// `etat` `pont` : relectures, trames, ordres.
    public private(set) var pont: [Echantillon] = []
    /// Par lampe : part des relectures repondues sur 10 min, en pour cent (`part_10min`).
    public private(set) var parts: [Int: [PointMesure]] = [:]
    /// Par lampe : fin de chaque ordre (`ordre` : issue, delai, essai).
    public private(set) var ordres: [Int: [PointOrdre]] = [:]
    /// Tas libre, en octets (`sante.sys.heap`).
    public private(set) var tas: [PointMesure] = []
    /// Plus bas du tas depuis le demarrage (`sante.sys.heap_min`).
    public private(set) var tasMin: [PointMesure] = []
    /// Segment en cours : augmente a chaque nouveau `boot`.
    public private(set) var segment = 0
    public private(set) var boot: String?

    public init(capacite: Int = SeriesCourbes.capaciteDefaut) {
        self.capacite = max(1, capacite)
    }

    /// Ajoute ce qu'un message apporte aux series. `date` : date de la ligne (ancre du
    /// `hello`). Les lignes anciennes (avant le `hello` de la connexion) n'y vont pas.
    public mutating func ajouter(_ m: MessageCarte, date: Date) {
        switch m {
        case .helloBase(let h): noterBoot(h.boot)
        case .helloIdentite(let h): noterBoot(h.boot)
        case .battement(let b): noterBoot(b.boot)
        case .etatPont(let p):
            noterBoot(p.boot)
            Self.borner(&pont, Echantillon.pont(p, date: date, boot: boot), capacite)
        case .etatSante(let s):
            noterBoot(s.boot)
            if let h = s.sys?.heap { Self.borner(&tas, PointMesure(date: date, segment: segment, valeur: Double(h)), capacite) }
            if let h = s.sys?.heapMin { Self.borner(&tasMin, PointMesure(date: date, segment: segment, valeur: Double(h)), capacite) }
        case .compteursMesh(let c):
            Self.borner(&mesh, Echantillon.mesh(c, date: date, boot: boot), capacite)
        case .etatLampe(let l):
            Self.borner(&parts[l.lampe, default: []],
                   PointMesure(date: date, segment: segment, valeur: l.part10Min.map(Double.init)), capacite)
        case .ordre(let o):
            Self.borner(&ordres[o.lampe, default: []],
                   PointOrdre(date: date, segment: segment, lampe: o.lampe, issue: o.issue, delaiMs: o.delaiMs,
                              essai: o.essai), capacite)
        default:
            break
        }
    }

    /// Tout oublier (bouton "Effacer les courbes").
    public mutating func vider() {
        self = SeriesCourbes(capacite: capacite)
    }

    /// Numeros des lampes presentes dans les series.
    public var lampes: [Int] { Set(parts.keys).union(ordres.keys).sorted() }

    /// Delais des ordres confirmes d'une lampe, en millisecondes.
    public func delaisConfirmes(lampe: Int) -> [PointMesure] {
        (ordres[lampe] ?? []).compactMap { o in
            guard o.issue == .confirme, let d = o.delaiMs else { return nil }
            return PointMesure(date: o.date, segment: o.segment, valeur: Double(d))
        }
    }

    private mutating func noterBoot(_ b: String?) {
        guard let b else { return }
        if let boot, boot != b { segment += 1 }
        boot = b
    }

    private static func borner<T>(_ serie: inout [T], _ x: T, _ capacite: Int) {
        serie.append(x)
        if serie.count > capacite { serie.removeFirst(serie.count - capacite) }
    }
}
````

`apps/macos/AmaranProtocole/Reseau/RepertoirePonts.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (Reseau/RepertoirePonts.swift) : le numero de serie du pont
// amaran est `AMARAN-<MAC>` (docs/PROTOCOLE-JSON.md 5.1), son nom SRP vient du bloc `ip` (5.5).
import Foundation

/// Ponts deja vus par l'app, retenus par MAC : leur modele, tire du numero de serie
/// du pont (`hello` `identite` : `id.serie` = `AMARAN-<MAC>`, 5.1), et leur nom SRP
/// (bloc `ip`, 5.5). Sert a nommer un port USB avant la connexion (son numero de
/// serie USB est la MAC) et l'entree reseau du meme pont : "AMARAN · F0:F5:BD:0A:0B:0C".
/// Codable : le modele de l'app le garde dans les reglages (`cleReglages`).
public struct RepertoirePonts: Codable, Sendable, Equatable {
    public struct Entree: Codable, Sendable, Equatable {
        /// "AMARAN" : le numero de serie sans sa MAC.
        public var modele: String?
        /// Nom SRP, sans `.local`.
        public var srp: String?

        public init(modele: String? = nil, srp: String? = nil) {
            self.modele = modele
            self.srp = srp
        }
    }

    /// Cle des reglages (UserDefaults) ou le modele de l'app le range.
    public static let cleReglages = "repertoirePonts"

    /// Cle : MAC en 12 hexa majuscules.
    public private(set) var parMac: [String: Entree] = [:]

    public init() {}

    /// Relu depuis les reglages ; nil si les donnees sont illisibles.
    public init?(donnees: Data) {
        guard let r = try? JSONDecoder().decode(Self.self, from: donnees) else { return nil }
        self = r
    }

    /// Pour les reglages.
    public var donnees: Data? { try? JSONEncoder().encode(self) }

    /// MAC en 12 hexa majuscules, separateurs (":" ou "-") retires ; nil si le texte
    /// n'en est pas une.
    public static func mac(_ texte: String?) -> String? {
        guard let texte else { return nil }
        let h = texte.uppercased().filter { $0 != ":" && $0 != "-" }
        guard h.count == 12, h.allSatisfy(\.isHexDigit) else { return nil }
        return h
    }

    /// "F0:F5:BD:0A:0B:0C" pour "F0F5BD0A0B0C".
    public static func macLisible(_ mac: String) -> String {
        var s = ""
        for (i, c) in mac.enumerated() {
            if i > 0, i % 2 == 0 { s.append(":") }
            s.append(c)
        }
        return s
    }

    /// Modele du numero de serie "AMARAN-F0F5BD0A0B0C" : "AMARAN". nil si la serie ne
    /// finit pas par "-" et la MAC de ce pont.
    public static func modele(serie: String?, mac: String) -> String? {
        guard let serie, let tiret = serie.lastIndex(of: "-") else { return nil }
        let avant = String(serie[..<tiret])
        guard !avant.isEmpty, Self.mac(String(serie[serie.index(after: tiret)...])) == mac else { return nil }
        return avant
    }

    /// Note ce que le pont dit de lui (`hello` `identite`, bloc `ip`) ; vrai si le
    /// repertoire change. Un nom SRP n'appartient qu'a un pont : retire a celui qui
    /// l'avait (pont remplace, nouvelle mise en service).
    @discardableResult
    public mutating func noter(mac texte: String?, serie: String?, srp: String?) -> Bool {
        guard let mac = Self.mac(texte) else { return false }
        let avant = self
        var e = parMac[mac] ?? Entree()
        if let m = Self.modele(serie: serie, mac: mac) { e.modele = m }
        if let srp, !srp.isEmpty {
            for (autre, x) in parMac where autre != mac && x.srp == srp { parMac[autre]?.srp = nil }
            e.srp = srp
        }
        parMac[mac] = e
        return self != avant
    }

    /// Note ce que l'etat du pont en dit : MAC et serie du `hello` `identite`, nom
    /// SRP du bloc `ip`.
    @discardableResult
    public mutating func noter(_ etat: EtatPont) -> Bool {
        noter(mac: etat.mac, serie: etat.identite?.valeur.id?.serie, srp: etat.srp)
    }

    /// Oublie un pont (reglages "Oublier ce pont").
    public mutating func oublier(mac texte: String) {
        guard let mac = Self.mac(texte) else { return }
        parMac[mac] = nil
    }

    /// MAC du pont qui porte ce nom SRP.
    public func mac(pourSrp srp: String) -> String? {
        parMac.first { $0.value.srp == srp }?.key
    }

    /// Ponts joignables par le reseau (nom SRP connu), par MAC.
    public var pontsReseau: [(mac: String, srp: String)] {
        parMac.compactMap { m, e in e.srp.map { (m, $0) } }.sorted { $0.mac < $1.mac }
    }

    /// "AMARAN · F0:F5:BD:0A:0B:0C" ; modele encore inconnu (pont jamais connecte) :
    /// "ESP32 · F0:F5:BD:0A:0B:0C".
    public func titre(mac: String) -> String {
        "\(parMac[mac]?.modele ?? "ESP32") · \(Self.macLisible(mac))"
    }
}
````

`apps/macos/AmaranProtocole/Reseau/CleReseau.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : cle UDP de 32 octets creee par l'USB, code pur ;
// l'etat de l'acces reseau se lit dans le bloc `ip` (docs/PROTOCOLE-JSON.md 5.5, 10.2).
import Foundation

/// Cle partagee du transport reseau, creee par l'USB (spec 3b, section 7) : l'app fournit
/// un alea, le pont calcule `cle = HMAC-SHA256(alea_app, alea_pont)` et la
/// rend une seule fois dans la reponse.
public enum CleReseau {
    /// Alea de l'app : 32 octets d'un generateur cryptographique.
    public static func alea() -> Data { H1.aleatoire(32) }

    /// `json cle nouvelle <64 HEXA>` (USB seulement ; le pont la refuse a distance).
    public static func commande(alea: Data) -> String {
        "json cle nouvelle \(H1.hexa(alea))"
    }

    public struct Creee: Sendable, Equatable {
        public var cle: Data
        public var empreinte: String
    }

    public enum Erreur: Error, Sendable, Equatable, CustomStringConvertible {
        /// `ok` faux (tampon USB occupe...) : rien n'a change sur le pont.
        case refusee(String)
        case cleIllisible
        case empreinteIncoherente

        public var description: String {
            switch self {
            case .refusee(let msg): "Le pont refuse la nouvelle clé : \(msg)"
            case .cleIllisible: "Réponse sans clé lisible (64 hexa majuscules attendus) : clé non rangée."
            case .empreinteIncoherente: "Empreinte incohérente avec la clé reçue : clé non rangée."
            }
        }
    }

    /// Reponse `fin` a `json cle nouvelle` : la cle et son empreinte, verifiees.
    public static func verifier(_ r: Reponse) -> Result<Creee, Erreur> {
        guard r.ok else { return .failure(.refusee(r.msg ?? r.code.rawValue)) }
        guard let texte = r.cle, let cle = H1.octets(hexa: texte), cle.count == 32 else { return .failure(.cleIllisible) }
        guard let e = r.empreinte, e == H1.kid(cle: cle) else { return .failure(.empreinteIncoherente) }
        return .success(Creee(cle: cle, empreinte: e))
    }
}

/// Acces reseau vu par l'USB : bloc `ip` du pont (5.5), et cles de ce Mac.
public enum EtatAccesReseau: Sendable, Equatable {
    /// Pas de bloc `ip` (pas encore recu), nom SRP inconnu, ou firmware sans canal
    /// UDP (pas de `udp`).
    case inconnu
    /// Le pont n'a pas de cle : port 5480 ferme.
    case sansCle(nom: String)
    /// La cle du pont est celle que ce Mac garde pour ce nom SRP.
    case cleConnue(nom: String, empreinte: String)
    /// Le pont a une cle que ce Mac n'a pas (autre Mac, cle recreee ailleurs).
    case cleInconnue(nom: String, empreinte: String)

    /// `empreinteDuMac` : empreinte de la cle que ce Mac garde pour un nom SRP, nil sans cle.
    /// Une cle existe si `udp.cle` le dit (a defaut, si le port ecoute) et qu'elle a une empreinte.
    public static func depuis(ip: ReseauIp?, empreinteDuMac: (String) -> String?) -> EtatAccesReseau {
        guard let nom = ip?.srp, !nom.isEmpty, let udp = ip?.udp else { return .inconnu }
        guard udp.cle ?? (udp.ouvert == true), let e = udp.empreinte, !e.isEmpty else { return .sansCle(nom: nom) }
        return empreinteDuMac(nom) == e ? .cleConnue(nom: nom, empreinte: e) : .cleInconnue(nom: nom, empreinte: e)
    }

    /// Nom SRP du pont, s'il est connu.
    public var nom: String? {
        switch self {
        case .inconnu: nil
        case .sansCle(let n), .cleConnue(let n, _), .cleInconnue(let n, _): n
        }
    }
}
````

- [ ] **Step 4 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `Test run with 193 tests in 25 suites passed` (`AmaranProtocoleTests`) et `Test run with 12 tests in 4 suites passed` (`AmaranCompagnonTests`) ; aucune ligne `error:` ni `warning:`.

- [ ] **Step 5 : commit.**

```bash
git add apps/macos/AmaranProtocole apps/macos/AmaranProtocoleTests
git commit -m "$(printf "App compagnon : courbes, repertoire des ponts, etat de l'acces reseau\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 8: Le modèle : source réseau, trousseau des ponts, création de la clé, alertes, trames et courbes, démo

**Files:**
- Create: `apps/macos/AmaranCompagnon/Modele/CompteursMesh.swift`, `apps/macos/AmaranCompagnon/Modele/CourbesRedemarrages.swift`, `apps/macos/AmaranCompagnon/Modele/FiltreTrames.swift`, `apps/macos/AmaranCompagnon/Modele/Pont+Reseau.swift`, `apps/macos/AmaranCompagnon/Reseau/AlerteReseau.swift`, `apps/macos/AmaranCompagnon/Reseau/EtatSessionPont.swift`, `apps/macos/AmaranCompagnon/Reseau/TrousseauPonts.swift`
- Modify: `apps/macos/AmaranCompagnon/AmaranCompagnon.entitlements`, `apps/macos/AmaranCompagnon/AmaranCompagnonApp.swift`, `apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, `apps/macos/AmaranCompagnon/Modele/Journal.swift`, `apps/macos/AmaranCompagnon/Modele/Pont.swift`, `apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, `apps/macos/project.yml`
- Create: `apps/macos/AmaranCompagnonTests/CompteursMeshTests.swift`, `apps/macos/AmaranCompagnonTests/PontReseauTests.swift`, `apps/macos/AmaranCompagnonTests/TrousseauPontsTests.swift`
- Modify: `apps/macos/AmaranCompagnonTests/DemoBoutEnBoutTests.swift`

**Interfaces:**
- Consumes : les Tasks 5 à 7.
- Produces (pour les écrans de la Task 9) :
  - `Pont.Source.reseau(nom:)` ; `Pont` : `trames`, `courbes`, `alerteReseau`, `pontsConnus`, `repertoire`, `genreTransport`, `aDistance`, `peutEnvoyer(_:)`, `activerTrames(_:)`, `tramesActives`, `tramesDemandeesLe`, `tramesCoupeesParLePont(a:)`, `secondesAvantCoupureDesTrames(a:)`, `reglerCadence(_:ms:)`, `etatCompteursMesh`, `reseauChange()`, `viderTrames()`, `viderCourbes()` ; `Pont+Reseau.swift` : `titre(serie:chemin:)`, `titre(port:)`, `titre(reseau:)`, `titre(pont:)` (« MODELE · MAC » tiré du répertoire, comme Halo Compagnon), `accesReseau`, `texteSansAccesReseau`, `creationCleEnCours`, `creerCle()`, `oublierPont(_:)`, `relirePontsConnus()` ;
  - `protocol TrousseauPonts` (`lister`, `lire(nom:)`, `ranger(nom:cle:empreinte:)`, `oublier(nom:)`), `TrousseauPontsSysteme`, `TrousseauPontsMemoire`, `PontConnu`, `ErreurTrousseauPonts` ;
  - `AlerteReseau` (`transport`, `trousseau`, `sansHello` ; `texte`, `raison`), `EtatSessionPont`, `CompteursMesh`, `FiltreTrames`, `CourbesRedemarrages` ;
  - le droit `com.apple.security.network.client` et `NSLocalNetworkUsageDescription`.

Pourquoi : la spec 3b, sections 5 (la clé UDP dans le trousseau), 7, 8 et 9.
- **La source réseau** : un pont connu du trousseau des ponts s'ouvre par `TransportUDP` vers `<nom SRP>.local` ; la politique réseau du corrélateur et les réglages distants du moteur s'appliquent ; la reprise suit Halo (pas de boucle serrée, reprise au changement du chemin réseau ou au réveil). La première ligne reçue par UDP n'est pas jetée (Halo jetait le `hello` et perdait 4 s à chaque connexion).
- **Le trousseau des ponts** : service `fr.djoko.amaran.pont`, compte = nom SRP, local au Mac (comme celui des clés du Mesh, jamais iCloud) ; la clé n'en sort que pour ouvrir une session.
- **La clé se crée par l'USB seulement** : `creerCle` envoie `CleReseau.commande` comme une commande secrète, vérifie l'empreinte rendue, puis range la clé sous le nom SRP du bloc `ip`. « Oublier… » retire la clé de ce Mac (le pont garde la sienne).
- **Les alertes** : route absente (la console et le panneau de connexion pointent vers `halo-routes`), clé absente ou trousseau inaccessible, sessions pleines (`sansHello`, nouvel essai toutes les 30 s).
- **À distance**, la carte du Mesh dit quand les compteurs ne sont pas relevés, et propose de les demander ; la console refuse sans l'envoyer une commande que la liste blanche du pont refuserait.
- **La démo** répond à `json trames`, `json cle nouvelle|efface` et porte un bloc `ip`, avec des valeurs inventées.

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranCompagnonTests/CompteursMeshTests.swift` (contenu complet) :

````swift
// Carte « Bluetooth Mesh » et ecran Graphiques a distance : l'explication des compteurs
// absents ou figes, et l'origine de l'IV Index (logique pure, docs/PROTOCOLE-JSON.md 10.5).
import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

@Suite("Compteurs du Mesh a distance")
struct CompteursMeshTests {
    @Test func parLUSBRienNeChange() {
        #expect(CompteursMesh.etat(aDistance: false, enDirect: false, periodeMs: 1000) == .normal)
        #expect(CompteursMesh.etat(aDistance: false, enDirect: false, periodeMs: nil) == .normal)
        #expect(CompteursMesh.etat(aDistance: false, enDirect: true, periodeMs: 0) == .normal)
        #expect(CompteursMesh.texte(.normal, dernierReleve: Date()) == nil)
    }

    @Test func aDistanceSansCompteurs() {
        #expect(CompteursMesh.etat(aDistance: true, enDirect: false, periodeMs: 0) == .nonReleves)
        #expect(CompteursMesh.etat(aDistance: true, enDirect: false, periodeMs: nil) == .nonReleves)
        #expect(CompteursMesh.etat(aDistance: true, enDirect: false, periodeMs: 5000) == .demandes)
        #expect(CompteursMesh.etat(aDistance: true, enDirect: true, periodeMs: 5000) == .normal)
    }

    /// Un bloc recu dans une session precedente ne fait jamais passer la carte pour
    /// relevee : periode a 0, « non releves », quel que soit ce qui a ete recu avant.
    @Test func periodeNulleToujoursNonReleves() {
        #expect(CompteursMesh.etat(aDistance: true, enDirect: true, periodeMs: 0) == .nonReleves)
        let texte = CompteursMesh.texte(.nonReleves, dernierReleve: Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(texte?.hasPrefix("Compteurs du Mesh non relevés à distance (dernier relevé à ") == true)
        #expect(CompteursMesh.texte(.nonReleves, dernierReleve: nil) == "Compteurs du Mesh non relevés à distance")
        #expect(CompteursMesh.texte(.demandes, dernierReleve: nil) == "Compteurs du Mesh demandés, en attente du premier relevé")
    }

    @Test func periodeProposeeEstPermiseADistance() {
        // 10.5 : `json compteurs` 0 ou 5 000 a 60 000 ms.
        #expect(PolitiqueCommandes.autoriseeADistance("json compteurs \(CompteursMesh.periodeProposeeMs)") == nil)
    }

    @Test func ivIndex() {
        #expect(CompteursMesh.ivIndex(compteurs: 3, ivNvs: 2)?.texte == "3")
        #expect(CompteursMesh.ivIndex(compteurs: 3, ivNvs: 2)?.deNvs == false)
        #expect(CompteursMesh.ivIndex(compteurs: nil, ivNvs: 2)?.texte == "2 (mémoire du pont)")
        #expect(CompteursMesh.ivIndex(compteurs: nil, ivNvs: 0)?.deNvs == true)
        #expect(CompteursMesh.ivIndex(compteurs: nil, ivNvs: nil) == nil)
    }
}
````

`apps/macos/AmaranCompagnonTests/DemoBoutEnBoutTests.swift`, bloc 1 sur 3. Remplacer :

````swift
func pontDemo(copie: ReseauMesh? = ReseauDemo.reseau) -> Pont {
    let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(copie),
                 preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
    p.vitesseDemo = 20
````

par :

````swift
func pontDemo(copie: ReseauMesh? = ReseauDemo.reseau) -> Pont {
    let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(copie),
                 trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                 preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
    p.vitesseDemo = 20
````

`apps/macos/AmaranCompagnonTests/DemoBoutEnBoutTests.swift`, bloc 2 sur 3. Remplacer :

````swift
    }

    @Test func etiquettesDesPortsEtConfirmationDuPont() {
        func port(_ chemin: String, vid: Int, serie: String?) -> PortUSB {
            PortUSB(chemin: chemin, vid: vid, pid: 0x1001, serie: serie, produit: nil)
````

par :

````swift
    }

    /// Titres des ports comme Halo Compagnon : "MODELE · MAC" (modele du repertoire ; `AMARAN`
    /// pour le dernier pont confirme pas encore note ; sinon "ESP32"), le nom court sans MAC.
    @Test func titresDesPortsEtConfirmationDuPont() {
        func port(_ chemin: String, vid: Int, serie: String?) -> PortUSB {
            PortUSB(chemin: chemin, vid: vid, pid: 0x1001, serie: serie, produit: nil)
````

`apps/macos/AmaranCompagnonTests/DemoBoutEnBoutTests.swift`, bloc 3 sur 3. Remplacer :

````swift
        let pont = "02:00:00:00:00:AA"
        let autre = "02:00:00:00:00:BB"
        #expect(Pont.libellePort(port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont), dernierPont: pont) == "Pont amaran (…00:AA)")
        #expect(Pont.libellePort(port("/dev/cu.usbmodem1101", vid: 0x303A, serie: autre), dernierPont: pont) == "Autre carte Espressif (…00:BB)")
        // Aucun pont confirme : toute carte Espressif est "autre".
        #expect(Pont.libellePort(port("/dev/cu.usbmodem1101", vid: 0x303A, serie: pont), dernierPont: nil) == "Autre carte Espressif (…00:AA)")
        // Sans numero de serie : le nom court du port.
        #expect(Pont.libellePort(port("/dev/cu.usbmodem1101", vid: 0x303A, serie: nil), dernierPont: pont) == "usbmodem1101")
        #expect(Pont.libellePort(port("/dev/cu.usbmodem1101", vid: 0x303A, serie: ""), dernierPont: pont) == "usbmodem1101")

        // Un pont est confirme par la capacite `mesh` ou par un numero de serie AMARAN-.
````

par :

````swift
        let pont = "02:00:00:00:00:AA"
        let autre = "02:00:00:00:00:BB"
        let prefs = UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!
        prefs.set(pont, forKey: Pont.cleDernierPont)
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(),
                     trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                     preferences: prefs)
        // Dernier pont confirme, repertoire encore vide : le modele AMARAN ; l'autre carte : ESP32.
        #expect(p.titre(port: port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont)) == "AMARAN · 02:00:00:00:00:AA")
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: autre)) == "ESP32 · 02:00:00:00:00:BB")
        // Le repertoire fait foi des qu'il connait la carte (modele appris au hello).
        p.repertoire.noter(mac: autre, serie: "AMARAN-0200000000BB", srp: nil)
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: autre)) == "AMARAN · 02:00:00:00:00:BB")
        p.repertoire.noter(mac: pont, serie: "BANC-0200000000AA", srp: nil)
        #expect(p.titre(port: port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont)) == "BANC · 02:00:00:00:00:AA")
        // Sans numero de serie lisible : le nom court du port.
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: nil)) == "usbmodem1101")
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: "")) == "usbmodem1101")
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: "pas-une-mac")) == "usbmodem1101")
        // La source serie choisie, debranchee ou non, porte le meme titre.
        #expect(p.titre(serie: autre, chemin: "/dev/cu.usbmodem1101") == "AMARAN · 02:00:00:00:00:BB")
        #expect(p.titre(serie: nil, chemin: "/dev/cu.usbmodem1101") == "usbmodem1101")
        // Aucun pont confirme : toute carte inconnue est ESP32.
        let vierge = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(),
                          trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                          preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        #expect(vierge.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: pont)) == "ESP32 · 02:00:00:00:00:AA")

        // Un pont est confirme par la capacite `mesh` ou par un numero de serie AMARAN-.
````

`apps/macos/AmaranCompagnonTests/PontReseauTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5, PontReseauTests.swift) : la source reseau du
// modele (docs/PROTOCOLE-JSON.md 10). Un transport factice joue le pont joint par Thread
// (lignes de 10.6) ; la creation de cle passe par le pont simule du mode demo. Nom SRP,
// MAC, adresses et cles inventes ; trousseaux en memoire.
import AmaranProtocole
import Foundation
import Synchronization
import Testing
@testable import AmaranCompagnon

/// Transport factice d'une source reseau : garde les lignes envoyees, rend les lignes
/// injectees comme `TransportUDP` les rendrait (RS + JSON + LF). Chaque ouverture est
/// une nouvelle session.
final class TransportFactice: Transport {
    let genre: GenreTransport = .udp
    let nom: String
    private struct Etat {
        var suite: AsyncStream<EvenementTransport>.Continuation?
        var envoyees: [String] = []
        var ouvertures = 0
        var cles: [Data] = []
    }
    private let etat = Mutex(Etat())

    init(hote: String) { nom = hote }

    var envoyees: [String] { etat.withLock { $0.envoyees } }
    var ouvertures: Int { etat.withLock { $0.ouvertures } }
    var cles: [Data] { etat.withLock { $0.cles } }

    func noterCle(_ cle: Data) { etat.withLock { $0.cles.append(cle) } }

    func ouvrir() async throws -> AsyncStream<EvenementTransport> {
        let (flux, suite) = AsyncStream.makeStream(of: EvenementTransport.self, bufferingPolicy: .unbounded)
        etat.withLock { e in
            e.suite = suite
            e.ouvertures += 1
        }
        return flux
    }

    func envoyer(_ donnees: Data) throws {
        let lignes = String(decoding: donnees, as: UTF8.self).split(separator: "\n").map(String.init)
        etat.withLock { $0.envoyees += lignes }
    }

    func fermer() {
        let suite = etat.withLock { e -> AsyncStream<EvenementTransport>.Continuation? in
            let s = e.suite
            e.suite = nil
            return s
        }
        suite?.yield(.ferme(raison: "session réseau fermée par l'app"))
        suite?.finish()
    }

    /// Une ligne du pont.
    func injecter(_ json: String) {
        _ = etat.withLock { $0.suite?.yield(.donnees(Data(("\u{1E}" + json + "\n").utf8))) }
    }

    /// Numero de la derniere ligne envoyee qui contient `texte`.
    func numero(de texte: String) -> Int? {
        guard let l = envoyees.last(where: { $0.contains(texte) }), l.hasPrefix("id="),
              let espace = l.firstIndex(of: " ") else { return nil }
        return Int(l[l.index(l.startIndex, offsetBy: 3)..<espace])
    }
}

@Suite("Source reseau du modele", .serialized)
@MainActor
struct PontReseauTests {
    static let nom = "1A2B3C4D5E6F7081"
    static let cle = Data((0..<32).map { 0x40 &+ UInt8($0) })
    /// Nom SRP du pont simule du mode demo : jamais 16 hexa.
    static let nomDemo = SimulateurDemo.srpDemo

    static func pont(cle: Data? = PontReseauTests.cle, trousseauPontsDemo: TrousseauPontsMemoire = TrousseauPontsMemoire(),
                     preferences: UserDefaults? = nil) throws -> (Pont, TrousseauPontsMemoire) {
        let t = TrousseauPontsMemoire()
        if let cle { try t.ranger(nom: nom, cle: cle, empreinte: H1.kid(cle: cle)) }
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                     trousseauPonts: t, trousseauPontsDemo: trousseauPontsDemo,
                     preferences: preferences ?? UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        p.vitesseDemo = 20
        return (p, t)
    }

    /// Le pont factice repond au json 1 comme un pont joint par Thread (10.6).
    static func repondreAuJson1(_ f: TransportFactice, boot: String = "3FA2C901") async throws {
        try #require(await attendre { f.numero(de: "json 1") != nil })
        let n = try #require(f.numero(de: "json 1"))
        f.injecter(#"{"v":1,"t":"hello","n":0,"ms":900120,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"\#(boot)","reset":"logiciel","reset_n":3,"up_s":900,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false},"limites":{"ligne_max":1024,"cmd_max":127}}"#)
        f.injecter(#"{"v":1,"t":"hello","n":1,"ms":900121,"bloc":"identite","boot":"\#(boot)","mac":"02000000DE01","id":{"fabricant":"TEST_VENDOR","produit":"TEST_PRODUCT","serie":"AMARAN-02000000DE01","nom":"Pont amaran"},"caps":["matter","thread","mesh","catalogue","ordres","led","log","trames","udp","cle","texte"]}"#)
        f.injecter(#"{"v":1,"t":"reponse","n":2,"ms":900130,"id":\#(n),"etape":"fin","cmd":"json 1 bail 60","ok":true,"code":"ok","duree_ms":10,"bail_s":60,"up_s":900}"#)
    }

    /// Ouverture par le reseau : cle lue dans le trousseau des ponts, hote `<nom>.local`,
    /// session distante (json 1 avec un bail, sans Ctrl-U, politique reseau), repertoire,
    /// liste blanche de la console, texte d'une commande, trames.
    @Test func ouvertureParLeReseau() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        var hotes: [String] = []
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { hote, cle in
            hotes.append(hote)
            f.noterCle(cle)
            return f
        }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(hotes == ["1A2B3C4D5E6F7081.local"])
        #expect(f.cles == [Self.cle], "la cle du trousseau des ponts ouvre la session")
        #expect(f.envoyees.first?.hasSuffix(" json 1 bail 60") == true)
        #expect(!f.envoyees.contains { $0.contains("\u{15}") }, "pas de Ctrl-U a distance")
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.aDistance)
        #expect(pont.moteur.genre == .udp)
        #expect(pont.moteur.correlateur.politique == .reseau)
        // La premiere ligne recue (le hello) n'est pas jetee comme a l'ouverture d'un port.
        #expect(pont.etat.helloBase?.valeur.rev == 1)
        #expect(pont.reglages?.transport == .udp)
        #expect(f.envoyees.filter { $0.contains("json 1") }.count == 1, "hello recu du premier coup : pas de renvoi")
        #expect(pont.console.elements.contains { $0.texte == "Session réseau ouverte : 1A2B3C4D5E6F7081.local." })
        #expect(pont.accesReseau == .inconnu, "l'acces reseau ne se gere que par l'USB")

        // Le bloc ip d'un vrai pont : le repertoire le retient, et titre la source.
        f.injecter(#"{"v":1,"t":"reseau","n":3,"ms":900200,"bloc":"ip","srp":"1A2B3C4D5E6F7081","adresses":[{"type":"omr","adresse":"fd12:34:5678:0:aaaa:bbbb:ccc:dddd"}],"udp":{"port":5480,"cle":true,"empreinte":"\#(H1.kid(cle: Self.cle))","ouvert":true,"sessions":1,"recus":4,"emis":9,"rejets":0,"perdus":0}}"#)
        #expect(await attendre { pont.etat.srp == Self.nom })
        #expect(pont.titre(reseau: Self.nom) == "AMARAN · 02:00:00:00:DE:01", "titre de la carte : modele puis MAC")
        #expect(pont.titre(reseau: "0000000000000000") == "0000000000000000.local", "pont inconnu : son nom SRP")
        let garde = try #require(pont.preferences.data(forKey: RepertoirePonts.cleReglages))
        #expect(RepertoirePonts(donnees: garde)?.mac(pourSrp: Self.nom) == "02000000DE01")

        // Compteurs : le profil distant les coupe ; l'IV Index vient alors de config mesh.
        #expect(pont.etatCompteursMesh == .nonReleves)
        #expect(pont.ivIndexMesh == nil)
        f.injecter(#"{"v":1,"t":"config","n":4,"ms":900210,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":2,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}"#)
        #expect(await attendre { pont.etat.mesh != nil })
        #expect(pont.ivIndexMesh?.texte == "2 (mémoire du pont)")
        pont.activerCompteursMesh()
        #expect(f.envoyees.last?.hasSuffix(" json compteurs 5000") == true)
        // Les reglages ne suivent qu'a la reponse du pont.
        let nc = try #require(f.numero(de: "json compteurs 5000"))
        f.injecter(#"{"v":1,"t":"reponse","n":5,"ms":905000,"id":\#(nc),"etape":"fin","cmd":"json compteurs 5000","ok":true,"code":"ok","duree_ms":1}"#)
        #expect(await attendre { pont.etatCompteursMesh == .demandes })
        f.injecter(#"{"v":1,"t":"compteurs","n":6,"ms":905612,"bloc":"mesh","annonces":5120,"nid_reconnu":1630,"nid_inconnu":3402,"netmic_faux":0,"emis":64,"echecs_emission":0,"iv":3,"seq":1093,"plancher":1024}"#)
        #expect(await attendre { pont.etat.compteurs != nil })
        #expect(pont.etatCompteursMesh == .normal)
        #expect(pont.ivIndexMesh?.texte == "3", "les compteurs priment sur iv_nvs")

        // Liste blanche : une commande refusee n'est jamais envoyee, la console le dit.
        let avant = f.envoyees.count
        guard case .refusee(let raison) = pont.console("redemarre") else {
            Issue.record("redemarre doit etre refusee a distance")
            return
        }
        #expect(raison.contains("interdite a distance"))
        // La raison du pont citee une fois, telle quelle, dans une phrase qui ne la repete pas.
        #expect(pont.console.elements.last?.texte
                == "« redemarre » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).")
        if case .refusee = pont.console("json cle efface") {} else { Issue.record("json cle efface : USB seulement") }
        #expect(pont.envoyer("mesh releve 5") == nil)
        #expect(pont.console.elements.last?.texte
                == "« mesh releve 5 » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).")
        #expect(!pont.peutEnvoyer("mesh releve 5"))
        #expect(pont.peutEnvoyer("lampe 1 on"))
        // Une commande permise qui demande une confirmation la garde a distance.
        if case .confirmation = pont.console("mesh lampe 1 masquer") {} else { Issue.record("confirmation attendue") }
        #expect(f.envoyees.count == avant, "rien n'est parti")
        // Une commande permise part, avec un id, et sa sortie `texte` va dans la console.
        #expect(pont.console("lampe 1") == .envoyee)
        try #require(await attendre { f.numero(de: "lampe 1") != nil })
        let n = try #require(f.numero(de: "lampe 1"))
        f.injecter(#"{"v":1,"t":"reponse","n":4,"ms":913000,"id":\#(n),"etape":"debut","cmd":"lampe 1","ok":true,"code":"en_cours"}"#)
        f.injecter(#"{"v":1,"t":"texte","n":5,"ms":913004,"id":\#(n),"txt":"lampe 1 : Lampe bureau"}"#)
        f.injecter(#"{"v":1,"t":"reponse","n":6,"ms":913006,"id":\#(n),"etape":"fin","cmd":"lampe 1","ok":true,"code":"ok","duree_ms":6}"#)
        #expect(await attendre { pont.suivis.last { $0.numero == n }?.etat == .terminee })
        #expect(pont.console.elements.contains { $0.texte == "lampe 1 : Lampe bureau" && $0.numero == n })
        #expect(pont.suivis.last { $0.numero == n }?.texte == ["lampe 1 : Lampe bureau"])

        // Trames (7.6) : journal borne.
        f.injecter(#"{"v":1,"t":"trame","n":7,"ms":95012,"sens":"tx","quoi":"ordre","lampe":1,"marche":true,"intensite":500,"essai":1,"sautes":0}"#)
        #expect(await attendre { pont.trames.elements.count == 1 })
        #expect(pont.trames.elements.first?.trame == Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: true, intensite: 500, essai: 1, sautes: 0))
        #expect(pont.derniereTrame != nil)
        pont.viderTrames()
        #expect(pont.trames.elements.isEmpty)

        // A distance, jamais de creation de cle.
        let lignes = f.envoyees.count
        pont.creerCle()
        #expect(f.envoyees.count == lignes)
        #expect(pont.creationCle == nil)

        // Fermer : json 0 scelle d'abord (une place de session rendue au pont).
        pont.deconnecter()
        #expect(await attendre { f.envoyees.last?.hasSuffix(" json 0") == true })
    }

    /// Les cadences demandees a distance restent dans la liste blanche.
    @Test func cadenceADistanceDansLaListeBlanche() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        pont.reglerCadence(.compteurs, ms: 1000)
        #expect(await attendre { f.envoyees.last?.hasSuffix(" json compteurs 5000") == true })
    }

    /// Aucun hello a distance (places de session prises) : bandeau sansHello, note une
    /// fois, puis nouvelle poignee de main a la relance de 30 s.
    @Test func sansHelloNouvellePoigneeDeMain() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try #require(await attendre { f.numero(de: "json 1") != nil })
        // Renvois du json 1 (meme id a distance), puis l'abandon.
        for d in [2.1, 4.3, 6.5, 8.7] { pont.avancerPourUnTest(de: d) }
        #expect(pont.phase == .sansReponse)
        #expect(pont.alerteReseau == .sansHello)
        #expect(pont.alerte == nil, "a distance, le bandeau est celui de la source reseau")
        let numeros = Set(f.envoyees.filter { $0.contains("json 1") }.map { $0.split(separator: " ")[0] })
        #expect(numeros.count == 1, "a distance, le json 1 renvoye garde son id : \(f.envoyees)")
        func notes() -> Int { pont.console.elements.filter { $0.texte == AlerteReseau.sansHello.texte }.count }
        #expect(notes() == 1)
        // Relance de 30 s : nouvelle poignee de main (le transport se ferme et se rouvre).
        pont.avancerPourUnTest(de: 8.7 + 30.1)
        #expect(await attendre { f.ouvertures == 2 && f.numero(de: "json 1") != nil && pont.etatTransport == .ouvert })
        #expect(pont.alerteReseau == .sansHello, "le bandeau tient jusqu'au hello")
        #expect(pont.console.elements.contains { $0.texte == MoteurSession.Note.reseauSansHello.texte })
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.alerteReseau == nil)
        #expect(notes() == 1)
    }

    @Test func cleAbsenteArreteSansReessayer() throws {
        let (pont, _) = try Self.pont(cle: nil)
        var ouvertures = 0
        pont.fabriqueReseau = { hote, _ in
            ouvertures += 1
            return TransportFactice(hote: hote)
        }
        pont.connecter(.reseau(nom: Self.nom))
        #expect(pont.alerteReseau == .trousseau(.absente(Self.nom)))
        if case .erreur = pont.etatTransport {} else { Issue.record("etat \(pont.etatTransport)") }
        // Chemin reseau retrouve (ou reveil) : une cle absente n'est pas une cause que le
        // reseau puisse lever seul.
        pont.reseauChange()
        #expect(pont.alerteReseau == .trousseau(.absente(Self.nom)), "cle absente : pas de reprise seule")
        if case .erreur = pont.etatTransport {} else { Issue.record("aucune reprise attendue") }
        #expect(ouvertures == 0, "aucun transport sans cle")
        pont.deconnecter()
    }

    @Test func echecAvecRepriseAutomatiqueEffaceLAlerteEtReprogramme() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        // L'echec d'un essai reseau ulterieur : « pas de route » reprend seul.
        pont.echecOuverture(ErreurTransportReseau.pasDeRoute)
        #expect(pont.alerteReseau == nil, "reprise automatique : pas de bandeau d'arret")
        if case .attente = pont.etatTransport {} else { Issue.record("reprise programmee attendue : \(pont.etatTransport)") }
        #expect(pont.console.elements.contains { $0.texte.contains("halo-routes") }, "la note pointe l'assistant des routes")
        pont.deconnecter()
    }

    @Test func echecSansRepriseAutomatiqueGardeLAlerteEtArrete() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        // « Port injoignable » (pont sans cle) : arret net, pas de reessai seul.
        pont.echecOuverture(ErreurTransportReseau.portInjoignable)
        #expect(pont.alerteReseau == .transport(.portInjoignable))
        if case .erreur = pont.etatTransport {} else { Issue.record("arret attendu : \(pont.etatTransport)") }
        pont.reseauChange()
        if case .erreur = pont.etatTransport {} else { Issue.record("pas de reprise sur un changement du reseau") }
        pont.deconnecter()
    }

    /// Reseau local refuse : bandeau, et la reconnexion reessaie quand meme (le refus se
    /// leve dans Reglages Systeme sans evenement pour l'app).
    @Test func reseauLocalRefuseMontreLeBandeauEtReessaie() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        pont.echecOuverture(ErreurTransportReseau.reseauLocalRefuse)
        #expect(pont.alerteReseau == .transport(.reseauLocalRefuse))
        if case .attente = pont.etatTransport {} else { Issue.record("reprise programmee attendue : \(pont.etatTransport)") }
        // Une autre cause ensuite efface le bandeau perime.
        pont.echecOuverture(ErreurTransportReseau.nomIntrouvable(Self.nom + ".local"))
        #expect(pont.alerteReseau == nil)
        pont.deconnecter()
    }

    @Test func causeReseauNoteeUneFoisTantQuElleNeChangePas() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        func occurrences(_ sousChaine: String) -> Int {
            pont.console.elements.filter { $0.texte.contains(sousChaine) }.count
        }
        #expect(occurrences("Clé absente") == 1)
        // Reessayer sur la meme cause n'ajoute pas de ligne.
        pont.reconnecter()
        #expect(occurrences("Clé absente") == 1, "meme cause : pas de nouvelle ligne")
        // Une cause differente, elle, est notee.
        pont.echecOuverture(ErreurTransportReseau.pasDeRoute)
        #expect(occurrences("Pas de route IPv6") == 1, "cause differente : nouvelle ligne")
        pont.deconnecter()
    }

    /// « Liberer le port » sur une source reseau : rien a flasher, la note parle de session.
    @Test func libererUneSourceReseauParleDeSession() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        pont.libererPort()
        #expect(pont.etatTransport == .libere)
        #expect(pont.alerteReseau == nil)
        #expect(pont.console.elements.last?.texte == "Session réseau fermée. « Reconnecter » pour reprendre.")
        #expect(!pont.console.elements.contains { $0.texte.contains("Flasher") })
        pont.deconnecter()
    }

    @Test func pontsConnusEtOubli() async throws {
        let (pont, t) = try Self.pont()
        #expect(pont.pontsConnus == [PontConnu(nom: Self.nom, empreinte: H1.kid(cle: Self.cle))])
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        #expect(await attendre { f.numero(de: "json 1") != nil })
        pont.oublierPont(Self.nom)
        #expect(pont.pontsConnus.isEmpty)
        #expect(t.lister().isEmpty)
        #expect(pont.etatTransport == .ferme, "la source oubliee est deconnectee")
    }

    @Test func textes() {
        #expect(AlerteReseau.textePasDeRoute(assistant: false).contains("tools/macos/halo-routes/installer.sh"))
        #expect(AlerteReseau.textePasDeRoute(assistant: false).contains("github.com/Djoko-cli/benq-screenbar-halo-matter"))
        #expect(!AlerteReseau.textePasDeRoute(assistant: true).contains("installer.sh"))
        #expect(AlerteReseau.sansHello.texte.contains("30 s"))
        #expect(Pont.texteSansReponse(.reseau) == "sans réponse sous 6 s (2 renvois du même id)")
        #expect(Pont.texteSansReponse(.reseau, commande: "json etat") == "sans réponse sous 12 s (2 renvois du même id)",
                "la fin de json etat suit l'instantane")
        #expect(Pont.texteSansReponse(.usb) == "sans réponse sous 3 s (pas de réémission)")
        #expect(Pont.texteSansReponse(.usb, commande: "json etat") == "sans réponse sous 3 s (pas de réémission)")
    }

    /// Creation de la cle par l'USB (ici le pont simule) : rangee dans le trousseau isole
    /// de la demo, jamais dans le vrai ; la cle ne traine nulle part.
    @Test func creerLaCleParLUSB() async throws {
        let demo = TrousseauPontsMemoire()
        let (pont, reel) = try Self.pont(cle: nil, trousseauPontsDemo: demo)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        #expect(pont.accesReseau == .sansCle(nom: Self.nomDemo))
        #expect(pont.repertoire == RepertoirePonts(), "le repertoire ne note jamais la demo")
        pont.creerCle()
        #expect(pont.creationCleEnCours)
        try #require(await attendre { !demo.lister().isEmpty })
        let connu = try #require(demo.lister().first)
        #expect(connu.nom == Self.nomDemo)
        let cle = try demo.lire(nom: connu.nom)
        #expect(H1.kid(cle: cle) == connu.empreinte)
        // Isolation de la demo : jamais dans le vrai trousseau, jamais dans pontsConnus.
        #expect(reel.lister().isEmpty, "le trousseau reel n'est jamais touche par la demo")
        #expect(pont.pontsConnus.isEmpty, "pontsConnus ne suit que le trousseau reel")
        // Ni la cle ni l'alea ne trainent : console, suivis, rejets.
        let hexa = H1.hexa(cle)
        func longHexa(_ s: String) -> Bool { s.contains(/[0-9A-Fa-f]{32,}/) }
        #expect(!pont.console.elements.contains { $0.texte.contains(hexa) || longHexa($0.texte) })
        #expect(pont.console.elements.contains { $0.texte.hasSuffix("json cle nouvelle ••••••••") }, "ligne envoyee masquee")
        #expect(!pont.suivis.contains { $0.fin?.cle != nil || longHexa($0.commande) })
        #expect(!pont.rejets.elements.contains { $0.brut.contains(hexa) })
        #expect(await attendre { pont.accesReseau == .cleConnue(nom: connu.nom, empreinte: connu.empreinte) })
        #expect(!pont.creationCleEnCours)
    }

    /// Une reconnexion ne laisse jamais une creation de cle perimee bloquer le prochain essai.
    @Test func laCreationDeCleReprendApresUneReconnexion() async throws {
        let demo = TrousseauPontsMemoire()
        let (pont, _) = try Self.pont(cle: nil, trousseauPontsDemo: demo)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        pont.creerCle()
        pont.deconnecter()
        pont.connecter(.demo)
        // La reconnexion a coupe l'ancien essai : signale, pas bloque en silence.
        #expect(pont.console.elements.contains { $0.genre == .note(grave: true) && $0.texte.contains("interrompue") })
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        pont.creerCle()
        try #require(await attendre { !demo.lister().isEmpty })
        #expect(demo.lister().first?.nom == Self.nomDemo)
    }

    /// Un suivi de creation termine sans reponse ne bloque pas un second essai.
    @Test func laCreationDeCleReprendApresUnSuiviTermineSansReponse() async throws {
        let demo = TrousseauPontsMemoire()
        let (pont, _) = try Self.pont(cle: nil, trousseauPontsDemo: demo)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        func demandes() -> Int {
            pont.console.elements.filter { $0.texte.contains("Nouvelle clé réseau demandée") }.count
        }
        pont.creerCle()
        #expect(demandes() == 1)
        pont.creerCle()
        #expect(demandes() == 1, "un essai en vol bloque le suivant")
        // Meme acteur, aucun `await` : la reponse simulee ne peut pas arriver avant.
        pont.avancerPourUnTest(de: 0.1)
        pont.avancerPourUnTest(de: 3.5)
        #expect(pont.console.elements.contains { $0.texte.contains("Pas encore de réponse à la création de clé") })
        pont.creerCle()
        #expect(demandes() == 2, "le suivi du premier essai est termine : un second essai part")
        try #require(await attendre { !demo.lister().isEmpty })
        #expect(demo.lister().first?.nom == Self.nomDemo)
    }

    /// En demo, le repertoire n'apprend rien et les vraies preferences ne bougent pas.
    @Test func laDemoNeNotePasLeRepertoire() async throws {
        let (pont, _) = try Self.pont(cle: nil)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.etat.srp != nil })
        #expect(pont.repertoire.parMac.isEmpty)
        #expect(pont.preferences.data(forKey: RepertoirePonts.cleReglages) == nil)
        #expect(pont.etat.ip?.valeur.adresseOmr == "fd12:34:5678:0:aaaa:bbbb:ccc:dddd")
    }

    /// Titres des sources reseau comme Halo Compagnon : "MODELE · MAC" quand le repertoire connait
    /// la carte ; sinon « Pont amaran » dans les listes et `<nom>.local` pour la source choisie.
    @Test func titreDeLaSourceReseau() throws {
        let autre = "9F8E7D6C5B4A3921"
        let (pont, trousseau) = try Self.pont()
        let inconnu = PontConnu(nom: Self.nom, empreinte: "?")
        #expect(pont.titre(pont: inconnu) == "Pont amaran")
        #expect(pont.titre(reseau: Self.nom) == "\(Self.nom).local")
        // Un second pont dans le trousseau ne change rien : pas de discriminant.
        try trousseau.ranger(nom: autre, cle: Self.cle, empreinte: H1.kid(cle: Self.cle))
        pont.relirePontsConnus()
        #expect(pont.titre(pont: PontConnu(nom: autre, empreinte: "?")) == "Pont amaran")
        // MAC connue du repertoire, modele pas encore appris : ESP32.
        pont.repertoire.noter(mac: "02000000DE01", serie: nil, srp: Self.nom)
        #expect(pont.titre(reseau: Self.nom) == "ESP32 · 02:00:00:00:DE:01")
        // Modele appris au hello : AMARAN, dans la liste comme pour la source choisie.
        pont.repertoire.noter(mac: "02000000DE01", serie: "AMARAN-02000000DE01", srp: Self.nom)
        #expect(pont.titre(reseau: Self.nom) == "AMARAN · 02:00:00:00:DE:01")
        #expect(pont.titre(pont: inconnu) == "AMARAN · 02:00:00:00:DE:01")
        #expect(pont.titre(reseau: autre) == "\(autre).local")
    }

    /// Changer de source dit ce qui est fait : la console garde ses lignes (comme Halo).
    @Test func changementDeSourceGardeLaConsole() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        #expect(await attendre { !pont.console.elements.isEmpty })
        let avant = pont.console.elements.count
        pont.connecter(.reseau(nom: Self.nom))
        let notes = pont.console.elements.filter { $0.texte.hasPrefix("Nouvelle source") }
        #expect(notes.last?.texte.contains("la console garde ses lignes") == true)
        #expect(notes.last?.texte.contains("console remis") == false)
        #expect(pont.console.elements.count >= avant, "aucune ligne de la source precedente n'est effacee")
    }

    /// « Oublier… » refuse par le trousseau (element cree par une autre signature, « Refuser »
    /// a l'invite) : la cle reste, la console dit l'erreur, rien n'est note comme oublie, et
    /// la session continue.
    @Test func oublierQuiEchoueNeDeconnectePas() async throws {
        let t = TrousseauPontsRefus()
        try t.ranger(nom: Self.nom, cle: Self.cle, empreinte: H1.kid(cle: Self.cle))
        let pont = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                        trousseauPonts: t, trousseauPontsDemo: TrousseauPontsMemoire(),
                        preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        pont.vitesseDemo = 20
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        pont.oublierPont(Self.nom)
        #expect(pont.pontsConnus.map(\.nom) == [Self.nom], "la cle est toujours la")
        #expect(pont.console.elements.contains { $0.genre == .note(grave: true) && $0.texte.hasPrefix("Clé du pont \(Self.nom).local non oubliée : Trousseau") })
        #expect(!pont.console.elements.contains { $0.texte.contains("oubliée par ce Mac") })
        #expect(pont.etatTransport == .ouvert && pont.phase == .connecte, "la session continue")
    }

    /// Relecture M1 : compteurs actives, blocs recus, puis la session tombe et se rouvre. Le
    /// `json 1` de la nouvelle session remet `compteurs_ms` a 0 : l'ancien bloc n'est plus
    /// releve. La carte et les graphiques disent « non releves » (avec l'heure du dernier
    /// releve), jamais les compteurs figes comme actuels ; l'IV Index vient de la memoire
    /// du pont. Activer de nouveau : « demandes », puis le premier bloc du releve.
    @Test func compteursFigesApresReconnexion() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        f.injecter(#"{"v":1,"t":"config","n":4,"ms":900210,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":2,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}"#)
        #expect(await attendre { pont.etat.mesh != nil })
        #expect(pont.etatCompteursMesh == .nonReleves)
        #expect(pont.texteCompteursMesh == "Compteurs du Mesh non relevés à distance", "rien de releve encore : pas d'heure")

        func activer(_ n: Int) async throws {
            pont.activerCompteursMesh()
            try #require(await attendre { f.envoyees.filter { $0.hasSuffix(" json compteurs 5000") }.count == n })
            let nc = try #require(f.numero(de: "json compteurs 5000"))
            f.injecter(#"{"v":1,"t":"reponse","n":5,"ms":905000,"id":\#(nc),"etape":"fin","cmd":"json compteurs 5000","ok":true,"code":"ok","duree_ms":1}"#)
            try #require(await attendre { pont.reglages?.compteursMs == 5000 })
        }
        try await activer(1)
        #expect(pont.etatCompteursMesh == .demandes)
        f.injecter(#"{"v":1,"t":"compteurs","n":6,"ms":905612,"bloc":"mesh","annonces":5120,"nid_reconnu":1630,"nid_inconnu":3402,"netmic_faux":0,"emis":64,"echecs_emission":0,"iv":3,"seq":1093,"plancher":1024}"#)
        #expect(await attendre { pont.etatCompteursMesh == .normal })
        #expect(pont.compteursMeshActuels?.annonces == 5120)
        #expect(pont.ivIndexMesh?.texte == "3")
        #expect(pont.texteCompteursMesh == nil)

        // La session tombe (chemin perdu, silence...) et se rouvre seule.
        f.fermer()
        try #require(await attendre { f.ouvertures == 2 && f.envoyees.filter { $0.contains(" json 1 ") }.count == 2 })
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte && pont.reglages?.compteursMs == 0 })
        #expect(pont.etat.compteurs?.valeur.annonces == 5120, "l'ancien bloc est toujours la...")
        #expect(pont.etatCompteursMesh == .nonReleves, "... mais il n'est plus releve")
        #expect(pont.compteursMeshActuels == nil, "la carte ne montre pas de compteurs figes")
        #expect(pont.texteCompteursMesh?.hasPrefix("Compteurs du Mesh non relevés à distance (dernier relevé à ") == true)
        #expect(pont.ivIndexMesh?.texte == "2 (mémoire du pont)", "l'IV Index des compteurs figes n'est plus montre")

        // De nouveau actives : demandes tant que le premier bloc du releve n'est pas la.
        try await activer(2)
        #expect(pont.etatCompteursMesh == .demandes, "l'ancien bloc ne vaut pas premier releve")
        #expect(pont.compteursMeshActuels == nil)
        f.injecter(#"{"v":1,"t":"compteurs","n":7,"ms":915612,"bloc":"mesh","annonces":6000,"nid_reconnu":1900,"nid_inconnu":4000,"netmic_faux":0,"emis":70,"echecs_emission":0,"iv":3,"seq":1200,"plancher":1024}"#)
        #expect(await attendre { pont.etatCompteursMesh == .normal })
        #expect(pont.compteursMeshActuels?.annonces == 6000)
    }

    /// Par l'USB (ici le pont simule), la console juge refus et confirmations sur la ligne
    /// decoupee comme le pont la decoupe : `re\xdemarre` est `redemarre`, et
    /// `js\xon cle nouvelle <alea>` ne part pas.
    @Test func consoleParLUSBJugeeCommeLePont() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        if case .confirmation = p.console(#"re\xdemarre"#) {} else { Issue.record("re\\xdemarre : confirmation attendue") }
        if case .confirmation = p.console(#"json c\xle efface"#) {} else { Issue.record("json c\\xle efface : confirmation attendue") }
        let avant = p.suivis.count
        guard case .refusee(let raison) = p.console(#"js\xon cle nouvelle "# + String(repeating: "AB", count: 32)) else {
            Issue.record("js\\xon cle nouvelle : refus attendu")
            return
        }
        #expect(raison.contains("Nouvelle clé"))
        #expect(p.suivis.count == avant, "rien n'est parti")
    }

    /// Cles du Mesh inventees, et les memes ecrites avec un `\x` tous les 4 hexa, que la
    /// console du pont oublie.
    static let k1 = "404142434445464748494A4B4C4D4E4F"
    static let k2 = "505152535455565758595A5B5C5D5E5F"
    static func echappee(_ k: String) -> String {
        stride(from: 0, to: k.count, by: 4).map { String(k.dropFirst($0).prefix(4)) }.joined(separator: #"\x"#)
    }

    /// Vrai si un morceau de 6 hexa d'une des deux cles se lit dans le texte, decoupe comme
    /// le pont le decoupe (echappements et guillemets retires).
    static func fuite(_ texte: String) -> Bool {
        let lu = LigneCommande.argv(texte, maxArguments: 10_000).joined().uppercased()
        return [k1, k2].contains { cle in
            let h = Array(cle)
            return (0...(h.count - 6)).contains { lu.contains(String(h[$0..<($0 + 6)])) }
        }
    }

    /// Reste du rapport : des cles tapees dans la console avec des echappements ou des
    /// guillemets que le pont retire n'apparaissent nulle part, par l'USB (ici le pont
    /// simule) : ni l'historique de saisie, ni la ligne envoyee du journal, ni le suivi.
    @Test func clesEcritesAutrementJamaisAffichees() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        for ligne in ["mesh cles \(Self.echappee(Self.k1)) \(Self.echappee(Self.k2))",
                      #"mesh cles "\#(Self.k1)" "\#(Self.echappee(Self.k2))""#] {
            // Historique de saisie : la vue n'y garde qu'une ligne que le masque laisse intacte.
            #expect(PolitiqueCommandes.masquerCle(ligne) != ligne, "\(ligne)")
            guard case .confirmation = p.console(ligne) else {
                Issue.record("mesh cles demande confirmation : \(ligne)")
                return
            }
            let avant = p.suivis.count
            #expect(p.console(ligne, confirme: true) == .envoyee)
            #expect(await attendre { p.suivis.count > avant })
        }
        // Les deux lignes parties (une seule en vol a la fois) et finies par le pont simule.
        #expect(await attendre { p.suivis.filter { $0.commande == "mesh cles •••••••• ••••••••" && $0.etat.estFinal }.count == 2 },
                "le suivi n'en garde que le masque")
        #expect(p.console.elements.filter { $0.texte.hasSuffix(" mesh cles •••••••• ••••••••") }.count == 2, "lignes envoyees masquees")
        #expect(!p.console.elements.contains { Self.fuite($0.texte) })
        #expect(!p.suivis.contains { Self.fuite($0.commande) })
    }

    /// A distance, la meme ligne est refusee par la liste blanche : la note qui la cite
    /// est masquee.
    @Test func clesEcritesAutrementCiteesMasquees() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        let ligne = #"mesh cles "\#(Self.echappee(Self.k1))" \#(Self.echappee(Self.k2))"#
        guard case .refusee = pont.console(ligne) else {
            Issue.record("mesh cles : USB seulement")
            return
        }
        #expect(pont.console.elements.last?.texte
                == "« mesh cles •••••••• •••••••• » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).")
        #expect(!pont.console.elements.contains { Self.fuite($0.texte) })
        #expect(!f.envoyees.contains { Self.fuite($0) }, "rien n'est parti")
    }

    /// `json trames 1` reconnu comme le pont le lit : le compte a rebours des 60 s part
    /// aussi pour une ligne avec guillemets ou echappements.
    @Test func demandeDeTramesLueCommeLePont() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.console(#"js\xon "trames" 1"#) == .envoyee)
        #expect(pont.tramesDemandeesLe != nil)
    }
}

/// Trousseau des ponts qui refuse toute suppression (`errSecAuthFailed`), comme un element
/// cree par une autre signature ; en memoire, isole du vrai.
final class TrousseauPontsRefus: TrousseauPonts {
    private let memoire = TrousseauPontsMemoire()

    func lister() -> [PontConnu] { memoire.lister() }
    func lire(nom: String) throws -> Data { try memoire.lire(nom: nom) }
    func ranger(nom: String, cle: Data, empreinte: String) throws { try memoire.ranger(nom: nom, cle: cle, empreinte: empreinte) }
    func oublier(nom: String) throws { throw ErreurTrousseauPonts.systeme(-25293) }
}
````

`apps/macos/AmaranCompagnonTests/TrousseauPontsTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5, TrousseauTests.swift) : trousseau des cles
// UDP des ponts (docs/PROTOCOLE-JSON.md 10.2). Nom SRP et cle inventes.
import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

@Suite("Trousseau des ponts (cles UDP)")
struct TrousseauPontsTests {
    static let nom = "1A2B3C4D5E6F7081"
    static let cle = Data((0..<32).map { 0x40 &+ UInt8($0) })

    static func exercer(_ t: any TrousseauPonts) throws {
        try? t.oublier(nom: nom)
        #expect(t.lister().isEmpty)
        #expect(throws: ErreurTrousseauPonts.absente(nom)) { try t.lire(nom: nom) }
        try t.ranger(nom: nom, cle: cle, empreinte: H1.kid(cle: cle))
        #expect(t.lister() == [PontConnu(nom: nom, empreinte: H1.kid(cle: cle))])
        #expect(try t.lire(nom: nom) == cle)
        // Nouvelle cle pour le meme pont : remplacee, pas doublee.
        let autre = Data(repeating: 0x5A, count: 32)
        try t.ranger(nom: nom, cle: autre, empreinte: H1.kid(cle: autre))
        #expect(t.lister().count == 1)
        #expect(t.lister().first?.empreinte == H1.kid(cle: autre))
        #expect(try t.lire(nom: nom) == autre)
        try t.oublier(nom: nom)
        #expect(t.lister().isEmpty)
        try t.oublier(nom: nom)  // deja oublie : sans erreur
    }

    @Test func enMemoire() throws {
        try Self.exercer(TrousseauPontsMemoire())
    }

    /// Le trousseau des ponts et celui des cles Mesh sont deux elements distincts.
    @Test func distinctDuTrousseauMesh() {
        #expect(TrousseauPontsSysteme().service == "fr.djoko.amaran.pont")
        #expect(TrousseauSysteme().service == "fr.djoko.amaran.reseau")
    }

    /// Vrai trousseau (service de test, nettoye) : seulement sur demande,
    /// `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild ... test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMARAN_TEST_TROUSSEAU"] == "1"))
    func trousseauDuMac() throws {
        try Self.exercer(TrousseauPontsSysteme(service: "fr.djoko.amaran.pont.tests"))
    }

    @Test func pontConnu() {
        #expect(PontConnu(nom: Self.nom, empreinte: "CA2A4FE7").hote == "1A2B3C4D5E6F7081.local")
    }

    /// Le texte d'une cle absente ne cite que le nom SRP.
    @Test func texteDeLaCleAbsente() {
        let t = ErreurTrousseauPonts.absente(Self.nom).description
        #expect(t.contains("1A2B3C4D5E6F7081.local"))
        #expect(t.contains("Activer l'accès réseau"))
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `TEST FAILED` : `type 'CompteursMesh' has no member 'etat'`, `cannot find 'TrousseauPontsMemoire' in scope`, `type 'SimulateurDemo' has no member 'srpDemo'`…

- [ ] **Step 3 : le code.**

`apps/macos/AmaranCompagnon/AmaranCompagnon.entitlements`, bloc 1 sur 1. Remplacer :

````xml
	<key>com.apple.security.files.bookmarks.app-scope</key>
	<true/>
</dict>
</plist>
````

par :

````xml
	<key>com.apple.security.files.bookmarks.app-scope</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
````

`apps/macos/AmaranCompagnon/AmaranCompagnonApp.swift`, bloc 1 sur 1. Remplacer :

````swift
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                    preferences: UserDefaults(suiteName: suite)!)
    }
````

par :

````swift
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                    trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                    preferences: UserDefaults(suiteName: suite)!)
    }
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 1 sur 13. Remplacer :

````swift
// en bout.
import AmaranProtocole
import Foundation

````

par :

````swift
// en bout.
import AmaranProtocole
import CryptoKit
import Foundation

````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 2 sur 13. Remplacer :

````swift

    var empreintes: (reseau: String, application: String)?
    var lampes: [Lampe]
    var releveMs = 2000
````

par :

````swift

    var empreintes: (reseau: String, application: String)?
    /// Empreinte de la cle UDP (10.2) ; nil : pas de cle, port 5480 ferme. La cle
    /// elle-meme n'est jamais gardee par le simulateur : seule l'app la range.
    var empreinteUdp: String?
    var lampes: [Lampe]
    var releveMs = 2000
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 3 sur 13. Remplacer :

````swift
    private var dernierRx: TimeInterval = 0
    private var log = false
    private var periodes = (etat: 1000, lampes: 10000, compteurs: 1000, reseau: 5000)
    private var prochains = (etat: 0.0, lampes: 0.0, compteurs: 0.0, reseau: 0.0, regard: 0.0)
````

par :

````swift
    private var dernierRx: TimeInterval = 0
    private var log = false
    private var trames = false
    /// Prochaine demande d'etat au groupe des lampes (trames `json trames 1`), en secondes simulees.
    private var prochaineDemande = 0.0
    private var periodes = (etat: 1000, lampes: 10000, compteurs: 1000, reseau: 5000)
    private var prochains = (etat: 0.0, lampes: 0.0, compteurs: 0.0, reseau: 0.0, regard: 0.0)
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 4 sur 13. Remplacer :

````swift
                         msg: String? = nil, extra: [(String, J)] = []) {
        guard let id else { return }
        var c: [(String, J)] = [("id", .i(id)), ("etape", .s(debut ? "debut" : "fin")),
                                ("cmd", .s(PolitiqueCommandes.masquerCle(cmd) == cmd ? String(cmd.prefix(40)) : "mesh cles")),
                                ("ok", .b(ok)), ("code", .s(debut ? "en_cours" : code))]
        if let msg { c.append(("msg", .s(msg))) }
````

par :

````swift
                         msg: String? = nil, extra: [(String, J)] = []) {
        guard let id else { return }
        // Comme le pont : `cmd` ne cite jamais une cle (mesh cles) ni l'alea (json cle nouvelle).
        let m = LigneCommande.mots(cmd)
        let vue = m.starts(with: ["json", "cle", "nouvelle"]) ? "json cle nouvelle"
            : PolitiqueCommandes.masquerCle(cmd) == cmd ? String(cmd.prefix(40)) : "mesh cles"
        var c: [(String, J)] = [("id", .i(id)), ("etape", .s(debut ? "debut" : "fin")),
                                ("cmd", .s(vue)),
                                ("ok", .b(ok)), ("code", .s(debut ? "en_cours" : code))]
        if let msg { c.append(("msg", .s(msg))) }
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 5 sur 13. Remplacer :

````swift
    private func hello() {
        ligne("hello", bloc: "base", [
            ("rev", .i(0)), ("fw", .s("0.1.0-demo")), ("date", .s("Oct  5 2026")), ("heure", .s("14:02:11")),
            ("idf", .s("v5.5.4")), ("puce", .s("esp32c6")), ("boot", .s(boot)), ("reset", .s("logiciel")),
            ("reset_n", .i(3)), ("up_s", .i(Int(ms / 1000))),
            ("session", .o([("periode_ms", .i(periodes.etat)), ("lampes_ms", .i(periodes.lampes)),
                            ("compteurs_ms", .i(periodes.compteurs)), ("reseau_ms", .i(periodes.reseau)),
                            ("bail_s", .i(bailS)), ("log", .b(log))])),
            ("limites", .o([("ligne_max", .i(1024)), ("cmd_max", .i(127))])),
        ])
````

par :

````swift
    private func hello() {
        ligne("hello", bloc: "base", [
            ("rev", .i(1)), ("fw", .s("0.1.0-demo")), ("date", .s("Oct  5 2026")), ("heure", .s("14:02:11")),
            ("idf", .s("v5.5.4")), ("puce", .s("esp32c6")), ("boot", .s(boot)), ("reset", .s("logiciel")),
            ("reset_n", .i(3)), ("up_s", .i(Int(ms / 1000))),
            ("session", .o([("transport", .s("usb")), ("periode_ms", .i(periodes.etat)), ("lampes_ms", .i(periodes.lampes)),
                            ("compteurs_ms", .i(periodes.compteurs)), ("reseau_ms", .i(periodes.reseau)),
                            ("bail_s", .i(bailS)), ("log", .b(log)), ("trames", .b(trames))])),
            ("limites", .o([("ligne_max", .i(1024)), ("cmd_max", .i(127))])),
        ])
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 6 sur 13. Remplacer :

````swift
            ("id", .o([("fabricant", .s("TEST_VENDOR")), ("produit", .s("TEST_PRODUCT")),
                       ("serie", .s("AMARAN-02000000DE00")), ("nom", .s("Pont amaran"))])),
            ("caps", .a(["matter", "thread", "mesh", "catalogue", "ordres", "led", "log"].map { .s($0) })),
        ])
        ligne("config", bloc: "catalogue", [
````

par :

````swift
            ("id", .o([("fabricant", .s("TEST_VENDOR")), ("produit", .s("TEST_PRODUCT")),
                       ("serie", .s("AMARAN-02000000DE00")), ("nom", .s("Pont amaran"))])),
            ("caps", .a(["matter", "thread", "mesh", "catalogue", "ordres", "led", "log", "trames", "udp", "cle", "texte"]
                .map { .s($0) })),
        ])
        ligne("config", bloc: "catalogue", [
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 7 sur 13. Remplacer :

````swift
        ])
        ligne("reseau", bloc: "thread", [("role", .s("child")), ("attache", .b(true))])
    }

    private func instantane() {
````

par :

````swift
        ])
        ligne("reseau", bloc: "thread", [("role", .s("child")), ("attache", .b(true))])
        let e = memoire.empreinteUdp
        ligne("reseau", bloc: "ip", [
            ("srp", .s(Self.srpDemo)),
            ("adresses", .a([.o([("type", .s("omr")), ("adresse", .s("fd12:34:5678:0:aaaa:bbbb:ccc:dddd"))]),
                             .o([("type", .s("ml_eid")), ("adresse", .s("fd12:34:5678:1:1111:2222:3333:4444"))])])),
            ("udp", .o([("port", .i(5480)), ("cle", .b(e != nil)), ("empreinte", .s(e)), ("ouvert", .b(e != nil)),
                        ("sessions", .i(0)), ("recus", .i(0)), ("emis", .i(0)), ("rejets", .i(0)), ("perdus", .i(0))])),
        ])
    }

    /// Nom SRP du pont simule : jamais 16 hexa, pour ne jamais se confondre avec un vrai
    /// pont (le trousseau de la demo est isole, mais un nom distinct le dit aussi).
    static let srpDemo = "DEMO-AMARAN"

    // MARK: - Trames (7.6)

    /// Une ligne `trame`, seulement avec `json trames 1` (le pont simule suit l'USB : pas de
    /// coupure a 60 s). `lampe` nil : le groupe des lampes.
    private func trame(_ sens: String, _ quoi: String, lampe: Int?, marche: Bool? = nil, intensite: Int? = nil,
                       essai: Int? = nil) {
        guard machine, trames, !ferme else { return }
        var c: [(String, J)] = [("sens", .s(sens)), ("quoi", .s(quoi)), ("lampe", lampe.map(J.i) ?? .s(nil)),
                                ("marche", marche.map(J.b) ?? .s(nil)), ("intensite", intensite.map(J.i) ?? .s(nil))]
        if let essai { c.append(("essai", .i(essai))) }
        c.append(("sautes", .i(0)))
        ligne("trame", c)
    }

    /// Demande d'etat au groupe, puis l'etat que chaque lampe entendue renvoie (`seulement`
    /// : une seule lampe, pour `lampe <n> releve`).
    private func demandeEtDonnees(seulement k: Int? = nil) {
        trame("tx", "demande", lampe: nil)
        for i in lampes.indices where lampes[i].entendue && (k == nil || k == i + 1) {
            trame("rx", "etat", lampe: i + 1, marche: lampes[i].marche, intensite: lampes[i].intensite)
        }
    }

    /// Reemission d'un ordre (essais 2 et 3) tant que la lampe ne repond pas.
    private func renvoyerOrdre(_ k: Int, marche: Bool?, intensite: Int?, essai: Int) {
        guard lampes[k - 1].consigne != nil else { return }
        trame("tx", "ordre", lampe: k, marche: marche, intensite: intensite, essai: essai)
    }


    private func instantane() {
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 8 sur 13. Remplacer :

````swift
            for i in lampes.indices where montrees.count > i && montrees[i] != resume(i) { etatLampe(i) }
            prochains.regard = now + 0.1
        }
        if periodes.compteurs > 0, now >= prochains.compteurs {
````

par :

````swift
            for i in lampes.indices where montrees.count > i && montrees[i] != resume(i) { etatLampe(i) }
            prochains.regard = now + 0.1
        }
        if trames, now >= prochaineDemande {
            demandeEtDonnees()
            prochaineDemande = now + Double(memoire.releveMs) / 1000
        }
        if periodes.compteurs > 0, now >= prochains.compteurs {
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 9 sur 13. Remplacer :

````swift
            periodes = (1000, 10000, 1000, 5000)
            log = false
            let now = t
            prochains = (now + 1, now + 10, now + 1, now + 5, now)
````

par :

````swift
            periodes = (1000, 10000, 1000, 5000)
            log = false
            trames = false
            let now = t
            prochains = (now + 1, now + 10, now + 1, now + 5, now)
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 10 sur 13. Remplacer :

````swift
            log = m.count == 3 && m[2] == "1"
            reponse(id, l)
        default:
            reponse(id, l, ok: false, code: "usage", msg: "json [1|0|etat|hello|ping|...]")
        }
    }
````

par :

````swift
            log = m.count == 3 && m[2] == "1"
            reponse(id, l)
        case "trames" where m.count == 3 && (m[2] == "0" || m[2] == "1"):
            trames = m[2] == "1"
            prochaineDemande = t + 1
            reponse(id, l)
        case "cle":
            commandeCle(id, l, m)
        default:
            reponse(id, l, ok: false, code: "usage", msg: "json [1|0|etat|hello|ping|...]")
        }
    }

    /// `json cle nouvelle <64 hexa>` et `json cle efface` (10.2), comme le firmware : la
    /// cle vaut HMAC-SHA256(alea de l'app, alea du pont), rendue une seule fois.
    private func commandeCle(_ id: Int?, _ l: String, _ m: [String]) {
        if m.count == 4, m[2] == "nouvelle", let alea = H1.octets(hexa: m[3].uppercased()), alea.count == 32 {
            let cle = Data(HMAC<SHA256>.authenticationCode(for: H1.aleatoire(32), using: SymmetricKey(data: alea)))
            let empreinte = H1.kid(cle: cle)
            memoire.empreinteUdp = empreinte
            sauver(memoire)
            if id == nil { texte("ok cle UDP \(empreinte), port 5480 ouvert") }
            reponse(id, l, extra: [("cle", .s(H1.hexa(cle))), ("empreinte", .s(empreinte))])
        } else if m.count == 3, m[2] == "efface" {
            memoire.empreinteUdp = nil
            sauver(memoire)
            if id == nil { texte("ok cle UDP effacee, port 5480 ferme") }
            reponse(id, l)
        } else {
            reponse(id, l, ok: false, code: "usage", msg: "json cle nouvelle <64 hexa> | json cle efface")
        }
    }
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 11 sur 13. Remplacer :

````swift
            reponse(id, l, debut: true)
            texte("ok demande d'etat a la lampe \(k)")
            return reponse(id, l)
        }
````

par :

````swift
            reponse(id, l, debut: true)
            texte("ok demande d'etat a la lampe \(k)")
            demandeEtDonnees(seulement: k)
            return reponse(id, l)
        }
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 12 sur 13. Remplacer :

````swift
        lampes[i].consigne = (marche, intensite)
        let attente = Int((lampes[i].entendue ? 430 : 3700) / vitesse)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(attente))
            await self?.finirConsigne(i, marche: marche, intensite: intensite)
        }
    }
````

par :

````swift
        lampes[i].consigne = (marche, intensite)
        let attente = Int((lampes[i].entendue ? 430 : 3700) / vitesse)
        trame("tx", "ordre", lampe: k, marche: marche, intensite: intensite, essai: 1)
        // Copies : les taches ci-dessous ne capturent pas les `var` de la fonction.
        let (voulueMarche, voulueIntensite) = (marche, intensite)
        if !lampes[i].entendue {
            // Sans reponse : le pont renvoie l'ordre aux essais 2 et 3 avant d'abandonner.
            Task { [weak self] in
                for essai in 2...3 {
                    try? await Task.sleep(for: .milliseconds(attente / 3))
                    await self?.renvoyerOrdre(k, marche: voulueMarche, intensite: voulueIntensite, essai: essai)
                }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(attente))
            await self?.finirConsigne(i, marche: voulueMarche, intensite: voulueIntensite)
        }
    }
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift`, bloc 13 sur 13. Remplacer :

````swift
            if let intensite { lampes[i].intensite = intensite }
            lampes[i].consigne = nil
            ordres.confirmes += 1
            ordres.delai += 430
````

par :

````swift
            if let intensite { lampes[i].intensite = intensite }
            lampes[i].consigne = nil
            trame("tx", "demande", lampe: nil)
            trame("rx", "etat", lampe: i + 1, marche: lampes[i].marche, intensite: lampes[i].intensite)
            ordres.confirmes += 1
            ordres.delai += 430
````

`apps/macos/AmaranCompagnon/Modele/CompteursMesh.swift` (contenu complet) :

````swift
// Carte « Bluetooth Mesh » du tableau de bord et ecran Graphiques, source reseau : le
// profil d'une session distante coupe les compteurs (`json compteurs 0`, docs/PROTOCOLE-JSON.md
// 10.5), donc IV Index, annonces, NetMIC faux et emis / refus n'arrivent pas, et un bloc
// recu avant (session precedente) garde des valeurs figees. Logique pure : ce que les deux
// ecrans disent, et d'ou vient l'IV Index.
import AmaranProtocole
import Foundation

enum CompteursMesh {
    /// Etat des compteurs du Mesh pour la carte et les graphiques.
    enum Etat: Equatable {
        /// Rien a dire : par l'USB, ou les compteurs du releve en cours arrivent.
        case normal
        /// A distance, periode a 0 (profil d'une session distante, `json compteurs 0`) :
        /// le pont ne les envoie pas. Un bloc d'avant (session precedente) n'est plus releve :
        /// ses valeurs ne sont jamais montrees comme actuelles. Les ecrans proposent de les
        /// activer.
        case nonReleves
        /// A distance, periode demandee, premier bloc du releve pas encore arrive.
        case demandes
    }

    /// Periode proposee par « Activer » (`json compteurs 5000` : le plus court permis a distance).
    static let periodeProposeeMs = 5000

    /// `enDirect` : un bloc est arrive depuis que la periode est non nulle (`Pont.compteursEnDirect`).
    static func etat(aDistance: Bool, enDirect: Bool, periodeMs: Int?) -> Etat {
        guard aDistance else { return .normal }
        guard let p = periodeMs, p > 0 else { return .nonReleves }
        return enDirect ? .normal : .demandes
    }

    /// La phrase commune a la carte « Bluetooth Mesh » et a l'ecran Graphiques ; nil :
    /// rien a dire. `dernierReleve` : date du dernier bloc recu (une session precedente).
    static func texte(_ e: Etat, dernierReleve: Date?) -> String? {
        switch e {
        case .normal:
            return nil
        case .nonReleves:
            let heure = dernierReleve.map { " (dernier relevé à \($0.formatted(date: .omitted, time: .standard)))" } ?? ""
            return "Compteurs du Mesh non relevés à distance\(heure)"
        case .demandes:
            return "Compteurs du Mesh demandés, en attente du premier relevé"
        }
    }

    /// IV Index montre par la carte : celui des compteurs du releve en cours ; sans eux,
    /// celui que le pont garde en NVS (`config` `mesh` `iv_nvs`), et la carte le dit.
    static func ivIndex(compteurs: Int?, ivNvs: Int?) -> (texte: String, deNvs: Bool)? {
        if let compteurs { return (String(compteurs), false) }
        if let ivNvs { return ("\(ivNvs) (mémoire du pont)", true) }
        return nil
    }
}

extension Pont {
    var etatCompteursMesh: CompteursMesh.Etat {
        CompteursMesh.etat(aDistance: aDistance, enDirect: compteursEnDirect, periodeMs: reglages?.compteursMs)
    }

    /// Bloc `compteurs` que les ecrans peuvent montrer comme actuel : par l'USB, le dernier ;
    /// a distance, seulement celui du releve en cours (nil sinon : lignes « – »).
    var compteursMeshActuels: AmaranProtocole.CompteursMesh? {
        etatCompteursMesh == .normal ? etat.compteurs?.valeur : nil
    }

    /// Phrase de la carte et des graphiques (nil : rien a dire).
    var texteCompteursMesh: String? {
        CompteursMesh.texte(etatCompteursMesh, dernierReleve: etat.compteurs?.date)
    }

    var ivIndexMesh: (texte: String, deNvs: Bool)? {
        CompteursMesh.ivIndex(compteurs: compteursMeshActuels?.iv, ivNvs: etat.mesh?.valeur.ivNvs)
    }

    /// « Activer » : `json compteurs 5000`, permis a distance (10.5).
    func activerCompteursMesh() {
        reglerCadence(.compteurs, ms: CompteursMesh.periodeProposeeMs)
    }
}
````

`apps/macos/AmaranCompagnon/Modele/CourbesRedemarrages.swift` (contenu complet) :

````swift
// Repere des graphiques : les dates ou le pont a redemarre (nouveau `boot`, donc nouveau
// segment des series). Code pur, sans vue.
import AmaranProtocole
import Foundation

extension SeriesCourbes {
    /// Dates des changements de segment : le tas est publie a chaque periode, c'est la
    /// serie la plus fournie.
    var redemarrages: [Date] {
        var sortie: [Date] = []
        var precedent: Int?
        for p in tas {
            if let q = precedent, q != p.segment { sortie.append(p.date) }
            precedent = p.segment
        }
        return sortie
    }
}
````

`apps/macos/AmaranCompagnon/Modele/FiltreTrames.swift` (contenu complet) :

````swift
// Filtres de l'ecran « Trames » (spec 3b, section 8) : sens, lampe, nature du message.
// Code pur, sans vue : les tests le jugent directement.
import AmaranProtocole
import Foundation

struct FiltreTrames: Equatable, Sendable {
    /// Lampe visee par une trame : une lampe, le groupe (demande d'etat), ou toutes.
    enum Cible: Hashable, Sendable {
        case toutes
        case groupe
        case lampe(Int)
    }

    /// nil : les deux sens.
    var sens: SensTrame?
    var cible: Cible = .toutes
    /// Natures montrees. Une nature que l'app ne connait pas (`inconnu`, absente) n'est
    /// jamais cachee : une trace qu'on ne comprend pas ne se filtre pas en silence.
    var quoi: Set<QuoiTrame> = [.ordre, .demande, .etat]

    func garde(_ t: Trame) -> Bool {
        if let sens, t.sens != sens { return false }
        switch cible {
        case .toutes: break
        case .groupe: if t.lampe != nil { return false }
        case .lampe(let n): if t.lampe != n { return false }
        }
        if let q = t.quoi, q != .inconnu, !quoi.contains(q) { return false }
        return true
    }

    /// Les trames gardees, de la plus recente a la plus ancienne.
    func appliquer(_ source: [TrameRecue]) -> [TrameRecue] {
        source.reversed().filter { garde($0.trame) }
    }

    /// « 1 · Lampe bureau », ou « Groupe » pour la demande d'etat.
    static func libelleCible(_ t: Trame, noms: [Int: String]) -> String {
        guard let n = t.lampe else { return "Groupe" }
        return noms[n].map { "\(n) · \($0)" } ?? "\(n)"
    }

    /// Aucun filtre : tout est montre.
    var estNeutre: Bool { self == FiltreTrames() }
}

extension SensTrame {
    var libelle: String {
        switch self {
        case .tx: "Émise"
        case .rx: "Reçue"
        case .inconnu: "?"
        }
    }

    var fleche: String {
        switch self {
        case .tx: "→"
        case .rx: "←"
        case .inconnu: "?"
        }
    }
}

extension QuoiTrame {
    var libelle: String {
        switch self {
        case .ordre: "Ordre"
        case .demande: "Demande d'état"
        case .etat: "État"
        case .inconnu: "Inconnu"
        }
    }
}
````

`apps/macos/AmaranCompagnon/Modele/Journal.swift`, bloc 1 sur 2. Remplacer :

````swift
// Repris de Halo Compagnon (commit e114cd5) : la console et les rejets (les trames et
// les courbes viendront au plan 3b-2).
import AmaranProtocole
import Foundation
````

par :

````swift
// Repris de Halo Compagnon (commit e114cd5) : la console, les rejets et le journal des
// trames Bluetooth Mesh (les courbes sont dans AmaranProtocole, SeriesCourbes).
import AmaranProtocole
import Foundation
````

`apps/macos/AmaranCompagnon/Modele/Journal.swift`, bloc 2 sur 2. Remplacer :

````swift
}

/// Tableau borne : les plus anciens sortent.
struct Borne<Element> {
````

par :

````swift
}

/// Trame Bluetooth Mesh decodee par le pont (`trame`, 7.6), avec sa date (ancre du `hello`).
struct TrameRecue: Identifiable, Sendable, Equatable {
    let id: Int
    let date: Date
    let trame: Trame
}

/// Tableau borne : les plus anciens sortent.
struct Borne<Element> {
````

`apps/macos/AmaranCompagnon/Modele/Pont+Reseau.swift` (contenu complet) :

````swift
// Acces reseau du pont (docs/PROTOCOLE-JSON.md 10), repris de Halo Compagnon (commit
// e114cd5, Modele/Pont.swift) : cle UDP creee par l'USB et rangee dans le trousseau des
// ponts, etat de l'acces, oubli d'un pont, repertoire et titres des sources reseau. La
// cle n'est jamais affichee ni journalisee : seule son empreinte l'est.
import AmaranProtocole
import Foundation

extension Pont {
    // MARK: - Repertoire et titres

    /// Titre de la source reseau choisie (comme Halo Compagnon) : celui de la carte,
    /// "AMARAN · F0:F5:BD:0A:0B:0C", si le repertoire connait sa MAC ; sinon `<nom>.local`.
    func titre(reseau nom: String) -> String {
        repertoire.mac(pourSrp: nom).map { repertoire.titre(mac: $0) } ?? "\(nom).local"
    }

    /// Titre d'un pont du trousseau dans les listes : celui de sa carte si le repertoire la
    /// connait (vue au moins une fois, par l'USB ou le reseau), sinon « Pont amaran ».
    func titre(pont p: PontConnu) -> String {
        guard let mac = repertoire.mac(pourSrp: p.nom) else { return "Pont amaran" }
        return repertoire.titre(mac: mac)
    }

    /// Identite et bloc `ip` d'un vrai pont (jamais la demo) : le repertoire apprend son
    /// modele et son nom SRP, et les preferences le gardent.
    func noterRepertoire() {
        guard genreTransport == .usb || genreTransport == .udp else { return }
        guard repertoire.noter(etat) else { return }
        if let d = repertoire.donnees { preferences.set(d, forKey: RepertoirePonts.cleReglages) }
    }

    // MARK: - Acces reseau

    /// Acces reseau (bloc `ip` du pont) : par l'USB ou la demo seulement. En demo,
    /// l'empreinte vient du trousseau isole de la demo, jamais du vrai.
    var accesReseau: EtatAccesReseau {
        guard genreTransport == .usb || genreTransport == .demo else { return .inconnu }
        let connus = genreTransport == .demo ? trousseauPontsDemo.lister() : pontsConnus
        return EtatAccesReseau.depuis(ip: etat.ip?.valeur) { nom in connus.first { $0.nom == nom }?.empreinte }
    }

    /// Ce que dit la section « Pont branche en USB » quand la cle ne peut pas s'y gerer
    /// (acces `.inconnu`) : pas de pont connecte par l'USB, ou un pont connecte qui n'a pas
    /// encore de nom SRP (la cle se range sous ce nom, `creerCle`).
    var texteSansAccesReseau: String {
        Self.texteSansAccesReseau(parUSB: (genreTransport == .usb || genreTransport == .demo) && peutCommander,
                                  udpAnnonce: etat.identite == nil || etat.a(.udp),
                                  ipRecu: etat.ip?.valeur.udp != nil, srpConnu: !(etat.srp ?? "").isEmpty)
    }

    static func texteSansAccesReseau(parUSB: Bool, udpAnnonce: Bool, ipRecu: Bool, srpConnu: Bool) -> String {
        guard parUSB else {
            return "Brancher le pont en USB et le connecter (menu Source) pour créer ou renouveler sa clé."
        }
        guard udpAnnonce else {
            return "Ce firmware du pont n'a pas d'accès par Thread (capacité udp absente)."
        }
        guard ipRecu else {
            return "Pont connecté par l'USB : son accès par Thread n'est pas encore connu (bloc ip attendu)."
        }
        guard srpConnu else {
            return "Pont connecté par l'USB, nom SRP inconnu : le pont doit d'abord rejoindre le réseau Thread (être dans Maison) ; sa clé se range sous ce nom."
        }
        return "Brancher le pont en USB et le connecter (menu Source) pour créer ou renouveler sa clé."
    }

    /// Une creation de cle est en file ou en vol.
    var creationCleEnCours: Bool {
        guard let c = creationCle, let s = moteur.correlateur.suivi(c.id) else { return false }
        return !s.etat.estFinal
    }

    /// « Activer l'acces reseau » et « Nouvelle cle… » : alea de l'app, cle calculee par
    /// le pont et rendue une fois, rangee dans le trousseau des ponts sous le nom SRP du
    /// bloc `ip` ; les sessions reseau en cours tombent (10.2). Par l'USB seulement, et
    /// avec un acces reseau connu (nom SRP et bloc `udp`) : jamais de cle rangee sous un
    /// compte vide. Bloque seulement si un essai est encore en file ou en vol.
    func creerCle() {
        guard !creationCleEnCours else { return }
        guard !aDistance, accesReseau != .inconnu, let nom = etat.srp, !nom.isEmpty else { return }
        // La ligne porte l'alea : secrete (jamais gardee dans un suivi, jamais renvoyee),
        // et masquee dans la console par `masquerCle`.
        guard let id = envoyer(CleReseau.commande(alea: CleReseau.alea()), secret: true) else { return }
        creationCle = (id, nom)
        note("Nouvelle clé réseau demandée au pont : les sessions réseau en cours tombent.")
    }

    /// La reponse `fin` a la creation de cle en cours, telle que recue (avec sa cle), et
    /// le nom SRP sous lequel la ranger ; nil pour toute autre ligne. `creationCle` est
    /// desarme ici : la reponse ne sert qu'une fois.
    func reponseACreationCle(_ element: ElementRecu) -> (Reponse, String)? {
        guard let c = creationCle, case .machine(let l) = element, case .reponse(let r) = l.message,
              r.etape == .fin, r.code != .dejaTraite, moteur.correlateur.suivi(numero: r.id)?.id == c.id else { return nil }
        creationCle = nil
        return (r, c.nom)
    }

    /// Verifie la cle rendue et la range. En mode demo, dans le trousseau isole de la
    /// demo : elle n'ecrase jamais celle d'un vrai pont.
    func terminerCreationCle(_ r: Reponse, nom: String) {
        switch CleReseau.verifier(r) {
        case .success(var c):
            defer { c.cle.resetBytes(in: 0..<c.cle.count) }
            do {
                if genreTransport == .demo {
                    try trousseauPontsDemo.ranger(nom: nom, cle: c.cle, empreinte: c.empreinte)
                    // Le pont simule n'a pas de source reseau : rien a joindre par Thread.
                    note("Clé réseau rangée dans le trousseau de la démo (empreinte \(c.empreinte)), à part du vrai : le pont simulé ne se joint pas par le réseau Thread.")
                } else {
                    try trousseauPonts.ranger(nom: nom, cle: c.cle, empreinte: c.empreinte)
                    pontsConnus = trousseauPonts.lister()
                    note("Clé réseau rangée dans le trousseau (empreinte \(c.empreinte)) : le pont est joignable par le réseau Thread.")
                }
                // Le bloc `ip` suit (json etat le renvoie) : l'acces passe a « cle connue ».
                rafraichir()
            } catch {
                // Le pont a deja adopte la nouvelle cle : le Mac doit recommencer.
                note("Le pont a déjà changé de clé, mais le Mac n'a pas pu la ranger (\(String(describing: error))) : relancer « Nouvelle clé… ».",
                     grave: true)
            }
        case .failure(let e):
            note(e.description, grave: true)
        }
    }

    /// La connexion ne portera plus la reponse d'une creation de cle (transport ferme,
    /// source changee) : le dire plutot que de bloquer un nouvel essai en silence.
    func interrompreCreationCle() {
        guard creationCle != nil else { return }
        creationCle = nil
        note("Création de clé interrompue : si le pont a changé de clé, l'accès réseau affichera « clé inconnue de ce Mac » ; recommencer.",
             grave: true)
    }

    /// « Oublier… » : retire la cle d'un pont du trousseau de ce Mac (le pont garde la
    /// sienne). La source en cours, si c'est ce pont, est deconnectee. Seulement si la
    /// suppression a reussi : sinon la cle reste, la console dit l'erreur, et la session
    /// continue.
    func oublierPont(_ nom: String) {
        do {
            try trousseauPonts.oublier(nom: nom)
        } catch {
            pontsConnus = trousseauPonts.lister()
            note("Clé du pont \(nom).local non oubliée : \(String(describing: error))", grave: true)
            return
        }
        pontsConnus = trousseauPonts.lister()
        note("Clé du pont \(nom).local oubliée par ce Mac (le pont garde la sienne).")
        if source == .reseau(nom: nom) { deconnecter() }
    }

    /// Relit la liste des ponts connus (trousseau modifie hors de l'app).
    func relirePontsConnus() {
        pontsConnus = trousseauPonts.lister()
    }
}
````

`apps/macos/AmaranCompagnon/Modele/Pont.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : sources (USB, demo, reseau Thread),
// reconnexion, session, console, trames et courbes. Les gestes des lampes, des cles
// Mesh et de l'acces reseau sont dans Pont+Lampes.swift, Pont+Cles.swift et
// Pont+Reseau.swift.
import AmaranProtocole
import AppKit
import Foundation
import Network
import Observation

/// Modele central de l'app : un transport, le recepteur, le moteur de session et tout
/// ce que les ecrans affichent. Tout se passe sur l'acteur principal ; la couche
/// protocole (AmaranProtocole) est du code pur appele d'ici.
@MainActor
@Observable
final class Pont {
    enum Source: Hashable, Sendable {
        case serie(chemin: String, serie: String?)
        case demo
        /// Pont joint par le reseau Thread (docs/PROTOCOLE-JSON.md 10) : son nom SRP, sans `.local`.
        case reseau(nom: String)

        var estDemo: Bool { self == .demo }
        var estReseau: Bool { if case .reseau = self { true } else { false } }
    }

    enum EtatTransport: Equatable, Sendable {
        case ferme
        case ouverture
        case ouvert
        /// Reouverture programmee (re-enumeration USB, silence...).
        case attente(prochain: Date, raison: String)
        /// "Liberer le port" : rien ne se rouvre avant un clic.
        case libere
        case erreur(String)
    }

    enum ResultatConsole: Equatable {
        case envoyee
        case confirmation(String)
        case refusee(String)
    }

    // MARK: Etat publie

    private(set) var source: Source?
    private(set) var ports: [PortUSB] = []
    private(set) var etatTransport: EtatTransport = .ferme
    /// Nom du transport ouvert (chemin du port, demo).
    private(set) var nomTransport = ""
    private(set) var phase: MoteurSession.Phase = .ferme
    private(set) var etat = EtatPont()
    private(set) var reception = CompteursReception()
    private(set) var statistiques = StatistiquesLien()
    private(set) var suivis: [SuiviCommande] = []
    private(set) var console = Borne<LigneConsole>(capacite: 4000)
    private(set) var rejets = Borne<Rejet>(capacite: 100)
    /// Trafic Bluetooth Mesh decode (`json trames 1`, 7.6).
    private(set) var trames = Borne<TrameRecue>(capacite: 5000)
    /// Dernier `json trames 1` envoye : a distance, le pont coupe le flux 60 s plus tard
    /// sans le dire (7.6), et ses reglages d'app gardent `trames` a vrai.
    private(set) var tramesDemandeesLe: Date?
    /// Series des graphiques (compteurs, relectures, ordres, tas), par segment de `boot`.
    private(set) var courbes = SeriesCourbes()
    /// Un bloc `compteurs` est arrive depuis que leur periode est non nulle : il est celui
    /// du releve en cours. Faux des que la periode retombe a 0 (session distante ouverte
    /// ou rouverte, `json compteurs 0`) : le dernier bloc garde alors des valeurs figees
    /// (CompteursMesh.swift).
    private(set) var compteursEnDirect = false
    /// Annonce grave (ancien firmware, aucune reponse...) montree en bandeau.
    private(set) var alerte: MoteurSession.Note?
    /// Alerte de la source reseau qui demande l'utilisateur (cle absente ou trousseau en
    /// erreur, reseau local refuse, pont sans cle, sessions pleines), montree en bandeau.
    /// Une cause qui se reprend seule (pas de route, pont introuvable...) n'en a pas :
    /// la console et le panneau de connexion la disent (sans route, ils pointent vers
    /// halo-routes), comme Halo.
    private(set) var alerteReseau: AlerteReseau?
    private(set) var derniereReception: Date?
    /// Commande de la console du pont de plus de 20 min : proposer de fermer le port.
    var propositionFermeture = false
    /// Numero de serie USB du dernier pont confirme (preferences) : titre `AMARAN · MAC` de sa carte dans les menus tant que le repertoire ne la connait pas.
    private(set) var dernierPont: String?
    /// Reglages de session en vigueur ; nil avant le `hello`.
    private(set) var reglages: HelloBase.ReglagesSession?
    /// Facteur de temps du mode demo (1 : temps reel ; les tests accelerent).
    @ObservationIgnored var vitesseDemo: Double = 1

    // Acces reseau (Pont+Reseau.swift)
    /// Ponts dont ce Mac a la cle UDP (trousseau des ponts, jamais celui de la demo).
    var pontsConnus: [PontConnu] = []
    /// Ponts deja vus (modele et nom SRP par MAC) : titres des sources reseau, gardes
    /// dans les preferences (`RepertoirePonts.cleReglages`).
    var repertoire = RepertoirePonts()
    /// `json cle nouvelle` en cours : suivi et nom SRP du pont (Pont+Reseau.swift).
    @ObservationIgnored var creationCle: (id: UUID, nom: String)?

    // Cles (Pont+Cles.swift)
    /// Copie du trousseau (celui de la demo en mode demo), sans ses cles.
    var copie: ApercuReseau?
    /// Derniere lecture de la base d'amaran Desktop, sans ses cles.
    var base: ApercuReseau?
    var erreurBase: String?
    /// Dossier d'amaran Desktop autorise (signet).
    var dossierAmaran: URL?
    var chargement: EtatChargement = .repos
    var derniereSauvegarde: Date?
    @ObservationIgnored var charge: ChargementEnCours?
    /// `avancerChargement` est en cours : `envoyer` rappelle `synchroniser`, qui le rappellerait.
    @ObservationIgnored var chargementAvance = false

    // MARK: Interne

    @ObservationIgnored var moteur = MoteurSession()
    @ObservationIgnored private var recepteur = RecepteurLignes()
    @ObservationIgnored private var transport: (any Transport)?
    @ObservationIgnored private var demo: TransportDemo?
    @ObservationIgnored private(set) var genreTransport: GenreTransport?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tacheLecture: Task<Void, Never>?
    @ObservationIgnored private var tacheReconnexion: Task<Void, Never>?
    @ObservationIgnored private var tacheTic: Task<Void, Never>?
    @ObservationIgnored private var reconnexionAuto = false
    @ObservationIgnored private var essaisReconnexion = 0
    @ObservationIgnored private var compteur = 0
    @ObservationIgnored private var dernierCurseur: [String: TimeInterval] = [:]
    @ObservationIgnored private let origine = ContinuousClock.now
    @ObservationIgnored private let surveillant = SurveillantUSB()
    @ObservationIgnored let trousseau: any TrousseauReseau
    /// Trousseau isole de la demo : rien de la demo n'ecrase la vraie copie.
    @ObservationIgnored let trousseauDemo: any TrousseauReseau
    @ObservationIgnored let preferences: UserDefaults
    /// Cles UDP des ponts joints par Thread.
    @ObservationIgnored let trousseauPonts: any TrousseauPonts
    /// Trousseau des ponts isole de la demo : une cle creee en mode demo n'ecrase jamais
    /// celle d'un vrai pont et n'apparait jamais dans `pontsConnus`.
    @ObservationIgnored let trousseauPontsDemo: any TrousseauPonts
    /// Transport d'une source reseau (hote `<nom>.local`, cle) : `TransportUDP` ; les
    /// tests y mettent un transport factice.
    @ObservationIgnored var fabriqueReseau: @MainActor (_ hote: String, _ cle: Data) -> any Transport = { hote, cle in
        TransportUDP(hote: hote, cle: cle)
    }
    @ObservationIgnored private let cheminReseau = NWPathMonitor()
    /// Derniere cause reseau notee en console : une meme cause n'est notee qu'une fois
    /// tant qu'elle ne change pas.
    @ObservationIgnored private var derniereCauseReseau: String?
    @ObservationIgnored private var observateurReveil: (any NSObjectProtocol)?
    @ObservationIgnored private var observateurFin: (any NSObjectProtocol)?
    /// Session serie ouverte : pas de mise en sommeil de l'app (App Nap) qui
    /// retarderait le ping au-dela du bail de 30 s.
    @ObservationIgnored private var activite: (any NSObjectProtocol)?

    /// Delais de reouverture apres une fermeture : 300 ms, puis 1 s, 2 s, 5 s (3.1).
    static let delaisReconnexion: [Double] = [0.3, 1, 2, 5]

    init(trousseau: any TrousseauReseau = TrousseauSysteme(), trousseauDemo: any TrousseauReseau = TrousseauMemoire(ReseauDemo.reseau),
         trousseauPonts: any TrousseauPonts = TrousseauPontsSysteme(),
         trousseauPontsDemo: any TrousseauPonts = TrousseauPontsMemoire(),
         preferences: UserDefaults = .standard) {
        self.trousseau = trousseau
        self.trousseauDemo = trousseauDemo
        self.trousseauPonts = trousseauPonts
        self.trousseauPontsDemo = trousseauPontsDemo
        self.preferences = preferences
        dernierPont = preferences.string(forKey: Self.cleDernierPont)
        pontsConnus = trousseauPonts.lister()
        if let d = preferences.data(forKey: RepertoirePonts.cleReglages), let r = RepertoirePonts(donnees: d) {
            repertoire = r
        }
        ports = Self.portsVisibles(SurveillantUSB.lister())
        surveillant.changement = { [weak self] ports in self?.portsChanges(ports) }
        surveillant.demarrer()
        cheminReseau.pathUpdateHandler = { [weak self] chemin in
            guard chemin.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.reseauChange() }
        }
        cheminReseau.start(queue: .main)
        observateurReveil = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Pause de lecture : la premiere ligne lue ensuite peut etre un fragment (2.4).
                self?.recepteur.signalerPause()
                self?.reseauChange()
            }
        }
        observateurFin = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Rendre la console texte au pont avant de partir (sinon JSON jusqu'a la fin du bail).
                self?.fermerProprement(synchrone: true)
            }
        }
        tacheTic = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.tic()
            }
        }
        chargerPreferencesCles()
    }

    func maintenant() -> TimeInterval {
        (ContinuousClock.now - origine) / .seconds(1)
    }

    private func prochainId() -> Int {
        compteur += 1
        return compteur
    }

    // MARK: - Connexion

    /// Cle des preferences : numero de serie USB du dernier pont confirme (le `hello` a
    /// montre un pont amaran), jamais d'un port seulement choisi dans le menu.
    static let cleDernierPont = "dernierPont"

    /// Source proposee par "Connecter" : seulement le dernier pont confirme, reconnu a son
    /// numero de serie USB. Jamais "le premier port Espressif" (la C6 BenQ en est un aussi).
    var sourceParDefaut: Source? {
        Self.sourceParDefaut(ports: ports, dernierPont: dernierPont)
    }

    /// Vrai si l'identite du `hello` est celle d'un pont amaran : la capacite `mesh`, ou un
    /// numero de serie `AMARAN-...`.
    static func estPontAmaran(_ identite: HelloIdentite?) -> Bool {
        guard let identite else { return false }
        return (identite.caps ?? []).contains("mesh") || (identite.id?.serie?.hasPrefix("AMARAN-") ?? false)
    }

    /// Une carte USB deja confirmee comme pont est retenue pour "Connecter".
    private func confirmerPont() {
        guard case .serie(_, let serie?)? = source, serie != dernierPont,
              Self.estPontAmaran(etat.identite?.valeur) else { return }
        dernierPont = serie
        preferences.set(serie, forKey: Self.cleDernierPont)
    }

    /// Titre d'un port (comme Halo Compagnon) : "AMARAN · F0:F5:BD:0A:0B:0C", le modele puis la
    /// MAC (le numero de serie USB de la carte est sa MAC). Le modele vient du repertoire (appris
    /// au `hello` d'un vrai pont, par l'USB ou le reseau) ; carte encore inconnue du repertoire
    /// mais dernier pont confirme : `AMARAN` ; sinon "ESP32". Sans MAC lisible, le nom court du port.
    func titre(port p: PortUSB) -> String { titre(serie: p.serie, chemin: p.chemin) }

    /// Titre d'une carte USB par son numero de serie (sa MAC) et son chemin : celui d'un port
    /// branche comme celui de la source serie choisie (branchee ou non).
    func titre(serie: String?, chemin: String) -> String {
        guard let mac = RepertoirePonts.mac(serie) else {
            return chemin.replacingOccurrences(of: "/dev/cu.", with: "")
        }
        if repertoire.parMac[mac]?.modele == nil, serie == dernierPont {
            return "\(Self.modelePont) · \(RepertoirePonts.macLisible(mac))"
        }
        return repertoire.titre(mac: mac)
    }

    /// Modele d'un pont amaran (le numero de serie du `hello` est `AMARAN-<MAC>`).
    static let modelePont = "AMARAN"

    static func sourceParDefaut(ports: [PortUSB], dernierPont: String?) -> Source? {
        guard let dernierPont,
              let p = ports.first(where: { $0.estEspressif && $0.serie == dernierPont }) else { return nil }
        return .serie(chemin: p.chemin, serie: p.serie)
    }

    func connecter(_ s: Source) {
        let changement = s != source
        if changement {
            // Autre pont ou demo : le pont quitte retrouve la console texte, et rien de
            // l'ancienne source ne reste (ni etat, ni boot).
            fermerProprement()
            oublierSource()
        } else if s.estReseau {
            // Meme pont reseau choisi de nouveau : json 0 scelle d'abord, sinon l'ancienne
            // session H1 garderait l'une des deux places du pont jusqu'a son oubli (10.3).
            fermerProprement()
        } else {
            fermerTransport()
        }
        source = s
        alerte = nil
        alerteReseau = nil
        derniereCauseReseau = nil
        reconnexionAuto = true
        essaisReconnexion = 0
        if changement, let nom = nomSource {
            // Comme Halo : la console garde ses lignes (l'historique de la session), seuls les
            // etats, trames et courbes repartent de zero.
            note("Nouvelle source : \(nom). États, trames et courbes remis à zéro ; la console garde ses lignes.")
        }
        rafraichirCopie()
        ouvrir()
    }

    func deconnecter() {
        reconnexionAuto = false
        alerteReseau = nil
        fermerProprement()
        etatTransport = .ferme
    }

    /// "Liberer le port" (3.1) : `json 0`, fermeture, pas de reouverture avant un clic.
    /// Source reseau : la session H1 se ferme de meme (`json 0` scelle), rien a flasher.
    func libererPort() {
        reconnexionAuto = false
        let modeMachine = rendModeTexte
        let reseau = source?.estReseau == true
        fermerProprement()
        etatTransport = .libere
        // Plus aucune relance : un bandeau reseau qui en promettait une ne vaut plus.
        alerteReseau = nil
        if reseau {
            note(modeMachine
                 ? "Session réseau fermée : json 0 envoyé. « Reconnecter » pour reprendre."
                 : "Session réseau fermée. « Reconnecter » pour reprendre.")
        } else {
            note(modeMachine
                 ? "Port libéré : json 0 envoyé, port fermé. Flasher est possible ; « Reconnecter » pour reprendre."
                 : "Port libéré : port fermé. Flasher est possible ; « Reconnecter » pour reprendre.")
        }
    }

    /// Vrai si fermer doit d'abord rendre la console texte au pont (`json 0`) : session
    /// machine ou tentative en cours, et pas de commande en cours (la console du pont
    /// ne lit plus).
    private var rendModeTexte: Bool {
        guard transport != nil, moteur.correlateur.commandeDeBanc == nil else { return false }
        switch moteur.phase {
        case .ferme, .ancienFirmware, .versionInconnue, .modeHumain: return false
        default: return true
        }
    }

    /// `json 0` si besoin, puis fermeture apres vidage de la file de sortie.
    private func fermerProprement(synchrone: Bool = false) {
        tacheReconnexion?.cancel()
        guard let t = transport else {
            fermerTransport()
            return
        }
        if rendModeTexte {
            executer(moteur.liberer(maintenant: maintenant()))
        } else if moteur.phase != .ferme {
            moteur.ferme(maintenant: maintenant())
        }
        transport = nil
        // La boucle de lecture se detache (generation) ; l'annuler fermerait le port
        // tout de suite, avant que json 0 soit parti.
        generation += 1
        tacheLecture = nil
        t.fermerApresVidage(synchrone: synchrone)
        finActivite()
        synchroniser()
    }

    /// Nouvelle source : moteur, recepteur et etats repartent de zero.
    private func oublierSource() {
        moteur = MoteurSession()
        recepteur = RecepteurLignes()
        etat = EtatPont()
        demo = nil
        rejets.vider()
        trames.vider()
        tramesDemandeesLe = nil
        courbes.vider()
        compteursEnDirect = false
        dernierCurseur = [:]
        propositionFermeture = false
        derniereReception = nil
        interrompreChargement("source changée")
        interrompreCreationCle()
        synchroniser()
    }

    private var nomSource: String? {
        switch source {
        case .serie(let chemin, let serie): titre(serie: serie, chemin: chemin)
        case .demo: "démo"
        case .reseau(let nom): repertoire.mac(pourSrp: nom) == nil ? "\(nom).local" : "\(titre(reseau: nom)) (\(nom).local)"
        case nil: nil
        }
    }

    func reconnecter() {
        guard source != nil else { return }
        reconnexionAuto = true
        essaisReconnexion = 0
        alerte = nil
        // La cause n'est PAS oubliee (derniereCauseReseau) : reessayer sur la meme cause
        // ne redouble pas la ligne de console.
        alerteReseau = nil
        ouvrir()
    }

    /// Nouvel essai de `json 1` (apres un flash du firmware, par exemple).
    func reessayer() {
        alerte = nil
        executer(moteur.reessayer(maintenant: maintenant()))
    }

    private func ouvrir() {
        guard let source else { return }
        tacheReconnexion?.cancel()
        fermerTransport()
        let t: any Transport
        switch source {
        case .demo:
            if demo == nil { demo = TransportDemo(vitesse: vitesseDemo) }
            t = demo!
        case .serie(let chemin, let serie):
            // Le meme pont (meme numero de serie USB) peut revenir sous un autre nom ;
            // jamais un autre appareil, meme sous le nom d'avant.
            guard let port = Self.portDuPont(ports, chemin: chemin, serie: serie) else {
                echecOuverture(ErreurTransport("Pont absent : aucune carte Espressif reconnue"))
                return
            }
            t = TransportSerie(chemin: port.chemin)
        case .reseau(let nom):
            do {
                // La cle quitte le trousseau pour la session seulement.
                t = fabriqueReseau("\(nom).local", try trousseauPonts.lire(nom: nom))
            } catch {
                let a = AlerteReseau.trousseau(error as? ErreurTrousseauPonts ?? .absente(nom))
                alerteReseau = a
                etatTransport = .erreur(a.texte)
                noterCauseReseau(a.texte, grave: true)
                return
            }
        }
        transport = t
        genreTransport = t.genre
        nomTransport = t.nom
        etatTransport = .ouverture
        generation += 1
        let g = generation
        tacheLecture = Task { [weak self] in
            do {
                let flux = try await t.ouvrir()
                guard let self, self.generation == g else {
                    t.fermer()
                    return
                }
                self.transportOuvert()
                var raison = "flux terminé"
                for await ev in flux {
                    guard self.generation == g else { break }
                    if case .ferme(let r) = ev { raison = r }
                    self.recevoir(ev)
                }
                if self.generation == g { self.transportFerme(raison) }
            } catch {
                guard let self, self.generation == g else { return }
                self.echecOuverture(error)
            }
        }
    }

    private func fermerTransport() {
        generation += 1
        tacheLecture?.cancel()
        tacheLecture = nil
        transport?.fermer()
        transport = nil
        finActivite()
        if moteur.phase != .ferme {
            moteur.ferme(maintenant: maintenant())
            synchroniser()
        }
        interrompreCreationCle()
    }

    private func debutActivite() {
        guard activite == nil else { return }
        activite = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Session du pont amaran : ping du bail")
    }

    private func finActivite() {
        guard let a = activite else { return }
        ProcessInfo.processInfo.endActivity(a)
        activite = nil
    }

    private func transportOuvert() {
        etatTransport = .ouvert
        // Une poignee de main reussie leve les causes d'echec d'ouverture, pas « aucune
        // reponse au json 1 » (sansHello) : elle reussissait deja. Ce bandeau tient
        // jusqu'au hello (synchroniser), sans etre redit a chaque relance.
        if alerteReseau != .sansHello {
            alerteReseau = nil
            derniereCauseReseau = nil
        }
        debutActivite()
        // Port serie : jeter ce qui precede le premier LF (3.1). Reseau : chaque datagramme
        // est une ligne entiere, et la premiere est le hello du json 1 : rien a jeter.
        if genreTransport != .udp { recepteur.resynchroniser() }
        switch genreTransport {
        case .demo: note("Pont de démonstration ouvert.")
        case .udp: note("Session réseau ouverte : \(nomTransport).")
        default: note("Port ouvert : \(nomTransport) (DTR = RTS = 0).")
        }
        executer(moteur.ouvert(maintenant: maintenant(), genre: genreTransport ?? .usb))
    }

    private func transportFerme(_ raison: String) {
        transport = nil
        finActivite()
        moteur.ferme(maintenant: maintenant())
        synchroniser()
        note("Transport fermé : \(raison)")
        interrompreCreationCle()
        if reconnexionAuto { planifierReconnexion(raison) } else { etatTransport = .ferme }
    }

    func echecOuverture(_ erreur: any Error) {
        transport = nil
        if let e = erreur as? ErreurTransportReseau {
            let texte = AlerteReseau.transport(e).texte
            // Bandeau tant que l'utilisateur doit agir (reseau local refuse, pont sans
            // cle), essais en cours ou non ; une autre cause efface un bandeau perime.
            alerteReseau = e.bandeau ? .transport(e) : nil
            noterCauseReseau(texte, grave: e.bandeau)
            if !e.repriseAutomatique {
                etatTransport = .erreur(texte)
            } else if reconnexionAuto, essaisReconnexion < 40 {
                planifierReconnexion(texte)
            } else {
                etatTransport = .erreur("\(texte) — en attente d'un changement du réseau")
            }
            return
        }
        let texte = String(describing: erreur)
        if reconnexionAuto, essaisReconnexion < 40 {
            planifierReconnexion(texte)
        } else if reconnexionAuto {
            // Plus d'essais minutes (~3 min), mais le retour du port (IOKit) rouvre encore.
            etatTransport = .erreur("\(texte) — en attente du retour du port")
        } else {
            etatTransport = .erreur(texte)
        }
    }

    private func planifierReconnexion(_ raison: String) {
        let delai = Self.delaisReconnexion[min(essaisReconnexion, Self.delaisReconnexion.count - 1)]
        essaisReconnexion += 1
        etatTransport = .attente(prochain: Date().addingTimeInterval(delai), raison: raison)
        tacheReconnexion?.cancel()
        tacheReconnexion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delai / (self?.vitesseDemo ?? 1)))
            guard !Task.isCancelled else { return }
            self?.ouvrir()
        }
    }

    /// Le port du pont parmi `ports` : Espressif seulement. Avec un numero de serie USB
    /// connu, c'est lui qui decide (le pont peut changer de nom, jamais de numero) ;
    /// sans numero, le port de meme chemin.
    static func portDuPont(_ ports: [PortUSB], chemin: String, serie: String?) -> PortUSB? {
        let cartes = ports.filter(\.estEspressif)
        if let serie { return cartes.first { $0.serie == serie } }
        return cartes.first { $0.chemin == chemin }
    }

    /// Ports du menu Source : les cartes Espressif seulement (USB Serial/JTAG du C6,
    /// VID 303A) ; ni Bluetooth, ni console de debogage, ni ecrans.
    static func portsVisibles(_ tous: [PortUSB]) -> [PortUSB] { tous.filter(\.estEspressif) }

    /// Arrivee ou depart d'un port (IOKit) : on rouvre des que le pont revient, meme
    /// apres l'abandon des essais minutes (etat `.erreur`).
    private func portsChanges(_ nouveaux: [PortUSB]) {
        ports = Self.portsVisibles(nouveaux)
        guard reconnexionAuto, case .serie(let chemin, let serie)? = source else { return }
        switch etatTransport {
        case .attente, .erreur: break
        default: return
        }
        if Self.portDuPont(nouveaux, chemin: chemin, serie: serie) != nil {
            essaisReconnexion = 0
            planifierReconnexion("port revenu")
        }
    }

    /// Chemin reseau retrouve ou reveil du Mac : une source reseau en attente ou en
    /// echec repart (la ou l'USB attend le retour du port). Les arrets qui exigent
    /// l'utilisateur (cle absente ou trousseau en erreur, pont sans cle) ne
    /// reessaient pas seuls. « Reseau local refuse » reessaie seul, bandeau tenu, et
    /// repart aussi d'ici apres ses 40 essais.
    func reseauChange() {
        guard reconnexionAuto, source?.estReseau == true else { return }
        if case .trousseau = alerteReseau { return }
        if case .transport(.portInjoignable) = alerteReseau { return }
        switch etatTransport {
        case .attente, .erreur:
            essaisReconnexion = 0
            planifierReconnexion("réseau changé")
        default:
            break
        }
    }

    // MARK: - Boucle

    private func tic() {
        if moteur.phase != .ferme { executer(moteur.tic(maintenant: maintenant())) }
        avancerChargement()
    }

    /// Seul un test appelle ceci : avance l'horloge de la session de `secondes` sans
    /// attendre, comme le ferait `tic()` a l'echeance reelle.
    func avancerPourUnTest(de secondes: TimeInterval) {
        executer(moteur.tic(maintenant: maintenant() + secondes))
    }

    private func recevoir(_ ev: EvenementTransport) {
        guard case .donnees(let d) = ev else { return }
        derniereReception = Date()
        for element in recepteur.alimenter(d) { traiter(element) }
        synchroniser()
    }

    private func traiter(_ brut: ElementRecu) {
        // La reponse a `json cle nouvelle` porte la cle UDP : elle ne sert qu'ici, a la
        // ranger. Tout le reste (moteur, etats, console, rejets, trames) ne voit que
        // l'element sans cle (masque strict pour les lignes abimees et les fragments).
        let suiviCle = reponseACreationCle(brut)
        let element = brut.sansCle
        let effets = moteur.recu(element, maintenant: maintenant())
        let historique = moteur.historique
        // Un redemarrage vide les etats derives AVANT d'appliquer la ligne qui l'a revele
        // (le hello du nouveau demarrage doit rester).
        let (redemarrages, autres) = effets.reduce(into: ([MoteurSession.Effet](), [MoteurSession.Effet]())) { r, e in
            if case .redemarrage = e { r.0.append(e) } else { r.1.append(e) }
        }
        executer(redemarrages)
        if let c = suiviCle { terminerCreationCle(c.0, nom: c.1) }
        switch element {
        case .machine(let l):
            traiterMachine(l, historique: historique)
        case .texte(let t):
            if t.classe != .invite {
                ajouterConsole(.texte(t.classe), t.texte, numero: moteur.correlateur.commandeDeBanc?.numero)
            }
        case .fragment(let s):
            ajouterConsole(.fragment, s)
        case .abimee(let raison, let brut):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "abîmée : \(raison)", brut: brut))
        case .versionInconnue(let v, let t):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "version \(v) inconnue",
                                  brut: PolitiqueCommandes.masquerCle(t)))
        case .invalide(let t, let raison):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "\(t) invalide : \(raison)", brut: ""))
        case .debordement(let s):
            ajouterConsole(.texte(.commande), s)
        }
        executer(autres)
    }

    /// `l` est deja sans cle (`LigneMachine.sansCle`).
    private func traiterMachine(_ l: LigneMachine, historique: Bool) {
        let recueA = Date()
        let date = historique ? etat.dater(ms: l.enveloppe.ms, recueA: recueA) : etat.appliquer(l, recueA: recueA)
        if !historique {
            courbes.ajouter(l.message, date: date)
            switch l.message {
            case .helloIdentite, .reseauIp: noterRepertoire()
            case .compteursMesh where (moteur.reglages.compteursMs ?? 0) > 0 && !compteursEnDirect: compteursEnDirect = true
            default: break
            }
        }
        switch l.message {
        case .texte(let t):
            // A distance, la sortie d'une commande a texte (10.4) : comme le texte de la
            // console par l'USB, rattachee a son id.
            ajouterConsole(.texte(.commande), t.txt ?? "", numero: t.id)
        case .trame(let t):
            trames.ajouter(TrameRecue(id: prochainId(), date: date, trame: t))
        case .ordre(let o):
            for id in o.ids ?? [] {
                guard let s = moteur.correlateur.suivi(numero: id) else { continue }
                ajouterConsole(.retour(ok: o.issue != .abandon, session: s.origine == .session),
                               "‹ id=\(id) « \(s.commande) » : \(Interpretation.ordre(o))", numero: id)
            }
        case .reponse(let r):
            let s = moteur.correlateur.suivi(numero: r.id)
            ajouterConsole(.retour(ok: r.ok, session: (s?.origine ?? .session) == .session),
                           "‹ " + Interpretation.reponse(r), numero: r.id)
        case .log(let lg):
            ajouterConsole(.log, lg.txt ?? "")
        case .lampe(let e):
            let quoi = switch e.quoi {
            case .entree: "entre dans Maison (EP\(e.endpoint ?? 0))"
            case .masquee: "retirée de Maison"
            case .remise: "remise dans Maison (EP\(e.endpoint ?? 0))"
            case .echec: "endpoint Matter non créé"
            case .inconnu, nil: "changement inconnu"
            }
            note("Lampe \(e.lampe) : \(quoi).")
        case .alerte(let a):
            switch a.quoi {
            case .releves:
                note(a.manque == true
                     ? "Lampe \(a.lampe ?? 0) : relectures manquées, \(a.part ?? 0) % répondues sur 10 min."
                     : "Lampe \(a.lampe ?? 0) : relectures de nouveau répondues (\(a.part ?? 0) %).",
                     grave: a.manque == true)
            case .mesh:
                note("Bluetooth Mesh : \(Interpretation.diag(a.diag)).", grave: a.diag != .ok)
            case .inconnu, nil:
                break
            }
        default:
            break
        }
    }

    func executer(_ effets: [MoteurSession.Effet]) {
        for e in effets {
            switch e {
            case .envoyer(let d):
                do {
                    try transport?.envoyer(d)
                } catch {
                    note("Envoi impossible : \(String(describing: error))")
                }
                journaliserEnvoi(d)
            case .rouvrir(let n):
                note(n.texte)
                // Relance prevue a distance (toujours aucun hello), pas un echec de plus :
                // le nouvel essai part des la fermeture, le bandeau « nouvel essai toutes
                // les 30 s » reste vrai, et ces relances n'usent pas les 40 essais.
                if n == .reseauSansHello { essaisReconnexion = 0 }
                // Reseau : .ferme, transportFerme, puis reconnexion (nouvelle resolution du
                // nom, nouvelle poignee de main).
                transport?.fermer()
            case .redemarrage(let ancien, let nouveau):
                etat.viderDerives()
                note("Redémarrage du pont détecté (boot \(ancien ?? "?") → \(nouveau ?? "?")) : états vidés.")
            case .note(let n):
                if n == .aucuneReponse, genreTransport == .udp {
                    alerteReseau = .sansHello
                    // Redite a chaque relance (nouvelle poignee de main toutes les 30 s) :
                    // notee une fois tant que la cause ne change pas.
                    noterCauseReseau(AlerteReseau.sansHello.texte, grave: true)
                } else {
                    note(n.texte, grave: n.grave)
                    if n.grave { alerte = n }
                }
            case .commandeSansReponse(let id):
                if creationCle?.id == id {
                    // `creationCle` reste arme : une reponse tardive doit encore etre rangee.
                    note("Pas encore de réponse à la création de clé : une réponse tardive sera quand même rangée ; sinon l'accès réseau affichera « clé inconnue de ce Mac ».")
                }
                if let s = moteur.correlateur.suivi(id) {
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   "‹ id=\(s.numero ?? 0) « \(s.commande) » : \(Self.texteSansReponse(moteur.correlateur.politique, commande: s.commande))",
                                   numero: s.numero)
                }
            case .ordrePerdu(let id):
                if let s = moteur.correlateur.suivi(id) {
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   "‹ id=\(s.numero ?? 0) « \(s.commande) » : aucune issue sous 10 s (ligne perdue ?)",
                                   numero: s.numero)
                }
            case .proposerFermeture:
                propositionFermeture = true
            }
        }
        synchroniser()
    }

    private func journaliserEnvoi(_ d: Data) {
        let texte = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .newlines)
        guard !texte.isEmpty, texte != "\u{15}" else { return }
        var numero: Int?
        var origine = OrigineCommande.session
        if texte.hasPrefix("id="), let espace = texte.firstIndex(of: " ") {
            numero = Int(texte[texte.index(texte.startIndex, offsetBy: 3)..<espace])
            if let n = numero, let s = moteur.correlateur.suivi(numero: n) { origine = s.origine }
        } else {
            origine = .console
        }
        ajouterConsole(.envoi(origine), "› " + texte, numero: numero)
    }

    func synchroniser() {
        if phase != moteur.phase {
            phase = moteur.phase
            if phase == .connecte {
                essaisReconnexion = 0
                // Session retablie : l'alerte d'un echec passe ne vaut plus, et une cause
                // reseau qui reviendrait ensuite sera notee de nouveau.
                alerte = nil
                alerteReseau = nil
                derniereCauseReseau = nil
            }
        }
        let r = etat.helloBase != nil ? moteur.reglages : nil
        if reglages != r { reglages = r }
        // Periode des compteurs a 0 (ou pas de session) : le dernier bloc n'est plus releve.
        if compteursEnDirect, (r?.compteursMs ?? 0) == 0 { compteursEnDirect = false }
        if suivis != moteur.correlateur.suivis { suivis = moteur.correlateur.suivis }
        if statistiques != moteur.statistiques { statistiques = moteur.statistiques }
        if reception != recepteur.compteurs { reception = recepteur.compteurs }
        confirmerPont()
        avancerChargement()
    }

    /// Toute ligne de la console passe par le masque des cles : texte recu,
    /// fragments, retours qui citent la commande, notes.
    private func ajouterConsole(_ genre: LigneConsole.Genre, _ texte: String, numero: Int? = nil) {
        console.ajouter(LigneConsole(id: prochainId(), date: Date(), genre: genre,
                                     texte: PolitiqueCommandes.masquerCle(texte), numero: numero))
    }

    /// Annonce de l'app dans la console.
    func note(_ texte: String, grave: Bool = false) {
        ajouterConsole(.note(grave: grave), texte)
    }

    /// Cause d'un arret ou d'une reprise reseau : un meme message n'est note qu'une
    /// fois dans la console tant que la cause ne change pas.
    private func noterCauseReseau(_ texte: String, grave: Bool) {
        guard derniereCauseReseau != texte else { return }
        derniereCauseReseau = texte
        note(texte, grave: grave)
    }

    /// Fin d'une commande sans reponse : par l'USB, 3 s sans renvoi ; a distance, le
    /// meme id renvoye avant le verdict (politique du correlateur), 6 s, ou 12 s pour une
    /// commande dont la `fin` suit un instantane (`json etat`, `json hello`, `json 1`).
    static func texteSansReponse(_ p: PolitiqueDelais, commande: String = "") -> String {
        let delai = Int(p.delaiReponse(pour: commande))
        return p.renvois > 0
            ? "sans réponse sous \(delai) s (\(p.renvois) renvois du même id)"
            : "sans réponse sous \(delai) s (pas de réémission)"
    }

    // MARK: - Commandes

    var peutCommander: Bool { phase.modeMachine && transport != nil }

    /// Source reseau ouverte : la liste blanche du pont s'applique (10.5).
    var aDistance: Bool { genreTransport == .udp }

    /// La commande peut partir par la source en vigueur (boutons des ecrans).
    func peutEnvoyer(_ commande: String) -> Bool {
        peutCommander && (!aDistance || PolitiqueCommandes.autoriseeADistance(commande) == nil)
    }

    /// La console envoie avec un `id` : session machine, ou `json 1` en attente de
    /// son `hello`. Sinon (ancien firmware, console texte...) : ligne brute. A distance,
    /// toujours avec un `id` (le pont ignore une ligne sans id).
    var consoleAvecId: Bool {
        if aDistance { return true }
        if phase.modeMachine { return true }
        if case .attenteHello = phase { return true }
        return false
    }

    /// Commande d'un bouton ou d'un curseur, avec `id` et correlation. `secret` : la
    /// commande porte des cles (jamais gardee ni affichee).
    @discardableResult
    func envoyer(_ commande: String, fusion: String? = nil, secret: Bool = false) -> UUID? {
        guard peutCommander else {
            note("Pas de session machine : « \(PolitiqueCommandes.masquerCle(commande)) » n'est pas envoyée.")
            return nil
        }
        if aDistance, let raison = PolitiqueCommandes.autoriseeADistance(commande) {
            note(Self.texteNonEnvoyee(commande, raison: raison))
            return nil
        }
        let (id, effets) = moteur.soumettre(commande, origine: .interface, fusion: fusion, secret: secret,
                                            maintenant: maintenant())
        noterDemandeTrames(commande)
        executer(effets)
        return id
    }

    /// Curseurs : une commande toutes les 150 ms au plus pendant le glissement,
    /// toujours la valeur finale au relachement (6.4).
    func curseur(_ commande: String, cle: String, fini: Bool) {
        let t = maintenant()
        guard fini || t - (dernierCurseur[cle] ?? -1) >= 0.15 else { return }
        dernierCurseur[cle] = t
        envoyer(commande, fusion: cle)
    }

    /// Note d'une commande que la liste blanche du pont refuse : rien ne part. La raison
    /// du pont n'y est citee qu'une fois, telle quelle ; la commande, masquee.
    static func texteNonEnvoyee(_ commande: String, raison: String) -> String {
        "« \(PolitiqueCommandes.masquerCle(commande.trimmingCharacters(in: .whitespaces))) » n'est pas envoyée : \(PolitiqueCommandes.refusDistant(raison))."
    }

    /// Console brute : regles de 2.5, confirmations et interdits de 6.4.
    func console(_ ligne: String, confirme: Bool = false) -> ResultatConsole {
        switch PolitiqueCommandes.verdictConsole(ligne, transport: genreTransport ?? .usb) {
        case .interdite(let raison):
            if aDistance, let refus = PolitiqueCommandes.autoriseeADistance(ligne) {
                // Rien ne part : la console le dit aussi, la ligne tapee masquee.
                note(Self.texteNonEnvoyee(ligne, raison: refus))
            }
            return .refusee(raison)
        case .confirmation(let raison) where !confirme:
            return .confirmation(raison)
        default:
            break
        }
        guard let transport else { return .refusee("Aucun pont connecté.") }
        let propre = ligne.trimmingCharacters(in: .whitespaces)
        let secret = PolitiqueCommandes.masquerCle(propre) != propre
        if consoleAvecId {
            let (_, effets) = moteur.soumettre(propre, origine: .console, secret: secret, maintenant: maintenant())
            noterDemandeTrames(propre)
            executer(effets)
        } else {
            // Ancien firmware, console texte... : ligne brute, sans id.
            switch moteur.ligneBrute(propre) {
            case .success(let d):
                do { try transport.envoyer(d) } catch {
                    return .refusee("Envoi impossible : \(String(describing: error))")
                }
                journaliserEnvoi(d)
            case .failure(let e):
                return .refusee(e.description)
            }
        }
        if PolitiqueCommandes.attendReenumeration(propre) {
            note("Attente de la ré-énumération USB (le pont redémarre).")
        }
        return .envoyee
    }

    func rafraichir() { envoyer("json etat") }

    func viderConsole() { console.vider() }

    /// `json trames 1` ou `0` (7.6). Les reglages suivent la reponse du pont ; a
    /// distance, le pont les coupe seul au bout de 60 s.
    func activerTrames(_ actives: Bool) {
        envoyer("json trames \(actives ? 1 : 0)")
    }

    /// Flux `trame` demande (reglages de la session : `hello`, puis `json trames`).
    var tramesActives: Bool { reglages?.trames == true }

    /// Duree du flux des trames a distance : le pont le coupe seul (7.6).
    static let dureeTramesADistance: TimeInterval = 60

    /// A distance, le flux demande est coupe par le pont 60 s apres le dernier
    /// `json trames 1` : il ne le signale pas, l'app le deduit de l'horloge (un `hello`
    /// qui dirait `trames` faux ramene de toute facon `tramesActives` a faux).
    func tramesCoupeesParLePont(a maintenant: Date = Date()) -> Bool {
        guard aDistance, tramesActives, let d = tramesDemandeesLe else { return false }
        return maintenant.timeIntervalSince(d) >= Self.dureeTramesADistance
    }

    /// Secondes avant la coupure du flux a distance ; nil : pas de coupure a attendre
    /// (USB, flux non demande, ou deja coupe).
    func secondesAvantCoupureDesTrames(a maintenant: Date = Date()) -> Int? {
        guard aDistance, tramesActives, let d = tramesDemandeesLe, !tramesCoupeesParLePont(a: maintenant) else { return nil }
        return Int((Self.dureeTramesADistance - maintenant.timeIntervalSince(d)).rounded(.up))
    }

    /// `json trames 1` lu comme la console du pont le decoupe (`LigneCommande.argv`,
    /// sensible a la casse) : la ligne que le pont executera, guillemets ou echappements compris.
    private func noterDemandeTrames(_ commande: String) {
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        if a == ["json", "trames", "1"] { tramesDemandeesLe = Date() }
    }

    /// Derniere trame recue (a distance, son absence dit que le pont a coupe le flux).
    var derniereTrame: Date? { trames.elements.last?.date }

    func viderTrames() { trames.vider() }

    func viderCourbes() { courbes.vider() }

    /// `json periode|lampes|compteurs|reseau <ms>`, ramenee dans les bornes du transport
    /// (a distance, celles de la liste blanche) : par exemple les `compteurs` des courbes
    /// Mesh, coupes par le profil distant.
    func reglerCadence(_ c: MoteurSession.Cadence, ms: Int) {
        envoyer(moteur.ligneCadence(c, ms: ms))
    }

    // MARK: - Lectures pour les ecrans

    var estDemo: Bool { source?.estDemo ?? false }

    /// Commande de la console du pont en cours (`reponse debut` recue, pas de `fin`).
    var commandeDeBanc: SuiviCommande? {
        suivis.last { $0.etat == .enCours }
    }
}
````

`apps/macos/AmaranCompagnon/Reseau/AlerteReseau.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5, Reseau/AlerteReseau.swift) : la route IPv6
// vers le reseau Thread est celle que tient l'assistant systeme halo-routes de Halo.
import AmaranProtocole
import Foundation

/// Alerte de la source reseau, montree en bandeau.
enum AlerteReseau: Equatable, Sendable {
    case transport(ErreurTransportReseau)
    case trousseau(ErreurTrousseauPonts)
    /// DEFI recu, puis aucun `hello` (places de session prises, 10.3).
    case sansHello

    var texte: String {
        switch self {
        case .transport(.pasDeRoute): Self.textePasDeRoute(assistant: Self.assistantInstalle)
        case .transport(let e): e.description
        case .trousseau(let e): e.description
        case .sansHello:
            "Aucune réponse au json 1 par le réseau : deux autres sessions déjà actives (autre Mac, script de banc) ? Nouvel essai toutes les 30 s."
        }
    }

    /// Cause en quelques mots (liste des ponts connus).
    var raison: String {
        switch self {
        case .transport(.pasDeRoute): "pas de route IPv6"
        case .transport(.reseauLocalRefuse): "accès au réseau local refusé"
        case .transport(.portInjoignable): "le pont n'a plus de clé"
        case .transport(.nomIntrouvable): "pont introuvable"
        case .transport: "erreur réseau"
        case .trousseau(.absente): "clé absente de ce Mac"
        // La cle peut y etre : le trousseau en refuse la lecture (app recompilee ad hoc,
        // « Refuser » a l'invite) ; le bandeau donne le message du systeme.
        case .trousseau(.systeme): "trousseau inaccessible"
        case .sansHello: "aucune réponse, sessions prises ?"
        }
    }

    static func textePasDeRoute(assistant: Bool) -> String {
        ErreurTransportReseau.pasDeRoute.description + " " + (assistant
            ? "L'assistant système halo-routes est installé : la route revient d'elle-même."
            : "Installer l'assistant système halo-routes : tools/macos/halo-routes/installer.sh du dépôt github.com/Djoko-cli/benq-screenbar-halo-matter.")
    }

    /// Le plist de l'assistant halo-routes, s'il est installe (et que la sandbox laisse le voir).
    static var assistantInstalle: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/fr.djoko.halo.routes.plist")
    }
}
````

`apps/macos/AmaranCompagnon/Reseau/EtatSessionPont.swift` (contenu complet) :

````swift
// Etat de la session reseau d'un pont connu (Reglages › Acces reseau Thread) : lecture
// seule du modele, rien n'est envoye.
import AmaranProtocole
import Foundation

enum EtatSessionPont: Equatable, Sendable {
    /// Ce pont n'est pas la source en cours.
    case aucune
    /// Ouverture, poignee de main ou reconnexion en cours.
    case enCours
    case ouverte
    /// Le pont, ou le chemin, refuse ou ne repond pas : la raison, courte.
    case refusee(String)

    var libelle: String {
        switch self {
        case .aucune: "pas de session"
        case .enCours: "session en cours d'ouverture"
        case .ouverte: "session ouverte"
        case .refusee(let raison): "session refusée : \(raison)"
        }
    }
}

extension Pont {
    /// Session de ce pont (nom SRP, sans `.local`) : ouverte, en cours, refusee ou aucune.
    func etatSession(pour nom: String) -> EtatSessionPont {
        guard source == .reseau(nom: nom) else { return .aucune }
        if let a = alerteReseau { return .refusee(a.raison) }
        switch etatTransport {
        case .ouvert:
            switch phase {
            case .connecte: return .ouverte
            case .sansReponse: return .refusee("aucune réponse")
            default: return .enCours
            }
        case .ouverture, .attente: return .enCours
        case .ferme, .libere: return .aucune
        case .erreur(let e): return .refusee(e)
        }
    }
}
````

`apps/macos/AmaranCompagnon/Reseau/TrousseauPonts.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5, Reseau/Trousseau.swift) : les cles UDP des
// ponts joints par Thread (docs/PROTOCOLE-JSON.md 10.2). Distinct du trousseau des cles
// Mesh (Cles/Trousseau.swift, `TrousseauReseau`, service `fr.djoko.amaran.reseau`).
import AmaranProtocole
import Foundation
import Security
import Synchronization

/// Pont connu de ce Mac : son nom SRP (16 hexa, sans `.local`) et l'empreinte de sa cle UDP.
struct PontConnu: Hashable, Sendable, Identifiable {
    let nom: String
    let empreinte: String
    var id: String { nom }
    var hote: String { "\(nom).local" }
}

/// Cles du transport reseau (10.2), une par pont. La cle ne quitte le trousseau que
/// pour ouvrir une session ; elle n'est jamais affichee ni journalisee.
protocol TrousseauPonts: Sendable {
    func lister() -> [PontConnu]
    func lire(nom: String) throws -> Data
    func ranger(nom: String, cle: Data, empreinte: String) throws
    func oublier(nom: String) throws
}

enum ErreurTrousseauPonts: Error, Equatable, Sendable, CustomStringConvertible {
    case absente(String)
    case systeme(Int32)

    var description: String {
        switch self {
        case .absente(let nom):
            "Clé absente de ce Mac pour \(nom).local : brancher le pont en USB, puis « Nouvelle clé… » (« Activer l'accès réseau… » si le pont n'a pas de clé)."
        case .systeme(let s):
            "Trousseau : \(SecCopyErrorMessageString(s, nil) as String? ?? String(s))"
        }
    }
}

/// Trousseau de session du Mac : mot de passe generique, service
/// `fr.djoko.amaran.pont`, compte = nom SRP (sans `.local`), valeur = 64 hexa
/// MAJUSCULES, commentaire = empreinte. Local au Mac (pas de synchronisation iCloud),
/// comme Halo.
struct TrousseauPontsSysteme: TrousseauPonts {
    let service: String

    init(service: String = "fr.djoko.amaran.pont") {
        self.service = service
    }

    private func requete(_ nom: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let nom { q[kSecAttrAccount as String] = nom }
        return q
    }

    func lister() -> [PontConnu] {
        var q = requete()
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        q[kSecReturnAttributes as String] = true
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let elements = r as? [[String: Any]]
        else { return [] }
        return elements.compactMap { a in
            guard let nom = a[kSecAttrAccount as String] as? String else { return nil }
            return PontConnu(nom: nom, empreinte: a[kSecAttrComment as String] as? String ?? "?")
        }.sorted { $0.nom < $1.nom }
    }

    func lire(nom: String) throws -> Data {
        var q = requete(nom)
        q[kSecReturnData as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { throw ErreurTrousseauPonts.absente(nom) }
        guard s == errSecSuccess else { throw ErreurTrousseauPonts.systeme(s) }
        guard let d = r as? Data, let cle = H1.octets(hexa: String(decoding: d, as: UTF8.self)), cle.count == 32
        else { throw ErreurTrousseauPonts.systeme(errSecDecode) }
        return cle
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        let valeurs: [String: Any] = [kSecValueData as String: Data(H1.hexa(cle).utf8),
                                      kSecAttrComment as String: empreinte,
                                      kSecAttrLabel as String: "amaran - pont \(nom)"]
        var s = SecItemUpdate(requete(nom) as CFDictionary, valeurs as CFDictionary)
        if s == errSecItemNotFound {
            s = SecItemAdd(requete(nom).merging(valeurs) { $1 } as CFDictionary, nil)
        }
        guard s == errSecSuccess else { throw ErreurTrousseauPonts.systeme(s) }
    }

    func oublier(nom: String) throws {
        let s = SecItemDelete(requete(nom) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw ErreurTrousseauPonts.systeme(s) }
    }
}

/// Trousseau des tests et du mode demo : en memoire, isole du vrai.
final class TrousseauPontsMemoire: TrousseauPonts {
    private let cles = Mutex<[String: (cle: Data, empreinte: String)]>([:])

    func lister() -> [PontConnu] {
        cles.withLock { $0.map { PontConnu(nom: $0.key, empreinte: $0.value.empreinte) } }.sorted { $0.nom < $1.nom }
    }

    func lire(nom: String) throws -> Data {
        guard let e = cles.withLock({ $0[nom] }) else { throw ErreurTrousseauPonts.absente(nom) }
        return e.cle
    }

    func ranger(nom: String, cle: Data, empreinte: String) throws {
        cles.withLock { $0[nom] = (cle, empreinte) }
    }

    func oublier(nom: String) throws {
        _ = cles.withLock { $0.removeValue(forKey: nom) }
    }
}
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 1 sur 2. Remplacer :

````swift
                        } label: {
                            Label {
                                Text(verbatim: Pont.libellePort(p, dernierPont: pont.dernierPont))
                                Text(verbatim: p.chemin.replacingOccurrences(of: "/dev/cu.", with: ""))
                            } icon: {
````

par :

````swift
                        } label: {
                            Label {
                                Text(verbatim: pont.titre(port: p))
                                Text(verbatim: p.chemin.replacingOccurrences(of: "/dev/cu.", with: ""))
                            } icon: {
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 2 sur 2. Remplacer :

````swift
        switch pont.source {
        case .demo: "Démo"
        case .serie(let chemin, let serie): pont.libelleSource(chemin: chemin, serie: serie)
        case nil: "Choisir une source…"
        }
````

par :

````swift
        switch pont.source {
        case .demo: "Démo"
        case .serie(let chemin, let serie): pont.titre(serie: serie, chemin: chemin)
        case .reseau(let nom): pont.titre(reseau: nom)
        case nil: "Choisir une source…"
        }
````

`apps/macos/project.yml`, bloc 1 sur 1. Remplacer :

````yaml
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
````

par :

````yaml
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        INFOPLIST_KEY_NSLocalNetworkUsageDescription: "Amaran Compagnon parle au pont amaran par le réseau Thread de la maison (UDP, par les routeurs de bordure)."
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
````

- [ ] **Step 4 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `Test run with 193 tests in 25 suites passed` (`AmaranProtocoleTests`) et `Test run with 45 tests in 7 suites passed` (`AmaranCompagnonTests`) ; aucune ligne `error:` ni `warning:`.

- [ ] **Step 5 : commit.**

```bash
git add apps/macos/AmaranCompagnon apps/macos/AmaranCompagnonTests apps/macos/project.yml
git commit -m "$(printf "App compagnon, modele reseau : source Thread, trousseau des ponts, creation de la cle UDP par l'USB, alertes, trames et courbes\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 9: Les écrans : menu Réseau, Graphiques, Trames, Accès réseau Thread, carte ip

**Files:**
- Create: `apps/macos/AmaranCompagnon/Vues/Graphiques.swift`, `apps/macos/AmaranCompagnon/Vues/Trames.swift`, `apps/macos/AmaranCompagnon/Vues/ReglagesAccesReseau.swift`
- Modify: `apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, `apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, `apps/macos/AmaranCompagnon/Vues/Reglages.swift`, `apps/macos/AmaranCompagnon/Vues/Cles.swift`, `apps/macos/AmaranCompagnon/Vues/CommandesEtConsole.swift`
- Create: `apps/macos/AmaranCompagnonTests/VuesTests.swift`

**Interfaces:**
- Consumes : la Task 8 (le modèle `Pont` et ses types).
- Produces : les vues `Graphiques`, `Trames`, `ReglagesAccesReseau` ; le menu Source avec la section « Réseau » et le bandeau `AlerteReseau` (`ContenuPrincipal`) ; la carte « Thread et Matter » avec le bloc `ip` et « Gérer… » (`TableauDeBord`) ; l'onglet des réglages (`Reglages`).

Pourquoi : la spec 3b, section 8.
- **Graphiques** (Swift Charts) : par lampe, la part des relectures répondues et les délais des ordres ; pour le Mesh, les annonces (et celles de notre réseau), la part des NetMIC faux, les refus d'émission ; le tas libre. Fenêtre de 10 s ou d'une minute, durée, « Vider » ; un repère à chaque redémarrage. À distance, un avis propose d'activer les compteurs.
- **Trames** : tableau du trafic décodé, filtres (sens, lampe ou groupe, nature), « Figer », « Vider » ; l'interrupteur envoie `json trames 1|0` ; à distance, le pont les coupe seul au bout de 60 s, et l'écran le dit et propose de prolonger.
- **Réglages, « Accès réseau Thread »** : les ponts connus de ce Mac (nom, empreinte, état de session ; « Oublier… ») ; le pont branché en USB : « aucune clé » et « Activer l'accès réseau… », ou clé connue ou inconnue et « Nouvelle clé… », chacun avec sa confirmation.
- Les tests de cette tâche montent chaque écran avec la démo : ce sont des tests de fumée (le montage ne plante pas) ; la logique qu'ils affichent est testée aux Tasks 6 à 8.

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranCompagnonTests/VuesTests.swift` (contenu complet) :

````swift
// Tests des ecrans du plan 3b-2 (chantier C) : filtres des trames, flux des trames a
// distance, trames du pont simule, etat de session des ponts connus, textes de l'acces
// reseau, et tests de fumee des vues (les monter ne plante pas). Le vrai trousseau et les
// vraies preferences ne servent jamais ; valeurs inventees.
import AmaranProtocole
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import AmaranCompagnon

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite("Filtres des trames")
struct FiltreTramesTests {
    static let ordre = Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: true, intensite: 500, essai: 1, sautes: 0)
    static let demande = Trame(sens: .tx, quoi: .demande, lampe: nil, sautes: 0)
    static let etat1 = Trame(sens: .rx, quoi: .etat, lampe: 1, marche: true, intensite: 500, sautes: 2)
    static let etat2 = Trame(sens: .rx, quoi: .etat, lampe: 2, marche: false, intensite: 0, sautes: 0)
    static let inconnue = Trame(sens: .inconnu, quoi: .inconnu, lampe: 3)

    static let journal: [TrameRecue] = [ordre, demande, etat1, etat2, inconnue].enumerated().map { i, t in
        TrameRecue(id: i, date: t0.addingTimeInterval(Double(i)), trame: t)
    }

    @Test func sansFiltreToutPasseDuPlusRecentAuPlusAncien() {
        let f = FiltreTrames()
        #expect(f.estNeutre)
        #expect(f.appliquer(Self.journal).map(\.id) == [4, 3, 2, 1, 0])
    }

    @Test func parSens() {
        var f = FiltreTrames()
        f.sens = .tx
        #expect(f.appliquer(Self.journal).map(\.id) == [1, 0])
        f.sens = .rx
        #expect(f.appliquer(Self.journal).map(\.id) == [3, 2])
        #expect(!f.estNeutre)
    }

    @Test func parLampeOuGroupe() {
        var f = FiltreTrames()
        f.cible = .lampe(1)
        #expect(f.appliquer(Self.journal).map(\.id) == [2, 0], "ordre et etat de la lampe 1, jamais la demande au groupe")
        f.cible = .groupe
        #expect(f.appliquer(Self.journal).map(\.id) == [1])
        f.cible = .lampe(9)
        #expect(f.appliquer(Self.journal).isEmpty)
    }

    @Test func parNature() {
        var f = FiltreTrames()
        f.quoi = [.etat]
        // L'inconnue n'est jamais cachee : une trace qu'on ne comprend pas ne se filtre pas.
        #expect(f.appliquer(Self.journal).map(\.id) == [4, 3, 2])
        f.quoi = []
        #expect(f.appliquer(Self.journal).map(\.id) == [4])
    }

    @Test func filtresCombines() {
        let f = FiltreTrames(sens: .rx, cible: .lampe(2), quoi: [.etat])
        #expect(f.appliquer(Self.journal).map(\.id) == [3])
    }

    @Test func libellesEtCibles() {
        #expect(FiltreTrames.libelleCible(Self.demande, noms: [:]) == "Groupe")
        #expect(FiltreTrames.libelleCible(Self.ordre, noms: [1: "Lampe bureau"]) == "1 · Lampe bureau")
        #expect(FiltreTrames.libelleCible(Self.ordre, noms: [:]) == "1")
        #expect(SensTrame.tx.fleche == "→" && SensTrame.rx.fleche == "←")
        #expect(QuoiTrame.demande.libelle == "Demande d'état")
    }
}

@Suite("Graphiques : segments")
struct GraphiquesSegmentsTests {
    @Test func unRedemarrageDuPontEstUneRupture() throws {
        var s = SeriesCourbes()
        func sante(_ boot: String, _ heap: Int, _ dt: Double) throws {
            let json = #"{"boot":"\#(boot)","sys":{"heap":\#(heap)}}"#
            let bloc = try JSONDecoder().decode(BlocSante.self, from: Data(json.utf8))
            s.ajouter(.etatSante(bloc), date: t0.addingTimeInterval(dt))
        }
        try sante("AAAA0001", 100, 0)
        try sante("AAAA0001", 90, 2)
        try sante("BBBB0002", 110, 10)
        try sante("BBBB0002", 105, 12)
        try sante("CCCC0003", 120, 20)
        #expect(s.redemarrages == [t0.addingTimeInterval(10), t0.addingTimeInterval(20)])
        #expect(SeriesCourbes().redemarrages.isEmpty)
    }
}

@Suite("Etat de session des ponts", .serialized)
@MainActor
struct EtatSessionTests {
    @Test func libelles() {
        #expect(EtatSessionPont.aucune.libelle == "pas de session")
        #expect(EtatSessionPont.ouverte.libelle == "session ouverte")
        #expect(EtatSessionPont.enCours.libelle == "session en cours d'ouverture")
        #expect(EtatSessionPont.refusee("pas de route IPv6").libelle == "session refusée : pas de route IPv6")
        #expect(AlerteReseau.sansHello.raison.contains("sessions prises"))
        #expect(AlerteReseau.transport(.reseauLocalRefuse).raison == "accès au réseau local refusé")
    }

    /// Le trousseau qui refuse la lecture n'est pas une cle absente : la cle peut y etre
    /// (app recompilee ad hoc, « Refuser » a l'invite).
    @Test func trousseauInaccessibleNestPasUneCleAbsente() {
        #expect(AlerteReseau.trousseau(.absente(PontReseauTests.nom)).raison == "clé absente de ce Mac")
        #expect(AlerteReseau.trousseau(.systeme(-25293)).raison == "trousseau inaccessible")
        #expect(EtatSessionPont.refusee(AlerteReseau.trousseau(.systeme(-25293)).raison).libelle
                == "session refusée : trousseau inaccessible")
    }

    /// La cle absente de ce Mac : le pont en garde souvent une (« Nouvelle cle... ») ;
    /// « Activer l'acces reseau... » seulement s'il n'en a pas.
    @Test func cleAbsenteDitLeBonBouton() {
        let texte = ErreurTrousseauPonts.absente(PontReseauTests.nom).description
        #expect(texte.contains("puis « Nouvelle clé… » (« Activer l'accès réseau… » si le pont n'a pas de clé)"))
    }

    @Test func cleAbsenteEstUneSessionRefusee() throws {
        let (pont, _) = try PontReseauTests.pont(cle: nil)
        defer { pont.deconnecter() }
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .aucune)
        pont.connecter(.reseau(nom: PontReseauTests.nom))
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .refusee("clé absente de ce Mac"))
        #expect(pont.etatSession(pour: "0000000000000000") == .aucune, "un autre pont n'est pas la source")
    }

    @Test func sessionOuvertePuisFermee() async throws {
        let (pont, _) = try PontReseauTests.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: PontReseauTests.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: PontReseauTests.nom))
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .enCours)
        try await PontReseauTests.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .ouverte)
        #expect(pont.etatSession(pour: "0000000000000000") == .aucune)
        pont.deconnecter()
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .aucune)
    }
}

@Suite("Acces reseau Thread : textes", .serialized)
@MainActor
struct AccesReseauTextesTests {
    /// Relecture M6 : un pont connecte par l'USB sans nom SRP n'est pas « pas de pont ».
    @Test func sansAccesReseauDistingueLesCas() {
        let sansPont = Pont.texteSansAccesReseau(parUSB: false, udpAnnonce: true, ipRecu: true, srpConnu: true)
        #expect(sansPont.hasPrefix("Brancher le pont en USB"))
        let sansSrp = Pont.texteSansAccesReseau(parUSB: true, udpAnnonce: true, ipRecu: true, srpConnu: false)
        #expect(sansSrp.hasPrefix("Pont connecté par l'USB, nom SRP inconnu : le pont doit d'abord rejoindre le réseau Thread (être dans Maison)"))
        #expect(!sansSrp.contains("Brancher"))
        #expect(Pont.texteSansAccesReseau(parUSB: true, udpAnnonce: false, ipRecu: false, srpConnu: false).contains("capacité udp absente"))
        #expect(Pont.texteSansAccesReseau(parUSB: true, udpAnnonce: true, ipRecu: false, srpConnu: false).contains("bloc ip attendu"))
    }

    /// Le pont simule (USB) annonce son nom SRP : la section gere la cle, aucun de ces textes.
    @Test func demoAvecUnNomSRP() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(await attendre { p.etat.ip != nil })
        #expect(p.accesReseau != .inconnu)
    }

    /// Relecture M4 : sans cle, rien ne tombe ; le texte de « Nouvelle cle... » ne change pas.
    @Test func confirmationsDeLaCle() {
        let sans = AccesReseau.texteConfirmation(sansCle: true)
        #expect(sans == "Le pont crée sa clé et ouvre le port 5480 ; la clé est rangée dans le trousseau de ce Mac.")
        #expect(!sans.contains("tombent"))
        #expect(AccesReseau.texteConfirmation(sansCle: false).hasPrefix("Le pont remplace sa clé : les sessions réseau en cours tombent"))
    }
}

@Suite("Flux des trames a distance", .serialized)
@MainActor
struct FluxTramesDistantTests {
    /// Le pont coupe `json trames 1` seul 60 s apres la demande, sans le dire : l'app le
    /// deduit de l'horloge, un nouveau `json trames 1` repart pour 60 s, et un `hello` qui
    /// dit `trames` faux ramene l'etat a coupe.
    @Test func coupureAu60sEtRelance() async throws {
        let (pont, _) = try PontReseauTests.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: PontReseauTests.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: PontReseauTests.nom))
        try await PontReseauTests.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(!pont.tramesActives)
        #expect(!pont.tramesCoupeesParLePont())
        #expect(pont.secondesAvantCoupureDesTrames() == nil)

        pont.activerTrames(true)
        try #require(await attendre { f.numero(de: "json trames 1") != nil })
        let n = try #require(f.numero(de: "json trames 1"))
        f.injecter(#"{"v":1,"t":"reponse","n":3,"ms":901000,"id":\#(n),"etape":"fin","cmd":"json trames 1","ok":true,"code":"ok","duree_ms":1}"#)
        try #require(await attendre { pont.tramesActives })
        let demande = try #require(pont.tramesDemandeesLe)
        #expect(!pont.tramesCoupeesParLePont(a: demande.addingTimeInterval(59)))
        #expect(pont.secondesAvantCoupureDesTrames(a: demande.addingTimeInterval(20)) == 40)
        #expect(pont.tramesCoupeesParLePont(a: demande.addingTimeInterval(60)))
        #expect(pont.secondesAvantCoupureDesTrames(a: demande.addingTimeInterval(61)) == nil, "deja coupe")

        // « Relancer » : un nouveau json trames 1 repart pour 60 s.
        try await Task.sleep(for: .milliseconds(10))
        pont.activerTrames(true)
        let relance = try #require(pont.tramesDemandeesLe)
        #expect(relance > demande)
        #expect(!pont.tramesCoupeesParLePont(a: relance.addingTimeInterval(30)))

        // Un hello qui dit `trames` faux : le flux n'est plus demande.
        f.injecter(#"{"v":1,"t":"hello","n":4,"ms":960000,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","boot":"3FA2C901","up_s":960,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false}}"#)
        #expect(await attendre { !pont.tramesActives })
        #expect(!pont.tramesCoupeesParLePont(a: relance.addingTimeInterval(500)), "plus rien a couper")
    }

    @Test func parLUsbLeFluxNeSeCoupePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        #expect(p.tramesDemandeesLe != nil)
        #expect(!p.tramesCoupeesParLePont(a: .distantFuture))
        #expect(p.secondesAvantCoupureDesTrames() == nil)
    }
}

@Suite("Trames du pont simule", .serialized)
@MainActor
struct TramesDeLaDemoTests {
    /// Rien sans `json trames 1` ; avec : la demande d'etat au groupe, l'ordre vers la
    /// lampe, l'etat qu'elle renvoie ; plus rien apres `json trames 0`.
    @Test func ordreDemandeEtEtat() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(!p.tramesActives)
        #expect(p.trames.elements.isEmpty)
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        #expect(await attendre { p.trames.elements.contains { $0.trame.quoi == .demande && $0.trame.lampe == nil } },
                "relecture periodique : demande au groupe")
        #expect(await attendre { p.trames.elements.contains { $0.trame.sens == .rx && $0.trame.quoi == .etat } })

        p.allumer(lampe: 1, false)
        #expect(await attendre {
            p.trames.elements.contains { $0.trame == Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: false, intensite: nil, essai: 1, sautes: 0) }
        })
        #expect(await attendre {
            p.trames.elements.contains { $0.trame == Trame(sens: .rx, quoi: .etat, lampe: 1, marche: false, intensite: 500, sautes: 0) }
        }, "la lampe renvoie son etat, coherent avec l'ordre")
        #expect(await attendre { p.lampes[0].dernierOrdre?.issue == .confirme })

        // L'ordre precede l'etat qui le confirme.
        let ordre = try #require(p.trames.elements.firstIndex { $0.trame.quoi == .ordre && $0.trame.lampe == 1 })
        let etat = try #require(p.trames.elements.lastIndex { $0.trame.quoi == .etat && $0.trame.lampe == 1 && $0.trame.marche == false })
        #expect(ordre < etat)
        #expect(Interpretation.trame(p.trames.elements[ordre].trame) == "→ lampe 1 : ordre éteinte (essai 1)")

        // `lampe 2 releve` : demande, puis l'etat de cette lampe seulement.
        let avant = p.trames.elements.count
        p.relire(lampe: 2)
        #expect(await attendre { p.trames.elements.dropFirst(avant).contains { $0.trame.sens == .rx && $0.trame.lampe == 2 } })

        // Plus de flux apres json trames 0 : un ordre de plus, aucune trame de plus.
        p.activerTrames(false)
        #expect(await attendre { !p.tramesActives })
        let figees = p.trames.elements.count
        p.allumer(lampe: 1, true)
        #expect(await attendre { p.lampes[0].dernierOrdre?.issue == .confirme && p.lampes[0].etat?.lue?.marche == true })
        #expect(p.trames.elements.count == figees)
    }

    /// Un ordre « deja tenu » n'envoie rien a la lampe : aucune trame.
    @Test func ordreDejaTenuSansTrame() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        p.allumer(lampe: 2, false)  // deja eteinte
        #expect(await attendre { p.suivis.last?.etat == .tenue })
        #expect(!p.trames.elements.contains { $0.trame.quoi == .ordre })
    }

    /// Lampe jamais entendue : l'ordre part aux essais 1, 2 et 3, puis l'abandon. Temps
    /// reel (la lampe ne repond qu'apres 15 s simulees).
    @Test func ordreSansReponseTroisEssais() async throws {
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                     trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                     preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        p.vitesseDemo = 1
        p.connecter(.demo)
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        p.allumer(lampe: 3, true)
        #expect(await attendre(.seconds(20)) { p.lampes[2].dernierOrdre?.issue == .abandon })
        let essais = p.trames.elements.filter { $0.trame.quoi == .ordre && $0.trame.lampe == 3 }.map(\.trame.essai)
        #expect(essais == [1, 2, 3])
        #expect(!p.trames.elements.contains { $0.trame.sens == .rx && $0.trame.lampe == 3 }, "la lampe ne repond pas")
    }
}

/// Tests de fumee : monter la vue ne plante pas. Chaque vue est hebergee dans une fenetre
/// hors ecran et mise en page, avec les donnees du pont simule, d'une session distante ou
/// sans rien recu (ni bloc `ip`, ni trame, ni point manquant ne doit l'arreter). Ils ne
/// verifient rien du contenu ni du dessin : la taille d'une vue cadree est toujours celle
/// du cadre, et `ImageRenderer` ne sait pas rendre les tables d'AppKit.
@Suite("Fumee : monter les vues ne plante pas", .serialized)
@MainActor
struct FumeeVuesTests {
    /// Monter la vue ne plante pas : fenetre hors ecran, mise en page forcee.
    private func monter<V: View>(_ vue: V, _ pont: Pont) {
        let h = NSHostingView(rootView: vue.environment(pont).frame(width: 900, height: 700))
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: true)
        fenetre.contentView = h
        h.layoutSubtreeIfNeeded()
        fenetre.contentView = nil
    }

    @Test func monterGraphiquesNePlantePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        try #require(await connecte(p))
        p.allumer(lampe: 1, false)
        try #require(await attendre { !p.courbes.tas.isEmpty && !p.courbes.ordres.isEmpty })
        monter(Graphiques(), p)
    }

    @Test func monterTramesNePlantePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        try #require(await connecte(p))
        p.activerTrames(true)
        try #require(await attendre { p.trames.elements.contains { $0.trame.quoi == .etat } })
        monter(Trames(), p)
    }

    @Test func monterTableauEtReglagesNePlantePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        try #require(await connecte(p))
        try #require(await attendre { p.etat.ip?.valeur.srp == SimulateurDemo.srpDemo })
        monter(TableauDeBord(), p)
        monter(ReglagesAccesReseau(), p)
        monter(FenetreReglages(), p)
    }

    /// Session distante : compteurs non releves, pont hors service sans codes d'appairage
    /// (`code_manuel` et `qr` a null a distance).
    @Test func monterLesVuesADistanceNePlantePas() async throws {
        let (p, _) = try PontReseauTests.pont()
        defer { p.deconnecter() }
        let f = TransportFactice(hote: PontReseauTests.nom + ".local")
        p.fabriqueReseau = { _, _ in f }
        p.connecter(.reseau(nom: PontReseauTests.nom))
        try await PontReseauTests.repondreAuJson1(f)
        try #require(await attendre { p.phase == .connecte })
        f.injecter(#"{"v":1,"t":"reseau","n":3,"ms":900200,"bloc":"matter","demarre":true,"fabriques":0,"ble":false,"identifie":false,"abonnements":{"demandes":0,"plafonnes":0,"etablis":0,"termines":0,"plafond_s":20},"code_manuel":null,"qr":null}"#)
        try #require(await attendre { p.etat.enService == false })
        monter(TableauDeBord(), p)
        monter(Graphiques(), p)
        monter(ReglagesAccesReseau(), p)
    }

    @Test func monterSansRienRecuNePlantePas() throws {
        let (p, _) = try PontReseauTests.pont()
        monter(Graphiques(), p)
        monter(Trames(), p)
        monter(ReglagesAccesReseau(), p)
        monter(ContenuPrincipal(), p)
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `TEST FAILED` : `cannot find 'AccesReseau' in scope`, `cannot find 'Graphiques' in scope`, `cannot find 'Trames' in scope`, `cannot find 'ReglagesAccesReseau' in scope`…

- [ ] **Step 3 : le code.**

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 1 sur 13. Remplacer :

````swift
// Repris de Halo Compagnon (commit e114cd5) : fenetre, bandeaux, panneau de connexion.
// Deux ecrans en 3b-1 (les graphiques et les trames viendront au plan 3b-2).
import AmaranProtocole
import SwiftUI

enum Ecran: String, CaseIterable, Identifiable {
    case tableau, commandes

    var id: String { rawValue }
````

par :

````swift
// Repris de Halo Compagnon (commit e114cd5) : fenetre, bandeaux, panneau de connexion.
// Quatre ecrans : tableau de bord, graphiques, trames, commandes et console.
import AmaranProtocole
import SwiftUI

enum Ecran: String, CaseIterable, Identifiable {
    case tableau, graphiques, trames, commandes

    var id: String { rawValue }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 2 sur 13. Remplacer :

````swift
        switch self {
        case .tableau: "Tableau de bord"
        case .commandes: "Commandes et console"
        }
````

par :

````swift
        switch self {
        case .tableau: "Tableau de bord"
        case .graphiques: "Graphiques"
        case .trames: "Trames"
        case .commandes: "Commandes et console"
        }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 3 sur 13. Remplacer :

````swift
        switch self {
        case .tableau: "gauge.with.dots.needle.33percent"
        case .commandes: "slider.horizontal.3"
        }
````

par :

````swift
        switch self {
        case .tableau: "gauge.with.dots.needle.33percent"
        case .graphiques: "chart.xyaxis.line"
        case .trames: "dot.radiowaves.left.and.right"
        case .commandes: "slider.horizontal.3"
        }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 4 sur 13. Remplacer :

````swift
        } detail: {
            VStack(spacing: 0) {
                if let alerte = pont.alerte {
                    Bandeau(texte: alerte.texte, couleur: .red, icone: "exclamationmark.octagon.fill")
                }
````

par :

````swift
        } detail: {
            VStack(spacing: 0) {
                if let a = pont.alerteReseau {
                    Bandeau(texte: a.texte, couleur: .red, icone: "network.slash")
                } else if let alerte = pont.alerte {
                    Bandeau(texte: alerte.texte, couleur: .red, icone: "exclamationmark.octagon.fill")
                }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 5 sur 13. Remplacer :

````swift
                    switch ecran {
                    case .tableau: TableauDeBord()
                    case .commandes: CommandesEtConsole()
                    }
````

par :

````swift
                    switch ecran {
                    case .tableau: TableauDeBord()
                    case .graphiques: Graphiques()
                    case .trames: Trames()
                    case .commandes: CommandesEtConsole()
                    }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 6 sur 13. Remplacer :

````swift
            Button("Libérer le port") { pont.libererPort() }
        } message: {
            Text("L'app envoie json 0 et ferme le port (DTR et RTS restent à 0) : idf.py flash pourra flasher. Rien ne se rouvre avant « Reconnecter ».")
        }
    }
````

par :

````swift
            Button("Libérer le port") { pont.libererPort() }
        } message: {
            if pont.source?.estReseau == true {
                Text("L'app envoie json 0 et ferme la session réseau. Rien ne se rouvre avant « Reconnecter ».")
            } else {
                Text("L'app envoie json 0 et ferme le port (DTR et RTS restent à 0) : idf.py flash pourra flasher. Rien ne se rouvre avant « Reconnecter ».")
            }
        }
    }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 7 sur 13. Remplacer :

````swift
                Label("Libérer le port", systemImage: "eject")
            }
            .help("json 0 puis fermeture du port, pour flasher")
            .disabled(pont.phase == .ferme || pont.estDemo)
        }
````

par :

````swift
                Label("Libérer le port", systemImage: "eject")
            }
            .help(pont.source?.estReseau == true
                  ? "json 0 puis fermeture de la session réseau"
                  : "json 0 puis fermeture du port, pour flasher")
            .disabled(pont.phase == .ferme || pont.estDemo)
        }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 8 sur 13. Remplacer :

````swift
}

/// Choix de la source (port USB ou demo) et etat du transport. Aucun port ne
/// s'ouvre sans un clic.
struct PanneauConnexion: View {
    @Environment(Pont.self) private var pont
````

par :

````swift
}

/// Choix de la source (port USB, pont par le reseau ou demo) et etat du transport.
/// Aucun port ni session reseau ne s'ouvre sans un clic.
struct PanneauConnexion: View {
    @Environment(Pont.self) private var pont
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 9 sur 13. Remplacer :

````swift
                            Label {
                                Text(verbatim: pont.titre(port: p))
                                Text(verbatim: p.chemin.replacingOccurrences(of: "/dev/cu.", with: ""))
                            } icon: {
                                Image(systemName: "cpu")
                            }
                        }
````

par :

````swift
                            Label {
                                Text(verbatim: pont.titre(port: p))
                                Text(verbatim: p.chemin)
                            } icon: {
                                Image(systemName: "cpu")
                            }
                        }
                    }
                }
                Section("Réseau") {
                    if pont.pontsConnus.isEmpty {
                        Text("Aucun pont : Réglages › Accès réseau Thread, pont branché en USB")
                    }
                    ForEach(pont.pontsConnus) { p in
                        Button {
                            pont.connecter(.reseau(nom: p.nom))
                        } label: {
                            Label {
                                Text(verbatim: pont.titre(pont: p))
                                Text(verbatim: "\(p.hote) · clé \(p.empreinte)")
                            } icon: {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                            }
                        }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 10 sur 13. Remplacer :

````swift
                }
            } label: {
                Label(libelleSource, systemImage: pont.estDemo ? "play.rectangle" : "cable.connector")
                    .lineLimit(1)
            }
````

par :

````swift
                }
            } label: {
                Label(libelleSource, systemImage: iconeSource)
                    .lineLimit(1)
            }
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 11 sur 13. Remplacer :

````swift
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
````

par :

````swift
                .foregroundStyle(.secondary)
                .lineLimit(3)
                // Trois lignes au plus : le texte entier (sans route IPv6, l'assistant
                // halo-routes) reste lisible au survol.
                .help(Text(verbatim: libelleTransport))

            HStack {
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 12 sur 13. Remplacer :

````swift
    }

    private var libelleSource: String {
        switch pont.source {
````

par :

````swift
    }

    private var iconeSource: String {
        if pont.estDemo { "play.rectangle" } else if pont.source?.estReseau == true { "point.3.connected.trianglepath.dotted" } else { "cable.connector" }
    }

    private var libelleSource: String {
        switch pont.source {
````

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift`, bloc 13 sur 13. Remplacer :

````swift
    private var libelleTransport: String {
        switch pont.etatTransport {
        case .ferme: "Port fermé"
        case .ouverture: "Ouverture…"
        case .ouvert: "Ouvert · \(pont.phase.libelle)"
        case .attente(let prochain, let raison):
            "\(raison)\nRéouverture \(prochain.formatted(.relative(presentation: .numeric)))"
        case .libere: "Port libéré (json 0) : flasher est possible"
        case .erreur(let e): "Erreur : \(e)"
        }
````

par :

````swift
    private var libelleTransport: String {
        switch pont.etatTransport {
        case .ferme: pont.source?.estReseau == true ? "Session réseau fermée" : "Port fermé"
        case .ouverture: "Ouverture…"
        case .ouvert: "Ouvert · \(pont.phase.libelle)"
        case .attente(let prochain, let raison):
            "\(raison)\nRéouverture \(prochain.formatted(.relative(presentation: .numeric)))"
        case .libere:
            pont.source?.estReseau == true ? "Session réseau fermée (json 0)" : "Port libéré (json 0) : flasher est possible"
        case .erreur(let e): "Erreur : \(e)"
        }
````

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, bloc 1 sur 6. Remplacer :

````swift
                        Label("Aucun état reçu", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("Choisir le port du pont (VID 303A) ou le mode démo dans la barre latérale.")
                    } actions: {
                        Button("Lancer la démo") { pont.connecter(.demo) }
````

par :

````swift
                        Label("Aucun état reçu", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text(verbatim: pont.source == nil
                             ? "Choisir le pont dans le menu de la barre latérale : un port USB (VID 303A), un pont « Réseau » joint par Thread, ou le mode démo."
                             : "Rien n'est encore arrivé de cette source : son état est sous le menu de la barre latérale, où se choisit aussi une autre source (port USB, pont « Réseau », démo).")
                    } actions: {
                        Button("Lancer la démo") { pont.connecter(.demo) }
````

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, bloc 2 sur 6. Remplacer :

````swift
        let p = pont.etat.pont?.valeur
        let m = pont.etat.mesh?.valeur
        let c = pont.etat.compteurs?.valeur
        let pret = p?.mesh?.pret == true
        Carte(titre: "Bluetooth Mesh", icone: "point.3.filled.connected.trianglepath.dotted",
````

par :

````swift
        let p = pont.etat.pont?.valeur
        let m = pont.etat.mesh?.valeur
        // A distance, seulement les compteurs du releve en cours : jamais des valeurs
        // figees (bloc d'une session precedente) montrees comme actuelles.
        let c = pont.compteursMeshActuels
        let pret = p?.mesh?.pret == true
        Carte(titre: "Bluetooth Mesh", icone: "point.3.filled.connected.trianglepath.dotted",
````

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, bloc 3 sur 6. Remplacer :

````swift
            if let d = p?.mesh?.diag, d != .ok { LigneInfo("Diagnostic", Interpretation.diag(d), couleur: .red) }
            LigneInfo("Adresse du pont", m?.adresse.map { "0x\($0)" }, mono: true)
            LigneInfo("IV Index", c?.iv.map(String.init))
            LigneInfo("Relecture", m?.releveMs.map { "toutes les \($0 / 1000) s" })
            LigneInfo("Ordres", p?.ordres.map { o in
````

par :

````swift
            if let d = p?.mesh?.diag, d != .ok { LigneInfo("Diagnostic", Interpretation.diag(d), couleur: .red) }
            LigneInfo("Adresse du pont", m?.adresse.map { "0x\($0)" }, mono: true)
            LigneInfo("IV Index", pont.ivIndexMesh?.texte)
            LigneInfo("Relecture", m?.releveMs.map { "toutes les \($0 / 1000) s" })
            LigneInfo("Ordres", p?.ordres.map { o in
````

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, bloc 4 sur 6. Remplacer :

````swift
            LigneInfo("NetMIC faux", c?.netmicFaux.map(String.init), couleur: (c?.netmicFaux ?? 0) > 0 ? .orange : nil)
            LigneInfo("Émis, refus", c.map { "\($0.emis ?? 0), \($0.echecsEmission ?? 0)" })
        }
    }
````

par :

````swift
            LigneInfo("NetMIC faux", c?.netmicFaux.map(String.init), couleur: (c?.netmicFaux ?? 0) > 0 ? .orange : nil)
            LigneInfo("Émis, refus", c.map { "\($0.emis ?? 0), \($0.echecsEmission ?? 0)" })
            noteCompteurs
        }
    }

    /// Source reseau : sans compteurs du releve en cours, les lignes « – » ci-dessus
    /// s'expliquent (la meme phrase que l'ecran Graphiques).
    @ViewBuilder private var noteCompteurs: some View {
        switch pont.etatCompteursMesh {
        case .normal:
            EmptyView()
        case .nonReleves:
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: pont.texteCompteursMesh ?? "")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Activer") { pont.activerCompteursMesh() }
                    .buttonStyle(.link)
                    .disabled(!pont.peutCommander)
                    .help("json compteurs \(CompteursMesh.periodeProposeeMs) : un bloc toutes les 5 s par le réseau")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .demandes:
            Text(verbatim: pont.texteCompteursMesh ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
````

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, bloc 5 sur 6. Remplacer :

````swift
            LigneInfo("Annonce BLE", Format.oui(m?.ble))
            LigneInfo("Identification", Format.oui(m?.identifie))
        }
    }
}
````

par :

````swift
            LigneInfo("Annonce BLE", Format.oui(m?.ble))
            LigneInfo("Identification", Format.oui(m?.identifie))
            if let ip = pont.etat.ip?.valeur {
                Divider()
                BlocIp(ip: ip)
            }
            Divider()
            ResumeAccesReseau()
        }
    }
}

/// Bloc `ip` du pont (5.5) : ce que l'app vise par le reseau Thread, et l'etat du canal
/// UDP (10.2). La cle n'y est jamais : son empreinte seulement.
private struct BlocIp: View {
    let ip: ReseauIp

    var body: some View {
        LigneInfo("Nom réseau", ip.hote, mono: true)
        ForEach(Array((ip.adresses ?? []).enumerated()), id: \.offset) { _, a in
            LigneInfo(a.type.libelle, a.adresse, mono: true)
        }
        if let u = ip.udp {
            LigneInfo("Canal UDP", u.ouvert == true ? "port \(u.port ?? 0) ouvert" : "fermé",
                      couleur: u.ouvert == true ? nil : .secondary)
            LigneInfo("Clé du pont", u.cle == true ? "empreinte \(u.empreinte ?? "?")" : "aucune",
                      couleur: u.cle == true ? nil : .secondary, mono: u.cle == true)
            LigneInfo("Sessions réseau", u.sessions.map(String.init))
            LigneInfo("Reçus · émis", "\(u.recus ?? 0) · \(u.emis ?? 0)")
            LigneInfo("Rejets · perdus", "\(u.rejets ?? 0) · \(u.perdus ?? 0)",
                      couleur: (u.rejets ?? 0) + (u.perdus ?? 0) > 0 ? .orange : nil)
        }
    }
}

private extension Optional where Wrapped == TypeAdresse {
    /// Libelle de la ligne d'une adresse du pont.
    var libelle: String {
        switch self {
        case .omr: "Adresse OMR (réseau local)"
        case .mlEid: "Adresse ML-EID (Thread)"
        case .autre: "Autre adresse"
        case .inconnu, nil: "Adresse"
        }
    }
}

/// Etat de la cle du transport reseau, en lecture seule : la gestion (creer, renouveler,
/// oublier) est dans Reglages › Acces reseau Thread, que ce bouton ouvre.
private struct ResumeAccesReseau: View {
    @Environment(Pont.self) private var pont
    @Environment(\.openSettings) private var ouvrirReglages
    @AppStorage(OngletReglages.cle) private var onglet: OngletReglages = .general

    var body: some View {
        HStack {
            switch pont.accesReseau {
            case .sansCle:
                Text("Accès réseau : aucune clé").foregroundStyle(.secondary)
            case .cleConnue(_, let e):
                Text(verbatim: "Clé \(e) connue de ce Mac").foregroundStyle(.secondary)
            case .cleInconnue(_, let e):
                Text(verbatim: "Clé \(e) inconnue de ce Mac").foregroundStyle(.orange)
            case .inconnu:
                Text("Ponts connus et clés de ce Mac").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Gérer…") {
                onglet = .accesReseau
                ouvrirReglages()
            }
        }
        .font(.callout)
        .controlSize(.small)
    }
}
````

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift`, bloc 6 sur 6. Remplacer :

````swift
                .font(.callout)
            } else {
                Text("Le pont n'est pas encore mis en service ; ses codes d'appairage arrivent avec le bloc réseau.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
````

par :

````swift
                .font(.callout)
            } else {
                // A distance, le pont ne donne jamais ses codes d'appairage (`code_manuel` et
                // `qr` a null, 5.5) : rien de secret ne passe par Thread.
                Text(verbatim: pont.aDistance
                     ? "Le pont n'est pas encore mis en service. Ses codes d'appairage passent par l'USB seulement : le brancher et le connecter (menu Source) pour les afficher."
                     : "Le pont n'est pas encore mis en service ; ses codes d'appairage arrivent avec le bloc réseau.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
````

`apps/macos/AmaranCompagnon/Vues/Graphiques.swift` (contenu complet) :

````swift
// Ecran « Graphiques » (spec 3b, section 8) : les courbes du pont, calculees par
// differences de compteurs successifs (AmaranProtocole.Courbes) ou lues telles quelles
// (SeriesCourbes). Repris des Graphiques de Halo Compagnon (commit e114cd5) : fenetre
// de 10 s ou 1 min, duree affichee, segments (un redemarrage du pont ouvre un nouveau
// segment, jamais une ligne entre deux demarrages), bouton vider.
import AmaranProtocole
import Charts
import SwiftUI

/// Etiquettes de valeurs tracees : des symboles, sans traduction.
private enum Symbole {
    static let serie = "s"
    static let pourcent = "%"
    static let ms = "ms"
}

struct Graphiques: View {
    @Environment(Pont.self) private var pont
    @State private var fenetre: Double = 10
    @State private var duree: Double = 15 * 60

    /// Point trace : une valeur datee d'une serie, dans un segment de `boot`.
    private struct Point: Identifiable {
        let id: String
        let debut: Date
        let fin: Date
        let serie: String
        let segment: Int
        let valeur: Double
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { contexte in
            // L'axe finit au plus recent de l'horloge et du dernier point (lignes datees par
            // `ms`, l'ancre du hello, pas par leur arrivee).
            let c = pont.courbes
            let fin = [contexte.date, c.pont.last?.date, c.mesh.last?.date, c.tas.last?.date]
                .compactMap { $0 }.max() ?? contexte.date
            let debut = duree > 0 ? fin.addingTimeInterval(-duree) : .distantPast
            contenu(debut: debut, fin: fin)
        }
    }

    @ViewBuilder
    private func contenu(debut: Date, fin: Date) -> some View {
        let c = pont.courbes
        // Un trou dans les echantillons (app suspendue, lien perdu) ouvre un segment.
        let ecartMesh = Courbes.ecartMax(periodeMs: pont.reglages?.compteursMs)
        let ecartPont = Courbes.ecartMax(periodeMs: pont.reglages?.periodeMs)
        let dMesh = Courbes.differences(c.mesh, fenetre: fenetre, ecartMax: ecartMesh).filter { $0.fin >= debut }
        let dPont = Courbes.differences(c.pont, fenetre: fenetre, ecartMax: ecartPont).filter { $0.fin >= debut }
        let redemarrages = c.redemarrages.filter { $0 >= debut }
        let lampes = c.lampes
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                reglages
                if c.tas.isEmpty && c.pont.isEmpty && c.mesh.isEmpty && lampes.isEmpty {
                    ContentUnavailableView("Pas encore de courbes", systemImage: "chart.xyaxis.line",
                                           description: Text("Les courbes se tracent au fil des blocs que le pont envoie : connecter le pont, ou lancer la démo."))
                }
                // La meme phrase que la carte « Bluetooth Mesh » du tableau de bord.
                if let texte = pont.texteCompteursMesh {
                    avisCompteurs(texte, demander: pont.etatCompteursMesh == .nonReleves)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 16, alignment: .top)], spacing: 16) {
                    Carte(titre: "Relectures répondues", icone: "arrow.triangle.2.circlepath") {
                        graphePart(lampes: lampes, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Part des relectures de chaque lampe qui ont reçu une réponse sur 10 min (jauge du pont, nulle tant qu'aucune relecture n'a eu lieu).")
                    }
                    Carte(titre: "Délais des ordres", icone: "timer") {
                        grapheDelais(lampes: lampes, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Délai de chaque ordre confirmé ; croix rouge : ordre abandonné (la lampe n'a pas répondu ; à 0 ms : Bluetooth Mesh pas prêt). Pointillé : au-delà d'une seconde, l'ordre est dit lent.")
                    }
                    Carte(titre: "Ordres du pont", icone: "list.number") {
                        grapheOrdres(dPont, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Ordres confirmés et abandonnés par fenêtre de \(Int(fenetre)) s (différences du bloc pont).")
                    }
                    Carte(titre: "Annonces Bluetooth Mesh", icone: "point.3.filled.connected.trianglepath.dotted") {
                        grapheAnnonces(dMesh, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Annonces reçues par fenêtre de \(Int(fenetre)) s, dont celles de notre réseau (nid reconnu).")
                    }
                    Carte(titre: "NetMIC faux", icone: "exclamationmark.shield") {
                        grapheLigne(dMesh.compactMap { d in Courbes.partNetmicFaux(d).map { (d, $0 * 100) } },
                                    serie: "NetMIC faux", unite: Symbole.pourcent, couleur: .orange,
                                    debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Part des annonces de notre réseau dont le NetMIC est faux : un IV Index faux la fait monter vers 100 %. Des clés périmées font tomber à zéro les annonces de notre réseau.")
                    }
                    Carte(titre: "Refus d'émission", icone: "paperplane.circle") {
                        grapheRefus(dMesh, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Émissions refusées par la pile Bluetooth, par fenêtre ; courbe : part des émissions refusées.")
                    }
                    Carte(titre: "Tas libre", icone: "memorychip") {
                        grapheTas(c, debut: debut, fin: fin, redemarrages: redemarrages)
                        legende("Mémoire libre du pont (trait plein) et son plus bas depuis le démarrage (pointillé).")
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Reglages de l'ecran

    private var reglages: some View {
        HStack(spacing: 16) {
            Picker("Fenêtre", selection: $fenetre) {
                Text(verbatim: "10 s").tag(10.0)
                Text(verbatim: "1 min").tag(60.0)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("Durée", selection: $duree) {
                Text(verbatim: "5 min").tag(300.0)
                Text(verbatim: "15 min").tag(900.0)
                Text(verbatim: "1 h").tag(3600.0)
                Text("Tout").tag(0.0)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Text("Un redémarrage du pont, une différence négative ou un trou ouvre un nouveau segment.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Vider les courbes") { pont.viderCourbes() }
                .help("Efface les courbes de l'app seulement : le pont ne change pas")
        }
    }

    /// A distance, le profil du pont coupe les compteurs Mesh : sans eux, trois courbes
    /// ne recoivent plus de point. Les redemander coute des datagrammes, donc seulement
    /// sur demande. `texte` : la phrase de la carte « Bluetooth Mesh » (CompteursMesh).
    private func avisCompteurs(_ texte: String, demander: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
            Text(verbatim: texte + (demander
                ? " : par le réseau, le pont ne les envoie que sur demande ; les courbes d'annonces, de NetMIC faux et de refus ne reçoivent plus de point."
                : "."))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if demander {
                Button("Demander les compteurs") { pont.activerCompteursMesh() }
                    .disabled(!pont.peutCommander)
                    .help("json compteurs \(CompteursMesh.periodeProposeeMs)")
            }
        }
        .font(.callout)
        .padding(10)
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.blue)
    }

    private func legende(_ texte: String) -> some View {
        Text(verbatim: texte).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Donnees

    private func nom(_ lampe: Int) -> String {
        let n = pont.lampes.first { $0.numero == lampe }?.nom ?? "Lampe \(lampe)"
        return "\(lampe) · \(n)"
    }

    /// Axe du temps : la periode choisie, ramenee au premier point s'il est plus recent.
    private func echelle(_ debut: Date, _ fin: Date) -> ClosedRange<Date> {
        let c = pont.courbes
        let premiers = [c.pont.first?.date, c.mesh.first?.date, c.tas.first?.date,
                        c.parts.values.compactMap { $0.first?.date }.min(),
                        c.ordres.values.compactMap { $0.first?.date }.min()].compactMap { $0 }
        let premier = premiers.min() ?? fin.addingTimeInterval(-60)
        return min(max(debut, premier), fin.addingTimeInterval(-30))...fin
    }

    // MARK: - Graphes

    @ChartContentBuilder
    private func reperes(_ dates: [Date]) -> some ChartContent {
        ForEach(dates, id: \.self) { d in
            RuleMark(x: .value("Redémarrage", d))
                .foregroundStyle(.purple.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }

    private func graphePart(lampes: [Int], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let c = pont.courbes
        let noms = lampes.map(nom)
        return Chart {
            ForEach(lampes, id: \.self) { l in
                ForEach(Array((c.parts[l] ?? []).enumerated()), id: \.offset) { _, p in
                    if p.date >= debut, let v = p.valeur {
                        LineMark(x: .value("Heure", p.date), y: .value(Symbole.pourcent, v),
                                 series: .value(Symbole.serie, "\(l)-\(p.segment)"))
                            .foregroundStyle(by: .value("Lampe", nom(l)))
                    }
                }
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(domain: noms, range: Self.palette(noms.count))
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel(Symbole.pourcent)
        .frame(height: 170)
    }

    private func grapheDelais(lampes: [Int], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let c = pont.courbes
        let noms = lampes.map(nom)
        let maxi = lampes.flatMap { c.ordres[$0] ?? [] }.filter { $0.date >= debut }.compactMap(\.delaiMs).max() ?? 0
        return Chart {
            ForEach(lampes, id: \.self) { l in
                ForEach(Array((c.ordres[l] ?? []).enumerated()), id: \.offset) { _, o in
                    if o.date >= debut, let d = o.delaiMs {
                        if o.issue == .confirme {
                            PointMark(x: .value("Heure", o.date), y: .value(Symbole.ms, d))
                                .foregroundStyle(by: .value("Lampe", nom(l)))
                                .symbolSize(28)
                        } else if o.issue == .abandon {
                            PointMark(x: .value("Heure", o.date), y: .value(Symbole.ms, d))
                                .symbol(.cross)
                                .symbolSize(70)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            if maxi > 250 {
                RuleMark(y: .value("Lent", 1000))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(domain: noms, range: Self.palette(noms.count))
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel(Symbole.ms)
        .frame(height: 170)
    }

    private func grapheOrdres(_ d: [Difference], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let confirmes = points(d, "confirmés") { $0[.confirmes].map(Double.init) }
        let abandons = points(d, "abandonnés") { $0[.abandons].map(Double.init) }
        return Chart {
            ForEach((confirmes + abandons).filter { $0.valeur > 0 }) { x in
                BarMark(xStart: .value("Début", x.debut), xEnd: .value("Fin", x.fin), y: .value("par fenêtre", x.valeur))
                    .foregroundStyle(by: .value("Issue", x.serie))
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(["confirmés": Color.green, "abandonnés": Color.red])
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel("par fenêtre")
        .frame(height: 130)
    }

    private func grapheAnnonces(_ d: [Difference], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let toutes = points(d, "annonces") { $0[.annonces].map(Double.init) }
        let notres = points(d, "de notre réseau") { $0[.nidReconnu].map(Double.init) }
        return Chart {
            ForEach(toutes + notres) { p in
                LineMark(x: .value("Heure", p.fin), y: .value("par fenêtre", p.valeur),
                         series: .value(Symbole.serie, "\(p.serie)-\(p.segment)"))
                    .foregroundStyle(by: .value("Annonces", p.serie))
            }
            reperes(redemarrages)
        }
        .chartForegroundStyleScale(["annonces": Color.gray, "de notre réseau": Color.blue])
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel("par fenêtre")
        .frame(height: 130)
    }

    private func grapheLigne(_ valeurs: [(Difference, Double)], serie: String, unite: String, couleur: Color,
                             debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        Chart {
            ForEach(Array(valeurs.enumerated()), id: \.offset) { _, v in
                LineMark(x: .value("Heure", v.0.fin), y: .value(unite, v.1),
                         series: .value(Symbole.serie, "\(serie)-\(v.0.segment)"))
                    .foregroundStyle(couleur)
            }
            reperes(redemarrages)
        }
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel(unite)
        .frame(height: 110)
    }

    private func grapheRefus(_ d: [Difference], debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let echecs = points(d, "refus") { $0[.echecsEmission].map(Double.init) }
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(echecs.filter { $0.valeur > 0 }) { x in
                    BarMark(xStart: .value("Début", x.debut), xEnd: .value("Fin", x.fin), y: .value("par fenêtre", x.valeur))
                        .foregroundStyle(.red)
                }
                reperes(redemarrages)
            }
            .chartXScale(domain: echelle(debut, fin))
            .chartPlotStyle { $0.clipped() }
            .chartYAxisLabel("par fenêtre")
            .frame(height: 90)
            grapheLigne(d.compactMap { x in Courbes.partRefusEmission(x).map { (x, $0 * 100) } },
                        serie: "part des refus", unite: Symbole.pourcent, couleur: .red,
                        debut: debut, fin: fin, redemarrages: redemarrages)
        }
    }

    private func grapheTas(_ c: SeriesCourbes, debut: Date, fin: Date, redemarrages: [Date]) -> some View {
        let libre = c.tas.filter { $0.date >= debut }
        let plusBas = c.tasMin.filter { $0.date >= debut }
        return Chart {
            ForEach(Array(libre.enumerated()), id: \.offset) { _, p in
                if let v = p.valeur {
                    LineMark(x: .value("Heure", p.date), y: .value("Ko", v / 1024),
                             series: .value(Symbole.serie, "tas-\(p.segment)"))
                        .foregroundStyle(.blue)
                }
            }
            ForEach(Array(plusBas.enumerated()), id: \.offset) { _, p in
                if let v = p.valeur {
                    LineMark(x: .value("Heure", p.date), y: .value("Ko", v / 1024),
                             series: .value(Symbole.serie, "min-\(p.segment)"))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            reperes(redemarrages)
        }
        .chartXScale(domain: echelle(debut, fin))
        .chartPlotStyle { $0.clipped() }
        .chartYAxisLabel("Ko")
        .frame(height: 140)
    }

    private func points(_ d: [Difference], _ serie: String, _ f: (Difference) -> Double?) -> [Point] {
        d.enumerated().compactMap { i, x in
            f(x).map { Point(id: "\(serie)-\(i)", debut: x.debut, fin: x.fin, serie: serie, segment: x.segment, valeur: $0) }
        }
    }

    /// Couleurs distinctes pour n lampes (16 au plus) : la teinte fait le tour du cercle.
    private static func palette(_ n: Int) -> [Color] {
        (0..<n).map { Color(hue: Double($0) / Double(max(n, 1)), saturation: 0.65, brightness: 0.85) }
    }
}
````

`apps/macos/AmaranCompagnon/Vues/Trames.swift` (contenu complet) :

````swift
// Ecran « Trames » (spec 3b, section 8) : le trafic Bluetooth Mesh que le pont decode
// (`trame`, 7.6), en tableau filtrable. Repris de TramesEnDirect de Halo Compagnon (commit
// e114cd5) pour le tableau, les filtres et « Figer » ; l'interrupteur du flux est propre a
// amaran : le pont n'emet les trames que sur `json trames 1`, et les coupe seul au bout
// de 60 s a distance (sans le dire : l'app le deduit de l'horloge).
import AmaranProtocole
import SwiftUI

struct Trames: View {
    @Environment(Pont.self) private var pont
    @State private var filtre = FiltreTrames()
    @State private var figees: [TrameRecue]?
    @State private var selection: TrameRecue.ID?

    var body: some View {
        let source = figees ?? pont.trames.elements
        let lignes = filtre.appliquer(source)
        let noms = Dictionary(uniqueKeysWithValues: pont.lampes.map { ($0.numero, $0.nom) })
        VStack(spacing: 0) {
            BarreFlux()
            Divider()
            barreFiltres
            Divider()
            ZStack {
                Table(lignes, selection: $selection) {
                    TableColumn("Heure") { t in
                        Text(verbatim: Format.heure(t.date)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 100, max: 110)
                    TableColumn("Sens") { t in
                        Text(verbatim: "\(t.trame.sens?.fleche ?? "?") \(t.trame.sens?.libelle.lowercased() ?? "")")
                            .foregroundStyle(t.trame.sens == .tx ? Color.teal : Color.blue)
                    }
                    .width(min: 70, ideal: 80, max: 100)
                    TableColumn("Nature") { t in
                        Pastille(texte: t.trame.quoi?.libelle ?? "?", couleur: couleur(t.trame))
                    }
                    .width(min: 100, ideal: 120, max: 150)
                    TableColumn("Lampe") { t in
                        Text(verbatim: FiltreTrames.libelleCible(t.trame, noms: noms))
                            .foregroundStyle(t.trame.lampe == nil ? .secondary : .primary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 160)
                    TableColumn("Marche") { t in
                        Text(verbatim: t.trame.marche.map { $0 ? "allumée" : "éteinte" } ?? "–")
                    }
                    .width(min: 60, ideal: 70, max: 90)
                    TableColumn("Intensité") { t in
                        Text(verbatim: t.trame.intensite.map(Interpretation.intensite) ?? "–").monospacedDigit()
                    }
                    .width(min: 60, ideal: 70, max: 90)
                    TableColumn("Essai") { t in
                        Text(verbatim: t.trame.essai.map(String.init) ?? "–").monospacedDigit()
                    }
                    .width(min: 40, ideal: 50, max: 60)
                    TableColumn("Sautées") { t in
                        Text(verbatim: t.trame.sautes.map(String.init) ?? "–")
                            .monospacedDigit()
                            .foregroundStyle((t.trame.sautes ?? 0) > 0 ? Color.orange : .secondary)
                            .help("Trames non émises par le pont depuis la précédente (plafond de débit)")
                    }
                    .width(min: 55, ideal: 65, max: 80)
                }
                if source.isEmpty {
                    ContentUnavailableView("Aucune trame", systemImage: "dot.radiowaves.left.and.right",
                                           description: Text("Activer « Trames du pont » : le pont décode alors les messages Bluetooth Mesh de ses lampes (ordres et demandes d'état émis, états reçus)."))
                        .background(.background)
                }
            }
            Divider()
            HStack {
                Text("\(lignes.count) affichées sur \(source.count)")
                if figees != nil { Pastille(texte: "affichage figé", couleur: .orange) }
                Spacer()
                Text("Au plus 50 trames par seconde par l'USB, 10 à distance : « Sautées » compte les absentes.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var barreFiltres: some View {
        HStack(spacing: 10) {
            Picker("Sens", selection: $filtre.sens) {
                Text("Tous").tag(SensTrame?.none)
                Text(verbatim: "→ émises").tag(SensTrame?.some(.tx))
                Text(verbatim: "← reçues").tag(SensTrame?.some(.rx))
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("Lampe", selection: $filtre.cible) {
                Text("Toutes les lampes").tag(FiltreTrames.Cible.toutes)
                Text("Groupe").tag(FiltreTrames.Cible.groupe)
                Divider()
                ForEach(pont.lampes) { l in
                    Text(verbatim: "\(l.numero) · \(l.nom)").tag(FiltreTrames.Cible.lampe(l.numero))
                }
            }
            .fixedSize()
            Menu {
                ForEach([QuoiTrame.ordre, .demande, .etat], id: \.self) { q in
                    Toggle(q.libelle, isOn: Binding(
                        get: { filtre.quoi.contains(q) },
                        set: { if $0 { filtre.quoi.insert(q) } else { filtre.quoi.remove(q) } }))
                }
                Divider()
                Button("Toutes") { filtre.quoi = [.ordre, .demande, .etat] }
            } label: {
                Label("Nature (\(filtre.quoi.count))", systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
            if !filtre.estNeutre {
                Button("Effacer les filtres") { filtre = FiltreTrames() }
                    .controlSize(.small)
            }
            Spacer()
            Button {
                figees = figees == nil ? pont.trames.elements : nil
            } label: {
                Label(figees == nil ? "Figer" : "Reprendre", systemImage: figees == nil ? "pause" : "play")
            }
            .help("Figer l'affichage sans rien demander au pont : les trames continuent d'être gardées")
            Button("Vider") {
                pont.viderTrames()
                figees = nil
                selection = nil
            }
            .disabled(pont.trames.elements.isEmpty && figees == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func couleur(_ t: Trame) -> Color {
        switch t.quoi {
        case .ordre: .teal
        case .demande: .gray
        case .etat: .blue
        case .inconnu, nil: .secondary
        }
    }
}

/// Interrupteur du flux : `json trames 1|0`. A distance, le pont coupe le flux 60 s apres
/// la demande sans le dire ; la barre le deduit de l'horloge et propose de relancer.
private struct BarreFlux: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexte in
            let coupe = pont.tramesCoupeesParLePont(a: contexte.date)
            let reste = pont.secondesAvantCoupureDesTrames(a: contexte.date)
            let capable = pont.etat.a(.trames)
            HStack(spacing: 10) {
                Toggle("Trames du pont", isOn: Binding(
                    get: { pont.tramesActives && !coupe },
                    set: { pont.activerTrames($0) }))
                    .toggleStyle(.switch)
                    .disabled(!pont.peutEnvoyer("json trames 1") || !capable)
                    .help("json trames 1 ou 0 : le trafic Bluetooth Mesh en messages « trame »")
                if coupe {
                    Pastille(texte: "coupé par le pont après 60 s", couleur: .orange)
                    Button("Relancer") { pont.activerTrames(true) }
                        .controlSize(.small)
                        .disabled(!pont.peutEnvoyer("json trames 1"))
                } else if let reste {
                    Pastille(texte: "coupure dans \(reste) s", couleur: .blue)
                    Button("Prolonger") { pont.activerTrames(true) }
                        .controlSize(.small)
                        .help("Renvoie json trames 1 : le pont repart pour 60 s")
                } else if pont.tramesActives {
                    Pastille(texte: "flux actif", couleur: .green)
                } else if pont.peutCommander && !capable {
                    Pastille(texte: "ce pont n'annonce pas les trames", couleur: .secondary)
                } else {
                    Pastille(texte: "flux coupé", couleur: .secondary)
                }
                Spacer()
                if let t = pont.derniereTrame {
                    Text("Dernière trame \(Format.heure(t))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    let actif = pont.tramesActives && !coupe
                    Button(actif ? "Couper les trames (json trames 0)" : "Reprendre les trames (json trames 1)") {
                        pont.activerTrames(!actif)
                    }
                    .disabled(!pont.peutEnvoyer("json trames 1") || !pont.etat.a(.trames))
                    Divider()
                    Button("Annonces en messages log (json log 1)") { pont.envoyer("json log 1") }
                        .disabled(!pont.peutEnvoyer("json log 1") || !pont.etat.a(.log) || pont.reglages?.log == true)
                    Button("Annonces en texte (json log 0)") { pont.envoyer("json log 0") }
                        .disabled(!pont.peutEnvoyer("json log 0") || !pont.etat.a(.log) || pont.reglages?.log == false)
                } label: {
                    Label("Flux", systemImage: "antenna.radiowaves.left.and.right")
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
````

`apps/macos/AmaranCompagnon/Vues/Reglages.swift`, bloc 1 sur 1. Remplacer :

````swift
// Fenetre Reglages (spec 3b, section 8) : l'onglet General (l'onglet « Acces reseau
// Thread » viendra au plan 3b-2, comme celui de Halo Compagnon).
import AmaranProtocole
import SwiftUI

struct FenetreReglages: View {
    var body: some View {
        TabView {
            Tab("Général", systemImage: "gearshape") {
                ReglagesGeneral()
            }
        }
````

par :

````swift
// Fenetre Reglages (spec 3b, section 8) : General, et « Acces reseau Thread » (comme
// Halo Compagnon, commit e114cd5).
import AmaranProtocole
import SwiftUI

/// Onglets de la fenetre Reglages ; le choix est garde, et la carte « Thread et Matter »
/// du tableau de bord ouvre directement « Acces reseau Thread ».
enum OngletReglages: String {
    case general, accesReseau
    static let cle = "reglages.onglet"
}

struct FenetreReglages: View {
    @AppStorage(OngletReglages.cle) private var onglet: OngletReglages = .general

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Général", systemImage: "gearshape", value: OngletReglages.general) {
                ReglagesGeneral()
            }
            Tab("Accès réseau Thread", systemImage: "point.3.connected.trianglepath.dotted",
                value: OngletReglages.accesReseau) {
                ReglagesAccesReseau()
            }
        }
````

`apps/macos/AmaranCompagnon/Vues/ReglagesAccesReseau.swift` (contenu complet) :

````swift
// Reglages › Acces reseau Thread (spec 3b, section 8), repris de ReglagesAccesReseau de Halo
// Compagnon (commit e114cd5) : les ponts dont ce Mac a la cle, avec l'etat de leur
// session, et la cle du pont branche en USB (10.2 : la cle ne passe que par l'USB).
import AmaranProtocole
import SwiftUI

struct ReglagesAccesReseau: View {
    @Environment(Pont.self) private var pont
    @State private var aOublier: PontConnu?

    var body: some View {
        Form {
            Section {
                if pont.pontsConnus.isEmpty {
                    Text("Aucun pont : brancher un pont en USB, le connecter (menu Source), puis « Activer l'accès réseau… » ci-dessous (« Nouvelle clé… » si le pont a déjà une clé).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(pont.pontsConnus) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: pont.titre(pont: p))
                            Text(verbatim: "\(p.hote) · clé \(p.empreinte)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LigneSession(etat: pont.etatSession(pour: p.nom))
                        }
                        Spacer()
                        Button("Oublier…", role: .destructive) { aOublier = p }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Ponts connus de ce Mac")
            } footer: {
                Text("Le pont garde sa clé : l'oublier ne la change pas, mais ce Mac ne peut plus ouvrir de session réseau avec lui.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                if pont.accesReseau == .inconnu {
                    // Pas de pont par l'USB, ou un pont connecte sans nom SRP (pas encore
                    // dans le reseau Thread) : les deux cas se disent differemment.
                    Text(verbatim: pont.texteSansAccesReseau)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AccesReseau()
                }
            } header: {
                Text("Pont branché en USB")
            } footer: {
                Text("La clé ne passe que par l'USB. Elle est rangée dans le trousseau de ce Mac, sans jamais être affichée : seule son empreinte l'est. À la première session réseau, macOS demande l'accès au réseau local.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Oublier ce pont ?", isPresented: Binding(get: { aOublier != nil }, set: { if !$0 { aOublier = nil } }),
                            presenting: aOublier) { p in
            Button("Oublier \(p.hote)", role: .destructive) { pont.oublierPont(p.nom) }
        } message: { p in
            Text("La clé de \(p.hote) est retirée du trousseau de ce Mac ; le pont garde la sienne. Si ce pont est la source en cours, la session réseau se ferme. Pour revenir : brancher le pont en USB, puis « Nouvelle clé… » (« Activer l'accès réseau… » si le pont n'a pas de clé).")
        }
    }
}

/// Etat de la session d'un pont connu, avec sa couleur.
private struct LigneSession: View {
    let etat: EtatSessionPont

    var body: some View {
        Label {
            Text(verbatim: etat.libelle)
        } icon: {
            Image(systemName: icone)
        }
        .font(.caption)
        .foregroundStyle(couleur)
    }

    private var icone: String {
        switch etat {
        case .aucune: "circle"
        case .enCours: "circle.dotted"
        case .ouverte: "checkmark.circle.fill"
        case .refusee: "exclamationmark.triangle.fill"
        }
    }

    private var couleur: Color {
        switch etat {
        case .aucune: .secondary
        case .enCours: .orange
        case .ouverte: .green
        case .refusee: .red
        }
    }
}

/// Cle du transport reseau du pont branche en USB (10.2) : etat et creation.
struct AccesReseau: View {
    @Environment(Pont.self) private var pont
    @State private var confirmation = false

    var body: some View {
        HStack {
            switch pont.accesReseau {
            case .sansCle:
                Text("Accès réseau : aucune clé").foregroundStyle(.secondary)
                Spacer()
                Button("Activer l'accès réseau…") { confirmation = true }
            case .cleConnue(_, let e):
                Text(verbatim: "Clé \(e) connue de ce Mac").foregroundStyle(.secondary)
                Spacer()
                Button("Nouvelle clé…") { confirmation = true }
            case .cleInconnue(_, let e):
                Text(verbatim: "Clé \(e) inconnue de ce Mac").foregroundStyle(.orange)
                Spacer()
                Button("Nouvelle clé…") { confirmation = true }
            case .inconnu:
                EmptyView()
            }
        }
        .font(.callout)
        .controlSize(.small)
        .disabled(!pont.peutCommander || pont.aDistance || pont.creationCleEnCours)
        .confirmationDialog(titreConfirmation, isPresented: $confirmation) {
            Button(sansCle ? "Activer l'accès réseau" : "Créer la nouvelle clé") { pont.creerCle() }
        } message: {
            Text(verbatim: Self.texteConfirmation(sansCle: sansCle))
        }
    }

    /// Le pont sans cle n'a ni port ouvert ni session : rien ne tombe. Avec une cle, il la
    /// remplace, et toute session en cours tombe (10.2).
    static func texteConfirmation(sansCle: Bool) -> String {
        sansCle
            ? "Le pont crée sa clé et ouvre le port 5480 ; la clé est rangée dans le trousseau de ce Mac."
            : "Le pont remplace sa clé : les sessions réseau en cours tombent, y compris celles d'autres Mac ou de scripts, qui devront obtenir la nouvelle clé par l'USB. La nouvelle clé est rangée dans le trousseau de ce Mac."
    }

    private var sansCle: Bool {
        if case .sansCle = pont.accesReseau { true } else { false }
    }

    private var titreConfirmation: String {
        sansCle ? "Activer l'accès réseau ?" : "Créer une nouvelle clé réseau ?"
    }
}
````

`apps/macos/AmaranCompagnon/Vues/Cles.swift`, bloc 1 sur 1. Remplacer :

````swift
                        .disabled(pont.copie == nil)
                }
                .disabled(!pont.peutCommander || pont.chargement.actif)
                .fixedSize()
            }
````

par :

````swift
                        .disabled(pont.copie == nil)
                }
                .disabled(!pont.peutCommander || pont.aDistance || pont.chargement.actif)
                .help(pont.aDistance ? "Le chargement des clés passe par l'USB : le pont le refuse par le réseau." : "")
                .fixedSize()
            }
````

`apps/macos/AmaranCompagnon/Vues/CommandesEtConsole.swift`, bloc 1 sur 2. Remplacer :

````swift
                    }
                    Button("Appliquer") { pont.reglerReleve(secondes: releve) }
                        .disabled(pont.etat.mesh?.valeur.releveMs == releve * 1000)
                }
                Carte(titre: "Commandes récentes", icone: "list.bullet.rectangle") {
````

par :

````swift
                    }
                    Button("Appliquer") { pont.reglerReleve(secondes: releve) }
                        .disabled(pont.etat.mesh?.valeur.releveMs == releve * 1000 || !pont.peutEnvoyer("mesh releve \(releve)"))
                    if pont.aDistance {
                        Text("Par le réseau, le pont refuse ce réglage (liste blanche) : le faire par l'USB.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Carte(titre: "Commandes récentes", icone: "list.bullet.rectangle") {
````

`apps/macos/AmaranCompagnon/Vues/CommandesEtConsole.swift`, bloc 2 sur 2. Remplacer :

````swift
                if let erreur {
                    Text(verbatim: erreur).foregroundStyle(.red)
                } else if !pont.consoleAvecId, pont.phase != .ferme {
                    Text(verbatim: "Console seule (\(pont.phase.libelle)) : lignes envoyées sans id, sans corrélation.")
````

par :

````swift
                if let erreur {
                    Text(verbatim: erreur).foregroundStyle(.red)
                } else if pont.aDistance {
                    Text("Par le réseau, le pont n'accepte qu'une liste de commandes (les autres ne partent pas) ; le texte d'une commande revient rattaché à son id.")
                        .foregroundStyle(.secondary)
                } else if !pont.consoleAvecId, pont.phase != .ferme {
                    Text(verbatim: "Console seule (\(pont.phase.libelle)) : lignes envoyées sans id, sans corrélation.")
````

- [ ] **Step 4 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E 'error:|warning:|Test run with|TEST (SUCCEEDED|FAILED)' | /usr/bin/grep -v appintentsmetadataprocessor; cd ../..`
Expected: `Test run with 193 tests in 25 suites passed` (`AmaranProtocoleTests`) et `Test run with 70 tests in 14 suites passed` (`AmaranCompagnonTests`) ; aucune ligne `error:` ni `warning:`.

- [ ] **Step 5 : commit.**

```bash
git add apps/macos/AmaranCompagnon apps/macos/AmaranCompagnonTests
git commit -m "$(printf "App compagnon, ecrans du plan 3b-2 : menu Reseau, graphiques, trames, acces reseau Thread, carte ip\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 10: La documentation : README, README de l'app, la spec

**Files:**
- Modify: `README.md`, `apps/macos/README.md`, `docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`

**Interfaces:**
- Consumes : tout ce qui précède.
- Produces : la documentation à jour ; la spec porte les choix fixés en préparant ce plan (section « Choix fixés » de l'en-tête).

Pourquoi : la spec est l'autorité du plan ; ce que le prototype a établi (essai radio, liste blanche sur les mots de la console, réglage du débit, identité des sessions, tâche `distant`, console sans hôte USB) y entre, pour que la suite (plan 3c) parte de faits. Les README disent comment se servir de l'accès par Thread, et ce qui reste réservé à l'USB.

- [ ] **Step 1 : le README.**

`README.md`, bloc 1 sur 4. Remplacer :

````markdown
## L'app compagnon

Amaran Compagnon (`apps/macos`) supervise et pilote le pont par l'USB : une carte par lampe, le Bluetooth Mesh, Matter, le voyant, et la console du pont. Elle gère aussi les clés du réseau des lampes, à la place de `outils/cles_amaran.py` :
- elle lit la base d'amaran Desktop, sans jamais y écrire (Réglages, « Changer… » : désigner une fois le dossier `amaran Desktop` de `~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support`) ;
- elle en garde une copie dans le trousseau de ce Mac, et l'exporte sur demande en sauvegarde chiffrée par une phrase de passe (iCloud Drive conseillé) ;
- elle charge le pont par l'USB, vérifie ses empreintes et sa liste, puis le redémarre ;
- elle compare les empreintes de la base, de la copie et du pont, sans jamais montrer une clé.

Le mode démo (menu de la barre latérale, ou Fichier › Mode démo, ⇧⌘D) simule un pont à trois lampes, sans matériel. Compiler : voir [apps/macos/README.md](apps/macos/README.md).
````

par :

````markdown
## L'app compagnon

Amaran Compagnon (`apps/macos`) supervise et pilote le pont par l'USB, ou à distance par le réseau Thread de la maison : une carte par lampe, le Bluetooth Mesh, Matter, le voyant, la console du pont, des graphiques et les trames du Bluetooth Mesh décodées. Elle gère aussi les clés du réseau des lampes, à la place de `outils/cles_amaran.py` :
- elle lit la base d'amaran Desktop, sans jamais y écrire (Réglages, « Changer… » : désigner une fois le dossier `amaran Desktop` de `~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support`) ;
- elle en garde une copie dans le trousseau de ce Mac, et l'exporte sur demande en sauvegarde chiffrée par une phrase de passe (iCloud Drive conseillé) ;
- elle charge le pont par l'USB, vérifie ses empreintes et sa liste, puis le redémarre ;
- elle compare les empreintes de la base, de la copie et du pont, sans jamais montrer une clé.

**À distance, par Thread.** Le pont écoute en UDP (port 5480) sur le réseau Thread, une fois qu'une clé UDP existe. Cette clé se crée par l'USB seulement (Réglages › Accès réseau Thread › « Activer l'accès réseau… ») : le pont la garde, l'app la range dans le trousseau de ce Mac. Ensuite, le pont apparaît dans le menu Source, sous « Réseau ». Chaque message est signé avec cette clé, mais rien n'est chiffré : aucun secret ne passe par Thread. À distance, les lectures, les ordres aux lampes, `mesh lampe <n> masquer|afficher` et `led` sont permis ; tout ce qui touche aux clés, à la liste des lampes, au réseau Mesh, à Matter ou au redémarrage reste réservé à l'USB. `json cle efface`, `decommission` et BOOT tenu 8 s effacent la clé UDP.

macOS perd parfois la route IPv6 vers le réseau Thread : l'assistant `halo-routes` du pont Halo ([tools/macos/halo-routes](https://github.com/Djoko-cli/benq-screenbar-halo-matter/tree/main/tools/macos/halo-routes)) la rétablit, et sert tel quel ici (même réseau Thread).

Le mode démo (menu de la barre latérale, ou Fichier › Mode démo, ⇧⌘D) simule un pont à trois lampes, sans matériel. Compiler : voir [apps/macos/README.md](apps/macos/README.md).
````

`README.md`, bloc 2 sur 4. Remplacer :

````markdown
| éclat blanc | BOOT court : redémarrage |

Bouton BOOT : appui court, redémarrage ; de 2 à 8 s, rien ; 8 s ou plus, désappairage de Maison. Les clés restent.

## Console
````

par :

````markdown
| éclat blanc | BOOT court : redémarrage |

Bouton BOOT : appui court, redémarrage ; de 2 à 8 s, rien ; 8 s ou plus, désappairage de Maison. Les clés du réseau des lampes restent ; la clé UDP de l'accès par Thread est effacée.

## Console
````

`README.md`, bloc 3 sur 4. Remplacer :

````markdown
- `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` : la liste des lampes, tout ou rien (c'est ce qu'envoie `outils/cles_amaran.py`) ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre` ;
- `json …` : le mode machine de l'app compagnon ([docs/PROTOCOLE-JSON.md](docs/PROTOCOLE-JSON.md)). Le pont démarre toujours en console texte ; `json 1` passe en mode machine, `json 0` (ou 30 s sans rien de l'app) revient au texte.

Une commande inconnue répond `Commande inconnue : "<nom>" (help)`.
````

par :

````markdown
- `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` : la liste des lampes, tout ou rien (c'est ce qu'envoie `outils/cles_amaran.py`) ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `redemarre` ;
- `decommission` : retire le pont de Maison (toutes les fabriques Matter) et efface la clé UDP, puis redémarre ;
- `json …` : le mode machine de l'app compagnon ([docs/PROTOCOLE-JSON.md](docs/PROTOCOLE-JSON.md)). Le pont démarre toujours en console texte ; `json 1` passe en mode machine, `json 0` (ou 30 s sans rien de l'app) revient au texte. `json cle nouvelle <64 hexa>` crée la clé UDP de l'accès par Thread (la réponse ne la montre qu'en mode machine, une seule fois ; la console texte n'en montre que l'empreinte), `json cle efface` l'efface ; `json trames 1|0` envoie ou coupe les trames du Bluetooth Mesh décodées.

Une commande inconnue répond `Commande inconnue : "<nom>" (help)`.
````

`README.md`, bloc 4 sur 4. Remplacer :

````markdown
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
du même auteur) : `components/socle`, avec ses tests. Le mode JSON
(`components/protocole`) et l'app compagnon (`apps/macos`) sont une copie
adaptée de son protocole et de Halo Compagnon.

Projet personnel, sans lien avec Aputure. Il n'ouvre ni ne modifie les lampes.
````

par :

````markdown
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
du même auteur) : `components/socle`, avec ses tests. Le mode JSON
(`components/protocole`), l'enveloppe H1 de l'accès par Thread
(`components/h1`, avec ses tests) et l'app compagnon (`apps/macos`) sont une
copie adaptée de son protocole et de Halo Compagnon.

Projet personnel, sans lien avec Aputure. Il n'ouvre ni ne modifie les lampes.
````

- [ ] **Step 2 : le README de l'app.**

`apps/macos/README.md`, bloc 1 sur 3. Remplacer :

````markdown
# Amaran Compagnon

L'app macOS du pont amaran : supervision, commandes et console par l'USB, et gestion des clés du réseau Bluetooth Mesh des lampes. Copie adaptée de Halo Compagnon (le pont BenQ Halo du même auteur). La spec : [docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md](../../docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) ; le protocole du pont : [docs/PROTOCOLE-JSON.md](../../docs/PROTOCOLE-JSON.md).

## Compiler
````

par :

````markdown
# Amaran Compagnon

L'app macOS du pont amaran : supervision, commandes et console, par l'USB ou par le réseau Thread, et gestion des clés du réseau Bluetooth Mesh des lampes. Copie adaptée de Halo Compagnon (le pont BenQ Halo du même auteur). La spec : [docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md](../../docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) ; le protocole du pont : [docs/PROTOCOLE-JSON.md](../../docs/PROTOCOLE-JSON.md).

## Compiler
````

`apps/macos/README.md`, bloc 2 sur 3. Remplacer :

````markdown

Ils n'utilisent ni le pont ni le trousseau du Mac : le pont simulé du mode démo, un trousseau en mémoire, une base d'amaran Desktop factice. Le vrai trousseau ne sert que sur demande : `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild … test`.

## Signature
````

par :

````markdown

Ils n'utilisent ni le pont ni le trousseau du Mac : le pont simulé du mode démo, un trousseau en mémoire, une base d'amaran Desktop factice. Le vrai trousseau ne sert que sur demande : `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild … test`.

## Écrans

- **Tableau de bord** : une carte par lampe, le Bluetooth Mesh, les clés, le voyant, le système, et « Thread et Matter », avec le bloc `ip` du pont (nom SRP, adresses OMR et ML-EID, canal UDP : clé, empreinte, ouvert, sessions, reçus, émis, rejets, perdus).
- **Graphiques** : par lampe, la part des relectures répondues et les délais des ordres ; pour le Mesh, les annonces, les NetMIC faux et les refus d'émission ; le tas libre. Fenêtre de 10 s ou 1 min, durée affichée au choix ; un redémarrage du pont ouvre un nouveau segment ; « Vider les courbes » n'efface que celles de l'app. Par le réseau, le pont n'envoie pas les compteurs du Mesh : un bouton les redemande (`json compteurs 5000`).
- **Trames** : le trafic Bluetooth Mesh décodé (ordres, demandes d'état, états reçus), en tableau, avec des filtres (sens, lampe, nature) et « Figer ». L'interrupteur « Trames du pont » envoie `json trames 1` ou `0` ; par le réseau, le pont coupe le flux seul au bout de 60 s : l'app l'indique et propose de relancer.
- **Commandes et console** : par le réseau, la console n'envoie que les commandes de la liste blanche du pont ; les autres ne partent pas, et la sortie texte d'une commande revient rattachée à son `id`.
- **Réglages** (⌘,) : « Général » (dossier d'amaran Desktop, sauvegarde) et « Accès réseau Thread » (les ponts connus de ce Mac, avec leur empreinte et l'état de leur session, « Oublier… » ; pour le pont branché en USB, « Activer l'accès réseau… » ou « Nouvelle clé… »). La carte « Thread et Matter » du tableau de bord ouvre cet onglet.

## Accès par Thread

Le menu Source de la barre latérale propose, en plus des ports série, les ponts « Réseau » dont ce Mac a la clé. La clé UDP d'un pont se crée par l'USB (« Activer l'accès réseau… ») et se range dans le trousseau de ce Mac (service `fr.djoko.amaran.pont`, un compte par nom SRP) : elle n'est jamais affichée, seule son empreinte l'est. Chaque session s'ouvre par `json 1 bail 60`, sans Ctrl-U.

- **Droit réseau** : l'app est sandboxée, avec `com.apple.security.network.client` (`AmaranCompagnon.entitlements`), et `NSLocalNetworkUsageDescription` dans `project.yml`. À la première session, macOS demande l'accès au « Réseau local » ; s'il est refusé, un bandeau le dit (Réglages Système › Confidentialité et sécurité › Réseau local).
- **Route IPv6** : si macOS n'a pas de route vers le réseau Thread, la console et le panneau de connexion pointent vers l'assistant `halo-routes` du dépôt de Halo ; l'app réessaie seule, sans bandeau, comme Halo.

## Signature
````

`apps/macos/README.md`, bloc 3 sur 3. Remplacer :

````markdown
## Lancer

- `open "<DerivedData>/Build/Products/Debug/Amaran Compagnon.app" --args -demo` : démarre en mode démo (pont simulé à trois lampes) ;
- `--args -ecran commandes` : ouvre l'écran des commandes.

L'app ne s'ouvre jamais seule sur un port : choisir le pont (VID 303A) dans le menu de la barre latérale, la connexion part aussitôt. Ensuite, « Connecter » vise ce même pont, reconnu à son numéro de série USB, jamais un autre port Espressif ; tant qu'aucun pont n'a été choisi au menu, il reste grisé. Ouvrir le port ne redémarre pas le pont : DTR et RTS passent à 0 en un seul appel. « Libérer le port » rend la console texte au pont (`json 0`) et ferme le port, pour flasher.

## Structure

- `AmaranProtocole/` : le protocole, sans interface : tramage, session et corrélation (repris de Halo Compagnon), messages du pont, clés (base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison).
- `AmaranCompagnon/` : l'app SwiftUI : port série, modèle `Pont`, trousseau, écrans, mode démo.
- `AmaranProtocoleTests/`, `AmaranCompagnonTests/` : les tests. `ExemplesSpecTests` lit les exemples de `docs/PROTOCOLE-JSON.md`, que le firmware forme tels quels (`tests/hote/test_json.cpp`).
````

par :

````markdown
## Lancer

- `open "<DerivedData>/Build/Products/Debug/Amaran Compagnon.app" --args -demo` : démarre en mode démo (pont simulé à trois lampes, avec un bloc `ip` inventé et des trames sous `json trames 1`) ;
- `--args -ecran commandes` : ouvre l'écran des commandes (`tableau`, `graphiques`, `trames` ou `commandes`).

L'app ne s'ouvre jamais seule sur un port ni sur une session réseau : choisir le pont (VID 303A, ou un pont « Réseau ») dans le menu de la barre latérale, la connexion part aussitôt. Ensuite, « Connecter » vise ce même pont, reconnu à son numéro de série USB, jamais un autre port Espressif ; tant qu'aucun pont n'a été choisi au menu, il reste grisé. Ouvrir le port ne redémarre pas le pont : DTR et RTS passent à 0 en un seul appel. « Libérer le port » rend la console texte au pont (`json 0`) et ferme le port, pour flasher.

## Structure

- `AmaranProtocole/` : le protocole, sans interface : tramage, session et corrélation (repris de Halo Compagnon), messages du pont, clés (base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison), `Reseau/` (enveloppe H1, clé UDP et état de l'accès réseau, erreurs du réseau, répertoire des ponts), `Transport/TransportUDP` (la session par Thread, reprise de Halo) et `Courbes/` (différences des compteurs et séries des graphiques).
- `AmaranCompagnon/` : l'app SwiftUI : port série, modèle `Pont`, trousseau des clés du Mesh, `Reseau/` (trousseau des ponts, alertes de la source réseau, état de session des ponts connus), écrans, mode démo.
- `AmaranProtocoleTests/`, `AmaranCompagnonTests/` : les tests. `ExemplesSpecTests` lit les exemples de `docs/PROTOCOLE-JSON.md`, que le firmware forme tels quels (`tests/hote/test_json.cpp`).
````

- [ ] **Step 3 : la spec.**

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 1 sur 10. Remplacer :

````markdown
- **Mémoire du pont** (banc 4 du plan 3a) : tas au plus bas 103 Ko à
  16 lampes ; firmware de 1,7 Mo, 57 % de la partition libres.

## 4. Architecture et découpage
````

par :

````markdown
- **Mémoire du pont** (banc 4 du plan 3a) : tas au plus bas 103 Ko à
  16 lampes ; firmware de 1,7 Mo, 57 % de la partition libres.
- **Une socket UDP sur OpenThread cohabite avec Matter** (essai radio du
  05/10, prototype 3b-2) : ouverte et utilisée sans jamais prendre le verrou
  d'OpenThread (tout passe par la file de tâches d'OpenThread), 20 échos sur
  20 à 42 ms ; une salve de 1 Ko trois fois par seconde pendant 60 s, avec
  56 ordres de Maison : 178 échos sur 180, aucun ordre abandonné, tampons
  d'OpenThread jamais sous 34. Le nom SRP du pont se résout sur le Mac
  (`<16 hexa>.local`).
- **Sans hôte USB** (chargeur, port du Mac en veille), ESP-IDF 5.5.4 rend
  toute lecture de la console en échec immédiat : la tâche de console de 3b-1
  rebouclait et affamait le démarrage (voyant bleu, Matter jamais lancé).
  Corrigé le 05/10 (`692bff9`) ; chaque banc vérifie depuis le pont sur
  secteur.

## 4. Architecture et découpage
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 2 sur 10. Remplacer :

````markdown
  liste des lampes, au cœur `lampes`, au Mesh et à Matter ;
- `components/h1` (3b-2) : enveloppe, sessions et anti-rejeu (purs, repris de
  Halo) ; la socket OpenThread et la clé UDP en NVS vivent dans
  `firmware/main`.

Le firmware `ecoute` n'est pas touché.
````

par :

````markdown
  liste des lampes, au cœur `lampes`, au Mesh et à Matter ;
- `components/h1` (3b-2) : enveloppe, sessions et anti-rejeu (purs, repris de
  Halo) ; la socket OpenThread, l'anneau d'émission et la clé UDP en NVS
  vivent dans `firmware/main/net_udp` ; `json_pont` tient une session par
  origine (l'USB et deux sessions H1), et une tâche `distant` exécute les
  commandes à texte venues de Thread (vu en préparant le plan 3b-2).

Le firmware `ecoute` n'est pas touché.
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 3 sur 10. Remplacer :

````markdown
- `hello` : version du firmware, ESP-IDF, cause du démarrage, durée de marche,
  numéro de série `AMARAN-<MAC>`, capacités (`matter`, `thread`, `mesh`,
  `catalogue` ; `udp` et `cle` en 3b-2) ;
- `config` :
  - le catalogue des modèles (code, nom, capacités), dont le firmware est la
````

par :

````markdown
- `hello` : version du firmware, ESP-IDF, cause du démarrage, durée de marche,
  numéro de série `AMARAN-<MAC>`, capacités (`matter`, `thread`, `mesh`,
  `catalogue` ; `udp`, `cle`, `trames` et `texte` en 3b-2) ;
- `config` :
  - le catalogue des modèles (code, nom, capacités), dont le firmware est la
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 4 sur 10. Remplacer :

````markdown
  silence et compté.

**Liste blanche à distance** (tout le reste reçoit `interdite`) :
- `json 1` (bail de 10 à 120 s), `json 0`, `json etat`, `json hello`,
  `json ping`, et les cadences dans des bornes plus lentes ;
````

par :

````markdown
  silence et compté.

**Précisé en préparant le plan 3b-2** (prototype, essai radio, relectures) :
- jamais le verrou d'OpenThread depuis nos tâches : la socket passe par la
  file de tâches d'OpenThread (`esp_openthread_task_queue_post`) ; un anneau
  de 12 datagrammes, plafonné en débit, laisse 24 tampons d'OpenThread à
  Matter ; le débit vers chaque session distante est réglé comme chez Halo
  (une ligne périodique ne part que s'il reste de la place), si bien que
  l'instantané de 16 lampes arrive entier ;
- chaque session distante a sa génération : une ligne d'une session passée
  ne touche jamais la suivante ;
- toute ligne distante porte un `id` ; le pont garde les 8 dernières
  réponses de chaque session (même `id` : même réponse, sans rien exécuter),
  ignore le renvoi d'une commande encore en cours, et répond `deja_traite`
  à un `id` plus ancien (réponse oubliée) ;
- la clé UDP = HMAC-SHA256(aléa de l'app, aléa du pont), gardée en NVS ; la
  console texte n'en montre que l'empreinte ; le port 5480 ne s'ouvre
  qu'avec une clé ; le code d'appairage Matter vaut `null` à distance ;
- les commandes à texte permises à distance passent par une tâche `distant`
  du pont : leur sortie devient des messages `texte`, envoyés après la
  commande (capturée sans verrou : la première version figeait le pont sur
  `mesh lampe <n> masquer`).

**Liste blanche à distance** (tout le reste reçoit `interdite`), jugée sur
les mots que la console exécuterait (`esp_console_split_argv`), jamais sur la
ligne brute (chez Halo, `json 1 "bail" 0` passait) :
- `json 1` (bail de 10 à 120 s), `json 0`, `json etat`, `json hello`,
  `json ping`, et les cadences dans des bornes plus lentes ;
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 5 sur 10. Remplacer :

````markdown
**Profil à distance :** l'état toutes les 2 s (une lampe à chaque changement,
et toutes les 30 s), le réseau toutes les 30 s, ni compteurs ni trames par
défaut.

**Le firmware :** `components/h1` (pur, repris de Halo) ; dans
````

par :

````markdown
**Profil à distance :** l'état toutes les 2 s (une lampe à chaque changement,
et toutes les 30 s), le réseau toutes les 30 s, ni compteurs ni trames par
défaut ; l'app peut demander les compteurs (toutes les 5 s au plus vite) ;
les trames se coupent seules au bout de 60 s ; bail de 10 à 120 s, jamais 0.

**Le firmware :** `components/h1` (pur, repris de Halo) ; dans
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 6 sur 10. Remplacer :

````markdown
même réseau Thread.

**Risque :** CHIP possède OpenThread. Halo y a déjà ouvert une socket UDP sur
la même pile ESP-IDF ; le plan 3b-2 commence quand même par cet essai.

## 8. L'app : écrans, réglages et mode démo
````

par :

````markdown
même réseau Thread.

**Risque levé :** CHIP possède OpenThread. Halo y avait ouvert une socket UDP
sur la même pile ESP-IDF ; l'essai radio du 05/10 l'a confirmé pour le pont
amaran (section 3).

## 8. L'app : écrans, réglages et mode démo
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 7 sur 10. Remplacer :

````markdown

**3. Graphiques (3b-2)** : par lampe, la part des relectures répondues et les
délais des ordres ; pour le Mesh, les annonces, les NetMIC faux et les refus
d'émission ; le tas libre. Un redémarrage du pont ouvre un nouveau segment.

**4. Trames (3b-2)** : le trafic Mesh décodé (ordres et demandes d'état émis,
````

par :

````markdown

**3. Graphiques (3b-2)** : par lampe, la part des relectures répondues et les
délais des ordres ; pour le Mesh, les annonces (et celles de notre réseau),
la part des NetMIC faux parmi les annonces de notre réseau (un IV Index faux
la fait monter vers 100 % ; des clés périmées font tomber à zéro les
annonces de notre réseau) et les refus d'émission ; le tas libre. Un
redémarrage du pont ouvre un nouveau segment. À distance, les compteurs du
Mesh ne viennent que sur demande : la carte du Mesh et l'écran le disent et
proposent de les activer.

**4. Trames (3b-2)** : le trafic Mesh décodé (ordres et demandes d'état émis,
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 8 sur 10. Remplacer :

````markdown
- Phrase de passe fausse ou fichier de sauvegarde altéré : refus net, sans
  indice.
- Thread (3b-2) : route IPv6 absente (l'app pointe vers `halo-routes`), pont
  sans clé (port fermé), sessions pleines ; messages repris de Halo.

## 10. Tests sur le Mac
````

par :

````markdown
- Phrase de passe fausse ou fichier de sauvegarde altéré : refus net, sans
  indice.
- Thread (3b-2) : route IPv6 absente (la console et le panneau de connexion
  pointent vers `halo-routes`, sans bandeau, comme Halo), pont sans clé (port
  fermé), clé absente de ce Mac ou trousseau inaccessible (bandeau), sessions
  pleines (bandeau, nouvel essai toutes les 30 s) ; messages repris de Halo.

## 10. Tests sur le Mac
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 9 sur 10. Remplacer :

````markdown
  exporter puis importer une sauvegarde ; relever les marges de pile et de tas
  avec la tâche `json`.
- **3b-2** : ouvrir une session par Thread ; refuser une commande interdite ;
  piloter à distance ; une heure d'endurance à distance.

## 12. Risques et questions ouvertes
````

par :

````markdown
  exporter puis importer une sauvegarde ; relever les marges de pile et de tas
  avec la tâche `json`.
- **3b-2** : banc A par l'USB (clé UDP créée et effacée sans s'afficher,
  trames, marges, démarrage sur secteur) ; banc B avec l'app : ouvrir une
  session par Thread ; refuser une commande interdite ; piloter à distance ;
  une heure d'endurance à distance, le pont sur secteur.

## 12. Risques et questions ouvertes
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 10 sur 10. Remplacer :

````markdown
| l'USB ne sait pas écrire une ligne entière sans bloquer | tampon et écriture tout ou rien, ligne perdue et comptée | levé en préparant le plan 3b-1 : `usb_serial_jtag_write_bytes` sans attente écrit tout ou rien (tampon porté à 4 Ko) ; à confirmer au banc A |
| le signet ne donne pas accès au conteneur d'amaran Desktop | copie de la base choisie par Djoko, ou app sans sandbox (à décider avec lui) | banc B du plan 3b-1, en premier : l'essai demande l'app signée et un choix de Djoko ; macOS lui demande alors d'autoriser l'accès aux données d'une autre app |
| une socket UDP sur OpenThread gêne CHIP | essai d'abord ; Halo l'a déjà fait | tâche 1 du plan 3b-2 |
| la tâche `json` ou H1 manque de tas ou de pile | budget relevé au banc ; cadences abaissées | bancs 3b-1 et 3b-2 |
| l'icône M2 reprend une marque déposée | non versionnée ; A2 en repli dans le dépôt | décision 9 |
````

par :

````markdown
| l'USB ne sait pas écrire une ligne entière sans bloquer | tampon et écriture tout ou rien, ligne perdue et comptée | levé en préparant le plan 3b-1 : `usb_serial_jtag_write_bytes` sans attente écrit tout ou rien (tampon porté à 4 Ko) ; à confirmer au banc A |
| le signet ne donne pas accès au conteneur d'amaran Desktop | copie de la base choisie par Djoko, ou app sans sandbox (à décider avec lui) | banc B du plan 3b-1, en premier : l'essai demande l'app signée et un choix de Djoko ; macOS lui demande alors d'autoriser l'accès aux données d'une autre app |
| une socket UDP sur OpenThread gêne CHIP | essai d'abord ; Halo l'a déjà fait | levé à l'essai radio du 05/10 (prototype 3b-2, section 3) |
| les lignes distantes débordent l'anneau d'émission (perte de l'instantané au-delà de 2 lampes) | débit réglé vers chaque session, comme Halo | trouvé à la relecture du prototype 3b-2, corrigé avant le plan |
| la console du pont sans hôte USB | lecture de la console en échec immédiat : attendre au lieu de reboucler | trouvé au banc du prototype 3b-2 (pont bleu sur un chargeur), corrigé sur `main` (`692bff9`) |
| la tâche `json` ou H1 manque de tas ou de pile | budget relevé au banc ; cadences abaissées | bancs 3b-1 et 3b-2 |
| l'icône M2 reprend une marque déposée | non versionnée ; A2 en repli dans le dépôt | décision 9 |
````

- [ ] **Step 4 : aucune valeur réelle.** Les seules adresses `fd…` versionnées sont les adresses inventées des exemples (`fd12:34:5678:…`, `fd00:aaaa:bbbb:…`, `fd00:cccc:dddd:…`) ; aucun nom SRP autre que `1A2B3C4D5E6F7081` ou `DEMO-AMARAN`, aucune MAC hors `02:00:…`, aucune empreinte réelle.

Run: `git diff HEAD --stat && git grep -noE "fd[0-9a-f]{2}:[0-9a-f:]+" -- README.md apps docs tests components firmware | /usr/bin/grep -vE "fd12:34:5678|fd00:aaaa:bbbb|fd00:cccc:dddd" | head`
Expected : la liste des trois fichiers ; aucune ligne du second `grep`. Une ligne trouvée est à examiner : une adresse du réseau de Djoko n'a rien à faire dans le dépôt.

- [ ] **Step 5 : commit.**

```bash
git add README.md apps/macos/README.md docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md
git commit -m "$(printf "Documentation du plan 3b-2 : acces par Thread (README, README de l'app), choix reportes dans la spec\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 11: Banc B : l'app par Thread, le pont sur secteur, une heure à distance (Claude et Djoko)

**Files:**
- Modify: `docs/BANC.md` (une section « Plan 3b-2 : banc B »), `README.md` (la ligne P3b-2 du tableau « État »)

Cette tâche est faite par Claude, avec Djoko : flasher si le firmware a changé depuis le banc A, lancer l'app sur le vrai pont, émettre vers les lampes. Aucun sous-agent.

**Interfaces:**
- Consumes : le firmware (Task 3, vérifié au banc A) ; l'app (Tasks 5 à 9) ; `apps/macos/Local.xcconfig` (équipe de Djoko, ignoré par git : sans lui, le trousseau et l'autorisation « Réseau local » ne survivent pas à une compilation).
- Produces : les faits du banc dans `docs/BANC.md` ; la ligne P3b-2 de l'état du README ; un ruling dans le registre si un point échoue.

Pourquoi : la spec 3b, section 11 : ouvrir une session par Thread, refuser une commande interdite, piloter à distance, une heure d'endurance à distance. Le pont est sur un chargeur secteur pendant l'endurance : c'est l'usage réel, et le défaut de la console sans hôte USB (`692bff9`) l'a montré.

- [ ] **Step 1 : construire et lancer l'app** (Claude ; Djoko ferme d'abord toute autre Amaran Compagnon, qui tiendrait le port).

```bash
cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd build 2>&1 | /usr/bin/grep -E "error:|warning:|BUILD" ; open "build/dd/Build/Products/Debug/Amaran Compagnon.app"
```

- [ ] **Step 2 : la clé, par l'USB.** Pont branché au Mac. Djoko : Source › le port du pont › Connecter ; Réglages (⌘,) › « Accès réseau Thread ». Expected : « Pont branché en USB » dit « aucune clé » (bouton « Activer l'accès réseau… ») ou « Clé … inconnue de ce Mac » (« Nouvelle clé… ») ; après le geste et sa confirmation : « Clé … connue de ce Mac », le pont listé dans « Ponts connus de ce Mac » avec la même empreinte (macOS peut demander l'accès au trousseau).

- [ ] **Step 3 : la session par Thread.** Djoko : Déconnecter ; Source › Réseau › « Pont amaran » ; Connecter (macOS demande l'accès au réseau local la première fois : accepter). Expected : le tableau de bord se remplit ; la carte « Thread et Matter » montre le nom réseau, les adresses, le canal UDP ouvert, la session ; la carte Bluetooth Mesh dit « Compteurs du Mesh non relevés à distance » ; « Activer » les fait venir.

- [ ] **Step 4 : la console et la liste blanche, à distance.** Dans la console : `lampes`, `lampe 1`, `matter`. Expected : leur texte, rattaché à leur `id`. Puis `redemarre` : l'app refuse, sans rien envoyer, en citant la liste blanche du pont.

- [ ] **Step 5 : piloter à distance (Djoko présent).** Commandes : lampe 1 allumée, 30 %, 100 %, éteinte ; écran Trames, interrupteur actif pendant ces ordres. Expected : chaque ordre confirmé, la lampe et Maison suivent ; les trames `tx` et `rx` défilent ; au bout de 60 s, le pont coupe les trames et l'écran le dit (« Prolonger »).

- [ ] **Step 6 (au choix de Djoko) : retirer de Maison, puis remettre, à distance.** Seulement avec une lampe dont Djoko accepte de perdre la configuration dans Maison (elle revient comme un nouvel accessoire, décision 7). `mesh lampe <n> masquer`, confirmé, puis `afficher`. Expected : chaque commande répond `ok` avec son texte ; le pont reste vivant (états toutes les 2 s, console USB et Maison réactives) : c'est le chemin qui figeait le pont avant la relecture du prototype (journal émis sous le verrou des lampes).

- [ ] **Step 7 : sur secteur, une heure à distance.** Djoko branche le pont sur un chargeur secteur ; l'app, toujours sur la source réseau, se reconnecte seule (session perdue au débranchement, puis reprise). Pendant une heure : l'app connectée, l'écran Graphiques ouvert, aucun geste. Expected à la fin : la session est restée ouverte (ou s'est reprise seule, à noter) ; `perdus` et `rejets` du bloc `udp` et les lignes perdues de la session, relevés ; les graphiques continus ; un ordre allumer/éteindre confirmé ; Maison réactive ; tas au plus bas et marges de pile (bloc `sante`) au moins 1 Ko pour `udp`, `distant`, `json`.

- [ ] **Step 8 : consigner.** `docs/BANC.md` : une section `## Plan 3b-2 : banc B, l'app par Thread (<date>)` (étapes 2 à 7, délais des ordres, pertes, marges, écarts), sans adresse, nom SRP ni empreinte réels. `README.md` : la ligne P3b-2 du tableau « État » (comme la ligne P3b-1), « faite (<date>) : bancs A et B ; … ». Puis commit :

```bash
git add docs/BANC.md README.md
git commit -m "$(printf "Banc B du plan 3b-2 : l'app par Thread, le pont sur secteur, une heure a distance\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

Si un point échoue : le noter, ruling dans le registre, correction, puis refaire le point. Pas de push sans l'accord de Djoko.
