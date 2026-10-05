# Pont amaran, plan 3b-1 : l'app compagnon par l'USB : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le pont gagne un mode machine sur sa console USB (le protocole v1 de Halo, adapté à N lampes), et l'app macOS Amaran Compagnon le supervise et le pilote par l'USB : clés d'amaran Desktop (trousseau, sauvegarde chiffrée, chargement du pont), tableau de bord à N lampes, commandes et console, mode démo.

**Architecture:**
- Firmware :
  - le cœur `lampes` signale désormais chaque ordre (`confirme`, `abandon`, `tenu`) avec son délai ;
  - un composant neuf, `protocole` (C++ pur, testé sur le Mac), forme les lignes machine : briques reprises de `json_out` de Halo, messages du pont amaran ; chaque exemple de `docs/PROTOCOLE-JSON.md` en sort tel quel ;
  - la console du pont devient notre propre tâche : linenoise en mode texte, lecture sans écho en mode machine. La tâche `json`, de basse priorité, émet l'état et les événements ; une ligne s'écrit entière ou pas du tout, sans attendre.
- App (`apps/macos`, projet XcodeGen, Swift 6 strict) :
  - `AmaranProtocole`, sans interface : tramage, session et corrélation repris de Halo Compagnon, messages du pont, clés (base d'amaran Desktop lue en mémoire, sauvegarde chiffrée, chargement, comparaison) ;
  - `AmaranCompagnon` : port série (repris de Halo), modèle `Pont`, trousseau local, écrans, mode démo (un pont simulé à trois lampes, qui sert aussi aux tests de bout en bout).

```
amaran Desktop (base, lue en memoire) ──► Amaran Compagnon ──USB──► console du pont
            trousseau du Mac ◄────────┘    (session, id=)    │  texte : linenoise
            sauvegarde chiffree ◄─────┘                       │  machine : json_pont (tache json)
                                                              ▼
                                   etat, ordres, alertes ◄── tache lampes, mesh, Matter, socle
```

**Tech Stack:** ESP-IDF v5.5.4 (C11, C++17, FreeRTOS), esp-matter `c5b9ea8` ; clang et clang++ pour les tests natifs ; Swift 6, SwiftUI, Swift Testing, XcodeGen 2.46, Xcode 27, macOS 15 ou plus ; CryptoKit, CommonCrypto, SQLite du système.

**Spec:** `docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md` : c'est l'autorité de ce plan (sections 1 à 6 et 8 à 12, la part 3b-1). Les specs du pont (`2026-09-28-pont-amaran-design.md`) et des N lampes (`2026-10-03-pont-amaran-n-lampes-design.md`) restent la référence pour tout ce qu'elle ne change pas. Le protocole lui-même : `docs/PROTOCOLE-JSON.md` (Task 2).

**Modèle :** le pont Halo et Halo Compagnon, au commit `e114cd5` de `~/Documents/Dev/esp32/benq` (lecture seule) : `src/json_out.*`, `src/json_mode.*`, `tools/host_tests/test_json.cpp`, `apps/macos`. Chaque fichier repris le dit en tête.

## Global Constraints

- ESP-IDF v5.5.4 dans `~/esp/esp-idf`, esp-matter commit `c5b9ea8` dans `~/esp/esp-matter`. Cible `esp32c6`, flash 4 Mo, une seule application.
- **ESP-IDF et esp-matter ne sont jamais modifiés.**
- L'adresse Mesh de l'ESP32 est dans `0x7F00`–`0x7F7F`, **jamais `0x0001`**. Aucune lampe ne peut avoir une adresse de cette plage.
- **Aucune clé** dans le dépôt, un journal ou un affichage. L'empreinte d'une clé = les 8 premiers chiffres hexa, en majuscules, de son SHA-256. L'app ne montre, ne journalise ni ne copie jamais une clé ; la console de l'app masque `mesh cles` ; le pont ne renvoie pas d'écho en mode machine.
- Le dépôt est public : ni MAC complète (lampes, carte), ni numéro de série USB, ni numéro `AMARAN-…`, ni empreinte réelle de clé. Les exemples et le mode démo n'utilisent que des valeurs inventées (MAC `02:00:…`, empreintes `1A2B3C4D`).
- **L'icône M2 (le A d'Aputure) n'est jamais versionnée** : `apps/macos/AmaranCompagnon/Ressources/AppIconM2.icon` est ignoré par git. Le dépôt porte l'icône libre A2.
- Firmware : français partout (console, commits, docs) ; les commentaires du code sont **sans accents** (style du pont Halo). App : mêmes règles ; les textes de l'interface portent leurs accents. Français seulement : pas de catalogue de traduction.
- App : Swift 6, concurrence stricte complète, avertissements traités comme des erreurs, macOS 15 ou plus, sandbox (`device.serial`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, rien d'autre en 3b-1) ; runtime durci quand l'app est signée avec une équipe (`Local.xcconfig`) : signée ad hoc, elle ne chargerait pas son framework. `project.yml` fait foi : le projet Xcode est généré (`xcodegen generate`) et ignoré par git.
- Commits : directement sur `main`, message en français, terminé par une ligne `Co-Authored-By: Claude …` (le modèle qui écrit le commit). **Aucun push sans l'accord de Djoko.**
- **Les sous-agents ne flashent jamais, n'ouvrent jamais de port série, ne lancent jamais l'app sur un vrai port.** Le mode démo et les tests sont permis.
  - Claude flashe avec l'accord de Djoko.
  - Djoko est présent dès qu'on émet vers les lampes.
- La carte du pont se reconnaît au champ `SER=` de `python -m serial.tools.list_ports -v`, jamais au nom du port. Le port est toujours donné explicitement. Ne jamais ouvrir ni flasher la C6 du maillage Thread BenQ, ni un écran LG (eux aussi en `usbmodem`).
- **Seul Claude lit la base d'amaran Desktop** (`~/Library/Containers/com.sidus.amaran-desktop`), jamais un sous-agent. Les tests n'utilisent qu'une base factice, en mémoire.
- **Le vrai trousseau du Mac n'est jamais touché par un sous-agent** : les tests utilisent un trousseau en mémoire ; le test du vrai trousseau ne tourne qu'avec `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1`.
- Dans les scripts et les commandes, utiliser `/usr/bin/grep` : le `grep` du poste est ugrep.
- Environnement, dans la même commande shell que `idf.py` : `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null`, suivi, pour le firmware du pont, de `&& source ~/esp/esp-matter/export.sh >/dev/null`. Le `PATH` d'abord : le Python 3.11 de PlatformIO, souvent en tête, fait échouer `export.sh`.
- `SRC_DIRS "."` : un fichier ajouté à `firmware/main` n'est compilé qu'après `idf.py reconfigure`. Un composant neuf dans `components/` aussi, et dans les deux firmwares (`ecoute/main` dépend de tous les composants).
- Tests natifs : `sh tests/hote/lancer.sh`, tout vert avant chaque commit. Tests de l'outil des clés : `python3 -m unittest discover -s outils -p "test_*.py"` (inchangés). Tests de l'app : depuis `apps/macos`, `xcodegen generate` puis `xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test`.

## Choix fixés en préparant le plan

Le code de ce plan a été écrit, compilé (les deux firmwares et l'app) et testé sur le Mac dans une copie de travail avant d'être recopié ici. Ce prototype a fixé les choix suivants (la Task 10 les reporte dans la spec) :

1. **Le composant s'appelle `components/protocole`**, pas `json` : c'est le nom du composant cJSON d'ESP-IDF, que le nôtre masquerait (la compilation de `wifi_provisioning` échoue alors).
2. **La console du pont est notre propre tâche** (`console`), et non la REPL d'ESP-IDF : linenoise fait toujours l'écho de ce qu'il lit. En mode texte, linenoise lit la ligne ; en mode machine, `json_pont_lire` lit l'USB sans écho ni invite. Dans les deux modes, `json_pont_executer` exécute la ligne (préfixe `id=`, cadence, réponses). Le pilote de l'USB a un tampon d'émission de 4 096 octets.
3. **Une ligne machine s'écrit d'un seul appel** à `usb_serial_jtag_write_bytes(…, 0)` : entière ou pas du tout, sans attendre. Une seconde chance une milliseconde plus tard couvre le cas où une autre tâche tenait le pilote. Sinon, la ligne est perdue et comptée.
4. **Le cœur signale chaque ordre** : `LAMPES_SIGNAL_TENU` s'ajoute (la lampe était déjà dans cet état : rien n'est émis), avec `lampe_t.dernier_delai_ms` et `lampes_t.tenus`. L'`id` d'un ordre de l'app part avec l'ordre dans la file de la tâche des lampes, qui le range par lampe : le signal suivant de la lampe le porte. Aucune course entre l'ordre et son issue.
5. **Le bloc `sante` et le battement `hb` portent l'`id` de la commande en cours** (`commande`) : la tâche `json` émet pendant qu'une commande tourne, et une `reponse fin` perdue se voit au bloc suivant. Le bail ne court pas pendant une commande.
6. **Codes de `reponse`** : `ok`, `accepte`, `en_cours`, `erreur` (la commande a échoué : son texte dit pourquoi), `usage`, `inconnue`, `trop_long`, `cadence`. Un firmware d'avant ce plan répond `Unrecognized command` à `id=1 json 1` : l'app le reconnaît.
7. **UTF-8** : les noms des lampes passent tels quels dans les lignes machine (une séquence invalide devient `?`). L'app charge un nom entre guillemets, `"` et `\` échappés, en un seul argument de `esp_console_split_argv` : ses espaces passent tels quels. La console texte (linenoise), elle, retire les caractères non ASCII.
8. **Jamais le verrou d'OpenThread** depuis nos tâches : le rôle Thread vient des événements, comme avant. L'identité et les codes d'appairage sont lus une fois, sous le verrou de la pile, juste après `esp_matter::start()`.
9. **La base d'amaran Desktop est lue en mémoire** : le fichier est lu, puis ouvert par SQLite depuis cette copie (`sqlite3_deserialize`), effacée ensuite. Rien ne s'écrit près de la base (elle est en journal `delete`, sans WAL). Le panneau d'ouverture part du vrai dossier personnel (`getpwuid`) : dans la sandbox, `homeDirectoryForCurrentUser` est le conteneur de l'app (vu par un test hébergé).
10. **Le trousseau** : un élément générique (service `fr.djoko.amaran.reseau`, compte `reseau`) ; les deux clés dans la donnée secrète, l'aperçu (empreintes, lampes, date) dans l'attribut générique, lisible sans les clés.
11. **La sauvegarde** : `AMARANSV`, version (1), tours (600 000, gros-boutiste), sel (16 octets), puis la boîte AES-GCM (nonce, contenu, étiquette). L'en-tête est authentifié avec le contenu. Phrase fausse ou fichier altéré : la même erreur, sans indice.
12. **Le chargement du pont** : une commande à la fois, chacune vérifiée avant la suivante (empreintes rendues, liste enregistrée), puis `redemarre`, puis la comparaison de ce que le pont montre. `mesh cles` part « en secret » : le suivi n'en garde que le masque, et la ligne est oubliée dès son envoi.
13. **Le mode démo** : trois lampes (une dans Maison, une retirée de Maison, une jamais vue qui y entre au bout de 15 s), des clés et des MAC inventées, un trousseau en mémoire à part. Son bail se compte en temps réel ; les tests accélèrent le reste (×20).
14. **L'icône** : `ASSETCATALOG_COMPILER_APPICON_NAME` est dans `Signature.xcconfig`, avant `#include? "Local.xcconfig"` : `Local.xcconfig` choisit `AppIconM2`. Vérifié : seule l'icône nommée entre dans l'app.

## Carte des fichiers

| fichier | rôle | tâche |
|---|---|---|
| `components/lampes/{include/lampes.h,lampes.c}`, `tests/hote/test_lampes.c` | signal `tenu`, délai du dernier ordre | 1 |
| `components/liste/{include/catalogue.h,catalogue.c}`, `tests/hote/test_liste.c` | parcours du catalogue | 1 |
| `firmware/main/tache_lampes.c` | `tenu` ne compte pas comme abandon (1) ; ordres avec `id`, événements, annonces (3) | 1, 3 |
| `components/protocole/{CMakeLists.txt,include/json_ligne.h,include/json_amaran.h,json_ligne.cpp,json_amaran.cpp}` | lignes machine (C++ pur) | 2 |
| `tests/hote/{test_json.cpp,lancer.sh}`, `docs/PROTOCOLE-JSON.md` | tests et document du protocole | 2 |
| `firmware/main/{json_pont.h,json_pont.cpp}` | session, tâche `json`, exécution des lignes | 3 |
| `firmware/main/{console_pont.h,console_pont.c}` | notre tâche de console | 3 |
| `firmware/main/{tache_lampes.h,pont_matter.h,pont_matter.cpp,socle.h,socle.cpp,app_main.cpp}` | accesseurs et événements | 3 |
| `docs/BANC.md` | résultats des bancs | 4, 11 |
| `apps/macos/{project.yml,Signature.xcconfig,.gitignore,Outils/constellation-a.svg}`, `apps/macos/AmaranCompagnon/{AmaranCompagnon.entitlements,Ressources/AppIcon.icon}` | projet de l'app, icône A2 | 5 |
| `apps/macos/AmaranProtocole/{Messages,Tramage}`, `Interpretation/Appairage.swift` | messages du pont, tramage, codes d'appairage | 5 |
| `apps/macos/AmaranProtocole/{Commandes,Transport,Session,Etat}`, `Interpretation/Interpretation.swift` | commandes, corrélation, session, état du pont, textes | 6 |
| `apps/macos/AmaranProtocole/Cles` | clés : réseau, base, sauvegarde, chargement, comparaison | 7 |
| `apps/macos/AmaranCompagnon/{Serie,Modele,Cles,Demo}` | port série, modèle `Pont`, trousseau, démo | 8 |
| `apps/macos/AmaranCompagnon/{Vues,AmaranCompagnonApp.swift}` | écrans et réglages | 5 (app provisoire), 9 |
| `apps/macos/AmaranProtocoleTests/{TramageTests,ExemplesSpecTests,AppairageTests}.swift` | tests du tramage et des messages | 5 |
| `apps/macos/AmaranProtocoleTests/{CorrelationTests,AncreTempsTests,CouvertureClesTests}.swift` | tests de la session et de l'état | 6 |
| `apps/macos/AmaranProtocoleTests/ClesTests.swift` | tests des clés | 7 |
| `apps/macos/AmaranCompagnonTests/{LancementTests,DemoBoutEnBoutTests}.swift` | test provisoire (5, retiré en 8) ; bout en bout et trousseau (8) | 5, 8 |
| `README.md`, `apps/macos/README.md`, `docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md` | documentation | 10 |

---

### Task 1: Le cœur signale chaque ordre, le catalogue se parcourt (C pur, testé sur le Mac)

**Files:**
- Modify: `components/lampes/include/lampes.h`, `components/lampes/lampes.c`, `tests/hote/test_lampes.c`
- Modify: `components/liste/include/catalogue.h`, `components/liste/catalogue.c`, `tests/hote/test_liste.c`
- Modify: `firmware/main/tache_lampes.c`

**Interfaces:**
- Consumes : le cœur `lampes` et le catalogue du plan 3a.
- Produces (les Tasks 2 et 3 s'en servent telles quelles) :
  - `LAMPES_SIGNAL_TENU`, troisième valeur de `lampes_signal_t` : un ordre égal au dernier état lu, rien n'est émis ;
  - `uint32_t lampe_t.dernier_delai_ms` : délai du dernier ordre fini (confirmé ou abandonné ; 0 s'il était tenu) ;
  - `uint32_t lampes_t.tenus` : ordres tenus depuis le démarrage ;
  - `unsigned catalogue_nombre(void)`, `const catalogue_modele_t *catalogue_modele(unsigned i)` (le repli au-delà), `const catalogue_modele_t *catalogue_repli(void)`.

Pourquoi : l'événement `ordre` du protocole (spec 3b, section 6) dit l'issue de chaque ordre de l'app, et le message `config` décrit le catalogue. Jusqu'ici, un ordre déjà tenu ne donnait aucun signal : l'app attendrait en vain. La sortie `signaler` de la tâche des lampes compte encore tout ce qui n'est pas confirmé comme un abandon (rouge ×3 au voyant) : elle apprend ici à ignorer `tenu`.

- [ ] **Step 1 : écrire les tests.**

`tests/hote/test_lampes.c`, bloc 1 sur 5. Remplacer :

````c
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].e.marche && g_pubs[0].e.intensite == 500, "etat confirme publie");
  VERIFIE(L.confirmes == 1 && L.lampes[0].phase == LAMPE_REPOS, "compteur et repos");
}

````

par :

````c
  VERIFIE(g_nb_pubs == 1 && g_pubs[0].e.marche && g_pubs[0].e.intensite == 500, "etat confirme publie");
  VERIFIE(L.confirmes == 1 && L.lampes[0].phase == LAMPE_REPOS, "compteur et repos");
  VERIFIE(L.lampes[0].dernier_delai_ms == 400 && L.lampes[0].essai == 1,
          "delai du dernier ordre (%u ms), au premier essai", (unsigned)L.lampes[0].dernier_delai_ms);
}

````

`tests/hote/test_lampes.c`, bloc 2 sur 5. Remplacer :

````c
  VERIFIE(L.abandons == 1 && L.lampes[0].phase == LAMPE_REPOS && !L.lampes[0].veut_marche,
          "consigne effacee");
}

````

par :

````c
  VERIFIE(L.abandons == 1 && L.lampes[0].phase == LAMPE_REPOS && !L.lampes[0].veut_marche,
          "consigne effacee");
  VERIFIE(L.lampes[0].dernier_delai_ms == 3700 && L.lampes[0].essai == LAMPES_ESSAIS,
          "abandon : delai depuis l'ordre (%u ms), au dernier essai", (unsigned)L.lampes[0].dernier_delai_ms);
}

````

`tests/hote/test_lampes.c`, bloc 3 sur 5. Remplacer :

````c
  VERIFIE(compter(0x0002, TELINK_CMD_MARCHE) == 0 && compter(0x0002, TELINK_CMD_INTENSITE) == 0,
          "rien n'est emis");
  VERIFIE(g_nb_sigs == 0, "ni confirmation ni abandon");
}

````

par :

````c
  VERIFIE(compter(0x0002, TELINK_CMD_MARCHE) == 0 && compter(0x0002, TELINK_CMD_INTENSITE) == 0,
          "rien n'est emis");
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_TENU && g_sigs[0].lampe == 0,
          "un signal : deja tenu (%d signaux)", g_nb_sigs);
  VERIFIE(L.tenus == 1 && L.confirmes == 0 && L.abandons == 0 && L.lampes[0].dernier_delai_ms == 0,
          "compte comme tenu, sans delai");
}

````

`tests/hote/test_lampes.c`, bloc 4 sur 5. Remplacer :

````c
  VERIFIE(compter(0x0002, TELINK_CMD_INTENSITE) == 0, "433 egale 430 relu : aucune trame d'intensite");
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 0, "aucune demande d'etat pour cet ordre");
  VERIFIE(g_nb_sigs == 0, "ni confirmation ni abandon");
}

````

par :

````c
  VERIFIE(compter(0x0002, TELINK_CMD_INTENSITE) == 0, "433 egale 430 relu : aucune trame d'intensite");
  VERIFIE(compter(0x0002, TELINK_CMD_ETAT) == 0, "aucune demande d'etat pour cet ordre");
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_TENU, "ni confirmation ni abandon : deja tenu");
}

````

`tests/hote/test_lampes.c`, bloc 5 sur 5. Remplacer :

````c
  avancer(1500);
  VERIFIE(g_nb_envois == 0, "aucune trame (%d)", g_nb_envois);
  VERIFIE(g_nb_sigs == 0, "ni confirmation ni abandon");
}

````

par :

````c
  avancer(1500);
  VERIFIE(g_nb_envois == 0, "aucune trame (%d)", g_nb_envois);
  VERIFIE(g_nb_sigs == 1 && g_sigs[0].s == LAMPES_SIGNAL_TENU, "ni confirmation ni abandon : deja tenu");
}

````

`tests/hote/test_liste.c`, bloc 1 sur 1. Remplacer :

````c
  VERIFIE(LISTE_CODE_V1 == CATALOGUE_CODE_COB_60D && catalogue_connu(LISTE_CODE_V1),
          "les lampes converties du plan 2 sont des 60d cataloguees");
}

````

par :

````c
  VERIFIE(LISTE_CODE_V1 == CATALOGUE_CODE_COB_60D && catalogue_connu(LISTE_CODE_V1),
          "les lampes converties du plan 2 sont des 60d cataloguees");
  // Parcours du catalogue (protocole JSON) : chaque modele une fois, puis le repli.
  VERIFIE(catalogue_nombre() == 1 && catalogue_modele(0) == m, "un modele : la 60d");
  VERIFIE(catalogue_modele(catalogue_nombre()) == r && catalogue_repli() == r, "au-dela : le repli");
}

````

> **Amendement (exécution, 05/10)** : la relecture de cette tâche a montré qu'un ordre refusé faute de Bluetooth Mesh (`lampes_ordre`, Mesh pas prêt) gardait le délai et l'essai de l'ordre précédent. Correctif en un commit à part : `p->debut_ms = maintenant_ms; p->essai = 0;` avant `finir`, et deux vérifications de plus dans `test_mesh_perdu_pendant_un_ordre` (`lampes : 162 verifications`).

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `sh tests/hote/lancer.sh`
Expected: FAIL à la compilation de `test_lampes.c` (`LAMPES_SIGNAL_TENU` non déclaré).

- [ ] **Step 3 : le cœur.**

`components/lampes/include/lampes.h`, bloc 1 sur 3. Remplacer :

````c
} lampe_etat_t;

typedef enum {
  LAMPES_SIGNAL_CONFIRME,  // ordre confirme par l'etat lu (voyant : eclat vert)
  LAMPES_SIGNAL_ABANDON,   // ordre abandonne : 3 essais, ou Mesh pas pret (rouge x3)
} lampes_signal_t;

````

par :

````c
} lampe_etat_t;

// Chaque ordre finit par un signal : confirme, abandon, ou tenu ; un ordre arrive
// pendant un autre se fond dans le sien, et le signal de celui-ci vaut pour les deux.
typedef enum {
  LAMPES_SIGNAL_CONFIRME,  // ordre confirme par l'etat lu (voyant : eclat vert)
  LAMPES_SIGNAL_ABANDON,   // ordre abandonne : 3 essais, ou Mesh pas pret (rouge x3)
  LAMPES_SIGNAL_TENU,      // deja tenu par le dernier etat lu : rien n'est emis (6.4)
} lampes_signal_t;

````

`components/lampes/include/lampes.h`, bloc 2 sur 3. Remplacer :

````c
  uint32_t demande_ms;           // demande d'etat de l'essai en cours
  uint32_t debut_ms;             // arrivee du dernier ordre de la chaine (delai de confirmation)
  bool a_refaire;                // consigne changee depuis les dernieres trames
  // Ce que Matter montre (publie par nous, ou ecrit par un controleur)
````

par :

````c
  uint32_t demande_ms;           // demande d'etat de l'essai en cours
  uint32_t debut_ms;             // arrivee du dernier ordre de la chaine (delai de confirmation)
  uint32_t dernier_delai_ms;     // dernier ordre fini : confirme ou abandonne apres ce delai ; tenu : 0
  bool a_refaire;                // consigne changee depuis les dernieres trames
  // Ce que Matter montre (publie par nous, ou ecrit par un controleur)
````

`components/lampes/include/lampes.h`, bloc 3 sur 3. Remplacer :

````c
  uint32_t prochaine_releve_ms;
  lampes_sorties_t sorties;
  uint32_t ordres, confirmes, abandons, releves, trames_recues;
  uint32_t delai_total_ms, delai_max_ms;  // ordre -> confirmation (banc C, regle 5.8 : 1 s)
  uint32_t lents;                         // confirmations en plus d'une seconde
````

par :

````c
  uint32_t prochaine_releve_ms;
  lampes_sorties_t sorties;
  uint32_t ordres, confirmes, abandons, tenus, releves, trames_recues;
  uint32_t delai_total_ms, delai_max_ms;  // ordre -> confirmation (banc C, regle 5.8 : 1 s)
  uint32_t lents;                         // confirmations en plus d'une seconde
````

`components/lampes/lampes.c`, bloc 1 sur 2. Remplacer :

````c
  p->veut_marche = p->veut_intensite = false;
  p->a_refaire = false;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    const uint32_t delai = maintenant_ms - p->debut_ms;
    l->confirmes++;
    l->delai_total_ms += delai;
````

par :

````c
  p->veut_marche = p->veut_intensite = false;
  p->a_refaire = false;
  const uint32_t delai = maintenant_ms - p->debut_ms;
  p->dernier_delai_ms = delai;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    l->confirmes++;
    l->delai_total_ms += delai;
````

`components/lampes/lampes.c`, bloc 2 sur 2. Remplacer :

````c
  if (p->connu && consigne_tenue(p, &p->lu)) {
    p->veut_marche = p->veut_intensite = false;
    montrer(l, lampe, false);
    return;
````

par :

````c
  if (p->connu && consigne_tenue(p, &p->lu)) {
    p->veut_marche = p->veut_intensite = false;
    p->dernier_delai_ms = 0;
    l->tenus++;
    l->sorties.signaler(l->sorties.ctx, lampe, LAMPES_SIGNAL_TENU);
    montrer(l, lampe, false);
    return;
````

- [ ] **Step 4 : le catalogue.**

`components/liste/include/catalogue.h`, bloc 1 sur 1. Remplacer :

````c
// (console, et reponse de `mesh lampe` que lit outils/cles_amaran.py).
const char *catalogue_capacites_texte(uint8_t capacites);

#ifdef __cplusplus
````

par :

````c
// (console, et reponse de `mesh lampe` que lit outils/cles_amaran.py).
const char *catalogue_capacites_texte(uint8_t capacites);
// Les modeles catalogues un a un (i < catalogue_nombre()), et le repli : le
// catalogue du protocole JSON (docs/PROTOCOLE-JSON.md, config.catalogue).
unsigned catalogue_nombre(void);
const catalogue_modele_t *catalogue_modele(unsigned i);
const catalogue_modele_t *catalogue_repli(void);

#ifdef __cplusplus
````

`components/liste/catalogue.c`, bloc 1 sur 1. Remplacer :

````c
bool catalogue_connu(uint32_t code) { return code != 0 && catalogue_trouver(code) != &REPLI; }

const char *catalogue_capacites_texte(uint8_t capacites) {
  switch (capacites & (CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR)) {
````

par :

````c
bool catalogue_connu(uint32_t code) { return code != 0 && catalogue_trouver(code) != &REPLI; }

unsigned catalogue_nombre(void) { return sizeof(MODELES) / sizeof(MODELES[0]); }

const catalogue_modele_t *catalogue_modele(unsigned i) { return i < catalogue_nombre() ? &MODELES[i] : &REPLI; }

const catalogue_modele_t *catalogue_repli(void) { return &REPLI; }

const char *catalogue_capacites_texte(uint8_t capacites) {
  switch (capacites & (CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR)) {
````

- [ ] **Step 5 : la tâche des lampes ne compte plus un ordre tenu comme un abandon.**

`firmware/main/tache_lampes.c`, bloc 1 sur 1. Remplacer :

````c
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    s_confirmes++;
  } else {
    s_abandons++;
  }
````

par :

````c
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    s_confirmes++;
  } else if (signal == LAMPES_SIGNAL_ABANDON) {
    s_abandons++;
  }
````

- [ ] **Step 6 : lancer les tests, tout est vert.**

Run: `sh tests/hote/lancer.sh`
Expected: `lampes : 160 verifications, 0 echecs`, `liste : 65 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 7 : les deux firmwares compilent.**

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader") && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader")`
Expected : pour chaque firmware, sa taille (`amaran_ecoute.bin binary size …`, puis `amaran_pont.bin binary size …`) et `Project build complete. To flash, run:` ; aucune ligne `warning:` ni `error:`.

- [ ] **Step 8 : commit.**

```bash
git add components/lampes components/liste tests/hote firmware/main/tache_lampes.c
git commit -m "$(printf "Coeur : chaque ordre finit par un signal (confirme, abandon ou tenu), catalogue parcourable\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 2: Le composant `protocole` et le document du protocole (C++ pur, testé sur le Mac)

**Files:**
- Create: `components/protocole/CMakeLists.txt`, `components/protocole/include/json_ligne.h`, `components/protocole/include/json_amaran.h`, `components/protocole/json_ligne.cpp`, `components/protocole/json_amaran.cpp`
- Create: `tests/hote/test_json.cpp`, `docs/PROTOCOLE-JSON.md`
- Modify: `tests/hote/lancer.sh`

**Interfaces:**
- Consumes : `lampe_t`, `lampes_t`, `lampe_phase_t`, `LAMPES_GROUPE` (`lampes.h`) ; `liste_lampe_t`, `LISTE_*` (`liste.h`) ; `catalogue_*` (Task 1).
- Produces (espace de noms `jsonp`, la Task 3 s'en sert) :
  - `json_ligne.h` (repris de `json_out.h` de Halo) : `Writer` (`begin`, `str`, `u32`, `i32`, `boolean`, `null`, `hex`, `hexU32`, `obj`, `arr`, `end`, `finish`, `data`, `size`) ; `heartbeat(w, n, ms, boot, upS, lost, cmdId)`, `sessionEnd`, `led`, `logLine` ; `struct Reply` (`id`, `fin`, `cmd`, `ok`, `code`, `msg`, `durMs`, `suite` : `SuiteNone`/`SuiteOrder`/`SuiteNothing`, `lampe`, `hasLease`, `leaseS`, `upS`) et `reply` ; `parseIdPrefix`, `copyCmd`, `maskCmd` ; `LineAssembler` (`feed`, `text`, `tooLong`, `reset`) ; `RateCap`, `Cadence` ; `Item`, `Queued`, `Queue` (48 places, `push(item, now, session, arg)`, `front`, `pop`, `dropLate`, `dropSession`) ; `leaseExpired` ; constantes `kLineMax` (1024), `kBudget` (896), `kCmdMax` (127), `kCmdTextMax` (40), `kLogTextMax` (127), `kIdMax` ;
  - `json_amaran.h` : `Session`, `HelloBase`, `HelloId`, `ConfigMesh`, `EtatPont`, `Pile`, `EtatSante` (avec `cmdId`), `CompteursMesh`, `ReseauMatter`, `Ordre`, `kIdsMax` (4) ; `helloBase`, `helloId`, `configCatalogue`, `configMesh`, `configLampe`, `etatPont`, `etatLampe`, `etatSante`, `compteursMesh`, `reseauMatter`, `reseauThread`, `ordre`, `alerteReleves`, `alerteMesh`, `lampe`, `phaseCode`.

Pourquoi : la spec 3b, section 6, et la décision 8 (les modules purs de Halo, avec une fine couche pour ESP-IDF). Tout ce qui forme une ligne se teste ici, sur le Mac : l'écrivain (UTF-8 gardé, octets de contrôle remplacés), le préfixe `id=`, l'assemblage des lignes reçues, la cadence, la file, le bail, et chaque message du pont. `test_json.cpp` lit `docs/PROTOCOLE-JSON.md` : chaque ligne `<RS>` du document doit sortir telle quelle des messages formés par le test, chaque message formé doit y figurer, et le pire cas de chacun tient dans 896 octets. Les exemples de la section 9 du document ont été produits par ce test (`test_json --exemples`).

Repris de Halo (commit `e114cd5`) : `src/json_out.h` et `.cpp` pour l'écrivain, la réponse, le préfixe, l'assemblage, le débit, la cadence, la file et le bail ; `tools/host_tests/test_json.cpp` pour leurs tests. Retiré : les messages de la lampe BenQ, la livraison, le cache des réponses et la liste blanche (réseau, plan 3b-2).

- [ ] **Step 1 : le document du protocole.**

`docs/PROTOCOLE-JSON.md` (contenu complet) :

````markdown
# Protocole JSON du pont amaran (v1)

Le protocole machine entre le pont (ESP32-C6, `firmware/`) et l'app Amaran Compagnon (`apps/macos/`), par l'USB. Il reprend la version 1 du protocole du pont Halo (`~/Documents/Dev/esp32/benq/docs/PROTOCOLE-JSON.md`) : même tramage, même session, mêmes réponses. Seuls les messages propres au pont changent (sections 5 et 7). Le transport par Thread viendra au plan 3b-2.

Chaque exemple de la section 9 est formé tel quel par `tests/hote/test_json.cpp`, et chaque message que ce test forme figure dans la section 9 : le document et le firmware ne peuvent pas diverger.

## 0. Décisions en bref

| Sujet | Décision |
|---|---|
| Tramage | Une ligne machine = l'octet RS (`0x1E`), un objet JSON compact, puis LF. 1 024 octets au plus, RS et LF compris ; 896 au pire visé. Tout le reste du flux est du texte : réponses des commandes, journaux d'ESP-IDF, invite. |
| Sens app → pont | Les lignes de la console, telles qu'un humain les tape, préfixées par `id=<n> `. Jamais de JSON vers le pont. |
| Session | `json 1` passe en mode machine, avec un bail de 30 s que `json ping` renouvelle ; `json 0` ou le bail échu ramènent la console texte. Rien n'est gardé en NVS : chaque démarrage repart en texte. |
| Réponses | Toute ligne qui porte un `id` reçoit une `reponse`. Les ordres de lampe sont asynchrones : `reponse` aussitôt, puis l'événement `ordre`. Les autres commandes : `reponse` `debut`, leur texte, puis `reponse` `fin`. |
| État | `etat` (blocs `pont` et `sante` chaque seconde ; une ligne par lampe à chaque changement, et toutes les 10 s), `compteurs` (chaque seconde), `reseau` (toutes les 5 s). Les événements sont des indices ; la vérité est dans l'état périodique. |
| Compatibilité | `v` dans chaque ligne ; les ajouts ne changent pas `v` ; l'app ignore les champs, types et valeurs qu'elle ne connaît pas. |
| Clés | Jamais dans une ligne machine : seulement leurs empreintes (8 premiers chiffres hexa, en majuscules, du SHA-256). `reponse.cmd` d'un `mesh cles` ne cite pas les clés, et le pont ne renvoie pas d'écho en mode machine. |

## 1. Vocabulaire et principes

- **pont** : l'ESP32-C6 et son firmware ; **app** : Amaran Compagnon.
- **ligne machine** : une ligne RS + JSON (section 2) ; **texte** : toute autre ligne.
- **lampe *n*** : la lampe numéro *n* de la liste du pont, de 1 à 16, comme dans les commandes de la console.
- **consigne** : l'état voulu pour une lampe (Maison, la console ou l'app) ; **état lu** : le dernier état que la lampe a renvoyé.

Principes :
1. **Le pont n'attend jamais l'app.** Une ligne machine qui ne tient pas dans le tampon d'émission de l'USB est perdue et comptée (`json_perdus`).
2. **L'état est périodique, les événements sont des indices.** Une ligne perdue ou abîmée ne fausse rien durablement : l'instantané suivant corrige. L'app ne reconstruit jamais un état en cumulant des événements.
3. **Rien de nouveau ne part vers les lampes** à cause du protocole : l'app passe par les mêmes ordres que Maison et la console (`tache_lampes_ordre`).

## 2. Tramage sur l'USB

### 2.1 Ce qui circule

Le port USB Serial/JTAG du C6 porte, entremêlés : le texte des commandes, l'écho et l'invite `amaran> ` (en mode texte seulement), les annonces du pont (`[lampes] …`, `!! …`, `[mesh] …`, `[bouton] …`), les journaux d'ESP-IDF (`E (12345) tag: …`), et les lignes machine. Les journaux d'ESP-IDF s'écrivent caractère par caractère depuis n'importe quelle tâche : l'un d'eux peut couper un texte, mais jamais une ligne machine, qui entre d'un seul bloc dans le tampon d'émission (2.3).

### 2.2 La ligne machine

```
RS  JSON  LF
0x1E {"v":1,"t":"etat","n":42,"ms":61234,...} 0x0A
```

Règles :
1. Elle commence par l'octet **RS** (`0x1E`), suivi de `{"v":`. RS n'apparaît dans aucune autre sortie du pont ni d'ESP-IDF.
2. Un seul objet JSON, **compact** (aucun espace hors des chaînes), sur une ligne, terminé par **LF** seul.
3. **UTF-8, sans octet de contrôle.** Dans les chaînes, `"` et `\` sont échappés ; un octet de contrôle est remplacé par `?`, de même qu'une séquence UTF-8 invalide ; aucune séquence `\uXXXX`. Les noms des lampes viennent d'amaran Desktop et peuvent porter des accents : ils passent tels quels.
4. **1 024 octets au plus**, RS et LF compris. Le pire cas de chaque message, avec 16 lampes et des noms de 31 octets, tient en **896 octets** (vérifié par `tests/hote/test_json.cpp`) : il reste 128 octets aux ajouts. Un message qui approcherait le budget gagne un bloc, jamais de longueur.
5. Les premiers champs sont toujours `v`, `t`, `n`, `ms`, dans cet ordre, puis `bloc` pour les messages en blocs (`hello`, `config`, `etat`, `compteurs`, `reseau`).

### 2.3 Émission côté pont

- Une ligne est formée dans un tampon de 1 024 octets, puis confiée **d'un seul appel** au pilote de l'USB (`usb_serial_jtag_write_bytes`, sans attente) : elle entre entière dans son tampon d'émission de 4 096 octets, ou pas du tout. Faute de place, elle est perdue et comptée (`json_perdus`) ; le pont réessaie une fois une milliseconde plus tard, pour le cas où une autre tâche tenait le pilote.
- Les lignes périodiques et les instantanés passent par une file (48 places) : la tâche `json` en émet une toutes les 10 ms. Une ligne en retard de plus de 500 ms est perdue et comptée ; une `reponse` ne l'est jamais.
- Les événements partent dès que la tâche `json` les reçoit.
- `n` augmente à chaque ligne produite, écrite ou perdue : un trou dans `n` signale une perte.

### 2.4 Réception côté app

Comme pour Halo (section 2.4 de son protocole) : l'app travaille sur des octets bruts, coupe aux LF, retire un CR final, cherche le **dernier** RS de la ligne, traite comme texte ce qui le précède, et rejette comme « ligne abîmée » un JSON de plus de 1 022 octets, qui ne commence pas par `{"v":`, ne finit pas par `}` ou n'est pas valide. Les octets UTF-8 n'y changent rien : ils ne valent jamais RS ni LF.

Textes reconnus par l'app (jamais d'état tiré du texte) :

| Motif | Classe |
|---|---|
| `^[EWIDV] \(\d+\) [^:]+: ` | journal d'ESP-IDF |
| `^\[(lampes\|mesh\|bouton)\] `, `^!! ` | annonce du pont |
| `^ESP-ROM:`, `^rst:0x`, `^boot:0x` | démarrage |
| `^amaran> ?` | invite (mode texte) |
| autre | texte de commande |

### 2.5 Sens app → pont

- Des lignes de la console terminées par LF ; un CR est ignoré.
- **127 octets au plus**, préfixe `id=` compris. Au-delà, rien n'est exécuté : `reponse` `trop_long`.
- Octets acceptés : 0x20 à 0x7E, et l'UTF-8 des noms. En mode machine, le pont ignore les autres octets de contrôle, sauf LF, CR, `0x15` (Ctrl-U, vide la ligne en cours) et le retour arrière.
- L'app envoie `0x15` puis LF à l'ouverture du port, pour effacer un reste de ligne.

## 3. Session

### 3.1 Ouverture du port

Comme pour Halo (sections 3.1 et 3.2 de son protocole) : `/dev/cu.usbmodem*` en `O_NONBLOCK`, accès exclusif, `HUPCL` retiré, et **DTR et RTS à 0 en un seul `TIOCMSET`** : l'état RTS = 1, DTR = 0 redémarrerait le C6, même un instant. Ouvrir le port ne redémarre pas le pont (`outils/serie.py` fait de même). Tout redémarrage du pont fait disparaître le port, puis revenir : l'app rouvre après 0,3, 1, 2 puis 5 s. Le numéro de série USB du pont est l'adresse MAC de sa puce : l'app retrouve le même pont par lui.

### 3.2 Séquence de connexion

```
App                                            Pont
ouvre le port, DTR = RTS = 0
envoie 0x15 0x0A  ---------------------------> ligne en cours vidée
envoie "id=1 json 1\n"  ---------------------> mode machine : écho et invite coupés
                  <--------------------------- hello (base, identite)
                  <--------------------------- config (catalogue, mesh, une ligne par lampe)
                  <--------------------------- etat (pont, une ligne par lampe, sante)
                  <--------------------------- compteurs (mesh)
                  <--------------------------- reseau (matter, thread)
                  <--------------------------- reponse id=1 fin ok
... puis l'état, les compteurs et le réseau à leurs périodes, et les événements
envoie "id=k json ping\n" après 10 s sans autre commande
```

Sans `hello` 2 s après `json 1`, l'app renvoie (3 fois). Un firmware sans mode JSON répond `Unrecognized command` (console d'ESP-IDF d'avant le plan 3b) : l'app reste en console seule et le dit.

### 3.3 La commande `json`

| Commande | Effet | Bornes |
|---|---|---|
| `json` | état de la session, en texte | |
| `json 1 [bail <s>]` | mode machine : écho et invite coupés, réglages de session remis à leurs valeurs par défaut, puis `hello`, `config` et l'instantané complet par la file ; la `reponse` `fin` part après la dernière ligne. Renvoyer `json 1` resynchronise. | bail 0 (aucun) ou 10 à 600 s ; 30 par défaut |
| `json 0` | retour au texte : message `fin`, puis l'invite | |
| `json etat` | instantané : `etat`, `compteurs`, `reseau`, par la file ; la `reponse` `fin` après. Marche aussi en mode texte. | |
| `json hello` | `hello` et `config`, par la file. Marche aussi en mode texte. | |
| `json ping` | renouvelle le bail ; la `reponse` porte `bail_s` et `up_s` | |
| `json periode <ms>` | période des blocs `etat` `pont` et `sante` | 0 (coupé) ou 200 à 60 000 ; 1 000 par défaut |
| `json lampes <ms>` | période de l'envoi de toutes les lignes `etat` `lampe` | 0 ou 1 000 à 60 000 ; 10 000 par défaut |
| `json compteurs <ms>` | période des `compteurs` | 0 ou 200 à 60 000 ; 1 000 par défaut |
| `json reseau <ms>` | période des `reseau` | 0 ou 1 000 à 60 000 ; 5 000 par défaut |
| `json log 0\|1` | annonces du pont en messages `log` au lieu de texte | 0 par défaut |

Un argument hors bornes : `reponse` `usage`, avec les bornes dans `msg`.

### 3.4 Bail et ping

Le pont date le dernier octet reçu et la fin de la dernière commande ; le bail court depuis le plus récent des deux, et pas pendant une commande (la console ne lit plus l'USB tant qu'elle tourne). Bail échu : message `fin` (`cause` `bail`), puis le texte `json : mode machine coupe (hote muet depuis 30 s)` et l'invite. L'app envoie `json ping` après 10 s sans autre commande.

### 3.5 Battement, silence, redémarrage

- Les blocs `etat` servent de battement. Si `periode_ms` vaut 0 ou plus de 2 000, le pont émet un `hb` toutes les 2 000 ms.
- Silence : aucune ligne depuis 3 × max(période, 2 s), hors commande en cours. L'app renvoie `json 1` ; sans réponse sous 5 s, elle ferme et rouvre le port.
- Redémarrage : `boot` (8 chiffres hexa tirés au démarrage) change, ou `up_s` recule.

### 3.6 Écho et invite

En mode texte, la console est celle d'ESP-IDF (linenoise) : écho, invite `amaran> `, historique. En mode machine, la tâche de la console lit elle-même l'USB, sans écho ni invite : linenoise ne sait pas couper son écho. L'app affiche elle-même la commande envoyée dans sa console.

## 4. Enveloppe et conventions

| Champ | Type | Sens |
|---|---|---|
| `v` | entier | version majeure du protocole : 1 |
| `t` | chaîne | type du message |
| `n` | entier | numéro de la ligne produite depuis le démarrage (pas remis à 0 par `json 1`) |
| `ms` | entier | millisecondes depuis le démarrage, à la production de la ligne |
| `bloc` | chaîne | partie d'un message en blocs |

Conventions :
- **Entiers seulement.** Les compteurs sont des entiers de 32 bits qui reviennent à 0.
- **Unités dans le nom** : `_ms`, `_s`, `_k` (kelvins). Sans suffixe : un nombre d'événements. `intensite` : 0 à 1 000, au dixième de pour cent.
- **Octets en hexa** : majuscules, sans `0x` : adresse Mesh `"7F38"`, MAC `"020000000001"`, empreinte `"1A2B3C4D"`.
- **Booléens** `true`/`false` ; **`null`** = inconnu ou sans objet.
- **Énumérations** : ASCII minuscule, `_` comme séparateur.
- **Lampes** : `lampe` est le numéro de la lampe, de 1 à 16.
- **Pas d'horloge murale** : l'app date à la réception d'un `hello` (heure locale ↔ `ms`) et en déduit le reste.

## 5. Messages périodiques et de session (pont → app)

Chaque instantané est une suite de lignes d'un même type, une par `bloc`. L'app remplace les valeurs d'un (`t`, `bloc`) à chaque réception, et d'un (`t`, `bloc`, `lampe`) pour les lignes de lampe.

### 5.1 `hello`

Émis après `json 1` et sur `json hello`.

**Bloc `base`** :

| Champ | Sens |
|---|---|
| `rev` | révision mineure du protocole (0) |
| `fw` | version du firmware (`0.1.0-<commit>`) |
| `date`, `heure` | compilation |
| `idf`, `puce` | version d'ESP-IDF, `esp32c6` |
| `boot` | 8 hexa, tirés au démarrage |
| `reset`, `reset_n` | cause du démarrage : `mise_sous_tension`, `broche`, `logiciel`, `panique`, `chien_int`, `chien_tache`, `chien`, `baisse_tension`, `usb`, `inconnue` ; et la valeur de `esp_reset_reason()` |
| `up_s` | secondes depuis le démarrage |
| `session` | réglages en vigueur : `periode_ms`, `lampes_ms`, `compteurs_ms`, `reseau_ms`, `bail_s`, `log` |
| `limites` | `ligne_max` (1 024), `cmd_max` (127) |

**Bloc `identite`** : `boot` ; `mac` (MAC de la puce) ; `id` (`fabricant`, `produit`, `serie` = `AMARAN-<MAC>`, `nom`) ; `caps`, les capacités : `matter`, `thread`, `mesh`, `catalogue`, `ordres` (ordres de lampe asynchrones), `led`, `log`. L'app se règle sur `caps`, pas sur la version du firmware.

### 5.2 `config`

Réglages lents : émis avec `hello`, et de nouveau après toute commande `mesh` réussie portant un `id`.

**Bloc `catalogue`** : `modeles`, un objet par modèle catalogué (`code` produit Sidus, `nom`, `capacites` parmi `intensite`, `cct`, `couleur`, `type` d'appareil Matter `variable`, `temperature` ou `couleur`, `cct_k` : `{min, max}` ou `null`), et `repli`, le modèle prêté à un code inconnu. Le firmware est la seule source du catalogue.

**Bloc `mesh`** : `cles` (chargées ou non), `empreintes` (`reseau`, `application`, ou `null` sans clés), `adresse` de l'ESP32, `iv_nvs` (l'IV Index gardé en NVS), `balayage` (`fenetre_ms`, `intervalle_ms`), et l'en-tête de la liste : `lampes` (*N*), `capacite` (16), `releve_ms` (période de relecture), `groupe` (`C000`). Les clés chargées par `mesh cles` ne valent qu'après le redémarrage : jusque-là, ce bloc montre les empreintes en service.

**Bloc `lampe`**, une ligne par lampe de la liste en service : `lampe`, `adresse`, `mac`, `nom`, `code`, `modele` (nom du modèle, ou celui du repli), `catalogue` (code connu ou non), `capacites`, `type`. Une liste chargée par `mesh lampes` ne vaut, elle aussi, qu'après le redémarrage.

### 5.3 `etat`

**Bloc `pont`** (toutes les `periode_ms`) : `boot`, `up_s` ; `mesh` (`pret`, `diag` : `ok`, `cles_absentes`, `pas_entre`, `cles_perimees`, `iv_faux`) ; `ordres` (`total`, `confirmes`, `abandons`, `tenus`, `delai_total_ms` et `delai_max_ms` des ordres confirmés, `lents` : confirmés en plus d'une seconde) ; `releves` (relectures envoyées) ; `trames` (trames reçues des lampes). Le délai moyen vaut `delai_total_ms / confirmes`.

**Bloc `lampe`**, une ligne par lampe, à chaque changement et toutes les `lampes_ms` :

| Champ | Sens |
|---|---|
| `lampe` | numéro |
| `maison` | `endpoint` (son numéro dans Maison, ou `null` hors de Maison), `vue` (a répondu au moins une fois), `masquee` (retirée de Maison par un geste) |
| `entendue` | une trame de la lampe depuis le démarrage |
| `lue` | dernier état lu (`marche`, `intensite`), ou `null` |
| `joignable` | `false` après trois relectures sans réponse |
| `reponse_ms` | `ms` de la dernière trame reçue, ou `null` |
| `consigne` | ordre en cours (`marche` et `intensite` voulues, `null` pour un champ inchangé ; `phase` : `trames`, `attente` ; `essai` : 1 à 3), ou `null` |
| `repondues` | relectures suivies d'une réponse, depuis le démarrage |
| `part_10min` | part des relectures répondues sur 10 min, en pour cent tronqué, ou `null` |
| `alerte` | relectures manquées signalées |

Une lampe lue en marche à l'intensité 0 est noire : Maison la montre éteinte. Sa place dans Maison se déduit de `maison` : un `endpoint` ; sinon `masquee` ; sinon jamais vue ; sinon (vue, non masquée, sans endpoint) hors de Maison après un échec.

**Bloc `sante`** (toutes les `periode_ms`) : `boot`, `up_s` ; `commande` : l'`id` de la commande de la console en cours, ou `null` (6.2) ; `led` (`motif` du voyant, `test`, `depuis_ms` : âge de la phase du motif) ; `matter` (`en_service`, `thread` attaché, `identifie`, `ble` : annonce de mise en service en cours) ; `sys` (`heap`, `heap_min`, `heap_bloc`, `piles` : octets jamais utilisés de chaque tâche, `null` si elle n'existe pas, `json_perdus`, `json_trop_longs`, `rejets` : lignes refusées pour longueur ou cadence).

### 5.4 `compteurs`

**Bloc `mesh`** (toutes les `compteurs_ms`), cumulatifs depuis le démarrage : `annonces` (messages Mesh vus), `nid_reconnu` et `nid_inconnu` (de notre réseau ou d'un autre), `netmic_faux`, `acces_dechiffres`, `etats_lampes`, `doublons` (copies réseau et rejeux écartés), `balises` (`notres`, `autres`, `fausses`, `derniere` : `iv`, `drapeaux`, `ms`, ou `null`), `emis`, `echecs_emission`, `file_pleine` (événements du crochet perdus), puis l'`iv` courant, la séquence `seq` et le `plancher` de séquence gardé en NVS.

### 5.5 `reseau`

**Bloc `matter`** (toutes les `reseau_ms`) : `demarre`, `fabriques`, `ble`, `identifie` ; `abonnements` (`demandes`, `plafonnes`, `etablis`, `termines`, `plafond_s`) ; `code_manuel` et `qr` (charge `MT:…`), pour ajouter le pont à Maison, ou `null`. Les abonnements actifs valent à peu près `etablis − termines`.

**Bloc `thread`** : `role` (`disabled`, `detached`, `child`, `router`, `leader`), tel que l'annonce le dernier événement d'OpenThread ; `attache`. Le pont ne prend jamais le verrou d'OpenThread depuis ses tâches : rien de plus en 3b-1.

### 5.6 `hb` et `fin`

`hb` : battement quand les `etat` sont coupés ou lents (3.5) : `boot`, `up_s`, `json_perdus`, et `commande` comme le bloc `sante`.

`fin` : dernier message d'une session machine. `cause` : `commande` (`json 0`) ou `bail`.

## 6. Commandes de l'app (app → pont)

### 6.1 `id=<n>`

L'app envoie les commandes de la console, précédées de `id=<n> ` (1 à 999 999 999, croissants pendant toute la vie de l'app) :

```
id=17 lampe 1 niveau 500
```

Le préfixe est retiré avant l'aiguillage. Sans `id`, rien ne change : texte seul, aucune `reponse`.

### 6.2 Sémantique d'une ligne avec `id`

| Commande | Déroulement |
|---|---|
| famille `json` | `reponse` `fin` aussitôt ; après la dernière ligne pour `json 1`, `json etat`, `json hello` |
| `lampe <n> on\|off\|niveau <0-1000>` | **asynchrone** : `reponse` `fin`, code `accepte`, `suite` `ordre`, en quelques millisecondes ; puis l'événement `ordre` qui porte l'`id` (7.1) |
| toute autre commande | `reponse` `debut`, le texte de la commande, puis `reponse` `fin` : `ok` si elle a réussi, `erreur` sinon (le texte dit pourquoi), `inconnue` pour une commande inconnue |

La tâche `json` émet pendant qu'une commande tourne. Le bloc `sante` et le battement `hb` portent l'`id` de la commande en cours (`commande`) : il y entre avec la `reponse` `debut` et en sort avec la `fin`. Un bloc `sante` ou un `hb` sans cet `id`, reçu après le `debut`, dit que la `fin` s'est perdue.

Ordres de lampe : un numéro hors de la liste, ou un argument hors bornes, reçoit `usage`. L'ordre rejoint ensuite la tâche des lampes avec son `id`. Chaque ordre finit par un événement `ordre` : `confirme`, `abandon` ou `tenu` ; un ordre arrivé pendant un autre se fond dans le sien, et l'événement de celui-ci porte les deux `id`.

### 6.3 Message `reponse`

| Champ | Sens |
|---|---|
| `id` | celui de la ligne |
| `etape` | `debut` (la commande commence) ou `fin` |
| `cmd` | la commande reçue, sans le préfixe, tronquée à 40 octets ; `mesh cles` sans ses clés |
| `ok` | réussite |
| `code` | voir ci-dessous |
| `msg` | explication (120 octets au plus), facultative |
| `duree_ms` | durée d'exécution (`fin`) |
| `suite` | `ordre` : un événement `ordre` suivra |
| `lampe` | numéro de la lampe d'un ordre |
| `bail_s`, `up_s` | `json 1`, `json ping` |

| Code | ok | Sens |
|---|---|---|
| `ok` | oui | exécutée |
| `accepte` | oui | ordre de lampe accepté : un `ordre` suivra |
| `en_cours` | oui | étape `debut` |
| `erreur` | non | la commande a échoué : son texte dit pourquoi |
| `usage` | non | arguments invalides (famille `json`, ordres de lampe) |
| `inconnue` | non | commande inconnue |
| `trop_long` | non | ligne de plus de 127 octets : rien n'est exécuté |
| `cadence` | non | plus de 20 lignes par seconde en mode machine : rien n'est exécuté |

### 6.4 Commandes utilisées par l'app

| Écran | Action | Ligne envoyée |
|---|---|---|
| tous | connexion, bail | `json 1`, puis `json ping` |
| tableau de bord | rafraîchir | `json etat` |
| tableau de bord | tester le voyant | `led test`, `led stop` |
| commandes | marche, arrêt, niveau | `lampe <n> on`, `lampe <n> off`, `lampe <n> niveau <0-1000>` |
| commandes | relire une lampe | `lampe <n> releve` |
| commandes | retirer de Maison, remettre (confirmation) | `mesh lampe <n> masquer`, `mesh lampe <n> afficher` |
| commandes | période de relecture | `mesh releve <1-60 s>` |
| clés | charger le pont | `mesh cles <reseau> <application>`, `mesh lampes <N>`, une ligne `mesh lampe <n> <adresse> <mac> <code> <nom>` par lampe, puis `redemarre` |
| console | tout le reste | la ligne tapée, préfixée d'un `id` |

L'app confirme avant d'envoyer `redemarre`, `decommission`, `mesh oublie`, `mesh adresse`, `mesh iv` et `mesh lampe <n> masquer`. Elle n'envoie qu'une commande à la fois, et attend sa `reponse` `fin` (3 s au plus sans `debut`) avant la suivante.

## 7. Événements (pont → app)

Émis en mode machine seulement, dès que le pont les constate.

### 7.1 `ordre` : fin d'un ordre de lampe

`lampe` ; `issue` : `confirme` (l'état relu égale la consigne), `abandon` (trois essais sans confirmation, ou Bluetooth Mesh pas prêt), `tenu` (la lampe était déjà dans cet état : rien n'est émis) ; `delai_ms` (depuis le dernier ordre de la chaîne ; 0 pour `tenu`, et pour un ordre refusé faute de Bluetooth Mesh) ; `essai` (1 à 3 ; 0 pour `tenu`, et pour un ordre refusé faute de Bluetooth Mesh) ; `ids` (les `id` des ordres de l'app couverts, 4 au plus ; vide pour un ordre de Maison ou de la console sans `id`) ; `ids_perdus` (au-delà de 4).

### 7.2 `alerte`

- `quoi` `releves` : `lampe`, `manque` (vrai quand la part des relectures répondues sur 10 min passe sous 95 %, faux quand elle y revient), `part` (en pour cent).
- `quoi` `mesh` : `diag`, la cause probable d'un Bluetooth Mesh inopérant (5.3), ou `ok` quand il repart.

### 7.3 `lampe` : place dans Maison

`lampe` ; `quoi` : `entree` (première réponse d'une lampe jamais vue : elle entre dans Maison), `masquee` (`mesh lampe <n> masquer`), `remise` (`mesh lampe <n> afficher`), `echec` (endpoint Matter non créé) ; `endpoint`, ou `null`.

### 7.4 `led` : motif du voyant

À chaque changement de motif : `motif`, `avant`, `test`, `depuis_ms`. Les motifs sont ceux du pont Halo (`components/socle/include/status_led.h`, `patternCode`) : `identification`, `desappairage`, `redemarrage`, `injoignable`, `panne_radio` (ici : Bluetooth Mesh inopérant), `livree` (ordre confirmé), `non_appaire`, `hors_reseau`, `operationnel`.

### 7.5 `log` : annonces du pont

Seulement avec `json log 1` : les annonces de la tâche des lampes (`[lampes] …`, `!! …`, `[mesh] …`) et du bouton BOOT (`[bouton] …`) partent alors en `log` **au lieu** du texte. Champs : `src` (`lampes`, `mesh`, `bouton`), `niv` (`notice` ou `alerte`), `txt` (127 octets au plus). Au plus 20 par seconde ; au-delà, le suivant porte `sautes`. Les journaux d'ESP-IDF et le texte des commandes ne passent jamais par `log`.

## 8. Versionnage et débit

- `v` change seulement pour une rupture. Tout le reste est additif et garde `v` ; `rev` augmente à chaque ajout.
- L'app ignore les champs, types et blocs inconnus, et range une valeur d'énumération inconnue sous « inconnu ».
- Au repos, deux lampes, réglages par défaut : environ 1,8 Ko/s (`etat` `pont` et `sante`, `compteurs` chaque seconde ; une ligne par lampe toutes les 10 s ; `reseau` toutes les 5 s). À 16 lampes : environ 2,3 Ko/s. Un instantané complet à 16 lampes fait 42 lignes, environ 11 Ko, émises en un peu plus de 0,4 s.

## 9. Exemples

`<RS>` note l'octet `0x1E` ; le LF final est omis. Les MAC, le numéro de série et les empreintes sont inventés.

### 9.1 Connexion

App → pont (`\x15` : l'octet `0x15`, suivi de LF) :

```
\x15
id=1 json 1
```

Pont → app : le pont a deux lampes, toutes deux dans Maison ; « Lumière fenêtre » montre un nom accentué.

```
<RS>{"v":1,"t":"hello","n":0,"ms":83512,"bloc":"base","rev":0,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"3FA2C901","reset":"logiciel","reset_n":3,"up_s":83,"session":{"periode_ms":1000,"lampes_ms":10000,"compteurs_ms":1000,"reseau_ms":5000,"bail_s":30,"log":false},"limites":{"ligne_max":1024,"cmd_max":127}}
<RS>{"v":1,"t":"hello","n":1,"ms":83522,"bloc":"identite","boot":"3FA2C901","mac":"F0F5BD0A0B0C","id":{"fabricant":"TEST_VENDOR","produit":"TEST_PRODUCT","serie":"AMARAN-F0F5BD0A0B0C","nom":"Pont amaran"},"caps":["matter","thread","mesh","catalogue","ordres","led","log"]}
<RS>{"v":1,"t":"config","n":2,"ms":83532,"bloc":"catalogue","modeles":[{"code":40065,"nom":"amaran COB 60d","capacites":["intensite"],"type":"variable","cct_k":null}],"repli":{"nom":"modele non catalogue","capacites":["intensite"],"type":"variable","cct_k":null}}
<RS>{"v":1,"t":"config","n":3,"ms":83542,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":0,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}
<RS>{"v":1,"t":"config","n":4,"ms":83552,"bloc":"lampe","lampe":1,"adresse":"0002","mac":"020000000001","nom":"Lampe bureau","code":40065,"modele":"amaran COB 60d","catalogue":true,"capacites":["intensite"],"type":"variable"}
<RS>{"v":1,"t":"config","n":5,"ms":83562,"bloc":"lampe","lampe":2,"adresse":"0004","mac":"020000000002","nom":"Lumière fenêtre","code":40065,"modele":"amaran COB 60d","catalogue":true,"capacites":["intensite"],"type":"variable"}
<RS>{"v":1,"t":"etat","n":6,"ms":83572,"bloc":"pont","boot":"3FA2C901","up_s":83,"mesh":{"pret":true,"diag":"ok"},"ordres":{"total":6,"confirmes":5,"abandons":0,"tenus":1,"delai_total_ms":2150,"delai_max_ms":620,"lents":0},"releves":41,"trames":80}
<RS>{"v":1,"t":"etat","n":7,"ms":83582,"bloc":"lampe","lampe":1,"maison":{"endpoint":2,"vue":true,"masquee":false},"entendue":true,"lue":{"marche":true,"intensite":430},"joignable":true,"reponse_ms":83390,"consigne":null,"repondues":40,"part_10min":97,"alerte":false}
<RS>{"v":1,"t":"etat","n":8,"ms":83592,"bloc":"lampe","lampe":2,"maison":{"endpoint":3,"vue":true,"masquee":false},"entendue":true,"lue":{"marche":false,"intensite":600},"joignable":true,"reponse_ms":83398,"consigne":null,"repondues":41,"part_10min":100,"alerte":false}
<RS>{"v":1,"t":"etat","n":9,"ms":83602,"bloc":"sante","boot":"3FA2C901","up_s":83,"commande":null,"led":{"motif":"operationnel","test":false,"depuis_ms":62160},"matter":{"en_service":true,"thread":true,"identifie":false,"ble":false},"sys":{"heap":112640,"heap_min":103424,"heap_bloc":45056,"piles":{"lampes":2104,"json":1460,"console":2876,"socle":1180,"CHIP":1872,"ot_task":1536,"nimble_host":1712,"mesh_adv_task":980,"amaran_tx":1290},"json_perdus":0,"json_trop_longs":0,"rejets":0}}
<RS>{"v":1,"t":"compteurs","n":10,"ms":83612,"bloc":"mesh","annonces":5120,"nid_reconnu":1630,"nid_inconnu":3402,"netmic_faux":0,"acces_dechiffres":1500,"etats_lampes":81,"doublons":77,"balises":{"notres":17,"autres":0,"fausses":0,"derniere":{"iv":0,"drapeaux":0,"ms":81870}},"emis":64,"echecs_emission":0,"file_pleine":0,"iv":0,"seq":1093,"plancher":1024}
<RS>{"v":1,"t":"reseau","n":11,"ms":83622,"bloc":"matter","demarre":true,"fabriques":1,"ble":false,"identifie":false,"abonnements":{"demandes":2,"plafonnes":2,"etablis":2,"termines":1,"plafond_s":20},"code_manuel":"34970112332","qr":"MT:Y.K9042C00KA0648G00"}
<RS>{"v":1,"t":"reseau","n":12,"ms":83632,"bloc":"thread","role":"child","attache":true}
<RS>{"v":1,"t":"reponse","n":13,"ms":83642,"id":1,"etape":"fin","cmd":"json 1","ok":true,"code":"ok","duree_ms":130,"bail_s":30,"up_s":83}
```

### 9.2 Un ordre de l'app

```
id=2 lampe 1 niveau 500
```

```
<RS>{"v":1,"t":"reponse","n":31,"ms":95002,"id":2,"etape":"fin","cmd":"lampe 1 niveau 500","ok":true,"code":"accepte","duree_ms":0,"suite":"ordre","lampe":1}
<RS>{"v":1,"t":"etat","n":32,"ms":95010,"bloc":"lampe","lampe":1,"maison":{"endpoint":2,"vue":true,"masquee":false},"entendue":true,"lue":{"marche":true,"intensite":430},"joignable":true,"reponse_ms":83390,"consigne":{"marche":null,"intensite":500,"phase":"trames","essai":1},"repondues":40,"part_10min":97,"alerte":false}
<RS>{"v":1,"t":"ordre","n":33,"ms":95412,"lampe":1,"issue":"confirme","delai_ms":410,"essai":1,"ids":[2],"ids_perdus":0}
<RS>{"v":1,"t":"led","n":34,"ms":95413,"motif":"livree","avant":"operationnel","test":false,"depuis_ms":0}
<RS>{"v":1,"t":"etat","n":35,"ms":95420,"bloc":"lampe","lampe":1,"maison":{"endpoint":2,"vue":true,"masquee":false},"entendue":true,"lue":{"marche":true,"intensite":500},"joignable":true,"reponse_ms":95410,"consigne":null,"repondues":46,"part_10min":97,"alerte":false}
<RS>{"v":1,"t":"led","n":36,"ms":95563,"motif":"operationnel","avant":"livree","test":false,"depuis_ms":74000}
```

La consigne part à 500 ; la lampe relit 500 au premier essai, 410 ms après l'ordre. Le voyant donne son éclat vert. Les `n` manquants sont des lignes périodiques, omises ici.

### 9.3 Déjà tenu, abandon, relectures manquées

La lampe 2 est déjà éteinte :

```
id=3 lampe 2 off
```

```
<RS>{"v":1,"t":"reponse","n":40,"ms":101002,"id":3,"etape":"fin","cmd":"lampe 2 off","ok":true,"code":"accepte","duree_ms":0,"suite":"ordre","lampe":2}
<RS>{"v":1,"t":"ordre","n":41,"ms":101003,"lampe":2,"issue":"tenu","delai_ms":0,"essai":0,"ids":[3],"ids_perdus":0}
```

Puis la lampe 2 est débranchée, et l'app l'allume (`id=4 lampe 2 on`) : trois essais, abandon, trois éclats rouges. Plus tard, ses relectures manquées passent sous 95 % sur 10 min :

```
<RS>{"v":1,"t":"ordre","n":52,"ms":108705,"lampe":2,"issue":"abandon","delai_ms":3700,"essai":3,"ids":[4],"ids_perdus":0}
<RS>{"v":1,"t":"led","n":53,"ms":108706,"motif":"injoignable","avant":"operationnel","test":false,"depuis_ms":0}
<RS>{"v":1,"t":"alerte","n":210,"ms":603000,"quoi":"releves","lampe":2,"manque":true,"part":82}
```

### 9.4 Retirer de Maison, remettre

```
id=5 mesh lampe 2 masquer
```

```
<RS>{"v":1,"t":"reponse","n":220,"ms":640001,"id":5,"etape":"debut","cmd":"mesh lampe 2 masquer","ok":true,"code":"en_cours"}
ok lampe 2 retiree de Maison (mesh lampe 2 afficher pour la remettre)
<RS>{"v":1,"t":"reponse","n":221,"ms":640039,"id":5,"etape":"fin","cmd":"mesh lampe 2 masquer","ok":true,"code":"ok","duree_ms":38}
<RS>{"v":1,"t":"lampe","n":222,"ms":640040,"lampe":2,"quoi":"masquee","endpoint":null}
```

L'événement `lampe` part de la tâche `json` : il peut suivre la `reponse` `fin`. Plus tard, `id=6 mesh lampe 2 afficher` la remet (même numéro, mais Maison la voit comme un nouvel accessoire) ; et une lampe chargée depuis, jamais vue, entre dans Maison à sa première réponse :

```
<RS>{"v":1,"t":"lampe","n":230,"ms":652100,"lampe":2,"quoi":"remise","endpoint":3}
<RS>{"v":1,"t":"lampe","n":12,"ms":21402,"lampe":3,"quoi":"entree","endpoint":4}
```

### 9.5 Bluetooth Mesh inopérant

Le réseau a été recréé dans amaran Desktop : le pont entend des annonces Mesh, aucune de son réseau. Puis les nouvelles clés sont chargées, et le Mesh repart :

```
<RS>{"v":1,"t":"alerte","n":40,"ms":125030,"quoi":"mesh","diag":"cles_perimees"}
<RS>{"v":1,"t":"alerte","n":61,"ms":133210,"quoi":"mesh","diag":"ok"}
```

### 9.6 Console

Une commande de la console : son texte entre `debut` et `fin`. Le bloc `sante` émis pendant qu'elle tourne porte son `id`.

```
id=7 mesh
```

```
<RS>{"v":1,"t":"reponse","n":300,"ms":700002,"id":7,"etape":"debut","cmd":"mesh","ok":true,"code":"en_cours"}
mesh pret : oui
cles : reseau 1A2B3C4D, application 5E6F7A8B
<RS>{"v":1,"t":"etat","n":301,"ms":700003,"bloc":"sante","boot":"3FA2C901","up_s":700,"commande":7,"led":{"motif":"operationnel","test":false,"depuis_ms":62160},"matter":{"en_service":true,"thread":true,"identifie":false,"ble":false},"sys":{"heap":112640,"heap_min":103424,"heap_bloc":45056,"piles":{"lampes":2104,"json":1460,"console":2876,"socle":1180,"CHIP":1872,"ot_task":1536,"nimble_host":1712,"mesh_adv_task":980,"amaran_tx":1290},"json_perdus":0,"json_trop_longs":0,"rejets":0}}
...
<RS>{"v":1,"t":"reponse","n":302,"ms":700008,"id":7,"etape":"fin","cmd":"mesh","ok":true,"code":"ok","duree_ms":6}
```

Un ordre pour une lampe absente, une commande inconnue, une ligne trop longue (le chargement d'une lampe au nom trop long : rien n'est exécuté), une rafale au-delà de 20 lignes par seconde :

```
<RS>{"v":1,"t":"reponse","n":303,"ms":701000,"id":8,"etape":"fin","cmd":"lampe 9 on","ok":false,"code":"usage","msg":"lampe <1-2> on|off|niveau <0-1000>","duree_ms":0}
<RS>{"v":1,"t":"reponse","n":304,"ms":702000,"id":9,"etape":"debut","cmd":"bonjour","ok":true,"code":"en_cours"}
Commande inconnue : "bonjour" (help)
<RS>{"v":1,"t":"reponse","n":305,"ms":702001,"id":9,"etape":"fin","cmd":"bonjour","ok":false,"code":"inconnue","duree_ms":0}
<RS>{"v":1,"t":"reponse","n":306,"ms":703000,"id":10,"etape":"fin","cmd":"mesh lampe 1 0x0002 02:00:00:00:00:01 40","ok":false,"code":"trop_long","msg":"ligne de plus de 127 octets : rien n'est execute","duree_ms":0}
<RS>{"v":1,"t":"reponse","n":307,"ms":704000,"id":31,"etape":"fin","cmd":"json ping","ok":false,"code":"cadence","msg":"plus de 20 lignes par seconde : rien n'est execute","duree_ms":0}
```

Le chargement des clés : `cmd` ne les cite pas, et le texte ne donne que leurs empreintes.

```
id=32 mesh cles <32 hexa> <32 hexa>
```

```
<RS>{"v":1,"t":"reponse","n":310,"ms":710001,"id":32,"etape":"debut","cmd":"mesh cles","ok":true,"code":"en_cours"}
ok cles 1A2B3C4D 5E6F7A8B (redemarrer pour les appliquer)
<RS>{"v":1,"t":"reponse","n":311,"ms":710022,"id":32,"etape":"fin","cmd":"mesh cles","ok":true,"code":"ok","duree_ms":21}
```

Une commande qui échoue : son texte dit pourquoi.

```
<RS>{"v":1,"t":"reponse","n":312,"ms":711001,"id":33,"etape":"debut","cmd":"mesh lampe 3 masquer","ok":true,"code":"en_cours"}
erreur : mesh lampe <1-2> masquer|afficher
<RS>{"v":1,"t":"reponse","n":313,"ms":711002,"id":33,"etape":"fin","cmd":"mesh lampe 3 masquer","ok":false,"code":"erreur","duree_ms":1}
```

### 9.7 Journal, battement, fin de session

Après `id=34 json log 1`, `id=35 json periode 0` et `id=36 json compteurs 0`, l'app se tait ; 30 s après sa dernière ligne, le bail rend la console texte.

```
<RS>{"v":1,"t":"log","n":400,"ms":720100,"src":"lampes","niv":"alerte","txt":"!! lampe 2 : relectures manquees, 82 % repondues sur 10 min : allonger la periode (mesh releve)"}
<RS>{"v":1,"t":"hb","n":401,"ms":722000,"boot":"3FA2C901","up_s":722,"json_perdus":0,"commande":null}
<RS>{"v":1,"t":"fin","n":415,"ms":751400,"cause":"bail"}
json : mode machine coupe (hote muet depuis 30 s)
amaran>
```
````

- [ ] **Step 2 : les tests.**

`tests/hote/test_json.cpp` (contenu complet) :

````cpp
// Tests sur le Mac du protocole JSON (components/protocole). Les briques reprises du
// pont Halo gardent ses tests (tools/host_tests/test_json.cpp, commit e114cd5) :
// ecrivain, prefixe id=, assemblage, debit, cadence, file, bail. Puis les
// messages du pont amaran : chaque exemple de docs/PROTOCOLE-JSON.md (ligne qui
// commence par <RS>) doit sortir tel quel d'ici, chaque message forme ici doit y
// figurer, et le pire cas de chacun tient dans le budget de 896 octets.
// Lancer : sh tests/hote/lancer.sh. Avec --exemples : imprime les lignes formees.
#include <stdio.h>
#include <string.h>

#include <fstream>
#include <set>
#include <string>

#include "catalogue.h"
#include "json_amaran.h"
#include "json_ligne.h"

using namespace jsonp;

static int gChecks = 0, gFails = 0;
static bool gImprimer = false;

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

static Writer gW;

// Ferme la ligne et la rend telle qu'elle partirait (RS ... LF).
static std::string finish(Writer &w, bool *ok = nullptr) {
  const bool good = w.finish();
  if (ok) *ok = good;
  return std::string((const char *)w.data(), w.size());
}

static std::string framed(const char *json) { return std::string("\x1e") + json + "\n"; }

static void expectLine(Writer &w, const char *json, const char *what) {
  bool ok = false;
  const std::string got = finish(w, &ok);
  const std::string want = framed(json);
  CHECK(ok && got == want, "%s :\n  obtenu  %s  attendu %s", what, got.c_str() + (got.empty() ? 0 : 1),
        want.c_str() + 1);
}

// ---------------------------------------------------------------------------
//  Ecrivain
// ---------------------------------------------------------------------------

static void testWriter() {
  gW.begin("x", 5, 7);
  expectLine(gW, "{\"v\":1,\"t\":\"x\",\"n\":5,\"ms\":7}", "enveloppe seule");

  // Ordre v, t, n, ms, puis bloc ; entiers extremes ; imbrication.
  gW.begin("etat", 4294967295u, 4294967295u);
  gW.str("bloc", "lampe");
  gW.i32("neg", -2147483647 - 1);
  gW.i32("pos", 2147483647);
  gW.u32("zero", 0);
  gW.obj("o");
  gW.arr("a");
  gW.u32(nullptr, 1);
  gW.str(nullptr, "b");
  gW.obj(nullptr);
  gW.boolean("t", true);
  gW.null("z");
  gW.end();
  gW.end();
  gW.boolean("f", false);
  gW.end();
  gW.arr("vide");
  gW.end();
  expectLine(gW,
             "{\"v\":1,\"t\":\"etat\",\"n\":4294967295,\"ms\":4294967295,\"bloc\":\"lampe\",\"neg\":-2147483648,"
             "\"pos\":2147483647,\"zero\":0,\"o\":{\"a\":[1,\"b\",{\"t\":true,\"z\":null}],\"f\":false},\"vide\":[]}",
             "imbrication et entiers extremes");

  // Echappement : '"' et '\', octets de controle -> '?', jamais de \u ; UTF-8 valide garde.
  gW.begin("log", 1, 2);
  gW.str("s", "a\"b\\c\x01\x1e\x7f\xc3\xa9 ~");
  gW.str("tronq", "abcdefgh", 3);
  gW.str("tronq_esc", "\"\"\"\"", 2);  // max compte les octets de la valeur, pas l'echappement
  gW.str("nul", nullptr);
  expectLine(gW,
             "{\"v\":1,\"t\":\"log\",\"n\":1,\"ms\":2,\"s\":\"a\\\"b\\\\c???\xc3\xa9 ~\",\"tronq\":\"abc\","
             "\"tronq_esc\":\"\\\"\\\"\",\"nul\":null}",
             "echappement");

  // Hexa.
  const uint8_t b[3] = {0x0A, 0xFF, 0x2E};
  gW.begin("h", 0, 0);
  gW.hex("b", b, 3);
  gW.hex("vide", b, 0);
  gW.hexU32("boot", 0x3FA2C901, 8);
  gW.hexU32("adresse", 0x7F38, 4);
  gW.hexU32("petit", 0x5, 4);
  expectLine(gW,
             "{\"v\":1,\"t\":\"h\",\"n\":0,\"ms\":0,\"b\":\"0AFF2E\",\"vide\":\"\",\"boot\":\"3FA2C901\","
             "\"adresse\":\"7F38\",\"petit\":\"0005\"}",
             "hexa");

  // Mal ferme : jamais emis.
  bool ok = true;
  gW.begin("x", 0, 0);
  gW.obj("o");
  finish(gW, &ok);
  CHECK(!ok, "objet non ferme accepte");
  gW.begin("x", 0, 0);
  gW.end();
  finish(gW, &ok);
  CHECK(!ok, "fermeture en trop acceptee");

  // Taille : exactement 1024 octets (RS et LF compris) passe, 1025 non.
  for (int extra = 0; extra < 2; extra++) {
    gW.begin("x", 0, 0);
    // enveloppe : RS {"v":1,"t":"x","n":0,"ms":0 = 1 + 27 ; ,"p":"..." = 7 + len ; } LF = 2
    const size_t head = 1 + strlen("{\"v\":1,\"t\":\"x\",\"n\":0,\"ms\":0");
    const size_t pad = kLineMax - head - 7 - 2 + (size_t)extra;
    std::string s(pad, 'a');
    gW.str("p", s.c_str(), pad);
    const bool good = gW.finish();
    CHECK(good == (extra == 0) && (!good || gW.size() == kLineMax), "limite de 1024 octets (extra %d, taille %zu)",
          extra, gW.size());
    CHECK(gW.size() <= kLineMax, "jamais plus de 1024 octets en tampon (%zu)", gW.size());
  }
  // Un depassement enorme reste borne et refuse.
  gW.begin("x", 0, 0);
  for (int i = 0; i < 300; i++) gW.u32("k", 4294967295u);
  CHECK(!gW.finish() && gW.overflow() && gW.size() <= kLineMax, "depassement borne");
}

// Le nom d'une lampe vient d'amaran Desktop : de l'UTF-8 (accents), garde tel quel,
// sauf une sequence invalide ou coupee par la longueur maximale.
static void testUtf8() {
  const uint8_t e[] = {0xC3, 0xA9};               // e accent aigu
  const uint8_t euro[] = {0xE2, 0x82, 0xAC};      // euro
  const uint8_t emoji[] = {0xF0, 0x9F, 0x92, 0xA1};
  CHECK(utf8Seq(e, 2) == 2 && utf8Seq(euro, 3) == 3 && utf8Seq(emoji, 4) == 4, "2, 3 et 4 octets");
  CHECK(utf8Seq(e, 1) == 0 && utf8Seq(euro, 2) == 0, "sequence coupee");
  const uint8_t suite[] = {0xA9}, trop_longue[] = {0xC0, 0xAF}, e0[] = {0xE0, 0x80, 0xAF};
  const uint8_t surrogat[] = {0xED, 0xA0, 0x80}, haut[] = {0xF4, 0x90, 0x80, 0x80}, f5[] = {0xF5, 0x80, 0x80, 0x80};
  const uint8_t mauvaise_suite[] = {0xC3, 0x28};
  CHECK(!utf8Seq(suite, 1) && !utf8Seq(trop_longue, 2) && !utf8Seq(e0, 3) && !utf8Seq(surrogat, 3) &&
            !utf8Seq(haut, 4) && !utf8Seq(f5, 4) && !utf8Seq(mauvaise_suite, 2),
        "octet de suite isole, formes trop longues, surrogat, au-dela de U+10FFFF, mauvaise suite");
  gW.begin("x", 0, 0);
  gW.str("nom", "Lumi\xc3\xa8re fen\xc3\xaatre");
  gW.str("coupe", "ab\xc3\xa9", 3);   // max tombe au milieu du e accent
  gW.str("invalide", "a\xff\xc3(b");
  expectLine(gW,
             "{\"v\":1,\"t\":\"x\",\"n\":0,\"ms\":0,\"nom\":\"Lumi\xc3\xa8re fen\xc3\xaatre\",\"coupe\":\"ab?\","
             "\"invalide\":\"a?" "?(b\"}",  // "?" "?" : pas de trigraphe
             "UTF-8 garde, sequences invalides ou coupees remplacees");
}

// ---------------------------------------------------------------------------
//  Lignes de l'hote
// ---------------------------------------------------------------------------

static bool idOf(const char *line, uint32_t *id, std::string *rest) {
  char buf[256];
  snprintf(buf, sizeof(buf), "%s", line);
  char *r = nullptr;
  const bool ok = parseIdPrefix(buf, id, &r);
  *rest = r;
  return ok;
}

static void testIdPrefix() {
  uint32_t id = 0;
  std::string rest;
  CHECK(idOf("id=17 lampe 1 niveau 500", &id, &rest) && id == 17 && rest == "lampe 1 niveau 500", "id=17");
  CHECK(idOf("  id=1   json 1", &id, &rest) && id == 1 && rest == "json 1", "espaces");
  CHECK(idOf("id=999999999 json ping", &id, &rest) && id == 999999999 && rest == "json ping", "id maximal");
  CHECK(idOf("id=5", &id, &rest) && id == 5 && rest.empty(), "id seul");
  CHECK(idOf("id=007 x", &id, &rest) && id == 7, "zeros de tete");
  CHECK(!idOf("id=0 json 1", &id, &rest) && rest == "id=0 json 1", "id=0 refuse");
  CHECK(!idOf("id=1000000000 json 1", &id, &rest), "id trop grand");
  CHECK(!idOf("id=0000000001 x", &id, &rest), "plus de 9 chiffres");
  CHECK(!idOf("id= 5 x", &id, &rest), "sans chiffre");
  CHECK(!idOf("id=17lampe", &id, &rest), "sans espace apres le numero");
  CHECK(!idOf("id=-3 x", &id, &rest), "negatif");
  CHECK(!idOf("lampe id=3", &id, &rest), "pas en tete");
  CHECK(!idOf("ID=3 x", &id, &rest), "majuscules");
}

static void testMask() {
  char a[] = "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F";
  maskCmd(a);
  CHECK(!strcmp(a, "mesh cles"), "mesh cles : les cles ne reviennent jamais ('%s')", a);
  char b[] = "  mesh   cles 0011";
  maskCmd(b);
  CHECK(!strcmp(b, "mesh cles"), "espaces en trop ('%s')", b);
  char c[] = "mesh lampe 1 masquer";
  maskCmd(c);
  CHECK(!strcmp(c, "mesh lampe 1 masquer"), "le reste passe tel quel");
  char d[] = "mesh clesX 00";
  maskCmd(d);
  CHECK(!strcmp(d, "mesh clesX 00"), "seulement le mot cles");
  // Une ligne trop longue n'est jamais executee, mais sa reponse cite la commande :
  // masquee avant d'etre tronquee.
  char cmd[kCmdTextMax + 1];
  char e[] = "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F 2021222324";
  maskCmd(e);
  copyCmd(cmd, e);
  CHECK(!strcmp(cmd, "mesh cles"), "masquee puis tronquee");
  copyCmd(cmd, "lampe 1 niveau 500 et encore des mots pour depasser");
  CHECK(strlen(cmd) == kCmdTextMax && !strncmp(cmd, "lampe 1 niveau 500 et encore des mots po", kCmdTextMax),
        "copyCmd : '%s'", cmd);
}

static std::string feedAll(LineAssembler &a, const char *bytes, size_t n, int *lines) {
  std::string last;
  for (size_t i = 0; i < n; i++) {
    if (a.feed((uint8_t)bytes[i]) == LineAssembler::Ev::Line) {
      last = a.text();
      last += a.tooLong() ? "|trop long" : "";
      (*lines)++;
      a.reset();
    }
  }
  return last;
}

static void testAssembler() {
  LineAssembler a;
  int lines = 0;
  const char in1[] = "id=1 json 1\r\n";
  CHECK(feedAll(a, in1, sizeof(in1) - 1, &lines) == "id=1 json 1" && lines == 1, "ligne simple, CR ignore");
  // RS, echappement et autres octets de controle ignores ; octets hauts gardes (UTF-8).
  lines = 0;
  const char in2[] = "le\x1e" "d\x1b\x01 test\n";
  CHECK(feedAll(a, in2, sizeof(in2) - 1, &lines) == "led test" && lines == 1, "octets de controle filtres");
  lines = 0;
  const char in3[] = "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 Lumi\xc3\xa8re\n";
  CHECK(feedAll(a, in3, sizeof(in3) - 1, &lines) == "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 Lumi\xc3\xa8re" &&
            lines == 1,
        "nom en UTF-8 garde");
  // Ctrl-U vide la ligne ; retour arriere.
  lines = 0;
  const char in4[] = "reste d'une session\x15" "\nid=2 json pinh\x08g\n";
  a.reset();
  std::string last = feedAll(a, in4, sizeof(in4) - 1, &lines);
  CHECK(lines == 2 && last == "id=2 json ping", "Ctrl-U puis retour arriere : %d ligne(s), '%s'", lines, last.c_str());
  a.reset();
  a.feed('a');
  a.feed('b');
  CHECK(a.feed(kCtrlU) == LineAssembler::Ev::Clear && a.length() == 0, "Ctrl-U");
  CHECK(a.feed(8) == LineAssembler::Ev::None, "retour arriere sur ligne vide");
  // 127 octets passent, 128 marquent la ligne trop longue ; la suivante repart.
  for (int extra = 0; extra < 2; extra++) {
    a.reset();
    lines = 0;
    std::string s(kCmdMax + (size_t)extra, 'x');
    s += "\n";
    last = feedAll(a, s.c_str(), s.size(), &lines);
    CHECK(lines == 1 && (extra ? last.size() == kCmdMax + strlen("|trop long") : last.size() == kCmdMax),
          "limite de 127 (extra %d) : %zu", extra, last.size());
  }
  lines = 0;
  last = feedAll(a, "ok\n", 3, &lines);
  CHECK(last == "ok", "apres une ligne trop longue");
  // Ctrl-U efface aussi le depassement.
  a.reset();
  std::string s(200, 'y');
  s += "\x15" "json\n";
  lines = 0;
  last = feedAll(a, s.c_str(), s.size(), &lines);
  CHECK(last == "json", "Ctrl-U apres depassement : '%s'", last.c_str());
}

// ---------------------------------------------------------------------------
//  Debit, cadence, file, bail
// ---------------------------------------------------------------------------

static void testRate() {
  RateCap cap(20);
  uint32_t t = 0u - 300;  // a travers le retour a zero de l'horloge
  unsigned passed = 0;
  for (int i = 0; i < 50; i++) {
    if (cap.available(t)) {
      cap.take();
      passed++;
    } else {
      cap.skip();
    }
    t += 10;  // 50 evenements en 500 ms
  }
  CHECK(passed == 20 && cap.takeSkipped() == 30 && cap.takeSkipped() == 0, "20 par seconde : %u", passed);
  t += 1000;
  CHECK(cap.available(t), "nouvelle fenetre");
  // Cadence : 20 lignes par seconde glissante.
  Cadence c;
  uint32_t now = 1000;
  int ok = 0;
  for (int i = 0; i < 25; i++) ok += c.allow(now + (uint32_t)i * 10);  // 25 lignes en 250 ms
  CHECK(ok == 20, "cadence : %d lignes acceptees sur 25", ok);
  CHECK(!c.allow(now + 999), "21e ligne dans la seconde");
  CHECK(c.allow(now + 1000), "la plus ancienne sort de la fenetre");
  CHECK(!c.allow(now + 1001), "une seule place liberee");
  CHECK(c.allow(now + 1010), "la suivante sort a son tour");
}

static void testQueue() {
  Queue q;
  CHECK(q.push(Item::EtatPont, 0, true) && q.push(Item::EtatSante, 1, true) && q.size() == 2, "deux elements");
  CHECK(q.push(Item::EtatPont, 2, true) && q.size() == 2, "doublon ignore");
  CHECK(q.push(Item::EtatLampe, 2, true, 0) && q.push(Item::EtatLampe, 2, true, 1) && q.size() == 4,
        "une ligne par lampe : l'argument distingue");
  CHECK(q.push(Item::EtatLampe, 3, true, 1) && q.size() == 4 && q.has(Item::EtatLampe, 1) &&
            !q.has(Item::EtatLampe, 2),
        "meme lampe : fondue");
  CHECK(q.push(Item::Reply, 3, false, 1) && q.push(Item::Reply, 3, false, 2) && q.size() == 6, "reponses jamais fondues");
  CHECK(q.push(Item::EtatSante, 4, false) && q.size() == 6, "doublon explicite");
  CHECK(q.dropSession() == 3 && q.size() == 3, "fin de session : %u restent", q.size());
  const Queued *f = q.front();
  CHECK(f && f->item == Item::EtatSante && !f->session && f->at == 4, "sante promue, gardee a sa place, retard depuis la demande");
  q.pop();
  f = q.front();
  CHECK(f && f->item == Item::Reply && f->arg == 1, "ordre garde");
  q.clear();
  int pushed = 0;
  for (int i = 0; i < 60; i++) pushed += q.push(Item::Reply, (uint32_t)i, false, (uint8_t)i);
  CHECK(pushed == Queue::kN && q.size() == Queue::kN, "file pleine a %u", q.size());
  CHECK(!q.push(Item::ConfigMesh, 50, false), "rien de plus");
  for (int i = 0; i < 5; i++) q.pop();
  CHECK(q.push(Item::ConfigMesh, 51, false) && q.has(Item::ConfigMesh), "place rendue");
  uint8_t prev = 4;
  bool order = true;
  while (const Queued *e = q.front()) {
    if (e->item == Item::Reply) {
      order &= e->arg == prev + 1;
      prev = e->arg;
    }
    q.pop();
  }
  CHECK(order, "ordre FIFO a travers le tour de l'anneau");
  // Un instantane complet a 16 lampes tient dans la file : hello (2), catalogue,
  // mesh, 16 config, pont, 16 etat, sante, compteurs, reseau (2), reponse.
  q.clear();
  int n = 0;
  n += q.push(Item::HelloBase, 0, true) + q.push(Item::HelloId, 0, true) + q.push(Item::ConfigCatalogue, 0, true) +
       q.push(Item::ConfigMesh, 0, true);
  for (uint8_t i = 0; i < LISTE_CAPACITE; i++) n += q.push(Item::ConfigLampe, 0, true, i);
  n += q.push(Item::EtatPont, 0, true);
  for (uint8_t i = 0; i < LISTE_CAPACITE; i++) n += q.push(Item::EtatLampe, 0, true, i);
  n += q.push(Item::EtatSante, 0, true) + q.push(Item::CptMesh, 0, true) + q.push(Item::NetMatter, 0, true) +
       q.push(Item::NetThread, 0, true) + q.push(Item::Reply, 0, false, 0);
  CHECK(n == 42 && q.size() == 42, "instantane a 16 lampes : %d lignes en file", n);
}

// Retard (500 ms) : la garde de la tache json.
static void testQueueDrain() {
  Queue q;
  CHECK(!q.front() && q.dropLate(1000) == 0, "file vide");
  q.push(Item::EtatPont, 0, true);
  q.push(Item::EtatSante, 100, true);
  q.push(Item::Reply, 200, false, 0);
  q.push(Item::CptMesh, 250, true);
  CHECK(q.dropLate(500) == 0 && q.size() == 4, "500 ms tout juste : rien de perdu");
  CHECK(q.dropLate(700) == 2 && q.front()->item == Item::Reply, "deux periodiques perdues, la reponse arrete le balayage");
  CHECK(q.dropLate(1000000) == 0 && q.size() == 2, "une reponse n'est jamais perdue pour retard");
  q.pop();
  CHECK(q.front()->item == Item::CptMesh && q.dropLate(1000000) == 1 && !q.size(),
        "derriere la reponse, la periodique en retard est perdue a son tour");
  // Fusion : une demande explicite repart de maintenant, pas une periodique.
  q.push(Item::EtatSante, 0, true);
  q.push(Item::EtatSante, 450, false);
  CHECK(q.size() == 1 && !q.front()->session && q.front()->at == 450, "json etat fondu dans une periodique");
  CHECK(q.dropLate(950) == 0 && q.dropLate(951) == 1, "retard compte depuis la demande explicite");
  q.push(Item::EtatPont, 0, true);
  q.push(Item::EtatPont, 400, true);
  CHECK(q.front()->at == 0 && q.dropLate(501) == 1, "periodique fondue : garde son retard");
  q.clear();
  q.push(Item::HelloBase, 0, false);
  q.push(Item::HelloBase, 300, true);
  CHECK(!q.front()->session && q.front()->at == 0, "periodique fondue dans une demande explicite : ni session, ni retard remis");
}

static void testLease() {
  CHECK(!leaseExpired(1000000, 0, 0, 0), "sans bail : jamais");
  CHECK(!leaseExpired(30999, 1000, 500, 30) && leaseExpired(31000, 1000, 500, 30), "30 s apres le dernier octet");
  // Commande longue de 60 s : le bail part de sa fin.
  CHECK(!leaseExpired(90000, 1000, 70000, 30) && leaseExpired(100000, 1000, 70000, 30), "30 s apres la fin de la commande");
  const uint32_t rx = 0xFFFFF000u;
  CHECK(!leaseExpired(rx + 29999u, rx, rx - 0x1000u, 30) && leaseExpired(rx + 30000u, rx, rx - 0x1000u, 30),
        "a travers le retour a zero de l'horloge");
  CHECK(!leaseExpired(9999, 0, 0, 10) && leaseExpired(600000, 0, 0, 600), "bornes 10 et 600 s");
}

// ---------------------------------------------------------------------------
//  Messages du pont amaran, et exemples du document
// ---------------------------------------------------------------------------

static std::set<std::string> gDoc;   // lignes <RS> du document, sans RS ni LF
static std::set<std::string> gVues;  // lignes formees par les exemples ci-dessous

static void lireDocument() {
  std::ifstream f("docs/PROTOCOLE-JSON.md");
  CHECK(f.good(), "docs/PROTOCOLE-JSON.md introuvable (lancer depuis la racine du depot)");
  std::string l;
  while (std::getline(f, l)) {
    if (l.compare(0, 4, "<RS>") == 0) gDoc.insert(l.substr(4));
  }
}

// La ligne formee est un exemple du document : elle doit y figurer telle quelle.
static void exemple(Writer &w, const char *what) {
  bool ok = false;
  const std::string got = finish(w, &ok);
  CHECK(ok && got.size() >= 2 && got[0] == '\x1e' && got.back() == '\n', "%s : ligne mal formee", what);
  CHECK(got.size() <= kBudget, "%s : %zu octets, au-dela du budget de %zu", what, got.size(), kBudget);
  const std::string json = got.substr(1, got.size() - 2);
  gVues.insert(json);
  if (gImprimer) printf("%s\t<RS>%s\n", what, json.c_str());
  CHECK(gDoc.count(json), "%s : absente du document :\n  <RS>%s", what, json.c_str());
}

// Deux lampes de demonstration (MAC inventees, adresses de la base d'amaran Desktop).
static liste_lampe_t lampeListe(uint16_t adresse, uint8_t dernier, const char *nom, uint16_t ep) {
  liste_lampe_t l;
  memset(&l, 0, sizeof(l));
  l.adresse = adresse;
  const uint8_t mac[6] = {0x02, 0x00, 0x00, 0x00, 0x00, dernier};
  memcpy(l.mac, mac, 6);
  snprintf(l.nom, sizeof(l.nom), "%s", nom);
  l.code = CATALOGUE_CODE_COB_60D;
  l.endpoint = ep;
  l.drapeaux = LISTE_VUE;
  return l;
}

static lampe_t lampeLue(uint16_t adresse, bool marche, uint16_t intensite, uint32_t reponse, uint32_t repondues) {
  lampe_t p;
  memset(&p, 0, sizeof(p));
  p.adresse = adresse;
  p.entendue = p.connu = p.joignable = true;
  p.lu.marche = marche;
  p.lu.intensite = intensite;
  p.memoire = intensite;
  p.reponse_ms = reponse;
  p.releves_repondues = repondues;
  return p;
}

static const uint32_t kBoot = 0x3FA2C901;
static const Pile kPiles[] = {{"lampes", 2104}, {"json", 1460},       {"console", 2876},
                              {"socle", 1180},  {"CHIP", 1872},       {"ot_task", 1536},
                              {"nimble_host", 1712}, {"mesh_adv_task", 980}, {"amaran_tx", 1290}};

static EtatSante sante(uint32_t ms) {
  EtatSante e;
  e.boot = kBoot;
  e.upS = ms / 1000;
  e.motif = "operationnel";
  e.depuisMs = 62160;
  e.enService = e.threadAttache = true;
  e.heap = 112640;
  e.heapMin = 103424;
  e.heapBloc = 45056;
  e.piles = kPiles;
  e.nPiles = sizeof(kPiles) / sizeof(kPiles[0]);
  return e;
}

static void testExemples() {
  const liste_lampe_t l1 = lampeListe(0x0002, 0x01, "Lampe bureau", 2);
  liste_lampe_t l2 = lampeListe(0x0004, 0x02, "Lumi\xc3\xa8re fen\xc3\xaatre", 3);
  lampe_t p1 = lampeLue(0x0002, true, 430, 83390, 40);
  lampe_t p2 = lampeLue(0x0004, false, 600, 83398, 41);

  // 9.1 Connexion : instantane de 'json 1'.
  HelloBase hb;
  hb.fw = "0.1.0-d569f01";
  hb.date = "Oct  5 2026";
  hb.heure = "14:02:11";
  hb.idf = "v5.5.4";
  hb.puce = "esp32c6";
  hb.boot = kBoot;
  hb.reset = "logiciel";
  hb.resetN = 3;
  hb.upS = 83;
  helloBase(gW, 0, 83512, hb);
  exemple(gW, "hello base");
  HelloId hi;
  hi.boot = kBoot;
  const uint8_t mac[6] = {0xF0, 0xF5, 0xBD, 0x0A, 0x0B, 0x0C};
  memcpy(hi.mac, mac, 6);
  hi.fabricant = "TEST_VENDOR";
  hi.produit = "TEST_PRODUCT";
  hi.serie = "AMARAN-F0F5BD0A0B0C";
  hi.nom = "Pont amaran";
  helloId(gW, 1, 83522, hi);
  exemple(gW, "hello identite");
  configCatalogue(gW, 2, 83532);
  exemple(gW, "config catalogue");
  ConfigMesh cm;
  cm.cles = true;
  cm.empReseau = "1A2B3C4D";
  cm.empApp = "5E6F7A8B";
  cm.adresse = 0x7F38;
  cm.fenetreMs = 20;
  cm.intervalleMs = 40;
  cm.lampes = 2;
  cm.releveMs = 2000;
  configMesh(gW, 3, 83542, cm);
  exemple(gW, "config mesh");
  configLampe(gW, 4, 83552, 0, l1);
  exemple(gW, "config lampe 1");
  configLampe(gW, 5, 83562, 1, l2);
  exemple(gW, "config lampe 2 (UTF-8)");
  EtatPont ep;
  ep.boot = kBoot;
  ep.upS = 83;
  ep.meshPret = true;
  ep.ordres = 6;
  ep.confirmes = 5;
  ep.tenus = 1;
  ep.delaiTotalMs = 2150;
  ep.delaiMaxMs = 620;
  ep.releves = 41;
  ep.trames = 80;
  etatPont(gW, 6, 83572, ep);
  exemple(gW, "etat pont");
  etatLampe(gW, 7, 83582, 0, p1, l1, 2, 97);
  exemple(gW, "etat lampe 1");
  etatLampe(gW, 8, 83592, 1, p2, l2, 3, 100);
  exemple(gW, "etat lampe 2");
  etatSante(gW, 9, 83602, sante(83602));
  exemple(gW, "etat sante");
  CompteursMesh c;
  c.annonces = 5120;
  c.nidReconnu = 1630;
  c.nidInconnu = 3402;
  c.accesDechiffres = 1500;
  c.etatsLampes = 81;
  c.doublons = 77;
  c.balisesNotres = 17;
  c.baliseVue = true;
  c.baliseMs = 81870;
  c.emis = 64;
  c.seq = 1093;
  c.plancher = 1024;
  compteursMesh(gW, 10, 83612, c);
  exemple(gW, "compteurs mesh");
  ReseauMatter rm;
  rm.demarre = true;
  rm.fabriques = 1;
  rm.demandes = rm.plafonnes = rm.etablis = 2;
  rm.termines = 1;
  rm.plafondS = 20;
  rm.codeManuel = "34970112332";
  rm.qr = "MT:Y.K9042C00KA0648G00";
  reseauMatter(gW, 11, 83622, rm);
  exemple(gW, "reseau matter");
  reseauThread(gW, 12, 83632, "child", true);
  exemple(gW, "reseau thread");
  Reply r;
  r.id = 1;
  r.cmd = "json 1";
  r.durMs = 130;
  r.hasLease = true;
  r.leaseS = 30;
  r.upS = 83;
  reply(gW, 13, 83642, r);
  exemple(gW, "reponse json 1");

  // 9.2 Ordre : accepte, en cours, confirme, voyant.
  r = Reply();
  r.id = 2;
  r.cmd = "lampe 1 niveau 500";
  r.code = "accepte";
  r.suite = Reply::SuiteOrder;
  r.lampe = 1;
  reply(gW, 31, 95002, r);
  exemple(gW, "reponse accepte");
  p1.phase = LAMPE_TRAMES;
  p1.essai = 1;
  p1.veut_intensite = true;
  p1.consigne.intensite = 500;
  etatLampe(gW, 32, 95010, 0, p1, l1, 2, 97);
  exemple(gW, "etat lampe, ordre en cours");
  Ordre o;
  o.lampe = 0;
  o.delaiMs = 410;
  o.essai = 1;
  o.ids[0] = 2;
  o.nIds = 1;
  ordre(gW, 33, 95412, o);
  exemple(gW, "ordre confirme");
  led(gW, 34, 95413, "livree", "operationnel", false, 0);
  exemple(gW, "led livree");
  p1.phase = LAMPE_REPOS;
  p1.veut_intensite = false;
  p1.lu.intensite = 500;
  p1.reponse_ms = 95410;
  p1.releves_repondues = 46;
  etatLampe(gW, 35, 95420, 0, p1, l1, 2, 97);
  exemple(gW, "etat lampe, confirmee");
  led(gW, 36, 95563, "operationnel", "livree", false, 74000);
  exemple(gW, "led operationnel");

  // 9.3 Deja tenu, abandon, alerte.
  r = Reply();
  r.id = 3;
  r.cmd = "lampe 2 off";
  r.code = "accepte";
  r.suite = Reply::SuiteOrder;
  r.lampe = 2;
  reply(gW, 40, 101002, r);
  exemple(gW, "reponse accepte, lampe 2");
  o = Ordre();
  o.lampe = 1;
  o.issue = "tenu";
  o.ids[0] = 3;
  o.nIds = 1;
  ordre(gW, 41, 101003, o);
  exemple(gW, "ordre tenu");
  o = Ordre();
  o.lampe = 1;
  o.issue = "abandon";
  o.delaiMs = 3700;
  o.essai = 3;
  o.ids[0] = 4;
  o.nIds = 1;
  ordre(gW, 52, 108705, o);
  exemple(gW, "ordre abandon");
  led(gW, 53, 108706, "injoignable", "operationnel", false, 0);
  exemple(gW, "led injoignable");
  alerteReleves(gW, 210, 603000, 1, true, 82);
  exemple(gW, "alerte releves");

  // 9.4 Maison : retirer, remettre, premiere reponse.
  r = Reply();
  r.id = 5;
  r.fin = false;
  r.cmd = "mesh lampe 2 masquer";
  r.code = "en_cours";
  reply(gW, 220, 640001, r);
  exemple(gW, "reponse debut masquer");
  r.fin = true;
  r.code = "ok";
  r.durMs = 38;
  reply(gW, 221, 640039, r);
  exemple(gW, "reponse fin masquer");
  lampe(gW, 222, 640040, 1, "masquee", 0);
  exemple(gW, "lampe masquee");
  lampe(gW, 230, 652100, 1, "remise", 3);
  exemple(gW, "lampe remise");
  lampe(gW, 12, 21402, 2, "entree", 4);
  exemple(gW, "lampe entree");

  // 9.5 Bluetooth Mesh inoperant.
  alerteMesh(gW, 40, 125030, "cles_perimees");
  exemple(gW, "alerte mesh");
  alerteMesh(gW, 61, 133210, "ok");
  exemple(gW, "alerte mesh ok");

  // 9.6 Console : commande, usage, inconnue, trop longue, cadence, cles masquees.
  r = Reply();
  r.id = 7;
  r.fin = false;
  r.cmd = "mesh";
  r.code = "en_cours";
  reply(gW, 300, 700002, r);
  exemple(gW, "reponse debut mesh");
  EtatSante es = sante(700003);
  es.cmdId = 7;
  etatSante(gW, 301, 700003, es);
  exemple(gW, "etat sante, commande en cours");
  r.fin = true;
  r.code = "ok";
  r.durMs = 6;
  reply(gW, 302, 700008, r);
  exemple(gW, "reponse fin mesh");
  r = Reply();
  r.id = 8;
  r.cmd = "lampe 9 on";
  r.ok = false;
  r.code = "usage";
  r.msg = "lampe <1-2> on|off|niveau <0-1000>";
  reply(gW, 303, 701000, r);
  exemple(gW, "reponse usage");
  r = Reply();
  r.id = 9;
  r.fin = false;
  r.cmd = "bonjour";
  r.code = "en_cours";
  reply(gW, 304, 702000, r);
  exemple(gW, "reponse debut inconnue");
  r.fin = true;
  r.ok = false;
  r.code = "inconnue";
  reply(gW, 305, 702001, r);
  exemple(gW, "reponse inconnue");
  r = Reply();
  r.id = 10;
  r.cmd = "mesh lampe 1 0x0002 02:00:00:00:00:01 40";
  r.ok = false;
  r.code = "trop_long";
  r.msg = "ligne de plus de 127 octets : rien n'est execute";
  reply(gW, 306, 703000, r);
  exemple(gW, "reponse trop longue");
  r = Reply();
  r.id = 31;
  r.cmd = "json ping";
  r.ok = false;
  r.code = "cadence";
  r.msg = "plus de 20 lignes par seconde : rien n'est execute";
  reply(gW, 307, 704000, r);
  exemple(gW, "reponse cadence");
  r = Reply();
  r.id = 32;
  r.fin = false;
  r.cmd = "mesh cles";
  r.code = "en_cours";
  reply(gW, 310, 710001, r);
  exemple(gW, "reponse debut mesh cles");
  r.fin = true;
  r.code = "ok";
  r.durMs = 21;
  reply(gW, 311, 710022, r);
  exemple(gW, "reponse fin mesh cles");
  r = Reply();
  r.id = 33;
  r.fin = false;
  r.cmd = "mesh lampe 3 masquer";
  r.code = "en_cours";
  reply(gW, 312, 711001, r);
  exemple(gW, "reponse debut erreur");
  r.fin = true;
  r.ok = false;
  r.code = "erreur";
  r.durMs = 1;
  reply(gW, 313, 711002, r);
  exemple(gW, "reponse erreur");

  // 9.7 Journal, battement, fin de session.
  logLine(gW, 400, 720100, "lampes", "alerte",
          "!! lampe 2 : relectures manquees, 82 % repondues sur 10 min : allonger la periode (mesh releve)", 0);
  exemple(gW, "log");
  heartbeat(gW, 401, 722000, kBoot, 722, 0, 0);
  exemple(gW, "hb");
  sessionEnd(gW, 415, 751400, "bail");
  exemple(gW, "fin");

  // Chaque exemple du document a ete forme ici.
  for (const std::string &d : gDoc) CHECK(gVues.count(d), "exemple du document jamais forme :\n  <RS>%s", d.c_str());
}

// Pire cas de chaque message : 16 lampes, noms de 31 octets, compteurs au maximum.
static void testPiresCas() {
  const uint32_t M = 4294967295u;
  bool ok = false;
  liste_lampe_t l;
  memset(&l, 0xFF, sizeof(l));
  memset(l.nom, '"', LISTE_NOM_MAX - 1);  // 31 guillemets : 62 octets echappes
  l.nom[LISTE_NOM_MAX - 1] = 0;
  l.code = M;
  configLampe(gW, M, M, LISTE_CAPACITE - 1, l);
  std::string s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "config lampe : %zu octets", s.size());
  lampe_t p;
  memset(&p, 0xFF, sizeof(p));
  p.phase = LAMPE_ATTENTE;
  p.veut_marche = p.veut_intensite = true;
  p.consigne.intensite = 65535;
  p.lu.intensite = 65535;
  p.essai = 255;
  etatLampe(gW, M, M, LISTE_CAPACITE - 1, p, l, 65535, 100);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat lampe : %zu octets", s.size());
  HelloBase hb;
  std::string longue(64, 'x');
  hb.fw = hb.date = hb.heure = hb.idf = hb.puce = hb.reset = longue.c_str();
  hb.boot = hb.upS = M;
  hb.resetN = 255;
  hb.session.periodeMs = hb.session.lampesMs = hb.session.compteursMs = hb.session.reseauMs = M;
  hb.session.bailS = 65535;
  helloBase(gW, M, M, hb);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "hello base : %zu octets", s.size());
  HelloId hi;
  hi.boot = M;
  hi.fabricant = hi.produit = hi.serie = hi.nom = longue.c_str();
  helloId(gW, M, M, hi);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "hello identite : %zu octets", s.size());
  configCatalogue(gW, M, M);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "config catalogue : %zu octets (une ligne par modele au-dela)", s.size());
  ConfigMesh cm;
  cm.cles = true;
  cm.empReseau = cm.empApp = longue.c_str();
  cm.adresse = 65535;
  cm.ivNvs = cm.releveMs = M;
  cm.fenetreMs = cm.intervalleMs = 65535;
  cm.lampes = 255;
  configMesh(gW, M, M, cm);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "config mesh : %zu octets", s.size());
  EtatPont ep;
  ep.boot = ep.upS = ep.ordres = ep.confirmes = ep.abandons = ep.tenus = M;
  ep.delaiTotalMs = ep.delaiMaxMs = ep.lents = ep.releves = ep.trames = M;
  ep.diag = "cles_absentes";
  etatPont(gW, M, M, ep);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat pont : %zu octets", s.size());
  Pile piles[9];
  const char *noms[9] = {"lampes", "json", "console", "socle", "CHIP", "ot_task", "nimble_host", "mesh_adv_task",
                         "amaran_tx"};
  for (int i = 0; i < 9; i++) piles[i] = Pile{noms[i], 2147483647};
  EtatSante e;
  e.boot = e.upS = e.depuisMs = e.heap = e.heapMin = e.heapBloc = e.perdus = e.tropLongs = e.rejets = M;
  e.cmdId = kIdMax;
  e.motif = "identification";
  e.piles = piles;
  e.nPiles = 9;
  etatSante(gW, M, M, e);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat sante : %zu octets", s.size());
  CompteursMesh c;
  c.annonces = c.nidReconnu = c.nidInconnu = c.netmicFaux = c.accesDechiffres = c.etatsLampes = c.doublons = M;
  c.balisesNotres = c.balisesAutres = c.balisesFausses = c.baliseIv = c.baliseMs = M;
  c.baliseVue = true;
  c.baliseDrapeaux = 255;
  c.emis = c.echecsEmission = c.filePleine = c.iv = c.seq = c.plancher = M;
  compteursMesh(gW, M, M, c);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "compteurs mesh : %zu octets", s.size());
  ReseauMatter rm;
  rm.fabriques = 255;
  rm.demandes = rm.plafonnes = rm.etablis = rm.termines = M;
  rm.plafondS = 65535;
  rm.codeManuel = rm.qr = longue.c_str();
  reseauMatter(gW, M, M, rm);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reseau matter : %zu octets", s.size());
  Ordre o;
  o.lampe = LISTE_CAPACITE - 1;
  o.delaiMs = o.idsPerdus = M;
  o.essai = 255;
  for (uint8_t i = 0; i < kIdsMax; i++) o.ids[i] = kIdMax;
  o.nIds = kIdsMax;
  ordre(gW, M, M, o);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "ordre : %zu octets", s.size());
  Reply r;
  r.id = kIdMax;
  r.fin = true;
  std::string cmd(200, '"');
  r.cmd = cmd.c_str();
  r.ok = false;
  r.code = "deja_traite";
  r.msg = cmd.c_str();
  r.durMs = M;
  r.suite = Reply::SuiteOrder;
  r.lampe = 255;
  r.hasLease = true;
  r.leaseS = r.upS = M;
  reply(gW, M, M, r);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reponse : %zu octets", s.size());
  std::string txt(300, '"');
  logLine(gW, M, M, "lampes", "alerte", txt.c_str(), M);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "log : %zu octets", s.size());
}

int main(int argc, char **argv) {
  gImprimer = argc > 1 && !strcmp(argv[1], "--exemples");
  lireDocument();
  testWriter();
  testUtf8();
  testIdPrefix();
  testMask();
  testAssembler();
  testRate();
  testQueue();
  testQueueDrain();
  testLease();
  testExemples();
  testPiresCas();
  printf("json : %d verifications, %d echecs\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
````

`tests/hote/lancer.sh`, bloc 1 sur 1. Remplacer :

````sh
"$SORTIE/test_socle"

echo "tests hote : tout est vert"
````

par :

````sh
"$SORTIE/test_socle"

# Protocole JSON (components/protocole) : C++17, avec le catalogue (C) ; lit les exemples
# de docs/PROTOCOLE-JSON.md.
"$CC" $CFLAGS -c components/liste/catalogue.c -o "$SORTIE/catalogue.o"
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/protocole/include -Icomponents/liste/include \
  -Icomponents/lampes/include -Icomponents/telink/include components/protocole/json_ligne.cpp \
  components/protocole/json_amaran.cpp tests/hote/test_json.cpp "$SORTIE/catalogue.o" -o "$SORTIE/test_json"
"$SORTIE/test_json"

echo "tests hote : tout est vert"
````

- [ ] **Step 3 : lancer les tests, ils échouent.**

Run: `sh tests/hote/lancer.sh`
Expected: FAIL à la compilation de `test_json.cpp` (`json_amaran.h` introuvable).

- [ ] **Step 4 : le composant.**

`components/protocole/CMakeLists.txt` (contenu complet) :

````cmake
# Protocole JSON du pont (docs/PROTOCOLE-JSON.md) : briques pures reprises du
# pont Halo (commit e114cd5) et messages du pont amaran. Teste sur le Mac
# (tests/hote/test_json.cpp). Pas "json" : c'est le nom du composant cJSON d'ESP-IDF.
idf_component_register(SRCS "json_ligne.cpp" "json_amaran.cpp"
                       INCLUDE_DIRS "include"
                       REQUIRES lampes liste)
````

`components/protocole/include/json_ligne.h` (contenu complet) :

````c
#pragma once
// ===========================================================================
//  Protocole JSON du pont, v1 (docs/PROTOCOLE-JSON.md) : briques pures
//
//  Reprises de json_out.h du pont Halo (commit e114cd5), sans ses messages
//  propres a la lampe BenQ :
//  - Writer : une ligne machine, RS + objet JSON compact + LF, 1024 octets au
//    plus (section 2.2). Chaines echappees ('"' et '\') ; octet de controle
//    remplace par '?' ; UTF-8 valide garde tel quel (noms des lampes), tout
//    autre octet haut remplace par '?' ; jamais de \uXXXX. Au-dela de 1024
//    octets, la ligne est marquee trop longue : jamais emise.
//  - Messages communs : reponse, battement, fin de session, voyant, journal.
//  - Mecaniques de la session : prefixe id= des lignes de l'hote, assemblage
//    des lignes recues, plafonds de debit, cadence, file des lignes
//    periodiques, bail.
//
//  Pur et sans ESP-IDF : teste sur le Mac (tests/hote/test_json.cpp). La
//  session, l'ecriture sur l'USB et les instantanes sont dans
//  firmware/main/json_pont.cpp.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

namespace jsonp {

constexpr uint8_t kVersion = 1;         // v : version majeure
constexpr uint8_t kRev = 0;             // hello.rev : revision mineure (ajouts)
constexpr size_t kLineMax = 1024;       // RS et LF compris
constexpr size_t kBudget = 896;         // pire cas vise par message (marge de 128 pour les ajouts)
constexpr size_t kCmdMax = 127;         // ligne de l'hote, prefixe id= compris
constexpr size_t kCmdTextMax = 40;      // reponse.cmd
constexpr size_t kMsgMax = 120;         // reponse.msg
constexpr size_t kLogTextMax = 127;     // log.txt
constexpr size_t kStrMax = 255;         // toute autre chaine
constexpr uint8_t kRS = 0x1E;
constexpr uint8_t kCtrlU = 0x15;        // vide la ligne en cours de saisie
constexpr uint32_t kIdMax = 999999999;  // id=<1..999999999>

// ---------------------------------------------------------------------------
//  Ecrivain d'une ligne machine
// ---------------------------------------------------------------------------

class Writer {
 public:
  // Ouvre la ligne : RS {"v":1,"t":type,"n":n,"ms":ms. Le champ suivant d'un
  // message en blocs est "bloc" (str("bloc", ...)).
  void begin(const char *type, uint32_t n, uint32_t ms);
  // Champs. k nul : element du tableau ouvert. Les cles sont des litteraux
  // ASCII du firmware, jamais echappees.
  void str(const char *k, const char *v, size_t max = kStrMax);  // v nul : null ; max octets de v
  void u32(const char *k, uint32_t v);
  void i32(const char *k, int32_t v);
  void boolean(const char *k, bool v);
  void null(const char *k);
  void hex(const char *k, const uint8_t *p, size_t n);  // "C5A5" (majuscules, sans 0x) ; n == 0 : ""
  void hexU32(const char *k, uint32_t v, uint8_t digits);  // "3FA2C901", "7F38"
  void obj(const char *k);
  void arr(const char *k);
  void end();  // ferme l'objet ou le tableau ouvert
  // Ferme la ligne (} LF). false : plus de kLineMax octets, ou objets mal
  // fermes (bogue) ; la ligne ne doit pas etre emise.
  bool finish();
  const uint8_t *data() const { return buf_; }
  size_t size() const { return len_; }
  bool overflow() const { return over_; }

 private:
  static constexpr uint8_t kDepth = 8;
  void put(char c);
  void puts(const char *s);
  void sep(const char *k);
  void num(uint32_t v, bool neg);
  void open(const char *k, char o, char c);
  uint8_t buf_[kLineMax];
  size_t len_ = 0;
  bool over_ = false, bad_ = false;
  uint8_t depth_ = 0;
  bool first_[kDepth] = {};
  char close_[kDepth] = {};
};

// Longueur de la sequence UTF-8 valide qui commence en s (2 a 4 octets, s[0]
// >= 0x80), au plus n octets lus ; 0 si elle n'est pas valide (octet de
// suite isole, sequence trop longue ou coupee, surrogat, au-dela de U+10FFFF).
size_t utf8Seq(const uint8_t *s, size_t n);

// ---------------------------------------------------------------------------
//  Messages communs
// ---------------------------------------------------------------------------

// cmdId : id de la commande de la console en cours (0 : null), comme le bloc sante.
void heartbeat(Writer &w, uint32_t n, uint32_t ms, uint32_t boot, uint32_t upS, uint32_t lost, uint32_t cmdId);
void sessionEnd(Writer &w, uint32_t n, uint32_t ms, const char *cause);  // t "fin" : commande, bail
void led(Writer &w, uint32_t n, uint32_t ms, const char *motif, const char *before, bool test, uint32_t depuisMs);
void logLine(Writer &w, uint32_t n, uint32_t ms, const char *src, const char *niv, const char *txt, uint32_t skipped);

// Message reponse (section 6.3).
struct Reply {
  enum Suite : uint8_t { SuiteNone, SuiteOrder, SuiteNothing };  // absent, ordre, aucune
  uint32_t id = 0;
  bool fin = true;              // false : etape debut
  const char *cmd = "";         // la commande sans le prefixe, tronquee a kCmdTextMax
  bool ok = true;
  const char *code = "ok";
  const char *msg = nullptr;    // nul : absent ; tronque a kMsgMax
  uint32_t durMs = 0;           // fin seulement
  Suite suite = SuiteNone;
  uint8_t lampe = 0;            // ordre d'une lampe (suite ordre) : son numero, 1..16 ; 0 : absent
  bool hasLease = false;        // bail_s, up_s (json 1, json ping)
  uint32_t leaseS = 0, upS = 0;
};
void reply(Writer &w, uint32_t n, uint32_t ms, const Reply &r);

// ---------------------------------------------------------------------------
//  Lignes de l'hote
// ---------------------------------------------------------------------------

// Prefixe "id=<n> " (n decimal 1..999999999) en tete de ligne, espaces de tete
// ignores. true : *id rempli et *rest pointe sur la commande (espaces sautes).
// false : pas de prefixe valide, *rest = line.
bool parseIdPrefix(char *line, uint32_t *id, char **rest);
// Copie la commande pour reponse.cmd : kCmdTextMax octets au plus.
void copyCmd(char out[kCmdTextMax + 1], const char *cmd);
// reponse.cmd ne renvoie jamais une cle : 'mesh cles <reseau> <application>'
// devient 'mesh cles'.
void maskCmd(char *shown);

// Assemblage des octets recus en lignes (tache de la console, mode machine).
// Octets de controle ignores, sauf LF, CR, Ctrl-U et retour arriere, pour
// qu'aucun RS ne revienne dans un message ; les octets hauts (UTF-8 des noms)
// sont gardes. Au-dela de kCmdMax octets, la ligne est marquee trop longue
// (refusee a son LF, rien n'est execute).
class LineAssembler {
 public:
  enum class Ev : uint8_t { None, Byte, Erase, Clear, Line };
  Ev feed(uint8_t c);
  char *text();  // ligne terminee par 0 (apres Ev::Line)
  bool tooLong() const { return tooLong_; }
  uint8_t length() const { return len_; }
  void reset() {
    len_ = 0;
    tooLong_ = false;
  }

 private:
  char buf_[kCmdMax + 1] = {};
  uint8_t len_ = 0;
  bool tooLong_ = false;
};

// ---------------------------------------------------------------------------
//  Debit
// ---------------------------------------------------------------------------

// Plafond par fenetre d'une seconde. Au-dela, l'evenement n'est pas produit
// (aucun n consomme) et le suivant du meme type porte 'sautes'.
class RateCap {
 public:
  explicit RateCap(uint16_t perSecond) : limit_(perSecond) {}
  bool available(uint32_t now);  // place dans la fenetre en cours
  void take() { count_++; }
  void skip() { skipped_++; }
  uint32_t takeSkipped() {
    const uint32_t s = skipped_;
    skipped_ = 0;
    return s;
  }

 private:
  uint16_t limit_, count_ = 0;
  bool started_ = false;
  uint32_t winAt_ = 0, skipped_ = 0;
};

// Au plus kLines lignes acceptees par kWindowMs glissantes (section 6.5).
class Cadence {
 public:
  static constexpr uint8_t kLines = 20;
  static constexpr uint32_t kWindowMs = 1000;
  bool allow(uint32_t now);  // true : ligne acceptee et comptee

 private:
  uint32_t at_[kLines] = {};
  uint8_t idx_ = 0, n_ = 0;
};

// ---------------------------------------------------------------------------
//  File des lignes periodiques (section 2.3)
// ---------------------------------------------------------------------------

constexpr uint32_t kLateMs = 500;  // ligne periodique perdue apres ce retard

// Une ligne a former a son tour. arg : la lampe (0..15) pour ConfigLampe et
// EtatLampe, la place de la reponse differee pour Reply.
enum class Item : uint8_t {
  HelloBase, HelloId, ConfigCatalogue, ConfigMesh, ConfigLampe, EtatPont, EtatLampe, EtatSante, CptMesh,
  NetMatter, NetThread, Heartbeat, Reply
};
struct Queued {
  Item item;
  uint8_t arg;
  bool session;  // periodique ou instantane de 'json 1' : retire a la fin du mode machine
  uint32_t at;   // mise en file (ou derniere demande explicite fondue dedans)
};

class Queue {
 public:
  static constexpr uint8_t kN = 48;  // un instantane complet a 16 lampes : 42 lignes
  // Ajoute en queue. Un element deja en file (meme item et meme arg, hors
  // Reply) n'est pas double ; une demande explicite (session faux) fondue
  // dedans le rend explicite et repart de maintenant (son retard ne compte
  // que depuis la demande). false : file pleine.
  bool push(Item item, uint32_t now, bool session, uint8_t arg = 0);
  const Queued *front() const { return n_ ? &q_[head_] : nullptr; }
  void pop();
  uint8_t size() const { return n_; }
  bool has(Item item, uint8_t arg = 0) const;
  // Retire de la tete les lignes en retard de plus de lateMs et rend leur
  // nombre (n consomme, json_perdus). Une reponse n'est jamais perdue pour
  // retard : elle arrete le balayage, les lignes derriere elle attendent.
  uint8_t dropLate(uint32_t now, uint32_t lateMs = kLateMs);
  // Retire les elements de session ; ceux qui restent gardent leur ordre.
  uint8_t dropSession();
  void clear() { head_ = n_ = 0; }

 private:
  Queued q_[kN] = {};
  uint8_t head_ = 0, n_ = 0;
};

// ---------------------------------------------------------------------------
//  Bail (section 3.5)
// ---------------------------------------------------------------------------

// Le bail court depuis le plus recent : dernier octet recu, ou fin de la
// derniere commande (une commande longue ne le fait pas expirer).
// leaseS nul : sans bail, jamais expire.
bool leaseExpired(uint32_t now, uint32_t lastRx, uint32_t lastCmd, uint16_t leaseS);

}  // namespace jsonp
````

`components/protocole/json_ligne.cpp` (contenu complet) :

````cpp
// Briques pures du protocole JSON (voir json_ligne.h), reprises de json_out.cpp
// du pont Halo (commit e114cd5).
#include "json_ligne.h"

#include <string.h>

namespace jsonp {

// ===========================================================================
//  Writer
// ===========================================================================

void Writer::put(char c) {
  if (len_ < kLineMax) buf_[len_++] = (uint8_t)c;
  else over_ = true;
}

void Writer::puts(const char *s) {
  while (*s) put(*s++);
}

// Virgule avant tout champ sauf le premier de son niveau, puis la cle.
void Writer::sep(const char *k) {
  if (!depth_) {
    bad_ = true;
    return;
  }
  if (!first_[depth_ - 1]) put(',');
  first_[depth_ - 1] = false;
  if (k) {
    put('"');
    puts(k);
    put('"');
    put(':');
  }
}

void Writer::num(uint32_t v, bool neg) {
  char t[10];
  uint8_t i = 0;
  do {
    t[i++] = (char)('0' + v % 10);
    v /= 10;
  } while (v);
  if (neg) put('-');
  while (i) put(t[--i]);
}

void Writer::begin(const char *type, uint32_t n, uint32_t ms) {
  len_ = 0;
  over_ = bad_ = false;
  depth_ = 1;
  first_[0] = true;
  close_[0] = '}';
  put((char)kRS);
  put('{');
  u32("v", kVersion);
  str("t", type);
  u32("n", n);
  u32("ms", ms);
}

size_t utf8Seq(const uint8_t *s, size_t n) {
  const uint8_t c = s[0];
  size_t len;
  uint32_t cp;
  if (c >= 0xC2 && c <= 0xDF) {
    len = 2;
    cp = c & 0x1F;
  } else if (c >= 0xE0 && c <= 0xEF) {
    len = 3;
    cp = c & 0x0F;
  } else if (c >= 0xF0 && c <= 0xF4) {
    len = 4;
    cp = c & 0x07;
  } else {
    return 0;  // octet de suite isole, 0xC0, 0xC1 (formes trop longues), au-dela de 0xF4
  }
  if (len > n) return 0;
  for (size_t i = 1; i < len; i++) {
    if ((s[i] & 0xC0) != 0x80) return 0;
    cp = cp << 6 | (s[i] & 0x3F);
  }
  if ((len == 3 && cp < 0x800) || (len == 4 && (cp < 0x10000 || cp > 0x10FFFF))) return 0;
  if (cp >= 0xD800 && cp <= 0xDFFF) return 0;  // surrogats
  return len;
}

void Writer::str(const char *k, const char *v, size_t max) {
  sep(k);
  if (!v) {
    puts("null");
    return;
  }
  put('"');
  const uint8_t *s = (const uint8_t *)v;
  size_t lim = 0;
  while (lim < max && s[lim]) lim++;
  for (size_t i = 0; i < lim;) {
    const uint8_t c = s[i];
    if (c == '"' || c == '\\') {
      put('\\');
      put((char)c);
      i++;
    } else if (c < 0x20 || c == 0x7F) {
      put('?');  // jamais de \uXXXX, jamais d'octet de controle
      i++;
    } else if (c < 0x80) {
      put((char)c);
      i++;
    } else {
      // Un caractere UTF-8 entier, ou '?' (sequence invalide, ou coupee par max).
      const size_t len = utf8Seq(s + i, lim - i);
      if (!len) {
        put('?');
        i++;
        continue;
      }
      for (size_t j = 0; j < len; j++) put((char)s[i + j]);
      i += len;
    }
  }
  put('"');
}

void Writer::u32(const char *k, uint32_t v) {
  sep(k);
  num(v, false);
}

void Writer::i32(const char *k, int32_t v) {
  sep(k);
  if (v < 0) num((uint32_t)(-(int64_t)v), true);
  else num((uint32_t)v, false);
}

void Writer::boolean(const char *k, bool v) {
  sep(k);
  puts(v ? "true" : "false");
}

void Writer::null(const char *k) {
  sep(k);
  puts("null");
}

static const char kHexDigits[] = "0123456789ABCDEF";

void Writer::hex(const char *k, const uint8_t *p, size_t n) {
  sep(k);
  put('"');
  for (size_t i = 0; i < n; i++) {
    put(kHexDigits[p[i] >> 4]);
    put(kHexDigits[p[i] & 0x0F]);
  }
  put('"');
}

void Writer::hexU32(const char *k, uint32_t v, uint8_t digits) {
  sep(k);
  put('"');
  if (digits > 8) digits = 8;
  for (int8_t i = (int8_t)digits - 1; i >= 0; i--) put(kHexDigits[(v >> (4 * i)) & 0x0F]);
  put('"');
}

void Writer::open(const char *k, char o, char c) {
  sep(k);
  put(o);
  if (depth_ >= kDepth) {
    bad_ = true;
    return;
  }
  first_[depth_] = true;
  close_[depth_] = c;
  depth_++;
}

void Writer::obj(const char *k) { open(k, '{', '}'); }
void Writer::arr(const char *k) { open(k, '[', ']'); }

void Writer::end() {
  if (depth_ <= 1) {
    bad_ = true;
    return;
  }
  depth_--;
  put(close_[depth_]);
}

bool Writer::finish() {
  if (depth_ != 1) bad_ = true;
  put('}');
  put('\n');
  depth_ = 0;
  return !over_ && !bad_;
}

// ===========================================================================
//  Messages communs
// ===========================================================================

void heartbeat(Writer &w, uint32_t n, uint32_t ms, uint32_t boot, uint32_t upS, uint32_t lost, uint32_t cmdId) {
  w.begin("hb", n, ms);
  w.hexU32("boot", boot, 8);
  w.u32("up_s", upS);
  w.u32("json_perdus", lost);
  if (cmdId) w.u32("commande", cmdId);
  else w.null("commande");
}

void sessionEnd(Writer &w, uint32_t n, uint32_t ms, const char *cause) {
  w.begin("fin", n, ms);
  w.str("cause", cause);
}

void led(Writer &w, uint32_t n, uint32_t ms, const char *motif, const char *before, bool test, uint32_t depuisMs) {
  w.begin("led", n, ms);
  w.str("motif", motif);
  w.str("avant", before);
  w.boolean("test", test);
  w.u32("depuis_ms", depuisMs);
}

void logLine(Writer &w, uint32_t n, uint32_t ms, const char *src, const char *niv, const char *txt,
             uint32_t skipped) {
  w.begin("log", n, ms);
  w.str("src", src);
  w.str("niv", niv);
  w.str("txt", txt, kLogTextMax);
  if (skipped) w.u32("sautes", skipped);
}

void reply(Writer &w, uint32_t n, uint32_t ms, const Reply &r) {
  w.begin("reponse", n, ms);
  w.u32("id", r.id);
  w.str("etape", r.fin ? "fin" : "debut");
  w.str("cmd", r.cmd ? r.cmd : "", kCmdTextMax);
  w.boolean("ok", r.ok);
  w.str("code", r.code);
  if (r.msg) w.str("msg", r.msg, kMsgMax);
  if (r.fin) w.u32("duree_ms", r.durMs);
  if (r.suite != Reply::SuiteNone) w.str("suite", r.suite == Reply::SuiteOrder ? "ordre" : "aucune");
  if (r.lampe) w.u32("lampe", r.lampe);
  if (r.hasLease) {
    w.u32("bail_s", r.leaseS);
    w.u32("up_s", r.upS);
  }
}

// ===========================================================================
//  Lignes de l'hote
// ===========================================================================

// Mot i (0, 1, ...) de s, separe par des espaces ; nullptr s'il manque.
static const char *word(const char *s, uint8_t i, size_t *len) {
  *len = 0;
  for (;;) {
    while (*s == ' ') s++;
    if (!*s) return nullptr;
    const char *w = s;
    while (*s && *s != ' ') s++;
    if (!i--) {
      *len = (size_t)(s - w);
      return w;
    }
  }
}

static bool wordIs(const char *w, size_t n, const char *k) { return w && strlen(k) == n && !strncmp(w, k, n); }

void maskCmd(char *shown) {
  size_t n0, n1;
  const char *w0 = word(shown, 0, &n0), *w1 = word(shown, 1, &n1);
  if (wordIs(w0, n0, "mesh") && wordIs(w1, n1, "cles")) strcpy(shown, "mesh cles");
}

bool parseIdPrefix(char *line, uint32_t *id, char **rest) {
  *rest = line;
  char *p = line;
  while (*p == ' ') p++;
  if (strncmp(p, "id=", 3)) return false;
  p += 3;
  uint32_t v = 0;
  uint8_t digits = 0;
  while (*p >= '0' && *p <= '9') {
    if (++digits > 9) return false;
    v = v * 10 + (uint32_t)(*p++ - '0');
  }
  if (!digits || v < 1 || v > kIdMax || (*p && *p != ' ')) return false;
  while (*p == ' ') p++;
  *id = v;
  *rest = p;
  return true;
}

void copyCmd(char out[kCmdTextMax + 1], const char *cmd) {
  size_t i = 0;
  for (; cmd && cmd[i] && i < kCmdTextMax; i++) out[i] = cmd[i];
  out[i] = 0;
}

LineAssembler::Ev LineAssembler::feed(uint8_t c) {
  if (c == '\r') return Ev::None;  // CRLF de l'hote : le CR est ignore
  if (c == '\n') {
    buf_[len_] = 0;
    return Ev::Line;
  }
  if (c == kCtrlU) {
    len_ = 0;
    tooLong_ = false;
    return Ev::Clear;
  }
  if (c == 8 || c == 127) {  // retour arriere
    if (!len_) return Ev::None;
    len_--;
    return Ev::Erase;
  }
  if (c < 0x20) return Ev::None;
  if (len_ >= kCmdMax) {
    tooLong_ = true;
    return Ev::None;
  }
  buf_[len_++] = (char)c;
  return Ev::Byte;
}

char *LineAssembler::text() {
  buf_[len_] = 0;
  return buf_;
}

// ===========================================================================
//  Debit
// ===========================================================================

bool RateCap::available(uint32_t now) {
  if (!started_ || now - winAt_ >= 1000) {
    started_ = true;
    winAt_ = now;
    count_ = 0;
  }
  return count_ < limit_;
}

bool Cadence::allow(uint32_t now) {
  // at_[idx_] : la plus ancienne des kLines dernieres lignes acceptees.
  if (n_ >= kLines && now - at_[idx_] < kWindowMs) return false;
  at_[idx_] = now;
  idx_ = (uint8_t)((idx_ + 1) % kLines);
  if (n_ < kLines) n_++;
  return true;
}

// ===========================================================================
//  File
// ===========================================================================

bool Queue::has(Item item, uint8_t arg) const {
  for (uint8_t i = 0; i < n_; i++) {
    const Queued &q = q_[(head_ + i) % kN];
    if (q.item == item && q.arg == arg) return true;
  }
  return false;
}

bool Queue::push(Item item, uint32_t now, bool session, uint8_t arg) {
  if (item != Item::Reply) {
    for (uint8_t i = 0; i < n_; i++) {
      Queued &q = q_[(head_ + i) % kN];
      if (q.item != item || q.arg != arg) continue;
      // Demande explicite : survit a la fin du mode machine, et son retard
      // part d'elle (la ligne est formatee a l'envoi : rien n'est perime).
      if (!session) {
        q.session = false;
        q.at = now;
      }
      return true;
    }
  }
  if (n_ >= kN) return false;
  q_[(head_ + n_) % kN] = Queued{item, arg, session, now};
  n_++;
  return true;
}

void Queue::pop() {
  if (!n_) return;
  head_ = (uint8_t)((head_ + 1) % kN);
  n_--;
}

uint8_t Queue::dropLate(uint32_t now, uint32_t lateMs) {
  uint8_t dropped = 0;
  while (n_) {
    const Queued &q = q_[head_];
    if (q.item == Item::Reply || now - q.at <= lateMs) break;
    pop();
    dropped++;
  }
  return dropped;
}

uint8_t Queue::dropSession() {
  Queued keep[kN];
  uint8_t k = 0, dropped = 0;
  for (uint8_t i = 0; i < n_; i++) {
    const Queued &q = q_[(head_ + i) % kN];
    if (q.session) dropped++;
    else keep[k++] = q;
  }
  for (uint8_t i = 0; i < k; i++) q_[i] = keep[i];
  head_ = 0;
  n_ = k;
  return dropped;
}

// ===========================================================================
//  Bail
// ===========================================================================

bool leaseExpired(uint32_t now, uint32_t lastRx, uint32_t lastCmd, uint16_t leaseS) {
  if (!leaseS) return false;
  const uint32_t last = (int32_t)(lastRx - lastCmd) > 0 ? lastRx : lastCmd;
  return now - last >= (uint32_t)leaseS * 1000u;
}

}  // namespace jsonp
````

`components/protocole/include/json_amaran.h` (contenu complet) :

````c
#pragma once
// ===========================================================================
//  Messages du pont amaran (docs/PROTOCOLE-JSON.md, sections 5 et 7), formes
//  depuis des donnees simples : les structures du coeur (lampes.h) et de la
//  liste (liste.h), et des releves remplis par firmware/main/json_pont.cpp.
//  Pur et sans ESP-IDF : teste sur le Mac (tests/hote/test_json.cpp), qui
//  verifie aussi que chaque exemple du document sort tel quel d'ici.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "json_ligne.h"
#include "lampes.h"
#include "liste.h"

namespace jsonp {

// --- hello (5.1)

struct Session {
  uint32_t periodeMs = 1000;    // etat : blocs pont et sante
  uint32_t lampesMs = 10000;    // etat : toutes les lampes (une lampe part aussi a chaque changement)
  uint32_t compteursMs = 1000;
  uint32_t reseauMs = 5000;
  uint16_t bailS = 30;
  bool log = false;
};

struct HelloBase {
  const char *fw = "";          // esp_app_get_description()->version
  const char *date = "", *heure = "";
  const char *idf = "";
  const char *puce = "";
  uint32_t boot = 0;
  const char *reset = "";       // code de la cause du demarrage (json_pont.cpp)
  uint8_t resetN = 0;           // esp_reset_reason()
  uint32_t upS = 0;
  Session session;
};
void helloBase(Writer &w, uint32_t n, uint32_t ms, const HelloBase &h);

struct HelloId {
  uint32_t boot = 0;
  uint8_t mac[6] = {};
  const char *fabricant = nullptr, *produit = nullptr, *serie = nullptr, *nom = nullptr;  // nul : inconnu
};
void helloId(Writer &w, uint32_t n, uint32_t ms, const HelloId &h);

// --- config (5.2)

void configCatalogue(Writer &w, uint32_t n, uint32_t ms);

struct ConfigMesh {
  bool cles = false;
  const char *empReseau = nullptr, *empApp = nullptr;  // 8 hexa ; nul sans cles
  uint16_t adresse = 0;
  uint32_t ivNvs = 0;
  uint16_t fenetreMs = 0, intervalleMs = 0;            // balayage
  uint8_t lampes = 0;                                  // N de la liste du demarrage
  uint32_t releveMs = 0;
};
void configMesh(Writer &w, uint32_t n, uint32_t ms, const ConfigMesh &c);

// lampe : index (0..15) ; le message porte son numero (1..16).
void configLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const liste_lampe_t &l);

// --- etat (5.3)

struct EtatPont {
  uint32_t boot = 0, upS = 0;
  bool meshPret = false;
  const char *diag = "ok";
  uint32_t ordres = 0, confirmes = 0, abandons = 0, tenus = 0;
  uint32_t delaiTotalMs = 0, delaiMaxMs = 0, lents = 0;
  uint32_t releves = 0, trames = 0;
};
void etatPont(Writer &w, uint32_t n, uint32_t ms, const EtatPont &e);

// part : lampes_part_repondue (-1 : aucune relecture comptee) ; endpoint : 0 si
// la lampe n'est pas dans Maison.
void etatLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const lampe_t &p, const liste_lampe_t &l,
               uint16_t endpoint, int part);

struct Pile {
  const char *nom;
  int32_t libre;  // octets jamais utilises ; -1 : tache absente
};
struct EtatSante {
  uint32_t boot = 0, upS = 0;
  uint32_t cmdId = 0;           // id de la commande de la console en cours ; 0 : aucune
  const char *motif = nullptr;  // code du voyant (status_led.h : patternCode)
  bool test = false;
  uint32_t depuisMs = 0;
  bool enService = false, threadAttache = false, identifie = false, ble = false;
  uint32_t heap = 0, heapMin = 0, heapBloc = 0;
  const Pile *piles = nullptr;
  uint8_t nPiles = 0;
  uint32_t perdus = 0, tropLongs = 0, rejets = 0;
};
void etatSante(Writer &w, uint32_t n, uint32_t ms, const EtatSante &e);

// --- compteurs (5.4)

struct CompteursMesh {
  uint32_t annonces = 0, nidReconnu = 0, nidInconnu = 0, netmicFaux = 0, accesDechiffres = 0, etatsLampes = 0,
           doublons = 0;
  uint32_t balisesNotres = 0, balisesAutres = 0, balisesFausses = 0;
  bool baliseVue = false;
  uint32_t baliseIv = 0, baliseMs = 0;
  uint8_t baliseDrapeaux = 0;
  uint32_t emis = 0, echecsEmission = 0, filePleine = 0;
  uint32_t iv = 0, seq = 0, plancher = 0;
};
void compteursMesh(Writer &w, uint32_t n, uint32_t ms, const CompteursMesh &c);

// --- reseau (5.5)

struct ReseauMatter {
  bool demarre = false;
  uint8_t fabriques = 0;
  bool ble = false, identifie = false;
  uint32_t demandes = 0, plafonnes = 0, etablis = 0, termines = 0;
  uint16_t plafondS = 0;
  const char *codeManuel = nullptr, *qr = nullptr;  // nul : inconnus
};
void reseauMatter(Writer &w, uint32_t n, uint32_t ms, const ReseauMatter &r);
void reseauThread(Writer &w, uint32_t n, uint32_t ms, const char *role, bool attache);

// --- evenements (7)

constexpr uint8_t kIdsMax = 4;  // id en attente par lampe

struct Ordre {
  int lampe = 0;                 // index
  const char *issue = "confirme";  // confirme, abandon, tenu
  uint32_t delaiMs = 0;
  uint8_t essai = 0;
  uint32_t ids[kIdsMax] = {};
  uint8_t nIds = 0;
  uint32_t idsPerdus = 0;
};
void ordre(Writer &w, uint32_t n, uint32_t ms, const Ordre &o);
void alerteReleves(Writer &w, uint32_t n, uint32_t ms, int lampe, bool manque, uint8_t part);
void alerteMesh(Writer &w, uint32_t n, uint32_t ms, const char *diag);
// quoi : entree, masquee, remise, echec ; endpoint 0 : null.
void lampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const char *quoi, uint16_t endpoint);

// Codes du protocole.
const char *phaseCode(lampe_phase_t p);  // repos, trames, attente

}  // namespace jsonp
````

`components/protocole/json_amaran.cpp` (contenu complet) :

````cpp
// Messages du pont amaran (voir json_amaran.h).
#include "json_amaran.h"

#include <initializer_list>

#include "catalogue.h"

namespace jsonp {

// --- Codes

const char *phaseCode(lampe_phase_t p) {
  switch (p) {
    case LAMPE_TRAMES: return "trames";
    case LAMPE_ATTENTE: return "attente";
    case LAMPE_REPOS:
    default: return "repos";
  }
}

static const char *typeCode(catalogue_type_t t) {
  switch (t) {
    case CATALOGUE_LAMPE_TEMPERATURE: return "temperature";
    case CATALOGUE_LAMPE_COULEUR: return "couleur";
    case CATALOGUE_LAMPE_VARIABLE:
    default: return "variable";
  }
}

// ["intensite","cct","couleur"] : les capacites, une par mot.
static void capacites(Writer &w, uint8_t c) {
  w.arr("capacites");
  if (c & CATALOGUE_INTENSITE) w.str(nullptr, "intensite");
  if (c & CATALOGUE_CCT) w.str(nullptr, "cct");
  if (c & CATALOGUE_COULEUR) w.str(nullptr, "couleur");
  w.end();
}

static void modele(Writer &w, const char *k, const catalogue_modele_t *m, bool code) {
  w.obj(k);
  if (code) w.u32("code", m->code);
  w.str("nom", m->nom);
  capacites(w, m->capacites);
  w.str("type", typeCode(m->type));
  if (m->capacites & CATALOGUE_CCT) {
    w.obj("cct_k");
    w.u32("min", m->cct_min_k);
    w.u32("max", m->cct_max_k);
    w.end();
  } else {
    w.null("cct_k");
  }
  w.end();
}

static void etatLu(Writer &w, const char *k, const lampe_etat_t &e) {
  w.obj(k);
  w.boolean("marche", e.marche);
  w.u32("intensite", e.intensite);
  w.end();
}

// --- hello

void helloBase(Writer &w, uint32_t n, uint32_t ms, const HelloBase &h) {
  w.begin("hello", n, ms);
  w.str("bloc", "base");
  w.u32("rev", kRev);
  w.str("fw", h.fw, 32);
  w.str("date", h.date, 16);
  w.str("heure", h.heure, 16);
  w.str("idf", h.idf, 32);
  w.str("puce", h.puce, 16);
  w.hexU32("boot", h.boot, 8);
  w.str("reset", h.reset);
  w.u32("reset_n", h.resetN);
  w.u32("up_s", h.upS);
  w.obj("session");
  w.u32("periode_ms", h.session.periodeMs);
  w.u32("lampes_ms", h.session.lampesMs);
  w.u32("compteurs_ms", h.session.compteursMs);
  w.u32("reseau_ms", h.session.reseauMs);
  w.u32("bail_s", h.session.bailS);
  w.boolean("log", h.session.log);
  w.end();
  w.obj("limites");
  w.u32("ligne_max", (uint32_t)kLineMax);
  w.u32("cmd_max", (uint32_t)kCmdMax);
  w.end();
}

void helloId(Writer &w, uint32_t n, uint32_t ms, const HelloId &h) {
  w.begin("hello", n, ms);
  w.str("bloc", "identite");
  w.hexU32("boot", h.boot, 8);
  w.hex("mac", h.mac, 6);
  w.obj("id");
  w.str("fabricant", h.fabricant, 32);
  w.str("produit", h.produit, 32);
  w.str("serie", h.serie, 32);
  w.str("nom", h.nom, 32);
  w.end();
  w.arr("caps");
  for (const char *c : {"matter", "thread", "mesh", "catalogue", "ordres", "led", "log"}) w.str(nullptr, c);
  w.end();
}

// --- config

void configCatalogue(Writer &w, uint32_t n, uint32_t ms) {
  w.begin("config", n, ms);
  w.str("bloc", "catalogue");
  w.arr("modeles");
  for (unsigned i = 0; i < catalogue_nombre(); i++) modele(w, nullptr, catalogue_modele(i), true);
  w.end();
  modele(w, "repli", catalogue_repli(), false);
}

void configMesh(Writer &w, uint32_t n, uint32_t ms, const ConfigMesh &c) {
  w.begin("config", n, ms);
  w.str("bloc", "mesh");
  w.boolean("cles", c.cles);
  if (c.cles) {
    w.obj("empreintes");
    w.str("reseau", c.empReseau, 8);
    w.str("application", c.empApp, 8);
    w.end();
  } else {
    w.null("empreintes");
  }
  w.hexU32("adresse", c.adresse, 4);
  w.u32("iv_nvs", c.ivNvs);
  w.obj("balayage");
  w.u32("fenetre_ms", c.fenetreMs);
  w.u32("intervalle_ms", c.intervalleMs);
  w.end();
  w.u32("lampes", c.lampes);
  w.u32("capacite", LISTE_CAPACITE);
  w.u32("releve_ms", c.releveMs);
  w.hexU32("groupe", LAMPES_GROUPE, 4);
}

void configLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const liste_lampe_t &l) {
  const catalogue_modele_t *m = catalogue_trouver(l.code);
  w.begin("config", n, ms);
  w.str("bloc", "lampe");
  w.u32("lampe", (uint32_t)lampe + 1);
  w.hexU32("adresse", l.adresse, 4);
  w.hex("mac", l.mac, 6);
  w.str("nom", l.nom, LISTE_NOM_MAX - 1);
  w.u32("code", l.code);
  w.str("modele", m->nom);
  w.boolean("catalogue", catalogue_connu(l.code));
  capacites(w, m->capacites);
  w.str("type", typeCode(m->type));
}

// --- etat

void etatPont(Writer &w, uint32_t n, uint32_t ms, const EtatPont &e) {
  w.begin("etat", n, ms);
  w.str("bloc", "pont");
  w.hexU32("boot", e.boot, 8);
  w.u32("up_s", e.upS);
  w.obj("mesh");
  w.boolean("pret", e.meshPret);
  w.str("diag", e.diag);
  w.end();
  w.obj("ordres");
  w.u32("total", e.ordres);
  w.u32("confirmes", e.confirmes);
  w.u32("abandons", e.abandons);
  w.u32("tenus", e.tenus);
  w.u32("delai_total_ms", e.delaiTotalMs);
  w.u32("delai_max_ms", e.delaiMaxMs);
  w.u32("lents", e.lents);
  w.end();
  w.u32("releves", e.releves);
  w.u32("trames", e.trames);
}

void etatLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const lampe_t &p, const liste_lampe_t &l,
               uint16_t endpoint, int part) {
  w.begin("etat", n, ms);
  w.str("bloc", "lampe");
  w.u32("lampe", (uint32_t)lampe + 1);
  w.obj("maison");
  if (endpoint) w.u32("endpoint", endpoint);
  else w.null("endpoint");
  w.boolean("vue", (l.drapeaux & LISTE_VUE) != 0);
  w.boolean("masquee", (l.drapeaux & LISTE_MASQUEE) != 0);
  w.end();
  w.boolean("entendue", p.entendue);
  if (p.connu) etatLu(w, "lue", p.lu);
  else w.null("lue");
  w.boolean("joignable", p.joignable);
  if (p.entendue) w.u32("reponse_ms", p.reponse_ms);
  else w.null("reponse_ms");
  if (p.phase == LAMPE_REPOS) {
    w.null("consigne");
  } else {
    w.obj("consigne");
    if (p.veut_marche) w.boolean("marche", p.consigne.marche);
    else w.null("marche");
    if (p.veut_intensite) w.u32("intensite", p.consigne.intensite);
    else w.null("intensite");
    w.str("phase", phaseCode(p.phase));
    w.u32("essai", p.essai);
    w.end();
  }
  w.u32("repondues", p.releves_repondues);
  if (part >= 0) w.u32("part_10min", (uint32_t)part);
  else w.null("part_10min");
  w.boolean("alerte", p.alerte);
}

void etatSante(Writer &w, uint32_t n, uint32_t ms, const EtatSante &e) {
  w.begin("etat", n, ms);
  w.str("bloc", "sante");
  w.hexU32("boot", e.boot, 8);
  w.u32("up_s", e.upS);
  if (e.cmdId) w.u32("commande", e.cmdId);
  else w.null("commande");
  w.obj("led");
  w.str("motif", e.motif);
  w.boolean("test", e.test);
  w.u32("depuis_ms", e.depuisMs);
  w.end();
  w.obj("matter");
  w.boolean("en_service", e.enService);
  w.boolean("thread", e.threadAttache);
  w.boolean("identifie", e.identifie);
  w.boolean("ble", e.ble);
  w.end();
  w.obj("sys");
  w.u32("heap", e.heap);
  w.u32("heap_min", e.heapMin);
  w.u32("heap_bloc", e.heapBloc);
  w.obj("piles");
  for (uint8_t i = 0; i < e.nPiles; i++) {
    if (e.piles[i].libre >= 0) w.u32(e.piles[i].nom, (uint32_t)e.piles[i].libre);
    else w.null(e.piles[i].nom);
  }
  w.end();
  w.u32("json_perdus", e.perdus);
  w.u32("json_trop_longs", e.tropLongs);
  w.u32("rejets", e.rejets);
  w.end();
}

// --- compteurs

void compteursMesh(Writer &w, uint32_t n, uint32_t ms, const CompteursMesh &c) {
  w.begin("compteurs", n, ms);
  w.str("bloc", "mesh");
  w.u32("annonces", c.annonces);
  w.u32("nid_reconnu", c.nidReconnu);
  w.u32("nid_inconnu", c.nidInconnu);
  w.u32("netmic_faux", c.netmicFaux);
  w.u32("acces_dechiffres", c.accesDechiffres);
  w.u32("etats_lampes", c.etatsLampes);
  w.u32("doublons", c.doublons);
  w.obj("balises");
  w.u32("notres", c.balisesNotres);
  w.u32("autres", c.balisesAutres);
  w.u32("fausses", c.balisesFausses);
  if (c.baliseVue) {
    w.obj("derniere");
    w.u32("iv", c.baliseIv);
    w.u32("drapeaux", c.baliseDrapeaux);
    w.u32("ms", c.baliseMs);
    w.end();
  } else {
    w.null("derniere");
  }
  w.end();
  w.u32("emis", c.emis);
  w.u32("echecs_emission", c.echecsEmission);
  w.u32("file_pleine", c.filePleine);
  w.u32("iv", c.iv);
  w.u32("seq", c.seq);
  w.u32("plancher", c.plancher);
}

// --- reseau

void reseauMatter(Writer &w, uint32_t n, uint32_t ms, const ReseauMatter &r) {
  w.begin("reseau", n, ms);
  w.str("bloc", "matter");
  w.boolean("demarre", r.demarre);
  w.u32("fabriques", r.fabriques);
  w.boolean("ble", r.ble);
  w.boolean("identifie", r.identifie);
  w.obj("abonnements");
  w.u32("demandes", r.demandes);
  w.u32("plafonnes", r.plafonnes);
  w.u32("etablis", r.etablis);
  w.u32("termines", r.termines);
  w.u32("plafond_s", r.plafondS);
  w.end();
  w.str("code_manuel", r.codeManuel, 32);
  w.str("qr", r.qr, 64);
}

void reseauThread(Writer &w, uint32_t n, uint32_t ms, const char *role, bool attache) {
  w.begin("reseau", n, ms);
  w.str("bloc", "thread");
  w.str("role", role, 16);
  w.boolean("attache", attache);
}

// --- evenements

void ordre(Writer &w, uint32_t n, uint32_t ms, const Ordre &o) {
  w.begin("ordre", n, ms);
  w.u32("lampe", (uint32_t)o.lampe + 1);
  w.str("issue", o.issue);
  w.u32("delai_ms", o.delaiMs);
  w.u32("essai", o.essai);
  w.arr("ids");
  for (uint8_t i = 0; i < o.nIds && i < kIdsMax; i++) w.u32(nullptr, o.ids[i]);
  w.end();
  w.u32("ids_perdus", o.idsPerdus);
}

void alerteReleves(Writer &w, uint32_t n, uint32_t ms, int lampe, bool manque, uint8_t part) {
  w.begin("alerte", n, ms);
  w.str("quoi", "releves");
  w.u32("lampe", (uint32_t)lampe + 1);
  w.boolean("manque", manque);
  w.u32("part", part);
}

void alerteMesh(Writer &w, uint32_t n, uint32_t ms, const char *diag) {
  w.begin("alerte", n, ms);
  w.str("quoi", "mesh");
  w.str("diag", diag);
}

void lampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const char *quoi, uint16_t endpoint) {
  w.begin("lampe", n, ms);
  w.u32("lampe", (uint32_t)lampe + 1);
  w.str("quoi", quoi);
  if (endpoint) w.u32("endpoint", endpoint);
  else w.null("endpoint");
}

}  // namespace jsonp
````

- [ ] **Step 5 : lancer les tests, tout est vert.**

Run: `sh tests/hote/lancer.sh`
Expected: `json : 281 verifications, 0 echecs`, puis `tests hote : tout est vert`.

- [ ] **Step 6 : le composant compile aussi pour la carte.** Il est neuf : `reconfigure` d'abord, dans les deux firmwares (le `main` de l'écoute dépend de tous les composants). Rien ne l'appelle encore : c'est l'épreuve de gcc et des options d'ESP-IDF.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && (cd ecoute && idf.py reconfigure >/dev/null && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader") && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py reconfigure >/dev/null && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader")`
Expected : comme à la Task 1 : deux tailles, deux `Project build complete. To flash, run:`, aucune ligne `warning:` ni `error:`.

> **Amendement (exécution, 05/10)** : la relecture a montré que `leaseExpired` et `Queue::dropLate` comparaient des écarts de temps non signés ; la tâche `json` prend l'heure avant son verrou, et un horodatage posé juste après par la console faisait expirer le bail ou perdre une ligne à tort. Correctif en un commit à part : écarts signés, et deux vérifications de plus (`json : 283 verifications`).

- [ ] **Step 7 : commit.**

```bash
git add components/protocole tests/hote docs/PROTOCOLE-JSON.md
git commit -m "$(printf "Composant protocole : lignes machine du pont (protocole v1 de Halo) et docs/PROTOCOLE-JSON.md\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 3: Le mode JSON dans le firmware : notre console, la tâche `json`, les événements

**Files:**
- Create: `firmware/main/json_pont.h`, `firmware/main/json_pont.cpp`
- Modify: `firmware/main/console_pont.h`, `firmware/main/console_pont.c`
- Modify: `firmware/main/tache_lampes.h`, `firmware/main/tache_lampes.c`
- Modify: `firmware/main/pont_matter.h`, `firmware/main/pont_matter.cpp`
- Modify: `firmware/main/socle.h`, `firmware/main/socle.cpp`
- Modify: `firmware/main/app_main.cpp`

**Interfaces:**
- Consumes : le composant `protocole` (Task 2) ; `LAMPES_SIGNAL_TENU`, `dernier_delai_ms`, `tenus` (Task 1) ; `mesh_lire_stats`, `mesh_iv_courant`, `mesh_sequence`, `mesh_plancher`, `mesh_balayage`, `mesh_pret`, `config_empreinte` (composant `mesh`) ; `statusled::patternCode` (socle).
- Produces :
  - `json_pont.h` (C) : `json_pont_demarrer(cfg)`, `json_pont_machine()`, `json_pont_lire()`, `json_pont_executer(ligne, trop_long)`, `json_pont_commande(argc, argv)`, `json_pont_ordre(lampe, signal, delai_ms, essai, ids, n_ids, ids_perdus)`, `json_pont_alerte_releves`, `json_pont_alerte_mesh`, `json_pont_lampe(lampe, quoi, endpoint)` avec `JSON_LAMPE_ENTREE|MASQUEE|REMISE|ECHEC`, `json_pont_led`, `json_pont_annoncer(src, alerte, format, ...)`, `JSON_PONT_CMD_MAX` (127), `JSON_PONT_IDS_MAX` (4) ;
  - `console_pont.h` : `CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES]` (9 tâches : `lampes`, `socle`, `json`, `console`, `amaran_tx`, `nimble_host`, `mesh_adv_task`, `CHIP`, `ot_task`) ;
  - `tache_lampes.h` : `tache_lampes_ordre_id(lampe, marche, intensite, id)`, `tache_lampes_diagnostic()` ;
  - `pont_matter.h` : `pont_infos_t`, `pont_lire(infos)`, `PONT_NOM` ;
  - `socle.h` : `socle_voyant_t`, `socle_voyant(v)`.

Pourquoi : la spec 3b, section 6, et les choix 2 à 8 de ce plan.
- **La console** : la REPL d'ESP-IDF fait toujours l'écho (linenoise). `console_pont_demarrer` reprend donc ce que fait `esp_console_new_repl_usb_serial_jtag` (fins de ligne, pilote de l'USB avec un tampon d'émission de 4 Ko, `esp_console_init`, linenoise), puis lance notre tâche `console` : linenoise en mode texte, `json_pont_lire` en mode machine. La commande `json` s'ajoute à la console.
- **La tâche `json`** (priorité 1, pile de 4 Ko, un tic toutes les 10 ms) : bail, périodes, regard sur les lampes toutes les 100 ms (une ligne `etat` `lampe` à chaque changement), une ligne de la file par tic, formée à l'envoi. Les événements arrivent par une file FreeRTOS ; les annonces en mode `json log 1`, par une autre. Un seul verrou, `s_verrou`, garde la session, la file et l'écrivain ; on n'y prend jamais celui de la tâche des lampes avant de le lâcher, et la tâche des lampes ne prend jamais `s_verrou`.
- **Les ordres** : `lampe <n> on|off|niveau <v>` avec un `id` répond `accepte`, puis l'ordre part avec son `id` (`tache_lampes_ordre_id`). La tâche des lampes range l'`id` sous la lampe avant d'appeler le cœur ; `sortie_signaler` envoie l'événement `ordre` avec les `id` de la lampe, puis les oublie.
- **Les annonces** de la tâche des lampes et du bouton BOOT passent par `json_pont_annoncer` : texte, ou message `log` en mode machine avec `json log 1`.

- [ ] **Step 1 : l'interface du mode JSON.**

`firmware/main/json_pont.h` (contenu complet) :

````c
// Mode JSON du pont sur l'USB (docs/PROTOCOLE-JSON.md) : la session (mode
// machine, bail, periodes), la tache json qui forme et ecrit les lignes, et
// l'execution des lignes de la console (prefixe id=, reponses, ordres
// asynchrones). Les briques pures sont dans components/protocole.
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

// Avant le socle, la console et la tache des lampes, qui lui envoient leurs
// evenements : tire le numero de demarrage, cree les files et la tache json.
// cfg reste a l'appelant (empreintes des cles, adresse, liste).
esp_err_t json_pont_demarrer(const amaran_config_t *cfg);
// Mode machine en cours : la console lit l'USB sans echo ni invite.
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

// Evenements (section 7), depuis n'importe quelle tache, sans bloquer ; ignores
// hors du mode machine.
// Fin d'un ordre de lampe : ids, les id des ordres de l'app qu'il couvre.
void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     uint8_t n_ids, uint32_t ids_perdus);
void json_pont_alerte_releves(int lampe, bool manque, uint8_t pour_cent);
void json_pont_alerte_mesh(diagnostic_t etat);
typedef enum { JSON_LAMPE_ENTREE, JSON_LAMPE_MASQUEE, JSON_LAMPE_REMISE, JSON_LAMPE_ECHEC } json_lampe_t;
void json_pont_lampe(int lampe, json_lampe_t quoi, uint16_t endpoint);
// Le voyant change de motif (codes de status_led.h : patternCode).
void json_pont_led(const char *motif, const char *avant, bool test, uint32_t depuis_ms);
// Annonce du pont (une ligne, sans LF) : message log en mode machine avec
// `json log 1`, sinon texte. src : "lampes", "mesh", "bouton".
void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) __attribute__((format(printf, 3, 4)));

#ifdef __cplusplus
}
#endif
````

- [ ] **Step 2 : la tâche `json` et l'exécution des lignes.**

`firmware/main/json_pont.cpp` (contenu complet) :

````cpp
// Mode JSON du pont (voir json_pont.h). Sur le modele de json_mode.cpp du pont
// Halo (commit e114cd5), pour ESP-IDF : la console lit et execute dans sa tache,
// la tache json forme les lignes periodiques et les evenements. Une ligne se
// forme et s'ecrit sous s_verrou, d'un seul appel au pilote de l'USB, sans
// attendre (2.3).
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
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "texte.h"

using namespace jsonp;

static_assert(JSON_PONT_CMD_MAX == kCmdMax, "json_pont.h et json_ligne.h : meme longueur de ligne");
static_assert(JSON_PONT_IDS_MAX == kIdsMax, "json_pont.h et json_amaran.h : meme nombre d'id par ordre");

#define TIC_MS 10            // une ligne de la file par tic (2.3)
#define REGARD_MS 100        // changements des lampes
#define BATTEMENT_MS 2000    // hb, quand les etat sont coupes ou lents (3.5)
#define FILE_EVENEMENTS 16
#define FILE_JOURNAL 6
#define PLAFOND_JOURNAL 20   // log par seconde (7.5)
#define DIFFEREES 4          // reponses qui attendent la fin d'un instantane

typedef enum { EV_ORDRE, EV_RELEVES, EV_MESH, EV_LAMPE, EV_LED } ev_type_t;

typedef struct {
  ev_type_t type;
  int8_t lampe;
  uint8_t a, b;         // ordre : signal, essai ; releves : manque, part ; mesh : diag ; lampe : quoi
  uint8_t n_ids;
  uint16_t endpoint;
  uint32_t delai_ms;    // ordre ; led : depuis_ms
  uint32_t ids[kIdsMax];
  uint32_t ids_perdus;
  const char *motif, *avant;  // led
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

static const amaran_config_t *s_cfg;
static SemaphoreHandle_t s_verrou;  // session, file, ecrivain, id en attente de reponse
static QueueHandle_t s_evenements, s_journal;
static uint32_t s_boot;

// Session : sous s_verrou ; s_machine et s_log se lisent aussi sans lui.
static volatile bool s_machine, s_log;
static Session s_reglages;
static uint32_t s_dernier_rx, s_derniere_cmd;
// Commande de la console en cours : le bail ne court pas (la console ne lit plus
// l'USB), et le bloc sante porte son id (une reponse fin perdue s'y voit, 6.2).
static bool s_en_commande;
static uint32_t s_cmd_id;
static uint32_t s_prochain_etat, s_prochain_lampes, s_prochain_compteurs, s_prochain_reseau, s_prochain_hb,
    s_prochain_regard;
static Queue s_file;
static differee_t s_differees[DIFFEREES];
static Cadence s_cadence;
static RateCap s_plafond_journal(PLAFOND_JOURNAL);
static resume_t s_resumes[LISTE_CAPACITE];

// Ecrivain : une ligne a la fois, sous s_verrou.
static Writer s_w;
static uint32_t s_n;
static uint32_t s_perdus, s_trop_longs, s_rejets;

// Copies de l'etat des lampes, relues sous s_verrou quand une ligne en a besoin.
static lampes_t s_lampes;
static liste_t s_liste;

static LineAssembler s_assembleur;  // tache de la console

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
static bool echu(uint32_t t, uint32_t echeance) { return (int32_t)(t - echeance) >= 0; }

// --- Ecriture (2.3)

// Tout ou rien, sans attendre ; une seconde chance une milliseconde plus tard, si
// une autre tache tenait le pilote (son verrou d'emission).
static bool ecrire(const void *p, size_t n) {
  if (usb_serial_jtag_write_bytes(p, n, 0) == (int)n) return true;
  vTaskDelay(1);
  return usb_serial_jtag_write_bytes(p, n, 0) == (int)n;
}

// La ligne formee dans s_w : n consomme, ecrite ou comptee perdue. Sous s_verrou.
static void envoyer(void) {
  s_n++;
  if (!s_w.finish()) {
    s_trop_longs++;
    return;
  }
  if (!ecrire(s_w.data(), s_w.size())) s_perdus++;
}

// Texte du protocole (fin de session) : meme chemin, sans attendre. Sous s_verrou.
static void texte(const char *t) {
  if (!ecrire(t, strlen(t))) s_perdus++;
}

static void reponse(const Reply &r) {
  reply(s_w, s_n, maintenant_ms(), r);
  envoyer();
}

static void repondre(uint32_t id, const char *cmd, bool ok, const char *code, const char *msg, uint32_t debut_ms) {
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.ok = ok;
  r.code = code;
  r.msg = msg;
  r.durMs = maintenant_ms() - debut_ms;
  reponse(r);
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

static void former(const Queued &q) {
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
      h.session = s_reglages;
      helloBase(s_w, s_n, ms, h);
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
      helloId(s_w, s_n, ms, h);
      break;
    }
    case Item::ConfigCatalogue:
      configCatalogue(s_w, s_n, ms);
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
      configMesh(s_w, s_n, ms, c);
      break;
    }
    case Item::ConfigLampe:
      relire_lampes();
      if (q.arg >= s_liste.n) return;
      configLampe(s_w, s_n, ms, q.arg, s_liste.lampes[q.arg]);
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
      etatPont(s_w, s_n, ms, e);
      break;
    }
    case Item::EtatLampe: {
      relire_lampes();
      const int i = q.arg;
      if (i >= s_lampes.n || i >= s_liste.n) return;
      resumer(i, &s_resumes[i]);
      etatLampe(s_w, s_n, ms, i, s_lampes.lampes[i], s_liste.lampes[i], s_resumes[i].endpoint,
                lampes_part_repondue(&s_lampes, i));
      break;
    }
    case Item::EtatSante: {
      EtatSante e;
      e.boot = s_boot;
      e.upS = up_s();
      e.cmdId = s_cmd_id;
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
      e.perdus = s_perdus;
      e.tropLongs = s_trop_longs;
      e.rejets = s_rejets;
      etatSante(s_w, s_n, ms, e);
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
      compteursMesh(s_w, s_n, ms, c);
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
      r.codeManuel = pont.code_manuel;
      r.qr = pont.qr;
      reseauMatter(s_w, s_n, ms, r);
      break;
    }
    case Item::NetThread:
      pont_lire(&pont);
      reseauThread(s_w, s_n, ms, pont.role, pont.thread_attache);
      break;
    case Item::Heartbeat:
      heartbeat(s_w, s_n, ms, s_boot, up_s(), s_perdus, s_cmd_id);
      break;
    case Item::Reply: {
      differee_t *d = &s_differees[q.arg % DIFFEREES];
      if (!d->utilisee) return;
      Reply r;
      r.id = d->id;
      r.cmd = d->cmd;
      r.durMs = ms - d->debut_ms;
      r.hasLease = d->bail;
      r.leaseS = s_reglages.bailS;
      r.upS = up_s();
      d->utilisee = false;
      reply(s_w, s_n, ms, r);
      break;
    }
  }
  envoyer();
}

// --- Session. Sous s_verrou.

static void pousser_hello(uint32_t t, bool session) {
  s_file.push(Item::HelloBase, t, session);
  s_file.push(Item::HelloId, t, session);
  s_file.push(Item::ConfigCatalogue, t, session);
  s_file.push(Item::ConfigMesh, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) s_file.push(Item::ConfigLampe, t, session, i);
}

static void pousser_etat(uint32_t t, bool session) {
  s_file.push(Item::EtatPont, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) s_file.push(Item::EtatLampe, t, session, i);
  s_file.push(Item::EtatSante, t, session);
  s_file.push(Item::CptMesh, t, session);
  s_file.push(Item::NetMatter, t, session);
  s_file.push(Item::NetThread, t, session);
}

// Reponse fin apres les lignes en file. Sans place : tout de suite.
static void differer(uint32_t id, const char *cmd, bool bail, uint32_t debut_ms) {
  for (uint8_t k = 0; k < DIFFEREES; k++) {
    differee_t *d = &s_differees[k];
    if (d->utilisee) continue;
    d->utilisee = true;
    d->id = id;
    d->debut_ms = debut_ms;
    d->bail = bail;
    copyCmd(d->cmd, cmd);
    if (s_file.push(Item::Reply, maintenant_ms(), false, k)) return;
    d->utilisee = false;
    break;
  }
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.durMs = maintenant_ms() - debut_ms;
  r.hasLease = bail;
  r.leaseS = s_reglages.bailS;
  r.upS = up_s();
  reponse(r);
}

static void entrer(uint16_t bail_s, uint32_t t) {
  s_file.dropSession();
  s_reglages = Session();
  s_reglages.bailS = bail_s;
  s_log = false;
  s_dernier_rx = s_derniere_cmd = t;
  s_prochain_etat = t + s_reglages.periodeMs;
  s_prochain_lampes = t + s_reglages.lampesMs;
  s_prochain_compteurs = t + s_reglages.compteursMs;
  s_prochain_reseau = t + s_reglages.reseauMs;
  s_prochain_hb = s_prochain_regard = t;
  memset(s_resumes, 0, sizeof(s_resumes));
  s_assembleur.reset();
  s_machine = true;
  pousser_hello(t, true);
  pousser_etat(t, true);
}

static void sortir(const char *cause, const char *message) {
  sessionEnd(s_w, s_n, maintenant_ms(), cause);
  envoyer();
  s_machine = false;
  s_log = false;
  s_file.dropSession();
  texte(message);
}

// Les lignes etat lampe dont ce qu'elles montrent a change.
static void regarder(uint32_t t) {
  relire_lampes();
  for (int i = 0; i < s_lampes.n && i < s_liste.n; i++) {
    resume_t r;
    resumer(i, &r);
    if (memcmp(&r, &s_resumes[i], sizeof(r)) != 0) s_file.push(Item::EtatLampe, t, true, (uint8_t)i);
  }
}

static void programmer(uint32_t t) {
  if (!s_en_commande && leaseExpired(t, s_dernier_rx, s_derniere_cmd, s_reglages.bailS)) {
    char m[80];
    snprintf(m, sizeof(m), "json : mode machine coupe (hote muet depuis %u s)\r\n", (unsigned)s_reglages.bailS);
    sortir("bail", m);
    return;
  }
  if (s_reglages.periodeMs && echu(t, s_prochain_etat)) {
    s_file.push(Item::EtatPont, t, true);
    s_file.push(Item::EtatSante, t, true);
    s_prochain_etat = t + s_reglages.periodeMs;
  }
  if (s_reglages.lampesMs && echu(t, s_prochain_lampes)) {
    for (uint8_t i = 0; i < s_cfg->liste.n; i++) s_file.push(Item::EtatLampe, t, true, i);
    s_prochain_lampes = t + s_reglages.lampesMs;
  }
  if (echu(t, s_prochain_regard)) {
    regarder(t);
    s_prochain_regard = t + REGARD_MS;
  }
  if (s_reglages.compteursMs && echu(t, s_prochain_compteurs)) {
    s_file.push(Item::CptMesh, t, true);
    s_prochain_compteurs = t + s_reglages.compteursMs;
  }
  if (s_reglages.reseauMs && echu(t, s_prochain_reseau)) {
    s_file.push(Item::NetMatter, t, true);
    s_file.push(Item::NetThread, t, true);
    s_prochain_reseau = t + s_reglages.reseauMs;
  }
  if ((s_reglages.periodeMs == 0 || s_reglages.periodeMs > BATTEMENT_MS) && echu(t, s_prochain_hb)) {
    s_file.push(Item::Heartbeat, t, true);
    s_prochain_hb = t + BATTEMENT_MS;
  }
}

// --- Evenements. Sous s_verrou.

static void evenement(const evenement_t &e) {
  const uint32_t ms = maintenant_ms();
  switch (e.type) {
    case EV_ORDRE: {
      Ordre o;
      o.lampe = e.lampe;
      o.issue = e.a == LAMPES_SIGNAL_CONFIRME ? "confirme" : e.a == LAMPES_SIGNAL_ABANDON ? "abandon" : "tenu";
      o.delaiMs = e.delai_ms;
      o.essai = e.b;
      o.nIds = e.n_ids;
      memcpy(o.ids, e.ids, sizeof(o.ids));
      o.idsPerdus = e.ids_perdus;
      ordre(s_w, s_n, ms, o);
      break;
    }
    case EV_RELEVES:
      alerteReleves(s_w, s_n, ms, e.lampe, e.a != 0, e.b);
      break;
    case EV_MESH:
      alerteMesh(s_w, s_n, ms, code_diag((diagnostic_t)e.a));
      break;
    case EV_LAMPE: {
      static const char *const QUOI[] = {"entree", "masquee", "remise", "echec"};
      lampe(s_w, s_n, ms, e.lampe, QUOI[e.a % 4], e.endpoint);
      break;
    }
    case EV_LED:
      led(s_w, s_n, ms, e.motif, e.avant, e.a != 0, e.delai_ms);
      break;
  }
  envoyer();
}

static void journal(const journal_t &j) {
  const uint32_t t = maintenant_ms();
  if (!s_plafond_journal.available(t)) {
    s_plafond_journal.skip();
    return;
  }
  s_plafond_journal.take();
  logLine(s_w, s_n, t, j.src, j.alerte ? "alerte" : "notice", j.txt, s_plafond_journal.takeSkipped());
  envoyer();
}

static void tache_json(void *arg) {
  (void)arg;
  uint32_t prochain_tic = maintenant_ms();
  for (;;) {
    const int32_t attente = (int32_t)(prochain_tic - maintenant_ms());
    evenement_t e;
    if (xQueueReceive(s_evenements, &e, attente > 0 ? pdMS_TO_TICKS(attente) : 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      if (s_machine) evenement(e);
      xSemaphoreGive(s_verrou);
      // Les evenements d'abord (ils ne passent pas par la file), mais le tic a son heure.
      if (!echu(maintenant_ms(), prochain_tic)) continue;
    }
    journal_t j;
    while (xQueueReceive(s_journal, &j, 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      if (s_machine) journal(j);
      xSemaphoreGive(s_verrou);
    }
    const uint32_t t = maintenant_ms();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    if (s_machine) programmer(t);
    s_perdus += s_file.dropLate(t);
    const Queued *q = s_file.front();
    if (q) {
      const Queued copie = *q;
      s_file.pop();
      former(copie);
    }
    xSemaphoreGive(s_verrou);
    prochain_tic = t + TIC_MS;
  }
}

// --- Commandes

static bool lire_ms(const char *texte, uint32_t min, uint32_t max, uint32_t *v) {
  return texte_lire_nombre(texte, v) && (*v == 0 || (*v >= min && *v <= max));
}

// La famille `json` (3.3). id 0 : sans reponse, texte pour un humain. Sous s_verrou.
static void commande_json(uint32_t id, const char *vue, int argc, char **argv, uint32_t debut_ms) {
  static const char USAGE[] = "json [1 [bail <s>]|0|etat|hello|ping|periode|lampes|compteurs|reseau <ms>|log 0|1]";
  const uint32_t t = maintenant_ms();
  const char *sous = argc >= 2 ? argv[1] : "";
  uint32_t v = 0;
  const char *erreur = nullptr;
  if (argc == 1) {
    printf("json : mode %s, bail %u s, etat %" PRIu32 " ms, lampes %" PRIu32 " ms, compteurs %" PRIu32
           " ms, reseau %" PRIu32 " ms, log %s ; lignes %" PRIu32 ", perdues %" PRIu32 ", refusees %" PRIu32 "\n",
           s_machine ? "machine" : "texte", (unsigned)s_reglages.bailS, s_reglages.periodeMs, s_reglages.lampesMs,
           s_reglages.compteursMs, s_reglages.reseauMs, s_reglages.log ? "oui" : "non", s_n, s_perdus, s_rejets);
  } else if (!strcmp(sous, "1")) {
    if (argc == 2 || (argc == 4 && !strcmp(argv[2], "bail") && lire_ms(argv[3], 10, 600, &v))) {
      entrer(argc == 4 ? (uint16_t)v : 30, t);
      if (id) {
        differer(id, vue, true, debut_ms);
        return;
      }
    } else {
      erreur = "json 1 [bail 0|10-600]";
    }
  } else if (!strcmp(sous, "0") && argc == 2) {
    if (id) repondre(id, vue, true, "ok", nullptr, debut_ms);
    if (s_machine) sortir("commande", "json : mode machine coupe\r\n");
    return;
  } else if ((!strcmp(sous, "etat") || !strcmp(sous, "hello")) && argc == 2) {
    if (!strcmp(sous, "etat")) pousser_etat(t, false);
    else pousser_hello(t, false);
    if (id) {
      differer(id, vue, false, debut_ms);
      return;
    }
  } else if (!strcmp(sous, "ping") && argc == 2) {
    s_dernier_rx = t;
    if (id) {
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.durMs = t - debut_ms;
      r.hasLease = true;
      r.leaseS = s_reglages.bailS;
      r.upS = up_s();
      reponse(r);
      return;
    }
  } else if (argc == 3 && !strcmp(sous, "periode")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      s_reglages.periodeMs = v;
      s_prochain_etat = s_prochain_hb = t;
    } else {
      erreur = "json periode <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "lampes")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      s_reglages.lampesMs = v;
      s_prochain_lampes = t;
    } else {
      erreur = "json lampes <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "compteurs")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      s_reglages.compteursMs = v;
      s_prochain_compteurs = t;
    } else {
      erreur = "json compteurs <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "reseau")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      s_reglages.reseauMs = v;
      s_prochain_reseau = t;
    } else {
      erreur = "json reseau <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "log") && (!strcmp(argv[2], "0") || !strcmp(argv[2], "1"))) {
    s_reglages.log = !strcmp(argv[2], "1");
    s_log = s_reglages.log;
  } else {
    erreur = USAGE;
  }
  if (id) {
    repondre(id, vue, !erreur, erreur ? "usage" : "ok", erreur, debut_ms);
  } else if (erreur) {
    printf("erreur : %s\n", erreur);
  } else if (argc > 1) {
    printf("ok json %s\n", sous);
  }
}

int json_pont_commande(int argc, char **argv) {
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  commande_json(0, "", argc, argv, maintenant_ms());
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

void json_pont_executer(char *ligne, bool trop_long) {
  const uint32_t debut = maintenant_ms();
  uint32_t id = 0;
  char *cmd = ligne;
  const bool a_id = parseIdPrefix(ligne, &id, &cmd);
  // Ligne vide (l'effacement 0x15 + LF que l'app envoie a l'ouverture) : rien a faire.
  if (!a_id && !trop_long && strspn(cmd, " ") == strlen(cmd)) return;
  // La commande telle que la reponse la cite : masquee (mesh cles), puis tronquee.
  char vue[kCmdTextMax + 1];
  {
    char masquee[kCmdMax + 1];
    snprintf(masquee, sizeof(masquee), "%s", cmd);
    maskCmd(masquee);
    copyCmd(vue, masquee);
  }
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_dernier_rx = debut;
  const char *refus = nullptr, *code = nullptr;
  if (trop_long) {
    refus = "ligne de plus de 127 octets : rien n'est execute";
    code = "trop_long";
  } else if (s_machine && !s_cadence.allow(debut)) {
    refus = "plus de 20 lignes par seconde : rien n'est execute";
    code = "cadence";
  }
  if (refus) {
    s_rejets++;
    if (a_id) repondre(id, vue, false, code, refus, debut);
    xSemaphoreGive(s_verrou);
    if (!a_id) printf("erreur : %s\n", refus);
    return;
  }
  // Les mots de la commande (esp_console_run decoupe une copie de son cote).
  static char copie[kCmdMax + 1];
  static char *argv[8];
  snprintf(copie, sizeof(copie), "%s", cmd);
  const int argc = (int)esp_console_split_argv(copie, argv, sizeof(argv) / sizeof(argv[0]));
  if (argc >= 1 && !strcmp(argv[0], "json")) {
    commande_json(a_id ? id : 0, vue, argc, argv, debut);
    s_derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  int lampe = 0;
  int8_t marche = -1;
  int32_t intensite = -1;
  bool usage = false;
  if (a_id && ordre_de_lampe(argc, argv, &lampe, &marche, &intensite, &usage)) {
    if (usage) {
      char msg[64];
      snprintf(msg, sizeof(msg), "lampe <1-%u> on|off|niveau <0-1000>", (unsigned)s_cfg->liste.n);
      repondre(id, vue, false, "usage", msg, debut);
    } else {
      // L'id part avec l'ordre : l'evenement ordre qui le finira le portera (7.1).
      const bool m = marche == 1;
      const uint16_t v = (uint16_t)intensite;
      tache_lampes_ordre_id(lampe, marche >= 0 ? &m : nullptr, intensite >= 0 ? &v : nullptr, id);
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.code = "accepte";
      r.suite = Reply::SuiteOrder;
      r.lampe = (uint8_t)(lampe + 1);
      r.durMs = maintenant_ms() - debut;
      reponse(r);
    }
    s_derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  // Toute autre commande : debut, son texte, fin (6.2). Rien sous s_verrou pendant
  // qu'elle tourne : la tache json continue d'emettre. L'id de la commande entre
  // dans le bloc sante avec le debut, et en sort avec la fin.
  s_en_commande = true;
  if (a_id) {
    s_cmd_id = id;
    Reply r;
    r.id = id;
    r.fin = false;
    r.cmd = vue;
    r.code = "en_cours";
    reponse(r);
  }
  xSemaphoreGive(s_verrou);
  int ret = 0;
  const esp_err_t err = argc >= 1 ? esp_console_run(cmd, &ret) : ESP_ERR_INVALID_ARG;
  if (err == ESP_ERR_NOT_FOUND) printf("Commande inconnue : \"%s\" (help)\n", argv[0]);
  fflush(stdout);  // le texte de la commande passe avant la reponse fin
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_derniere_cmd = maintenant_ms();
  s_en_commande = false;
  s_cmd_id = 0;
  if (a_id) {
    const bool inconnue = err != ESP_OK;
    const bool ok = !inconnue && ret == 0;
    repondre(id, vue, ok, inconnue ? "inconnue" : ok ? "ok" : "erreur", nullptr, debut);
    // Une commande mesh reussie a pu changer la configuration du Mesh (5.2).
    if (ok && !strcmp(argv[0], "mesh")) s_file.push(Item::ConfigMesh, maintenant_ms(), false);
  }
  xSemaphoreGive(s_verrou);
}

void json_pont_lire(void) {
  uint8_t octets[64];
  const int n = usb_serial_jtag_read_bytes(octets, sizeof(octets), pdMS_TO_TICKS(200));
  if (n <= 0) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_dernier_rx = maintenant_ms();
  xSemaphoreGive(s_verrou);
  for (int i = 0; i < n; i++) {
    if (s_assembleur.feed(octets[i]) != LineAssembler::Ev::Line) continue;
    json_pont_executer(s_assembleur.text(), s_assembleur.tooLong());
    s_assembleur.reset();
  }
}

bool json_pont_machine(void) { return s_machine; }

// --- Evenements, depuis les autres taches

static void poster(const evenement_t &e) {
  if (s_machine && s_evenements) xQueueSend(s_evenements, &e, 0);
}

void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     uint8_t n_ids, uint32_t ids_perdus) {
  evenement_t e = {};
  e.type = EV_ORDRE;
  e.lampe = (int8_t)lampe;
  e.a = (uint8_t)signal;
  e.b = essai;
  e.delai_ms = delai_ms;
  e.n_ids = n_ids > kIdsMax ? kIdsMax : n_ids;
  for (uint8_t i = 0; i < e.n_ids; i++) e.ids[i] = ids[i];
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

void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) {
  char txt[192];
  va_list ap;
  va_start(ap, format);
  vsnprintf(txt, sizeof(txt), format, ap);
  va_end(ap);
  if (s_machine && s_log && s_journal) {
    journal_t j;
    j.src = src;
    j.alerte = alerte;
    const size_t n = strnlen(txt, sizeof(j.txt) - 1);  // log.txt : 127 octets au plus (7.5)
    memcpy(j.txt, txt, n);
    j.txt[n] = 0;
    if (xQueueSend(s_journal, &j, 0) == pdTRUE) return;
  }
  printf("%s\n", txt);
}

esp_err_t json_pont_demarrer(const amaran_config_t *cfg) {
  s_cfg = cfg;
  // Aucune radio n'est encore active : le generateur tire de vrai bruit (comme Halo).
  bootloader_random_enable();
  s_boot = esp_random();
  bootloader_random_disable();
  s_verrou = xSemaphoreCreateMutex();
  s_evenements = xQueueCreate(FILE_EVENEMENTS, sizeof(evenement_t));
  s_journal = xQueueCreate(FILE_JOURNAL, sizeof(journal_t));
  if (!s_verrou || !s_evenements || !s_journal) return ESP_ERR_NO_MEM;
  // Basse priorite : les lampes, Matter et la console passent avant.
  return xTaskCreate(tache_json, "json", 4096, NULL, 1, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
````

- [ ] **Step 3 : notre tâche de console.**

`firmware/main/console_pont.h`, bloc 1 sur 2. Remplacer :

````c
// Console du pont, en francais (spec 7.5).
#pragma once

````

par :

````c
// Console du pont, en francais (spec 7.5), et son mode machine
// (docs/PROTOCOLE-JSON.md, json_pont.h).
#pragma once

````

`firmware/main/console_pont.h`, bloc 2 sur 2. Remplacer :

````c
#endif

// Demarre la console sur l'USB natif. cfg reste la propriete de l'appelant.
void console_pont_demarrer(amaran_config_t *cfg);

````

par :

````c
#endif

// Taches dont `taches` et le bloc sante du protocole JSON donnent la marge de pile.
#define CONSOLE_PONT_NB_TACHES 9
extern const char *const CONSOLE_PONT_TACHES[CONSOLE_PONT_NB_TACHES];

// Demarre la console sur l'USB natif, apres json_pont_demarrer. cfg reste la
// propriete de l'appelant.
void console_pont_demarrer(amaran_config_t *cfg);

````

`firmware/main/console_pont.c`, bloc 1 sur 4. Remplacer :

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
````

par :

````c
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
````

`firmware/main/console_pont.c`, bloc 2 sur 4. Remplacer :

````c
#include "texte.h"

static amaran_config_t *s_cfg;
// Copies : trop grosses pour la pile de la console. Une commande a la fois (REPL).
static lampes_t s_l;
static liste_t s_liste;
````

par :

````c
#include "texte.h"

#define INVITE "amaran> "
#define LIGNE_MAX 256  // linenoise : au-dela, la ligne est coupee ; 128 a 255 sont refusees (JSON_PONT_CMD_MAX)

static amaran_config_t *s_cfg;
// Copies : trop grosses pour la pile de la console. Une commande a la fois.
static lampes_t s_l;
static liste_t s_liste;
````

`firmware/main/console_pont.c`, bloc 3 sur 4. Remplacer :

````c
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
````

par :

````c
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
  if (linenoiseProbe() != 0) linenoiseSetDumbMode(1);  // terminal sans sequences d'echappement (l'app)
  const esp_console_cmd_t cmds[] = {
      {.command = "lampes", .help = "une ligne par lampe : Maison, etat lu, joignabilite, relectures ; ordres",
````

`firmware/main/console_pont.c`, bloc 4 sur 4. Remplacer :

````c
      {.command = "cause", .help = "pourquoi la carte a redemarre la derniere fois", .func = socle_commande_cause},
      {.command = "taches", .help = "marges de pile des taches et du tas (octets)", .func = mesh_console_taches},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
  ESP_ERROR_CHECK(esp_console_register_help_command());
  ESP_ERROR_CHECK(esp_console_start_repl(repl));
}
````

par :

````c
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
````

- [ ] **Step 4 : la tâche des lampes : ordres avec `id`, événements, annonces.**

`firmware/main/tache_lampes.h`, bloc 1 sur 3. Remplacer :

````c

#include "config_amaran.h"
#include "lampes.h"
#include "liste.h"
````

par :

````c

#include "config_amaran.h"
#include "diagnostic.h"
#include "lampes.h"
#include "liste.h"
````

`firmware/main/tache_lampes.h`, bloc 2 sur 3. Remplacer :

````c
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
````

par :

````c
// CHIP comprise). marche/intensite : NULL = inchange.
void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter);
// Ordre de l'app (mode JSON) : son id reviendra dans l'evenement ordre qui le finira.
void tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id);
// Nouvelle periode de relecture (ms).
void tache_lampes_regler_releve(uint32_t releve_ms);
````

`firmware/main/tache_lampes.h`, bloc 3 sur 3. Remplacer :

````c
uint32_t tache_lampes_confirmes(void);
uint32_t tache_lampes_abandons(void);

#ifdef __cplusplus
````

par :

````c
uint32_t tache_lampes_confirmes(void);
uint32_t tache_lampes_abandons(void);
// Etat du diagnostic du Bluetooth Mesh (spec 7.3).
diagnostic_t tache_lampes_diagnostic(void);

#ifdef __cplusplus
````

`firmware/main/tache_lampes.c`, bloc 1 sur 13. Remplacer :

````c

#include "diagnostic.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
````

par :

````c

#include "diagnostic.h"
#include "json_pont.h"
#include "mesh_amaran.h"
#include "mesh_console.h"
````

`firmware/main/tache_lampes.c`, bloc 2 sur 13. Remplacer :

````c
  uint16_t intensite;
  uint32_t releve_ms;
} message_t;

````

par :

````c
  uint16_t intensite;
  uint32_t releve_ms;
  uint32_t id;  // ordre de l'app (mode JSON) ; 0 : aucun
} message_t;

````

`firmware/main/tache_lampes.c`, bloc 3 sur 13. Remplacer :

````c
static bool s_cles;                  // cles du reseau presentes au demarrage
static diagnostic_suivi_t s_diag;    // Bluetooth Mesh inoperant (spec 7.3)

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
````

par :

````c
static bool s_cles;                  // cles du reseau presentes au demarrage
static diagnostic_suivi_t s_diag;    // Bluetooth Mesh inoperant (spec 7.3)
static volatile diagnostic_t s_diag_etat;
// Id des ordres de l'app en cours, par lampe : le prochain signal de la lampe les
// porte (un ordre arrive pendant un autre se fond dans le sien). Tache lampes.
static uint32_t s_ids[LAMPES_CAPACITE][JSON_PONT_IDS_MAX];
static uint8_t s_nb_ids[LAMPES_CAPACITE];
static uint32_t s_ids_perdus[LAMPES_CAPACITE];

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
````

`firmware/main/tache_lampes.c`, bloc 4 sur 13. Remplacer :

````c
}

static void sortie_signaler(void *ctx, int lampe, lampes_signal_t signal) {
  (void)ctx;
  (void)lampe;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    s_confirmes++;
````

par :

````c
}

// Le voyant suit confirmes et abandons ; l'app recoit chaque fin d'ordre, avec les
// id de ses ordres que le signal couvre (sous s_verrou, dans la tache lampes).
static void sortie_signaler(void *ctx, int lampe, lampes_signal_t signal) {
  (void)ctx;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    s_confirmes++;
````

`firmware/main/tache_lampes.c`, bloc 5 sur 13. Remplacer :

````c
    s_abandons++;
  }
}

````

par :

````c
    s_abandons++;
  }
  const lampe_t *p = &s_lampes.lampes[lampe];
  json_pont_ordre(lampe, signal, p->dernier_delai_ms, signal == LAMPES_SIGNAL_TENU ? 0 : p->essai, s_ids[lampe],
                  s_nb_ids[lampe], s_ids_perdus[lampe]);
  s_nb_ids[lampe] = 0;
  s_ids_perdus[lampe] = 0;
}

````

`firmware/main/tache_lampes.c`, bloc 6 sur 13. Remplacer :

````c
  (void)ctx;
  if (manque) {
    printf("!! lampe %d : relectures manquees, %u %% repondues sur 10 min : allonger la periode (mesh releve)\n",
           lampe + 1, (unsigned)pour_cent);
  } else {
    printf("[lampes] lampe %d : relectures de nouveau repondues a %u %% sur 10 min\n", lampe + 1,
           (unsigned)pour_cent);
  }
}

````

par :

````c
  (void)ctx;
  if (manque) {
    json_pont_annoncer("lampes", true,
                       "!! lampe %d : relectures manquees, %u %% repondues sur 10 min : allonger la periode (mesh releve)",
                       lampe + 1, (unsigned)pour_cent);
  } else {
    json_pont_annoncer("lampes", false, "[lampes] lampe %d : relectures de nouveau repondues a %u %% sur 10 min",
                       lampe + 1, (unsigned)pour_cent);
  }
  json_pont_alerte_releves(lampe, manque, pour_cent);
}

````

`firmware/main/tache_lampes.c`, bloc 7 sur 13. Remplacer :

````c
    if (!s_lampes.lampes[i].entendue || !liste_a_exposer_a_l_ecoute(a)) continue;
    liste_marquer_vue(a);
    if (config_maj_drapeaux(a->mac, a->drapeaux) != ESP_OK) printf("!! lampe %d : vue, mais NVS non mise a jour\n", i + 1);
    if (exposer(i) == ESP_OK) {
      printf("[lampes] lampe %d entendue : dans Maison (EP%u)\n", i + 1, (unsigned)pont_endpoint(i));
    } else {
      printf("!! lampe %d entendue, mais pas dans Maison (endpoint Matter)\n", i + 1);
    }
  }
````

par :

````c
    if (!s_lampes.lampes[i].entendue || !liste_a_exposer_a_l_ecoute(a)) continue;
    liste_marquer_vue(a);
    if (config_maj_drapeaux(a->mac, a->drapeaux) != ESP_OK) {
      json_pont_annoncer("lampes", true, "!! lampe %d : vue, mais NVS non mise a jour", i + 1);
    }
    if (exposer(i) == ESP_OK) {
      json_pont_annoncer("lampes", false, "[lampes] lampe %d entendue : dans Maison (EP%u)", i + 1,
                         (unsigned)pont_endpoint(i));
      json_pont_lampe(i, JSON_LAMPE_ENTREE, pont_endpoint(i));
    } else {
      json_pont_annoncer("lampes", true, "!! lampe %d entendue, mais pas dans Maison (endpoint Matter)", i + 1);
      json_pont_lampe(i, JSON_LAMPE_ECHEC, 0);
    }
  }
````

`firmware/main/tache_lampes.c`, bloc 8 sur 13. Remplacer :

````c
    lampes_regler_releve(&s_lampes, m->releve_ms);
    return;
  }
  lampes_ordre(&s_lampes, m->lampe, m->a_marche ? &m->marche : NULL, m->a_intensite ? &m->intensite : NULL,
````

par :

````c
    lampes_regler_releve(&s_lampes, m->releve_ms);
    return;
  }
  // L'id d'abord : un ordre deja tenu, ou un Mesh pas pret, signale aussitot.
  if (m->id && m->lampe >= 0 && m->lampe < s_lampes.n) {
    const int i = m->lampe;
    if (s_nb_ids[i] == JSON_PONT_IDS_MAX) {  // le plus ancien sort
      memmove(s_ids[i], s_ids[i] + 1, (JSON_PONT_IDS_MAX - 1) * sizeof(s_ids[i][0]));
      s_nb_ids[i]--;
      s_ids_perdus[i]++;
    }
    s_ids[i][s_nb_ids[i]++] = m->id;
  }
  lampes_ordre(&s_lampes, m->lampe, m->a_marche ? &m->marche : NULL, m->a_intensite ? &m->intensite : NULL,
````

`firmware/main/tache_lampes.c`, bloc 9 sur 13. Remplacer :

````c
  const diagnostic_ecarts_t compteurs = {st.annonces, st.nid_reconnu, st.netmic_faux, st.acces_dechiffres};
  if (!diagnostic_suivre(&s_diag, s_cles, mesh_pret(), &compteurs, t)) return;
  if (s_diag.etat == DIAG_OK) {
    printf("[mesh] de nouveau operationnel\n");
  } else {
    printf("!! Bluetooth Mesh inoperant : %s\n", diagnostic_texte(s_diag.etat));
  }
  socle_panne_mesh(s_diag.etat != DIAG_OK);
}
````

par :

````c
  const diagnostic_ecarts_t compteurs = {st.annonces, st.nid_reconnu, st.netmic_faux, st.acces_dechiffres};
  if (!diagnostic_suivre(&s_diag, s_cles, mesh_pret(), &compteurs, t)) return;
  s_diag_etat = s_diag.etat;
  if (s_diag.etat == DIAG_OK) {
    json_pont_annoncer("mesh", false, "[mesh] de nouveau operationnel");
  } else {
    json_pont_annoncer("mesh", true, "!! Bluetooth Mesh inoperant : %s", diagnostic_texte(s_diag.etat));
  }
  json_pont_alerte_mesh(s_diag.etat);
  socle_panne_mesh(s_diag.etat != DIAG_OK);
}
````

`firmware/main/tache_lampes.c`, bloc 10 sur 13. Remplacer :

````c
}

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  if (!s_file || lampe < 0 || lampe >= LAMPES_CAPACITE) return;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter};
  if (marche) {
    m.a_marche = true;
````

par :

````c
}

static void envoyer_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter, uint32_t id) {
  if (!s_file || lampe < 0 || lampe >= LAMPES_CAPACITE) return;
  message_t m = {.type = MSG_ORDRE, .lampe = (int8_t)lampe, .depuis_matter = depuis_matter, .id = id};
  if (marche) {
    m.a_marche = true;
````

`firmware/main/tache_lampes.c`, bloc 11 sur 13. Remplacer :

````c
  // vide la file en continu.
  xQueueSend(s_file, &m, 0);
}

````

par :

````c
  // vide la file en continu.
  xQueueSend(s_file, &m, 0);
}

void tache_lampes_ordre(int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter) {
  envoyer_ordre(lampe, marche, intensite, depuis_matter, 0);
}

void tache_lampes_ordre_id(int lampe, const bool *marche, const uint16_t *intensite, uint32_t id) {
  envoyer_ordre(lampe, marche, intensite, false, id);
}

````

`firmware/main/tache_lampes.c`, bloc 12 sur 13. Remplacer :

````c
    s_liste.lampes[lampe] = copie;
    err = afficher ? exposer(lampe) : pont_masquer(lampe);
  }
  xSemaphoreGive(s_verrou);
````

par :

````c
    s_liste.lampes[lampe] = copie;
    err = afficher ? exposer(lampe) : pont_masquer(lampe);
    json_pont_lampe(lampe, err != ESP_OK ? JSON_LAMPE_ECHEC : afficher ? JSON_LAMPE_REMISE : JSON_LAMPE_MASQUEE,
                    pont_endpoint(lampe));
  }
  xSemaphoreGive(s_verrou);
````

`firmware/main/tache_lampes.c`, bloc 13 sur 13. Remplacer :

````c

uint32_t tache_lampes_abandons(void) { return s_abandons; }
````

par :

````c

uint32_t tache_lampes_abandons(void) { return s_abandons; }

diagnostic_t tache_lampes_diagnostic(void) { return s_diag_etat; }
````

- [ ] **Step 5 : le côté Matter : un relevé sans verrou.**

`firmware/main/pont_matter.h`, bloc 1 sur 2. Remplacer :

````c
#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
````

par :

````c
#define PONT_PLAFOND_ABONNEMENT_S 20  // lecon du Halo : Apple se reabonne quand l'intervalle expire
#define PONT_NIVEAU_PLANCHER 4        // lecon du Halo : sous 4, Maison montre une lampe allumee a fond
#define PONT_NOM "Pont amaran"        // NodeLabel

// Releve du cote Matter pour le protocole JSON : rien n'y prend un verrou.
typedef struct {
  bool demarre;
  uint8_t fabriques;
  bool ble_annonce, identifie, thread_attache;
  const char *role;  // role Thread du dernier evenement : disabled, detached, child, router, leader
  uint32_t abo_demandes, abo_plafonnes, abo_etablis, abo_termines;
  // Lus une fois, juste apres le demarrage de Matter ; NULL avant, ou en cas d'echec.
  const char *code_manuel, *qr, *fabricant, *produit, *serie;
} pont_infos_t;

// Ordre d'un controleur pour une lampe (appele dans la tache CHIP, sans bloquer) :
````

`firmware/main/pont_matter.h`, bloc 2 sur 2. Remplacer :

````c
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
void pont_afficher(void);
// Retire toutes les fabriques Matter, puis la pile redemarre la carte. Les
// reglages "amaran" (cles, lampes) restent (spec 7.7).
````

par :

````c
// La commande `matter` : mise en service, fabriques, Thread, abonnements, codes.
void pont_afficher(void);
// Releve pour le protocole JSON, depuis n'importe quelle tache, sans verrou.
void pont_lire(pont_infos_t *infos);
// Retire toutes les fabriques Matter, puis la pile redemarre la carte. Les
// reglages "amaran" (cles, lampes) restent (spec 7.7).
````

`firmware/main/pont_matter.cpp`, bloc 1 sur 4. Remplacer :

````cpp
static volatile uint32_t s_identifie;
static volatile uint32_t s_effet_fin[EMPLACEMENTS];

// --- Abonnements : intervalle maximal plafonne (lecon du Halo : apres un
````

par :

````cpp
static volatile uint32_t s_identifie;
static volatile uint32_t s_effet_fin[EMPLACEMENTS];
// Codes d'appairage et identite, lus une fois sous le verrou de la pile juste apres
// esp_matter::start : le protocole JSON les rend ensuite sans verrou.
static char s_qr[128], s_manuel[32], s_fabricant[33], s_produit[33], s_serie[33];
static volatile bool s_infos_lues;

// --- Abonnements : intervalle maximal plafonne (lecon du Halo : apres un
````

`firmware/main/pont_matter.cpp`, bloc 2 sur 4. Remplacer :

````cpp
  node::config_t cfg_noeud;
  snprintf(cfg_noeud.root_node.basic_information.node_label,
           sizeof(cfg_noeud.root_node.basic_information.node_label), "%s", "Pont amaran");
  // Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1).
  s_noeud = node::create(&cfg_noeud, rappel_attribut, rappel_identification);
````

par :

````cpp
  node::config_t cfg_noeud;
  snprintf(cfg_noeud.root_node.basic_information.node_label,
           sizeof(cfg_noeud.root_node.basic_information.node_label), "%s", PONT_NOM);
  // Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1).
  s_noeud = node::create(&cfg_noeud, rappel_attribut, rappel_identification);
````

`firmware/main/pont_matter.cpp`, bloc 3 sur 4. Remplacer :

````cpp
    chip::app::InteractionModelEngine::GetInstance()->RegisterReadHandlerAppCallback(&s_plafond);
    s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
  }
  // Les lampes exposees, juste apres start (le compteur d'esp-matter vient d'etre
````

par :

````cpp
    chip::app::InteractionModelEngine::GetInstance()->RegisterReadHandlerAppCallback(&s_plafond);
    s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
    // Codes d'appairage (ils ne changent pas) et identite, pour le protocole JSON.
    chip::MutableCharSpan qr_span(s_qr), manuel_span(s_manuel);
    const chip::RendezvousInformationFlags ble(chip::RendezvousInformationFlag::kBLE);
    if (GetQRCode(qr_span, ble) != CHIP_NO_ERROR) s_qr[0] = 0;
    if (GetManualPairingCode(manuel_span, ble) != CHIP_NO_ERROR) s_manuel[0] = 0;
    chip::DeviceLayer::DeviceInstanceInfoProvider *infos = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
    if (!infos || infos->GetVendorName(s_fabricant, sizeof(s_fabricant)) != CHIP_NO_ERROR) s_fabricant[0] = 0;
    if (!infos || infos->GetProductName(s_produit, sizeof(s_produit)) != CHIP_NO_ERROR) s_produit[0] = 0;
    if (!infos || infos->GetSerialNumber(s_serie, sizeof(s_serie)) != CHIP_NO_ERROR) s_serie[0] = 0;
    s_infos_lues = true;
  }
  // Les lampes exposees, juste apres start (le compteur d'esp-matter vient d'etre
````

`firmware/main/pont_matter.cpp`, bloc 4 sur 4. Remplacer :

````cpp
}

bool pont_identifie(void) {
  if (s_identifie) return true;
````

par :

````cpp
}

void pont_lire(pont_infos_t *infos) {
  memset(infos, 0, sizeof(*infos));
  infos->demarre = esp_matter::is_started();
  infos->fabriques = s_fabriques;
  infos->ble_annonce = s_ble_annonce;
  infos->identifie = pont_identifie();
  infos->thread_attache = pont_thread_attache();
  infos->role = otThreadDeviceRoleToString(static_cast<otDeviceRole>(s_role));
  infos->abo_demandes = s_abo_demandes;
  infos->abo_plafonnes = s_abo_plafonnes;
  infos->abo_etablis = s_abo_etablis;
  infos->abo_termines = s_abo_termines;
  if (s_infos_lues) {
    infos->code_manuel = s_manuel[0] ? s_manuel : NULL;
    infos->qr = s_qr[0] ? s_qr : NULL;
    infos->fabricant = s_fabricant[0] ? s_fabricant : NULL;
    infos->produit = s_produit[0] ? s_produit : NULL;
    infos->serie = s_serie[0] ? s_serie : NULL;
  }
}

bool pont_identifie(void) {
  if (s_identifie) return true;
````

- [ ] **Step 6 : le socle : le voyant pour le bloc `sante`, l'événement `led`, les annonces du bouton.**

`firmware/main/socle.h`, bloc 1 sur 2. Remplacer :

````c

#include <stdbool.h>

#include "esp_err.h"
````

par :

````c

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
````

`firmware/main/socle.h`, bloc 2 sur 2. Remplacer :

````c
// Bluetooth Mesh inoperant (spec 7.3) : rouge fixe une fois le pont appaire.
void socle_panne_mesh(bool oui);
// Commande `led [test|stop]`.
int socle_commande_led(int argc, char **argv);
````

par :

````c
// Bluetooth Mesh inoperant (spec 7.3) : rouge fixe une fois le pont appaire.
void socle_panne_mesh(bool oui);

// Ce que montre le voyant, pour le protocole JSON (bloc sante).
typedef struct {
  const char *motif;   // code du motif (status_led.h : patternCode)
  bool test;           // `led test` en cours
  uint32_t depuis_ms;  // age de la phase du motif
} socle_voyant_t;
void socle_voyant(socle_voyant_t *v);
// Commande `led [test|stop]`.
int socle_commande_led(int argc, char **argv);
````

`firmware/main/socle.cpp`, bloc 1 sur 8. Remplacer :

````cpp

#include "boot_button.h"
#include "pont_matter.h"
#include "status_led.h"
````

par :

````cpp

#include "boot_button.h"
#include "json_pont.h"
#include "pont_matter.h"
#include "status_led.h"
````

`firmware/main/socle.cpp`, bloc 2 sur 8. Remplacer :

````cpp
static volatile statusled::Pattern s_motif;
static volatile uint32_t s_couleur;

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
````

par :

````cpp
static volatile statusled::Pattern s_motif;
static volatile uint32_t s_couleur;
static volatile uint32_t s_phase_ms;  // depart de la phase du motif affiche (protocole JSON)

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
````

`firmware/main/socle.cpp`, bloc 3 sur 8. Remplacer :

````cpp
      if (!dit) {
        dit = true;
        printf("[bouton] tenu pendant un redemarrage : reset au relachement (IO9, broche de strapping)\n");
      }
    } else if (t - haute_depuis >= (int64_t)kArretHautMs * 1000) {
````

par :

````cpp
      if (!dit) {
        dit = true;
        json_pont_annoncer("bouton", false,
                           "[bouton] tenu pendant un redemarrage : reset au relachement (IO9, broche de strapping)");
      }
    } else if (t - haute_depuis >= (int64_t)kArretHautMs * 1000) {
````

`firmware/main/socle.cpp`, bloc 4 sur 8. Remplacer :

````cpp
    // redemarre : esp_matter::factory_reset() ne dit pas son echec.
    if (s_redemarrage || t - s_desappairage_ms < kDesappairageMs) return;
    printf("[bouton] toujours en marche %" PRIu32 " s apres le desappairage : redemarrage\n", kDesappairageMs / 1000);
    if (broche_stable()) esp_restart();
    s_desappairage_ms = maintenant_ms();
````

par :

````cpp
    // redemarre : esp_matter::factory_reset() ne dit pas son echec.
    if (s_redemarrage || t - s_desappairage_ms < kDesappairageMs) return;
    json_pont_annoncer("bouton", true, "[bouton] toujours en marche %" PRIu32 " s apres le desappairage : redemarrage",
                       kDesappairageMs / 1000);
    if (broche_stable()) esp_restart();
    s_desappairage_ms = maintenant_ms();
````

`firmware/main/socle.cpp`, bloc 5 sur 8. Remplacer :

````cpp
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
````

par :

````cpp
      return;
    case Event::Armed:
      json_pont_annoncer("bouton", false, "[bouton] tenu 8 s : relacher pour desappairer (retrait de Matter)");
      return;
    case Event::Cancelled:
      json_pont_annoncer("bouton", false, "[bouton] appui de %" PRIu32 " ms (2 a 8 s) : annule, rien fait", tenu);
      return;
    case Event::Unsure:
      json_pont_annoncer("bouton", false,
                         "[bouton] appui de %" PRIu32 " ms ignore : releves interrompus %" PRIu32
                         " ms, duree incertaine",
                         tenu, s_bouton.lastGapMs());
      return;
    case Event::Dropped:
      json_pont_annoncer("bouton", false, "[bouton] nouvel appui : action en attente abandonnee");
      return;
    case Event::BootReleased:
      json_pont_annoncer("bouton", false, "[bouton] relache : il etait tenu au demarrage, ignore");
      return;
    case Event::Reboot:
      json_pont_annoncer("bouton", false, "[bouton] appui court (%" PRIu32 " ms) : redemarrage", tenu);
      if (!broche_stable()) break;
      esp_restart();
      return;
    case Event::Unpair:
      json_pont_annoncer("bouton", false,
                         "[bouton] appui long (%" PRIu32 " ms) : retrait de toutes les fabriques Matter, puis redemarrage",
                         tenu);
      if (!broche_stable()) break;
      s_desappairage = true;
````

`firmware/main/socle.cpp`, bloc 6 sur 8. Remplacer :

````cpp
  }
  // Rappuye pendant la derniere garde : pas de reset broche basse.
  printf("[bouton] rappuye juste avant le reset : action annulee\n");
  s_bouton.begin(bouton_bas(), maintenant_ms());
}
````

par :

````cpp
  }
  // Rappuye pendant la derniere garde : pas de reset broche basse.
  json_pont_annoncer("bouton", false, "[bouton] rappuye juste avant le reset : action annulee");
  s_bouton.begin(bouton_bas(), maintenant_ms());
}
````

`firmware/main/socle.cpp`, bloc 7 sur 8. Remplacer :

````cpp
    s_led.unreachable(t);
  }
  premier = false;
  const statusled::Frame f = s_led.frame(t);
  s_motif = f.p;
  s_couleur = (uint32_t)f.c.r << 16 | (uint32_t)f.c.g << 8 | f.c.b;
  s_en_test = s_led.testing();
````

par :

````cpp
    s_led.unreachable(t);
  }
  const statusled::Frame f = s_led.frame(t);
  // Changement de motif, ou du test : evenement led du protocole JSON (7.4).
  if (premier || f.p != s_motif || s_led.testing() != s_en_test) {
    json_pont_led(statusled::patternCode(f.p), statusled::patternCode(premier ? f.p : (statusled::Pattern)s_motif),
                  s_led.testing(), f.t);
  }
  premier = false;
  s_motif = f.p;
  s_phase_ms = t - f.t;
  s_couleur = (uint32_t)f.c.r << 16 | (uint32_t)f.c.g << 8 | f.c.b;
  s_en_test = s_led.testing();
````

`firmware/main/socle.cpp`, bloc 8 sur 8. Remplacer :

````cpp

void socle_panne_mesh(bool oui) { s_panne_mesh = oui; }

int socle_commande_led(int argc, char **argv) {
````

par :

````cpp

void socle_panne_mesh(bool oui) { s_panne_mesh = oui; }

void socle_voyant(socle_voyant_t *v) {
  v->motif = statusled::patternCode(s_motif);
  v->test = s_en_test;
  v->depuis_ms = maintenant_ms() - s_phase_ms;
}

int socle_commande_led(int argc, char **argv) {
````

- [ ] **Step 7 : le démarrage : le mode JSON avant le socle.**

`firmware/main/app_main.cpp`, bloc 1 sur 2. Remplacer :

````cpp
#include "config_amaran.h"
#include "console_pont.h"
#include "mesh_amaran.h"
#include "pont_matter.h"
````

par :

````cpp
#include "config_amaran.h"
#include "console_pont.h"
#include "json_pont.h"
#include "mesh_amaran.h"
#include "pont_matter.h"
````

`firmware/main/app_main.cpp`, bloc 2 sur 2. Remplacer :

````cpp
    cfg.cles_presentes = false;
  }
  // Le socle d'abord : la garde du bouton BOOT passe ainsi en dernier avant tout
  // reset, et le voyant montre l'etat des le demarrage.
  if (socle_demarrer() != ESP_OK) ESP_LOGE(TAG, "socle (voyant, bouton) non demarre");
````

par :

````cpp
    cfg.cles_presentes = false;
  }
  // Le mode JSON d'abord : le socle, la console et la tache des lampes lui
  // envoient leurs evenements, et le numero de demarrage se tire avant toute radio.
  if (json_pont_demarrer(&cfg) != ESP_OK) ESP_LOGE(TAG, "mode JSON non demarre");
  // Puis le socle : la garde du bouton BOOT passe ainsi en dernier avant tout
  // reset, et le voyant montre l'etat des le demarrage.
  if (socle_demarrer() != ESP_OK) ESP_LOGE(TAG, "socle (voyant, bouton) non demarre");
````

- [ ] **Step 8 : le pont compile.** `json_pont.cpp` est neuf : `reconfigure` d'abord. L'écoute n'utilise pas `firmware/main` : elle n'a pas à être recompilée.

Run: `export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && (cd firmware && idf.py reconfigure >/dev/null && idf.py build 2>&1 | /usr/bin/grep -E "binary size|Project build complete|warning:|error:" | /usr/bin/grep -vE "esp-idf/|esp-matter/|managed_components/|Bootloader")`
Expected : `amaran_pont.bin binary size 0x1ab330 bytes. Smallest app partition is 0x3e0000 bytes. 0x234cd0 bytes (57%) free.` (à quelques octets près), puis `Project build complete. To flash, run:` ; aucune ligne `warning:` ni `error:`.

- [ ] **Step 9 : les tests natifs restent verts.**

Run: `sh tests/hote/lancer.sh`
Expected: `tests hote : tout est vert`.

> **Amendement (exécution, 05/10)** : la relecture a montré deux défauts, corrigés en un commit à part. (1) linenoise en mode intelligent (sonde réussie, par exemple sous `idf.py monitor`) envoie `ESC[6n` et lit la ligne suivante de l'app comme réponse du curseur : la console reste toujours en mode simple. (2) Un événement ou un ordre perdu faute de place l'était sans trace : les événements perdus comptent dans `json_perdus`, la file d'événements passe à 32, et un ordre que la file des lampes refuse reçoit `erreur` (« file des lampes pleine ») au lieu d'`accepte` ; `docs/PROTOCOLE-JSON.md` le dit.

- [ ] **Step 10 : commit.**

```bash
git add firmware/main
git commit -m "$(printf "Mode JSON du pont : notre tache de console, la tache json, ordres et evenements\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 4: Banc A : le mode JSON sur la carte (Claude et Djoko)

**Files:**
- Modify: `docs/BANC.md` (une section « Plan 3b-1 : banc A », écrite après le banc)

Cette tâche est faite par Claude, avec Djoko : flasher, ouvrir le port, émettre vers les lampes. Aucun sous-agent.

**Interfaces:**
- Consumes : le firmware de la Task 3 ; `outils/console.py` (il envoie chaque étape suivie de CR LF, et journalise tout dans `logs/`, ignoré par git).
- Produces : les faits du banc dans `docs/BANC.md` ; un ruling dans le registre si un point échoue.

Pourquoi : la spec 3b, section 12, met en tête deux risques de la console d'ESP-IDF, levés en lisant ses sources (choix 2 et 3). Ce banc les confirme sur la carte, avant de bâtir l'app.

- [ ] **Step 1 : flasher, avec l'accord de Djoko.** Le port du pont se reconnaît à son `SER=` ; le donner explicitement. Mise à jour sans `erase-flash` (Maison garde tout).

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh >/dev/null && source ~/esp/esp-matter/export.sh >/dev/null && cd firmware && idf.py -p <port du pont> flash
```

- [ ] **Step 2 : la console texte n'a pas changé.**

Run: `python3 outils/console.py --port <port> "help" "mesh" "lampes" "taches" "bonjour"`
Expected : `help` liste `json` ; `mesh pret : oui` et les empreintes ; une ligne par lampe ; `taches` cite `json` et `console` avec leur marge de pile ; `bonjour` répond `Commande inconnue : "bonjour" (help)`, sans la ligne `Command returned non-zero error code` d'avant.

- [ ] **Step 3 : le mode machine, sans écho.**

Run: `python3 outils/console.py --port <port> "id=1 json 1" "@3" "id=2 lampe 1" "@2" "id=3 json ping" "@2" "id=4 json 0" "@1" "mesh"`
Expected, dans le journal :
- `hello` (`base`, `identite`), `config` (`catalogue`, `mesh`, une ligne `lampe` par lampe), `etat` (`pont`, une ligne `lampe` par lampe, `sante`), `compteurs`, `reseau` (`matter`, `thread`), puis `reponse` `id` 1, `fin`, `ok`, avec `bail_s` 30 ;
- aucun écho de `id=2 lampe 1` ; sa `reponse` `debut`, son texte (le détail de la lampe 1), sa `reponse` `fin` `ok` ; un bloc `sante` émis entre les deux porte `"commande":2` ;
- `id=3` : `reponse` avec `bail_s` et `up_s` ;
- `id=4` : `reponse` `ok`, puis `fin` (`cause` `commande`), le texte `json : mode machine coupe`, l'invite ; `mesh` répond ensuite en texte, avec écho.

Contrôle des lignes du journal (aucune ligne abîmée, `n` sans trou, 896 octets au plus) :

```bash
python3 - logs/<journal> <<'EOF'
import json, sys
n = None
for brute in open(sys.argv[1], encoding="utf-8", errors="replace"):
    if "\x1e" not in brute: continue
    l = brute.rstrip("\n").split("\x1e")[-1]
    m = json.loads(l)
    assert len(l.encode()) + 2 <= 896, (m["t"], len(l))
    if n is not None and m["n"] != n + 1: print("trou de n :", n, "->", m["n"])
    n = m["n"]
print("dernier n :", n)
EOF
```

- [ ] **Step 4 : les ordres et leur issue (Djoko présent, une lampe de son choix, la 1 ici).**

Run: `python3 outils/console.py --port <port> "id=1 json 1" "@3" "id=2 lampe 1 niveau 300" "@3" "id=3 lampe 1 niveau 300" "@2" "id=4 lampe 1 niveau 600" "@3" "id=5 json 0"`
Expected : pour 2 et 4, `reponse` `accepte` (`suite` `ordre`, `lampe` 1), puis `ordre` `confirme` avec `ids` [2] (puis [4]), un délai, l'essai, et `led` `livree` ; pour 3, `ordre` `tenu`, `ids` [3]. Djoko voit la lampe passer à 30 %, puis 60 %, et Maison suivre.

- [ ] **Step 5 : un ordre de Maison pendant le mode machine.** `"id=1 json 1" "@20" "id=2 json 0"` ; pendant les 20 s, Djoko allume ou éteint une lampe dans Maison. Expected : un `ordre` sans `id` (`"ids":[]`), puis la ligne `etat` `lampe` qui change.

- [ ] **Step 6 : le bail.** `"id=1 json 1" "@36"` (aucun ping). Expected : vers 30 s, `fin` (`cause` `bail`), puis le texte `json : mode machine coupe (hote muet depuis 30 s)` et l'invite.

- [ ] **Step 7 : les refus.**
- `"id=1 json 1" "@2" "id=2 mesh cles 00 11" "@1"` : la réponse cite `mesh cles` seul ; le texte dit l'usage ; rien n'est enregistré (clés invalides).
- Une ligne de 130 octets avec un `id` : `reponse` `trop_long`, rien n'est exécuté.
- `"id=3 lampe 9 on"` (lampe absente) : `reponse` `usage`.
- `"id=4 json periode 5"` : `reponse` `usage` (bornes dans `msg`).

- [ ] **Step 8 : les marges.** En mode machine, relever dans les blocs `sante` la pile libre de `json` et de `console`, et le tas (`heap_min`) ; en texte, `taches`. Expected : au moins 1 Ko de pile libre pour chacune ; `heap_min` proche de celui du plan 3a (103 Ko à 16 lampes, plus à deux).

- [ ] **Step 9 : consigner.** Ajouter à `docs/BANC.md` une section `## Plan 3b-1 : banc A, mode JSON (<date>)` : les étapes 2 à 8, ce qui a été vu, les marges relevées, et tout écart. Puis commit :

```bash
git add docs/BANC.md
git commit -m "$(printf "Banc A du plan 3b-1 : mode JSON du pont sur la carte\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

Si un point échoue : le noter, ruling dans le registre, correction avant la Task 5 (le reste du plan s'appuie sur ce protocole).

### Task 5: Le projet de l'app, les messages du pont et le tramage (Swift, testé sur le Mac)

**Files:**
- Create: `apps/macos/project.yml`, `apps/macos/Signature.xcconfig`, `apps/macos/.gitignore`
- Create: `apps/macos/AmaranCompagnon/AmaranCompagnon.entitlements`, `apps/macos/AmaranCompagnon/AmaranCompagnonApp.swift` (provisoire)
- Create: `apps/macos/Outils/constellation-a.svg`, `apps/macos/AmaranCompagnon/Ressources/AppIcon.icon/icon.json`, `apps/macos/AmaranCompagnon/Ressources/AppIcon.icon/Assets/constellation-a.png` (produit par `rsvg-convert`)
- Create: `apps/macos/AmaranProtocole/Messages/{Enumerations,Session,Etat,Evenements,MessageCarte}.swift`
- Create: `apps/macos/AmaranProtocole/Tramage/{ClasseurTexte,RecepteurLignes}.swift`, `apps/macos/AmaranProtocole/Interpretation/Appairage.swift`
- Test: `apps/macos/AmaranProtocoleTests/{TramageTests,ExemplesSpecTests,AppairageTests}.swift`, `apps/macos/AmaranCompagnonTests/LancementTests.swift` (provisoire)

**Interfaces:**
- Consumes : `docs/PROTOCOLE-JSON.md` (Task 2) : `ExemplesSpecTests` lit ses lignes `<RS>` et les décode toutes.
- Produces (module `AmaranProtocole`, tout `public`) :
  - les cibles XcodeGen : `AmaranProtocole` (framework), `AmaranCompagnon` (app, produit `Amaran Compagnon.app`), `AmaranProtocoleTests`, `AmaranCompagnonTests` (hébergés par l'app), le schéma `AmaranCompagnon` ;
  - `Octets` (`rs`, `lf`, `cr`, `ctrlU`) ; `RecepteurLignes` (`alimenter(_:) -> [ElementRecu]`, `resynchroniser()`, `signalerPause()`, `remettreCompteursAZero()`, `compteurs`, `tamponMax` 2048, `jsonMax` 1022) ; `ElementRecu` (`machine(LigneMachine)`, `texte(LigneTexte)`, `fragment`, `abimee`, `versionInconnue`, `invalide`, `debordement`) ; `CompteursReception` ;
  - `ClasseurTexte.classer(_:) -> LigneTexte`, `ClasseurTexte.sansANSI(_:)`, `ClasseurTexte.estRefusIdAncienFirmware(_:)` ; `ClasseTexte` (`logIDF`, `annonce`, `demarrage`, `invite`, `commande`) ;
  - `DecodeurMessages.decoder(json:) -> Resultat` (`valide(LigneMachine)`, `abimee`, `versionInconnue`, `invalide`) ; `LigneMachine` (`enveloppe`, `message`, `json`) ; `Enveloppe` (`v`, `t`, `n`, `ms`, `bloc`) ; `MessageCarte`, un cas par message (`helloBase`, `helloIdentite`, `configCatalogue`, `configMesh`, `configLampe`, `etatPont`, `etatLampe`, `etatSante`, `compteursMesh`, `reseauMatter`, `reseauThread`, `battement`, `fin`, `reponse`, `ordre`, `alerte`, `lampe`, `led`, `log`, `inconnu`) et `estPeriodique` ;
  - les messages : `HelloBase` (`ReglagesSession`, `Limites`), `HelloIdentite`, `Battement` (`commande`), `FinSession`, `Reponse` (`id`, `etape`, `cmd`, `ok`, `code`, `msg`, `dureeMs`, `suite`, `lampe`, `bailS`, `upS`), `EtatLu`, `ModeleCatalogue`, `ConfigCatalogue`, `ConfigMesh`, `ConfigLampe`, `BlocPont`, `BlocLampe` (`Maison`, `Consigne`), `BlocSante` (`commande`), `CompteursMesh`, `ReseauMatter`, `ReseauThread`, `EvenementOrdre` (`lampe`, `issue`, `delaiMs`, `essai`, `ids`, `idsPerdus`), `Alerte`, `EvenementLampe`, `ChangementLed`, `MessageLog` ;
  - les énumérations tolérantes (`EnumeTolerante` : une valeur inconnue devient `inconnu`, sans erreur) : `MotifLed`, `EtapeReponse`, `CodeReponse`, `SuiteReponse`, `CauseFin`, `IssueOrdre`, `PhaseOrdre`, `DiagMesh`, `QuoiAlerte`, `QuoiLampe`, `Capacite`, `TypeAppareil`, `NiveauLog` ;
  - `CodeAppairage.lisible(_:)`, `CodeAppairage.chargeValide(_:)`.

Pourquoi : la spec 3b, sections 4 (où vit le code), 6 et 10, et `docs/PROTOCOLE-JSON.md`, sections 2, 4, 5 et 7. Le tramage et le classeur de texte sont ceux de Halo Compagnon : une ligne machine commence par RS ; tout le reste est du texte (journal d'ESP-IDF, annonce, invite, réponse d'une commande). Les messages sont ceux du pont amaran. Le décodage est tolérant : un champ absent est `nil`, une valeur inconnue d'énumération devient `inconnu` ; seule une enveloppe illisible rejette la ligne. `ExemplesSpecTests` décode chaque exemple du document : le firmware (Task 2), le document et l'app ne divergent pas.

L'app de cette tâche est provisoire (une fenêtre vide) : la cible de l'app doit exister pour héberger les tests. Le test `LancementTests` est provisoire lui aussi : une cible de tests sans fichier ne se génère pas. La Task 8 le retire, la Task 9 met les écrans.

- [ ] **Step 1 : le projet.**

`apps/macos/project.yml` (contenu complet) :

````yaml
# Amaran Compagnon (docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) :
# copie adaptee de Halo Compagnon. Ce fichier fait foi : le projet Xcode est genere
# (xcodegen generate) et n'est pas versionne.
name: AmaranCompagnon
options:
  bundleIdPrefix: fr.djoko.amaran
  deploymentTarget:
    macOS: "15.0"
  developmentLanguage: fr
  createIntermediateGroups: true
  generateEmptyDirectories: false
configFiles:
  Debug: Signature.xcconfig
  Release: Signature.xcconfig
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
    GCC_TREAT_WARNINGS_AS_ERRORS: YES
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES
    MACOSX_DEPLOYMENT_TARGET: "15.0"
targets:
  AmaranProtocole:
    type: framework
    platform: macOS
    sources:
      - path: AmaranProtocole
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.amaran.protocole
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        SKIP_INSTALL: YES
        DEFINES_MODULE: YES
  AmaranCompagnon:
    type: application
    platform: macOS
    sources:
      - path: AmaranCompagnon
    dependencies:
      - target: AmaranProtocole
    settings:
      base:
        PRODUCT_NAME: Amaran Compagnon
        PRODUCT_MODULE_NAME: AmaranCompagnon
        PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.amaran.compagnon
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: Amaran Compagnon
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_ENTITLEMENTS: AmaranCompagnon/AmaranCompagnon.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        # ASSETCATALOG_COMPILER_APPICON_NAME : dans Signature.xcconfig, pour que
        # Local.xcconfig puisse choisir l'icone M2 (non versionnee).
  AmaranProtocoleTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: AmaranProtocoleTests
    dependencies:
      - target: AmaranProtocole
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.amaran.protocole.tests
        GENERATE_INFOPLIST_FILE: YES
  AmaranCompagnonTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: AmaranCompagnonTests
    dependencies:
      - target: AmaranCompagnon
      - target: AmaranProtocole
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.djoko.amaran.compagnon.tests
        GENERATE_INFOPLIST_FILE: YES
        # Le produit s'appelle "Amaran Compagnon" (avec une espace), pas comme la cible.
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Amaran Compagnon.app/Contents/MacOS/Amaran Compagnon"
        BUNDLE_LOADER: "$(TEST_HOST)"
schemes:
  AmaranCompagnon:
    build:
      targets:
        AmaranCompagnon: all
        AmaranProtocole: all
        AmaranProtocoleTests: [test]
        AmaranCompagnonTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - AmaranProtocoleTests
        - AmaranCompagnonTests
    archive:
      config: Release
````

`apps/macos/Signature.xcconfig` (contenu complet) :

````
// Signature de l'app et des tests (repris de Halo Compagnon).
// Par defaut : ad hoc (le depot compile partout, sans compte Apple). Pour que le
// trousseau et le dossier d'amaran Desktop autorise tiennent d'une compilation a
// l'autre, signer avec son equipe : creer Local.xcconfig (ignore par git) avec
//   DEVELOPMENT_TEAM = <equipe, 10 caracteres>
//   CODE_SIGN_IDENTITY = Apple Development
// L'equipe : security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject (champ OU).
// Icone : AppIcon (A2, versionnee) ; Local.xcconfig peut la remplacer par une icone
// locale, non versionnee (ASSETCATALOG_COMPILER_APPICON_NAME = AppIconM2).
CODE_SIGN_IDENTITY = -
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM =
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
#include? "Local.xcconfig"
````

`apps/macos/.gitignore` (contenu complet) :

````
# Projet genere par xcodegen (project.yml fait foi)
*.xcodeproj/
*.xcworkspace/
# Produits de compilation
build/
DerivedData/
.build/
*.xcresult
# Fichiers propres a l'utilisateur
xcuserdata/
*.xcuserstate
.swiftpm/
.DS_Store

# Signature propre au poste (equipe Apple Development) : voir Signature.xcconfig
Local.xcconfig
# Icone M2 (le A d'Aputure, marque deposee) : sur le Mac de Djoko seulement (spec 3b, decision 9)
AmaranCompagnon/Ressources/AppIconM2.icon/
````

`apps/macos/AmaranCompagnon/AmaranCompagnon.entitlements` (contenu complet) :

````xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.device.serial</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.files.bookmarks.app-scope</key>
	<true/>
</dict>
</plist>
````

- [ ] **Step 2 : l'icône A2.** Le dépôt porte l'icône libre A2 : une constellation qui trace un A. L'icône M2 (le A d'Aputure) n'y entre jamais (Global Constraints).

`apps/macos/Outils/constellation-a.svg` (contenu complet) :

````xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>
<radialGradient id="fond" cx="290" cy="260" r="900" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#e2404f"/><stop offset=".33" stop-color="#9a1a2c"/><stop offset=".68" stop-color="#330a12"/><stop offset="1" stop-color="#0d0306"/></radialGradient>
<radialGradient id="bleu" cx=".5" cy=".5" r=".5" fx=".34" fy=".3"><stop offset="0" stop-color="#ffffff"/><stop offset=".25" stop-color="#dbe9ff"/><stop offset=".62" stop-color="#8db8ff"/><stop offset="1" stop-color="#4a7fe8"/></radialGradient>
<radialGradient id="chaud" cx=".5" cy=".5" r=".5" fx=".34" fy=".3"><stop offset="0" stop-color="#ffffff"/><stop offset=".25" stop-color="#fff2cf"/><stop offset=".62" stop-color="#ffc76b"/><stop offset="1" stop-color="#ee8a25"/></radialGradient>
<radialGradient id="lueur-bleue"><stop offset="0" stop-color="#6ea8ff" stop-opacity=".55"/><stop offset="1" stop-color="#6ea8ff" stop-opacity="0"/></radialGradient>
<radialGradient id="lueur-chaude"><stop offset="0" stop-color="#ffb052" stop-opacity=".6"/><stop offset="1" stop-color="#ffb052" stop-opacity="0"/></radialGradient>
<radialGradient id="lueur-point"><stop offset="0" stop-color="#ffd79a" stop-opacity=".55"/><stop offset="1" stop-color="#ffd79a" stop-opacity="0"/></radialGradient>
</defs><line x1="369" y1="585" x2="125" y2="610" stroke="#e8a0a8" stroke-opacity=".65" stroke-width="5" stroke-dasharray="1 15" stroke-linecap="round"/><line x1="655" y1="585" x2="905" y2="620" stroke="#e8a0a8" stroke-opacity=".65" stroke-width="5" stroke-dasharray="1 15" stroke-linecap="round"/><line x1="282" y1="818" x2="512" y2="905" stroke="#e8a0a8" stroke-opacity=".65" stroke-width="5" stroke-dasharray="1 15" stroke-linecap="round"/><line x1="742" y1="818" x2="512" y2="905" stroke="#e8a0a8" stroke-opacity=".65" stroke-width="5" stroke-dasharray="1 15" stroke-linecap="round"/><line x1="512" y1="205" x2="175" y2="300" stroke="#e8a0a8" stroke-opacity=".65" stroke-width="5" stroke-dasharray="1 15" stroke-linecap="round"/><line x1="512" y1="205" x2="850" y2="320" stroke="#e8a0a8" stroke-opacity=".65" stroke-width="5" stroke-dasharray="1 15" stroke-linecap="round"/><line x1="512" y1="205" x2="369" y2="585" stroke="#fff1f2" stroke-opacity=".22" stroke-width="36" stroke-linecap="round"/><line x1="512" y1="205" x2="369" y2="585" stroke="#fff1f2" stroke-opacity="0.9" stroke-width="9" stroke-linecap="round"/><line x1="369" y1="585" x2="282" y2="818" stroke="#fff1f2" stroke-opacity=".22" stroke-width="36" stroke-linecap="round"/><line x1="369" y1="585" x2="282" y2="818" stroke="#fff1f2" stroke-opacity="0.9" stroke-width="9" stroke-linecap="round"/><line x1="512" y1="205" x2="655" y2="585" stroke="#fff1f2" stroke-opacity=".22" stroke-width="36" stroke-linecap="round"/><line x1="512" y1="205" x2="655" y2="585" stroke="#fff1f2" stroke-opacity="0.9" stroke-width="9" stroke-linecap="round"/><line x1="655" y1="585" x2="742" y2="818" stroke="#fff1f2" stroke-opacity=".22" stroke-width="36" stroke-linecap="round"/><line x1="655" y1="585" x2="742" y2="818" stroke="#fff1f2" stroke-opacity="0.9" stroke-width="9" stroke-linecap="round"/><line x1="369" y1="585" x2="655" y2="585" stroke="#fff1f2" stroke-opacity=".22" stroke-width="36" stroke-linecap="round"/><line x1="369" y1="585" x2="655" y2="585" stroke="#fff1f2" stroke-opacity="0.9" stroke-width="9" stroke-linecap="round"/><circle cx="175" cy="300" r="44" fill="url(#lueur-point)"/><circle cx="175" cy="300" r="17" fill="#ffd79a"/><circle cx="850" cy="320" r="44" fill="url(#lueur-point)"/><circle cx="850" cy="320" r="17" fill="#ffd79a"/><circle cx="125" cy="610" r="44" fill="url(#lueur-point)"/><circle cx="125" cy="610" r="17" fill="#ffd79a"/><circle cx="905" cy="620" r="44" fill="url(#lueur-point)"/><circle cx="905" cy="620" r="17" fill="#ffd79a"/><circle cx="512" cy="905" r="44" fill="url(#lueur-point)"/><circle cx="512" cy="905" r="17" fill="#ffd79a"/><circle cx="512" cy="455" r="44" fill="url(#lueur-point)"/><circle cx="512" cy="455" r="17" fill="#ffd79a"/><circle cx="369" cy="585" r="97" fill="url(#lueur-chaude)"/><circle cx="369" cy="585" r="46" fill="url(#chaud)"/><circle cx="655" cy="585" r="97" fill="url(#lueur-chaude)"/><circle cx="655" cy="585" r="46" fill="url(#chaud)"/><circle cx="282" cy="818" r="97" fill="url(#lueur-chaude)"/><circle cx="282" cy="818" r="46" fill="url(#chaud)"/><circle cx="742" cy="818" r="97" fill="url(#lueur-chaude)"/><circle cx="742" cy="818" r="46" fill="url(#chaud)"/><circle cx="512" cy="205" r="94" fill="none" stroke="#d6e4ff" stroke-opacity=".5" stroke-width="5"/><circle cx="512" cy="205" r="139" fill="url(#lueur-bleue)"/><circle cx="512" cy="205" r="66" fill="url(#bleu)"/></svg>````

`apps/macos/AmaranCompagnon/Ressources/AppIcon.icon/icon.json` (contenu complet) :

````json
{
  "fill": {
    "linear-gradient": [
      "srgb:0.88627,0.25098,0.30980,1.00000",
      "srgb:0.05098,0.01176,0.02353,1.00000"
    ]
  },
  "groups": [
    {
      "layers": [
        {
          "image-name": "constellation-a.png",
          "name": "constellation-a",
          "glass": false
        }
      ],
      "shadow": {
        "kind": "none",
        "opacity": 0.0
      },
      "translucency": {
        "enabled": false,
        "value": 0.5
      }
    }
  ],
  "supported-platforms": {
    "squares": [
      "macOS"
    ]
  }
}
````

Le calque PNG se produit depuis le SVG (`brew install librsvg` s'il manque `rsvg-convert`) :

```bash
cd apps/macos && mkdir -p AmaranCompagnon/Ressources/AppIcon.icon/Assets && rsvg-convert -w 1024 -h 1024 Outils/constellation-a.svg -o AmaranCompagnon/Ressources/AppIcon.icon/Assets/constellation-a.png && cd ../..
```

Expected : `sips -g pixelWidth -g pixelHeight apps/macos/AmaranCompagnon/Ressources/AppIcon.icon/Assets/constellation-a.png` donne 1024 et 1024.

- [ ] **Step 3 : l'app provisoire et son test.**

`apps/macos/AmaranCompagnon/AmaranCompagnonApp.swift` (contenu complet) :

````swift
// Provisoire (plan 3b-1, Task 5) : la Task 9 met les ecrans.
import SwiftUI

@main
struct AmaranCompagnonApp: App {
    var body: some Scene {
        WindowGroup("Amaran Compagnon") {
            Text("Amaran Compagnon")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
````

`apps/macos/AmaranCompagnonTests/LancementTests.swift` (contenu complet) :

````swift
// Provisoire (plan 3b-1, Task 5) : une cible de tests sans fichier ne se genere pas.
// La Task 8 le remplace par les tests de bout en bout du mode demo.
import Foundation
import Testing

@Test func lAppHebergeLesTests() {
    #expect(Bundle.main.bundleIdentifier == "fr.djoko.amaran.compagnon")
}
````

- [ ] **Step 4 : les messages du pont.** Des structures `Codable`, une par message de `docs/PROTOCOLE-JSON.md` ; les clés JSON sont en `snake_case`, décodées avec `.convertFromSnakeCase` : d'où `part10Min` pour `part_10min`. Les clés d'un dictionnaire ne sont pas converties : `piles` garde les noms des tâches tels quels.

`apps/macos/AmaranProtocole/Messages/Enumerations.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : EnumeTolerante ; les valeurs sont
// celles du pont amaran (docs/PROTOCOLE-JSON.md).
import Foundation

/// Enumeration du protocole qui range une valeur inconnue sous `inconnu`
/// sans echouer (section 8 : ajouts additifs dans une meme `v`).
public protocol EnumeTolerante: RawRepresentable, Codable, Sendable, Hashable, CaseIterable
where RawValue == String {
    static var inconnu: Self { get }
}

extension EnumeTolerante {
    public init(from decoder: any Decoder) throws {
        let conteneur = try decoder.singleValueContainer()
        let brut = try conteneur.decode(String.self)
        self = Self(rawValue: brut) ?? Self.inconnu
    }

    public func encode(to encoder: any Encoder) throws {
        var conteneur = encoder.singleValueContainer()
        try conteneur.encode(rawValue)
    }
}

/// Motif du voyant (7.4), repris du pont Halo.
public enum MotifLed: String, EnumeTolerante {
    case identification
    case desappairage
    case redemarrage
    case injoignable
    /// Ici : Bluetooth Mesh inoperant.
    case panneRadio = "panne_radio"
    case livree
    case nonAppaire = "non_appaire"
    case horsReseau = "hors_reseau"
    case operationnel
    case inconnu
}

/// `reponse.etape`.
public enum EtapeReponse: String, EnumeTolerante {
    case debut, fin, inconnu
}

/// `reponse.code` (6.3).
public enum CodeReponse: String, EnumeTolerante {
    case ok, accepte
    case enCours = "en_cours"
    case erreur, usage
    case commandeInconnue = "inconnue"
    case tropLong = "trop_long"
    case cadence
    case inconnu
}

/// `reponse.suite`.
public enum SuiteReponse: String, EnumeTolerante {
    case ordre, aucune, inconnu
}

/// `fin.cause`.
public enum CauseFin: String, EnumeTolerante {
    case commande, bail, inconnu
}

/// `ordre.issue` (7.1).
public enum IssueOrdre: String, EnumeTolerante {
    case confirme, abandon, tenu, inconnu
}

/// `etat.lampe.consigne.phase`.
public enum PhaseOrdre: String, EnumeTolerante {
    case repos, trames, attente, inconnu
}

/// Cause probable d'un Bluetooth Mesh inoperant (`etat.pont.mesh.diag`, `alerte.diag`).
public enum DiagMesh: String, EnumeTolerante {
    case ok
    case clesAbsentes = "cles_absentes"
    case pasEntre = "pas_entre"
    case clesPerimees = "cles_perimees"
    case ivFaux = "iv_faux"
    case inconnu
}

/// `alerte.quoi` (7.2).
public enum QuoiAlerte: String, EnumeTolerante {
    case releves, mesh, inconnu
}

/// `lampe.quoi` (7.3).
public enum QuoiLampe: String, EnumeTolerante {
    case entree, masquee, remise, echec, inconnu
}

/// Capacites d'un modele (`config.catalogue`, `config.lampe`).
public enum Capacite: String, EnumeTolerante {
    case intensite, cct, couleur, inconnu
}

/// Type d'appareil Matter d'un modele.
public enum TypeAppareil: String, EnumeTolerante {
    case variable, temperature, couleur, inconnu
}

/// `log.niv`.
public enum NiveauLog: String, EnumeTolerante {
    case notice, alerte, inconnu
}
````

`apps/macos/AmaranProtocole/Messages/Session.swift` (contenu complet) :

````swift
// Messages de session du pont amaran (docs/PROTOCOLE-JSON.md 5.1, 5.6, 6.3), sur le
// modele de ceux de Halo Compagnon (commit e114cd5). Tout champ est facultatif,
// sauf ceux sans lesquels le message ne sert a rien (section 8).
import Foundation

// MARK: - hello (5.1)

/// `hello`, bloc `base`.
public struct HelloBase: Codable, Sendable, Equatable {
    public struct ReglagesSession: Codable, Sendable, Equatable {
        public var periodeMs: Int?
        public var lampesMs: Int?
        public var compteursMs: Int?
        public var reseauMs: Int?
        public var bailS: Int?
        public var log: Bool?

        public init(periodeMs: Int? = nil, lampesMs: Int? = nil, compteursMs: Int? = nil, reseauMs: Int? = nil,
                    bailS: Int? = nil, log: Bool? = nil) {
            self.periodeMs = periodeMs
            self.lampesMs = lampesMs
            self.compteursMs = compteursMs
            self.reseauMs = reseauMs
            self.bailS = bailS
            self.log = log
        }
    }

    public struct Limites: Codable, Sendable, Equatable {
        public var ligneMax: Int?
        public var cmdMax: Int?
    }

    public var rev: Int?
    public var fw: String?
    public var date: String?
    public var heure: String?
    public var idf: String?
    public var puce: String?
    public var boot: String?
    public var reset: String?
    public var resetN: Int?
    public var upS: Int?
    public var session: ReglagesSession?
    public var limites: Limites?
}

/// `hello`, bloc `identite`.
public struct HelloIdentite: Codable, Sendable, Equatable {
    public struct Identite: Codable, Sendable, Equatable {
        public var fabricant: String?
        public var produit: String?
        public var serie: String?
        public var nom: String?
    }

    public var boot: String?
    public var mac: String?
    public var id: Identite?
    public var caps: [String]?
}

// MARK: - hb, fin (5.6)

public struct Battement: Codable, Sendable, Equatable {
    public var boot: String?
    public var upS: Int?
    public var jsonPerdus: Int?
    /// Id de la commande de la console en cours (6.2).
    public var commande: Int?
}

public struct FinSession: Codable, Sendable, Equatable {
    public var cause: CauseFin?
}

// MARK: - reponse (6.3)

public struct Reponse: Codable, Sendable, Equatable {
    public var id: Int
    public var etape: EtapeReponse
    public var cmd: String?
    public var ok: Bool
    public var code: CodeReponse
    public var msg: String?
    public var dureeMs: Int?
    public var suite: SuiteReponse?
    /// Ordre de lampe : son numero (1 a 16).
    public var lampe: Int?
    public var bailS: Int?
    public var upS: Int?

    public init(id: Int, etape: EtapeReponse, cmd: String? = nil, ok: Bool, code: CodeReponse, msg: String? = nil,
                dureeMs: Int? = nil, suite: SuiteReponse? = nil, lampe: Int? = nil, bailS: Int? = nil, upS: Int? = nil) {
        self.id = id
        self.etape = etape
        self.cmd = cmd
        self.ok = ok
        self.code = code
        self.msg = msg
        self.dureeMs = dureeMs
        self.suite = suite
        self.lampe = lampe
        self.bailS = bailS
        self.upS = upS
    }
}
````

`apps/macos/AmaranProtocole/Messages/Etat.swift` (contenu complet) :

````swift
// Messages periodiques du pont amaran (docs/PROTOCOLE-JSON.md 5.2 a 5.5) : config,
// etat, compteurs, reseau. Tout champ est facultatif, sauf le numero d'une lampe.
import Foundation

/// Etat d'une lampe : marche et intensite (0 a 1000, au dixieme de pour cent).
public struct EtatLu: Codable, Sendable, Equatable, Hashable {
    public var marche: Bool?
    public var intensite: Int?

    public init(marche: Bool? = nil, intensite: Int? = nil) {
        self.marche = marche
        self.intensite = intensite
    }

    /// En marche a l'intensite 0 : la lampe n'eclaire pas, Maison la montre eteinte.
    public var noire: Bool { marche == true && intensite == 0 }
}

// MARK: - config (5.2)

/// Un modele du catalogue du firmware.
public struct ModeleCatalogue: Codable, Sendable, Equatable {
    public struct PlageCCT: Codable, Sendable, Equatable {
        public var min: Int?
        public var max: Int?
    }

    /// Code produit Sidus ; absent pour le repli.
    public var code: Int?
    public var nom: String?
    public var capacites: [Capacite]?
    public var type: TypeAppareil?
    public var cctK: PlageCCT?
}

/// `config`, bloc `catalogue`.
public struct ConfigCatalogue: Codable, Sendable, Equatable {
    public var modeles: [ModeleCatalogue]?
    public var repli: ModeleCatalogue?
}

/// `config`, bloc `mesh` : cles en service, adresse, et en-tete de la liste.
public struct ConfigMesh: Codable, Sendable, Equatable {
    public struct Empreintes: Codable, Sendable, Equatable {
        public var reseau: String?
        public var application: String?
    }

    public struct Balayage: Codable, Sendable, Equatable {
        public var fenetreMs: Int?
        public var intervalleMs: Int?
    }

    public var cles: Bool?
    public var empreintes: Empreintes?
    public var adresse: String?
    public var ivNvs: Int?
    public var balayage: Balayage?
    public var lampes: Int?
    public var capacite: Int?
    public var releveMs: Int?
    public var groupe: String?
}

/// `config`, bloc `lampe` : l'identite d'une lampe de la liste.
public struct ConfigLampe: Codable, Sendable, Equatable {
    public var lampe: Int
    public var adresse: String?
    public var mac: String?
    public var nom: String?
    public var code: Int?
    public var modele: String?
    public var catalogue: Bool?
    public var capacites: [Capacite]?
    public var type: TypeAppareil?
}

// MARK: - etat (5.3)

/// `etat`, bloc `pont`.
public struct BlocPont: Codable, Sendable, Equatable {
    public struct Mesh: Codable, Sendable, Equatable {
        public var pret: Bool?
        public var diag: DiagMesh?
    }

    public struct Ordres: Codable, Sendable, Equatable {
        public var total: Int?
        public var confirmes: Int?
        public var abandons: Int?
        public var tenus: Int?
        public var delaiTotalMs: Int?
        public var delaiMaxMs: Int?
        public var lents: Int?

        /// Delai moyen d'un ordre confirme.
        public var delaiMoyenMs: Int? {
            guard let c = confirmes, c > 0, let t = delaiTotalMs else { return nil }
            return t / c
        }
    }

    public var boot: String?
    public var upS: Int?
    public var mesh: Mesh?
    public var ordres: Ordres?
    public var releves: Int?
    public var trames: Int?
}

/// `etat`, bloc `lampe` : une ligne par lampe.
public struct BlocLampe: Codable, Sendable, Equatable {
    public struct Maison: Codable, Sendable, Equatable {
        public var endpoint: Int?
        public var vue: Bool?
        public var masquee: Bool?
    }

    public struct Consigne: Codable, Sendable, Equatable {
        public var marche: Bool?
        public var intensite: Int?
        public var phase: PhaseOrdre?
        public var essai: Int?
    }

    public var lampe: Int
    public var maison: Maison?
    public var entendue: Bool?
    public var lue: EtatLu?
    public var joignable: Bool?
    public var reponseMs: UInt32?
    public var consigne: Consigne?
    public var repondues: Int?
    /// Part des relectures repondues sur 10 min (`part_10min`), en pour cent.
    public var part10Min: Int?
    public var alerte: Bool?
}

/// `etat`, bloc `sante`.
public struct BlocSante: Codable, Sendable, Equatable {
    public struct Led: Codable, Sendable, Equatable {
        public var motif: MotifLed?
        public var test: Bool?
        public var depuisMs: Int?
    }

    public struct Matter: Codable, Sendable, Equatable {
        public var enService: Bool?
        public var thread: Bool?
        public var identifie: Bool?
        public var ble: Bool?
    }

    public struct Systeme: Codable, Sendable, Equatable {
        public var heap: Int?
        public var heapMin: Int?
        public var heapBloc: Int?
        /// Octets de pile jamais utilises, par tache ; nil : tache absente.
        public var piles: [String: Int?]?
        public var jsonPerdus: Int?
        public var jsonTropLongs: Int?
        public var rejets: Int?
    }

    public var boot: String?
    public var upS: Int?
    /// Id de la commande de la console en cours (6.2).
    public var commande: Int?
    public var led: Led?
    public var matter: Matter?
    public var sys: Systeme?
}

// MARK: - compteurs (5.4)

/// `compteurs`, bloc `mesh` : cumulatifs depuis le demarrage.
public struct CompteursMesh: Codable, Sendable, Equatable {
    public struct Balises: Codable, Sendable, Equatable {
        public struct Derniere: Codable, Sendable, Equatable {
            public var iv: Int?
            public var drapeaux: Int?
            public var ms: UInt32?
        }

        public var notres: Int?
        public var autres: Int?
        public var fausses: Int?
        public var derniere: Derniere?
    }

    public var annonces: Int?
    public var nidReconnu: Int?
    public var nidInconnu: Int?
    public var netmicFaux: Int?
    public var accesDechiffres: Int?
    public var etatsLampes: Int?
    public var doublons: Int?
    public var balises: Balises?
    public var emis: Int?
    public var echecsEmission: Int?
    public var filePleine: Int?
    public var iv: Int?
    public var seq: Int?
    public var plancher: Int?
}

// MARK: - reseau (5.5)

/// `reseau`, bloc `matter`.
public struct ReseauMatter: Codable, Sendable, Equatable {
    public struct Abonnements: Codable, Sendable, Equatable {
        public var demandes: Int?
        public var plafonnes: Int?
        public var etablis: Int?
        public var termines: Int?
        public var plafondS: Int?

        /// Abonnements actifs, a peu pres : etablis moins termines.
        public var actifs: Int? {
            guard let e = etablis, let t = termines else { return nil }
            return max(0, e - t)
        }
    }

    public var demarre: Bool?
    public var fabriques: Int?
    public var ble: Bool?
    public var identifie: Bool?
    public var abonnements: Abonnements?
    public var codeManuel: String?
    public var qr: String?
}

/// `reseau`, bloc `thread`.
public struct ReseauThread: Codable, Sendable, Equatable {
    public var role: String?
    public var attache: Bool?
}
````

`apps/macos/AmaranProtocole/Messages/Evenements.swift` (contenu complet) :

````swift
// Evenements du pont amaran (docs/PROTOCOLE-JSON.md, section 7) : des indices ;
// la verite est dans l'etat periodique.
import Foundation

/// `ordre` (7.1) : fin d'un ordre de lampe.
public struct EvenementOrdre: Codable, Sendable, Equatable {
    public var lampe: Int
    public var issue: IssueOrdre?
    public var delaiMs: Int?
    public var essai: Int?
    /// Id des ordres de l'app couverts (vide : ordre de Maison ou de la console sans id).
    public var ids: [Int]?
    public var idsPerdus: Int?
}

/// `alerte` (7.2) : relectures manquees d'une lampe, ou Bluetooth Mesh inoperant.
public struct Alerte: Codable, Sendable, Equatable {
    public var quoi: QuoiAlerte?
    public var lampe: Int?
    public var manque: Bool?
    public var part: Int?
    public var diag: DiagMesh?
}

/// `lampe` (7.3) : place d'une lampe dans Maison.
public struct EvenementLampe: Codable, Sendable, Equatable {
    public var lampe: Int
    public var quoi: QuoiLampe?
    public var endpoint: Int?
}

/// `led` (7.4).
public struct ChangementLed: Codable, Sendable, Equatable {
    public var motif: MotifLed?
    public var avant: MotifLed?
    public var test: Bool?
    public var depuisMs: Int?
}

/// `log` (7.5).
public struct MessageLog: Codable, Sendable, Equatable {
    public var src: String?
    public var niv: NiveauLog?
    public var txt: String?
    public var sautes: Int?
}
````

`apps/macos/AmaranProtocole/Messages/MessageCarte.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : enveloppe et decodeur ; les messages
// sont ceux du pont amaran (docs/PROTOCOLE-JSON.md, sections 5 et 7).
import Foundation

/// Champs communs a toutes les lignes machine (section 4).
public struct Enveloppe: Codable, Sendable, Equatable {
    /// Version majeure du protocole.
    public var v: Int
    /// Type de message.
    public var t: String
    /// Numero de ligne produite depuis le demarrage.
    public var n: UInt32
    /// Millisecondes depuis le demarrage, a la production de la ligne.
    public var ms: UInt32?
    /// Partie d'un message en blocs.
    public var bloc: String?
}

/// Un message du pont, decode selon (`t`, `bloc`).
public enum MessageCarte: Sendable, Equatable {
    case helloBase(HelloBase)
    case helloIdentite(HelloIdentite)
    case configCatalogue(ConfigCatalogue)
    case configMesh(ConfigMesh)
    case configLampe(ConfigLampe)
    case etatPont(BlocPont)
    case etatLampe(BlocLampe)
    case etatSante(BlocSante)
    case compteursMesh(CompteursMesh)
    case reseauMatter(ReseauMatter)
    case reseauThread(ReseauThread)
    case battement(Battement)
    case fin(FinSession)
    case reponse(Reponse)
    case ordre(EvenementOrdre)
    case alerte(Alerte)
    case lampe(EvenementLampe)
    case led(ChangementLed)
    case log(MessageLog)
    /// Type ou bloc inconnu : ignore (section 8).
    case inconnu

    /// Vrai pour les messages periodiques (instantanes), faux pour les evenements.
    public var estPeriodique: Bool {
        switch self {
        case .helloBase, .helloIdentite, .configCatalogue, .configMesh, .configLampe, .etatPont, .etatLampe,
             .etatSante, .compteursMesh, .reseauMatter, .reseauThread, .battement:
            true
        default:
            false
        }
    }
}

/// Ligne machine valide et decodee.
public struct LigneMachine: Sendable, Equatable {
    public var enveloppe: Enveloppe
    public var message: MessageCarte
    /// Le JSON tel que recu, pour le journal et l'inspection.
    public var json: String

    public init(enveloppe: Enveloppe, message: MessageCarte, json: String) {
        self.enveloppe = enveloppe
        self.message = message
        self.json = json
    }
}

/// Decodage d'un objet JSON du pont : enveloppe d'abord, puis un `Codable`
/// par (`t`, `bloc`) (section 8).
public enum DecodeurMessages {
    /// Versions majeures gerees par l'app.
    public static let versionsGerees: Set<Int> = [1]

    public enum Resultat: Sendable, Equatable {
        case valide(LigneMachine)
        /// Enveloppe absente ou mal typee : ligne abimee.
        case abimee(String)
        case versionInconnue(v: Int, t: String)
        /// Champ obligatoire absent ou mal type dans le corps.
        case invalide(t: String, raison: String)
    }

    private static func decodeur() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func decoder(json: Data) -> Resultat {
        let d = decodeur()
        let enveloppe: Enveloppe
        do {
            enveloppe = try d.decode(Enveloppe.self, from: json)
        } catch {
            return .abimee("enveloppe : \(Self.raison(error))")
        }
        guard versionsGerees.contains(enveloppe.v) else {
            return .versionInconnue(v: enveloppe.v, t: enveloppe.t)
        }
        let texte = String(decoding: json, as: UTF8.self)
        do {
            let message = try corps(enveloppe: enveloppe, json: json, decodeur: d)
            return .valide(LigneMachine(enveloppe: enveloppe, message: message, json: texte))
        } catch {
            return .invalide(t: enveloppe.t, raison: Self.raison(error))
        }
    }

    private static func corps(enveloppe e: Enveloppe, json: Data, decodeur d: JSONDecoder) throws -> MessageCarte {
        switch (e.t, e.bloc) {
        case ("hello", "base"): return .helloBase(try d.decode(HelloBase.self, from: json))
        case ("hello", "identite"): return .helloIdentite(try d.decode(HelloIdentite.self, from: json))
        case ("config", "catalogue"): return .configCatalogue(try d.decode(ConfigCatalogue.self, from: json))
        case ("config", "mesh"): return .configMesh(try d.decode(ConfigMesh.self, from: json))
        case ("config", "lampe"): return .configLampe(try d.decode(ConfigLampe.self, from: json))
        case ("etat", "pont"): return .etatPont(try d.decode(BlocPont.self, from: json))
        case ("etat", "lampe"): return .etatLampe(try d.decode(BlocLampe.self, from: json))
        case ("etat", "sante"): return .etatSante(try d.decode(BlocSante.self, from: json))
        case ("compteurs", "mesh"): return .compteursMesh(try d.decode(CompteursMesh.self, from: json))
        case ("reseau", "matter"): return .reseauMatter(try d.decode(ReseauMatter.self, from: json))
        case ("reseau", "thread"): return .reseauThread(try d.decode(ReseauThread.self, from: json))
        case ("hb", _): return .battement(try d.decode(Battement.self, from: json))
        case ("fin", _): return .fin(try d.decode(FinSession.self, from: json))
        case ("reponse", _): return .reponse(try d.decode(Reponse.self, from: json))
        case ("ordre", _): return .ordre(try d.decode(EvenementOrdre.self, from: json))
        case ("alerte", _): return .alerte(try d.decode(Alerte.self, from: json))
        case ("lampe", _): return .lampe(try d.decode(EvenementLampe.self, from: json))
        case ("led", _): return .led(try d.decode(ChangementLed.self, from: json))
        case ("log", _): return .log(try d.decode(MessageLog.self, from: json))
        default: return .inconnu
        }
    }

    static func raison(_ erreur: any Error) -> String {
        guard let e = erreur as? DecodingError else { return String(describing: erreur) }
        func chemin(_ c: [any CodingKey]) -> String {
            c.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let cle, let ctx):
            let base = chemin(ctx.codingPath)
            let champ = (base.isEmpty ? "" : base + ".") + cle.stringValue
            return "champ absent : \(champ)"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "champ mal typé : \(chemin(ctx.codingPath))"
        case .dataCorrupted(let ctx):
            return "JSON invalide \(chemin(ctx.codingPath))"
        @unknown default:
            return "décodage impossible"
        }
    }
}
````

- [ ] **Step 5 : les tests du tramage, des exemples et des codes d'appairage.**

`apps/macos/AmaranProtocoleTests/TramageTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : textes et lignes du pont amaran.
import Foundation
import Testing
@testable import AmaranProtocole

/// Octets d'une ligne machine : RS + JSON + LF.
func ligneMachine(_ json: String) -> [UInt8] {
    [Octets.rs] + Array(json.utf8) + [Octets.lf]
}

let exempleHb = #"{"v":1,"t":"hb","n":641,"ms":202000,"boot":"3FA2C901","up_s":202,"json_perdus":0,"commande":null}"#

@Suite("Tramage (2.4)")
struct TramageTests {
    @Test func ligneMachineSimple() throws {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(exempleHb))
        #expect(e.count == 1)
        guard case .machine(let l) = e.first else { Issue.record("pas une ligne machine"); return }
        #expect(l.enveloppe.t == "hb")
        #expect(l.enveloppe.n == 641)
        #expect(l.enveloppe.ms == 202000)
        guard case .battement(let b) = l.message else { Issue.record("pas un hb"); return }
        #expect(b.boot == "3FA2C901")
        #expect(b.upS == 202)
        #expect(r.compteurs.lignesMachine == 1)
    }

    @Test func octetParOctet() {
        var r = RecepteurLignes()
        var sortie: [ElementRecu] = []
        for o in ligneMachine(exempleHb) + Array("texte humain\r\n".utf8) {
            sortie += r.alimenter([o])
        }
        #expect(sortie.count == 2)
        if case .machine = sortie[0] {} else { Issue.record("attendu machine") }
        #expect(sortie[1] == .texte(LigneTexte(texte: "texte humain", classe: .commande)))
    }

    @Test func texteAvantRSEtCRFinal() {
        var r = RecepteurLignes()
        let octets = Array("amaran> ".utf8) + ligneMachine(exempleHb).dropLast() + [Octets.cr, Octets.lf]
        let e = r.alimenter(octets)
        #expect(e.count == 2)
        #expect(e[0] == .texte(LigneTexte(texte: "amaran> ", classe: .invite)))
        if case .machine = e[1] {} else { Issue.record("attendu machine apres l'invite") }
    }

    @Test func dernierRSDeLaLigne() {
        // Ligne machine coupee sans LF, suivie d'une ligne complete : le dernier RS gagne.
        var r = RecepteurLignes()
        let coupee = Array("amaran> ".utf8) + [Octets.rs] + Array(#"{"v":1,"t":"etat","n":3,"ms"#.utf8)
        let e = r.alimenter(coupee + ligneMachine(exempleHb))
        #expect(e.count == 3)
        #expect(e[0] == .texte(LigneTexte(texte: "amaran> ", classe: .invite)))
        if case .abimee = e[1] {} else { Issue.record("le debut coupe est une ligne abimee, pas du texte") }
        if case .machine(let l) = e[2] { #expect(l.enveloppe.t == "hb") } else { Issue.record("attendu hb") }
        #expect(r.compteurs.lignesAbimees == 1)
    }

    @Test func logIDFAuMilieuPuisFragment() {
        // Un journal d'ESP-IDF coupe une ligne machine (2.1) : la ligne
        // est abimee, sa suite est un fragment, jamais du texte de commande.
        var r = RecepteurLignes()
        let debut = [Octets.rs] + Array(#"{"v":1,"t":"hb","n":641,"ms":2020"#.utf8)
        let log = Array("E (48213) chip[DL]: rafale\n".utf8)
        let suite = Array(#"00,"boot":"3FA2C901","up_s":202,"json_perdus":0,"commande":null}"#.utf8) + [Octets.lf]
        let e = r.alimenter(debut + log + suite)
        #expect(e.count == 2)
        if case .abimee = e[0] {} else { Issue.record("attendu abimee, obtenu \(e[0])") }
        if case .fragment = e[1] {} else { Issue.record("attendu fragment, obtenu \(e[1])") }
        #expect(r.compteurs.lignesAbimees == 1)
        #expect(r.compteurs.fragments == 1)
        #expect(r.compteurs.lignesTexte == 0)
    }

    @Test func fragmentApresPause() {
        var r = RecepteurLignes()
        _ = r.alimenter(Array("ligne\n".utf8))
        r.signalerPause()
        let e = r.alimenter(Array(#"1,"json_perdus":0}"#.utf8) + [Octets.lf])
        if case .fragment = e.first {} else { Issue.record("attendu fragment apres une pause") }
        // Une ligne en '}' qui ne suit ni pause ni ligne abimee reste du texte.
        let t = r.alimenter(Array("bloc {x}\n".utf8))
        if case .texte = t.first {} else { Issue.record("attendu texte") }
    }

    @Test func resynchronisationALOuverture() {
        var r = RecepteurLignes()
        r.resynchroniser()
        let e = r.alimenter(Array(#"reste,"up_s":3}"#.utf8) + [Octets.lf] + ligneMachine(exempleHb))
        #expect(e.count == 1)
        if case .machine = e.first {} else { Issue.record("le reste avant le 1er LF doit etre jete") }
    }

    @Test func debordementSansLF() {
        var r = RecepteurLignes()
        let e = r.alimenter([UInt8](repeating: UInt8(ascii: "x"), count: 2049))
        #expect(e.count == 1)
        if case .debordement(let t) = e.first { #expect(t.count == 2049) } else { Issue.record("attendu debordement") }
        #expect(r.compteurs.debordements == 1)
        // La suite repart proprement.
        let s = r.alimenter(ligneMachine(exempleHb))
        if case .machine = s.first {} else { Issue.record("attendu machine apres debordement") }
    }

    @Test func lignesAbimees() {
        var r = RecepteurLignes()
        let cas = [
            #"{"t":"hb","v":1,"n":1}"#,             // ne commence pas par {"v":
            #"{"v":1,"t":"hb","n":1"#,              // ne finit pas par }
            #"{"v":1,"t":"hb","n":1,,}"#,           // JSON invalide
            #"{"v":1,"t":"hb"}"#,                   // n absent
            #"{"v":"1","t":"hb","n":1}"#,           // v mal type
            #"{"v":1,"t":"hb","n":-4}"#,            // n hors 0..4294967295
            #"{"v":1,"t":"hb","n":4294967296}"#,
            "{\"v\":1,\"t\":\"hb\",\"n\":1,\"x\":\"" + String(repeating: "a", count: 1010) + "\"}",
        ]
        for c in cas {
            let e = r.alimenter(ligneMachine(c))
            if case .abimee = e.first {} else { Issue.record("attendu abimee pour \(c.prefix(40)) : \(e)") }
        }
        #expect(r.compteurs.lignesAbimees == cas.count)
        #expect(r.compteurs.lignesTexte == 0)
    }

    @Test func versionEtTypeInconnus() {
        var r = RecepteurLignes()
        let v2 = r.alimenter(ligneMachine(#"{"v":2,"t":"hello","n":0,"ms":1,"bloc":"base"}"#))
        #expect(v2 == [.versionInconnue(v: 2, t: "hello")])
        let t = r.alimenter(ligneMachine(#"{"v":1,"t":"futur","n":1,"ms":2,"champ":[1,2]}"#))
        if case .machine(let l) = t.first { #expect(l.message == .inconnu) } else { Issue.record("attendu machine") }
        #expect(r.compteurs.versionsInconnues == 1)
        #expect(r.compteurs.typesInconnus == 1)
    }

    @Test func champsEtValeursInconnusIgnores() {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(
            #"{"v":1,"t":"led","n":5,"ms":9,"motif":"violet_disco","avant":"operationnel","test":false,"nouveau":{"a":1}}"#))
        guard case .machine(let l) = e.first, case .led(let led) = l.message else {
            Issue.record("attendu led : \(e)"); return
        }
        #expect(led.motif == .inconnu)
        #expect(led.avant == .operationnel)
    }

    @Test func champObligatoireAbsent() {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(#"{"v":1,"t":"reponse","n":5,"ms":9,"etape":"fin","ok":true,"code":"ok"}"#))
        if case .invalide(let t, _) = e.first { #expect(t == "reponse") } else { Issue.record("attendu invalide : \(e)") }
        #expect(r.compteurs.messagesInvalides == 1)
    }

    @Test func texteUTF8AvecRemplacement() {
        var r = RecepteurLignes()
        let e = r.alimenter([0x61, 0xFF, 0x62, Octets.lf])
        if case .texte(let t) = e.first { #expect(t.texte == "a\u{FFFD}b") } else { Issue.record("attendu texte") }
    }

    /// Les noms des lampes passent en UTF-8 dans les lignes machine (2.2).
    @Test func nomEnUTF8() {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(
            #"{"v":1,"t":"config","n":5,"ms":83562,"bloc":"lampe","lampe":2,"nom":"Lumière fenêtre"}"#))
        guard case .machine(let l) = e.first, case .configLampe(let c) = l.message else {
            Issue.record("attendu config lampe : \(e)"); return
        }
        #expect(c.nom == "Lumière fenêtre")
    }
}

@Suite("Classement du texte (2.5)")
struct ClasseurTexteTests {
    @Test func classes() {
        #expect(ClasseurTexte.classer("E (48213) chip[DL]: rafale").classe == .logIDF)
        #expect(ClasseurTexte.classer("E (48213) chip[DL]: rafale").niveau == "E")
        #expect(ClasseurTexte.classer("W (1) tag: x").niveau == "W")
        #expect(ClasseurTexte.classer("[lampes] lampe 3 entendue : dans Maison (EP4)").classe == .annonce)
        #expect(ClasseurTexte.classer("[mesh] de nouveau operationnel").classe == .annonce)
        #expect(ClasseurTexte.classer("[bouton] tenu 8 s : relacher pour desappairer (retrait de Matter)").classe == .annonce)
        #expect(ClasseurTexte.classer("!! Bluetooth Mesh inoperant : cles absentes").classe == .annonce)
        #expect(ClasseurTexte.classer("ESP-ROM:esp32c6-20220919").classe == .demarrage)
        #expect(ClasseurTexte.classer("rst:0xc (SW_CPU),boot:0x6c (SPI_FAST_FLASH_BOOT)").classe == .demarrage)
        #expect(ClasseurTexte.classer("amaran>").classe == .invite)
        #expect(ClasseurTexte.classer("amaran> ").classe == .invite)
        #expect(ClasseurTexte.classer("mesh pret : oui").classe == .commande)
        #expect(ClasseurTexte.classer("E (x) tag: y").classe == .commande)
    }

    @Test func sequencesANSI() {
        let l = ClasseurTexte.classer("\u{1B}[0;31mE (5) wifi: echec\u{1B}[0m")
        #expect(l.texte == "E (5) wifi: echec")
        #expect(l.classe == .logIDF)
    }

    @Test func ancienFirmware() {
        // La REPL d'ESP-IDF d'avant le plan 3b lit `id=1` comme le nom d'une commande.
        #expect(ClasseurTexte.estRefusIdAncienFirmware("Unrecognized command"))
        #expect(ClasseurTexte.estRefusIdAncienFirmware("Unrecognized command "))
        // Le firmware du plan 3b ne l'ecrit jamais : sa console dit autre chose.
        #expect(!ClasseurTexte.estRefusIdAncienFirmware(#"Commande inconnue : "bonjour" (help)"#))
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

@Suite("Exemples de la specification (section 9)")
struct ExemplesSpecTests {
    @Test func toutesLesLignesSontLues() throws {
        #expect(try ExemplesSpec.lignes().count == 47)
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
        #expect(h.session?.lampesMs == 10000)
        #expect(h.session?.bailS == 30)
        #expect(h.limites?.cmdMax == 127)

        guard case .helloIdentite(let i) = l[1].message else { Issue.record("identite"); return }
        #expect(i.id?.serie == "AMARAN-F0F5BD0A0B0C")
        #expect(i.caps?.contains("ordres") == true)

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
}
````

`apps/macos/AmaranProtocoleTests/AppairageTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5).
import Testing
@testable import AmaranProtocole

/// Codes d'appairage Matter du pont : groupes comme dans Maison, charge du QR verifiee.
struct AppairageTests {
    @Test func codeManuelGroupe() {
        #expect(CodeAppairage.lisible("34970112332") == "3497-011-2332")
        #expect(CodeAppairage.lisible("749701123365521327") == "749701123365521327", "18 chiffres : tel quel")
        #expect(CodeAppairage.lisible("749701123365521327694") == "7497-011-2336-55213-27694")
        #expect(CodeAppairage.lisible("3497-011-2332") == "3497-011-2332", "deja groupe : tel quel")
        #expect(CodeAppairage.lisible("") == "")
        #expect(CodeAppairage.lisible("3497011233٢") == "3497011233٢", "chiffre non ASCII : tel quel")
    }

    @Test func chargeDuQR() {
        #expect(CodeAppairage.chargeValide("MT:Y.K9042C00KA0648G00"))
        #expect(!CodeAppairage.chargeValide("MT:"))
        #expect(!CodeAppairage.chargeValide("mt:Y.K9042C00KA0648G00"))
        #expect(!CodeAppairage.chargeValide("MT:y.k9042"), "base38 : majuscules seulement")
        #expect(!CodeAppairage.chargeValide("https://project-chip.github.io/connectedhomeip/qrcode.html?data=MT%3AY"))
        #expect(!CodeAppairage.chargeValide("MT:" + String(repeating: "A", count: 62)))
    }
}
````

- [ ] **Step 6 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `** TEST FAILED **` ; les tests ne compilent pas (`cannot find 'CodeAppairage' in scope`, `cannot find 'RecepteurLignes' in scope`…).

- [ ] **Step 7 : le tramage et les codes d'appairage.**

`apps/macos/AmaranProtocole/Tramage/ClasseurTexte.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : textes du pont amaran (docs/PROTOCOLE-JSON.md 2.4).
import Foundation

/// Classe d'une ligne de texte (hors RS), section 2.5.
public enum ClasseTexte: String, Sendable, Equatable, CaseIterable {
    /// `E (12345) tag: ...`
    case logIDF
    /// `[lampes] ...`, `[mesh] ...`, `[bouton] ...`, `!! ...`
    case annonce
    /// ROM : indice de redemarrage.
    case demarrage
    /// `amaran> ` : invite de la console en mode texte (ignoree).
    case invite
    /// Tout le reste : texte des commandes.
    case commande

    /// Filtre "logs systeme" de la console.
    public var estLogSysteme: Bool { self == .logIDF }
}

/// Ligne de texte classee.
public struct LigneTexte: Sendable, Equatable {
    /// Texte sans les sequences ANSI.
    public var texte: String
    public var classe: ClasseTexte
    /// Niveau d'un log (`E`, `W`, `I`, `D`, `V`).
    public var niveau: Character?

    public init(texte: String, classe: ClasseTexte, niveau: Character? = nil) {
        self.texte = texte
        self.classe = classe
        self.niveau = niveau
    }
}

public enum ClasseurTexte {
    private static let niveaux: Set<Character> = ["E", "W", "I", "D", "V"]

    public static func classer(_ brut: String) -> LigneTexte {
        let texte = sansANSI(brut)
        if let niv = niveauLogIDF(texte) { return LigneTexte(texte: texte, classe: .logIDF, niveau: niv) }
        if ["[lampes] ", "[mesh] ", "[bouton] ", "!! "].contains(where: texte.hasPrefix) {
            return LigneTexte(texte: texte, classe: .annonce)
        }
        if estDemarrage(texte) { return LigneTexte(texte: texte, classe: .demarrage) }
        if texte.trimmingCharacters(in: .whitespaces) == "amaran>" {
            return LigneTexte(texte: texte, classe: .invite)
        }
        return LigneTexte(texte: texte, classe: .commande)
    }

    /// Retire les sequences `ESC [ ... lettre`.
    public static func sansANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var sortie = String.UnicodeScalarView()
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            if c == "\u{1B}" {
                guard let suivant = it.next() else { break }
                if suivant == "[" {
                    while let x = it.next() {
                        if (x.value >= 0x41 && x.value <= 0x5A) || (x.value >= 0x61 && x.value <= 0x7A) { break }
                    }
                }
                continue
            }
            sortie.append(c)
        }
        return String(sortie)
    }

    /// `^[EWIDV] \(\d+\) [^:]+: `
    static func niveauLogIDF(_ s: String) -> Character? {
        let c = Array(s)
        guard c.count >= 8, niveaux.contains(c[0]), c[1] == " ", c[2] == "(" else { return nil }
        var i = 3
        var chiffres = 0
        while i < c.count, c[i].isASCII, c[i].isNumber { i += 1; chiffres += 1 }
        guard chiffres > 0, i + 1 < c.count, c[i] == ")", c[i + 1] == " " else { return nil }
        i += 2
        var tag = 0
        while i < c.count, c[i] != ":" { i += 1; tag += 1 }
        guard tag > 0, i + 1 < c.count, c[i] == ":", c[i + 1] == " " else { return nil }
        return c[0]
    }

    static func estDemarrage(_ s: String) -> Bool {
        s.hasPrefix("ESP-ROM:") || s.hasPrefix("rst:0x") || s.hasPrefix("boot:0x")
    }

    /// Firmware sans mode JSON (3.2) : sa console (la REPL d'ESP-IDF) lit `id=1`
    /// comme le nom d'une commande. Le firmware du plan 3b ne l'ecrit jamais.
    public static func estRefusIdAncienFirmware(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces) == "Unrecognized command"
    }
}
````

`apps/macos/AmaranProtocole/Tramage/RecepteurLignes.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : textes en francais seulement (spec 3b, decision 10).
import Foundation

/// Octets du tramage (section 2).
public enum Octets {
    /// Record Separator : debut d'une ligne machine.
    public static let rs: UInt8 = 0x1E
    public static let lf: UInt8 = 0x0A
    public static let cr: UInt8 = 0x0D
    /// Ctrl-U : vide la ligne en cours de saisie de la CLI.
    public static let ctrlU: UInt8 = 0x15
}

/// Ce que le recepteur tire du flux.
public enum ElementRecu: Sendable, Equatable {
    case machine(LigneMachine)
    case texte(LigneTexte)
    /// Suite d'une ligne machine coupee (filtre "logs systeme" seulement).
    case fragment(String)
    /// Ligne machine rejetee (non affichee comme texte).
    case abimee(raison: String, brut: String)
    case versionInconnue(v: Int, t: String)
    /// Objet JSON valide mais champ obligatoire absent ou mal type.
    case invalide(t: String, raison: String)
    /// Plus de 2048 octets sans LF : vides comme texte.
    case debordement(String)
}

/// Compteurs de reception de l'app (section 2.4).
public struct CompteursReception: Sendable, Equatable {
    public var lignesMachine = 0
    public var lignesTexte = 0
    public var lignesAbimees = 0
    public var fragments = 0
    public var debordements = 0
    public var versionsInconnues = 0
    public var typesInconnus = 0
    public var messagesInvalides = 0
    public var octets = 0

    public init() {}
}

/// Separation texte / JSON sur des octets bruts (algorithme 2.4).
///
/// Aucun decodage de caracteres avant d'avoir separe texte et JSON ; le texte
/// est ensuite decode en UTF-8 avec remplacement (jamais d'echec).
public struct RecepteurLignes: Sendable {
    public static let tamponMax = 2048
    /// JSON entre RS et LF : 1024 octets au plus, RS et LF compris.
    public static let jsonMax = 1022
    private static let debutJSON: [UInt8] = Array(#"{"v":"#.utf8)

    public private(set) var compteurs = CompteursReception()
    private var tampon: [UInt8] = []
    private var jeterJusquAuLF = false
    private var premiereApresPause = false
    private var precedenteAbimee = false

    public init() {}

    /// Ouverture du port : jeter tout ce qui precede le premier LF (3.1, etape 4).
    public mutating func resynchroniser() {
        tampon.removeAll(keepingCapacity: true)
        jeterJusquAuLF = true
        precedenteAbimee = false
        premiereApresPause = false
    }

    /// Pause de lecture de l'app (veille du Mac, app suspendue) : la premiere
    /// ligne lue ensuite peut etre un fragment.
    public mutating func signalerPause() {
        premiereApresPause = true
    }

    public mutating func remettreCompteursAZero() {
        compteurs = CompteursReception()
    }

    public mutating func alimenter<C: Collection>(_ octets: C) -> [ElementRecu] where C.Element == UInt8 {
        compteurs.octets += octets.count
        tampon.append(contentsOf: octets)
        var sortie: [ElementRecu] = []
        var debut = 0
        while let lf = tampon[debut...].firstIndex(of: Octets.lf) {
            let ligne = tampon[debut..<lf]
            debut = lf + 1
            traiter(ligne, dans: &sortie)
        }
        if debut > 0 { tampon.removeFirst(debut) }
        if tampon.count > Self.tamponMax {
            compteurs.debordements += 1
            let texte = String(decoding: tampon, as: UTF8.self)
            tampon.removeAll(keepingCapacity: true)
            precedenteAbimee = false
            if jeterJusquAuLF {
                // Toujours pas de LF : rien a jeter de plus, la suite est lisible.
                jeterJusquAuLF = false
            } else {
                sortie.append(.debordement(texte))
            }
        }
        return sortie
    }

    private mutating func traiter(_ brute: ArraySlice<UInt8>, dans sortie: inout [ElementRecu]) {
        var ligne = brute
        if ligne.last == Octets.cr { ligne = ligne.dropLast() }
        if jeterJusquAuLF {
            jeterJusquAuLF = false
            return
        }
        let apresPause = premiereApresPause
        premiereApresPause = false

        guard let i = ligne.lastIndex(of: Octets.rs) else {
            if ligne.last == UInt8(ascii: "}") && (precedenteAbimee || apresPause) {
                compteurs.fragments += 1
                sortie.append(.fragment(String(decoding: ligne, as: UTF8.self)))
            } else {
                compteurs.lignesTexte += 1
                sortie.append(.texte(ClasseurTexte.classer(String(decoding: ligne, as: UTF8.self))))
            }
            precedenteAbimee = false
            return
        }

        let avant = ligne[ligne.startIndex..<i]
        // Un RS plus tot dans la ligne : debut d'une ligne machine coupee avant
        // son LF (2.4, "le dernier RS"). Ce reste n'est jamais montre comme texte.
        let premierRS = avant.firstIndex(of: Octets.rs)
        let texteAvant = avant[avant.startIndex..<(premierRS ?? i)]
        if texteAvant.contains(where: { $0 != 0x20 && $0 != 0x09 }) {
            compteurs.lignesTexte += 1
            sortie.append(.texte(ClasseurTexte.classer(String(decoding: texteAvant, as: UTF8.self))))
        }
        if let premierRS {
            compteurs.lignesAbimees += 1
            sortie.append(.abimee(raison: "ligne machine coupée avant son LF",
                                  brut: String(decoding: avant[(premierRS + 1)...], as: UTF8.self)))
        }
        let json = ligne[(i + 1)...]
        precedenteAbimee = false

        func abimee(_ raison: String) {
            compteurs.lignesAbimees += 1
            precedenteAbimee = true
            sortie.append(.abimee(raison: raison, brut: String(decoding: json, as: UTF8.self)))
        }

        guard json.count <= Self.jsonMax else { return abimee("plus de \(Self.jsonMax) octets") }
        guard json.starts(with: Self.debutJSON) else { return abimee("ne commence pas par {\"v\":") }
        guard json.last == UInt8(ascii: "}") else { return abimee("ne finit pas par }") }

        switch DecodeurMessages.decoder(json: Data(json)) {
        case .valide(let l):
            compteurs.lignesMachine += 1
            if l.message == .inconnu { compteurs.typesInconnus += 1 }
            sortie.append(.machine(l))
        case .abimee(let raison):
            abimee(raison)
        case .versionInconnue(let v, let t):
            compteurs.versionsInconnues += 1
            sortie.append(.versionInconnue(v: v, t: t))
        case .invalide(let t, let raison):
            compteurs.messagesInvalides += 1
            sortie.append(.invalide(t: t, raison: raison))
        }
    }
}
````

`apps/macos/AmaranProtocole/Interpretation/Appairage.swift` (contenu complet) :

````swift
import Foundation

/// Codes d'appairage Matter du pont (`reseau`, bloc `thread`, objet `matter`,
/// section 5.5) : l'etiquette du pont, sur l'USB seulement (jamais a distance).
/// Ils ne servent que pendant une fenetre de mise en service : pont neuf, remis
/// a zero, ou retire de son dernier controleur.
public enum CodeAppairage {
    /// Code manuel groupe comme dans Maison : 11 chiffres en 4-3-4
    /// (`3497-011-2332`), 21 chiffres en 4-3-4-5-5 ; toute autre forme telle quelle.
    public static func lisible(_ code: String) -> String {
        guard code.allSatisfy({ ("0"..."9").contains($0) }) else { return code }
        let groupes: [Int]
        switch code.count {
        case 11: groupes = [4, 3, 4]
        case 21: groupes = [4, 3, 4, 5, 5]
        default: return code
        }
        var morceaux: [Substring] = []
        var debut = code.startIndex
        for n in groupes {
            let fin = code.index(debut, offsetBy: n)
            morceaux.append(code[debut..<fin])
            debut = fin
        }
        return morceaux.joined(separator: "-")
    }

    /// Charge d'un QR code Matter (`MT:` puis du base38) : seule forme dessinee.
    public static func chargeValide(_ charge: String) -> Bool {
        guard charge.hasPrefix("MT:"), charge.count > 3, charge.count <= 64 else { return false }
        let base38 = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.")
        return charge.dropFirst(3).allSatisfy { base38.contains($0) }
    }
}
````

- [ ] **Step 8 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `Test run with 23 tests in 4 suites passed` (`AmaranProtocoleTests`) et `Test run with 1 test in 0 suites passed` (`AmaranCompagnonTests`), puis `** TEST SUCCEEDED **`, sans avertissement.

> **Amendement (exécution, 05/10)** : la relecture a montré qu'une app Release signée ad hoc s'arrête au lancement : le runtime durci refuse `AmaranProtocole.framework` (pas d'équipe commune). Correctif en un commit à part : `ENABLE_HARDENED_RUNTIME` quitte `project.yml` ; `Signature.xcconfig` le met à `NO`, et `Local.xcconfig` l'active avec l'équipe (`ENABLE_HARDENED_RUNTIME = YES`). Les Tasks 10 (README de l'app) et 11 (banc B) en tiennent compte.

- [ ] **Step 9 : commit.** `git status` ne doit montrer ni `AmaranCompagnon.xcodeproj` ni `build/` (ignorés).

```bash
git add apps/macos
git commit -m "$(printf "App compagnon : projet XcodeGen, icone A2, messages du pont et tramage\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 6: Commandes, corrélation, session et état du pont (Swift, testé sur le Mac)

**Files:**
- Create: `apps/macos/AmaranProtocole/Commandes/{Commandes,Correlateur}.swift`, `apps/macos/AmaranProtocole/Transport/Transport.swift`
- Create: `apps/macos/AmaranProtocole/Session/MoteurSession.swift`, `apps/macos/AmaranProtocole/Etat/EtatPont.swift`, `apps/macos/AmaranProtocole/Interpretation/Interpretation.swift`
- Test: `apps/macos/AmaranProtocoleTests/{CorrelationTests,AncreTempsTests,CouvertureClesTests}.swift`

**Interfaces:**
- Consumes : tout ce que produit la Task 5 (messages, `RecepteurLignes`, `ElementRecu`, `ClasseurTexte`, `Octets`) ; `ExemplesSpec.decoder()`, `ligneMachine(_:)` et `exempleHb`, aides des tests de la Task 5.
- Produces (module `AmaranProtocole`, `public`) :
  - `GenreTransport` (`usb`, `demo`) ; `LigneCommande` (`valider(_:id:)`, `octets(_:id:) -> Result<Data, ErreurLigne>`, `suivant(_:)`, `mots(_:)`, `effacement`, `octetsMax` 127, `idMax`) ; `ErreurLigne` ; `PolitiqueCommandes` (`verdictConsole(_:) -> VerdictConsole`, `attendReenumeration(_:)`, `masquerCle(_:)`) ; `VerdictConsole` (`autorisee`, `confirmation(String)`, `interdite(String)`) ;
  - `Transport` (protocole : `genre`, `nom`, `ouvrir() async throws -> AsyncStream<EvenementTransport>`, `envoyer(_:)`, `fermer()`, `fermerApresVidage(synchrone:)`), `EvenementTransport` (`donnees(Data)`, `ferme(raison:)`), `ErreurTransport` ;
  - `Correlateur` (`soumettre(_:origine:fusion:secret:maintenant:)`, `prochainEnvoi(maintenant:)`, `recevoir(_ Reponse, maintenant:)`, `recevoir(_ EvenementOrdre, maintenant:)`, `texte(_:)`, `periodiqueRecu(commande:maintenant:)`, `verifierDelais`, `verifierOrdres`, `suivi(_:)`, `suivi(numero:)`, `occupe`, `commandeDeBanc`) ; `SuiviCommande` ; `EtatCommande` (`enFile`, `envoyee`, `enCours`, `terminee`, `attenteOrdre`, `confirmee`, `abandonnee`, `tenue`, `ordrePerdu`, `sansReponse`, `finPerdue`, `remplacee`, `perdue`) ; `OrigineCommande` (`interface`, `console`, `session`) ; `PolitiqueDelais.usb` (réponse 3 s, ordre 10 s) ;
  - `MoteurSession` (`ouvert(maintenant:)`, `ferme(maintenant:)`, `soumettre(…)`, `ligneBrute(_:)`, `liberer(maintenant:)`, `reessayer(maintenant:)`, `recu(_:maintenant:)`, `tic(maintenant:)`, tous `-> [Effet]` ; `phase`, `correlateur`, `periodeMs`, `bailS`, `reglages`) ; `MoteurSession.Phase` (`ferme`, `attenteHello(essai:)`, `connecte`, `resynchro`, `ancienFirmware`, `sansReponse`, `versionInconnue`, `modeHumain` ; `modeMachine`) ; `MoteurSession.Effet` (`envoyer(Data)`, `rouvrir(Note)`, `redemarrage(ancien:nouveau:)`, `note(Note)`, `commandeSansReponse(UUID)`, `ordrePerdu(UUID)`, `proposerFermeture`) ; `MoteurSession.Note` (`texte`, `grave`) ; `StatistiquesLien` ;
  - `EtatPont` (`appliquer(_:recueA:) -> Date`, `dater(ms:recueA:)`, `viderDerives()` ; un `Instantane<…>` par message : `helloBase`, `identite`, `catalogue`, `mesh`, `configLampes[n]`, `pont`, `lampes[n]`, `sante`, `compteurs`, `matter`, `thread`, `battement` ; `derniersOrdres[n]`, `motifLed`, `ledTest`, `ancre`, `numerosLampes`, `boot`, `upS`, `enService`, `capacites`) ; `Instantane` (`valeur`, `n`, `ms`, `date`) ;
  - `Interpretation` (`reponse(_:)`, `code(_:)`, `ordre(_:)`, `intensite(_:)`, `etat(_:)`, `maison(_:)`, `diag(_:)`) : les textes de la console et des cartes.

Pourquoi : la spec 3b, section 6, et `docs/PROTOCOLE-JSON.md`, sections 3 et 6 ; les choix 5, 6 et 12 de ce plan. Le corrélateur et le moteur de session sont ceux de Halo Compagnon, adaptés :
- une commande à la fois ; `json 1` ouvre la session, `json ping` tient le bail, `json 0` la rend ;
- un ordre de lampe (`accepte`, suite `ordre`) reste en `attenteOrdre` jusqu'à l'événement `ordre` qui porte son `id` (`confirmee`, `abandonnee`, `tenue`), ou `ordrePerdu` au bout de 10 s ;
- le champ `commande` des blocs `sante` et des battements dit si le pont exécute encore la commande en vol : une `reponse fin` perdue devient `finPerdue` ;
- une commande « secrète » (`mesh cles`) n'est gardée qu'en masque dans le suivi ; la ligne n'existe que le temps de l'envoi ;
- un pont d'avant ce plan répond `Unrecognized command` à `id=1 json 1` : phase `ancienFirmware`, console seule.

`EtatPont` garde le dernier message de chaque sorte et date chaque ligne par l'ancre du temps (le `ms` du pont rapporté à l'heure du Mac). `CouvertureClesTests` vérifie que chaque champ des exemples du document est lu par un décodeur : un champ ajouté au firmware sans l'être à l'app se voit. `Interpretation` ne fait que des textes, sans logique : elle n'a pas de test propre ; la console et les cartes de l'app les montrent (Tasks 8 et 9).

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranProtocoleTests/CorrelationTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : l'evenement ordre et le bloc sante du pont amaran.
import Foundation
import Testing
@testable import AmaranProtocole

func texte(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

func reponse(_ id: Int, _ etape: EtapeReponse = .fin, code: CodeReponse = .ok, ok: Bool = true,
             suite: SuiteReponse? = nil, lampe: Int? = nil, cmd: String? = nil) -> Reponse {
    Reponse(id: id, etape: etape, cmd: cmd, ok: ok, code: code, dureeMs: 1, suite: suite, lampe: lampe)
}

func ordre(lampe: Int, _ issue: IssueOrdre, ids: [Int], perdus: Int = 0) -> EvenementOrdre {
    EvenementOrdre(lampe: lampe, issue: issue, delaiMs: 410, essai: 1, ids: ids, idsPerdus: perdus)
}

@Suite("Correlation des commandes (6.2 a 6.4)")
struct CorrelateurTests {
    @Test func uneSeuleCommandeEnVol() throws {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        let b = c.soumettre("lampe 1 niveau 500", origine: .interface, maintenant: 0)
        let p1 = c.prochainEnvoi(maintenant: 0)
        let e1 = try #require(p1)
        #expect(e1.id == a)
        #expect(texte(e1.octets) == "id=1 lampe 1 on\n")
        #expect(c.prochainEnvoi(maintenant: 0.1) == nil, "une seule commande en vol")

        #expect(c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0.2)
                    == .fin(a, ordreAttendu: true))
        #expect(c.suivi(a)?.etat == .attenteOrdre)
        #expect(c.suivi(a)?.lampe == 1)
        let p2 = c.prochainEnvoi(maintenant: 0.2)
        let e2 = try #require(p2)
        #expect(e2.id == b)
        #expect(texte(e2.octets) == "id=2 lampe 1 niveau 500\n")
    }

    @Test func ordreCouvreLesOrdresDeSaLampe() throws {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 niveau 100", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0)
        let b = c.soumettre("lampe 1 niveau 150", origine: .interface, maintenant: 0.1)
        _ = c.prochainEnvoi(maintenant: 0.1)
        _ = c.recevoir(reponse(2, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0.1)
        let autre = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0.2)
        _ = c.prochainEnvoi(maintenant: 0.2)
        _ = c.recevoir(reponse(3, code: .accepte, suite: .ordre, lampe: 2), maintenant: 0.2)
        let d = c.soumettre("mesh releve 2", origine: .interface, maintenant: 0.3)
        _ = c.prochainEnvoi(maintenant: 0.3)
        _ = c.recevoir(reponse(4), maintenant: 0.3)

        // Le pont fond les ordres d'une lampe : l'evenement porte les id en attente
        // (ici 1 est sorti de sa liste : ids_perdus). La lampe 2 n'est pas touchee.
        let touches = c.recevoir(ordre(lampe: 1, .confirme, ids: [2], perdus: 1), maintenant: 1)
        #expect(Set(touches) == [a, b])
        #expect(c.suivi(a)?.etat == .confirmee)
        #expect(c.suivi(b)?.etat == .confirmee)
        #expect(c.suivi(b)?.ordre?.delaiMs == 410)
        #expect(c.suivi(autre)?.etat == .attenteOrdre, "un ordre d'une autre lampe reste en attente")
        #expect(c.suivi(d)?.etat == .terminee, "pas un ordre : rien a attendre")
        // Un ordre de Maison (ids vides) ne touche rien.
        #expect(c.recevoir(ordre(lampe: 2, .abandon, ids: []), maintenant: 2).isEmpty)
        #expect(c.recevoir(ordre(lampe: 2, .confirme, ids: [3]), maintenant: 3) == [autre])
    }

    @Test func abandonEtDejaTenu() {
        var c = Correlateur()
        let a = c.soumettre("lampe 2 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 2), maintenant: 0)
        c.recevoir(ordre(lampe: 2, .abandon, ids: [1]), maintenant: 5)
        #expect(c.suivi(a)?.etat == .abandonnee)
        #expect(c.suivi(a)?.ordre?.issue == .abandon)

        let b = c.soumettre("lampe 2 off", origine: .interface, maintenant: 6)
        _ = c.prochainEnvoi(maintenant: 6)
        _ = c.recevoir(reponse(2, code: .accepte, suite: .ordre, lampe: 2), maintenant: 6)
        c.recevoir(ordre(lampe: 2, .tenu, ids: [2]), maintenant: 6.01)
        #expect(c.suivi(b)?.etat == .tenue)
    }

    @Test func ordrePerduApresDixSecondes() {
        var c = Correlateur()
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, code: .accepte, suite: .ordre, lampe: 1), maintenant: 0.1)
        #expect(c.verifierOrdres(maintenant: 10.0).isEmpty)
        #expect(c.verifierOrdres(maintenant: 10.1).map(\.id) == [a])
        #expect(c.suivi(a)?.etat == .ordrePerdu)
    }

    @Test func commandeSecreteJamaisGardee() throws {
        var c = Correlateur()
        let cles = "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F"
        let a = c.soumettre(cles, origine: .interface, secret: true, maintenant: 0)
        #expect(c.suivi(a)?.commande == "mesh cles •••••••• ••••••••", "le suivi n'en garde que le masque")
        let envoi = c.prochainEnvoi(maintenant: 0)
        let p = try #require(envoi)
        #expect(texte(p.octets) == "id=1 " + cles + "\n", "la ligne envoyee porte les cles")
        #expect(!c.suivis.contains { $0.commande.contains("0001020304") })
    }

    @Test func sansReponseSousTroisSecondes() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.verifierDelais(maintenant: 2.9).isEmpty)
        let expirees = c.verifierDelais(maintenant: 3.0)
        #expect(expirees.map(\.id) == [a])
        #expect(c.suivi(a)?.etat == .sansReponse)
        #expect(c.enVol == nil, "la suivante peut partir, sans reemission")
        #expect(c.prochainEnvoi(maintenant: 3) == nil)
        // Une reponse tardive met encore le suivi a jour.
        _ = c.recevoir(reponse(1, code: .erreur, ok: false), maintenant: 4)
        #expect(c.suivi(a)?.etat == .terminee)
    }

    @Test func commandeHistoriqueEtTexteRattache() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 0.01) == .debut(a))
        #expect(c.texte("mesh pret : oui") == a)
        #expect(c.commandeDeBanc?.id == a)
        // Apres debut : pas de verdict de silence, meme longtemps apres.
        #expect(c.verifierDelais(maintenant: 600).isEmpty)
        _ = c.recevoir(reponse(1, .fin, code: .ok), maintenant: 601)
        #expect(c.suivi(a)?.texte == ["mesh pret : oui"])
        #expect(c.suivi(a)?.etat == .terminee)
        #expect(c.texte("apres") == nil)
    }

    @Test func fusionDesCurseurs() throws {
        var c = Correlateur()
        _ = c.soumettre("json ping", origine: .session, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        let v1 = c.soumettre("lampe 1 niveau 100", origine: .interface, fusion: "niveau1", maintenant: 0.1)
        let v2 = c.soumettre("lampe 1 niveau 120", origine: .interface, fusion: "niveau1", maintenant: 0.2)
        let t = c.soumettre("lampe 2 niveau 300", origine: .interface, fusion: "niveau2", maintenant: 0.3)
        #expect(c.suivi(v1)?.etat == .remplacee)
        #expect(c.enFile == 2)
        _ = c.recevoir(reponse(1), maintenant: 0.4)
        let p1 = c.prochainEnvoi(maintenant: 0.4)
        #expect(p1?.id == v2)
        _ = c.recevoir(reponse(2), maintenant: 0.5)
        let p2 = c.prochainEnvoi(maintenant: 0.5)
        #expect(p2?.id == t)
    }

    @Test func reponseInattendueEtReinitialisation() throws {
        var c = Correlateur()
        #expect(c.recevoir(reponse(42), maintenant: 0) == .inattendue)
        let a = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        let b = c.soumettre("lampe 1 off", origine: .interface, maintenant: 0)
        c.reinitialiser(maintenant: 1)
        #expect(c.suivi(a)?.etat == .perdue)
        #expect(c.suivi(b)?.etat == .perdue)
        #expect(c.enVol == nil)
        // Les numeros ne repartent pas a 1 : un ordre tardif de l'ancienne
        // connexion (ids [1]) ne doit pas tomber sur une commande neuve.
        _ = c.soumettre("lampe 1 niveau 300", origine: .interface, maintenant: 2)
        let p = c.prochainEnvoi(maintenant: 2)
        #expect(p.map { texte($0.octets) } == "id=2 lampe 1 niveau 300\n")
        _ = c.recevoir(reponse(2, code: .accepte, suite: .ordre, lampe: 1), maintenant: 2.1)
        #expect(c.recevoir(ordre(lampe: 1, .confirme, ids: [1]), maintenant: 2.2).isEmpty)
    }

    @Test func etapeInconnueNeClotRien() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(reponse(1, .inconnu, code: .enCours), maintenant: 0.1) == .inattendue)
        #expect(c.suivi(a)?.etat == .envoyee, "une etape future ne vaut pas fin")
        #expect(c.enVol == a, "la place en vol reste prise")
        let b = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0.2)
        #expect(c.prochainEnvoi(maintenant: 0.2) == nil)
        _ = c.recevoir(reponse(1, .fin, code: .ok), maintenant: 0.3)
        #expect(c.prochainEnvoi(maintenant: 0.3)?.id == b)
    }

    @Test func auPlusVingtLignesParSeconde() throws {
        var c = Correlateur()
        _ = c.soumettre("json ping", origine: .session, maintenant: 0)
        let b = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1), maintenant: 0.01)
        #expect(c.prochainEnvoi(maintenant: 0.02) == nil, "50 ms au moins entre deux lignes (6.3, cadence)")
        #expect(c.prochainEnvoi(maintenant: 0.05)?.id == b)
    }

    @Test func debutTardifBloqueLaFile() throws {
        var c = Correlateur()
        let banc = c.soumettre("mesh iv cherche", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.verifierDelais(maintenant: 3).map(\.id) == [banc])
        let etat = c.soumettre("json etat", origine: .session, maintenant: 3)
        _ = c.prochainEnvoi(maintenant: 3)
        // Le debut arrive apres le verdict "sans reponse" : la console du pont est occupee.
        #expect(c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 3.5) == .debut(banc))
        #expect(c.commandeDeBanc?.id == banc)
        #expect(c.occupe)
        #expect(c.texte("recherche de l'IV Index...") == banc, "le texte va a la commande en cours")
        let suivante = c.soumettre("lampe 1 on", origine: .interface, maintenant: 4)
        _ = c.verifierDelais(maintenant: 6)  // json etat sans reponse : la console du pont ne lit plus
        #expect(c.suivi(etat)?.etat == .sansReponse)
        #expect(c.prochainEnvoi(maintenant: 60) == nil, "rien ne part pendant la commande")
        _ = c.recevoir(reponse(1, .fin, code: .ok), maintenant: 600)
        #expect(c.commandeDeBanc == nil)
        #expect(c.prochainEnvoi(maintenant: 600)?.id == suivante)
    }

    @Test func finPerdueRattrapeeParLeBlocSante() throws {
        var c = Correlateur()
        let a = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        _ = c.recevoir(reponse(1, .debut, code: .enCours), maintenant: 0.1)
        let b = c.soumettre("lampe 1 on", origine: .interface, maintenant: 0.2)
        // Le bloc sante porte l'id de la commande en cours : elle tourne encore.
        #expect(c.periodiqueRecu(commande: 1, maintenant: 0.5).isEmpty)
        #expect(c.suivi(a)?.etat == .enCours)
        // La fin est perdue ; le bloc sante suivant ne porte plus son id.
        #expect(c.periodiqueRecu(commande: nil, maintenant: 1) == [a])
        #expect(c.suivi(a)?.etat == .finPerdue)
        #expect(c.prochainEnvoi(maintenant: 1)?.id == b)
    }

    @Test func numerotationBouclee() {
        #expect(LigneCommande.suivant(1) == 2)
        #expect(LigneCommande.suivant(999_999_999) == 1)
    }
}

@Suite("Moteur de session (3.2 a 3.6)")
struct MoteurSessionTests {
    static let hello = #"{"v":1,"t":"hello","n":0,"ms":83512,"bloc":"base","boot":"3FA2C901","up_s":83,"session":{"periode_ms":1000,"lampes_ms":10000,"bail_s":30}}"#

    static func element(_ json: String) -> ElementRecu {
        var r = RecepteurLignes()
        return r.alimenter(ligneMachine(json))[0]
    }

    static func envois(_ effets: [MoteurSession.Effet]) -> [String] {
        effets.compactMap { if case .envoyer(let d) = $0 { return texte(d) } else { return nil } }
    }

    static func finJson1(_ id: Int = 1, n: Int = 11) -> ElementRecu {
        element(#"{"v":1,"t":"reponse","n":\#(n),"ms":83523,"id":\#(id),"etape":"fin","cmd":"json 1","ok":true,"code":"ok","duree_ms":12,"bail_s":30,"up_s":83}"#)
    }

    /// Ouverture, hello puis reponse au json 1 : session etablie, file libre.
    static func connecte(a t: TimeInterval = 0) -> MoteurSession {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: t)
        _ = m.recu(element(hello), maintenant: t)
        _ = m.recu(finJson1(), maintenant: t)
        return m
    }

    @Test func sequenceDeConnexion() {
        var m = MoteurSession()
        let e = m.ouvert(maintenant: 0)
        #expect(Self.envois(e) == ["\u{15}\n", "id=1 json 1\n"])
        #expect(m.phase == .attenteHello(essai: 1))
        #expect(m.historique)
        _ = m.recu(Self.element(Self.hello), maintenant: 0.1)
        #expect(m.phase == .connecte)
        #expect(!m.historique)
        #expect(m.boot == "3FA2C901")
        #expect(m.bailS == 30)
        // Une seule commande en vol (6.5) : rien ne part avant la reponse fin du json 1.
        #expect(m.instantaneEnCours)
        let (_, e1) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.15)
        #expect(Self.envois(e1).isEmpty)
        // La reponse au json 1 n'est pas une commande inattendue ; elle libere la file.
        let e2 = m.recu(Self.finJson1(), maintenant: 0.2)
        #expect(m.phase == .connecte)
        #expect(!m.instantaneEnCours)
        #expect(Self.envois(e2) == ["id=2 lampe 1 on\n"])
    }

    @Test func reponseAuJson1SansHelloRenvoieJson1() {
        // hello perdu (json_perdus, coupe par un journal) : la reponse seule n'etablit rien,
        // et json 1 (idempotent) repart 2 s apres le premier envoi.
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.finJson1(), maintenant: 0.4)
        #expect(m.phase == .attenteHello(essai: 1))
        #expect(m.historique)
        #expect(Self.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1\n"])
        _ = m.recu(Self.element(Self.hello), maintenant: 2.1)
        _ = m.recu(Self.finJson1(2, n: 12), maintenant: 2.2)
        #expect(m.phase == .connecte)
        #expect(!m.instantaneEnCours)
    }

    @Test func reponseCadenceAuJson1RenvoieJson1() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":3,"ms":1,"id":1,"etape":"fin","cmd":"json 1","ok":false,"code":"cadence"}"#),
                   maintenant: 0.1)
        #expect(Self.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1\n"])
    }

    @Test func reponseAuJson1PerdueLibereLaFile() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0.1)
        let (_, e) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 0.2)
        #expect(Self.envois(e).isEmpty)
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 2.9)
        #expect(Self.envois(m.tic(maintenant: 2.9)).isEmpty)
        #expect(Self.envois(m.tic(maintenant: 3.0)) == ["id=2 lampe 1 on\n"])
    }

    @Test func numerosCroissantsApresReconnexion() {
        var m = MoteurSession()
        #expect(Self.envois(m.ouvert(maintenant: 0)).last == "id=1 json 1\n")
        m.ferme(maintenant: 1)
        #expect(Self.envois(m.ouvert(maintenant: 2)).last == "id=2 json 1\n")
    }

    @Test func pingAuTiersDUnBailCourt() {
        var m2 = MoteurSession()
        _ = m2.ouvert(maintenant: 0)
        _ = m2.recu(Self.element(Self.hello.replacingOccurrences(of: #""bail_s":30"#, with: #""bail_s":10"#)), maintenant: 0)
        _ = m2.recu(Self.element(#"{"v":1,"t":"reponse","n":11,"ms":1,"id":1,"etape":"fin","cmd":"json 1 bail 10","ok":true,"code":"ok","bail_s":10}"#),
                    maintenant: 0)
        #expect(m2.bailS == 10)
        _ = m2.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.3)
        #expect(Self.envois(m2.tic(maintenant: 3.3)).isEmpty)
        _ = m2.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.4)
        #expect(Self.envois(m2.tic(maintenant: 3.4)) == ["id=2 json ping\n"], "bail de 10 s : ping a 3,3 s")
    }

    @Test func reglagesSuivisDesCommandesJson() {
        var m = Self.connecte()
        #expect(m.reglages.log == false)
        _ = m.soumettre("json log 1", origine: .console, maintenant: 1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"fin","cmd":"json log 1","ok":true,"code":"ok"}"#), maintenant: 1.1)
        #expect(m.reglages.log == true)
        _ = m.soumettre("json lampes 5000", origine: .console, maintenant: 2)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":13,"ms":1,"id":3,"etape":"fin","cmd":"json lampes 5000","ok":true,"code":"ok"}"#), maintenant: 2.1)
        #expect(m.reglages.lampesMs == 5000)
        // json 1 remet les reglages par defaut : le hello suivant les annonce.
        _ = m.recu(Self.element(Self.hello.replacingOccurrences(of: #""bail_s":30"#, with: #""bail_s":30,"log":false"#)), maintenant: 3)
        #expect(m.reglages.log == false)
        #expect(m.reglages.lampesMs == 10000)
    }

    @Test func redemarragePerdLesOrdresAttendus() throws {
        var m = Self.connecte()
        let (id, _) = m.soumettre("lampe 1 niveau 500", origine: .interface, maintenant: 1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"fin","cmd":"lampe 1 niveau 500","ok":true,"code":"accepte","suite":"ordre","lampe":1}"#), maintenant: 1.1)
        #expect(m.correlateur.suivi(id)?.etat == .attenteOrdre)
        _ = m.recu(Self.element(#"{"v":1,"t":"hb","n":2,"ms":1000,"boot":"3FA2C901","up_s":1,"json_perdus":0,"commande":null}"#), maintenant: 2)
        #expect(m.correlateur.suivi(id)?.etat == .perdue, "le pont a redemarre : aucun ordre ne viendra")
    }

    @Test func ordreFinitLaCommande() throws {
        var m = Self.connecte()
        let (id, _) = m.soumettre("lampe 1 niveau 500", origine: .interface, maintenant: 1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"fin","cmd":"lampe 1 niveau 500","ok":true,"code":"accepte","suite":"ordre","lampe":1}"#), maintenant: 1.1)
        _ = m.recu(Self.element(#"{"v":1,"t":"ordre","n":13,"ms":1410,"lampe":1,"issue":"confirme","delai_ms":410,"essai":1,"ids":[2],"ids_perdus":0}"#), maintenant: 1.5)
        #expect(m.correlateur.suivi(id)?.etat == .confirmee)
    }

    @Test func debutTardifSuspendSilenceEtPing() {
        var m = Self.connecte()
        let (banc, e) = m.soumettre("mesh iv cherche", origine: .console, maintenant: 0.1)
        #expect(Self.envois(e) == ["id=2 mesh iv cherche\n"])
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.0)
        // Pas de reponse sous 3 s : "sans reponse", json etat demande.
        #expect(Self.envois(m.tic(maintenant: 3.1)) == ["id=3 json etat\n"])
        // Le debut arrive enfin : la console du pont est occupee.
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":12,"ms":1,"id":2,"etape":"debut","cmd":"mesh iv cherche","ok":true,"code":"en_cours"}"#), maintenant: 3.5)
        #expect(m.correlateur.commandeDeBanc?.id == banc)
        for t in stride(from: 4.0, through: 900, by: 7) {
            #expect(Self.envois(m.tic(maintenant: t)).isEmpty, "ni json 1 de silence, ni ping, ni commande (t = \(t))")
        }
        #expect(m.phase == .connecte)
        // La fin s'est perdue : un bloc sante sans son id la clot.
        _ = m.recu(Self.element(#"{"v":1,"t":"etat","n":40,"ms":9,"bloc":"sante","boot":"3FA2C901","up_s":990,"commande":null}"#), maintenant: 990)
        #expect(m.correlateur.suivi(banc)?.etat == .finPerdue)
        #expect(!m.correlateur.occupe)
    }

    @Test func renvoisDuJson1PuisSansReponse() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        #expect(Self.envois(m.tic(maintenant: 1.9)).isEmpty)
        #expect(Self.envois(m.tic(maintenant: 2.0)) == ["id=2 json 1\n"])
        #expect(Self.envois(m.tic(maintenant: 4.0)) == ["id=3 json 1\n"])
        #expect(Self.envois(m.tic(maintenant: 6.0)) == ["id=4 json 1\n"])
        #expect(m.phase == .attenteHello(essai: 4))
        let e = m.tic(maintenant: 8.0)
        #expect(Self.envois(e).isEmpty)
        #expect(m.phase == .sansReponse)
        // Puis \x15\n et json 1 toutes les 30 s, pas plus souvent.
        #expect(Self.envois(m.tic(maintenant: 30)).isEmpty)
        #expect(Self.envois(m.tic(maintenant: 36.0)) == ["\u{15}\n", "id=5 json 1\n"])
        _ = m.recu(Self.element(Self.hello), maintenant: 37)
        #expect(m.phase == .connecte)
    }

    @Test func ancienFirmware() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        let e = m.recu(.texte(ClasseurTexte.classer("Unrecognized command")), maintenant: 0.1)
        #expect(m.phase == .ancienFirmware)
        #expect(e.contains(.note(.ancienFirmware)))
        #expect(MoteurSession.Note.ancienFirmware.grave, "montree en bandeau")
        #expect(Self.envois(m.tic(maintenant: 60)).isEmpty, "plus de json 1 vers un ancien firmware")
    }

    @Test func versionInconnue() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(.versionInconnue(v: 2, t: "hello"), maintenant: 0.1)
        #expect(m.phase == .versionInconnue(2))
    }

    @Test func pingApresDixSecondes() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0.1)
        _ = m.recu(Self.finJson1(), maintenant: 0.2)
        // L'etat periodique arrive : pas de silence.
        for t in stride(from: 1.0, through: 9.0, by: 1.0) {
            _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: t)
            #expect(Self.envois(m.tic(maintenant: t)).isEmpty)
        }
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 10)
        #expect(Self.envois(m.tic(maintenant: 10)) == ["id=2 json ping\n"])
    }

    @Test func silencePuisReouverture() {
        var m = Self.connecte()
        // Une commande partie juste avant le silence : elle est perdue avec la session.
        let (enVol, _) = m.soumettre("lampe 1 on", origine: .interface, maintenant: 5)
        // 3 x max(1 s, 2 s) = 6 s sans aucune ligne.
        #expect(Self.envois(m.tic(maintenant: 5.9)).isEmpty)
        let e = m.tic(maintenant: 6.0)
        #expect(Self.envois(e) == ["id=3 json 1\n"])
        #expect(m.phase == .resynchro)
        #expect(m.correlateur.suivi(enVol)?.etat == .perdue)
        #expect(m.correlateur.enVol == nil)
        let r = m.tic(maintenant: 11.0)
        #expect(r.contains { if case .rouvrir = $0 { return true } else { return false } })
    }

    @Test func pasDeSilencePendantUneCommandeDeBanc() {
        var m = Self.connecte()
        let (_, e) = m.soumettre("mesh iv cherche", origine: .console, maintenant: 0.1)
        #expect(Self.envois(e) == ["id=2 mesh iv cherche\n"])
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":1,"ms":1,"id":2,"etape":"debut","cmd":"mesh iv cherche","ok":true,"code":"en_cours"}"#), maintenant: 0.1)
        #expect(Self.envois(m.tic(maintenant: 300)).isEmpty)
        #expect(m.phase == .connecte)
        let long = m.tic(maintenant: 20 * 60 + 1)
        #expect(long.contains(.proposerFermeture))
    }

    @Test func commandeSansReponseDemandeUnInstantane() {
        var m = Self.connecte()
        let (id, _) = m.soumettre("mesh", origine: .interface, maintenant: 1)
        _ = m.recu(.texte(LigneTexte(texte: "x", classe: .commande)), maintenant: 3.5)
        let e = m.tic(maintenant: 4.0)
        #expect(e.contains(.commandeSansReponse(id)))
        #expect(Self.envois(e) == ["id=3 json etat\n"])
    }

    @Test func redemarrageParBootOuUpS() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0)
        let hb = #"{"v":1,"t":"hb","n":1,"ms":90000,"boot":"3FA2C901","up_s":90,"json_perdus":0,"commande":null}"#
        #expect(m.recu(Self.element(hb), maintenant: 1).isEmpty)
        // up_s qui recule, meme boot : redemarrage, json 1 renvoye.
        let e = m.recu(Self.element(#"{"v":1,"t":"hb","n":2,"ms":1000,"boot":"3FA2C901","up_s":1,"json_perdus":0,"commande":null}"#),
                       maintenant: 2)
        #expect(e.contains(.redemarrage(ancien: "3FA2C901", nouveau: "3FA2C901")))
        #expect(Self.envois(e) == ["id=2 json 1\n"])
        // Nouveau boot au hello suivant : redemarrage signale, pas de json 1 de plus.
        let h = m.recu(Self.element(Self.hello.replacingOccurrences(of: "3FA2C901", with: "0BADCAFE")), maintenant: 3)
        #expect(h.contains(.redemarrage(ancien: "3FA2C901", nouveau: "0BADCAFE")))
        #expect(Self.envois(h).isEmpty)
        #expect(m.statistiques.redemarrages == 2)
    }

    @Test func finDeBailPuisJson1() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0)
        let e = m.recu(Self.element(#"{"v":1,"t":"fin","n":662,"ms":231400,"cause":"bail"}"#), maintenant: 5)
        #expect(Self.envois(e) == ["id=2 json 1\n"])
        #expect(m.phase == .attenteHello(essai: 1))
    }

    @Test func libererLePort() {
        var m = MoteurSession()
        _ = m.ouvert(maintenant: 0)
        _ = m.recu(Self.element(Self.hello), maintenant: 0)
        #expect(Self.envois(m.liberer(maintenant: 1)) == ["id=2 json 0\n"])
        #expect(m.phase == .ferme)
    }

    @Test func periodeSuivieParLeSeuilDeSilence() {
        var m = Self.connecte()
        _ = m.soumettre("json periode 5000", origine: .console, maintenant: 0.1)
        _ = m.recu(Self.element(#"{"v":1,"t":"reponse","n":1,"ms":1,"id":2,"etape":"fin","cmd":"json periode 5000","ok":true,"code":"ok"}"#), maintenant: 0.2)
        #expect(m.periodeMs == 5000)
        // 3 x 5 s = 15 s de silence toleres (ping a 10 s compris).
        _ = m.tic(maintenant: 10.2)
        #expect(m.phase == .connecte)
    }
}
````

`apps/macos/AmaranProtocoleTests/AncreTempsTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5).
import Foundation
import Testing
@testable import AmaranProtocole

/// Ancre du temps (heure locale <-> `ms` de la carte) et phase du voyant
/// (`led.depuis_ms`).
@Suite("Ancre du temps et phase du voyant")
struct AncreTempsTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// Egalite a la microseconde : les dates passent par des sommes de flottants.
    static func proche(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return abs(a.timeIntervalSince(b)) < 1e-6
    }

    static func ligne(_ json: String) throws -> LigneMachine {
        guard case .valide(let l) = DecodeurMessages.decoder(json: Data(json.utf8)) else {
            throw ErreurTransport("ligne invalide : \(json)")
        }
        return l
    }

    static func hello(ms: UInt32) throws -> LigneMachine {
        try ligne(#"{"v":1,"t":"hello","bloc":"base","n":1,"ms":\#(ms)}"#)
    }

    static func sante(n: Int, ms: UInt32, motif: String = "operationnel", depuis: Int? = nil) throws -> LigneMachine {
        let d = depuis.map { #","depuis_ms":\#($0)"# } ?? ""
        return try ligne(#"{"v":1,"t":"etat","bloc":"sante","n":\#(n),"ms":\#(ms),"led":{"motif":"\#(motif)","test":false\#(d)}}"#)
    }

    /// Le `hello` part en tete d'un instantane : il arrive parfois tard. La
    /// ligne arrivee le plus vite par rapport a lui devient l'ancre.
    @Test func ancreAffineeParLaLigneLaPlusRapide() throws {
        var e = EtatPont()
        e.appliquer(try Self.hello(ms: 10_000), recueA: Self.t0)
        // Predite a t0 + 2 s, arrivee 0,35 s plus tot : le hello avait du retard.
        e.appliquer(try Self.sante(n: 2, ms: 12_000), recueA: Self.t0.addingTimeInterval(1.65))
        #expect(e.ancre?.ms == 12_000)
        #expect(Self.proche(e.dater(ms: 20_000, recueA: .distantPast), Self.t0.addingTimeInterval(9.65)))
        // Une ligne plus lente que la prediction ne change rien.
        e.appliquer(try Self.sante(n: 3, ms: 14_000), recueA: Self.t0.addingTimeInterval(4.2))
        #expect(e.ancre?.ms == 12_000)
    }

    /// La fenetre suit la derive des horloges : la meilleure ligne sort apres
    /// `fenetreAncre` lignes, l'ancre revient aux plus recentes.
    @Test func fenetreGlissante() throws {
        var e = EtatPont()
        e.appliquer(try Self.hello(ms: 10_000), recueA: Self.t0)
        e.appliquer(try Self.sante(n: 2, ms: 12_000), recueA: Self.t0.addingTimeInterval(1.5))
        #expect(e.ancre?.ms == 12_000)
        for i in 0..<EtatPont.fenetreAncre {
            let ms = UInt32(14_000 + 100 * i)
            e.appliquer(try Self.sante(n: 3 + i, ms: ms), recueA: Self.t0.addingTimeInterval(Double(ms - 10_000) / 1000))
        }
        #expect(e.ancre?.ms != 12_000, "la ligne rapide est sortie de la fenetre")
        #expect(Self.proche(e.dater(ms: 30_000, recueA: .distantPast), Self.t0.addingTimeInterval(20)))
    }

    /// Nouveau `hello` : l'ancre repart de lui, la fenetre est videe.
    @Test func helloRepartDeZero() throws {
        var e = EtatPont()
        e.appliquer(try Self.hello(ms: 10_000), recueA: Self.t0)
        e.appliquer(try Self.sante(n: 2, ms: 12_000), recueA: Self.t0.addingTimeInterval(1.0))
        let t1 = Self.t0.addingTimeInterval(100)
        e.appliquer(try Self.hello(ms: 500), recueA: t1)
        #expect(e.ancre?.ms == 500 && e.ancre?.date == t1)
    }

    /// Avec `depuis_ms`, le voyant part du depart de phase de la carte, pas
    /// de la premiere ligne vue.
    @Test func phaseDuVoyantCaleeSurLaCarte() throws {
        var e = EtatPont()
        e.appliquer(try Self.hello(ms: 10_000), recueA: Self.t0)
        e.appliquer(try Self.sante(n: 2, ms: 20_000, depuis: 7_000), recueA: Self.t0.addingTimeInterval(10.2))
        #expect(e.motifLed == .operationnel)
        #expect(Self.proche(e.motifLedDepuis, Self.t0.addingTimeInterval(3)))
        // Evenement led : meme calcul (retour en ligne, phase d'avant).
        let led = try Self.ligne(#"{"v":1,"t":"led","n":3,"ms":21000,"motif":"livree","avant":"operationnel","test":false,"depuis_ms":0}"#)
        e.appliquer(led, recueA: Self.t0.addingTimeInterval(11.1))
        #expect(e.motifLed == .livree)
        #expect(Self.proche(e.motifLedDepuis, Self.t0.addingTimeInterval(11)))
    }

    /// Firmware sans `depuis_ms` : la phase part de la ligne ou le motif change.
    @Test func sansDepuisMsCommeAvant() throws {
        var e = EtatPont()
        e.appliquer(try Self.hello(ms: 10_000), recueA: Self.t0)
        e.appliquer(try Self.sante(n: 2, ms: 12_000), recueA: Self.t0.addingTimeInterval(2.1))
        let depart = e.motifLedDepuis
        #expect(Self.proche(depart, Self.t0.addingTimeInterval(2)))
        e.appliquer(try Self.sante(n: 3, ms: 14_000), recueA: Self.t0.addingTimeInterval(4.1))
        #expect(e.motifLedDepuis == depart, "meme motif : la phase ne repart pas")
    }
}
````

`apps/macos/AmaranProtocoleTests/CouvertureClesTests.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : les messages et les champs du pont amaran.
import Foundation
import Testing
@testable import AmaranProtocole

/// Couverture des cles : tout champ non nul d'une ligne du pont doit ressortir non
/// nul du modele decode. Une faute de frappe dans un nom de propriete decoderait
/// sinon en nil, sans rien dire (tous les champs sont optionnels, section 8).
enum CouvertureCles {
    /// Cle JSON -> nom de propriete, comme `.convertFromSnakeCase`.
    static func camel(_ cle: String) -> String {
        let parties = cle.split(separator: "_")
        guard parties.count > 1 else { return cle }
        return ([parties[0].lowercased()] + parties.dropFirst().map(\.capitalized)).joined()
    }

    /// Objets dont les cles sont des donnees (noms de taches), pas des champs : le
    /// decodeur ne les convertit pas.
    static let clesDonnees: Set<String> = ["sys.piles"]

    /// Chemins des valeurs non nulles : objets parcourus, tableaux indexes (un
    /// tableau vide compte comme une valeur presente).
    static func feuilles(_ v: Any, _ chemin: String = "", convertir: Bool) -> Set<String> {
        switch v {
        case let o as [String: Any]:
            var s = Set<String>()
            for (k, x) in o {
                let c = convertir && !clesDonnees.contains(chemin) ? camel(k) : k
                s.formUnion(feuilles(x, chemin.isEmpty ? c : chemin + "." + c, convertir: convertir))
            }
            return s
        case let a as [Any]:
            if a.isEmpty { return [chemin] }
            var s = Set<String>()
            for (i, x) in a.enumerated() { s.formUnion(feuilles(x, "\(chemin)[\(i)]", convertir: convertir)) }
            return s
        case is NSNull:
            return []
        default:
            return [chemin]
        }
    }

    static func encoder(_ m: MessageCarte) throws -> Data? {
        let e = JSONEncoder()
        switch m {
        case .helloBase(let v): return try e.encode(v)
        case .helloIdentite(let v): return try e.encode(v)
        case .configCatalogue(let v): return try e.encode(v)
        case .configMesh(let v): return try e.encode(v)
        case .configLampe(let v): return try e.encode(v)
        case .etatPont(let v): return try e.encode(v)
        case .etatLampe(let v): return try e.encode(v)
        case .etatSante(let v): return try e.encode(v)
        case .compteursMesh(let v): return try e.encode(v)
        case .reseauMatter(let v): return try e.encode(v)
        case .reseauThread(let v): return try e.encode(v)
        case .battement(let v): return try e.encode(v)
        case .fin(let v): return try e.encode(v)
        case .reponse(let v): return try e.encode(v)
        case .ordre(let v): return try e.encode(v)
        case .alerte(let v): return try e.encode(v)
        case .lampe(let v): return try e.encode(v)
        case .led(let v): return try e.encode(v)
        case .log(let v): return try e.encode(v)
        case .inconnu: return nil
        }
    }

    /// Champs non nuls de la ligne que le modele decode a perdus.
    static func perdus(_ json: String) throws -> [String] {
        var r = RecepteurLignes()
        let e = r.alimenter([Octets.rs] + Array(json.utf8) + [Octets.lf])
        guard e.count == 1, case .machine(let l) = e[0] else { return ["<ligne rejetee : \(e)>"] }
        guard let source = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let d = try encoder(l.message)
        else { return ["<type non gere : \(l.enveloppe.t)>"] }
        let attendus = feuilles(source, convertir: true).subtracting(["v", "t", "n", "ms", "bloc"])
        let obtenus = feuilles(try JSONSerialization.jsonObject(with: d), convertir: false)
        return attendus.subtracting(obtenus).sorted()
    }

    /// Champs que les exemples de la section 9 laissent nuls, vides ou absents.
    static let synthetiques: [String] = [
        // Un modele CCT au catalogue.
        #"{"v":1,"t":"config","n":1,"ms":1,"bloc":"catalogue","modeles":[{"code":40066,"nom":"amaran 150c","capacites":["intensite","cct","couleur"],"type":"couleur","cct_k":{"min":2500,"max":7500}}],"repli":{"nom":"modele non catalogue","capacites":["intensite"],"type":"variable","cct_k":null}}"#,
        // Mesh sans cles, puis une lampe masquee avec un ordre en attente.
        #"{"v":1,"t":"config","n":2,"ms":2,"bloc":"mesh","cles":false,"empreintes":null,"adresse":"7F38","iv_nvs":1,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":0,"capacite":16,"releve_ms":2000,"groupe":"C000"}"#,
        #"{"v":1,"t":"etat","n":3,"ms":3,"bloc":"lampe","lampe":3,"maison":{"endpoint":null,"vue":true,"masquee":true},"entendue":true,"lue":{"marche":false,"intensite":0},"joignable":false,"reponse_ms":2,"consigne":{"marche":true,"intensite":null,"phase":"attente","essai":2},"repondues":1,"part_10min":null,"alerte":true}"#,
        // Pont sans Mesh, sante en test, hb en commande, journal plafonne.
        #"{"v":1,"t":"etat","n":4,"ms":4,"bloc":"pont","boot":"3FA2C901","up_s":4,"mesh":{"pret":false,"diag":"iv_faux"},"ordres":{"total":3,"confirmes":1,"abandons":1,"tenus":1,"delai_total_ms":500,"delai_max_ms":500,"lents":0},"releves":2,"trames":1}"#,
        #"{"v":1,"t":"etat","n":5,"ms":5,"bloc":"sante","boot":"3FA2C901","up_s":5,"commande":9,"led":{"motif":"panne_radio","test":true,"depuis_ms":3},"matter":{"en_service":false,"thread":false,"identifie":true,"ble":true},"sys":{"heap":1,"heap_min":2,"heap_bloc":3,"piles":{"json":4,"socle":null},"json_perdus":5,"json_trop_longs":6,"rejets":7}}"#,
        #"{"v":1,"t":"hb","n":6,"ms":6,"boot":"3FA2C901","up_s":6,"json_perdus":0,"commande":12}"#,
        #"{"v":1,"t":"log","n":7,"ms":7,"src":"bouton","niv":"notice","txt":"[bouton] relache : il etait tenu au demarrage, ignore","sautes":4}"#,
        // Matter hors service, sans codes connus ; Thread detache.
        #"{"v":1,"t":"reseau","n":8,"ms":8,"bloc":"matter","demarre":false,"fabriques":0,"ble":true,"identifie":false,"abonnements":{"demandes":0,"plafonnes":0,"etablis":0,"termines":0,"plafond_s":20},"code_manuel":null,"qr":null}"#,
        // Ordre perdu au-dela de 4 id ; alerte de releves revenue ; echec d'endpoint.
        #"{"v":1,"t":"ordre","n":9,"ms":9,"lampe":4,"issue":"confirme","delai_ms":1210,"essai":2,"ids":[5,6,7,8],"ids_perdus":2}"#,
        #"{"v":1,"t":"alerte","n":10,"ms":10,"quoi":"releves","lampe":4,"manque":false,"part":96}"#,
        #"{"v":1,"t":"lampe","n":11,"ms":11,"lampe":5,"quoi":"echec","endpoint":null}"#,
        // Reponse complete : msg, suite aucune, lampe, bail.
        #"{"v":1,"t":"reponse","n":12,"ms":12,"id":17,"etape":"fin","cmd":"json ping","ok":true,"code":"ok","msg":"bail renouvele","duree_ms":1,"suite":"aucune","lampe":3,"bail_s":30,"up_s":90}"#,
    ]
}

@Suite("Couverture des cles (section 8)")
struct CouvertureClesTests {
    @Test(arguments: (try? ExemplesSpec.lignes()) ?? [])
    func chaqueChampDesExemplesEstLu(_ json: String) throws {
        let perdus = try CouvertureCles.perdus(json)
        #expect(perdus.isEmpty, "champs perdus au decodage : \(perdus)")
    }

    @Test(arguments: CouvertureCles.synthetiques)
    func chaqueChampHorsExemplesEstLu(_ json: String) throws {
        let perdus = try CouvertureCles.perdus(json)
        #expect(perdus.isEmpty, "champs perdus au decodage : \(perdus)")
    }

    @Test func leTestVoitUneCleMalNommee() throws {
        // Temoin : un champ inconnu du modele est bien signale.
        let perdus = try CouvertureCles.perdus(#"{"v":1,"t":"lampe","n":1,"ms":1,"lampe":1,"quoi":"entree","champ_futur":3}"#)
        #expect(perdus == ["champFutur"])
    }

    @Test func etapeInconnueDecodeeEtIgnoree() throws {
        var r = RecepteurLignes()
        let e = r.alimenter(ligneMachine(#"{"v":1,"t":"reponse","n":1,"ms":1,"id":1,"etape":"progression","cmd":"mesh","ok":true,"code":"en_cours"}"#))
        guard case .machine(let l) = e.first, case .reponse(let rep) = l.message else {
            Issue.record("reponse attendue : \(e)")
            return
        }
        #expect(rep.etape == .inconnu)
        var c = Correlateur()
        _ = c.soumettre("mesh", origine: .console, maintenant: 0)
        _ = c.prochainEnvoi(maintenant: 0)
        #expect(c.recevoir(rep, maintenant: 0.1) == .inattendue)
        #expect(c.enVol != nil)
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `** TEST FAILED **` ; les tests ne compilent pas (`cannot find 'EtatPont' in scope`, `cannot find type 'MoteurSession' in scope`, `cannot find 'Correlateur' in scope`…).

- [ ] **Step 3 : les commandes et le transport.**

`apps/macos/AmaranProtocole/Commandes/Commandes.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : regles et commandes du pont amaran.
import Foundation

/// Genre de transport. Thread (UDP) viendra au plan 3b-2.
public enum GenreTransport: String, Sendable, Equatable {
    case usb
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

    /// Mots d'une commande (separes par des espaces), en minuscules.
    public static func mots(_ commande: String) -> [String] {
        commande.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
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
    /// Commandes qui demandent confirmation (6.4).
    public static func verdictConsole(_ commande: String) -> VerdictConsole {
        let m = LigneCommande.mots(commande)
        guard let premier = m.first else { return .interdite(ErreurLigne.vide.description) }
        // Longueur jugee avec le plus long id possible : la ligne partira quel que soit son numero.
        if case .failure(let e) = LigneCommande.valider(commande, id: LigneCommande.idMax) {
            return .interdite(e.description)
        }
        if m == ["json", "0"] {
            return .interdite("Utiliser « Libérer le port » : l'app enverra json 0 et fermera le port.")
        }
        switch premier {
        case "redemarre":
            return .confirmation("Redémarre le pont (le port USB va se ré-énumérer).")
        case "decommission":
            return .confirmation("Retire le pont de Maison et de tout autre contrôleur Matter (clés et lampes gardées).")
        default:
            break
        }
        if premier == "mesh", m.count >= 2 {
            switch m[1] {
            case "cles":
                return .confirmation("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes.")
            case "oublie":
                return .confirmation("Efface les clés du réseau des lampes dans le pont.")
            case "adresse":
                return .confirmation("Change l'adresse Bluetooth Mesh du pont.")
            case "iv":
                return .confirmation(m.count >= 3 && m[2] == "cherche"
                    ? "Cherche l'IV Index : la console du pont reste occupée pendant la recherche."
                    : "Change l'IV Index du réseau des lampes.")
            case "lampes":
                return .confirmation("Ouvre une nouvelle liste de lampes (effet au redémarrage, une fois complète).")
            case "lampe" where m.count == 4 && m[3] == "masquer":
                return .confirmation("Retire la lampe de Maison : remise, elle y reviendra comme un nouvel accessoire, sans son nom, ses scènes ni ses automatisations.")
            default:
                break
            }
        }
        return .autorisee
    }

    /// Apres ces commandes, l'app attend la re-enumeration de l'USB (3.1).
    public static func attendReenumeration(_ commande: String) -> Bool {
        let m = LigneCommande.mots(commande)
        return m.first == "redemarre" || m.first == "decommission"
    }

    /// Masque les cles d'une ligne affichee : la commande `mesh cles <reseau>
    /// <application>` (casse et espaces quelconques, comme la console les lit), et
    /// toute suite de 32 chiffres hexa ou plus (une cle tapee ailleurs).
    public static func masquerCle(_ texte: String) -> String {
        guard texte.utf8.count >= 32 || texte.range(of: "cles", options: .caseInsensitive) != nil else { return texte }
        var s = texte
        s.replace(/(?i)(mesh[ \t]+cles)([ \t]+[0-9a-f]+)+/) { m in m.output.1 + " " + masque + " " + masque }
        s.replace(/[0-9A-Fa-f]{32,}/) { _ in masque }
        return s
    }

    private static let masque = String(repeating: "•", count: 8)
}
````

`apps/macos/AmaranProtocole/Commandes/Correlateur.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : l'evenement ordre du pont amaran remplace
// la livraison, et le bloc sante dit la commande en cours (docs/PROTOCOLE-JSON.md 6.2).
import Foundation

/// Qui a demande la commande.
public enum OrigineCommande: String, Sendable, Equatable {
    /// Boutons et curseurs de l'ecran Commandes, tableau de bord.
    case interface
    /// Console brute.
    case console
    /// Commandes de service de l'app (`json ping`, `json etat` apres un silence).
    case session
}

/// Ou en est une commande envoyee avec un `id` (6.2 a 6.4).
public enum EtatCommande: Sendable, Equatable {
    case enFile
    case envoyee
    /// `reponse` `debut` recue : commande historique en cours (peut bloquer).
    case enCours
    /// `reponse` `fin` recue, rien d'autre a attendre.
    case terminee
    /// `accepte`, `suite` `ordre` : un evenement `ordre` suivra (7.1).
    case attenteOrdre
    /// Issues de l'ordre : confirme, abandonne, deja tenu (rien n'est parti).
    case confirmee
    case abandonnee
    case tenue
    /// Aucun evenement `ordre` sous le delai de la politique : il s'est perdu.
    case ordrePerdu
    /// Pas de `reponse` sous 3 s, sans `debut` (pas de reemission).
    case sansReponse
    /// `debut` recu, puis un bloc `sante` (ou un `hb`) qui ne porte plus son id :
    /// la commande est finie, sa `fin` s'est perdue (6.2).
    case finPerdue
    /// Remplacee dans la file par une valeur plus recente (curseurs).
    case remplacee
    /// Connexion perdue avant la fin.
    case perdue

    public var estFinal: Bool {
        switch self {
        case .enFile, .envoyee, .enCours, .attenteOrdre: false
        default: true
        }
    }
}

/// Suivi d'une commande, de la file a l'evenement `ordre`.
public struct SuiviCommande: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let commande: String
    public let origine: OrigineCommande
    /// Cle de fusion : une commande en file de meme cle est remplacee.
    public let fusion: String?
    public internal(set) var numero: Int?
    public internal(set) var etat: EtatCommande
    public internal(set) var fin: Reponse?
    /// Ordre de lampe : son numero (`reponse.lampe`), et l'evenement qui l'a fini.
    public internal(set) var lampe: Int?
    public internal(set) var ordre: EvenementOrdre?
    /// Texte recu entre `reponse debut` et `reponse fin` (au mieux).
    public internal(set) var texte: [String]
    public let soumiseA: TimeInterval
    public internal(set) var envoyeeA: TimeInterval?
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

/// Correlation des commandes par `id`, une seule en vol a la fois (6.4).
///
/// Code pur : le temps est passe en argument (secondes monotones).
public struct Correlateur: Sendable {
    public static let historiqueMax = 300
    /// Au plus 20 lignes par seconde vers le pont (6.3, refus `cadence`).
    public static let intervalleMin: TimeInterval = 0.05

    public var politique = PolitiqueDelais.usb

    public private(set) var suivis: [SuiviCommande] = []
    private var file: [UUID] = []
    /// Commandes secretes (`mesh cles`), en attente d'envoi : le suivi n'en garde
    /// que la forme masquee, et la ligne est oubliee des son envoi (spec 3b, 5).
    private var secrets: [UUID: String] = [:]
    public private(set) var enVol: UUID?
    private var prochainNumero = 1
    public private(set) var dernierEnvoiA: TimeInterval?

    public init() {}

    /// Nouvelle connexion : tout ce qui attendait est perdu. Les numeros ne
    /// repartent PAS a 1 : les id en attente du pont (4 par lampe) survivent a une
    /// reconnexion de l'app, et un `ordre` tardif ne doit pas tomber sur une
    /// commande neuve de meme numero (6.1 : croissant).
    public mutating func reinitialiser(maintenant: TimeInterval) {
        for i in suivis.indices where !suivis[i].etat.estFinal {
            suivis[i].etat = .perdue
            suivis[i].termineeA = maintenant
        }
        file.removeAll()
        secrets.removeAll()
        enVol = nil
        dernierEnvoiA = nil
    }

    /// Avant un `json 1` en cours de session (silence, bail echu,
    /// redemarrage) : la commande en vol ne recevra plus sa `reponse` dans
    /// cette session ; la file reste et repartira apres la reponse au `json 1`.
    /// `redemarrage` : le pont a aussi oublie ses ordres en cours.
    public mutating func perdreEnVol(maintenant: TimeInterval, redemarrage: Bool = false) {
        for i in suivis.indices {
            let e = suivis[i].etat
            guard e == .envoyee || e == .enCours || (redemarrage && e == .attenteOrdre) else { continue }
            suivis[i].etat = .perdue
            suivis[i].termineeA = maintenant
        }
        enVol = nil
    }

    /// Reserve un numero hors file (json 1, json 0 envoyes par la session).
    public mutating func reserverNumero() -> Int {
        let n = prochainNumero
        prochainNumero = LigneCommande.suivant(n)
        return n
    }

    public func suivi(_ id: UUID) -> SuiviCommande? {
        suivis.first { $0.id == id }
    }

    public func suivi(numero: Int) -> SuiviCommande? {
        suivis.last { $0.numero == numero }
    }

    public var enFile: Int { file.count }
    public var occupe: Bool { enVol != nil || !file.isEmpty || commandeDeBanc != nil }

    /// Commande de la console du pont en cours (`debut` recu, pas encore `fin`),
    /// y compris un `debut` tardif, arrive apres le verdict "sans reponse" : la
    /// console du pont ne lit plus rien, rien d'autre ne part.
    public var commandeDeBanc: SuiviCommande? {
        suivis.last { $0.etat == .enCours }
    }

    /// `secret` : la commande porte des cles ; seul son masque reste dans le suivi.
    @discardableResult
    public mutating func soumettre(_ commande: String, origine: OrigineCommande, fusion: String? = nil,
                                   secret: Bool = false, maintenant: TimeInterval) -> UUID {
        if let fusion {
            var gardees: [UUID] = []
            for id in file {
                if let i = index(id), suivis[i].fusion == fusion {
                    suivis[i].etat = .remplacee
                    suivis[i].termineeA = maintenant
                } else {
                    gardees.append(id)
                }
            }
            file = gardees
        }
        let s = SuiviCommande(id: UUID(), commande: secret ? PolitiqueCommandes.masquerCle(commande) : commande,
                              origine: origine, fusion: fusion, numero: nil,
                              etat: .enFile, fin: nil, lampe: nil, ordre: nil, texte: [], soumiseA: maintenant,
                              envoyeeA: nil, debutA: nil, termineeA: nil)
        suivis.append(s)
        file.append(s.id)
        if secret { secrets[s.id] = commande }
        elaguer()
        return s.id
    }

    /// Prochaine ligne a envoyer si rien n'est en vol ni en cours, et pas
    /// plus d'une ligne toutes les 50 ms (20 par seconde). Une ligne invalide
    /// (trop longue...) est retiree et marquee terminee.
    public mutating func prochainEnvoi(maintenant: TimeInterval) -> (id: UUID, numero: Int, octets: Data)? {
        if let d = dernierEnvoiA, maintenant - d < Self.intervalleMin { return nil }
        while enVol == nil, commandeDeBanc == nil, !file.isEmpty {
            let id = file.removeFirst()
            guard let i = index(id) else { continue }
            let numero = prochainNumero
            switch LigneCommande.octets(secrets.removeValue(forKey: id) ?? suivis[i].commande, id: numero) {
            case .failure:
                suivis[i].etat = .terminee
                suivis[i].termineeA = maintenant
                continue
            case .success(let octets):
                prochainNumero = LigneCommande.suivant(numero)
                suivis[i].numero = numero
                suivis[i].etat = .envoyee
                suivis[i].envoyeeA = maintenant
                enVol = id
                dernierEnvoiA = maintenant
                return (id, numero, octets)
            }
        }
        return nil
    }

    /// Note un envoi fait hors file (json 1) pour le calcul du ping.
    public mutating func noterEnvoiHorsFile(maintenant: TimeInterval) {
        dernierEnvoiA = maintenant
    }

    public enum Correlation: Sendable, Equatable {
        /// `id` inconnu (autre connexion, humain au banc) : ignore.
        case inattendue
        case debut(UUID)
        /// `fin` : `ordreAttendu` si `suite` vaut `ordre`.
        case fin(UUID, ordreAttendu: Bool)
    }

    public mutating func recevoir(_ r: Reponse, maintenant: TimeInterval) -> Correlation {
        // Une reponse tardive (apres "sans reponse") met encore le suivi a jour.
        guard let i = suivis.lastIndex(where: {
            $0.numero == r.id && (!$0.etat.estFinal || $0.etat == .sansReponse)
        }) else {
            return .inattendue
        }
        let id = suivis[i].id
        switch r.etape {
        case .inconnu:
            // Etape future (progression...) : ne clot rien, ne libere pas la place en vol.
            return .inattendue
        case .debut:
            suivis[i].etat = .enCours
            suivis[i].debutA = maintenant
            return .debut(id)
        case .fin:
            suivis[i].fin = r
            suivis[i].termineeA = maintenant
            suivis[i].lampe = r.lampe
            let attend = r.ok && r.code == .accepte && r.suite == .ordre
            suivis[i].etat = attend ? .attenteOrdre : .terminee
            if enVol == id { enVol = nil }
            return .fin(id, ordreAttendu: attend)
        }
    }

    /// Un evenement `ordre` finit les ordres de sa lampe que porte `ids` ; un
    /// ordre arrive pendant un autre s'y est fondu (6.2). Les ordres plus anciens
    /// de la meme lampe, encore en attente, sont sortis de la liste du pont
    /// (`ids_perdus`) : ils prennent la meme issue.
    @discardableResult
    public mutating func recevoir(_ o: EvenementOrdre, maintenant: TimeInterval) -> [UUID] {
        guard let ids = o.ids, let plusGrand = ids.max() else { return [] }
        let etat: EtatCommande = switch o.issue {
        case .confirme: .confirmee
        case .abandon: .abandonnee
        case .tenu: .tenue
        case .inconnu, nil: .terminee
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

    /// Texte recu : rattache a la commande de banc en cours (meme apres un
    /// `debut` tardif), sinon a la commande en vol.
    @discardableResult
    public mutating func texte(_ ligne: String) -> UUID? {
        guard let id = commandeDeBanc?.id ?? enVol, let i = index(id),
              suivis[i].etat == .enCours || suivis[i].etat == .envoyee
        else { return nil }
        suivis[i].texte.append(ligne)
        if suivis[i].texte.count > 400 { suivis[i].texte.removeFirst() }
        return id
    }

    /// Bloc `sante` ou `hb` recu, avec l'id de la commande que la console du pont
    /// execute (`commande`, nil : aucune). Une commande encore "en cours" qui
    /// n'est pas celle-la est finie, et sa `reponse fin` s'est perdue (6.2).
    /// Sans cela, la place en vol resterait prise et plus rien ne partirait.
    @discardableResult
    public mutating func periodiqueRecu(commande: Int?, maintenant: TimeInterval) -> [UUID] {
        var touches: [UUID] = []
        for i in suivis.indices where suivis[i].etat == .enCours && suivis[i].numero != commande {
            suivis[i].etat = .finPerdue
            suivis[i].termineeA = maintenant
            if enVol == suivis[i].id { enVol = nil }
            touches.append(suivis[i].id)
        }
        return touches
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

    /// Ordres acceptes sans evenement `ordre` sous le delai de la politique.
    public mutating func verifierOrdres(maintenant: TimeInterval) -> [SuiviCommande] {
        var perdus: [SuiviCommande] = []
        for i in suivis.indices where suivis[i].etat == .attenteOrdre {
            guard let t = suivis[i].termineeA, maintenant - t >= politique.delaiOrdre else { continue }
            suivis[i].etat = .ordrePerdu
            suivis[i].termineeA = maintenant
            perdus.append(suivis[i])
        }
        return perdus
    }

    private func index(_ id: UUID) -> Int? {
        suivis.lastIndex { $0.id == id }
    }

    private mutating func elaguer() {
        guard suivis.count > Self.historiqueMax else { return }
        var aRetirer = suivis.count - Self.historiqueMax
        suivis.removeAll { s in
            guard aRetirer > 0, s.etat.estFinal else { return false }
            aRetirer -= 1
            return true
        }
    }
}
````

`apps/macos/AmaranProtocole/Transport/Transport.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : sans le transport UDP (plan 3b-2).
import Foundation

/// Ce qu'un transport remonte.
public enum EvenementTransport: Sendable, Equatable {
    /// Octets bruts, dans l'ordre de reception.
    case donnees(Data)
    /// Fermeture (EOF, erreur, re-enumeration USB, fermeture demandee). Le flux finit ensuite.
    case ferme(raison: String)
}

/// Transport d'octets : port serie USB, rejeu de demonstration (Thread viendra
/// au plan 3b-2). La couche protocole (tramage, session, correlation) ne connait
/// que ce protocole.
public protocol Transport: AnyObject, Sendable {
    var genre: GenreTransport { get }
    /// Nom lisible (chemin du port, "Démo"...).
    var nom: String { get }
    /// Ouvre le transport ; le flux se termine apres `.ferme`.
    func ouvrir() async throws -> AsyncStream<EvenementTransport>
    /// Envoi sans attente (ligne de 127 octets au plus).
    func envoyer(_ donnees: Data) throws
    /// Ferme sans toucher aux lignes de controle (DTR et RTS restent a 0).
    func fermer()
    /// Ferme apres avoir laisse partir les octets deja confies a `envoyer`
    /// (`json 0` avant de liberer le port), au plus quelques centaines de ms.
    /// `synchrone` : ne rend la main qu'une fois le transport ferme (fin de l'app).
    func fermerApresVidage(synchrone: Bool)
}

extension Transport {
    public func fermerApresVidage(synchrone: Bool) { fermer() }
}

/// Erreur de transport lisible.
public struct ErreurTransport: Error, Sendable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}
````

- [ ] **Step 4 : la session, l'état du pont, les textes.**

`apps/macos/AmaranProtocole/Session/MoteurSession.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : par l'USB seulement (Thread au plan 3b-2),
// avec les blocs et l'evenement ordre du pont amaran (docs/PROTOCOLE-JSON.md 3 et 6).
import Foundation

/// Compteurs de sante du lien, cote app.
public struct StatistiquesLien: Sendable, Equatable {
    /// Lignes perdues d'apres les trous de `n` (2.4).
    public var pertes = 0
    /// `n` qui recule sans changement de `boot` (lignes anciennes).
    public var reculs = 0
    public var redemarrages = 0
    public var sansReponse = 0
    public var silences = 0
    public var reouvertures = 0
    public var connexions = 0

    public init() {}
}

/// Machine d'etat de la session (section 3), independante du transport.
///
/// Code pur : chaque entree renvoie des effets que l'appelant execute
/// (envoyer des octets, rouvrir le transport...). Le temps est passe en
/// argument (secondes d'une horloge monotone), ce qui la rend testable.
public struct MoteurSession: Sendable {
    public struct Parametres: Sendable, Equatable {
        /// Sans `hello` 2 s apres `json 1` : renvoyer...
        public var delaiHello: TimeInterval = 2
        /// ... 3 fois.
        public var renvoisHello = 3
        /// Puis `\x15\n` et `json 1` toutes les 30 s, pas plus souvent.
        public var relanceLente: TimeInterval = 30
        /// `json ping` apres 10 s sans autre commande (bail de 30 s) ; plus tot
        /// si le bail est plus court (`json 1 bail 10` : au tiers du bail).
        public var pingApres: TimeInterval = 10
        /// Reponse `fin` au `json 1` attendue au plus 3 s apres le `hello`
        /// (un instantane a 16 lampes part en moins d'une demi-seconde) ; au-dela
        /// elle est tenue pour perdue et la file repart.
        public var delaiFinJson1: TimeInterval = 3
        /// Silence : aucune ligne depuis 3 x max(periode, 2 s).
        public var facteurSilence: Double = 3
        public var silenceMin: TimeInterval = 2
        /// Sans `hello` sous 5 s apres le `json 1` du silence : rouvrir le port.
        public var delaiResynchro: TimeInterval = 5
        /// Commande de la console du pont de plus de 20 min : proposer de fermer le port.
        public var bancLong: TimeInterval = 20 * 60

        public init() {}
    }

    public enum Phase: Sendable, Equatable {
        case ferme
        /// `json 1` envoye, `hello` attendu (essai 1 a 4).
        case attenteHello(essai: Int)
        /// Mode machine etabli.
        case connecte
        /// Silence du pont : `json 1` renvoye, `hello` attendu sous 5 s.
        case resynchro
        /// `Unrecognized command` : firmware sans mode JSON.
        case ancienFirmware
        /// Aucune reponse : ecoute, `json 1` toutes les 30 s.
        case sansReponse
        /// `hello` d'une version majeure non geree : console seule.
        case versionInconnue(Int)
        /// `json 0` : le pont est revenu a la console texte.
        case modeHumain

        /// Les commandes portent un `id` et suivent la correlation.
        public var modeMachine: Bool {
            switch self {
            case .connecte, .resynchro: true
            default: false
            }
        }
    }

    /// Annonce de la session a l'utilisateur.
    public enum Note: Sendable, Equatable {
        /// `Unrecognized command` (grave).
        case ancienFirmware
        /// Banniere de demarrage recue en texte.
        case texteDemarrage
        /// `hello` d'une version majeure non geree (grave).
        case versionInconnue(Int)
        /// Aucun `hello` apres les renvois de `json 1` (grave).
        case aucuneReponse
        case reponseJson1Perdue
        /// Silence du pont depuis tant de secondes : `json 1` renvoye.
        case silence(secondes: Int)
        /// Pas de `hello` sous 5 s apres le `json 1` du silence : le port est rouvert.
        case resynchroSansReponse
        /// `fin` `bail` : `json 1` renvoye.
        case bailEchu

        /// Montree en bandeau (echec de la connexion).
        public var grave: Bool {
            switch self {
            case .ancienFirmware, .versionInconnue, .aucuneReponse: true
            default: false
            }
        }

        public var texte: String {
            switch self {
            case .ancienFirmware:
                "Firmware sans mode JSON : flasher celui du plan 3b. L'app reste en console seule."
            case .texteDemarrage:
                "Texte de démarrage reçu : le pont a peut-être redémarré."
            case .versionInconnue(let v):
                "Protocole v\(v) non géré par cette app (v1) : console seule."
            case .aucuneReponse:
                "Aucune réponse : mauvais port, pont en mode téléchargement, ou commande longue en cours ? Nouvel essai toutes les 30 s."
            case .reponseJson1Perdue:
                "Réponse au json 1 perdue : les commandes reprennent."
            case .silence(let s):
                "Silence du pont depuis \(s) s : json 1 renvoyé."
            case .resynchroSansReponse:
                "Pas de réponse à json 1 sous 5 s : fermeture et réouverture du port."
            case .bailEchu:
                "Le pont a quitté le mode machine (bail échu) : json 1 renvoyé."
            }
        }
    }

    public enum Effet: Sendable, Equatable {
        case envoyer(Data)
        /// Fermer puis rouvrir le transport.
        case rouvrir(Note)
        /// Redemarrage du pont : vider les etats derives.
        case redemarrage(ancien: String?, nouveau: String?)
        case note(Note)
        case commandeSansReponse(UUID)
        /// Ordre accepte sans evenement `ordre` sous 10 s.
        case ordrePerdu(UUID)
        /// Commande de la console du pont de plus de 20 min.
        case proposerFermeture
    }

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
    public private(set) var boot: String?
    public private(set) var dernierUpS: Int?
    /// Vrai tant que le `hello` de cette connexion n'est pas arrive : les
    /// lignes recues sont des lignes anciennes, restees dans le tampon (3.1).
    public private(set) var historique = true
    /// `json 1` envoye, sa `reponse fin` pas encore recue : aucune commande
    /// de la file ne part avant (une seule commande en vol, 6.5).
    public var instantaneEnCours: Bool { json1 != nil }

    private var json1: (numero: Int, envoyeA: TimeInterval)?
    private var dernierEssaiA: TimeInterval = 0
    private var dernierRecuA: TimeInterval = 0
    private var ouvertA: TimeInterval = 0
    private var resynchroDepuis: TimeInterval?
    private var dernierN: UInt32?
    private var bancSignale = false

    public init() {}

    // MARK: - Entrees

    /// Transport ouvert : `\x15\n` puis `id=1 json 1` (3.2).
    public mutating func ouvert(maintenant: TimeInterval) -> [Effet] {
        correlateur.reinitialiser(maintenant: maintenant)
        statistiques.connexions += 1
        phase = .attenteHello(essai: 1)
        historique = true
        dernierN = nil
        ouvertA = maintenant
        dernierRecuA = maintenant
        resynchroDepuis = nil
        bancSignale = false
        return effacement + envoyerJson1(maintenant: maintenant)
    }

    private var effacement: [Effet] { [.envoyer(LigneCommande.effacement)] }

    /// Transport ferme (cable, re-enumeration, liberation du port).
    public mutating func ferme(maintenant: TimeInterval) {
        correlateur.reinitialiser(maintenant: maintenant)
        phase = .ferme
        json1 = nil
        resynchroDepuis = nil
    }

    public mutating func soumettre(_ commande: String, origine: OrigineCommande, fusion: String? = nil,
                                   secret: Bool = false, maintenant: TimeInterval) -> (UUID, [Effet]) {
        let id = correlateur.soumettre(commande, origine: origine, fusion: fusion, secret: secret, maintenant: maintenant)
        return (id, pomper(maintenant: maintenant))
    }

    /// Hors mode machine (ancien firmware, mode humain...) : ligne brute, sans `id`.
    public func ligneBrute(_ commande: String) -> Result<Data, ErreurLigne> {
        LigneCommande.octets(commande, id: nil)
    }

    /// "Liberer le port" : `json 0`, puis l'appelant ferme sans rouvrir (3.1).
    public mutating func liberer(maintenant: TimeInterval) -> [Effet] {
        var effets: [Effet] = []
        if phase != .ferme {
            let n = correlateur.reserverNumero()
            effets.append(.envoyer(Data("id=\(n) json 0\n".utf8)))
        }
        ferme(maintenant: maintenant)
        return effets
    }

    /// Relance manuelle apres un echec (firmware flashe depuis, bouton "Reessayer").
    public mutating func reessayer(maintenant: TimeInterval) -> [Effet] {
        guard phase != .ferme else { return [] }
        phase = .attenteHello(essai: 1)
        return effacement + envoyerJson1(maintenant: maintenant)
    }

    public mutating func recu(_ element: ElementRecu, maintenant: TimeInterval) -> [Effet] {
        dernierRecuA = maintenant
        var effets: [Effet] = []
        switch element {
        case .texte(let t):
            if ClasseurTexte.estRefusIdAncienFirmware(t.texte), !phase.modeMachine, phase != .ancienFirmware {
                phase = .ancienFirmware
                json1 = nil
                correlateur.reinitialiser(maintenant: maintenant)
                effets.append(.note(.ancienFirmware))
            } else if t.classe == .commande || t.classe == .annonce {
                correlateur.texte(t.texte)
            }
            if t.classe == .demarrage {
                effets.append(.note(.texteDemarrage))
            }
        case .machine(let l):
            continuite(l.enveloppe.n)
            effets += traiter(l, maintenant: maintenant)
        case .versionInconnue(let v, let t) where t == "hello":
            phase = .versionInconnue(v)
            json1 = nil
            correlateur.reinitialiser(maintenant: maintenant)
            effets.append(.note(.versionInconnue(v)))
        default:
            break
        }
        return effets + pomper(maintenant: maintenant)
    }

    public mutating func tic(maintenant: TimeInterval) -> [Effet] {
        var effets: [Effet] = []
        switch phase {
        case .attenteHello(let essai):
            if let j = json1, maintenant - j.envoyeA >= parametres.delaiHello {
                if essai <= parametres.renvoisHello {
                    phase = .attenteHello(essai: essai + 1)
                    effets += envoyerJson1(maintenant: maintenant)
                } else {
                    phase = .sansReponse
                    json1 = nil
                    // Pas de session : ce qui attendait en file ne partira pas plus tard, a l'insu.
                    correlateur.reinitialiser(maintenant: maintenant)
                    statistiques.sansReponse += 1
                    effets.append(.note(.aucuneReponse))
                }
            }
        case .sansReponse:
            if maintenant - dernierEssaiA >= parametres.relanceLente {
                effets += effacement
                effets += envoyerJson1(maintenant: maintenant)
            }
        case .connecte:
            if let j = json1, maintenant - j.envoyeA >= parametres.delaiFinJson1 {
                // hello recu mais pas la reponse fin (ligne perdue ou abimee) : la file repart.
                json1 = nil
                statistiques.sansReponse += 1
                effets.append(.note(.reponseJson1Perdue))
            }
            let limite = parametres.facteurSilence * max(Double(periodeMs) / 1000, parametres.silenceMin)
            if correlateur.commandeDeBanc == nil, maintenant - dernierRecuA >= limite {
                phase = .resynchro
                resynchroDepuis = maintenant
                statistiques.silences += 1
                effets.append(.note(.silence(secondes: Int(limite))))
                correlateur.perdreEnVol(maintenant: maintenant)
                effets += envoyerJson1(maintenant: maintenant)
            }
        case .resynchro:
            if let d = resynchroDepuis, maintenant - d >= parametres.delaiResynchro {
                resynchroDepuis = nil
                statistiques.reouvertures += 1
                effets.append(.rouvrir(.resynchroSansReponse))
            }
        default:
            break
        }

        if phase.modeMachine {
            for s in correlateur.verifierOrdres(maintenant: maintenant) { effets.append(.ordrePerdu(s.id)) }
            for s in correlateur.verifierDelais(maintenant: maintenant) {
                statistiques.sansReponse += 1
                effets.append(.commandeSansReponse(s.id))
                if s.origine != .session {
                    correlateur.soumettre("json etat", origine: .session, maintenant: maintenant)
                }
            }
            if let banc = correlateur.commandeDeBanc, let d = banc.debutA {
                if maintenant - d >= parametres.bancLong, !bancSignale {
                    bancSignale = true
                    effets.append(.proposerFermeture)
                }
            } else {
                bancSignale = false
            }
            if phase == .connecte, json1 == nil, !correlateur.occupe,
               maintenant - (correlateur.dernierEnvoiA ?? ouvertA) >= intervallePing {
                correlateur.soumettre("json ping", origine: .session, maintenant: maintenant)
            }
        }
        return effets + pomper(maintenant: maintenant)
    }

    // MARK: - Interne

    /// Ping au plus tard au tiers du bail : `json 1 bail 10` (permis depuis la
    /// console) laisserait sinon le ping de 10 s perdre la course (3.5).
    var intervallePing: TimeInterval {
        guard let b = bailS, b > 0 else { return parametres.pingApres }
        return min(parametres.pingApres, Double(b) / 3)
    }

    /// `json 1`, idempotent : chaque renvoi a son propre `id`.
    private mutating func envoyerJson1(maintenant: TimeInterval) -> [Effet] {
        let n = correlateur.reserverNumero()
        json1 = (n, maintenant)
        dernierEssaiA = maintenant
        correlateur.noterEnvoiHorsFile(maintenant: maintenant)
        return [.envoyer(Data("id=\(n) json 1\n".utf8))]
    }

    private mutating func pomper(maintenant: TimeInterval) -> [Effet] {
        guard phase == .connecte, json1 == nil, let e = correlateur.prochainEnvoi(maintenant: maintenant)
        else { return [] }
        return [.envoyer(e.octets)]
    }

    /// Controle de continuite de `n` (2.4).
    private mutating func continuite(_ n: UInt32) {
        defer { dernierN = n }
        guard let d = dernierN else { return }
        let attendu = d &+ 1
        let ecart = n &- attendu
        if ecart == 0 { return }
        if ecart < 0x8000_0000 {
            statistiques.pertes += Int(ecart)
        } else {
            statistiques.reculs += 1
        }
    }

    /// Redemarrage : `boot` change, ou `up_s` recule (3.5).
    private mutating func verifierDemarrage(boot b: String?, upS: Int?) -> Effet? {
        var redemarre = false
        let ancien = boot
        if let b {
            if let ancien, ancien != b { redemarre = true }
            boot = b
        }
        if let u = upS {
            if !redemarre, let d = dernierUpS, u < d { redemarre = true }
            dernierUpS = u
        }
        guard redemarre else { return nil }
        statistiques.redemarrages += 1
        // Le pont a oublie la commande en vol et ses ordres en cours.
        correlateur.perdreEnVol(maintenant: dernierRecuA, redemarrage: true)
        return .redemarrage(ancien: ancien, nouveau: boot)
    }

    private mutating func traiter(_ l: LigneMachine, maintenant: TimeInterval) -> [Effet] {
        var effets: [Effet] = []
        switch l.message {
        case .helloBase(let h):
            if let e = verifierDemarrage(boot: h.boot, upS: h.upS) { effets.append(e) }
            if let s = h.session { adopterReglages(s) }
            recevoirHello(maintenant: maintenant)
        case .helloIdentite(let h):
            if let e = verifierDemarrage(boot: h.boot, upS: nil) { effets.append(e) }
            recevoirHello(maintenant: maintenant)
        case .etatPont(let b):
            effets += demarrageHorsHello(boot: b.boot, upS: b.upS, maintenant: maintenant)
        case .etatSante(let b):
            correlateur.periodiqueRecu(commande: b.commande, maintenant: maintenant)
            effets += demarrageHorsHello(boot: b.boot, upS: b.upS, maintenant: maintenant)
        case .battement(let b):
            correlateur.periodiqueRecu(commande: b.commande, maintenant: maintenant)
            effets += demarrageHorsHello(boot: b.boot, upS: b.upS, maintenant: maintenant)
        case .reponse(let r):
            if let b = r.bailS { reglages.bailS = b }
            if let j = json1, r.id == j.numero {
                // La session ne s'etablit qu'avec le hello de cette tentative : une
                // reponse sans hello (hello perdu, coupe par un log, ok:false,
                // cadence) laisse json1 pose et le minuteur renvoie json 1
                // (idempotent). Apres le hello, la reponse fin libere la file.
                if r.etape == .fin, phase == .connecte { json1 = nil }
            } else if case .fin(let id, _) = correlateur.recevoir(r, maintenant: maintenant) {
                if r.ok, let s = correlateur.suivi(id) { appliquerReglage(s.commande) }
            }
        case .ordre(let o):
            correlateur.recevoir(o, maintenant: maintenant)
        case .fin(let f):
            if f.cause == .bail, phase.modeMachine {
                effets.append(.note(.bailEchu))
                historique = true
                phase = .attenteHello(essai: 1)
                correlateur.perdreEnVol(maintenant: maintenant)
                effets += envoyerJson1(maintenant: maintenant)
            } else if f.cause == .commande {
                phase = .modeHumain
                json1 = nil
            }
        default:
            break
        }
        return effets
    }

    private mutating func recevoirHello(maintenant: TimeInterval) {
        historique = false
        switch phase {
        case .attenteHello, .resynchro, .sansReponse, .ancienFirmware, .modeHumain:
            phase = .connecte
            resynchroDepuis = nil
        default:
            break
        }
    }

    /// Redemarrage vu hors `hello` (etat, hb) : le mode machine est retombe,
    /// renvoyer `json 1` (3.5).
    private mutating func demarrageHorsHello(boot b: String?, upS: Int?, maintenant: TimeInterval) -> [Effet] {
        guard let e = verifierDemarrage(boot: b, upS: upS) else { return [] }
        guard phase.modeMachine else { return [e] }
        historique = true
        phase = .attenteHello(essai: 1)
        return [e] + envoyerJson1(maintenant: maintenant)
    }

    /// Reglages annonces par un `hello` (les champs absents gardent leur valeur).
    private mutating func adopterReglages(_ s: HelloBase.ReglagesSession) {
        if let v = s.periodeMs { reglages.periodeMs = v }
        if let v = s.lampesMs { reglages.lampesMs = v }
        if let v = s.compteursMs { reglages.compteursMs = v }
        if let v = s.reseauMs { reglages.reseauMs = v }
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

`apps/macos/AmaranProtocole/Etat/EtatPont.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : instantanes et ancre du temps ; les
// blocs sont ceux du pont amaran, une entree par lampe (docs/PROTOCOLE-JSON.md 5).
import Foundation

/// Derniere valeur d'un (`t`, `bloc`), avec sa date.
public struct Instantane<Valeur: Sendable & Equatable>: Sendable, Equatable {
    public var valeur: Valeur
    public var n: UInt32
    public var ms: UInt32?
    /// Date deduite de `ms` et de l'ancre du `hello` (jamais l'heure d'arrivee,
    /// sauf avant le premier `hello`).
    public var date: Date
}

/// Ce que l'app sait du pont : la derniere valeur de chaque instantane (section 5 :
/// l'app remplace les valeurs d'un (`t`, `bloc`), et d'un (`t`, `bloc`, `lampe`), a
/// chaque reception) et les indices tires des evenements.
public struct EtatPont: Sendable, Equatable {
    public private(set) var helloBase: Instantane<HelloBase>?
    public private(set) var identite: Instantane<HelloIdentite>?
    public private(set) var catalogue: Instantane<ConfigCatalogue>?
    public private(set) var mesh: Instantane<ConfigMesh>?
    public private(set) var configLampes: [Int: Instantane<ConfigLampe>] = [:]
    public private(set) var pont: Instantane<BlocPont>?
    public private(set) var lampes: [Int: Instantane<BlocLampe>] = [:]
    public private(set) var sante: Instantane<BlocSante>?
    public private(set) var compteurs: Instantane<CompteursMesh>?
    public private(set) var matter: Instantane<ReseauMatter>?
    public private(set) var thread: Instantane<ReseauThread>?
    public private(set) var battement: Instantane<Battement>?

    /// Motif du voyant : bloc `sante` ou evenement `led`, le plus recent.
    public private(set) var motifLed: MotifLed?
    public private(set) var motifLedDepuis: Date?
    public private(set) var ledTest = false
    /// Dernier evenement `ordre` de chaque lampe.
    public private(set) var derniersOrdres: [Int: Instantane<EvenementOrdre>] = [:]

    public struct Ancre: Sendable, Equatable {
        public var date: Date
        public var ms: UInt32
    }

    /// Ancre du temps : heure locale <-> `ms` du pont. Posee a la reception d'un
    /// `hello`, puis affinee : la ligne arrivee le plus vite parmi les
    /// `fenetreAncre` dernieres (ecart a la prediction du `hello` le plus petit)
    /// la remplace. Le transit ne fait que retarder une ligne : la plus rapide dit
    /// le mieux l'ecart des horloges, et la fenetre suit leur derive.
    public private(set) var ancre: Ancre?
    /// Ancre du dernier `hello` : reference des ecarts de la fenetre.
    private var ancreHello: Ancre?
    private var echantillons: [Ancre] = []
    static let fenetreAncre = 64

    public init() {}

    /// Date d'une ligne : `ms` rapporte a l'ancre (ecart signe sur 32 bits, juste a
    /// travers le retour a zero de l'horloge du pont).
    public func dater(ms: UInt32?, recueA: Date) -> Date {
        guard let ms, let ancre else { return recueA }
        let ecart = Int32(bitPattern: ms &- ancre.ms)
        return ancre.date.addingTimeInterval(Double(ecart) / 1000)
    }

    /// Ancre affinee par la ligne (ms, recueA) : voir `ancre`.
    private mutating func affinerAncre(ms: UInt32, recueA: Date) {
        guard let h = ancreHello else { return }
        echantillons.append(Ancre(date: recueA, ms: ms))
        if echantillons.count > Self.fenetreAncre { echantillons.removeFirst(echantillons.count - Self.fenetreAncre) }
        func ecart(_ x: Ancre) -> TimeInterval {
            x.date.timeIntervalSince(h.date) - Double(Int32(bitPattern: x.ms &- h.ms)) / 1000
        }
        if let meilleur = echantillons.min(by: { ecart($0) < ecart($1) }) { ancre = meilleur }
    }

    /// Depart de la phase du motif du voyant : `ms - depuis_ms`, date par l'ancre.
    private func departPhase(ms: UInt32?, depuisMs: Int?, date: Date) -> Date? {
        guard let depuisMs else { return nil }
        guard let ms, ancre != nil else { return date.addingTimeInterval(-Double(depuisMs) / 1000) }
        return dater(ms: ms &- UInt32(clamping: depuisMs), recueA: date)
    }

    /// Applique une ligne machine ; renvoie sa date.
    @discardableResult
    public mutating func appliquer(_ l: LigneMachine, recueA: Date) -> Date {
        let e = l.enveloppe
        if case .helloBase = l.message, let ms = e.ms {
            ancre = Ancre(date: recueA, ms: ms)
            ancreHello = ancre
            echantillons = []
        }
        if let ms = e.ms { affinerAncre(ms: ms, recueA: recueA) }
        let date = dater(ms: e.ms, recueA: recueA)
        func inst<T>(_ v: T) -> Instantane<T> { Instantane(valeur: v, n: e.n, ms: e.ms, date: date) }
        switch l.message {
        case .helloBase(let v): helloBase = inst(v)
        case .helloIdentite(let v): identite = inst(v)
        case .configCatalogue(let v): catalogue = inst(v)
        case .configMesh(let v):
            mesh = inst(v)
            // La liste a pu raccourcir (une liste chargee depuis, puis un redemarrage) :
            // les lampes au-dela de N n'existent plus.
            if let n = v.lampes {
                configLampes = configLampes.filter { $0.key <= n }
                lampes = lampes.filter { $0.key <= n }
            }
        case .configLampe(let v): configLampes[v.lampe] = inst(v)
        case .etatPont(let v): pont = inst(v)
        case .etatLampe(let v): lampes[v.lampe] = inst(v)
        case .etatSante(let v):
            sante = inst(v)
            if let m = v.led?.motif {
                // Avec depuis_ms, la phase suit le pont a chaque ligne ; sans, elle
                // part de la premiere ligne ou le motif change.
                if let d = departPhase(ms: e.ms, depuisMs: v.led?.depuisMs, date: date) {
                    motifLed = m
                    motifLedDepuis = d
                } else if m != motifLed {
                    motifLed = m
                    motifLedDepuis = date
                }
            }
            ledTest = v.led?.test ?? false
        case .compteursMesh(let v): compteurs = inst(v)
        case .reseauMatter(let v): matter = inst(v)
        case .reseauThread(let v): thread = inst(v)
        case .battement(let v): battement = inst(v)
        case .led(let v):
            motifLed = v.motif
            motifLedDepuis = departPhase(ms: e.ms, depuisMs: v.depuisMs, date: date) ?? date
            ledTest = v.test ?? ledTest
        case .ordre(let v): derniersOrdres[v.lampe] = inst(v)
        default: break
        }
        return date
    }

    /// Redemarrage : les etats derives sont vides (3.5) ; l'ancre reste jusqu'au
    /// prochain `hello`.
    public mutating func viderDerives() {
        let a = ancre
        self = EtatPont()
        ancre = a
    }

    // MARK: - Lectures pratiques

    public var boot: String? {
        helloBase?.valeur.boot ?? pont?.valeur.boot ?? sante?.valeur.boot ?? battement?.valeur.boot
    }

    /// Secondes depuis le demarrage : la plus recente des valeurs connues.
    public var upS: Int? {
        [helloBase?.valeur.upS, pont?.valeur.upS, sante?.valeur.upS, battement?.valeur.upS].compactMap { $0 }.max()
    }

    public var capacites: Set<String> { Set(identite?.valeur.caps ?? []) }

    /// Numeros des lampes connues, dans l'ordre (liste du pont).
    public var numerosLampes: [Int] {
        Set(configLampes.keys).union(lampes.keys).sorted()
    }

    /// Mise en service : faite des qu'une fabrique existe (Maison ou un autre controleur).
    public var enService: Bool? {
        if let f = matter?.valeur.fabriques { return f > 0 }
        return sante?.valeur.matter?.enService
    }
}
````

`apps/macos/AmaranProtocole/Interpretation/Interpretation.swift` (contenu complet) :

````swift
// Textes lisibles des messages du pont amaran, pour la console et les cartes : sur
// le modele d'Interpretation.swift de Halo Compagnon (commit e114cd5).
import Foundation

public enum Interpretation {
    /// `reponse` : « id=5 « mesh lampe 2 masquer » : ok (38 ms) ».
    public static func reponse(_ r: Reponse) -> String {
        var t = "id=\(r.id)"
        if let c = r.cmd, !c.isEmpty { t += " « \(c) »" }
        switch r.etape {
        case .debut:
            return t + " : en cours"
        case .fin, .inconnu:
            t += " : " + code(r.code)
            if let m = r.msg, !m.isEmpty { t += " — " + m }
            if let d = r.dureeMs { t += " (\(d) ms)" }
            return t
        }
    }

    public static func code(_ c: CodeReponse) -> String {
        switch c {
        case .ok: "ok"
        case .accepte: "accepté"
        case .enCours: "en cours"
        case .erreur: "erreur (voir le texte)"
        case .usage: "arguments invalides"
        case .commandeInconnue: "commande inconnue"
        case .tropLong: "ligne trop longue"
        case .cadence: "trop de lignes par seconde"
        case .inconnu: "code inconnu"
        }
    }

    /// `ordre` : « confirmé en 410 ms (essai 1) ».
    public static func ordre(_ o: EvenementOrdre) -> String {
        switch o.issue {
        case .confirme:
            let essai = o.essai.map { " (essai \($0))" } ?? ""
            return "confirmé en \(o.delaiMs ?? 0) ms" + essai
        case .abandon:
            return "abandonné après \(o.essai ?? 0) essai(s), \(o.delaiMs ?? 0) ms : la lampe ne répond pas"
        case .tenu:
            return "déjà tenu : rien n'est parti vers la lampe"
        case .inconnu, nil:
            return "issue inconnue"
        }
    }

    /// Intensite au dixieme de pour cent : « 43 % », « 43,5 % ».
    public static func intensite(_ v: Int) -> String {
        v % 10 == 0 ? "\(v / 10) %" : "\(v / 10),\(v % 10) %"
    }

    /// Etat lu : « allumée, 43 % », « éteinte (43 %) », « noire (0 %) ».
    public static func etat(_ e: EtatLu?) -> String {
        guard let e, let marche = e.marche else { return "jamais lue" }
        let i = e.intensite.map(intensite) ?? "?"
        if e.noire { return "noire : en marche à 0 %" }
        return marche ? "allumée, \(i)" : "éteinte (\(i))"
    }

    /// Place d'une lampe dans Maison (5.3).
    public static func maison(_ m: BlocLampe.Maison?) -> String {
        guard let m else { return "inconnue" }
        if let ep = m.endpoint { return "dans Maison (EP\(ep))" }
        if m.masquee == true { return "retirée de Maison" }
        if m.vue != true { return "jamais vue : entrera dans Maison à sa première réponse" }
        return "hors de Maison (endpoint non créé)"
    }

    /// Cause d'un Bluetooth Mesh inoperant, et le remede (spec du pont 7.3).
    public static func diag(_ d: DiagMesh?) -> String {
        switch d {
        case .ok, nil: "opérationnel"
        case .clesAbsentes: "clés absentes : charger le pont depuis l'onglet Clés"
        case .pasEntre: "pas encore entré dans le réseau des lampes"
        case .clesPerimees: "aucune annonce de notre réseau : réseau recréé dans amaran Desktop ? Recopier les clés, puis recharger le pont"
        case .ivFaux: "NetMIC faux, rien de déchiffré : IV Index faux (mesh iv cherche)"
        case .inconnu: "cause inconnue"
        }
    }
}
````

- [ ] **Step 5 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `Test run with 67 tests in 8 suites passed` et `Test run with 1 test in 0 suites passed`, puis `** TEST SUCCEEDED **`, sans avertissement.

- [ ] **Step 6 : commit.**

```bash
git add apps/macos
git commit -m "$(printf "App compagnon : commandes, correlation, session et etat du pont (repris de Halo Compagnon)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 7: Les clés : base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison (Swift, testé sur le Mac)

**Files:**
- Create: `apps/macos/AmaranProtocole/Cles/{ReseauMesh,BaseAmaranDesktop,Sauvegarde,Comparaison,Chargement}.swift`
- Test: `apps/macos/AmaranProtocoleTests/ClesTests.swift`

**Interfaces:**
- Consumes : `ConfigMesh`, `ConfigLampe` (Task 5) ; `LigneCommande` (Task 6).
- Produces (module `AmaranProtocole`, `public`) :
  - `ReseauMesh` (`cleReseau`, `cleApplication`, `lampes`, `source`, `date`, `empreinteReseau`, `empreinteApplication`, `verifier() throws(ErreurReseau)`, `commandes() -> [String]`, `memeContenu(que:)`, `apercu` ; `capacite` 16, `nomMax` 31, `plageDuPont` `0x7F00...0x7F7F`) ; `ReseauMesh.Source` ; `LampeReseau` (`adresse`, `mac`, `nom`, `code`, `declarees`) ; `ErreurReseau` ; `Empreinte.de(_:)` (8 chiffres hexa majuscules du SHA-256) ;
  - `BaseAmaranDesktop` (`dossierHabituel`, `trouver(dans:) throws(ErreurBase) -> URL`, `lire(_:maintenant:)`, `lire(octets:maintenant:)`) ; `ErreurBase` ; `Data(hex:)`. `dossierHabituel` part du vrai dossier personnel (`getpwuid`) : dans une app sandboxée, `homeDirectoryForCurrentUser` est le conteneur de l'app. Un test hébergé de la Task 8, qui tourne dans la sandbox, le vérifie ;
  - `Sauvegarde` (`chiffrer(_:phrase:tours:) throws -> Data`, `tours` à 600 000 par défaut, `dechiffrer(_:phrase:) throws(ErreurSauvegarde) -> ReseauMesh`, `verifierPhrase(_:confirmation:)`, `magie`, `version`, `toursParDefaut` 600 000, `phraseMin` 12) ; `ErreurSauvegarde` ;
  - `ApercuReseau` (`empreinteReseau`, `empreinteApplication`, `lampes`, `source`, `date`, `dePont(mesh:lampes:)`, `memeReseau(que:)`, `memesCles(que:)`) ; `ComparaisonCles.ecarts(base:copie:pont:pontConnu:) -> [EcartCles]` ; `EcartCles` (`pasDeCopie`, `pontSansCles`, `pontDifferent`, `reseauRecree`, `lampesChangees` ; `texte`) ; `ComparaisonCles.modelesACataloguer(base:pont:) -> [ModeleACataloguer]` ; `ModeleACataloguer` (`lampe`, `nom`, `code`, `capacite`, `texte`) ;
  - `VerificationChargement` (`empreintesRendues(_:)`, `listeEnregistree(_:)`, `ecart(_:mesh:lampes:)`) ; `ErreurChargement`.

Pourquoi : la spec 3b, section 5, et les choix 9, 11 et 12 de ce plan. Tout est pur et testé ici, sans la vraie base ni le trousseau :
- la base est lue en mémoire (`sqlite3_deserialize`) : rien ne s'écrit près d'elle ; elle doit avoir un seul réseau, des clés de 16 octets et au moins une lampe, sinon un refus clair (`ErreurBase`) ;
- les pré-contrôles (`verifier`) reprennent ceux de `outils/cles_amaran.py` : au plus 16 lampes, adresses unicast hors de la plage du pont et sans doublon, MAC sans doublon, noms de 31 octets au plus sans caractère de contrôle ;
- `commandes()` produit ce que le pont attend : `mesh cles …`, `mesh lampes <N>`, puis une ligne `mesh lampe <n> <adresse> <mac> <code> "<nom>"` par lampe, le nom entre guillemets, avec `"` et `\` échappés (choix 7) ;
- la sauvegarde : PBKDF2-HMAC-SHA256 (600 000 tours) puis AES-GCM, l'en-tête authentifié ; phrase fausse ou fichier altéré donnent la même erreur ;
- la comparaison ne voit que des empreintes et des listes : jamais une clé ;
- la composition des lampes : une lampe qui déclare la température de couleur ou la couleur, que le pont ne lui connaît pas, est un « modèle à cataloguer », comme le dit `outils/cles_amaran.py`.

Les tests construisent une base factice en mémoire, avec les tables que lit l'app (`mesh` et `fixtures`, comme `outils/cles_amaran.py`) : clés en suites d'octets (`000102…0F`), MAC `02:00:…`. Le contenu d'un vrai réseau n'apparaît nulle part.

- [ ] **Step 1 : les tests.**

`apps/macos/AmaranProtocoleTests/ClesTests.swift` (contenu complet) :

````swift
// Tests des cles (spec 3b, section 5) : empreintes, pre-controles, commandes du
// chargement, lecture d'une base d'amaran Desktop factice, sauvegarde chiffree,
// controles du chargement. Aucune vraie cle : des octets inventes.
import Foundation
import SQLite3
import Testing
@testable import AmaranProtocole

enum Factice {
    static let cleReseau = Data((0..<16).map { UInt8($0) })
    static let cleApplication = Data((16..<32).map { UInt8($0) })

    static func reseau(_ lampes: [LampeReseau]? = nil) -> ReseauMesh {
        ReseauMesh(cleReseau: cleReseau, cleApplication: cleApplication,
                   lampes: lampes ?? [
                       LampeReseau(adresse: 0x0002, mac: "02:00:00:00:00:01", nom: "Lampe bureau", code: 40065),
                       LampeReseau(adresse: 0x0004, mac: "02:00:00:00:00:02", nom: "Lumière fenêtre", code: 40065),
                   ],
                   source: .amaranDesktop, date: Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    /// Base d'amaran Desktop factice, en memoire puis serialisee : les tables et
    /// colonnes que lit outils/cles_amaran.py.
    static func base(_ sql: [String]) throws -> Data {
        var db: OpaquePointer?
        let ouverte = sqlite3_open(":memory:", &db)
        try #require(ouverte == SQLITE_OK)
        defer { sqlite3_close(db) }
        for s in sql {
            let r = sqlite3_exec(db, s, nil, nil, nil)
            try #require(r == SQLITE_OK, "\(s)")
        }
        var taille: sqlite3_int64 = 0
        let serialisee = sqlite3_serialize(db, "main", &taille, 0)
        let p = try #require(serialisee)
        defer { sqlite3_free(p) }
        return Data(bytes: p, count: Int(taille))
    }

    static let tables = [
        "create table mesh (net_key text, app_key text)",
        "create table fixtures (node_address integer, mac_address text, name text, code text, composition_data text)",
    ]
    static let cles = "insert into mesh values ('000102030405060708090A0B0C0D0E0F', '101112131415161718191a1b1c1d1e1f')"
}

@Suite("Cles du reseau")
struct ClesTests {
    @Test func empreinte() {
        #expect(Empreinte.de(Data(count: 16)) == "374708FF")
        #expect(Factice.reseau().empreinteReseau == "BE45CB26")
    }

    @Test func preControles() throws {
        try Factice.reseau().verifier()
        func faute(_ lampes: [LampeReseau]) -> ErreurReseau? {
            do { try Factice.reseau(lampes).verifier() } catch { return error }
            return nil
        }
        let ok = LampeReseau(adresse: 2, mac: "02:00:00:00:00:01", nom: "A", code: 0)
        #expect(faute([]) == .nombreLampes(0))
        #expect(faute(Array(repeating: ok, count: 17)) == .nombreLampes(17))
        #expect(faute([LampeReseau(adresse: 0x7F38, mac: ok.mac, nom: "A", code: 0)]) == .adresseDuPont(lampe: 1, 0x7F38))
        #expect(faute([LampeReseau(adresse: 0, mac: ok.mac, nom: "A", code: 0)]) == .adresse(lampe: 1, 0))
        #expect(faute([ok, LampeReseau(adresse: 2, mac: "02:00:00:00:00:02", nom: "B", code: 0)]) == .adresseEnDouble(2))
        #expect(faute([ok, LampeReseau(adresse: 4, mac: "02:00:00:00:00:01", nom: "B", code: 0)])
                == .macEnDouble("02:00:00:00:00:01"))
        #expect(faute([LampeReseau(adresse: 2, mac: "02-00-00-00-00-01", nom: "A", code: 0)]) == .mac(lampe: 1))
        #expect(faute([LampeReseau(adresse: 2, mac: ok.mac, nom: "", code: 0)]) == .nom(lampe: 1, "nom vide"))
        #expect(faute([LampeReseau(adresse: 2, mac: ok.mac, nom: String(repeating: "é", count: 16), code: 0)])
                == .nom(lampe: 1, "nom de 32 octets, 31 au plus"))
        #expect(faute([LampeReseau(adresse: 2, mac: ok.mac, nom: "a\tb", code: 0)])
                == .nom(lampe: 1, "caractère de contrôle dans le nom"))
        var cle = Factice.reseau()
        cle.cleApplication = Data(count: 15)
        #expect(throws: ErreurReseau.cle("application")) { try cle.verifier() }
    }

    @Test func commandesDuChargement() {
        let c = Factice.reseau().commandes()
        #expect(c == [
            "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F",
            "mesh lampes 2",
            "mesh lampe 1 0x0002 02:00:00:00:00:01 40065 \"Lampe bureau\"",
            "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 \"Lumière fenêtre\"",
        ])
        // Guillemets et barres echappes : un seul argument pour esp_console_split_argv.
        #expect(ReseauMesh.argument(#"La "bonne" \ lampe"#) == #""La \"bonne\" \\ lampe""#)
    }

    /// Le pire nom (31 guillemets, echappes en 62 octets) tient encore dans une ligne
    /// de 127 octets, avec le plus long id et le plus long code.
    @Test func lignesDansLaLimite() throws {
        let pire = (0..<16).map { i in
            LampeReseau(adresse: 0x7EFF - UInt16(i), mac: String(format: "02:00:00:00:00:%02X", i),
                        nom: String(repeating: "\"", count: 31), code: .max)
        }
        let r = Factice.reseau(pire)
        try r.verifier()
        for c in r.commandes() {
            let ligne = try LigneCommande.valider(c, id: LigneCommande.idMax).get()
            #expect(ligne.utf8.count <= 127, "\(ligne.utf8.count) octets")
        }
    }

    @Test func masquage() {
        let c = Factice.reseau().commandes()[0]
        #expect(PolitiqueCommandes.masquerCle(c) == "mesh cles •••••••• ••••••••")
        #expect(PolitiqueCommandes.masquerCle("id=7 MESH  Cles 00112233445566778899aabbccddeeff x")
                == "id=7 MESH  Cles •••••••• •••••••• x")
        #expect(PolitiqueCommandes.masquerCle("ok cles 1A2B3C4D 5E6F7A8B (redemarrer)") == "ok cles 1A2B3C4D 5E6F7A8B (redemarrer)",
                "les empreintes restent visibles")
        #expect(PolitiqueCommandes.verdictConsole(c)
                == .confirmation("Remplace les clés du réseau des lampes dans le pont (effet au redémarrage). « Charger le pont » vérifie en plus les empreintes."))
    }
}

@Suite("Base d'amaran Desktop")
struct BaseAmaranDesktopTests {
    static let lampes = [
        // Composition (page 0) : en-tete de 11 octets, puis un element : OnOff et Lightness...
        "insert into fixtures values (2, '02:00:00:00:00:01', 'Lampe bureau', '40065', '0000000000000000000000' || '00000200' || '00100013')",
        // ... et, pour la seconde, Lightness, Light CTL et Light HSL.
        "insert into fixtures values (4, '02:00:00:00:00:02', 'Lumière fenêtre', ' 40065 ', '0000000000000000000000' || '00000300' || '001303130713')",
        "insert into fixtures values (null, '02:00:00:00:00:03', 'jamais provisionnee', null, null)",
    ]

    @Test func lecture() throws {
        let base = try Factice.base(Factice.tables + [Factice.cles] + Self.lampes)
        let r = try BaseAmaranDesktop.lire(octets: base, maintenant: Date(timeIntervalSinceReferenceDate: 1))
        #expect(r.cleReseau == Factice.cleReseau)
        #expect(r.cleApplication == Factice.cleApplication)
        #expect(r.lampes.map(\.adresse) == [2, 4], "les fixtures sans adresse sont ignorees")
        #expect(r.lampes[1].nom == "Lumière fenêtre")
        #expect(r.lampes.map(\.code) == [40065, 40065], "code en texte, espaces tolerees")
        #expect(r.lampes[0].declarees.isEmpty)
        #expect(r.lampes[1].declarees == ["cct", "couleur"], "Light CTL et Light HSL dans la composition")
        #expect(r.source == .amaranDesktop)
    }

    @Test func baseAncienneSansCodeNiComposition() throws {
        let base = try Factice.base([
            "create table mesh (net_key text, app_key text)",
            "create table fixtures (node_address integer, mac_address text, name text)",
            Factice.cles,
            "insert into fixtures values (2, '02:00:00:00:00:01', 'Lampe bureau')",
        ])
        let r = try BaseAmaranDesktop.lire(octets: base)
        #expect(r.lampes.first?.code == 0)
    }

    @Test func refus() throws {
        func erreur(_ sql: [String]) throws -> ErreurBase? {
            let base = try Factice.base(Factice.tables + sql)
            do { _ = try BaseAmaranDesktop.lire(octets: base) } catch { return error }
            return nil
        }
        #expect(try erreur([]) == .reseaux(0))
        #expect(try erreur([Factice.cles, Factice.cles]) == .reseaux(2))
        #expect(try erreur(["insert into mesh values ('0011', '2233')"]) == .cle)
        #expect(try erreur(["insert into mesh values ('zz0102030405060708090A0B0C0D0E0F', '101112131415161718191A1B1C1D1E1F')"]) == .cle)
        #expect(try erreur([Factice.cles]) == .aucuneLampe)
        // Une valeur qui n'est pas du texte (spec 3b, section 5) : un nom en BLOB, que
        // l'affinite TEXT de la colonne ne convertit pas.
        #expect(try erreur([Factice.cles, "insert into fixtures values (2, '02:00:00:00:00:01', X'41', null, null)"])
                == .lampe(adresse: "2"))
        #expect(try erreur([Factice.cles, "insert into fixtures values (2, 'pas une mac', 'A', null, null)"])
                == .lampe(adresse: "2"))
        #expect(try erreur([Factice.cles, "insert into fixtures values ('deux', '02:00:00:00:00:01', 'A', null, null)"])
                == .lampe(adresse: "?"))
        #expect(throws: ErreurBase.illisible("fichier vide")) { try BaseAmaranDesktop.lire(octets: Data()) }
    }

    @Test func dossierSansBase() {
        let vide = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(throws: ErreurBase.introuvable) { try BaseAmaranDesktop.trouver(dans: vide) }
    }
}

@Suite("Sauvegarde chiffree")
struct SauvegardeTests {
    static let phrase = "une phrase de passe assez longue"

    @Test func allerRetour() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase, tours: 1000)
        #expect(f.prefix(8) == Data("AMARANSV".utf8))
        #expect(f.range(of: Factice.cleReseau) == nil, "la cle n'apparait pas en clair")
        let r = try Sauvegarde.dechiffrer(f, phrase: Self.phrase)
        #expect(r == Factice.reseau())
    }

    @Test func toursParDefaut() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase)
        #expect(f[9..<13] == Data([0x00, 0x09, 0x27, 0xC0]), "600 000 tours dans l'en-tete")
        #expect(try Sauvegarde.dechiffrer(f, phrase: Self.phrase) == Factice.reseau())
    }

    @Test func phraseFausseOuFichierAltere() throws {
        let f = try Sauvegarde.chiffrer(Factice.reseau(), phrase: Self.phrase, tours: 1000)
        #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try Sauvegarde.dechiffrer(f, phrase: "une autre phrase longue") }
        #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try Sauvegarde.dechiffrer(f, phrase: "") }
        // Chaque octet apres la version (tours, sel, nonce, contenu, etiquette) est verifie.
        for i in stride(from: 9, to: f.count, by: 7) {
            var g = f
            g[i] ^= 0x01
            #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try Sauvegarde.dechiffrer(g, phrase: Self.phrase) }
        }
        var v = f
        v[8] = 2
        #expect(throws: ErreurSauvegarde.versionInconnue(2)) { try Sauvegarde.dechiffrer(v, phrase: Self.phrase) }
        #expect(throws: ErreurSauvegarde.pasUneSauvegarde) { try Sauvegarde.dechiffrer(Data("AMARANS".utf8), phrase: Self.phrase) }
        #expect(throws: ErreurSauvegarde.pasUneSauvegarde) { try Sauvegarde.dechiffrer(f.prefix(29), phrase: Self.phrase) }
    }

    @Test func phraseDePasse() {
        #expect(throws: ErreurSauvegarde.phraseTropCourte(11)) { try Sauvegarde.verifierPhrase("onze lettre", confirmation: "onze lettre") }
        #expect(throws: ErreurSauvegarde.phrasesDifferentes) { try Sauvegarde.verifierPhrase(Self.phrase, confirmation: Self.phrase + "!") }
        #expect(throws: Never.self) { try Sauvegarde.verifierPhrase("douze lettre", confirmation: "douze lettre") }
    }
}

@Suite("Controles du chargement")
struct ChargementTests {
    @Test func reponsesDuPont() {
        let e = VerificationChargement.empreintesRendues(["ok cles 1a2b3c4d 5E6F7A8B (redemarrer pour les appliquer)"])
        #expect(e?.reseau == "1A2B3C4D" && e?.application == "5E6F7A8B")
        #expect(VerificationChargement.empreintesRendues(["erreur : ecriture NVS"]) == nil)
        #expect(VerificationChargement.listeEnregistree([
            "ok lampe 2 0x0004 modele 40065 amaran COB 60d [intensite] : Lumière fenêtre ; liste de 2 lampe(s) enregistree (redemarrer pour l'appliquer)",
        ]) == 2)
        #expect(VerificationChargement.listeEnregistree(["ok lampe 1 0x0002 modele 40065 amaran COB 60d [intensite] : A"]) == nil)
    }

    @Test func apresLeRedemarrage() throws {
        let r = Factice.reseau()
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let mesh = try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"BE45CB26","application":"\#(r.empreinteApplication)"},"lampes":2}"#.utf8))
        func lampe(_ n: Int, _ a: String, _ mac: String, _ nom: String) throws -> ConfigLampe {
            try d.decode(ConfigLampe.self, from: Data(#"{"lampe":\#(n),"adresse":"\#(a)","mac":"\#(mac)","nom":"\#(nom)","code":40065}"#.utf8))
        }
        let lampes = [1: try lampe(1, "0002", "020000000001", "Lampe bureau"),
                      2: try lampe(2, "0004", "020000000002", "Lumière fenêtre")]
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh, lampes: lampes) == nil)
        #expect(VerificationChargement.ecart(r.apercu, mesh: mesh, lampes: [1: lampes[1]!]) == "1 lampe(s), 2 attendue(s)")
        var autre = r
        autre.lampes[0].nom = "Autre nom"
        #expect(VerificationChargement.ecart(autre.apercu, mesh: mesh, lampes: lampes) == "lampe 1 différente")
        autre = r
        autre.cleReseau = Data(count: 16)
        #expect(VerificationChargement.ecart(autre.apercu, mesh: mesh, lampes: lampes)?.hasPrefix("empreintes BE45CB26") == true)
        #expect(VerificationChargement.ecart(r.apercu, mesh: nil, lampes: lampes) == "pas de clés")
    }
}

@Suite("Comparaison des cles")
struct ComparaisonTests {
    static let copie = Factice.reseau().apercu

    @Test func pontDepuisSaConfig() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let mesh = try d.decode(ConfigMesh.self, from: Data(#"{"cles":true,"empreintes":{"reseau":"BE45CB26","application":"\#(Self.copie.empreinteApplication)"},"lampes":2}"#.utf8))
        let l1 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":1,"adresse":"0002","mac":"020000000001","nom":"Lampe bureau","code":40065}"#.utf8))
        let l2 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":2,"adresse":"0004","mac":"020000000002","nom":"Lumière fenêtre","code":40065}"#.utf8))
        let pont = try #require(ApercuReseau.dePont(mesh: mesh, lampes: [1: l1, 2: l2]))
        #expect(pont.memeReseau(que: Self.copie))
        #expect(pont.lampes[0].mac == "02:00:00:00:00:01")
        #expect(ApercuReseau.dePont(mesh: nil, lampes: [:]) == nil)
    }

    @Test func ecarts() {
        let c = Self.copie
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: c, pontConnu: true).isEmpty)
        #expect(ComparaisonCles.ecarts(base: c, copie: nil, pont: nil, pontConnu: true) == [.pasDeCopie])
        #expect(ComparaisonCles.ecarts(base: nil, copie: c, pont: nil, pontConnu: true) == [.pontSansCles])
        #expect(ComparaisonCles.ecarts(base: nil, copie: c, pont: nil, pontConnu: false).isEmpty, "pas de pont : rien a en dire")
        var autre = c
        autre.lampes.removeLast()
        #expect(ComparaisonCles.ecarts(base: c, copie: c, pont: autre, pontConnu: true) == [.pontDifferent])
        #expect(ComparaisonCles.ecarts(base: autre, copie: c, pont: c, pontConnu: true) == [.lampesChangees])
        var recree = c
        recree.empreinteReseau = "00000000"
        #expect(ComparaisonCles.ecarts(base: recree, copie: c, pont: c, pontConnu: true) == [.reseauRecree])
        // Les capacites declarees ne comptent pas : le pont ne les connait pas.
        var declarees = c
        declarees.lampes[0].declarees = ["cct"]
        #expect(declarees.memeReseau(que: c))
    }

    /// Comme outils/cles_amaran.py : une capacite declaree dans la base, que le pont
    /// ne connait pas a la lampe (meme MAC), fait un modele a cataloguer.
    @Test func modelesACataloguer() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let l1 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":1,"mac":"020000000001","capacites":["intensite"]}"#.utf8))
        let l2 = try d.decode(ConfigLampe.self, from: Data(#"{"lampe":2,"mac":"020000000002","capacites":["intensite","cct"]}"#.utf8))
        var base = Self.copie
        base.lampes[0].declarees = []
        base.lampes[1].declarees = ["cct", "couleur"]
        let m = ComparaisonCles.modelesACataloguer(base: base, pont: [1: l1, 2: l2])
        #expect(m == [ModeleACataloguer(lampe: 2, nom: "Lumière fenêtre", code: 40065, capacite: "couleur")])
        #expect(m.first?.texte == "Lampe 2 (Lumière fenêtre, code 40065) : déclare la couleur, que le pont ne lui connaît pas : marche et intensité seulement, modèle à cataloguer.")
        #expect(ComparaisonCles.modelesACataloguer(base: nil, pont: [1: l1]).isEmpty)
        #expect(ComparaisonCles.modelesACataloguer(base: base, pont: [:]).isEmpty, "pas de pont : rien a en dire")
    }
}
````

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `** TEST FAILED **` ; les tests ne compilent pas (`cannot find type 'ReseauMesh' in scope`, `cannot find 'LampeReseau' in scope`…).

- [ ] **Step 3 : le réseau, la base, la sauvegarde.**

`apps/macos/AmaranProtocole/Cles/ReseauMesh.swift` (contenu complet) :

````swift
// Le reseau Bluetooth Mesh des lampes : ses deux cles et la liste des lampes, tels
// qu'amaran Desktop les connait (spec 3b, section 5). Les cles ne sont jamais
// affichees, journalisees ni copiees : seulement leurs empreintes.
import CryptoKit
import Foundation

/// Empreinte d'une cle : les 8 premiers chiffres hexa, en majuscules, de son
/// SHA-256 (comme le pont, `config_empreinte`, et outils/cles_amaran.py).
public enum Empreinte {
    public static func de(_ cle: Data) -> String {
        SHA256.hash(data: cle).prefix(4).map { String(format: "%02X", $0) }.joined()
    }
}

/// Une lampe du reseau.
public struct LampeReseau: Codable, Sendable, Equatable, Hashable {
    /// Adresse unicast Bluetooth Mesh.
    public var adresse: UInt16
    /// `AA:BB:CC:DD:EE:FF`, en majuscules.
    public var mac: String
    public var nom: String
    /// Code produit Sidus ; 0 : inconnu.
    public var code: UInt32
    /// Capacites au-dela de l'intensite que sa composition declare (`cct`,
    /// `couleur`) : un modele a cataloguer si le pont ne les lui connait pas.
    public var declarees: [String]

    public init(adresse: UInt16, mac: String, nom: String, code: UInt32, declarees: [String] = []) {
        self.adresse = adresse
        self.mac = mac
        self.nom = nom
        self.code = code
        self.declarees = declarees
    }
}

/// Faute trouvee par les pre-controles : rien n'est envoye au pont.
public enum ErreurReseau: Error, Sendable, Equatable, CustomStringConvertible {
    case cle(String)
    case nombreLampes(Int)
    case adresse(lampe: Int, UInt16)
    case adresseDuPont(lampe: Int, UInt16)
    case adresseEnDouble(UInt16)
    case mac(lampe: Int)
    case macEnDouble(String)
    case nom(lampe: Int, String)

    public var description: String {
        switch self {
        case .cle(let quoi): "Clé \(quoi) : 16 octets attendus."
        case .nombreLampes(let n): "\(n) lampe(s) : le pont en gère de 1 à \(ReseauMesh.capacite)."
        case .adresse(let l, let a): "Lampe \(l) : adresse 0x\(String(format: "%04X", a)) hors de 0x0001–0x7FFF."
        case .adresseDuPont(let l, let a):
            "Lampe \(l) : adresse 0x\(String(format: "%04X", a)) dans la plage du pont (0x7F00–0x7F7F)."
        case .adresseEnDouble(let a): "Adresse 0x\(String(format: "%04X", a)) en double."
        case .mac(let l): "Lampe \(l) : MAC illisible."
        case .macEnDouble(let m): "MAC \(m) en double."
        case .nom(let l, let raison): "Lampe \(l) : \(raison)."
        }
    }
}

/// Les cles du reseau et ses lampes : copie d'amaran Desktop, gardee dans le
/// trousseau et dans les sauvegardes.
public struct ReseauMesh: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case amaranDesktop
        case sauvegarde
    }

    /// LISTE_CAPACITE du pont.
    public static let capacite = 16
    /// Nom d'une lampe : 31 octets au plus (NodeLabel de Matter, NUL compris dans 32).
    public static let nomMax = 31
    /// Plage des adresses du pont (spec du pont 5.4) : jamais celle d'une lampe.
    public static let plageDuPont: ClosedRange<UInt16> = 0x7F00...0x7F7F

    public var cleReseau: Data
    public var cleApplication: Data
    public var lampes: [LampeReseau]
    public var source: Source
    /// Date de la copie depuis amaran Desktop.
    public var date: Date

    public init(cleReseau: Data, cleApplication: Data, lampes: [LampeReseau], source: Source, date: Date) {
        self.cleReseau = cleReseau
        self.cleApplication = cleApplication
        self.lampes = lampes
        self.source = source
        self.date = date
    }

    public var empreinteReseau: String { Empreinte.de(cleReseau) }
    public var empreinteApplication: String { Empreinte.de(cleApplication) }

    /// Pre-controles avant tout envoi (spec 3b, section 5) : rien n'est ecrit dans le
    /// pont si l'un d'eux echoue.
    public func verifier() throws(ErreurReseau) {
        guard cleReseau.count == 16 else { throw .cle("réseau") }
        guard cleApplication.count == 16 else { throw .cle("application") }
        guard (1...Self.capacite).contains(lampes.count) else { throw .nombreLampes(lampes.count) }
        var adresses = Set<UInt16>()
        var macs = Set<String>()
        for (i, l) in lampes.enumerated() {
            let n = i + 1
            guard (0x0001...0x7FFF).contains(l.adresse) else { throw .adresse(lampe: n, l.adresse) }
            guard !Self.plageDuPont.contains(l.adresse) else { throw .adresseDuPont(lampe: n, l.adresse) }
            guard adresses.insert(l.adresse).inserted else { throw .adresseEnDouble(l.adresse) }
            guard Self.macValide(l.mac) else { throw .mac(lampe: n) }
            guard macs.insert(l.mac.uppercased()).inserted else { throw .macEnDouble(l.mac.uppercased()) }
            if let raison = Self.fauteNom(l.nom) { throw .nom(lampe: n, raison) }
        }
    }

    static func macValide(_ mac: String) -> Bool {
        mac.wholeMatch(of: /[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}/) != nil
    }

    /// Ce qui empeche un nom de passer tel quel : vide, plus de 31 octets, un
    /// caractere de controle.
    static func fauteNom(_ nom: String) -> String? {
        if nom.isEmpty { return "nom vide" }
        if nom.utf8.count > nomMax { return "nom de \(nom.utf8.count) octets, \(nomMax) au plus" }
        if nom.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }) {
            return "caractère de contrôle dans le nom"
        }
        return nil
    }

    /// Le nom en un seul argument de la console du pont (`esp_console_split_argv`) :
    /// entre guillemets, `"` et `\` echappes ; les espaces passent tels quels.
    static func argument(_ nom: String) -> String {
        "\"" + nom.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Les commandes du chargement (docs/PROTOCOLE-JSON.md 6.4) : `mesh cles`, `mesh
    /// lampes <N>`, puis une ligne par lampe, le code avant le nom. La premiere porte
    /// les cles : a soumettre en secret (Correlateur), jamais a afficher.
    public func commandes() -> [String] {
        func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined() }
        var c = ["mesh cles \(hex(cleReseau)) \(hex(cleApplication))", "mesh lampes \(lampes.count)"]
        for (i, l) in lampes.enumerated() {
            c.append("mesh lampe \(i + 1) 0x\(String(format: "%04X", l.adresse)) \(l.mac.uppercased()) \(l.code) "
                     + Self.argument(l.nom))
        }
        return c
    }

    /// Meme reseau et memes lampes (cles, puis adresse, MAC, nom et code de chaque lampe).
    public func memeContenu(que autre: ReseauMesh) -> Bool {
        cleReseau == autre.cleReseau && cleApplication == autre.cleApplication && lampes == autre.lampes
    }
}
````

`apps/macos/AmaranProtocole/Cles/BaseAmaranDesktop.swift` (contenu complet) :

````swift
// Lecture de la base d'amaran Desktop (spec 3b, section 5), en lecture seule : le
// fichier est lu en memoire, puis ouvert par SQLite depuis cette copie
// (sqlite3_deserialize) : rien ne s'ecrit jamais pres de la base, ni ailleurs sur
// le disque. Memes controles qu'outils/cles_amaran.py.
import Foundation
import SQLite3

public enum ErreurBase: Error, Sendable, Equatable, CustomStringConvertible {
    case introuvable
    case illisible(String)
    case reseaux(Int)
    case cle
    case aucuneLampe
    case lampe(adresse: String)

    public var description: String {
        switch self {
        case .introuvable: "Aucune base d'amaran Desktop (*/amaran.db) dans ce dossier."
        case .illisible(let raison): "Base d'amaran Desktop illisible (\(raison))."
        case .reseaux(let n): "\(n) réseaux dans la base d'amaran Desktop, 1 attendu."
        case .cle: "Clé illisible dans la base d'amaran Desktop."
        case .aucuneLampe: "Aucune lampe dans la base d'amaran Desktop."
        case .lampe(let a): "Lampe illisible dans la base d'amaran Desktop (adresse \(a))."
        }
    }
}

public enum BaseAmaranDesktop {
    /// Dossier d'amaran Desktop sur ce Mac (app sandboxee) : a proposer dans le
    /// panneau d'ouverture. Depuis le vrai dossier personnel : dans une app
    /// sandboxee, homeDirectoryForCurrentUser est le conteneur de l'app.
    public static var dossierHabituel: URL {
        let maison = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: maison, isDirectory: true)
            .appending(path: "Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop")
    }

    /// La base la plus recente du dossier : `*/amaran.db` (un sous-dossier par compte).
    public static func trouver(dans dossier: URL) throws(ErreurBase) -> URL {
        let fm = FileManager.default
        let sous = (try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)) ?? []
        let bases = sous.map { $0.appending(path: "amaran.db") }.filter { fm.fileExists(atPath: $0.path) }
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let plusRecente = bases.max(by: { date($0) < date($1) }) else { throw .introuvable }
        return plusRecente
    }

    /// Lit le reseau de la base. Le fichier lu est efface de la memoire apres usage.
    public static func lire(_ fichier: URL, maintenant: Date = Date()) throws(ErreurBase) -> ReseauMesh {
        var octets: Data
        do {
            octets = try Data(contentsOf: fichier)
        } catch {
            throw .illisible(error.localizedDescription)
        }
        defer { octets.resetBytes(in: 0..<octets.count) }
        return try lire(octets: octets, maintenant: maintenant)
    }

    /// Lit le reseau d'une base deja en memoire (tests : base factice).
    public static func lire(octets: Data, maintenant: Date = Date()) throws(ErreurBase) -> ReseauMesh {
        guard !octets.isEmpty else { throw .illisible("fichier vide") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw .illisible("sqlite3_open_v2")
        }
        // Copie geree ici : effacee, puis rendue, apres la fermeture.
        let taille = octets.count
        let tampon = UnsafeMutableRawPointer.allocate(byteCount: taille, alignment: 8)
        octets.copyBytes(to: tampon.assumingMemoryBound(to: UInt8.self), count: taille)
        defer {
            sqlite3_close(db)
            tampon.initializeMemory(as: UInt8.self, repeating: 0, count: taille)
            tampon.deallocate()
        }
        guard sqlite3_deserialize(db, "main", tampon.assumingMemoryBound(to: UInt8.self), Int64(taille),
                                  Int64(taille), UInt32(SQLITE_DESERIALIZE_READONLY)) == SQLITE_OK else {
            throw .illisible(String(cString: sqlite3_errmsg(db)))
        }
        return try lireReseau(db, maintenant: maintenant)
    }

    private static func lireReseau(_ db: OpaquePointer, maintenant: Date) throws(ErreurBase) -> ReseauMesh {
        let reseaux = try lignes(db, "select net_key, app_key from mesh where net_key is not null and app_key is not null")
        guard reseaux.count == 1 else { throw .reseaux(reseaux.count) }
        guard case .texte(let reseau)? = reseaux[0].first, case .texte(let application)? = reseaux[0].last,
              let cleReseau = Data(hex: reseau), let cleApplication = Data(hex: application) else { throw .cle }
        guard cleReseau.count == 16, cleApplication.count == 16 else { throw .cle }
        // `code` et `composition_data` : absentes d'une base plus ancienne, sans gravite.
        let colonnes = Set(try lignes(db, "pragma table_info(fixtures)").compactMap { l -> String? in
            if l.count > 1, case .texte(let nom) = l[1] { return nom }
            return nil
        })
        let extra = ["code", "composition_data"].map { colonnes.contains($0) ? $0 : "null" }.joined(separator: ", ")
        let fixtures = try lignes(db, "select node_address, mac_address, name, \(extra) from fixtures "
                                      + "where node_address is not null order by node_address")
        guard !fixtures.isEmpty else { throw .aucuneLampe }
        var lampes: [LampeReseau] = []
        for f in fixtures {
            guard f.count == 5, case .entier(let adresse) = f[0] else { throw .lampe(adresse: "?") }
            let a = String(adresse)
            guard (1...0x7FFF).contains(adresse) else { throw .lampe(adresse: a) }
            guard case .texte(let mac) = f[1], ReseauMesh.macValide(mac) else { throw .lampe(adresse: a) }
            guard case .texte(let nom) = f[2], !nom.isEmpty,
                  !nom.unicodeScalars.contains(where: { $0.value < 0x20 }) else { throw .lampe(adresse: a) }
            lampes.append(LampeReseau(adresse: UInt16(adresse), mac: mac.uppercased(), nom: nom,
                                      code: Self.code(f[3]), declarees: Self.capacitesDeclarees(f[4])))
        }
        return ReseauMesh(cleReseau: cleReseau, cleApplication: cleApplication, lampes: lampes,
                          source: .amaranDesktop, date: maintenant)
    }

    /// Code produit Sidus (colonne `code`, texte) ; 0 s'il manque ou n'est pas un nombre.
    static func code(_ v: Valeur) -> UInt32 {
        guard case .texte(let t) = v else { return 0 }
        let s = t.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.allSatisfy(\.isASCII), s.allSatisfy(\.isNumber) else { return 0 }
        return UInt32(s) ?? 0
    }

    // Modeles SIG serveurs qui disent une capacite dans la composition d'une lampe.
    static let modeleCTL: UInt16 = 0x1303  // Light CTL Server : temperature de couleur
    static let modeleHSL: UInt16 = 0x1307  // Light HSL Server : couleur

    /// Capacites au-dela de l'intensite que la lampe declare : `cct`, `couleur`.
    static func capacitesDeclarees(_ v: Valeur) -> [String] {
        guard case .texte(let t) = v else { return [] }
        let m = modelesSIG(Data(hex: t) ?? Data())
        return (m.contains(modeleCTL) ? ["cct"] : []) + (m.contains(modeleHSL) ? ["couleur"] : [])
    }

    /// Modeles SIG d'une composition (page 0) : numero de page, CID, PID, VID,
    /// CRPL, fonctions (2 octets chacun), puis chaque element : emplacement (2),
    /// nombre de modeles SIG (1) et vendeur (1), les modeles SIG (2 octets) et
    /// vendeur (4 octets). Vide si illisible.
    static func modelesSIG(_ d: Data) -> Set<UInt16> {
        let o = [UInt8](d)
        var modeles = Set<UInt16>()
        var i = 11
        while i + 4 <= o.count {
            let sig = Int(o[i + 2]), vendeur = Int(o[i + 3])
            i += 4
            guard i + 2 * sig + 4 * vendeur <= o.count else { return [] }
            for k in 0..<sig { modeles.insert(UInt16(o[i + 2 * k]) | UInt16(o[i + 2 * k + 1]) << 8) }
            i += 2 * sig + 4 * vendeur
        }
        return modeles
    }

    // MARK: - SQLite

    enum Valeur: Equatable {
        case entier(Int)
        case texte(String)
        case autre
    }

    private static func lignes(_ db: OpaquePointer, _ sql: String) throws(ErreurBase) -> [[Valeur]] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else {
            throw .illisible(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(st) }
        var resultat: [[Valeur]] = []
        while true {
            let r = sqlite3_step(st)
            if r == SQLITE_DONE { break }
            guard r == SQLITE_ROW else { throw .illisible(String(cString: sqlite3_errmsg(db))) }
            resultat.append((0..<sqlite3_column_count(st)).map { c -> Valeur in
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: .entier(Int(sqlite3_column_int64(st, c)))
                case SQLITE_TEXT: .texte(String(cString: sqlite3_column_text(st, c)))
                default: .autre
                }
            })
        }
        return resultat
    }
}

extension Data {
    /// Exactement 2 chiffres hexa par octet (casse libre) ; nil sinon.
    public init?(hex: String) {
        let c = Array(hex.utf8)
        guard c.count % 2 == 0 else { return nil }
        var o = [UInt8]()
        o.reserveCapacity(c.count / 2)
        func v(_ x: UInt8) -> UInt8? {
            switch x {
            case 0x30...0x39: x - 0x30
            case 0x41...0x46: x - 0x37
            case 0x61...0x66: x - 0x57
            default: nil
            }
        }
        var i = 0
        while i < c.count {
            guard let h = v(c[i]), let l = v(c[i + 1]) else { return nil }
            o.append(h << 4 | l)
            i += 2
        }
        self.init(o)
    }
}
````

`apps/macos/AmaranProtocole/Cles/Sauvegarde.swift` (contenu complet) :

````swift
// Sauvegarde chiffree du reseau (spec 3b, section 5) : la copie du trousseau, dans
// un fichier que Djoko range ou il veut (iCloud Drive conseille). AES-GCM 256, cle
// tiree de la phrase de passe par PBKDF2-HMAC-SHA256 (600 000 tours, sel aleatoire
// de 16 octets). L'en-tete (magie, version, tours, sel) est authentifie avec le
// contenu : rien n'y change sans que l'ouverture echoue.
import CommonCrypto
import CryptoKit
import Foundation

public enum ErreurSauvegarde: Error, Sendable, Equatable, CustomStringConvertible {
    case phraseTropCourte(Int)
    case phrasesDifferentes
    /// Phrase de passe fausse ou fichier altere : jamais de detail.
    case ouvertureImpossible
    case pasUneSauvegarde
    case versionInconnue(UInt8)

    public var description: String {
        switch self {
        case .phraseTropCourte(let n): "Phrase de passe trop courte : \(Sauvegarde.phraseMin) caractères au moins (\(n))."
        case .phrasesDifferentes: "Les deux phrases de passe diffèrent."
        case .ouvertureImpossible: "Phrase de passe fausse, ou fichier altéré."
        case .pasUneSauvegarde: "Ce fichier n'est pas une sauvegarde d'Amaran Compagnon."
        case .versionInconnue(let v): "Sauvegarde de version \(v) : cette app lit la version \(Sauvegarde.version)."
        }
    }
}

public enum Sauvegarde {
    public static let magie = Data("AMARANSV".utf8)
    public static let version: UInt8 = 1
    public static let toursParDefaut: UInt32 = 600_000
    public static let phraseMin = 12
    static let tailleSel = 16
    static let toursMax: UInt32 = 10_000_000

    /// Phrase de passe : 12 caracteres au moins, tapee deux fois.
    public static func verifierPhrase(_ phrase: String, confirmation: String) throws(ErreurSauvegarde) {
        guard phrase.count >= phraseMin else { throw .phraseTropCourte(phrase.count) }
        guard phrase == confirmation else { throw .phrasesDifferentes }
    }

    /// Chiffre le reseau. `tours` : 600 000 hors des tests.
    public static func chiffrer(_ reseau: ReseauMesh, phrase: String,
                                tours: UInt32 = toursParDefaut) throws -> Data {
        var sel = Data(count: tailleSel)
        let r = sel.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, tailleSel, $0.baseAddress!) }
        guard r == errSecSuccess else { throw ErreurSauvegarde.ouvertureImpossible }
        var tete = magie
        tete.append(version)
        withUnsafeBytes(of: tours.bigEndian) { tete.append(contentsOf: $0) }
        tete.append(sel)
        var clair = try JSONEncoder().encode(reseau)
        defer { clair.resetBytes(in: 0..<clair.count) }
        let cle = try deriver(phrase: phrase, sel: sel, tours: tours)
        let boite = try AES.GCM.seal(clair, using: cle, authenticating: tete)
        guard let scelle = boite.combined else { throw ErreurSauvegarde.ouvertureImpossible }
        return tete + scelle
    }

    /// Dechiffre et verifie l'integrite (en-tete compris).
    public static func dechiffrer(_ fichier: Data, phrase: String) throws(ErreurSauvegarde) -> ReseauMesh {
        let tailleTete = magie.count + 1 + 4 + tailleSel
        let f = Data(fichier)  // indices a partir de 0
        guard f.count > tailleTete, f.prefix(magie.count) == magie else { throw .pasUneSauvegarde }
        let v = f[magie.count]
        guard v == version else { throw .versionInconnue(v) }
        let tours = f[(magie.count + 1)..<(magie.count + 5)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard (1...toursMax).contains(tours) else { throw .ouvertureImpossible }
        let sel = f[(magie.count + 5)..<tailleTete]
        let tete = f.prefix(tailleTete)
        do {
            let cle = try deriver(phrase: phrase, sel: Data(sel), tours: tours)
            let boite = try AES.GCM.SealedBox(combined: f.suffix(from: tailleTete))
            var clair = try AES.GCM.open(boite, using: cle, authenticating: tete)
            defer { clair.resetBytes(in: 0..<clair.count) }
            return try JSONDecoder().decode(ReseauMesh.self, from: clair)
        } catch {
            throw .ouvertureImpossible
        }
    }

    /// PBKDF2-HMAC-SHA256, 32 octets.
    static func deriver(phrase: String, sel: Data, tours: UInt32) throws -> SymmetricKey {
        var cle = [UInt8](repeating: 0, count: 32)
        defer { cle.withUnsafeMutableBytes { _ = memset($0.baseAddress!, 0, $0.count) } }
        let mot = Array(phrase.utf8)
        guard !mot.isEmpty, !sel.isEmpty else { throw ErreurSauvegarde.ouvertureImpossible }
        let r = sel.withUnsafeBytes { s in
            mot.withUnsafeBufferPointer { m in
                m.baseAddress!.withMemoryRebound(to: Int8.self, capacity: m.count) { p in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p, m.count,
                                         s.bindMemory(to: UInt8.self).baseAddress, s.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), tours, &cle, cle.count)
                }
            }
        }
        guard r == kCCSuccess else { throw ErreurSauvegarde.ouvertureImpossible }
        return SymmetricKey(data: cle)
    }
}
````

- [ ] **Step 4 : la comparaison et la vérification d'un chargement.**

`apps/macos/AmaranProtocole/Cles/Comparaison.swift` (contenu complet) :

````swift
// Comparer sans rien montrer (spec 3b, section 5) : les empreintes et les lampes de
// la base d'amaran Desktop, de la copie du trousseau et du pont. Le panneau « Cles »
// nomme l'ecart et propose le geste qui convient.
import Foundation

/// Ce qu'une source montre du reseau, sans ses cles.
public struct ApercuReseau: Codable, Sendable, Equatable {
    public var empreinteReseau: String
    public var empreinteApplication: String
    public var lampes: [LampeReseau]
    /// Copie ou sauvegarde : sa source et sa date ; nil pour le pont.
    public var source: ReseauMesh.Source?
    public var date: Date?

    public init(empreinteReseau: String, empreinteApplication: String, lampes: [LampeReseau],
                source: ReseauMesh.Source? = nil, date: Date? = nil) {
        self.empreinteReseau = empreinteReseau
        self.empreinteApplication = empreinteApplication
        self.lampes = lampes
        self.source = source
        self.date = date
    }

    /// Ce que le pont montre (`config`, blocs `mesh` et `lampe`) ; nil sans cles.
    public static func dePont(mesh: ConfigMesh?, lampes: [Int: ConfigLampe]) -> ApercuReseau? {
        guard let mesh, mesh.cles == true, let r = mesh.empreintes?.reseau, let a = mesh.empreintes?.application
        else { return nil }
        let n = mesh.lampes ?? lampes.count
        let liste = (1...max(n, 1)).prefix(n).compactMap { i -> LampeReseau? in
            guard let c = lampes[i], let ad = c.adresse.flatMap({ UInt16($0, radix: 16) }), let mac = c.mac else { return nil }
            let deux = stride(from: 0, to: mac.count, by: 2).map { k -> String in
                let d = mac.index(mac.startIndex, offsetBy: k)
                return String(mac[d..<mac.index(d, offsetBy: 2, limitedBy: mac.endIndex)!])
            }
            return LampeReseau(adresse: ad, mac: deux.joined(separator: ":").uppercased(), nom: c.nom ?? "",
                               code: UInt32(clamping: c.code ?? 0))
        }
        return ApercuReseau(empreinteReseau: r, empreinteApplication: a, lampes: liste)
    }

    /// Memes cles et memes lampes (adresse, MAC, nom, code ; pas les capacites declarees).
    public func memeReseau(que autre: ApercuReseau) -> Bool {
        memesCles(que: autre) && Self.identites(lampes) == Self.identites(autre.lampes)
    }

    public func memesCles(que autre: ApercuReseau) -> Bool {
        empreinteReseau == autre.empreinteReseau && empreinteApplication == autre.empreinteApplication
    }

    static func identites(_ l: [LampeReseau]) -> [String] {
        l.map { "\($0.adresse) \($0.mac.uppercased()) \($0.nom) \($0.code)" }
    }
}

extension ReseauMesh {
    public var apercu: ApercuReseau {
        ApercuReseau(empreinteReseau: empreinteReseau, empreinteApplication: empreinteApplication, lampes: lampes,
                     source: source, date: date)
    }
}

/// Un ecart entre les sources, et le geste qui le resout.
public enum EcartCles: Sendable, Equatable {
    /// Aucune copie dans le trousseau : copier depuis amaran Desktop.
    case pasDeCopie
    /// Le pont n'a pas de cles : le charger.
    case pontSansCles
    /// Le pont n'a pas ce que garde le trousseau : le recharger.
    case pontDifferent
    /// amaran Desktop a d'autres cles : reseau recree ? Mettre le trousseau a jour,
    /// puis recharger le pont.
    case reseauRecree
    /// amaran Desktop a d'autres lampes : mettre le trousseau a jour.
    case lampesChangees

    public var texte: String {
        switch self {
        case .pasDeCopie: "Aucune copie des clés sur ce Mac : « Copier depuis amaran Desktop »."
        case .pontSansCles: "Le pont n'a pas de clés : « Charger le pont »."
        case .pontDifferent: "Le pont n'a pas les clés ou les lampes de la copie : « Charger le pont »."
        case .reseauRecree:
            "amaran Desktop a d'autres clés : réseau recréé ? « Copier depuis amaran Desktop », puis « Charger le pont »."
        case .lampesChangees:
            "amaran Desktop a d'autres lampes : « Copier depuis amaran Desktop », puis « Charger le pont »."
        }
    }
}

public enum ComparaisonCles {
    /// Les ecarts, du plus urgent au moins urgent. `pont` nil : pont sans cles ;
    /// `pontConnu` faux : aucun pont en mode machine (rien a dire de lui).
    public static func ecarts(base: ApercuReseau?, copie: ApercuReseau?, pont: ApercuReseau?,
                              pontConnu: Bool) -> [EcartCles] {
        var e: [EcartCles] = []
        if let base, let copie {
            if !base.memesCles(que: copie) {
                e.append(.reseauRecree)
            } else if !base.memeReseau(que: copie) {
                e.append(.lampesChangees)
            }
        }
        guard let copie else { return [.pasDeCopie] + e }
        if pontConnu {
            if let pont {
                if !pont.memeReseau(que: copie) { e.append(.pontDifferent) }
            } else {
                e.append(.pontSansCles)
            }
        }
        return e
    }

    /// Les lampes du pont (reconnues a leur MAC dans la base) dont une capacite
    /// declaree manque a celles que le pont leur connait, comme le signale
    /// outils/cles_amaran.py.
    public static func modelesACataloguer(base: ApercuReseau?, pont: [Int: ConfigLampe]) -> [ModeleACataloguer] {
        guard let base else { return [] }
        func cle(_ mac: String) -> String { mac.replacingOccurrences(of: ":", with: "").uppercased() }
        var r: [ModeleACataloguer] = []
        for (n, c) in pont.sorted(by: { $0.key < $1.key }) {
            guard let mac = c.mac, let l = base.lampes.first(where: { cle($0.mac) == cle(mac) }) else { continue }
            let connues = Set((c.capacites ?? []).map(\.rawValue))
            for capacite in ["cct", "couleur"] where l.declarees.contains(capacite) && !connues.contains(capacite) {
                r.append(ModeleACataloguer(lampe: n, nom: l.nom, code: l.code, capacite: capacite))
            }
        }
        return r
    }
}

/// Une lampe capable de plus que ce que le pont lui connait : pilotee en marche et
/// intensite seulement, tant que son modele n'est pas au catalogue du pont.
public struct ModeleACataloguer: Sendable, Equatable {
    public var lampe: Int
    public var nom: String
    public var code: UInt32
    /// `cct` ou `couleur`.
    public var capacite: String

    public init(lampe: Int, nom: String, code: UInt32, capacite: String) {
        self.lampe = lampe
        self.nom = nom
        self.code = code
        self.capacite = capacite
    }

    public var texte: String {
        let quoi = capacite == "cct" ? "la température de couleur" : "la couleur"
        return "Lampe \(lampe) (\(nom), code \(code)) : déclare \(quoi), que le pont ne lui connaît pas : "
            + "marche et intensité seulement, modèle à cataloguer."
    }
}
````

`apps/macos/AmaranProtocole/Cles/Chargement.swift` (contenu complet) :

````swift
// Chargement du pont par l'USB (spec 3b, section 5) : les quatre controles
// d'outils/cles_amaran.py, lus dans les reponses du pont (docs/PROTOCOLE-JSON.md 6.4).
import Foundation

public enum ErreurChargement: Error, Sendable, Equatable, CustomStringConvertible {
    case pasLePont
    case commande(String, String)
    case empreintes(rendues: String, attendues: String)
    case listeNonEnregistree
    case pasRedemarre
    case apresRedemarrage(String)

    public var description: String {
        switch self {
        case .pasLePont:
            "Ce port n'est pas un pont amaran en mode machine : rien n'a été envoyé."
        case .commande(let c, let raison):
            "« \(PolitiqueCommandes.masquerCle(c)) » : \(raison). Le pont n'est pas redémarré : relancer le chargement."
        case .empreintes(let r, let a):
            "Le pont a enregistré d'autres clés (empreintes \(r), attendues \(a)) : ne pas le redémarrer, relancer le chargement."
        case .listeNonEnregistree:
            "Le pont n'a pas enregistré la liste des lampes : ne pas le redémarrer, relancer le chargement."
        case .pasRedemarre:
            "Le pont n'a pas redémarré : vérifier l'onglet Clés après un redémarrage."
        case .apresRedemarrage(let ecart):
            "Après le redémarrage, le pont ne montre pas ce qui a été chargé : \(ecart)."
        }
    }
}

public enum VerificationChargement {
    /// `ok cles <EMPREINTE RESEAU> <EMPREINTE APPLICATION> (...)` : les empreintes rendues.
    public static func empreintesRendues(_ texte: [String]) -> (reseau: String, application: String)? {
        for l in texte {
            if let m = l.firstMatch(of: /ok cles ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8})(?:\s|$)/) {
                return (String(m.output.1).uppercased(), String(m.output.2).uppercased())
            }
        }
        return nil
    }

    /// Reponse a la derniere `mesh lampe` : `... ; liste de <N> lampe(s) enregistree (...)`.
    public static func listeEnregistree(_ texte: [String]) -> Int? {
        for l in texte {
            if let m = l.firstMatch(of: /; liste de (\d+) lampe\(s\) enregistree/) { return Int(m.output.1) }
        }
        return nil
    }

    /// Ce que le pont montre apres son redemarrage (`config`, blocs `mesh` et
    /// `lampe`), compare a ce qui a ete charge : nil s'il est identique.
    public static func ecart(_ attendu: ApercuReseau, mesh: ConfigMesh?, lampes: [Int: ConfigLampe]) -> String? {
        guard let pont = ApercuReseau.dePont(mesh: mesh, lampes: lampes) else { return "pas de clés" }
        guard pont.memesCles(que: attendu) else {
            return "empreintes \(pont.empreinteReseau) \(pont.empreinteApplication), attendues "
                + "\(attendu.empreinteReseau) \(attendu.empreinteApplication)"
        }
        guard pont.lampes.count == attendu.lampes.count else {
            return "\(pont.lampes.count) lampe(s), \(attendu.lampes.count) attendue(s)"
        }
        for (i, (p, a)) in zip(pont.lampes, attendu.lampes).enumerated()
        where ApercuReseau.identites([p]) != ApercuReseau.identites([a]) {
            return "lampe \(i + 1) différente"
        }
        return nil
    }
}
````

- [ ] **Step 5 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `Test run with 85 tests in 13 suites passed` et `Test run with 1 test in 0 suites passed`, puis `** TEST SUCCEEDED **`, sans avertissement.

> **Amendement (exécution, 05/10)** : la relecture (Opus) a montré que `ApercuReseau.dePont` faisait planter l'app sur des données du pont mal formées (MAC de longueur impaire, nombre de lampes négatif). Correctif en un commit à part : 0 à 16 lampes, une lampe ignorée sauf MAC de 12 chiffres hexa ; et la phrase de passe est normalisée en NFC avant PBKDF2 (format v1 fixé avant toute sauvegarde), ses octets effacés après usage. Deux tests de plus : `AmaranProtocoleTests` compte désormais 87 tests (les Tasks 8 et 9 aussi).

- [ ] **Step 6 : commit.**

```bash
git add apps/macos
git commit -m "$(printf "App compagnon : cles du reseau (base d'amaran Desktop en memoire, sauvegarde chiffree, chargement, comparaison)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 8: Le modèle `Pont` : port série, trousseau, chargement des clés, mode démo

**Files:**
- Create: `apps/macos/AmaranCompagnon/Serie/{PortSerie,SurveillantUSB,TransportSerie}.swift`
- Create: `apps/macos/AmaranCompagnon/Cles/Trousseau.swift`, `apps/macos/AmaranCompagnon/Modele/{Journal,Pont,Pont+Lampes,Pont+Cles}.swift`
- Create: `apps/macos/AmaranCompagnon/Demo/{ReseauDemo,SimulateurDemo,TransportDemo}.swift`
- Test: `apps/macos/AmaranCompagnonTests/DemoBoutEnBoutTests.swift`
- Delete: `apps/macos/AmaranCompagnonTests/LancementTests.swift`

**Interfaces:**
- Consumes : `AmaranProtocole` (Tasks 5 à 7).
- Produces (module `AmaranCompagnon`, interne ; la Task 9 s'en sert) :
  - `Pont` (`@MainActor @Observable final class`) : `init(trousseau:trousseauDemo:preferences:)` ; l'état publié : `source`, `ports`, `etatTransport`, `nomTransport`, `phase`, `etat` (`EtatPont`), `reception`, `statistiques`, `suivis`, `console` (`Borne<LigneConsole>`), `rejets`, `alerte`, `derniereReception`, `propositionFermeture`, `reglages`, `copie`, `base`, `erreurBase`, `dossierAmaran`, `chargement`, `derniereSauvegarde` ; les gestes : `connecter(_:)`, `deconnecter()`, `libererPort()`, `reconnecter()`, `reessayer()`, `envoyer(_:fusion:secret:) -> UUID?`, `curseur(_:cle:fini:)`, `console(_:confirme:) -> ResultatConsole`, `rafraichir()`, `viderConsole()` ; `peutCommander`, `consoleAvecId`, `estDemo`, `commandeDeBanc`, `sourceParDefaut`, `portsVisibles(_:)` ; `avancerPourUnTest(de:)` (tests) ;
  - `Pont.Source` (`serie(chemin:serie:)`, `demo`), `Pont.EtatTransport` (`ferme`, `ouverture`, `ouvert`, `attente(prochain:raison:)`, `libere`, `erreur`), `Pont.ResultatConsole` (`envoyee`, `confirmation`, `refusee`) ;
  - `Pont+Lampes` : `VueLampe` (`numero`, `config`, `etat`, `dernierOrdre`, `nom`, `dansMaison`), `lampes`, `allumer(lampe:_:)`, `niveau(lampe:pourCent:fini:)`, `relire(lampe:)`, `exposer(lampe:dansMaison:)`, `reglerReleve(secondes:)`, `testerVoyant(_:)`, `avertissementRetrait` ;
  - `Pont+Cles` : `EtatChargement` (`repos`, `enCours`, `attenteRedemarrage`, `reussi`, `echec` ; `actif`), `SourceCles` (`amaranDesktop`, `trousseau`), `autoriserDossier(_:)`, `relireBase()`, `copierDepuisAmaranDesktop()`, `apercuPont`, `ecartsCles`, `modelesACataloguer`, `chargerPont(depuis:)`, `interrompreChargement(_:)`, `exporterSauvegarde(vers:phrase:confirmation:)`, `lireSauvegarde(_:phrase:)`, `remplacerCopie(par:)` ;
  - `TrousseauReseau` (`apercu()`, `lire()`, `ranger(_:)`, `oublier()`), `TrousseauSysteme(service:)`, `TrousseauMemoire(_:)`, `ErreurTrousseau` ;
  - `LigneConsole` (`Genre`), `Rejet`, `Borne` ; `PortUSB` (`chemin`, `vid`, `pid`, `serie`, `produit`, `estEspressif`, `libelle`), `SurveillantUSB`, `TransportSerie(chemin:)`, `PortSerie` ;
  - `ReseauDemo.reseau`, `MemoireDemo`, `SimulateurDemo`, `TransportDemo(vitesse:)`.

Pourquoi : la spec 3b, sections 5, 8 et 9 ; les choix 10, 12 et 13 de ce plan.
- **Le port série** est celui de Halo Compagnon : accès exclusif (`TIOCEXCL`), DTR et RTS à 0 d'un seul appel (ouvrir le port ne redémarre pas le pont), réouverture après une ré-énumération USB, nouvelles tentatives à 0,3, 1, 2 et 5 s. Seuls les ports Espressif (VID 303A) sont proposés ; aucun n'est ouvert sans un clic.
- **Le trousseau** : un élément générique ; l'aperçu (empreintes, lampes, date) se lit sans les clés.
- **Le chargement** suit le choix 12 : les clés partent en secret, chaque étape est vérifiée avant la suivante (8 s au plus), puis `redemarre` (40 s au plus pour revenir), puis la comparaison de ce que le pont montre (`VerificationChargement.ecart`). Les pré-contrôles refusent avant tout envoi.
- **Le mode démo** : `SimulateurDemo` joue le pont, ligne à ligne, derrière `TransportDemo` : session, ordres (confirmé, déjà tenu), retrait et retour dans Maison, chargement avec redémarrage. Les tests de bout en bout passent par le vrai tramage, la vraie session et le vrai `Pont`, avec un trousseau en mémoire ; le vrai trousseau n'est testé que si `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1`.
- **La sandbox** : les tests hébergés tournent dans l'app, donc dans sa sandbox. `SandboxTests` vérifie que le panneau d'ouverture propose le vrai dossier d'amaran Desktop, et non un chemin dans le conteneur de l'app.

- [ ] **Step 1 : les tests de bout en bout, et le test provisoire s'en va.**

`apps/macos/AmaranCompagnonTests/DemoBoutEnBoutTests.swift` (contenu complet) :

````swift
// Bout en bout sans materiel (spec 3b, section 10) : le pont simule du mode demo, le
// tramage, la session, la correlation et le modele Pont, comme dans l'app. Le
// trousseau est en memoire : rien ne touche celui du Mac.
import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

/// Attend qu'une condition devienne vraie, au plus `delai` (repris de Halo Compagnon) :
/// pas de sommeil de duree fixe, qui casserait sur une machine chargee.
@MainActor
func attendre(_ delai: Duration = .seconds(15), _ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + delai
    while ContinuousClock.now < fin {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
func pontDemo(copie: ReseauMesh? = ReseauDemo.reseau) -> Pont {
    let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(copie),
                 preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
    p.vitesseDemo = 20
    p.connecter(.demo)
    return p
}

@MainActor
func connecte(_ p: Pont) async -> Bool {
    await attendre { p.phase == .connecte && p.etat.configLampes.count == 3 && !p.moteur.instantaneEnCours }
}

@Suite("Mode demo, bout en bout", .serialized)
@MainActor
struct DemoBoutEnBoutTests {
    @Test func connexionEtLampes() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.lampes.map(\.nom) == ["Lampe bureau", "Lumière fenêtre", "Lampe du fond"])
        #expect(p.lampes[0].etat?.lue == EtatLu(marche: true, intensite: 500))
        #expect(p.etat.capacites.contains("ordres"))
        // La lampe jamais vue repond au bout de 15 s simulees : elle entre dans Maison.
        #expect(await attendre { p.lampes[2].etat?.maison?.endpoint == 5 })
        #expect(p.console.elements.contains { $0.texte == "Lampe 3 : entre dans Maison (EP5)." })
    }

    @Test func ordresConfirmeEtDejaTenu() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.allumer(lampe: 1, false)
        #expect(await attendre { p.suivis.last?.etat == .confirmee })
        #expect(await attendre { p.lampes[0].etat?.lue?.marche == false })
        #expect(p.lampes[0].dernierOrdre?.issue == .confirme)
        p.allumer(lampe: 2, false)  // deja eteinte
        #expect(await attendre { p.suivis.last?.etat == .tenue })
        p.niveau(lampe: 1, pourCent: 73, fini: true)
        #expect(await attendre { p.lampes[0].etat?.lue?.intensite == 730 })
    }

    @Test func remettrePuisRetirerDeMaison() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.lampes[1].etat?.maison?.masquee == true, "la lampe 2 de la demo est retiree de Maison")
        p.exposer(lampe: 2, dansMaison: true)
        #expect(await attendre { p.lampes[1].etat?.maison?.endpoint == 3 }, "remise avec son numero")
        #expect(p.console.elements.contains { $0.texte == "Lampe 2 : remise dans Maison (EP3)." })
        p.exposer(lampe: 1, dansMaison: false)
        #expect(await attendre { p.lampes[0].etat?.maison?.masquee == true && p.lampes[0].etat?.maison?.endpoint == nil })
        #expect(p.console.elements.contains { $0.texte == "Lampe 1 : retirée de Maison." })
    }

    /// Charger le pont depuis la copie : quatre controles, redemarrage, comparaison.
    /// Les cles ne restent ni dans les suivis, ni dans la console.
    @Test func chargementDuPont() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.ecartsCles.isEmpty, "le pont simule a deja les cles de la copie")
        p.chargerPont(depuis: .trousseau)
        #expect(await attendre(.seconds(30)) {
            if case .reussi = p.chargement { return true }
            return false
        }, "chargement : \(p.chargement)")
        let cleHexa = ReseauDemo.reseau.commandes()[0].dropFirst("mesh cles ".count).prefix(32)
        #expect(!p.suivis.contains { $0.commande.contains(cleHexa) })
        #expect(!p.console.elements.contains { $0.texte.contains(cleHexa) })
        #expect(p.suivis.contains { $0.commande == "mesh cles •••••••• ••••••••" && $0.etat == .terminee })
        #expect(p.ecartsCles.isEmpty)
    }

    @Test func chargementRefuseParLesPreControles() async throws {
        var faux = ReseauDemo.reseau
        faux.lampes[1].adresse = 0x7F38
        let p = pontDemo(copie: faux)
        defer { p.deconnecter() }
        #expect(await connecte(p))
        let avant = p.suivis.count
        p.chargerPont(depuis: .trousseau)
        #expect(p.chargement == .echec(ErreurReseau.adresseDuPont(lampe: 2, 0x7F38).description))
        #expect(p.suivis.count == avant, "rien n'est envoye au pont")
    }

    @Test func sauvegardeExporteePuisImportee() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        let fichier = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sauvegarde")
        defer { try? FileManager.default.removeItem(at: fichier) }
        let phrase = "phrase de passe de test"
        #expect(throws: ErreurSauvegarde.phrasesDifferentes) {
            try p.exporterSauvegarde(vers: fichier, phrase: phrase, confirmation: phrase + ".")
        }
        try p.exporterSauvegarde(vers: fichier, phrase: phrase, confirmation: phrase)
        #expect(p.derniereSauvegarde != nil)
        var lue = try p.lireSauvegarde(fichier, phrase: phrase)
        #expect(lue.source == .sauvegarde)
        lue.source = .amaranDesktop
        #expect(lue == ReseauDemo.reseau)
        #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try p.lireSauvegarde(fichier, phrase: "une autre phrase") }
        try p.trousseauDemo.oublier()
        p.rafraichirCopie()
        #expect(p.copie == nil)
        try p.remplacerCopie(par: lue)
        #expect(p.copie?.memeReseau(que: ReseauDemo.reseau.apercu) == true)
    }
}

@Suite("Trousseau du reseau")
struct TrousseauTests {
    static func exercer(_ t: any TrousseauReseau) throws {
        try? t.oublier()
        #expect(try t.apercu() == nil)
        #expect(throws: ErreurTrousseau.absente) { try t.lire() }
        try t.ranger(ReseauDemo.reseau)
        #expect(try t.apercu() == ReseauDemo.reseau.apercu)
        #expect(try t.lire() == ReseauDemo.reseau)
        var autre = ReseauDemo.reseau
        autre.lampes.removeLast()
        try t.ranger(autre)
        #expect(try t.lire().lampes.count == 2, "remplacee, pas doublee")
        try t.oublier()
        #expect(try t.apercu() == nil)
        try t.oublier()  // deja oublie : sans erreur
    }

    @Test func enMemoire() throws {
        try Self.exercer(TrousseauMemoire())
    }

    /// Vrai trousseau (service de test, nettoye) : seulement sur demande,
    /// `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild ... test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMARAN_TEST_TROUSSEAU"] == "1"))
    func trousseauDuMac() throws {
        try Self.exercer(TrousseauSysteme(service: "fr.djoko.amaran.reseau.tests"))
    }
}

/// Les tests heberges tournent dans l'app, donc dans sa sandbox.
@Suite("Sandbox")
struct SandboxTests {
    /// Dans une app sandboxee, homeDirectoryForCurrentUser est le conteneur de l'app :
    /// le panneau d'ouverture doit proposer le vrai dossier d'amaran Desktop.
    @Test func dossierHabituelHorsDuConteneur() {
        let chemin = BaseAmaranDesktop.dossierHabituel.path
        #expect(!chemin.contains("/Containers/fr.djoko.amaran.compagnon"), "\(chemin)")
        #expect(chemin.hasSuffix("/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop"))
    }
}
````

```bash
git rm -q apps/macos/AmaranCompagnonTests/LancementTests.swift
```

- [ ] **Step 2 : lancer les tests, ils échouent.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `** TEST FAILED **` ; les tests ne compilent pas (`cannot find type 'Pont' in scope`, `cannot find 'TrousseauMemoire' in scope`, `cannot find 'ReseauDemo' in scope`…).

- [ ] **Step 3 : le port série.**

`apps/macos/AmaranCompagnon/Serie/PortSerie.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : textes en francais seulement.
import Darwin
import Foundation

/// Ouverture du port serie USB du C6 sans jamais le redemarrer (docs/PROTOCOLE-JSON.md 3.1).
///
/// Le peripherique USB Serial/JTAG lit DTR et RTS comme esptool : RTS=1 et
/// DTR=0, meme un instant, REDEMARRE LA PUCE. D'ou :
/// - DTR et RTS poses a 0 ensemble, en un seul `ioctl(TIOCMSET)`, juste apres
///   l'ouverture (passage direct 1,1 -> 0,0), et plus jamais touches ;
/// - `HUPCL` retire : a la fermeture, le pilote ne baisse pas DTR avant RTS.
enum PortSerie {
    // Macros de sys/ttycom.h non importees en Swift (_IO, _IOR, _IOW).
    /// `_IO('t', 13)` : acces exclusif (idf.py monitor ne pourra pas s'y attacher).
    static let tiocexcl: UInt = 0x2000_740D
    /// `_IOR('t', 106, int)` : lire les lignes de controle.
    static let tiocmget: UInt = 0x4004_746A
    /// `_IOW('t', 109, int)` : ecrire les lignes de controle, toutes a la fois.
    static let tiocmset: UInt = 0x8004_746D
    /// `_IOR('t', 115, int)` : octets encore dans la file de sortie du tty.
    static let tiocoutq: UInt = 0x4004_7473

    static let debit: speed_t = 115_200

    static func erreur(_ quoi: String) -> ErreurPort {
        ErreurPort(quoi: quoi, errno: errno)
    }

    /// Ouvre `/dev/cu.*` (jamais `/dev/tty.*`, qui attend DCD) ; renvoie le descripteur.
    static func ouvrir(_ chemin: String) throws -> Int32 {
        guard chemin.hasPrefix("/dev/cu.") else { throw ErreurPort(quoi: "chemin \(chemin) : /dev/cu.* attendu", errno: 0) }
        let fd = open(chemin, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw erreur("ouverture de \(chemin)") }
        do {
            // 1. Acces exclusif.
            guard ioctl(fd, tiocexcl) != -1 else { throw erreur("accès exclusif (TIOCEXCL)") }

            // 2. DTR = RTS = 0 dans un seul appel : jamais l'etat RTS=1, DTR=0.
            var lignes: Int32 = 0
            guard withUnsafeMutablePointer(to: &lignes, { ioctl(fd, tiocmget, $0) }) != -1 else {
                throw erreur("lecture de DTR et RTS (TIOCMGET)")
            }
            lignes &= ~(TIOCM_DTR | TIOCM_RTS)
            guard withUnsafeMutablePointer(to: &lignes, { ioctl(fd, tiocmset, $0) }) != -1 else {
                throw erreur("DTR et RTS à 0 (TIOCMSET)")
            }

            // 3. Mode brut, 8N1, CLOCAL | CREAD, HUPCL retire, 115200 (ignore par l'USB natif).
            var t = termios()
            guard tcgetattr(fd, &t) != -1 else { throw erreur("lecture des réglages (tcgetattr)") }
            cfmakeraw(&t)
            t.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
            t.c_cflag &= ~tcflag_t(HUPCL | PARENB | CSTOPB | CRTSCTS)
            t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
            guard cfsetspeed(&t, debit) != -1 else { throw erreur("débit (cfsetspeed)") }
            guard tcsetattr(fd, TCSANOW, &t) != -1 else { throw erreur("réglages (tcsetattr)") }
            return fd
        } catch {
            // Ouvrir a pose DTR = RTS = 1 : les baisser ensemble et retirer HUPCL
            // avant de fermer, pour que la fermeture ne passe jamais par RTS=1, DTR=0.
            desarmer(fd)
            close(fd)
            throw error
        }
    }

    /// Au mieux, sur un chemin d'erreur : DTR = RTS = 0 en un seul `TIOCMSET`, puis `HUPCL` retire.
    static func desarmer(_ fd: Int32) {
        var lignes: Int32 = 0
        if withUnsafeMutablePointer(to: &lignes, { ioctl(fd, tiocmget, $0) }) == -1 { lignes = 0 }
        lignes &= ~(TIOCM_DTR | TIOCM_RTS)
        _ = withUnsafeMutablePointer(to: &lignes, { ioctl(fd, tiocmset, $0) })
        var t = termios()
        if tcgetattr(fd, &t) != -1 {
            t.c_cflag &= ~tcflag_t(HUPCL)
            _ = tcsetattr(fd, TCSANOW, &t)
        }
    }

    /// Etat actuel de DTR et RTS (diagnostic).
    static func lignesDeControle(_ fd: Int32) -> (dtr: Bool, rts: Bool)? {
        var lignes: Int32 = 0
        guard withUnsafeMutablePointer(to: &lignes, { ioctl(fd, tiocmget, $0) }) != -1 else { return nil }
        return ((lignes & TIOCM_DTR) != 0, (lignes & TIOCM_RTS) != 0)
    }
}

struct ErreurPort: Error, CustomStringConvertible {
    var quoi: String
    var errno: Int32

    var description: String {
        guard errno != 0 else { return quoi }
        let detail = String(cString: strerror(errno))
        if errno == EBUSY {
            return "\(quoi) : port occupé (idf.py monitor, outils/console.py ou une autre app le tient)"
        }
        return "\(quoi) : \(detail)"
    }
}
````

`apps/macos/AmaranCompagnon/Serie/SurveillantUSB.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5), inchange.
import Foundation
import IOKit
import IOKit.serial

/// Un port serie vu par IOKit.
struct PortUSB: Identifiable, Hashable, Sendable {
    var id: String { chemin }
    /// `/dev/cu.*`
    let chemin: String
    let vid: Int?
    let pid: Int?
    /// Numero de serie USB : l'adresse MAC de la puce (3.1).
    let serie: String?
    let produit: String?

    /// VID Espressif : l'USB Serial/JTAG du C6 est 303A:1001.
    var estEspressif: Bool { vid == 0x303A }

    var libelle: String {
        var s = chemin.replacingOccurrences(of: "/dev/cu.", with: "")
        if let vid, let pid { s += String(format: " (%04X:%04X)", vid, pid) }
        if let serie, !serie.isEmpty { s += " · \(serie)" }
        return s
    }
}

/// Liste des ports et notifications d'arrivee et de depart (IOKit,
/// `IOServiceAddMatchingNotification` sur `IOSerialBSDClient`).
@MainActor
final class SurveillantUSB {
    static let vidEspressif = 0x303A

    /// Appele sur la file principale a chaque arrivee ou depart d'un port.
    var changement: (([PortUSB]) -> Void)?

    // Liberes aussi par deinit (non isole) : sans cela, un rappel IOKit viserait un objet detruit.
    nonisolated(unsafe) private var portNotification: IONotificationPortRef?
    nonisolated(unsafe) private var iterateurs: [io_iterator_t] = []

    deinit {
        for i in iterateurs { IOObjectRelease(i) }
        if let portNotification { IONotificationPortDestroy(portNotification) }
    }

    func demarrer() {
        guard portNotification == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        portNotification = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let contexte = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterateur: io_iterator_t = 0
            let resultat = IOServiceAddMatchingNotification(port, type, Self.critere(), { contexte, iterateur in
                // Rappel C, sur la file principale (IONotificationPortSetDispatchQueue).
                SurveillantUSB.vider(iterateur)
                guard let contexte else { return }
                MainActor.assumeIsolated {
                    let moi = Unmanaged<SurveillantUSB>.fromOpaque(contexte).takeUnretainedValue()
                    moi.changement?(SurveillantUSB.lister())
                }
            }, contexte, &iterateur)
            if resultat == KERN_SUCCESS {
                // Vider l'iterateur arme la notification.
                Self.vider(iterateur)
                iterateurs.append(iterateur)
            }
        }
    }

    func arreter() {
        for i in iterateurs { IOObjectRelease(i) }
        iterateurs.removeAll()
        if let portNotification { IONotificationPortDestroy(portNotification) }
        portNotification = nil
    }

    private nonisolated static func vider(_ iterateur: io_iterator_t) {
        while case let objet = IOIteratorNext(iterateur), objet != 0 {
            IOObjectRelease(objet)
        }
    }

    private nonisolated static func critere() -> CFDictionary {
        let d = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        d[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        return d as CFDictionary
    }

    /// Ports `/dev/cu.*`, ceux d'Espressif en tete.
    nonisolated static func lister() -> [PortUSB] {
        var iterateur: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, critere(), &iterateur) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterateur) }
        var ports: [PortUSB] = []
        while case let service = IOIteratorNext(iterateur), service != 0 {
            defer { IOObjectRelease(service) }
            guard let chemin = propriete(service, kIOCalloutDeviceKey, parents: false) as? String,
                  chemin.hasPrefix("/dev/cu.") else { continue }
            ports.append(PortUSB(
                chemin: chemin,
                vid: propriete(service, "idVendor") as? Int,
                pid: propriete(service, "idProduct") as? Int,
                serie: propriete(service, "USB Serial Number") as? String,
                produit: propriete(service, "USB Product Name") as? String))
        }
        return ports.sorted { a, b in
            if a.estEspressif != b.estEspressif { return a.estEspressif }
            return a.chemin < b.chemin
        }
    }

    private nonisolated static func propriete(_ service: io_object_t, _ cle: String, parents: Bool = true) -> Any? {
        if parents {
            return IORegistryEntrySearchCFProperty(service, kIOServicePlane, cle as CFString, kCFAllocatorDefault,
                                                   IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        }
        return IORegistryEntryCreateCFProperty(service, cle as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
````

`apps/macos/AmaranCompagnon/Serie/TransportSerie.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : textes en francais seulement.
import Darwin
import Foundation
import AmaranProtocole
import Synchronization

/// Transport USB : port serie POSIX lu par une source Dispatch.
///
/// Toutes les lectures et ecritures passent par une meme file serie : l'ordre
/// des lignes envoyees est garanti, et la file principale ne bloque jamais.
final class TransportSerie: Transport {
    let genre: GenreTransport = .usb
    let chemin: String
    var nom: String { chemin }

    private struct Etat {
        var fd: Int32 = -1
        var source: (any DispatchSourceRead)?
        var suite: AsyncStream<EvenementTransport>.Continuation?
    }

    private let file = DispatchQueue(label: "fr.djoko.amaran.serie", qos: .userInitiated)
    private let etat = Mutex(Etat())

    init(chemin: String) {
        self.chemin = chemin
    }

    func ouvrir() async throws -> AsyncStream<EvenementTransport> {
        let fd = try PortSerie.ouvrir(chemin)
        let (flux, suite) = AsyncStream.makeStream(of: EvenementTransport.self, bufferingPolicy: .unbounded)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: file)
        source.setEventHandler { [weak self] in self?.lire() }
        source.setCancelHandler {
            // DTR et RTS sont deja a 0 et HUPCL est retire : fermer ne change rien aux lignes.
            close(fd)
        }
        etat.withLock { e in
            e.fd = fd
            e.source = source
            e.suite = suite
        }
        suite.onTermination = { [weak self] _ in self?.fermer() }
        source.resume()
        return flux
    }

    /// Sur la file serie : tout ce qui est disponible.
    private func lire() {
        let fd = etat.withLock { $0.fd }
        guard fd >= 0 else { return }
        var tampon = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = tampon.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                let donnees = Data(tampon[0..<n])
                _ = etat.withLock { $0.suite?.yield(.donnees(donnees)) }
                continue
            }
            if n == 0 {
                terminer("port fermé (EOF) : le pont a peut-être redémarré")
                return
            }
            let code = errno
            if code == EAGAIN || code == EWOULDBLOCK { return }
            if code == EINTR { continue }
            terminer("lecture impossible : \(String(cString: strerror(code))) (ré-énumération USB ?)")
            return
        }
    }

    func envoyer(_ donnees: Data) throws {
        guard etat.withLock({ $0.fd }) >= 0 else { throw ErreurTransport("port fermé") }
        file.async { [weak self] in self?.ecrire(donnees) }
    }

    /// Sur la file serie. Ligne de 128 octets au plus : quelques essais si le tampon est plein.
    private func ecrire(_ donnees: Data) {
        let fd = etat.withLock { $0.fd }
        guard fd >= 0 else { return }
        var reste = donnees[...]
        var essais = 0
        while !reste.isEmpty {
            let n = reste.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                reste = reste.dropFirst(n)
                continue
            }
            let code = errno
            if n < 0, code == EAGAIN || code == EINTR, essais < 50 {
                essais += 1
                usleep(2000)
                continue
            }
            terminer("écriture impossible : \(String(cString: strerror(code)))")
            return
        }
    }

    private func terminer(_ raison: String) {
        let (source, suite) = etat.withLock { e -> ((any DispatchSourceRead)?, AsyncStream<EvenementTransport>.Continuation?) in
            let r = (e.source, e.suite)
            e.source = nil
            e.suite = nil
            e.fd = -1
            return r
        }
        source?.cancel()
        suite?.yield(.ferme(raison: raison))
        suite?.finish()
    }

    func fermer() {
        file.async { [weak self] in self?.terminer("port fermé par l'app") }
    }

    /// Le descripteur est `O_NONBLOCK` : a la fermeture, le tty jette ce qui
    /// n'est pas encore parti (`ttylclose`). Attendre donc que la file de
    /// sortie se vide (`TIOCOUTQ`, 300 ms au plus) avant de fermer.
    func fermerApresVidage(synchrone: Bool) {
        let travail: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.vider(delaiMax: .milliseconds(300))
            self.terminer("port fermé par l'app")
        }
        if synchrone { file.sync(execute: travail) } else { file.async(execute: travail) }
    }

    /// Sur la file serie, derriere les ecritures deja en file.
    private func vider(delaiMax: Duration) {
        let fd = etat.withLock { $0.fd }
        guard fd >= 0 else { return }
        let limite = ContinuousClock.now + delaiMax
        var reste: Int32 = 0
        while ContinuousClock.now < limite {
            guard withUnsafeMutablePointer(to: &reste, { ioctl(fd, PortSerie.tiocoutq, $0) }) != -1, reste > 0 else { break }
            usleep(5_000)
        }
        // Apres la file du tty, le pilote USB a encore ses tampons : un court delai de plus.
        usleep(20_000)
    }
}
````

- [ ] **Step 4 : le trousseau et le journal.**

`apps/macos/AmaranCompagnon/Cles/Trousseau.swift` (contenu complet) :

````swift
// Copie des cles dans le trousseau local du Mac (spec 3b, decision 4 et section 5),
// sur le modele de Trousseau.swift de Halo Compagnon (commit e114cd5) : element
// generique, sans groupe d'acces ni synchronisation, lie a la signature de l'app.
import AmaranProtocole
import Foundation
import Security
import Synchronization

/// La copie du reseau : un seul element. Les cles ne quittent le trousseau qu'au
/// dernier moment (chargement du pont, sauvegarde) ; l'apercu (empreintes, lampes,
/// date) se lit sans elles.
protocol TrousseauReseau: Sendable {
    func apercu() throws -> ApercuReseau?
    func lire() throws -> ReseauMesh
    func ranger(_ r: ReseauMesh) throws
    func oublier() throws
}

enum ErreurTrousseau: Error, Equatable, Sendable, CustomStringConvertible {
    case absente
    case systeme(Int32)
    case illisible

    var description: String {
        switch self {
        case .absente: "Aucune copie des clés sur ce Mac : « Copier depuis amaran Desktop »."
        case .systeme(let s): "Trousseau : \(SecCopyErrorMessageString(s, nil) as String? ?? String(s))"
        case .illisible: "Copie des clés illisible dans le trousseau."
        }
    }
}

/// Trousseau de session du Mac : mot de passe generique, service
/// `fr.djoko.amaran.reseau`, compte `reseau` ; valeur = les deux cles (32 octets) ;
/// attribut generique = l'apercu en JSON (sans cles) ; commentaire = les empreintes.
struct TrousseauSysteme: TrousseauReseau {
    let service: String
    static let compte = "reseau"

    init(service: String = "fr.djoko.amaran.reseau") {
        self.service = service
    }

    private var requete: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: Self.compte]
    }

    func apercu() throws -> ApercuReseau? {
        var q = requete
        q[kSecReturnAttributes as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
        guard let a = r as? [String: Any], let g = a[kSecAttrGeneric as String] as? Data,
              let apercu = try? JSONDecoder().decode(ApercuReseau.self, from: g) else { throw ErreurTrousseau.illisible }
        return apercu
    }

    func lire() throws -> ReseauMesh {
        var q = requete
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { throw ErreurTrousseau.absente }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
        guard let a = r as? [String: Any], var cles = a[kSecValueData as String] as? Data, cles.count == 32,
              let g = a[kSecAttrGeneric as String] as? Data,
              let apercu = try? JSONDecoder().decode(ApercuReseau.self, from: g) else { throw ErreurTrousseau.illisible }
        defer { cles.resetBytes(in: 0..<cles.count) }
        return ReseauMesh(cleReseau: Data(cles.prefix(16)), cleApplication: Data(cles.suffix(16)),
                          lampes: apercu.lampes, source: apercu.source ?? .amaranDesktop, date: apercu.date ?? Date())
    }

    func ranger(_ reseau: ReseauMesh) throws {
        var cles = reseau.cleReseau + reseau.cleApplication
        defer { cles.resetBytes(in: 0..<cles.count) }
        let apercu = try JSONEncoder().encode(reseau.apercu)
        let valeurs: [String: Any] = [
            kSecValueData as String: cles,
            kSecAttrGeneric as String: apercu,
            kSecAttrComment as String: "réseau \(reseau.empreinteReseau), application \(reseau.empreinteApplication)",
            kSecAttrLabel as String: "Amaran Compagnon - réseau des lampes",
        ]
        var s = SecItemUpdate(requete as CFDictionary, valeurs as CFDictionary)
        if s == errSecItemNotFound {
            s = SecItemAdd(requete.merging(valeurs) { $1 } as CFDictionary, nil)
        }
        guard s == errSecSuccess else { throw ErreurTrousseau.systeme(s) }
    }

    func oublier() throws {
        let s = SecItemDelete(requete as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw ErreurTrousseau.systeme(s) }
    }
}

/// Trousseau des tests et du mode demo : en memoire, isole du vrai.
final class TrousseauMemoire: TrousseauReseau {
    private let reseau = Mutex<ReseauMesh?>(nil)

    init(_ initial: ReseauMesh? = nil) {
        reseau.withLock { $0 = initial }
    }

    func apercu() throws -> ApercuReseau? { reseau.withLock { $0?.apercu } }

    func lire() throws -> ReseauMesh {
        guard let r = reseau.withLock({ $0 }) else { throw ErreurTrousseau.absente }
        return r
    }

    func ranger(_ r: ReseauMesh) throws { reseau.withLock { $0 = r } }

    func oublier() throws { reseau.withLock { $0 = nil } }
}
````

`apps/macos/AmaranCompagnon/Modele/Journal.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : la console et les rejets (les trames et
// les courbes viendront au plan 3b-2).
import AmaranProtocole
import Foundation

/// Ligne de la console.
struct LigneConsole: Identifiable, Sendable {
    enum Genre: Equatable, Sendable {
        /// Ligne envoyee par l'app.
        case envoi(OrigineCommande)
        /// Texte recu, classe (2.4).
        case texte(ClasseTexte)
        case fragment
        /// `reponse` ou `ordre` rendu lisible.
        case retour(ok: Bool, session: Bool)
        /// Message `log` (mode `json log 1`).
        case log
        /// Annonce de l'app elle-meme.
        case note(grave: Bool)
    }

    let id: Int
    let date: Date
    let genre: Genre
    let texte: String
    /// `id` de la commande a laquelle la ligne se rattache.
    let numero: Int?
}

/// Ligne machine rejetee (diagnostic du tableau de bord).
struct Rejet: Identifiable, Sendable {
    let id: Int
    let date: Date
    let raison: String
    let brut: String
}

/// Tableau borne : les plus anciens sortent.
struct Borne<Element> {
    private(set) var elements: [Element] = []
    let capacite: Int

    init(capacite: Int) { self.capacite = capacite }

    mutating func ajouter(_ e: Element) {
        elements.append(e)
        if elements.count > capacite + capacite / 10 { elements.removeFirst(elements.count - capacite) }
    }

    mutating func vider() { elements.removeAll() }
}

extension Borne: Sendable where Element: Sendable {}
````

- [ ] **Step 5 : le modèle `Pont`.**

`apps/macos/AmaranCompagnon/Modele/Pont.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : sources, reconnexion, session, console.
// Par l'USB seulement (Thread au plan 3b-2) ; les gestes des lampes et des cles sont
// dans Pont+Lampes.swift et Pont+Cles.swift.
import AmaranProtocole
import AppKit
import Foundation
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

        var estDemo: Bool { self == .demo }
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
    /// Annonce grave (ancien firmware, aucune reponse...) montree en bandeau.
    private(set) var alerte: MoteurSession.Note?
    private(set) var derniereReception: Date?
    /// Commande de la console du pont de plus de 20 min : proposer de fermer le port.
    var propositionFermeture = false
    /// Reglages de session en vigueur ; nil avant le `hello`.
    private(set) var reglages: HelloBase.ReglagesSession?
    /// Facteur de temps du mode demo (1 : temps reel ; les tests accelerent).
    @ObservationIgnored var vitesseDemo: Double = 1

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
    @ObservationIgnored private var genreTransport: GenreTransport?
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
    @ObservationIgnored private var observateurReveil: (any NSObjectProtocol)?
    @ObservationIgnored private var observateurFin: (any NSObjectProtocol)?
    /// Session serie ouverte : pas de mise en sommeil de l'app (App Nap) qui
    /// retarderait le ping au-dela du bail de 30 s.
    @ObservationIgnored private var activite: (any NSObjectProtocol)?

    /// Delais de reouverture apres une fermeture : 300 ms, puis 1 s, 2 s, 5 s (3.1).
    static let delaisReconnexion: [Double] = [0.3, 1, 2, 5]

    init(trousseau: any TrousseauReseau = TrousseauSysteme(), trousseauDemo: any TrousseauReseau = TrousseauMemoire(ReseauDemo.reseau),
         preferences: UserDefaults = .standard) {
        self.trousseau = trousseau
        self.trousseauDemo = trousseauDemo
        self.preferences = preferences
        ports = Self.portsVisibles(SurveillantUSB.lister())
        surveillant.changement = { [weak self] ports in self?.portsChanges(ports) }
        surveillant.demarrer()
        observateurReveil = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Pause de lecture : la premiere ligne lue ensuite peut etre un fragment (2.4).
                self?.recepteur.signalerPause()
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

    /// Source proposee par defaut : le premier port Espressif, sinon la demo.
    var sourceParDefaut: Source {
        if let p = ports.first(where: \.estEspressif) { return .serie(chemin: p.chemin, serie: p.serie) }
        return .demo
    }

    func connecter(_ s: Source) {
        let changement = s != source
        if changement {
            // Autre pont ou demo : le pont quitte retrouve la console texte, et rien de
            // l'ancienne source ne reste (ni etat, ni boot).
            fermerProprement()
            oublierSource()
        } else {
            fermerTransport()
        }
        source = s
        alerte = nil
        reconnexionAuto = true
        essaisReconnexion = 0
        if changement, let nom = nomSource {
            note("Nouvelle source : \(nom). États et console remis à zéro.")
        }
        rafraichirCopie()
        ouvrir()
    }

    func deconnecter() {
        reconnexionAuto = false
        fermerProprement()
        etatTransport = .ferme
    }

    /// "Liberer le port" (3.1) : `json 0`, fermeture, pas de reouverture avant un clic.
    func libererPort() {
        reconnexionAuto = false
        let modeMachine = rendModeTexte
        fermerProprement()
        etatTransport = .libere
        note(modeMachine
             ? "Port libéré : json 0 envoyé, port fermé. Flasher est possible ; « Reconnecter » pour reprendre."
             : "Port libéré : port fermé. Flasher est possible ; « Reconnecter » pour reprendre.")
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
        dernierCurseur = [:]
        propositionFermeture = false
        derniereReception = nil
        interrompreChargement("source changée")
        synchroniser()
    }

    private var nomSource: String? {
        switch source {
        case .serie(let chemin, _): chemin
        case .demo: "démo"
        case nil: nil
        }
    }

    func reconnecter() {
        guard source != nil else { return }
        reconnexionAuto = true
        essaisReconnexion = 0
        alerte = nil
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
            // Le meme pont (meme numero de serie USB) peut revenir sous un autre nom.
            let port = ports.first { serie != nil && $0.serie == serie } ?? ports.first { $0.chemin == chemin }
            t = TransportSerie(chemin: port?.chemin ?? chemin)
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
    }

    private func debutActivite() {
        guard activite == nil else { return }
        activite = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Session série du pont amaran : ping du bail")
    }

    private func finActivite() {
        guard let a = activite else { return }
        ProcessInfo.processInfo.endActivity(a)
        activite = nil
    }

    private func transportOuvert() {
        etatTransport = .ouvert
        debutActivite()
        recepteur.resynchroniser()
        note(genreTransport == .demo ? "Pont de démonstration ouvert." : "Port ouvert : \(nomTransport) (DTR = RTS = 0).")
        executer(moteur.ouvert(maintenant: maintenant()))
    }

    private func transportFerme(_ raison: String) {
        transport = nil
        finActivite()
        moteur.ferme(maintenant: maintenant())
        synchroniser()
        note("Transport fermé : \(raison)")
        if reconnexionAuto { planifierReconnexion(raison) } else { etatTransport = .ferme }
    }

    func echecOuverture(_ erreur: any Error) {
        transport = nil
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
        let revenu = nouveaux.contains { ($0.serie != nil && $0.serie == serie) || $0.chemin == chemin }
        if revenu {
            essaisReconnexion = 0
            planifierReconnexion("port revenu")
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

    private func traiter(_ element: ElementRecu) {
        let effets = moteur.recu(element, maintenant: maintenant())
        let historique = moteur.historique
        // Un redemarrage vide les etats derives AVANT d'appliquer la ligne qui l'a revele
        // (le hello du nouveau demarrage doit rester).
        let (redemarrages, autres) = effets.reduce(into: ([MoteurSession.Effet](), [MoteurSession.Effet]())) { r, e in
            if case .redemarrage = e { r.0.append(e) } else { r.1.append(e) }
        }
        executer(redemarrages)
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
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "version \(v) inconnue", brut: t))
        case .invalide(let t, let raison):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "\(t) invalide : \(raison)", brut: ""))
        case .debordement(let s):
            ajouterConsole(.texte(.commande), s)
        }
        executer(autres)
    }

    private func traiterMachine(_ l: LigneMachine, historique: Bool) {
        if !historique { etat.appliquer(l, recueA: Date()) }
        switch l.message {
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
                transport?.fermer()
            case .redemarrage(let ancien, let nouveau):
                etat.viderDerives()
                note("Redémarrage du pont détecté (boot \(ancien ?? "?") → \(nouveau ?? "?")) : états vidés.")
            case .note(let n):
                note(n.texte, grave: n.grave)
                if n.grave { alerte = n }
            case .commandeSansReponse(let id):
                if let s = moteur.correlateur.suivi(id) {
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   "‹ id=\(s.numero ?? 0) « \(s.commande) » : sans réponse sous 3 s (pas de réémission)",
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
                // Session retablie : l'alerte d'un echec passe ne vaut plus.
                alerte = nil
            }
        }
        let r = etat.helloBase != nil ? moteur.reglages : nil
        if reglages != r { reglages = r }
        if suivis != moteur.correlateur.suivis { suivis = moteur.correlateur.suivis }
        if statistiques != moteur.statistiques { statistiques = moteur.statistiques }
        if reception != recepteur.compteurs { reception = recepteur.compteurs }
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

    // MARK: - Commandes

    var peutCommander: Bool { phase.modeMachine && transport != nil }

    /// La console envoie avec un `id` : session machine, ou `json 1` en attente de
    /// son `hello`. Sinon (ancien firmware, console texte...) : ligne brute.
    var consoleAvecId: Bool {
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
        let (id, effets) = moteur.soumettre(commande, origine: .interface, fusion: fusion, secret: secret,
                                            maintenant: maintenant())
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

    /// Console brute : regles de 2.5, confirmations et interdits de 6.4.
    func console(_ ligne: String, confirme: Bool = false) -> ResultatConsole {
        switch PolitiqueCommandes.verdictConsole(ligne) {
        case .interdite(let raison):
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

    // MARK: - Lectures pour les ecrans

    var estDemo: Bool { source?.estDemo ?? false }

    /// Commande de la console du pont en cours (`reponse debut` recue, pas de `fin`).
    var commandeDeBanc: SuiviCommande? {
        suivis.last { $0.etat == .enCours }
    }
}
````

`apps/macos/AmaranCompagnon/Modele/Pont+Lampes.swift` (contenu complet) :

````swift
// Gestes des lampes (docs/PROTOCOLE-JSON.md 6.4) : marche, arret, niveau, relecture,
// retrait de Maison et retour, periode de relecture, voyant.
import AmaranProtocole
import Foundation

/// Ce que l'ecran montre d'une lampe : sa config (identite) et son etat.
struct VueLampe: Identifiable, Equatable {
    let numero: Int
    let config: ConfigLampe?
    let etat: BlocLampe?
    let dernierOrdre: EvenementOrdre?
    var id: Int { numero }

    var nom: String { config?.nom ?? "Lampe \(numero)" }
    var dansMaison: Bool { etat?.maison?.endpoint != nil }
}

extension Pont {
    /// Les lampes de la liste du pont, dans l'ordre.
    var lampes: [VueLampe] {
        etat.numerosLampes.map { n in
            VueLampe(numero: n, config: etat.configLampes[n]?.valeur, etat: etat.lampes[n]?.valeur,
                     dernierOrdre: etat.derniersOrdres[n]?.valeur)
        }
    }

    func allumer(lampe n: Int, _ marche: Bool) {
        envoyer("lampe \(n) \(marche ? "on" : "off")")
    }

    /// Niveau en pour cent (le pont garde le pour cent entier) : 0 a 1000 sur le fil.
    func niveau(lampe n: Int, pourCent: Int, fini: Bool) {
        curseur("lampe \(n) niveau \(max(0, min(100, pourCent)) * 10)", cle: "niveau\(n)", fini: fini)
    }

    func relire(lampe n: Int) {
        envoyer("lampe \(n) releve")
    }

    /// Retirer de Maison (apres la confirmation de l'ecran), ou remettre.
    func exposer(lampe n: Int, dansMaison: Bool) {
        envoyer("mesh lampe \(n) \(dansMaison ? "afficher" : "masquer")")
    }

    /// Periode de relecture des lampes, en secondes (1 a 60).
    func reglerReleve(secondes: Int) {
        envoyer("mesh releve \(max(1, min(60, secondes)))")
    }

    func testerVoyant(_ oui: Bool) {
        envoyer(oui ? "led test" : "led stop")
    }

    /// Texte de la confirmation de « Retirer de Maison » (spec 3b, decision 7 ; banc 2
    /// du plan 3a).
    static let avertissementRetrait = """
        Maison retire la tuile de la lampe. Remise, elle reviendra comme un nouvel accessoire : \
        son nom dans Maison, sa pièce si elle diffère de celle du pont, ses scènes et ses \
        automatisations seront perdus.
        """
}
````

`apps/macos/AmaranCompagnon/Modele/Pont+Cles.swift` (contenu complet) :

````swift
// Gestes des cles (spec 3b, section 5) : dossier d'amaran Desktop, copie dans le
// trousseau, chargement du pont par l'USB, sauvegarde chiffree. Les cles ne sont
// jamais affichees, journalisees ni copiees ; elles sont lues au dernier moment.
import AmaranProtocole
import Foundation

/// Ou en est le chargement du pont.
enum EtatChargement: Equatable, Sendable {
    case repos
    case enCours(String)
    case attenteRedemarrage
    case reussi(Date)
    case echec(String)

    var actif: Bool {
        switch self {
        case .enCours, .attenteRedemarrage: true
        default: false
        }
    }
}

/// D'ou viennent les cles a charger.
enum SourceCles: Sendable {
    case amaranDesktop
    case trousseau
}

/// Chargement en cours : les commandes restantes (la premiere porte les cles, et
/// n'est gardee que jusqu'a sa soumission), ce que le pont doit montrer ensuite.
struct ChargementEnCours {
    var attendu: ApercuReseau
    var restantes: [String]
    var etape = 0
    var suivi: UUID?
    var commandeSuivie = ""
    var bootAvant: String?
    var redemarrageDepuis: TimeInterval?
    var etapeDepuis: TimeInterval
}

extension Pont {
    static let cleSignet = "dossierAmaranDesktop"
    static let cleSauvegarde = "derniereSauvegarde"
    /// Delais du chargement : une etape (reponse du pont), puis le redemarrage.
    static let delaiEtape: TimeInterval = 8
    static let delaiRedemarrage: TimeInterval = 40

    /// Trousseau en vigueur : celui de la demo en mode demo.
    var trousseauCourant: any TrousseauReseau { estDemo ? trousseauDemo : trousseau }

    func chargerPreferencesCles() {
        if let t = preferences.object(forKey: Self.cleSauvegarde) as? Date { derniereSauvegarde = t }
        dossierAmaran = resoudreSignet()
        rafraichirCopie()
    }

    /// Relit l'apercu de la copie (sans ses cles).
    func rafraichirCopie() {
        do {
            copie = try trousseauCourant.apercu()
        } catch {
            copie = nil
            note(String(describing: error), grave: true)
        }
    }

    // MARK: - Dossier d'amaran Desktop (signet)

    /// Le dossier choisi dans le panneau d'ouverture : l'app en garde un signet.
    func autoriserDossier(_ url: URL) {
        do {
            let signet = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.set(signet, forKey: Self.cleSignet)
            dossierAmaran = url
            relireBase()
        } catch {
            erreurBase = "Signet du dossier impossible : \(error.localizedDescription)"
        }
    }

    private func resoudreSignet() -> URL? {
        guard let signet = preferences.data(forKey: Self.cleSignet) else { return nil }
        var perime = false
        guard let url = try? URL(resolvingBookmarkData: signet, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &perime) else { return nil }
        if perime, let neuf = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
            preferences.set(neuf, forKey: Self.cleSignet)
        }
        return url
    }

    /// Lit la base d'amaran Desktop (ou le reseau de demonstration). Les cles lues
    /// doivent etre effacees par l'appelant des qu'il en a fini.
    private func lireBaseAmaran() throws -> ReseauMesh {
        if estDemo { return ReseauDemo.reseau }
        guard let dossier = dossierAmaran else {
            throw ErreurCles("Dossier d'amaran Desktop non autorisé : Réglages, « Changer… ».")
        }
        let acces = dossier.startAccessingSecurityScopedResource()
        defer { if acces { dossier.stopAccessingSecurityScopedResource() } }
        return try BaseAmaranDesktop.lire(try BaseAmaranDesktop.trouver(dans: dossier))
    }

    /// Relit la base pour la comparer (apercu seulement).
    func relireBase() {
        do {
            var r = try lireBaseAmaran()
            base = r.apercu
            erreurBase = nil
            effacer(&r)
        } catch {
            base = nil
            erreurBase = String(describing: error)
        }
    }

    /// « Copier depuis amaran Desktop » : la base remplace la copie du trousseau.
    func copierDepuisAmaranDesktop() {
        do {
            var r = try lireBaseAmaran()
            defer { effacer(&r) }
            try trousseauCourant.ranger(r)
            base = r.apercu
            erreurBase = nil
            rafraichirCopie()
            note("Clés copiées depuis amaran Desktop dans le trousseau (empreintes \(r.empreinteReseau) \(r.empreinteApplication), \(r.lampes.count) lampe(s)).")
        } catch {
            erreurBase = String(describing: error)
            note(String(describing: error), grave: true)
        }
    }

    // MARK: - Chargement du pont

    /// Le pont tel que la config le montre, sans ses cles (nil : pas de cles).
    var apercuPont: ApercuReseau? {
        ApercuReseau.dePont(mesh: etat.mesh?.valeur, lampes: etat.configLampes.mapValues(\.valeur))
    }

    /// Ecarts entre la base, la copie et le pont (panneau « Cles »).
    var ecartsCles: [EcartCles] {
        ComparaisonCles.ecarts(base: base, copie: copie, pont: apercuPont, pontConnu: etat.mesh != nil)
    }

    /// Lampes du pont que la base (ou, sans elle, la copie) dit capables de plus.
    var modelesACataloguer: [ModeleACataloguer] {
        ComparaisonCles.modelesACataloguer(base: base ?? copie, pont: etat.configLampes.mapValues(\.valeur))
    }

    /// « Charger le pont » : pre-controles, puis `mesh cles`, `mesh lampes`, une ligne
    /// par lampe, chacune verifiee avant la suivante, puis `redemarre` et la
    /// comparaison de ce que le pont montre apres (spec 3b, section 5).
    func chargerPont(depuis source: SourceCles) {
        guard !chargement.actif else { return }
        guard peutCommander, etat.capacites.contains("mesh") else {
            chargement = .echec(ErreurChargement.pasLePont.description)
            return
        }
        do {
            var r = try source == .amaranDesktop ? lireBaseAmaran() : trousseauCourant.lire()
            defer { effacer(&r) }
            try r.verifier()
            charge = ChargementEnCours(attendu: r.apercu, restantes: r.commandes(), etapeDepuis: maintenant())
            chargement = .enCours("clés")
            note("Chargement du pont : \(r.lampes.count) lampe(s), empreintes \(r.empreinteReseau) \(r.empreinteApplication).")
            avancerChargement()
        } catch {
            chargement = .echec(String(describing: error))
        }
    }

    /// Un pas du chargement : verifie l'etape finie, soumet la suivante. Appele a
    /// chaque ligne recue et a chaque tic.
    func avancerChargement() {
        guard !chargementAvance, var c = charge else { return }
        chargementAvance = true
        defer { chargementAvance = false }
        let t = maintenant()
        if let depuis = c.redemarrageDepuis {
            // Le pont doit revenir avec un autre boot, et montrer ce qui a ete charge.
            if let boot = etat.boot, boot != c.bootAvant, let mesh = etat.mesh?.valeur,
               etat.configLampes.count >= (mesh.lampes ?? 0) {
                if let e = VerificationChargement.ecart(c.attendu, mesh: mesh, lampes: etat.configLampes.mapValues(\.valeur)) {
                    finirChargement(.echec(ErreurChargement.apresRedemarrage(e).description))
                } else {
                    finirChargement(.reussi(Date()))
                    note("Pont chargé et redémarré : il montre les clés et les lampes de la copie.")
                }
            } else if t - depuis > Self.delaiRedemarrage {
                finirChargement(.echec(ErreurChargement.pasRedemarre.description))
            }
            return
        }
        if let id = c.suivi {
            guard let s = moteur.correlateur.suivi(id) else {
                return finirChargement(.echec(ErreurChargement.commande(c.commandeSuivie, "suivi perdu").description))
            }
            if !s.etat.estFinal {
                if t - c.etapeDepuis > Self.delaiEtape {
                    finirChargement(.echec(ErreurChargement.commande(c.commandeSuivie, "pas de réponse").description))
                }
                return
            }
            if let erreur = verifierEtape(c, s) { return finirChargement(.echec(erreur.description)) }
            c.suivi = nil
        }
        guard peutCommander else { return }
        if c.restantes.isEmpty {
            // Dernier controle : le redemarrage, puis ce que le pont montre.
            c.bootAvant = etat.boot
            c.redemarrageDepuis = t
            charge = c
            chargement = .attenteRedemarrage
            envoyer("redemarre")
            return
        }
        let commande = c.restantes.removeFirst()
        let secret = c.etape == 0
        c.commandeSuivie = secret ? PolitiqueCommandes.masquerCle(commande) : commande
        c.suivi = envoyer(commande, secret: secret)
        c.etape += 1
        c.etapeDepuis = t
        charge = c
        chargement = .enCours(c.etape == 1 ? "clés" : c.etape == 2 ? "liste" : "lampe \(c.etape - 2) sur \(c.attendu.lampes.count)")
    }

    /// Les controles d'une etape finie : reponse ok, empreintes rendues, liste enregistree.
    private func verifierEtape(_ c: ChargementEnCours, _ s: SuiviCommande) -> ErreurChargement? {
        guard s.etat == .terminee, s.fin?.ok == true else {
            let raison = s.fin.map { Interpretation.code($0.code) } ?? "pas de réponse"
            return .commande(c.commandeSuivie, s.texte.last ?? raison)
        }
        if c.etape == 1 {
            let attendues = "\(c.attendu.empreinteReseau) \(c.attendu.empreinteApplication)"
            guard let e = VerificationChargement.empreintesRendues(s.texte) else {
                return .commande(c.commandeSuivie, "réponse sans empreintes")
            }
            let rendues = "\(e.reseau) \(e.application)"
            if rendues != attendues { return .empreintes(rendues: rendues, attendues: attendues) }
        }
        if c.etape == c.attendu.lampes.count + 2, VerificationChargement.listeEnregistree(s.texte) != c.attendu.lampes.count {
            return .listeNonEnregistree
        }
        return nil
    }

    private func finirChargement(_ e: EtatChargement) {
        charge = nil
        chargement = e
        if case .echec(let raison) = e { note(raison, grave: true) }
    }

    /// La connexion ne portera plus le chargement (source changee...).
    func interrompreChargement(_ raison: String) {
        guard let c = charge, c.redemarrageDepuis == nil else { return }
        finirChargement(.echec("Chargement interrompu (\(raison)) : relancer « Charger le pont »."))
    }

    // MARK: - Sauvegarde chiffree

    /// « Exporter une sauvegarde » : la copie du trousseau, chiffree.
    func exporterSauvegarde(vers url: URL, phrase: String, confirmation: String) throws {
        try Sauvegarde.verifierPhrase(phrase, confirmation: confirmation)
        var r = try trousseauCourant.lire()
        defer { effacer(&r) }
        let fichier = try Sauvegarde.chiffrer(r, phrase: phrase)
        try fichier.write(to: url, options: .atomic)
        derniereSauvegarde = Date()
        preferences.set(derniereSauvegarde, forKey: Self.cleSauvegarde)
        note("Sauvegarde chiffrée exportée (empreintes \(r.empreinteReseau) \(r.empreinteApplication)).")
    }

    /// « Importer une sauvegarde » : dechiffrer et verifier, sans rien remplacer.
    func lireSauvegarde(_ url: URL, phrase: String) throws -> ReseauMesh {
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        var r = try Sauvegarde.dechiffrer(try Data(contentsOf: url), phrase: phrase)
        r.source = .sauvegarde
        return r
    }

    /// Remplace la copie du trousseau, apres confirmation.
    func remplacerCopie(par r: ReseauMesh) throws {
        try trousseauCourant.ranger(r)
        rafraichirCopie()
        note("Copie du trousseau remplacée par la sauvegarde (empreintes \(r.empreinteReseau) \(r.empreinteApplication)).")
    }

    /// Efface les cles d'un reseau lu, au mieux.
    func effacer(_ r: inout ReseauMesh) {
        r.cleReseau.resetBytes(in: 0..<r.cleReseau.count)
        r.cleApplication.resetBytes(in: 0..<r.cleApplication.count)
    }
}

/// Erreur lisible des gestes des cles.
struct ErreurCles: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
````

- [ ] **Step 6 : le mode démo.** Uniquement des valeurs inventées : MAC `02:00:00:00:0D:01` à `03`, clés en suites d'octets (`A0` à `AF`, `C0` à `CF`).

`apps/macos/AmaranCompagnon/Demo/ReseauDemo.swift` (contenu complet) :

````swift
// Le reseau du mode demo (spec 3b, section 8) : des cles et des MAC inventees,
// jamais celles de Djoko. Le trousseau de la demo en garde la copie ; le pont
// simule l'a chargee.
import AmaranProtocole
import Foundation

enum ReseauDemo {
    static let reseau = ReseauMesh(
        cleReseau: Data((0..<16).map { 0xA0 &+ UInt8($0) }),
        cleApplication: Data((0..<16).map { 0xC0 &+ UInt8($0) }),
        lampes: [
            LampeReseau(adresse: 0x0002, mac: "02:00:00:00:0D:01", nom: "Lampe bureau", code: 40065),
            LampeReseau(adresse: 0x0004, mac: "02:00:00:00:0D:02", nom: "Lumière fenêtre", code: 40065),
            LampeReseau(adresse: 0x0006, mac: "02:00:00:00:0D:03", nom: "Lampe du fond", code: 40065),
        ],
        source: .amaranDesktop,
        date: Date(timeIntervalSinceReferenceDate: 812_000_000))
}
````

`apps/macos/AmaranCompagnon/Demo/SimulateurDemo.swift` (contenu complet) :

````swift
// Pont simule du mode demo (spec 3b, section 8), sur le modele de SimulateurDemo de
// Halo Compagnon (commit e114cd5) : trois lampes (une dans Maison allumee, une
// eteinte et retiree de Maison, une jamais vue qui y entre a sa premiere reponse). Il
// repond comme le firmware (docs/PROTOCOLE-JSON.md) ; il sert aussi aux tests de bout
// en bout.
import AmaranProtocole
import Foundation

/// Memoire du pont simule (sa NVS) : elle survit a ses redemarrages.
struct MemoireDemo: Sendable {
    struct Lampe: Sendable, Equatable {
        var adresse: UInt16
        var mac: String
        var nom: String
        var code: UInt32
        var endpoint: Int?
        var vue: Bool
        var masquee = false
    }

    var empreintes: (reseau: String, application: String)?
    var lampes: [Lampe]
    var releveMs = 2000
    var prochainEndpoint = 5
    /// Chargement en cours (`mesh cles`, `mesh lampes`, `mesh lampe`) : effet au redemarrage.
    var clesChargees: (reseau: String, application: String)?
    var brouillon: [Int: Lampe] = [:]
    var attendues = 0
    var listeChargee: [Lampe]?

    static var initiale: MemoireDemo {
        let r = ReseauDemo.reseau
        func l(_ i: Int, ep: Int?, vue: Bool, masquee: Bool = false) -> Lampe {
            let x = r.lampes[i]
            return Lampe(adresse: x.adresse, mac: x.mac, nom: x.nom, code: x.code, endpoint: ep, vue: vue, masquee: masquee)
        }
        return MemoireDemo(empreintes: (r.empreinteReseau, r.empreinteApplication),
                           lampes: [l(0, ep: 2, vue: true), l(1, ep: 3, vue: true, masquee: true), l(2, ep: nil, vue: false)])
    }

    /// Redemarrage : les cles et la liste chargees s'appliquent ; une MAC connue garde
    /// son numero et ses drapeaux (liste_fusionner).
    mutating func appliquerChargement() {
        if let c = clesChargees { empreintes = c }
        if let nouvelle = listeChargee {
            lampes = nouvelle.map { n in
                guard let a = lampes.first(where: { $0.mac == n.mac }) else { return n }
                var x = n
                x.endpoint = a.endpoint
                x.vue = a.vue
                x.masquee = a.masquee
                return x
            }
        }
        clesChargees = nil
        listeChargee = nil
        brouillon = [:]
        attendues = 0
    }
}

/// Valeur JSON ordonnee, en UTF-8 (2.2) : comme l'ecrivain du firmware.
indirect enum J: Sendable {
    case i(Int)
    case b(Bool)
    case s(String?)
    case a([J])
    case o([(String, J)])

    var texte: String {
        switch self {
        case .i(let v): String(v)
        case .b(let v): v ? "true" : "false"
        case .s(let v): v.map(Self.chaine) ?? "null"
        case .a(let v): "[" + v.map(\.texte).joined(separator: ",") + "]"
        case .o(let v): "{" + v.map { Self.chaine($0.0) + ":" + $0.1.texte }.joined(separator: ",") + "}"
        }
    }

    static func chaine(_ s: String) -> String {
        var r = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            default: r += u.value < 0x20 || u.value == 0x7F ? "?" : String(u)
            }
        }
        return r + "\""
    }
}

actor SimulateurDemo {
    private struct LampeSim {
        var entendue: Bool
        var marche: Bool
        var intensite: Int
        var reponseMs: UInt32?
        var repondues = 0
        var consigne: (marche: Bool?, intensite: Int?)?
        var ids: [Int] = []
    }

    private let sortie: AsyncStream<EvenementTransport>.Continuation
    private let boot: String
    private let vitesse: Double
    private let sauver: @Sendable (MemoireDemo) -> Void
    private var memoire: MemoireDemo
    private let depart = ContinuousClock.now
    private var n: UInt32 = 0
    private var machine = false
    private var bailS = 30
    private var dernierRx: TimeInterval = 0
    private var log = false
    private var periodes = (etat: 1000, lampes: 10000, compteurs: 1000, reseau: 5000)
    private var prochains = (etat: 0.0, lampes: 0.0, compteurs: 0.0, reseau: 0.0, regard: 0.0)
    private var lampes: [LampeSim]
    private var montrees: [String] = []
    private var tampon: [UInt8] = []
    private var ordres = (total: 0, confirmes: 0, abandons: 0, tenus: 0, delai: 0)
    private var ferme = false

    init(sortie: AsyncStream<EvenementTransport>.Continuation, boot: String, vitesse: Double, memoire: MemoireDemo,
         sauver: @escaping @Sendable (MemoireDemo) -> Void) {
        self.sortie = sortie
        self.boot = boot
        self.vitesse = vitesse
        self.memoire = memoire
        self.sauver = sauver
        lampes = memoire.lampes.enumerated().map { i, l in
            LampeSim(entendue: l.vue, marche: i == 0, intensite: i == 0 ? 500 : 600)
        }
    }

    /// Secondes simulees depuis le demarrage du pont simule.
    private var t: TimeInterval { reel * vitesse }
    /// Secondes reelles : le bail se compte en temps reel, comme le ping de l'app.
    private var reel: TimeInterval { (ContinuousClock.now - depart) / .seconds(1) }
    /// Horloge du pont : il a demarre 21 s avant l'ouverture du port.
    private var ms: UInt32 { UInt32(21_000 + t * 1000) }

    func executer(entrees: AsyncStream<Data>) async {
        texte("Console du pont amaran : 'help' pour les commandes.")
        brut("amaran> ")
        await withTaskGroup(of: Void.self) { g in
            g.addTask { [weak self] in
                for await d in entrees { await self?.recevoir(d) }
            }
            g.addTask { [weak self] in
                while !Task.isCancelled {
                    guard let self, await self.tic() else { return }
                    try? await Task.sleep(for: .milliseconds(Int(50 / self.vitesse)))
                }
            }
            await g.next()
            g.cancelAll()
        }
    }

    // MARK: - Sorties

    private func brut(_ s: String) {
        guard !ferme else { return }
        sortie.yield(.donnees(Data(s.utf8)))
    }

    private func texte(_ s: String) { brut(s + "\r\n") }

    private func ligne(_ type: String, bloc: String? = nil, _ champs: [(String, J)]) {
        var tete: [(String, J)] = [("v", .i(1)), ("t", .s(type)), ("n", .i(Int(n))), ("ms", .i(Int(ms)))]
        if let bloc { tete.append(("bloc", .s(bloc))) }
        n &+= 1
        brut("\u{1E}" + J.o(tete + champs).texte + "\n")
    }

    private func reponse(_ id: Int?, _ cmd: String, debut: Bool = false, ok: Bool = true, code: String = "ok",
                         msg: String? = nil, extra: [(String, J)] = []) {
        guard let id else { return }
        var c: [(String, J)] = [("id", .i(id)), ("etape", .s(debut ? "debut" : "fin")),
                                ("cmd", .s(PolitiqueCommandes.masquerCle(cmd) == cmd ? String(cmd.prefix(40)) : "mesh cles")),
                                ("ok", .b(ok)), ("code", .s(debut ? "en_cours" : code))]
        if let msg { c.append(("msg", .s(msg))) }
        if !debut { c.append(("duree_ms", .i(1))) }
        ligne("reponse", c + extra)
    }

    // MARK: - Instantanes (5)

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
        ligne("hello", bloc: "identite", [
            ("boot", .s(boot)), ("mac", .s("02000000DE00")),
            ("id", .o([("fabricant", .s("TEST_VENDOR")), ("produit", .s("TEST_PRODUCT")),
                       ("serie", .s("AMARAN-02000000DE00")), ("nom", .s("Pont amaran"))])),
            ("caps", .a(["matter", "thread", "mesh", "catalogue", "ordres", "led", "log"].map { .s($0) })),
        ])
        ligne("config", bloc: "catalogue", [
            ("modeles", .a([.o([("code", .i(40065)), ("nom", .s("amaran COB 60d")), ("capacites", .a([.s("intensite")])),
                                ("type", .s("variable")), ("cct_k", .s(nil))])])),
            ("repli", .o([("nom", .s("modele non catalogue")), ("capacites", .a([.s("intensite")])),
                          ("type", .s("variable")), ("cct_k", .s(nil))])),
        ])
        configMesh()
        for i in memoire.lampes.indices { configLampe(i) }
    }

    private func configMesh() {
        let e = memoire.empreintes
        ligne("config", bloc: "mesh", [
            ("cles", .b(e != nil)),
            ("empreintes", e.map { .o([("reseau", .s($0.reseau)), ("application", .s($0.application))]) } ?? .s(nil)),
            ("adresse", .s("7F38")), ("iv_nvs", .i(0)),
            ("balayage", .o([("fenetre_ms", .i(20)), ("intervalle_ms", .i(40))])),
            ("lampes", .i(memoire.lampes.count)), ("capacite", .i(16)), ("releve_ms", .i(memoire.releveMs)),
            ("groupe", .s("C000")),
        ])
    }

    private func configLampe(_ i: Int) {
        let l = memoire.lampes[i]
        ligne("config", bloc: "lampe", [
            ("lampe", .i(i + 1)), ("adresse", .s(String(format: "%04X", l.adresse))),
            ("mac", .s(l.mac.replacingOccurrences(of: ":", with: ""))), ("nom", .s(l.nom)), ("code", .i(Int(l.code))),
            ("modele", .s(l.code == 40065 ? "amaran COB 60d" : "modele non catalogue")), ("catalogue", .b(l.code == 40065)),
            ("capacites", .a([.s("intensite")])), ("type", .s("variable")),
        ])
    }

    private func etatPont() {
        ligne("etat", bloc: "pont", [
            ("boot", .s(boot)), ("up_s", .i(Int(ms / 1000))),
            ("mesh", .o([("pret", .b(memoire.empreintes != nil)), ("diag", .s(memoire.empreintes == nil ? "cles_absentes" : "ok"))])),
            ("ordres", .o([("total", .i(ordres.total)), ("confirmes", .i(ordres.confirmes)), ("abandons", .i(ordres.abandons)),
                           ("tenus", .i(ordres.tenus)), ("delai_total_ms", .i(ordres.delai)), ("delai_max_ms", .i(ordres.confirmes > 0 ? 430 : 0)),
                           ("lents", .i(0))])),
            ("releves", .i(Int(t / Double(memoire.releveMs) * 1000))), ("trames", .i(lampes.map(\.repondues).reduce(0, +))),
        ])
    }

    private func resume(_ i: Int) -> String {
        let l = lampes[i], m = memoire.lampes[i]
        return "\(l.entendue) \(l.marche) \(l.intensite) \(String(describing: l.consigne)) \(String(describing: m.endpoint)) \(m.vue) \(m.masquee)"
    }

    private func etatLampe(_ i: Int) {
        let l = lampes[i], m = memoire.lampes[i]
        let ep = m.masquee || !m.vue ? nil : m.endpoint
        var consigne: J = .s(nil)
        if let c = l.consigne {
            consigne = .o([("marche", c.marche.map(J.b) ?? .s(nil)), ("intensite", c.intensite.map(J.i) ?? .s(nil)),
                           ("phase", .s("attente")), ("essai", .i(1))])
        }
        ligne("etat", bloc: "lampe", [
            ("lampe", .i(i + 1)), ("maison", .o([("endpoint", ep.map(J.i) ?? .s(nil)), ("vue", .b(m.vue)), ("masquee", .b(m.masquee))])),
            ("entendue", .b(l.entendue)),
            ("lue", l.entendue ? .o([("marche", .b(l.marche)), ("intensite", .i(l.intensite))]) : .s(nil)),
            ("joignable", .b(l.entendue)), ("reponse_ms", l.reponseMs.map { .i(Int($0)) } ?? .s(nil)),
            ("consigne", consigne), ("repondues", .i(l.repondues)), ("part_10min", l.entendue ? .i(100) : .s(nil)),
            ("alerte", .b(false)),
        ])
        if i < montrees.count { montrees[i] = resume(i) }
    }

    private func sante() {
        ligne("etat", bloc: "sante", [
            ("boot", .s(boot)), ("up_s", .i(Int(ms / 1000))), ("commande", .s(nil)),
            ("led", .o([("motif", .s("operationnel")), ("test", .b(false)), ("depuis_ms", .i(Int(ms) % 10_000))])),
            ("matter", .o([("en_service", .b(true)), ("thread", .b(true)), ("identifie", .b(false)), ("ble", .b(false))])),
            ("sys", .o([("heap", .i(112_640)), ("heap_min", .i(103_424)), ("heap_bloc", .i(45_056)),
                        ("piles", .o([("lampes", .i(2104)), ("json", .i(1460)), ("console", .i(2876))])),
                        ("json_perdus", .i(0)), ("json_trop_longs", .i(0)), ("rejets", .i(0))])),
        ])
    }

    private func compteurs() {
        let k = Int(t * 40)
        ligne("compteurs", bloc: "mesh", [
            ("annonces", .i(k * 3)), ("nid_reconnu", .i(k)), ("nid_inconnu", .i(k * 2)), ("netmic_faux", .i(0)),
            ("acces_dechiffres", .i(k)), ("etats_lampes", .i(lampes.map(\.repondues).reduce(0, +))), ("doublons", .i(k / 2)),
            ("balises", .o([("notres", .i(Int(t / 5))), ("autres", .i(0)), ("fausses", .i(0)), ("derniere", .s(nil))])),
            ("emis", .i(Int(t))), ("echecs_emission", .i(0)), ("file_pleine", .i(0)), ("iv", .i(0)), ("seq", .i(1000 + Int(t))),
            ("plancher", .i(1024)),
        ])
    }

    private func reseau() {
        ligne("reseau", bloc: "matter", [
            ("demarre", .b(true)), ("fabriques", .i(1)), ("ble", .b(false)), ("identifie", .b(false)),
            ("abonnements", .o([("demandes", .i(2)), ("plafonnes", .i(2)), ("etablis", .i(2)), ("termines", .i(1)), ("plafond_s", .i(20))])),
            ("code_manuel", .s("34970112332")), ("qr", .s("MT:Y.K9042C00KA0648G00")),
        ])
        ligne("reseau", bloc: "thread", [("role", .s("child")), ("attache", .b(true))])
    }

    private func instantane() {
        etatPont()
        for i in lampes.indices { etatLampe(i) }
        sante()
        compteurs()
        reseau()
    }

    // MARK: - Temps

    /// Faux : le pont simule redemarre (le flux se ferme).
    private func tic() -> Bool {
        guard !ferme else { return false }
        let now = t
        // La lampe jamais vue repond pour la premiere fois au bout de 15 s.
        if now > 15, let i = memoire.lampes.indices.last, !lampes[i].entendue {
            lampes[i].entendue = true
            lampes[i].reponseMs = ms
            if !memoire.lampes[i].vue && !memoire.lampes[i].masquee {
                memoire.lampes[i].vue = true
                memoire.lampes[i].endpoint = memoire.prochainEndpoint
                memoire.prochainEndpoint += 1
                sauver(memoire)
                if machine {
                    ligne("lampe", [("lampe", .i(i + 1)), ("quoi", .s("entree")), ("endpoint", .i(memoire.lampes[i].endpoint ?? 0))])
                }
            }
        }
        for i in lampes.indices where lampes[i].entendue && Int(now * 1000) % memoire.releveMs < 60 {
            lampes[i].reponseMs = ms
            lampes[i].repondues += 1
        }
        guard machine else { return true }
        if bailS > 0, reel - dernierRx > Double(bailS) {
            ligne("fin", [("cause", .s("bail"))])
            texte("json : mode machine coupe (hote muet depuis \(bailS) s)")
            brut("amaran> ")
            machine = false
            return true
        }
        if periodes.etat > 0, now >= prochains.etat {
            etatPont()
            sante()
            prochains.etat = now + Double(periodes.etat) / 1000
        }
        if periodes.lampes > 0, now >= prochains.lampes {
            for i in lampes.indices { etatLampe(i) }
            prochains.lampes = now + Double(periodes.lampes) / 1000
        }
        if now >= prochains.regard {
            for i in lampes.indices where montrees.count > i && montrees[i] != resume(i) { etatLampe(i) }
            prochains.regard = now + 0.1
        }
        if periodes.compteurs > 0, now >= prochains.compteurs {
            compteurs()
            prochains.compteurs = now + Double(periodes.compteurs) / 1000
        }
        if periodes.reseau > 0, now >= prochains.reseau {
            reseau()
            prochains.reseau = now + Double(periodes.reseau) / 1000
        }
        return true
    }

    // MARK: - Commandes (6)

    private func recevoir(_ d: Data) {
        dernierRx = reel
        for o in d {
            if o == 0x0A {
                let l = String(decoding: tampon, as: UTF8.self)
                tampon.removeAll()
                executer(l)
            } else if o == 0x15 {
                tampon.removeAll()
            } else if o >= 0x20 || o == 0x09 {
                tampon.append(o)
            }
        }
    }

    private func executer(_ brute: String) {
        var l = brute.trimmingCharacters(in: .whitespaces)
        var id: Int?
        if l.hasPrefix("id="), let e = l.firstIndex(of: " ") {
            id = Int(l[l.index(l.startIndex, offsetBy: 3)..<e])
            l = String(l[e...]).trimmingCharacters(in: .whitespaces)
        }
        guard !l.isEmpty else { return }
        if !machine { texte(PolitiqueCommandes.masquerCle(l)) }
        let m = l.split(separator: " ").map(String.init)
        switch (m.first, m.count) {
        case ("json", _):
            commandeJson(id, l, m)
        case ("lampe", 3), ("lampe", 4):
            commandeLampe(id, l, m)
        case ("mesh", _):
            commandeMesh(id, l, m)
        case ("redemarre", 1):
            reponse(id, l, debut: true)
            texte("redemarrage")
            memoire.appliquerChargement()
            sauver(memoire)
            ferme = true
            sortie.yield(.ferme(raison: "le pont simulé redémarre"))
            sortie.finish()
        case ("led", 2):
            reponse(id, l, debut: true)
            texte(m[1] == "test" ? "Test de la LED, 6 s ('led stop' pour l'arreter) :" : "Test de la LED arrete.")
            reponse(id, l)
        default:
            reponse(id, l, debut: true)
            texte("Commande inconnue : \"\(m.first ?? "")\" (help)")
            reponse(id, l, ok: false, code: "inconnue")
        }
        if !machine { brut("amaran> ") }
    }

    private func commandeJson(_ id: Int?, _ l: String, _ m: [String]) {
        switch m.count > 1 ? m[1] : "" {
        case "1":
            machine = true
            bailS = m.count == 4 ? Int(m[3]) ?? 30 : 30
            periodes = (1000, 10000, 1000, 5000)
            log = false
            let now = t
            prochains = (now + 1, now + 10, now + 1, now + 5, now)
            hello()
            instantane()
            montrees = lampes.indices.map(resume)
            reponse(id, l, extra: [("bail_s", .i(bailS)), ("up_s", .i(Int(ms / 1000)))])
        case "0":
            reponse(id, l)
            if machine {
                ligne("fin", [("cause", .s("commande"))])
                texte("json : mode machine coupe")
                machine = false
            }
        case "etat":
            instantane()
            reponse(id, l)
        case "hello":
            hello()
            reponse(id, l)
        case "ping":
            reponse(id, l, extra: [("bail_s", .i(bailS)), ("up_s", .i(Int(ms / 1000)))])
        case "periode", "lampes", "compteurs", "reseau":
            if let v = m.count == 3 ? Int(m[2]) : nil {
                switch m[1] {
                case "periode": periodes.etat = v
                case "lampes": periodes.lampes = v
                case "compteurs": periodes.compteurs = v
                default: periodes.reseau = v
                }
                reponse(id, l)
            } else {
                reponse(id, l, ok: false, code: "usage", msg: "json \(m[1]) <ms>")
            }
        case "log":
            log = m.count == 3 && m[2] == "1"
            reponse(id, l)
        default:
            reponse(id, l, ok: false, code: "usage", msg: "json [1|0|etat|hello|ping|...]")
        }
    }

    private func commandeLampe(_ id: Int?, _ l: String, _ m: [String]) {
        guard let k = Int(m[1]), (1...lampes.count).contains(k) else {
            return reponse(id, l, ok: false, code: "usage", msg: "lampe <1-\(lampes.count)> on|off|niveau <0-1000>")
        }
        let i = k - 1
        if m[2] == "releve" {
            reponse(id, l, debut: true)
            texte("ok demande d'etat a la lampe \(k)")
            return reponse(id, l)
        }
        var marche: Bool?
        var intensite: Int?
        switch m[2] {
        case "on" where m.count == 3: marche = true
        case "off" where m.count == 3: marche = false
        case "niveau" where m.count == 4: intensite = Int(m[3]).map { min(1000, max(0, $0)) / 10 * 10 }
        default: break
        }
        guard marche != nil || intensite != nil else {
            return reponse(id, l, ok: false, code: "usage", msg: "lampe <1-\(lampes.count)> on|off|niveau <0-1000>")
        }
        reponse(id, l, code: "accepte", extra: [("suite", .s("ordre")), ("lampe", .i(k))])
        ordres.total += 1
        if let id { lampes[i].ids.append(id) }
        let tenu = lampes[i].entendue && (marche.map { $0 == lampes[i].marche } ?? true)
            && (intensite.map { $0 == lampes[i].intensite } ?? true)
        if tenu {
            ordres.tenus += 1
            return finirOrdre(i, issue: "tenu", delai: 0, essai: 0)
        }
        lampes[i].consigne = (marche, intensite)
        let attente = Int((lampes[i].entendue ? 430 : 3700) / vitesse)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(attente))
            await self?.finirConsigne(i, marche: marche, intensite: intensite)
        }
    }

    /// La lampe a obei (relue egale a la consigne), ou ne repond pas : abandon.
    private func finirConsigne(_ i: Int, marche: Bool?, intensite: Int?) {
        guard !ferme else { return }
        if lampes[i].entendue {
            if let marche { lampes[i].marche = marche }
            if let intensite { lampes[i].intensite = intensite }
            lampes[i].consigne = nil
            ordres.confirmes += 1
            ordres.delai += 430
            finirOrdre(i, issue: "confirme", delai: 430, essai: 1)
            if machine { ligne("led", [("motif", .s("livree")), ("avant", .s("operationnel")), ("test", .b(false)), ("depuis_ms", .i(0))]) }
        } else {
            lampes[i].consigne = nil
            ordres.abandons += 1
            finirOrdre(i, issue: "abandon", delai: 3700, essai: 3)
            if machine { ligne("led", [("motif", .s("injoignable")), ("avant", .s("operationnel")), ("test", .b(false)), ("depuis_ms", .i(0))]) }
        }
    }

    private func finirOrdre(_ i: Int, issue: String, delai: Int, essai: Int) {
        let ids = lampes[i].ids
        lampes[i].ids = []
        guard machine else { return }
        ligne("ordre", [("lampe", .i(i + 1)), ("issue", .s(issue)), ("delai_ms", .i(delai)), ("essai", .i(essai)),
                        ("ids", .a(ids.map(J.i))), ("ids_perdus", .i(0))])
    }

    private func commandeMesh(_ id: Int?, _ l: String, _ m: [String]) {
        reponse(id, l, debut: true)
        var ok = true
        switch (m.count > 1 ? m[1] : "", m.count) {
        case ("", 1):
            texte("mesh pret : \(memoire.empreintes == nil ? "non" : "oui")")
            if let e = memoire.empreintes { texte("cles : reseau \(e.reseau), application \(e.application)") }
        case ("releve", 3):
            if let s = Int(m[2]), (1...60).contains(s) {
                memoire.releveMs = s * 1000
                sauver(memoire)
                texte("ok relecture toutes les \(s) s")
                if machine { configMesh() }
            } else {
                texte("erreur : mesh releve <1-60 s>")
                ok = false
            }
        case ("lampe", 4) where m[3] == "masquer" || m[3] == "afficher":
            if let k = Int(m[2]), (1...memoire.lampes.count).contains(k) {
                let i = k - 1
                let afficher = m[3] == "afficher"
                memoire.lampes[i].masquee = !afficher
                if afficher {
                    memoire.lampes[i].vue = true
                    if memoire.lampes[i].endpoint == nil {
                        memoire.lampes[i].endpoint = memoire.prochainEndpoint
                        memoire.prochainEndpoint += 1
                    }
                }
                sauver(memoire)
                let ep = memoire.lampes[i].endpoint ?? 0
                texte(afficher ? "ok lampe \(k) dans Maison (EP\(ep))"
                               : "ok lampe \(k) retiree de Maison (mesh lampe \(k) afficher pour la remettre)")
                if machine {
                    ligne("lampe", [("lampe", .i(k)), ("quoi", .s(afficher ? "remise" : "masquee")),
                                    ("endpoint", afficher ? .i(ep) : .s(nil))])
                }
            } else {
                texte("erreur : mesh lampe <1-\(memoire.lampes.count)> masquer|afficher")
                ok = false
            }
        case ("cles", 4):
            let r = Data(hex: m[2]), a = Data(hex: m[3])
            if let r, let a, r.count == 16, a.count == 16 {
                let e = (Empreinte.de(r), Empreinte.de(a))
                memoire.clesChargees = e
                texte("ok cles \(e.0) \(e.1) (redemarrer pour les appliquer)")
            } else {
                texte("erreur : mesh cles <reseau 32 hexa> <application 32 hexa>")
                ok = false
            }
        case ("lampes", 3):
            memoire.attendues = Int(m[2]) ?? 0
            memoire.brouillon = [:]
            texte("ok liste de \(memoire.attendues) lampe(s) : envoyer mesh lampe 1 a \(memoire.attendues)")
        case ("lampe", let c) where c >= 7:
            ok = chargerLampe(l, m)
        default:
            texte("erreur : sous-commande inconnue (help)")
            ok = false
        }
        reponse(id, l, ok: ok, code: ok ? "ok" : "erreur")
    }

    /// `mesh lampe <n> <adresse> <mac> <code> "<nom>"` (nom entre guillemets, echappe).
    private func chargerLampe(_ l: String, _ m: [String]) -> Bool {
        guard memoire.attendues > 0, let k = Int(m[2]), (1...memoire.attendues).contains(k),
              let adresse = UInt16(m[3].replacingOccurrences(of: "0x", with: ""), radix: 16), let code = UInt32(m[5]),
              let q = l.firstIndex(of: "\"")
        else {
            texte("erreur : mesh lampe <1-\(memoire.attendues)> <adresse> <mac> <code> <nom>")
            return false
        }
        var nom = String(l[l.index(after: q)...])
        if nom.hasSuffix("\"") { nom.removeLast() }
        nom = nom.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        memoire.brouillon[k] = MemoireDemo.Lampe(adresse: adresse, mac: m[4], nom: nom, code: code, endpoint: nil, vue: false)
        var fin = ""
        if memoire.brouillon.count == memoire.attendues {
            memoire.listeChargee = (1...memoire.attendues).compactMap { memoire.brouillon[$0] }
            fin = " ; liste de \(memoire.attendues) lampe(s) enregistree (redemarrer pour l'appliquer)"
        }
        texte("ok lampe \(k) 0x\(String(format: "%04x", adresse)) modele \(code) amaran COB 60d [intensite] : \(nom)\(fin)")
        return true
    }
}
````

`apps/macos/AmaranCompagnon/Demo/TransportDemo.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : transport du mode demo, avec le pont
// simule (SimulateurDemo) et sa memoire, qui survit a ses redemarrages.
import AmaranProtocole
import Foundation
import Synchronization

/// Chaque ouverture est un nouveau demarrage du pont simule (nouveau `boot`) ; quand
/// il redemarre, le flux se ferme comme a une re-enumeration USB : l'app se
/// reconnecte seule.
final class TransportDemo: Transport {
    let genre: GenreTransport = .demo
    let nom = "Démo (pont simulé à trois lampes)"

    private struct Etat {
        var tache: Task<Void, Never>?
        var entrees: AsyncStream<Data>.Continuation?
        var sortie: AsyncStream<EvenementTransport>.Continuation?
        var memoire = MemoireDemo.initiale
    }

    private let vitesse: Double
    private let etat = Mutex(Etat())

    /// `vitesse` : facteur du temps du pont simule (les tests vont plus vite).
    init(vitesse: Double = 1) {
        self.vitesse = vitesse
    }

    func ouvrir() async throws -> AsyncStream<EvenementTransport> {
        let (flux, sortie) = AsyncStream.makeStream(of: EvenementTransport.self, bufferingPolicy: .unbounded)
        let (entrees, suiteEntrees) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let memoire = etat.withLock { $0.memoire }
        let boot = String(format: "%08X", UInt32.random(in: .min ... .max))
        let simulateur = SimulateurDemo(sortie: sortie, boot: boot, vitesse: vitesse, memoire: memoire) { [weak self] m in
            self?.etat.withLock { $0.memoire = m }
        }
        let tache = Task.detached(priority: .userInitiated) {
            await simulateur.executer(entrees: entrees)
            sortie.finish()
        }
        etat.withLock { e in
            e.tache = tache
            e.entrees = suiteEntrees
            e.sortie = sortie
        }
        return flux
    }

    func envoyer(_ donnees: Data) throws {
        guard let entrees = etat.withLock({ $0.entrees }) else { throw ErreurTransport("démo arrêtée") }
        entrees.yield(donnees)
    }

    func fermer() {
        let (tache, entrees, sortie) = etat.withLock { e in
            let r = (e.tache, e.entrees, e.sortie)
            e.tache = nil
            e.entrees = nil
            e.sortie = nil
            return r
        }
        entrees?.finish()
        tache?.cancel()
        sortie?.yield(.ferme(raison: "démo arrêtée"))
        sortie?.finish()
    }
}
````

- [ ] **Step 7 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `Test run with 85 tests in 13 suites passed` et `Test run with 9 tests in 3 suites passed`, puis `** TEST SUCCEEDED **`, sans avertissement. Le test du vrai trousseau est sauté.

> **Amendement (exécution, 05/10)** : la relecture (Opus) a montré deux défauts, corrigés en un commit à part. (1) Une réouverture par le seul nom du port pouvait ouvrir un autre appareil (la C6 du maillage BenQ, un écran LG) : le pont n'est plus reconnu qu'à son numéro de série USB (`Pont.portDuPont`, cartes Espressif seulement), avec un test (`PortDuPontTests`). (2) Les blocs de fermeture de `TransportSerie` capturaient `self` faiblement : le descripteur exclusif pouvait rester ouvert. Le drapeau « secret » du chargement vient aussi du masquage de la commande. `AmaranCompagnonTests` compte désormais 10 tests (la Task 9 aussi).

- [ ] **Step 8 : commit.**

```bash
git add apps/macos
git commit -m "$(printf "App compagnon : modele Pont, port serie, trousseau, chargement des cles, mode demo\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 9: Les écrans : tableau de bord, commandes et console, réglages

**Files:**
- Create: `apps/macos/AmaranCompagnon/Vues/{Composants,ContenuPrincipal,TableauDeBord,Cles,CommandesEtConsole,Reglages}.swift`
- Modify: `apps/macos/AmaranCompagnon/AmaranCompagnonApp.swift` (remplacé en entier)

**Interfaces:**
- Consumes : `Pont`, `VueLampe`, `EtatChargement`, `SourceCles`, `LigneConsole`, `PortUSB` (Task 8) ; `Interpretation`, `CodeAppairage`, `EtatPont`, `SuiviCommande` (Tasks 5 et 6).
- Produces : l'app complète. `Ecran` (`tableau`, `commandes`), `ContenuPrincipal(ecranInitial:)`, `FenetreReglages` ; les arguments de lancement `-demo` et `-ecran commandes`.

Pourquoi : la spec 3b, section 8 (la part 3b-1 : tableau de bord, commandes et console, réglages Généraux). La fenêtre reprend celle de Halo Compagnon :
- **la barre latérale** : « Supervision » (les deux écrans de 3b-1), puis le panneau de connexion : un menu des ports Espressif (avec leur numéro de série USB, affiché seulement) et du mode démo, puis « Connecter ». « Rafraîchir » et « Libérer le port » sont dans la barre d'outils ;
- **le tableau de bord** : « Ajouter à Maison » (QR et code) tant que le pont n'est pas appairé ; une carte par lampe ; Bluetooth Mesh ; Thread et Matter ; Clés (`CarteCles` : les empreintes de la base, de la copie de ce Mac et du pont, les écarts, les modèles à cataloguer, et les gestes « Copier depuis amaran Desktop » (« Autoriser le dossier d'amaran Desktop… » la première fois), « Relire », le menu « Charger le pont » (depuis amaran Desktop ou depuis la copie de ce Mac), « Exporter une sauvegarde… », « Importer une sauvegarde… ») ; Voyant ; Système ;
- **commandes et console** : à gauche, une lampe choisie (marche, arrêt, niveau au pour cent près, relecture, « retirer de Maison / remettre » avec sa confirmation, période de relecture) ; à droite, la console brute (corrélation des `id`, historique, masquage de `mesh cles`, confirmation des commandes dangereuses) ;
- **les réglages** (⌘,), onglet Général : le dossier d'amaran Desktop autorisé (« Changer… »), la date de la dernière sauvegarde exportée.

Les écrans 3 et 4 (graphiques, trames) et l'onglet « Accès réseau Thread » viendront au plan 3b-2.

- [ ] **Step 1 : les composants communs.**

`apps/macos/AmaranCompagnon/Vues/Composants.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : textes en francais seulement.
import AmaranProtocole
import SwiftUI

/// Carte du tableau de bord.
struct Carte<Contenu: View>: View {
    let titre: Text
    let icone: String
    var accent: Color = .secondary
    @ViewBuilder let contenu: Contenu

    init(titre: String, icone: String, accent: Color = .secondary, @ViewBuilder contenu: () -> Contenu) {
        self.init(titre: Text(verbatim: titre), icone: icone, accent: accent, contenu: contenu)
    }

    init(titre: Text, icone: String, accent: Color = .secondary, @ViewBuilder contenu: () -> Contenu) {
        self.titre = titre
        self.icone = icone
        self.accent = accent
        self.contenu = contenu()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { titre } icon: { Image(systemName: icone) }
                .font(.headline)
                .foregroundStyle(accent == .secondary ? .primary : accent)
            contenu
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent == .secondary ? .clear : accent.opacity(0.6)))
    }
}

/// Ligne "libelle : valeur".
struct LigneInfo: View {
    let libelle: Text
    let valeur: String
    var couleur: Color?
    var mono = false

    init(_ libelle: String, _ valeur: String?, couleur: Color? = nil, mono: Bool = false) {
        self.init(libelle: Text(verbatim: libelle), valeur, couleur: couleur, mono: mono)
    }

    private init(libelle: Text, _ valeur: String?, couleur: Color?, mono: Bool) {
        self.libelle = libelle
        self.valeur = valeur ?? "–"
        self.couleur = couleur
        self.mono = mono
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            libelle
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(valeur)
                .font(mono ? .body.monospaced() : .body)
                .foregroundStyle(couleur ?? .primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

extension String {
    /// Premiere lettre en majuscule (libelles affiches en debut de ligne).
    var avecMajuscule: String { prefix(1).uppercased() + dropFirst() }
}

/// Petite etiquette coloree.
struct Pastille: View {
    let texte: Text
    var couleur: Color = .secondary

    init(texte: String, couleur: Color = .secondary) {
        self.texte = Text(verbatim: texte)
        self.couleur = couleur
    }

    var body: some View {
        texte
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(couleur)
            .background(couleur.opacity(0.15), in: Capsule())
    }
}

/// Jauge "valeur / seuil".
struct JaugeSeuil: View {
    let libelle: String
    let valeur: Int?
    let seuil: Int?

    var body: some View {
        let v = Double(valeur ?? 0)
        let s = Double(max(seuil ?? 1, 1))
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: libelle).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(valeur.map(String.init) ?? "–") / \(seuil.map(String.init) ?? "–")").monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: min(v, s), total: s)
                .tint(v >= s ? .red : (v >= s * 0.6 ? .orange : .accentColor))
        }
    }
}

// MARK: - Voyant

/// Le voyant du pont, anime d'apres le motif et les constantes de
/// `components/socle/include/status_led.h` (la couleur instantanee n'est pas transmise, 7.4).
struct VoyantLed: View {
    let motif: MotifLed?
    let depuis: Date?
    var taille: CGFloat = 18

    var body: some View {
        // Redessine seulement quand le rendu change (clignements, lueur, arc-en-ciel),
        // jamais pour un motif fixe : pas de 30 images/s permanentes dans la barre d'outils.
        TimelineView(HoraireVoyant(motif: motif, depuis: depuis ?? .distantPast)) { contexte in
            let t = max(0, contexte.date.timeIntervalSince(depuis ?? .distantPast))
            let (couleur, intensite) = Self.rendu(motif, t: t)
            ZStack {
                Circle().fill(Color.black.opacity(0.75))
                Circle().fill(couleur.opacity(intensite))
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .frame(width: taille, height: taille)
            .shadow(color: couleur.opacity(intensite * 0.9), radius: intensite * taille * 0.5)
        }
        .accessibilityLabel(motif?.libelle ?? "voyant inconnu")
    }

    /// Prochain instant (secondes depuis le debut du motif) ou le rendu change ;
    /// nil : il ne changera plus (motif fixe, ou eclat termine).
    nonisolated static func prochainChangement(_ motif: MotifLed?, t: Double) -> Double? {
        let image = 1.0 / 30
        let ms = t * 1000
        switch motif {
        case .identification:
            return t + image
        case .desappairage:
            return (floor(ms / 100) + 1) * 0.1
        case .redemarrage:
            return ms < 150 ? 0.15 : nil
        case .injoignable:
            return ms < 1200 ? (floor(ms / 200) + 1) * 0.2 : nil
        case .panneRadio, .inconnu, nil:
            return nil
        case .livree:
            return ms < 150 ? 0.15 : nil
        case .nonAppaire:
            return (floor(ms / 250) + 1) * 0.25
        case .horsReseau:
            return floor(ms / 1000) + 1
        case .operationnel:
            let cycle = floor(ms / 10_000) * 10
            return ms.truncatingRemainder(dividingBy: 10_000) < 600 ? t + image : cycle + 10
        }
    }

    /// Couleur et intensite (0..1), `t` secondes apres le debut du motif.
    static func rendu(_ motif: MotifLed?, t: Double) -> (Color, Double) {
        let ms = t * 1000
        switch motif {
        case .identification:
            // Roue des couleurs, un tour en 2000 ms (kRainbowMs).
            return (Color(hue: ms.truncatingRemainder(dividingBy: 2000) / 2000, saturation: 1, brightness: 1), 1)
        case .desappairage:
            // Bouton tenu 8 s : rouge, noir, violet, noir, par pas de 100 ms (kUnpairStepMs).
            switch Int(ms / 100) % 4 {
            case 0: return (.red, 1)
            case 2: return (.purple, 1)
            default: return (.red, 0)
            }
        case .redemarrage:
            // Appui court : eclat blanc de 150 ms (kRebootFlashMs), puis noir.
            return (.white, ms < 150 ? 1 : 0)
        case .injoignable:
            // Rouge, 3 clignements de 200 ms / 200 ms (kRedHalfMs, kRedBlinks), puis noir.
            guard ms < 1200 else { return (.red, 0) }
            return (.red, Int(ms / 200) % 2 == 0 ? 1 : 0)
        case .panneRadio:
            return (.red, 1)
        case .livree:
            // Eclat vert de 150 ms (kDeliveredMs).
            return (.green, ms < 150 ? 1 : 0)
        case .nonAppaire:
            return (.blue, Int(ms / 250) % 2 == 0 ? 1 : 0)
        case .horsReseau:
            return (.orange, Int(ms / 1000) % 2 == 0 ? 1 : 0)
        case .operationnel:
            // Eteint, lueur blanche de 600 ms toutes les 10 s (kGlowPeriodMs, kGlowMs).
            let phase = ms.truncatingRemainder(dividingBy: 10_000)
            guard phase < 600 else { return (.white, 0) }
            return (.white, 0.8 * (1 - abs(phase - 300) / 300))
        case .inconnu, nil:
            return (.gray, 0.2)
        }
    }
}

/// Calendrier du voyant : une date a chaque changement du rendu.
struct HoraireVoyant: TimelineSchedule {
    let motif: MotifLed?
    let depuis: Date

    func entries(from debut: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        sequence(first: debut) { d in
            let t = max(0, d.timeIntervalSince(depuis))
            guard let p = VoyantLed.prochainChangement(motif, t: t) else { return nil }
            return depuis.addingTimeInterval(max(p, t + 1.0 / 60))
        }
    }
}

// MARK: - Formats

enum Format {
    private static let styleHeure = Date.FormatStyle()
        .hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits).second(.twoDigits)
        .secondFraction(.fractional(3))

    /// Heure a la milliseconde ("14:02:11,512").
    static func heure(_ d: Date) -> String { d.formatted(styleHeure) }

    static func duree(secondes s: Int?) -> String {
        guard let s else { return "–" }
        let j = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if j > 0 { return "\(j) j \(h) h \(m) min" }
        if h > 0 { return "\(h) h \(m) min \(sec) s" }
        if m > 0 { return "\(m) min \(sec) s" }
        return "\(sec) s"
    }

    static func ms(_ v: Int?) -> String {
        guard let v else { return "–" }
        return v >= 10_000 ? "\(v / 1000) s" : "\(v) ms"
    }

    static func octets(_ v: Int?) -> String {
        guard let v else { return "–" }
        return Int64(v).formatted(.byteCount(style: .memory))
    }

    static func oui(_ b: Bool?) -> String {
        guard let b else { return "–" }
        return b ? "oui" : "non"
    }

    static func hexa(_ v: Int?) -> String {
        v.map { String(format: "%02X", $0) } ?? "–"
    }
}

extension MoteurSession.Phase {
    var libelle: String {
        switch self {
        case .ferme: "fermé"
        case .attenteHello: "attente du hello"
        case .connecte: "connecté"
        case .resynchro: "resynchronisation"
        case .ancienFirmware: "firmware sans mode JSON"
        case .sansReponse: "sans réponse"
        case .versionInconnue(let v): "protocole v\(v) inconnu"
        case .modeHumain: "console texte"
        }
    }

    var couleur: Color {
        switch self {
        case .connecte: .green
        case .attenteHello, .resynchro: .orange
        case .ferme, .modeHumain: .secondary
        case .ancienFirmware, .sansReponse, .versionInconnue: .red
        }
    }
}

extension MotifLed {
    var libelle: String {
        switch self {
        case .identification: "identification (arc-en-ciel)"
        case .desappairage: "désappairage (bouton BOOT tenu)"
        case .redemarrage: "redémarrage (bouton BOOT)"
        case .injoignable: "lampe injoignable (rouge ×3)"
        case .panneRadio: "Bluetooth Mesh inopérant (rouge fixe)"
        case .livree: "ordre confirmé (éclat vert)"
        case .nonAppaire: "pas dans Maison (bleu)"
        case .horsReseau: "hors réseau Thread (orange)"
        case .operationnel: "opérationnel (lueur toutes les 10 s)"
        case .inconnu: "motif inconnu"
        }
    }
}
````

- [ ] **Step 2 : la fenêtre et la barre latérale.**

`apps/macos/AmaranCompagnon/Vues/ContenuPrincipal.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : fenetre, bandeaux, panneau de connexion.
// Deux ecrans en 3b-1 (les graphiques et les trames viendront au plan 3b-2).
import AmaranProtocole
import SwiftUI

enum Ecran: String, CaseIterable, Identifiable {
    case tableau, commandes

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .tableau: "Tableau de bord"
        case .commandes: "Commandes et console"
        }
    }

    var icone: String {
        switch self {
        case .tableau: "gauge.with.dots.needle.33percent"
        case .commandes: "slider.horizontal.3"
        }
    }
}

struct ContenuPrincipal: View {
    @Environment(Pont.self) private var pont
    @State private var ecran: Ecran
    @State private var confirmerLiberation = false

    init(ecranInitial: Ecran = .tableau) {
        _ecran = State(initialValue: ecranInitial)
    }

    var body: some View {
        @Bindable var pont = pont
        NavigationSplitView {
            List(selection: $ecran) {
                Section("Supervision") {
                    ForEach(Ecran.allCases) { e in
                        Label(e.titre, systemImage: e.icone).tag(e)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                PanneauConnexion()
                    .padding(12)
            }
        } detail: {
            VStack(spacing: 0) {
                if let alerte = pont.alerte {
                    Bandeau(texte: alerte.texte, couleur: .red, icone: "exclamationmark.octagon.fill")
                }
                if pont.estDemo {
                    Bandeau(texte: "Mode démo : un pont simulé à trois lampes ; ses clés et ses MAC sont inventées, et le trousseau de la démo est à part.",
                            couleur: .purple, icone: "play.rectangle.fill")
                }
                if let banc = pont.commandeDeBanc {
                    Bandeau(texte: "Commande en cours : « \(PolitiqueCommandes.masquerCle(banc.commande)) ». La console du pont ne lit plus rien jusqu'à la fin.",
                            couleur: .orange, icone: "hourglass")
                }
                if case .enCours(let etape) = pont.chargement {
                    Bandeau(texte: "Chargement du pont : \(etape)…", couleur: .blue, icone: "key")
                } else if pont.chargement == .attenteRedemarrage {
                    Bandeau(texte: "Chargement du pont : redémarrage, puis vérification…", couleur: .blue, icone: "key")
                }
                Group {
                    switch ecran {
                    case .tableau: TableauDeBord()
                    case .commandes: CommandesEtConsole()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Largeur ideale fixee : sans elle, un long texte donne sa largeur ideale
            // sur une ligne a la colonne de detail, et la barre laterale s'efface.
            .frame(minWidth: 560, idealWidth: 960, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(ecran.titre)
            .toolbar { barreOutils }
        }
        .alert("Commande de plus de 20 minutes", isPresented: $pont.propositionFermeture) {
            Button("Fermer le port", role: .destructive) { pont.deconnecter() }
            Button("Attendre", role: .cancel) {}
        } message: {
            Text("La console du pont ne lit plus rien : fermer le port n'arrête pas la commande, mais libère l'app.")
        }
        .confirmationDialog("Libérer le port ?", isPresented: $confirmerLiberation) {
            Button("Libérer le port") { pont.libererPort() }
        } message: {
            Text("L'app envoie json 0 et ferme le port (DTR et RTS restent à 0) : idf.py flash pourra flasher. Rien ne se rouvre avant « Reconnecter ».")
        }
    }

    @ToolbarContentBuilder
    private var barreOutils: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                VoyantLed(motif: pont.etat.motifLed, depuis: pont.etat.motifLedDepuis, taille: 14)
                Pastille(texte: pont.phase.libelle, couleur: pont.phase.couleur)
            }
            .padding(.horizontal, 8)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                pont.rafraichir()
            } label: {
                Label("Rafraîchir", systemImage: "arrow.clockwise")
            }
            .help("Instantané complet (json etat)")
            .disabled(!pont.peutCommander)

            Button {
                confirmerLiberation = true
            } label: {
                Label("Libérer le port", systemImage: "eject")
            }
            .help("json 0 puis fermeture du port, pour flasher")
            .disabled(pont.phase == .ferme || pont.estDemo)
        }
    }
}

struct Bandeau: View {
    let texte: String
    let couleur: Color
    let icone: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icone)
            Text(verbatim: texte)
                .fixedSize(horizontal: false, vertical: true)
                .frame(idealWidth: 400, maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(couleur)
        .background(couleur.opacity(0.12))
    }
}

/// Choix de la source (port USB ou demo) et etat du transport. Aucun port ne
/// s'ouvre sans un clic.
struct PanneauConnexion: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Section("Ports série") {
                    if pont.ports.isEmpty { Text("Aucun pont branché en USB") }
                    ForEach(pont.ports) { p in
                        Button {
                            pont.connecter(.serie(chemin: p.chemin, serie: p.serie))
                        } label: {
                            Label {
                                Text(verbatim: p.chemin.replacingOccurrences(of: "/dev/cu.", with: ""))
                                Text(verbatim: p.serie.map { "n° de série \($0)" } ?? p.chemin)
                            } icon: {
                                Image(systemName: "cpu")
                            }
                        }
                    }
                }
                Section {
                    Button {
                        pont.connecter(.demo)
                    } label: {
                        Label("Mode démo (sans matériel)", systemImage: "play.rectangle")
                    }
                }
            } label: {
                Label(libelleSource, systemImage: pont.estDemo ? "play.rectangle" : "cable.connector")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)

            Text(verbatim: libelleTransport)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                switch pont.etatTransport {
                case .ferme, .erreur, .libere:
                    Button(pont.source == nil ? "Connecter" : "Reconnecter") {
                        if pont.source == nil { pont.connecter(pont.sourceParDefaut) } else { pont.reconnecter() }
                    }
                    .buttonStyle(.borderedProminent)
                default:
                    Button("Déconnecter") { pont.deconnecter() }
                }
                if pont.phase == .ancienFirmware || pont.phase == .sansReponse {
                    Button("Réessayer json 1") { pont.reessayer() }
                }
            }
            .controlSize(.small)
        }
    }

    private var libelleSource: String {
        switch pont.source {
        case .demo: "Démo"
        case .serie(let chemin, _): chemin.replacingOccurrences(of: "/dev/cu.", with: "")
        case nil: "Choisir une source…"
        }
    }

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
    }
}
````

- [ ] **Step 3 : le tableau de bord et la carte des clés.**

`apps/macos/AmaranCompagnon/Vues/TableauDeBord.swift` (contenu complet) :

````swift
// Tableau de bord (spec 3b, section 8) : une grille de cartes, une par lampe. La carte
// « Ajouter a Maison » et le QR code sont repris de Halo Compagnon (commit e114cd5).
import AmaranProtocole
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct TableauDeBord: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        if pont.etat.helloBase == nil && pont.etat.lampes.isEmpty {
            ContentUnavailableView {
                Label("Aucun état reçu", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Choisir le port du pont (VID 303A) ou le mode démo dans la barre latérale.")
            } actions: {
                Button("Lancer la démo") { pont.connecter(.demo) }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14, alignment: .top)],
                          alignment: .leading, spacing: 14) {
                    // Pont pas encore mis en service : l'appairage passe avant tout.
                    if pont.etat.enService == false { CarteAppairage() }
                    ForEach(pont.lampes) { CarteLampe(lampe: $0) }
                    CarteMesh()
                    CarteMatter()
                    CarteCles()
                    CarteVoyant()
                    CarteSysteme()
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Lampes

private struct CarteLampe: View {
    @Environment(Pont.self) private var pont
    let lampe: VueLampe

    var body: some View {
        let e = lampe.etat
        let joignable = e?.joignable ?? false
        Carte(titre: "\(lampe.numero) · \(lampe.nom)", icone: "lightbulb",
              accent: e?.alerte == true || (e?.entendue == true && !joignable) ? .orange : .secondary) {
            LigneInfo("Modèle", lampe.config.map { c in
                (c.catalogue == true ? c.modele : "non catalogué (code \(c.code ?? 0))") ?? "?"
            })
            LigneInfo("Maison", Interpretation.maison(e?.maison))
            LigneInfo("État lu", Interpretation.etat(e?.lue))
            LigneInfo("Joignable", e?.entendue == true ? Format.oui(joignable) : "jamais entendue",
                      couleur: e?.entendue == true && !joignable ? .orange : nil)
            LigneInfo("Relectures sur 10 min", e?.part10Min.map { "\($0) %" } ?? "–",
                      couleur: e?.alerte == true ? .orange : nil)
            if let c = e?.consigne {
                let quoi = [c.marche.map { $0 ? "marche" : "arrêt" }, c.intensite.map(Interpretation.intensite)]
                    .compactMap { $0 }.joined(separator: ", ")
                LigneInfo("Consigne en cours", "\(quoi) (essai \(c.essai ?? 1))", couleur: .blue)
            }
            if let o = lampe.dernierOrdre {
                LigneInfo("Dernier ordre", Interpretation.ordre(o), couleur: o.issue == .abandon ? .orange : nil)
            }
        }
    }
}

// MARK: - Bluetooth Mesh

private struct CarteMesh: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let p = pont.etat.pont?.valeur
        let m = pont.etat.mesh?.valeur
        let c = pont.etat.compteurs?.valeur
        let pret = p?.mesh?.pret == true
        Carte(titre: "Bluetooth Mesh", icone: "point.3.filled.connected.trianglepath.dotted",
              accent: p?.mesh?.diag.map { $0 != .ok } == true ? .red : .secondary) {
            LigneInfo("Réseau des lampes", pret ? "prêt" : "pas prêt", couleur: pret ? .green : .orange)
            if let d = p?.mesh?.diag, d != .ok { LigneInfo("Diagnostic", Interpretation.diag(d), couleur: .red) }
            LigneInfo("Adresse du pont", m?.adresse.map { "0x\($0)" }, mono: true)
            LigneInfo("IV Index", c?.iv.map(String.init))
            LigneInfo("Relecture", m?.releveMs.map { "toutes les \($0 / 1000) s" })
            LigneInfo("Ordres", p?.ordres.map { o in
                "\(o.total ?? 0) : \(o.confirmes ?? 0) confirmé(s), \(o.abandons ?? 0) abandonné(s), \(o.tenus ?? 0) déjà tenu(s)"
            })
            LigneInfo("Délai moyen", p?.ordres?.delaiMoyenMs.map { "\($0) ms (max \(p?.ordres?.delaiMaxMs ?? 0) ms)" })
            LigneInfo("Annonces", c.map { "\($0.annonces ?? 0) (\($0.nidReconnu ?? 0) de notre réseau)" })
            LigneInfo("NetMIC faux", c?.netmicFaux.map(String.init), couleur: (c?.netmicFaux ?? 0) > 0 ? .orange : nil)
            LigneInfo("Émis, refus", c.map { "\($0.emis ?? 0), \($0.echecsEmission ?? 0)" })
        }
    }
}

// MARK: - Thread et Matter

private struct CarteMatter: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let m = pont.etat.matter?.valeur
        let t = pont.etat.thread?.valeur
        Carte(titre: "Thread et Matter", icone: "homekit") {
            LigneInfo("Mise en service", m?.fabriques.map { $0 > 0 ? "faite (\($0) fabrique(s))" : "en attente" })
            LigneInfo("Thread", t.map { "\($0.role ?? "?")\($0.attache == true ? " (attaché)" : "")" })
            LigneInfo("Abonnements actifs", m?.abonnements?.actifs.map(String.init))
            LigneInfo("Annonce BLE", Format.oui(m?.ble))
            LigneInfo("Identification", Format.oui(m?.identifie))
        }
    }
}

// MARK: - Voyant

private struct CarteVoyant: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        Carte(titre: "Voyant", icone: "light.beacon.max") {
            HStack(spacing: 14) {
                VoyantLed(motif: pont.etat.motifLed, depuis: pont.etat.motifLedDepuis, taille: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pont.etat.motifLed?.libelle ?? "inconnu")
                    if pont.etat.ledTest { Pastille(texte: "test en cours", couleur: .blue) }
                }
                Spacer()
                Button(pont.etat.ledTest ? "Arrêter" : "Tester") { pont.testerVoyant(!pont.etat.ledTest) }
                    .disabled(!pont.peutCommander)
            }
        }
    }
}

// MARK: - Systeme

private struct CarteSysteme: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let h = pont.etat.helloBase?.valeur
        let s = pont.etat.sante?.valeur.sys
        Carte(titre: "Système", icone: "cpu") {
            LigneInfo("Firmware", h?.fw, mono: true)
            LigneInfo("ESP-IDF", h?.idf)
            LigneInfo("Démarrage", h?.reset)
            LigneInfo("En marche depuis", Format.duree(secondes: pont.etat.upS))
            LigneInfo("Tas libre", s.map { "\(Format.octets($0.heap)) (au plus bas \(Format.octets($0.heapMin)))" })
            if let piles = s?.piles {
                LigneInfo("Piles (au plus bas)", piles.sorted { $0.key < $1.key }
                    .map { "\($0.key) \($0.value.map(String.init) ?? "–")" }.joined(separator: ", "))
            }
            LigneInfo("Lignes perdues", "\(s?.jsonPerdus ?? 0) au pont, \(pont.statistiques.pertes) sur le fil",
                      couleur: (s?.jsonPerdus ?? 0) + pont.statistiques.pertes > 0 ? .orange : nil)
            LigneInfo("Lignes abîmées", String(pont.reception.lignesAbimees))
        }
    }
}

// MARK: - Appairage

private struct CarteAppairage: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        let m = pont.etat.matter?.valeur
        Carte(titre: "Ajouter à Maison", icone: "qrcode.viewfinder", accent: .blue) {
            if let code = m?.codeManuel {
                HStack(alignment: .top, spacing: 16) {
                    if let qr = m?.qr { ImageCodeQR(charge: qr, cote: 168) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Le pont attend d'être ajouté à Maison.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Dans Maison : + › Ajouter un accessoire, puis scanner ce code. Sans appareil photo : « Plus d'options » et le code à 11 chiffres.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CodeManuel(code: code)
                        Text("L'iPhone près du pont : la mise en service passe par le Bluetooth.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
            } else {
                Text("Le pont n'est pas encore mis en service ; ses codes d'appairage arrivent avec le bloc réseau.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
            }
        }
    }
}

/// Code manuel groupe comme dans Maison, selectionnable, et un bouton pour le copier.
private struct CodeManuel: View {
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: CodeAppairage.lisible(code))
                .font(.title2.monospaced().weight(.semibold))
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copie les chiffres du code manuel")
        }
    }
}

/// QR code Matter en noir sur blanc, avec sa marge de silence (lisible en mode sombre
/// aussi) ; rien si la charge n'est pas un `MT:...`.
private struct ImageCodeQR: View {
    let charge: String
    let cote: CGFloat

    var body: some View {
        if CodeAppairage.chargeValide(charge), let image = CodeQR.image(charge) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: cote, height: cote)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.1)))
                .accessibilityLabel(Text("QR code Matter"))
                .help(Text(verbatim: charge))
        }
    }
}

enum CodeQR {
    static func image(_ texte: String) -> NSImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(texte.utf8)
        filtre.correctionLevel = "M"
        guard let sortie = filtre.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: sortie)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
````

`apps/macos/AmaranCompagnon/Vues/Cles.swift` (contenu complet) :

````swift
// Panneau « Cles » (spec 3b, section 5) : trois colonnes d'empreintes (amaran Desktop,
// ce Mac, le pont), l'ecart et le geste qui convient, la sauvegarde chiffree. Aucune
// cle n'est jamais affichee.
import AmaranProtocole
import AppKit
import SwiftUI

struct CarteCles: View {
    @Environment(Pont.self) private var pont
    @State private var confirmerChargement: SourceCles?
    @State private var exporter = false
    @State private var importer = false

    var body: some View {
        Carte(titre: "Clés", icone: "key", accent: pont.ecartsCles.isEmpty ? .secondary : .orange) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Réseau").foregroundStyle(.secondary)
                    Text("Application").foregroundStyle(.secondary)
                    Text("Lampes").foregroundStyle(.secondary)
                }
                ligne("amaran Desktop", pont.base, absent: pont.erreurBase ?? (pont.dossierAmaran == nil ? "dossier non autorisé" : "non lue"))
                ligne("Ce Mac", pont.copie, absent: "aucune copie")
                ligne("Le pont", pont.apercuPont, absent: pont.etat.mesh == nil ? "–" : "sans clés")
            }
            .font(.callout)
            ForEach(pont.ecartsCles, id: \.texte) { e in
                Label(e.texte, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(pont.modelesACataloguer, id: \.texte) { m in
                Label(m.texte, systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .echec(let raison) = pont.chargement {
                Label(raison, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .reussi(let d) = pont.chargement {
                Label("Pont chargé \(d.formatted(.relative(presentation: .named))).", systemImage: "checkmark.seal")
                    .foregroundStyle(.green).font(.callout)
            }
            HStack {
                if pont.dossierAmaran == nil && !pont.estDemo {
                    Button("Autoriser le dossier d'amaran Desktop…") { ChoixFichiers.dossierAmaran(pont) }
                } else {
                    Button("Copier depuis amaran Desktop") { pont.copierDepuisAmaranDesktop() }
                    Button("Relire") { pont.relireBase() }
                }
                Menu("Charger le pont") {
                    Button("Depuis amaran Desktop") { confirmerChargement = .amaranDesktop }
                        .disabled(pont.dossierAmaran == nil && !pont.estDemo)
                    Button("Depuis la copie de ce Mac") { confirmerChargement = .trousseau }
                        .disabled(pont.copie == nil)
                }
                .disabled(!pont.peutCommander || pont.chargement.actif)
                .fixedSize()
            }
            .controlSize(.small)
            HStack {
                Button("Exporter une sauvegarde…") { exporter = true }
                    .disabled(pont.copie == nil)
                Button("Importer une sauvegarde…") { importer = true }
                if let d = pont.derniereSauvegarde {
                    Text("dernière : \(d.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
        .confirmationDialog("Charger le pont ?", isPresented: Binding(get: { confirmerChargement != nil },
                                                                      set: { if !$0 { confirmerChargement = nil } })) {
            Button("Charger et redémarrer le pont") {
                if let s = confirmerChargement { pont.chargerPont(depuis: s) }
            }
        } message: {
            Text("Le pont reçoit les clés et la liste des lampes par l'USB, les vérifie, puis redémarre. Maison garde les lampes déjà connues (même MAC).")
        }
        .sheet(isPresented: $exporter) { FeuilleExport() }
        .sheet(isPresented: $importer) { FeuilleImport() }
    }

    @ViewBuilder
    private func ligne(_ titre: String, _ a: ApercuReseau?, absent: String) -> some View {
        GridRow {
            Text(verbatim: titre)
            if let a {
                Text(verbatim: a.empreinteReseau).monospaced()
                Text(verbatim: a.empreinteApplication).monospaced()
                Text(verbatim: "\(a.lampes.count)")
            } else {
                Text(verbatim: absent).foregroundStyle(.secondary).gridCellColumns(3)
            }
        }
    }
}

/// Panneaux du systeme : le dossier d'amaran Desktop (signet), les sauvegardes.
@MainActor
enum ChoixFichiers {
    static func dossierAmaran(_ pont: Pont) {
        let p = NSOpenPanel()
        p.message = "Choisir le dossier « amaran Desktop » (Bibliothèque › Containers › amaran Desktop › Data › Library › Application Support) : l'app le lira, sans jamais y écrire."
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.showsHiddenFiles = true
        p.directoryURL = BaseAmaranDesktop.dossierHabituel
        if p.runModal() == .OK, let url = p.url { pont.autoriserDossier(url) }
    }

    static func enregistrerSauvegarde() -> URL? {
        let p = NSSavePanel()
        p.message = "Où ranger la sauvegarde chiffrée ? iCloud Drive la garde même si ce Mac est perdu."
        p.nameFieldStringValue = "Réseau amaran.sauvegarde"
        return p.runModal() == .OK ? p.url : nil
    }

    static func ouvrirSauvegarde() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.url : nil
    }
}

/// « Exporter une sauvegarde » : la phrase de passe deux fois, jamais gardee.
private struct FeuilleExport: View {
    @Environment(Pont.self) private var pont
    @Environment(\.dismiss) private var fermer
    @State private var phrase = ""
    @State private var confirmation = ""
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Exporter une sauvegarde chiffrée", systemImage: "lock.doc").font(.title3.weight(.semibold))
            Text("La copie des clés de ce Mac, chiffrée par une phrase de passe (12 caractères au moins). Sans elle, la sauvegarde est perdue : rien ne permet de la retrouver.")
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Phrase de passe", text: $phrase)
            SecureField("La même, une seconde fois", text: $confirmation)
            if let erreur { Text(verbatim: erreur).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { fermer() }
                Button("Exporter…") {
                    do {
                        try Sauvegarde.verifierPhrase(phrase, confirmation: confirmation)
                        guard let url = ChoixFichiers.enregistrerSauvegarde() else { return }
                        try pont.exporterSauvegarde(vers: url, phrase: phrase, confirmation: confirmation)
                        phrase = ""
                        confirmation = ""
                        fermer()
                    } catch {
                        erreur = String(describing: error)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// « Importer une sauvegarde » : fichier, phrase, empreintes, puis remplacer la copie.
private struct FeuilleImport: View {
    @Environment(Pont.self) private var pont
    @Environment(\.dismiss) private var fermer
    @State private var fichier: URL?
    @State private var phrase = ""
    @State private var lue: ReseauMesh?
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Importer une sauvegarde chiffrée", systemImage: "lock.open").font(.title3.weight(.semibold))
            HStack {
                Text(verbatim: fichier?.lastPathComponent ?? "Aucun fichier choisi").foregroundStyle(.secondary)
                Spacer()
                Button("Choisir…") { fichier = ChoixFichiers.ouvrirSauvegarde() }
            }
            SecureField("Phrase de passe", text: $phrase)
            if let lue {
                let a = lue.apercu
                Text(verbatim: "Empreintes \(a.empreinteReseau) \(a.empreinteApplication), \(a.lampes.count) lampe(s) : \(a.lampes.map(\.nom).joined(separator: ", ")).")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let erreur { Text(verbatim: erreur).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { fermer() }
                if let lue {
                    Button("Remplacer la copie de ce Mac") {
                        do {
                            try pont.remplacerCopie(par: lue)
                            fermer()
                        } catch {
                            erreur = String(describing: error)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Ouvrir") {
                        guard let fichier else { return }
                        do {
                            lue = try pont.lireSauvegarde(fichier, phrase: phrase)
                            phrase = ""
                            erreur = nil
                        } catch {
                            erreur = String(describing: error)
                        }
                    }
                    .disabled(fichier == nil || phrase.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
````

- [ ] **Step 4 : commandes et console.**

`apps/macos/AmaranCompagnon/Vues/CommandesEtConsole.swift` (contenu complet) :

````swift
// Ecran « Commandes et console » (spec 3b, section 8) : une lampe choisie a gauche, la
// console brute de Halo Compagnon (commit e114cd5) a droite.
import AmaranProtocole
import SwiftUI

struct CommandesEtConsole: View {
    var body: some View {
        HSplitView {
            PanneauCommandes()
                .frame(minWidth: 380, idealWidth: 440, maxWidth: 540)
            ConsoleBrute()
                .frame(minWidth: 420)
        }
    }
}

// MARK: - Commandes

private struct PanneauCommandes: View {
    @Environment(Pont.self) private var pont
    @State private var choisie = 1
    @State private var niveau: Double = 50
    @State private var glisse = false
    @State private var confirmerRetrait = false
    @State private var releve = 2

    var body: some View {
        let lampes = pont.lampes
        let lampe = lampes.first { $0.numero == choisie }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Lampe", selection: $choisie) {
                    ForEach(lampes) { l in Text(verbatim: "\(l.numero) · \(l.nom)").tag(l.numero) }
                }
                if let lampe {
                    Carte(titre: lampe.nom, icone: "lightbulb") {
                        LigneInfo("État lu", Interpretation.etat(lampe.etat?.lue))
                        LigneInfo("Maison", Interpretation.maison(lampe.etat?.maison))
                        HStack {
                            Button("Allumer") { pont.allumer(lampe: lampe.numero, true) }
                            Button("Éteindre") { pont.allumer(lampe: lampe.numero, false) }
                            Button("Relire") { pont.relire(lampe: lampe.numero) }
                        }
                        HStack {
                            Text("Niveau").foregroundStyle(.secondary)
                            Slider(value: $niveau, in: 0...100, step: 1) { en in
                                glisse = en
                                pont.niveau(lampe: lampe.numero, pourCent: Int(niveau), fini: !en)
                            }
                            .onChange(of: niveau) { _, v in
                                if glisse { pont.niveau(lampe: lampe.numero, pourCent: Int(v), fini: false) }
                            }
                            Text(verbatim: "\(Int(niveau)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        if lampe.dansMaison {
                            Button("Retirer de Maison…") { confirmerRetrait = true }
                        } else {
                            Button("Remettre dans Maison") { pont.exposer(lampe: lampe.numero, dansMaison: true) }
                        }
                    }
                    .confirmationDialog("Retirer « \(lampe.nom) » de Maison ?", isPresented: $confirmerRetrait) {
                        Button("Retirer de Maison", role: .destructive) { pont.exposer(lampe: lampe.numero, dansMaison: false) }
                    } message: {
                        Text(verbatim: Pont.avertissementRetrait)
                    }
                }
                Carte(titre: "Relecture des lampes", icone: "arrow.triangle.2.circlepath") {
                    Stepper(value: $releve, in: 1...60) {
                        Text(verbatim: "Toutes les \(releve) s")
                    }
                    Button("Appliquer") { pont.reglerReleve(secondes: releve) }
                        .disabled(pont.etat.mesh?.valeur.releveMs == releve * 1000)
                }
                Carte(titre: "Commandes récentes", icone: "list.bullet.rectangle") {
                    let recents = pont.suivis.filter { $0.origine != .session }.suffix(12).reversed()
                    if recents.isEmpty {
                        Text("Aucune commande envoyée.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recents)) { s in LigneSuivi(suivi: s) }
                }
            }
            .padding(14)
            .disabled(!pont.peutCommander)
        }
        .onAppear { recopier() }
        .onChange(of: pont.etat.lampes[choisie]?.valeur.lue) { _, _ in recopier() }
        .onChange(of: choisie) { _, _ in recopier() }
    }

    /// Le curseur suit l'etat lu, sauf pendant le glissement et tant que sa valeur
    /// finale n'est pas partie.
    private func recopier() {
        if let m = pont.etat.mesh?.valeur.releveMs { releve = m / 1000 }
        guard !glisse, !pont.suivis.contains(where: { $0.fusion == "niveau\(choisie)" && !$0.etat.estFinal }),
              let i = pont.etat.lampes[choisie]?.valeur.lue?.intensite else { return }
        niveau = Double(i / 10)
    }
}

private struct LigneSuivi: View {
    let suivi: SuiviCommande

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: suivi.numero.map { "id=\($0)" } ?? "–").font(.caption.monospaced()).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(verbatim: suivi.commande).font(.callout.monospaced()).lineLimit(1)
            Spacer()
            Pastille(texte: libelle, couleur: couleur)
        }
        .help(aide)
    }

    private var libelle: String {
        if suivi.etat == .terminee, let f = suivi.fin, !f.ok { return Interpretation.code(f.code) }
        return suivi.etat.libelle
    }

    private var couleur: Color {
        switch suivi.etat {
        case .confirmee, .tenue: .green
        case .terminee: suivi.fin?.ok == false ? .red : .green
        case .abandonnee, .sansReponse, .perdue, .ordrePerdu: .red
        case .attenteOrdre, .envoyee, .enCours: .orange
        case .remplacee, .finPerdue: .secondary
        case .enFile: .blue
        }
    }

    private var aide: String {
        var s = suivi.commande
        if let f = suivi.fin { s += "\n" + Interpretation.reponse(f) }
        if let o = suivi.ordre { s += "\n" + Interpretation.ordre(o) }
        return s
    }
}

extension EtatCommande {
    var libelle: String {
        switch self {
        case .enFile: "en file"
        case .envoyee: "envoyée"
        case .enCours: "en cours"
        case .terminee: "ok"
        case .attenteOrdre: "ordre en cours"
        case .confirmee: "confirmée"
        case .abandonnee: "abandonnée"
        case .tenue: "déjà tenue"
        case .ordrePerdu: "issue perdue"
        case .sansReponse: "sans réponse"
        case .finPerdue: "fin perdue"
        case .remplacee: "remplacée"
        case .perdue: "perdue"
        }
    }
}

// MARK: - Console

private struct ConsoleBrute: View {
    @Environment(Pont.self) private var pont
    @State private var saisie = ""
    @State private var erreur: String?
    @State private var aConfirmer: (ligne: String, raison: String)?
    @State private var historique: [String] = []
    @State private var positionHistorique: Int?
    @State private var logsSysteme = true
    @State private var session = false
    @State private var defilement = true
    @FocusState private var focus: Bool

    var body: some View {
        let lignes = pont.console.elements.filter(visible).suffix(2000)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Console").font(.headline)
                Spacer()
                Toggle("Journaux d'ESP-IDF", isOn: $logsSysteme)
                Toggle("Session (ping, json 1)", isOn: $session)
                Toggle("Défilement", isOn: $defilement)
                Button("Vider") { pont.viderConsole() }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lignes) { l in
                            LigneConsoleVue(ligne: l).id(l.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: pont.console.elements.last?.id) { _, id in
                    if defilement, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            saisieVue
        }
        .alert("Confirmer la commande", isPresented: Binding(get: { aConfirmer != nil }, set: { if !$0 { aConfirmer = nil } }),
               presenting: aConfirmer) { c in
            Button("Envoyer « \(PolitiqueCommandes.masquerCle(c.ligne)) »", role: .destructive) {
                traiter(pont.console(c.ligne, confirme: true), ligne: c.ligne)
            }
            Button("Annuler", role: .cancel) {}
        } message: { c in
            Text(verbatim: c.raison)
        }
    }

    private var saisieVue: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: pont.consoleAvecId ? "id=…" : "brut").font(.caption.monospaced()).foregroundStyle(.secondary)
                TextField("commande de la console (ex. mesh, lampes, help)", text: $saisie)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($focus)
                    .onSubmit(soumettre)
                    .onKeyPress(.upArrow) { naviguer(-1) }
                    .onKeyPress(.downArrow) { naviguer(1) }
                Button("Envoyer", action: soumettre)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saisie.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                if let erreur {
                    Text(verbatim: erreur).foregroundStyle(.red)
                } else if !pont.consoleAvecId, pont.phase != .ferme {
                    Text(verbatim: "Console seule (\(pont.phase.libelle)) : lignes envoyées sans id, sans corrélation.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Chaque ligne part avec un id : le texte reçu entre réponse début et fin lui est rattaché.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Prefixe "id=<n> " : 13 octets au plus (n <= 999999999).
                let octets = saisie.utf8.count + (pont.consoleAvecId ? 13 : 0)
                Text(verbatim: "\(octets) / \(LigneCommande.octetsMax) octets")
                    .foregroundStyle(octets > LigneCommande.octetsMax ? .red : .secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .padding(10)
    }

    private func visible(_ l: LigneConsole) -> Bool {
        switch l.genre {
        case .texte(let c): return logsSysteme || !c.estLogSysteme
        case .fragment: return logsSysteme
        case .envoi(let o): return session || o != .session
        case .retour(_, let s): return session || !s
        default: return true
        }
    }

    private func soumettre() {
        let ligne = saisie.trimmingCharacters(in: .whitespaces)
        guard !ligne.isEmpty else { return }
        traiter(pont.console(ligne), ligne: ligne)
    }

    private func traiter(_ r: Pont.ResultatConsole, ligne: String) {
        switch r {
        case .envoyee:
            erreur = nil
            // Jamais de cle dans l'historique de saisie.
            if PolitiqueCommandes.masquerCle(ligne) == ligne, historique.last != ligne { historique.append(ligne) }
            positionHistorique = nil
            saisie = ""
        case .confirmation(let raison):
            aConfirmer = (ligne, raison)
        case .refusee(let raison):
            erreur = raison
        }
    }

    private func naviguer(_ sens: Int) -> KeyPress.Result {
        guard !historique.isEmpty else { return .ignored }
        let p = (positionHistorique ?? historique.count) + sens
        if p >= historique.count {
            positionHistorique = nil
            saisie = ""
        } else {
            positionHistorique = max(0, p)
            saisie = historique[max(0, p)]
        }
        return .handled
    }
}

private struct LigneConsoleVue: View {
    let ligne: LigneConsole

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: Format.heure(ligne.date))
                .foregroundStyle(.tertiary)
            Text(verbatim: ligne.texte)
                .foregroundStyle(couleur)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.leading, ligne.numero != nil && estTexte ? 14 : 0)
    }

    private var estTexte: Bool {
        if case .texte = ligne.genre { return true }
        return false
    }

    private var couleur: Color {
        switch ligne.genre {
        case .envoi(let o): o == .session ? .secondary : .accentColor
        case .texte(let c):
            switch c {
            case .logIDF: .secondary
            case .annonce: .purple
            case .demarrage: .orange
            default: .primary
            }
        case .fragment: .gray
        case .retour(let ok, let s): s ? .secondary : (ok ? .green : .red)
        case .log: .purple
        case .note(let grave): grave ? .red : .teal
        }
    }
}
````

- [ ] **Step 5 : les réglages, puis l'app.**

`apps/macos/AmaranCompagnon/Vues/Reglages.swift` (contenu complet) :

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
    }
}

/// Onglet General : le dossier d'amaran Desktop autorise, la derniere sauvegarde.
struct ReglagesGeneral: View {
    @Environment(Pont.self) private var pont

    var body: some View {
        Form {
            Section("amaran Desktop") {
                LabeledContent("Dossier autorisé") {
                    Text(verbatim: pont.dossierAmaran?.path(percentEncoded: false) ?? "aucun")
                        .foregroundStyle(pont.dossierAmaran == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Changer…") { ChoixFichiers.dossierAmaran(pont) }
                if let e = pont.erreurBase {
                    Text(verbatim: e).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                LabeledContent("Dernière exportée") {
                    Text(verbatim: pont.derniereSauvegarde?.formatted(date: .long, time: .shortened) ?? "jamais")
                }
            } header: {
                Text("Sauvegarde chiffrée")
            } footer: {
                Text("L'app lit la base d'amaran Desktop sans jamais y écrire. La copie des clés reste dans le trousseau de ce Mac ; une sauvegarde chiffrée la garde ailleurs (iCloud Drive), si ce Mac est perdu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
````

`apps/macos/AmaranCompagnon/AmaranCompagnonApp.swift` (contenu complet) :

````swift
// Repris de Halo Compagnon (commit e114cd5) : fenetre, menus, reglages ; francais seulement.
import AmaranProtocole
import SwiftUI

@main
struct AmaranCompagnonApp: App {
    @State private var pont = Pont()

    /// `--args -ecran commandes` : ecran affiche au lancement.
    private static var ecranDemande: Ecran {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "-ecran"), i + 1 < a.count, let e = Ecran(rawValue: a[i + 1]) else { return .tableau }
        return e
    }

    var body: some Scene {
        WindowGroup("Amaran Compagnon", id: "principale") {
            ContenuPrincipal(ecranInitial: Self.ecranDemande)
                .environment(pont)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    // "Amaran Compagnon.app" --args -demo : demarre directement en mode demo.
                    if CommandLine.arguments.contains("-demo"), pont.source == nil { pont.connecter(.demo) }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Mode démo") { pont.connecter(.demo) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Rafraîchir l'état (json etat)") { pont.rafraichir() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!pont.peutCommander)
                Divider()
                Button("Libérer le port") { pont.libererPort() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(pont.phase == .ferme || pont.estDemo)
            }
        }

        Settings {
            FenetreReglages()
                .environment(pont)
        }
    }
}
````

- [ ] **Step 6 : lancer les tests, tout est vert.**

Run: `cd apps/macos && xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd test 2>&1 | /usr/bin/grep -E '(swift:[0-9]+:[0-9]+: (error|warning)|Test run with|[*][*] TEST)' ; cd ../..`
Expected : `Test run with 85 tests in 13 suites passed` et `Test run with 9 tests in 3 suites passed`, puis `** TEST SUCCEEDED **`, sans avertissement.

- [ ] **Step 7 : l'app démarre en mode démo.** Pas de port réel : le mode démo seulement. L'app tourne 20 s, puis une alarme l'arrête (`timeout` n'existe pas sur macOS) :

```bash
perl -e 'alarm 20; exec { $ARGV[0] } @ARGV' "apps/macos/build/dd/Build/Products/Debug/Amaran Compagnon.app/Contents/MacOS/Amaran Compagnon" -demo -ecran commandes >/dev/null 2>&1; echo "code $?"
```

Expected : `code 142` : l'app tournait encore quand l'alarme l'a arrêtée. Un autre code : elle s'est arrêtée seule ; le plus récent des rapports `Amaran Compagnon-*.ips` de `~/Library/Logs/DiagnosticReports/` dit pourquoi.

> **Amendement (exécution, 05/10)** : la relecture a montré que « Connecter », sans source choisie, ouvrait le premier port Espressif (peut-être la C6 du maillage BenQ). Correctif en un commit à part : l'app retient le numéro de série du dernier pont choisi au menu, « Connecter » ne vise que lui (grisé sinon), avec un test ; le dialogue « Charger le pont » prend la forme `presenting:` ; la feuille d'import relâche le réseau déchiffré. `AmaranCompagnonTests` compte désormais 11 tests ; le README de l'app (Task 10) le dit.

- [ ] **Step 8 : commit.**

```bash
git add apps/macos
git commit -m "$(printf "App compagnon : ecrans (tableau de bord, commandes et console, reglages)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 10: La documentation : README du dépôt, README de l'app, spec

**Files:**
- Create: `apps/macos/README.md`
- Modify: `README.md`, `docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`

**Interfaces:**
- Consumes : tout ce que les Tasks 1 à 9 ont fait ; les choix fixés de ce plan (en tête).
- Produces : rien pour le code. Le README du dépôt a une ligne `P3b-1` (« en cours ») que la Task 11 complète.

Pourquoi : la spec 3b, section 4 (ce qui ne change pas : la console texte et `outils/cles_amaran.py` restent), et la règle des plans précédents : la spec dit ce qui a été construit. Le README du dépôt gagne :
- la ligne `P3b-1` du tableau des phases, et le lien vers `docs/PROTOCOLE-JSON.md` ;
- une section « L'app compagnon » : ce qu'elle fait, où elle lit la base, la copie dans le trousseau, la sauvegarde, le chargement, le mode démo ;
- la commande `json …` dans la liste de la console, et la réponse à une commande inconnue ;
- dans « À savoir », la console texte retire les accents des noms : l'app les garde ;
- dans « Clés du réseau » et les remerciements, l'app.

Le README de l'app dit comment compiler, tester, signer (`Local.xcconfig`), changer d'icône sans la versionner, lancer (`-demo`, `-ecran commandes`), et comment le code est rangé. La spec reçoit les choix 1 à 7 de ce plan (section 4 : `components/protocole` ; section 6 : UTF-8, codes de `reponse`, notre tâche de console, `commande` dans `sante` et `hb`, ordres `tenu`) ; sa décision 9 dit où vit chaque icône (choix 14) ; sa section 12 dit les risques levés en préparant le plan, et où se lève celui du signet.

- [ ] **Step 1 : le README de l'app.**

`apps/macos/README.md` (contenu complet) :

````markdown
# Amaran Compagnon

L'app macOS du pont amaran : supervision, commandes et console par l'USB, et gestion des clés du réseau Bluetooth Mesh des lampes. Copie adaptée de Halo Compagnon (le pont BenQ Halo du même auteur). La spec : [docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md](../../docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) ; le protocole du pont : [docs/PROTOCOLE-JSON.md](../../docs/PROTOCOLE-JSON.md).

## Compiler

Il faut Xcode 26 ou plus et XcodeGen (`brew install xcodegen`). Le projet Xcode est généré : `project.yml` fait foi.

```bash
cd apps/macos
xcodegen generate
xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' build
```

Les tests (Swift Testing) :

```bash
xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' test
```

Ils n'utilisent ni le pont ni le trousseau du Mac : le pont simulé du mode démo, un trousseau en mémoire, une base d'amaran Desktop factice. Le vrai trousseau ne sert que sur demande : `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild … test`.

## Signature

Par défaut, l'app est signée ad hoc : le dépôt compile partout, sans compte Apple. Mais une app ad hoc perd l'accès au trousseau, et au dossier d'amaran Desktop autorisé, à chaque compilation. Pour qu'ils tiennent, signer avec son équipe : créer `Local.xcconfig` (ignoré par git) à côté de `Signature.xcconfig` :

```
DEVELOPMENT_TEAM = <équipe, 10 caractères>
CODE_SIGN_IDENTITY = Apple Development
ENABLE_HARDENED_RUNTIME = YES
```

L'équipe : `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject` (champ OU). Un compte développeur gratuit suffit : l'app n'a aucun droit restreint.

## Icône

Le dépôt porte une icône libre (A2 : une constellation qui trace un A, sur fond rouge), au format Icon Composer : `AmaranCompagnon/Ressources/AppIcon.icon`. Son calque se refait depuis `Outils/constellation-a.svg` :

```bash
rsvg-convert -w 1024 -h 1024 Outils/constellation-a.svg -o AmaranCompagnon/Ressources/AppIcon.icon/Assets/constellation-a.png
```

Une icône locale peut la remplacer sans être versionnée : la poser dans `AmaranCompagnon/Ressources/AppIconM2.icon` (ignoré par git), puis ajouter à `Local.xcconfig` :

```
ASSETCATALOG_COMPILER_APPICON_NAME = AppIconM2
```

et refaire `xcodegen generate`. Seule l'icône nommée entre dans l'app.

## Lancer

- `open "<DerivedData>/Build/Products/Debug/Amaran Compagnon.app" --args -demo` : démarre en mode démo (pont simulé à trois lampes) ;
- `--args -ecran commandes` : ouvre l'écran des commandes.

L'app ne s'ouvre jamais seule sur un port : choisir le pont (VID 303A) dans le menu de la barre latérale, la connexion part aussitôt. Ensuite, « Connecter » vise ce même pont, reconnu à son numéro de série USB, jamais un autre port Espressif. Ouvrir le port ne redémarre pas le pont : DTR et RTS passent à 0 en un seul appel. « Libérer le port » rend la console texte au pont (`json 0`) et ferme le port, pour flasher.

## Structure

- `AmaranProtocole/` : le protocole, sans interface : tramage, session et corrélation (repris de Halo Compagnon), messages du pont, clés (base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison).
- `AmaranCompagnon/` : l'app SwiftUI : port série, modèle `Pont`, trousseau, écrans, mode démo.
- `AmaranProtocoleTests/`, `AmaranCompagnonTests/` : les tests. `ExemplesSpecTests` lit les exemples de `docs/PROTOCOLE-JSON.md`, que le firmware forme tels quels (`tests/hote/test_json.cpp`).
````

- [ ] **Step 2 : le README du dépôt.**

`README.md`, bloc 1 sur 7. Remplacer :

````markdown
| P2 | Produit : voyant, bouton, console, fiche produit ; bancs, puis endurance 24 h | faite (02/10/2026) : T1 à T10 (T5 partiel, T7 non fait) ; 24 h sans redémarrage, 97,9 % et 98,3 % des relectures répondues, 41 salves d'ordres sans échec ; lampe noire (molette à 0 %) corrigée et vérifiée |
| P3a | N lampes : liste, catalogue de modèles, numéros d'endpoint stables, exposition à la première réponse | faite (05/10/2026) : bancs 1 à 4 ; migration sans perte dans Maison ; 16 lampes tenues (tas au plus bas 103 Ko) ; une lampe masquée puis remise est oubliée par Maison, donc pas de masquage automatique |

Résultats des bancs : [docs/BANC.md](docs/BANC.md). Protocole relevé : [docs/PROTOCOLE.md](docs/PROTOCOLE.md).

## Ce que fait le pont
````

par :

````markdown
| P2 | Produit : voyant, bouton, console, fiche produit ; bancs, puis endurance 24 h | faite (02/10/2026) : T1 à T10 (T5 partiel, T7 non fait) ; 24 h sans redémarrage, 97,9 % et 98,3 % des relectures répondues, 41 salves d'ordres sans échec ; lampe noire (molette à 0 %) corrigée et vérifiée |
| P3a | N lampes : liste, catalogue de modèles, numéros d'endpoint stables, exposition à la première réponse | faite (05/10/2026) : bancs 1 à 4 ; migration sans perte dans Maison ; 16 lampes tenues (tas au plus bas 103 Ko) ; une lampe masquée puis remise est oubliée par Maison, donc pas de masquage automatique |
| P3b-1 | App compagnon par l'USB : mode JSON du pont ; clés d'amaran Desktop (trousseau, sauvegarde chiffrée, chargement du pont) ; tableau de bord, commandes et console, démo | en cours |

Résultats des bancs : [docs/BANC.md](docs/BANC.md). Protocole relevé : [docs/PROTOCOLE.md](docs/PROTOCOLE.md). Protocole machine du pont, pour l'app : [docs/PROTOCOLE-JSON.md](docs/PROTOCOLE-JSON.md).

## Ce que fait le pont
````

`README.md`, bloc 2 sur 7. Remplacer :

````markdown
   Pour mettre à jour un pont déjà appairé : `flash` sans `erase-flash` (sinon Maison perd tout), et supprimer d'abord `firmware/sdkconfig` pour que les réglages de `sdkconfig.defaults` s'appliquent. La première mise à jour vers les N lampes convertit la liste des lampes et efface l'ancien format : sauvegarder avant la flash entière (`esptool.py read_flash 0 0x400000 <fichier>`, gardé hors du dépôt : il contient les clés).

2. Charger les clés du réseau des lampes, lues dans la base d'amaran Desktop :

   ```bash
````

par :

````markdown
   Pour mettre à jour un pont déjà appairé : `flash` sans `erase-flash` (sinon Maison perd tout), et supprimer d'abord `firmware/sdkconfig` pour que les réglages de `sdkconfig.defaults` s'appliquent. La première mise à jour vers les N lampes convertit la liste des lampes et efface l'ancien format : sauvegarder avant la flash entière (`esptool.py read_flash 0 0x400000 <fichier>`, gardé hors du dépôt : il contient les clés).

2. Charger les clés du réseau des lampes, lues dans la base d'amaran Desktop : avec l'app compagnon (carte « Clés », « Charger le pont »), ou en ligne de commande :

   ```bash
````

`README.md`, bloc 3 sur 7. Remplacer :

````markdown

Carte déjà servie : `erase-flash` fait tirer au pont une nouvelle adresse Mesh au hasard (`0x7F00` à `0x7F7F`). Dans environ 1 cas sur 128 par adresse déjà employée, elle retombe sur une adresse que les lampes connaissent, et elles ignorent alors le pont, sans message d'erreur. Si toutes les lampes restent muettes (`lampes` : « lue jamais ») sans autre alerte de la console, taper `mesh adresse suivante` : le pont prend l'adresse voisine, repart de zéro et redémarre.

## Voyant et bouton
````

par :

````markdown

Carte déjà servie : `erase-flash` fait tirer au pont une nouvelle adresse Mesh au hasard (`0x7F00` à `0x7F7F`). Dans environ 1 cas sur 128 par adresse déjà employée, elle retombe sur une adresse que les lampes connaissent, et elles ignorent alors le pont, sans message d'erreur. Si toutes les lampes restent muettes (`lampes` : « lue jamais ») sans autre alerte de la console, taper `mesh adresse suivante` : le pont prend l'adresse voisine, repart de zéro et redémarre.

## L'app compagnon

Amaran Compagnon (`apps/macos`) supervise et pilote le pont par l'USB : une carte par lampe, le Bluetooth Mesh, Matter, le voyant, et la console du pont. Elle gère aussi les clés du réseau des lampes, à la place de `outils/cles_amaran.py` :
- elle lit la base d'amaran Desktop, sans jamais y écrire (Réglages, « Changer… » : désigner une fois le dossier `amaran Desktop` de `~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support`) ;
- elle en garde une copie dans le trousseau de ce Mac, et l'exporte sur demande en sauvegarde chiffrée par une phrase de passe (iCloud Drive conseillé) ;
- elle charge le pont par l'USB, vérifie ses empreintes et sa liste, puis le redémarre ;
- elle compare les empreintes de la base, de la copie et du pont, sans jamais montrer une clé.

Le mode démo (menu Source, ou ⇧⌘D) simule un pont à trois lampes, sans matériel. Compiler : voir [apps/macos/README.md](apps/macos/README.md).

## Voyant et bouton
````

`README.md`, bloc 4 sur 7. Remplacer :

````markdown
- `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` : la liste des lampes, tout ou rien (c'est ce qu'envoie `outils/cles_amaran.py`) ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre`.

## À savoir
````

par :

````markdown
- `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` : la liste des lampes, tout ou rien (c'est ce qu'envoie `outils/cles_amaran.py`) ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre` ;
- `json …` : le mode machine de l'app compagnon ([docs/PROTOCOLE-JSON.md](docs/PROTOCOLE-JSON.md)). Le pont démarre toujours en console texte ; `json 1` passe en mode machine, `json 0` (ou 30 s sans rien de l'app) revient au texte.

Une commande inconnue répond `Commande inconnue : "<nom>" (help)`.

## À savoir
````

`README.md`, bloc 5 sur 7. Remplacer :

````markdown
- Si une lampe joignable manque plus de 5 % de ses relectures sur 10 minutes, la console le dit (`!! lampe <n> : relectures manquees, <p> % repondues sur 10 min`) : allonger la période (`mesh releve`). Le premier verdict vient au plus tôt 10 minutes après le démarrage ; après un démarrage tardif du Mesh, ou une lampe absente depuis 10 minutes ou plus, il attend 5 minutes de relectures.
- Bouton BOOT : juste après un appui annulé (tenu de 2 à 8 s, donc sans effet), relâcher net ; un effleurement redémarre le pont, sans conséquence (les clés et l'appairage restent).

## Clés du réseau
````

par :

````markdown
- Si une lampe joignable manque plus de 5 % de ses relectures sur 10 minutes, la console le dit (`!! lampe <n> : relectures manquees, <p> % repondues sur 10 min`) : allonger la période (`mesh releve`). Le premier verdict vient au plus tôt 10 minutes après le démarrage ; après un démarrage tardif du Mesh, ou une lampe absente depuis 10 minutes ou plus, il attend 5 minutes de relectures.
- Bouton BOOT : juste après un appui annulé (tenu de 2 à 8 s, donc sans effet), relâcher net ; un effleurement redémarre le pont, sans conséquence (les clés et l'appairage restent).
- Un nom de lampe accentué : la console texte (et donc `outils/cles_amaran.py`) en retire les caractères non ASCII. L'app compagnon, qui charge le pont en mode machine, les garde.

## Clés du réseau
````

`README.md`, bloc 6 sur 7. Remplacer :

````markdown
Qui détient les clés du réseau Bluetooth Mesh contrôle les lampes.
- Elles ne vont **jamais** dans ce dépôt.
- Un script les lit dans la base d'amaran Desktop et les charge dans l'ESP32
  par l'USB.

## amaran Desktop sur macOS 27
````

par :

````markdown
Qui détient les clés du réseau Bluetooth Mesh contrôle les lampes.
- Elles ne vont **jamais** dans ce dépôt.
- L'app compagnon, ou un script, les lit dans la base d'amaran Desktop et les
  charge dans l'ESP32 par l'USB, jamais par le réseau.

## amaran Desktop sur macOS 27
````

`README.md`, bloc 7 sur 7. Remplacer :

````markdown
Le voyant et le bouton BOOT reprennent la logique du pont Halo
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
du même auteur) : `components/socle`, avec ses tests.

Projet personnel, sans lien avec Aputure. Il n'ouvre ni ne modifie les lampes.
````

par :

````markdown
Le voyant et le bouton BOOT reprennent la logique du pont Halo
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
du même auteur) : `components/socle`, avec ses tests. Le mode JSON
(`components/protocole`) et l'app compagnon (`apps/macos`) sont une copie
adaptée de son protocole et de Halo Compagnon.

Projet personnel, sans lien avec Aputure. Il n'ouvre ni ne modifie les lampes.
````

- [ ] **Step 3 : la spec.**

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 1 sur 6. Remplacer :

````markdown
   sur le bleu-noir du logo (`#01101E`), entouré d'un maillage. Format Icon
   Composer, comme l'icône validée de Halo Compagnon (constellation). C'est la
   marque déposée d'Aputure : `AppIcon.icon` n'est pas versionné et reste sur
   le Mac de Djoko ; le dépôt public garde une icône libre de repli (« A2 » :
   une constellation qui trace un A, sur fond rouge), que la compilation prend
   quand M2 est absente.
10. **Français seulement** (règle du projet) : on ne reprend pas la traduction
    anglaise de Halo.
````

par :

````markdown
   sur le bleu-noir du logo (`#01101E`), entouré d'un maillage. Format Icon
   Composer, comme l'icône validée de Halo Compagnon (constellation). C'est la
   marque déposée d'Aputure : M2 n'est pas versionnée et reste sur le Mac de
   Djoko (`AppIconM2.icon`, ignorée par git, choisie par `Local.xcconfig`) ; le
   dépôt public porte une icône libre (« A2 » : une constellation qui trace un
   A, sur fond rouge, `AppIcon.icon`), que la compilation prend par défaut.
10. **Français seulement** (règle du projet) : on ne reprend pas la traduction
    anglaise de Halo.
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 2 sur 6. Remplacer :

````markdown

**Firmware :**
- `components/json` (3b-1) : écriture compacte et ordonnée, file des messages
  périodiques, cadence, bail, préfixe `id=`, cache des réponses, codes. Ce
  sont les modules purs de Halo, en C++ avec une interface C, testés sur le
  Mac ;
- `firmware/main` : la tâche `json`, qui relie ces modules à la console, à la
  liste des lampes, au cœur `lampes`, au Mesh et à Matter ;
````

par :

````markdown

**Firmware :**
- `components/protocole` (3b-1) : écriture compacte et ordonnée, file des
  messages périodiques, cadence, bail, préfixe `id=`, codes, et les messages du
  pont amaran. Ce sont les modules purs de Halo, en C++, testés sur le Mac. Pas
  `components/json` : c'est le nom du composant cJSON d'ESP-IDF, que le nôtre
  masquerait (vu en préparant le plan 3b-1) ;
- `firmware/main` : la tâche `json`, qui relie ces modules à la console, à la
  liste des lampes, au cœur `lampes`, au Mesh et à Matter ;
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 3 sur 6. Remplacer :

````markdown
**Le protocole v1 de Halo**, pour que le moteur de session de l'app se reprenne
tel quel :
- une ligne machine = `RS` (0x1E) + un objet JSON compact en ASCII + `LF`,
  1 024 octets au plus ; ses premiers champs sont toujours
  `v`, `t`, `n`, `ms` et, s'il y a lieu, `bloc` ;
- le pont démarre en console texte ; `json 1 [bail]` le passe en mode machine
  (sans écho ni invite) ; `json 0`, ou un bail expiré (30 s sans rien reçu), le
  ramène en texte ; `json ping` renouvelle le bail ;
- l'app envoie des lignes de console `id=<n> <commande>` (127 octets au plus) ;
  le pont répond par `reponse` (codes `ok`, `accepte`, `refuse`, `usage`,
  `inconnue`, `trop_long`, `cadence`, `interdite`, `deja_traite`…) ; une
  commande texte reçoit `reponse debut`, son texte, puis `reponse fin` ;
- les journaux d'ESP-IDF peuvent s'intercaler ; le compteur `n` trahit les
  lignes perdues.
````

par :

````markdown
**Le protocole v1 de Halo**, pour que le moteur de session de l'app se reprenne
tel quel :
- une ligne machine = `RS` (0x1E) + un objet JSON compact + `LF`, 1 024 octets
  au plus ; ses premiers champs sont toujours `v`, `t`, `n`, `ms` et, s'il y a
  lieu, `bloc`. Les chaînes passent en UTF-8 (les noms des lampes portent des
  accents), sans octet de contrôle ni `\uXXXX` ;
- le pont démarre en console texte ; `json 1 [bail]` le passe en mode machine
  (sans écho ni invite) ; `json 0`, ou un bail expiré (30 s sans rien reçu), le
  ramène en texte ; `json ping` renouvelle le bail ;
- l'app envoie des lignes de console `id=<n> <commande>` (127 octets au plus) ;
  le pont répond par `reponse` (codes `ok`, `accepte`, `en_cours`, `erreur`,
  `usage`, `inconnue`, `trop_long`, `cadence` ; `interdite` et `deja_traite`
  viendront avec Thread) ; une commande texte reçoit `reponse debut`, son
  texte, puis `reponse fin` : `ok` si elle a réussi, `erreur` sinon ;
- la console texte du pont n'est plus la REPL d'ESP-IDF : linenoise fait
  toujours l'écho de ce qu'il lit. Le pont a sa propre tâche de console :
  linenoise en mode texte, une lecture sans écho ni invite en mode machine. Un
  firmware d'avant le plan 3b répond `Unrecognized command` à `id=1 json 1` ;
- la tâche `json` émet pendant qu'une commande tourne. Le bloc `etat` `sante`
  et le battement `hb` portent l'`id` de la commande en cours (`commande`) :
  une `reponse fin` perdue s'y voit. Le bail ne court pas pendant une commande ;
- les journaux d'ESP-IDF peuvent s'intercaler ; le compteur `n` trahit les
  lignes perdues.
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 4 sur 6. Remplacer :

````markdown
**Ordres.** `lampe <n> on|off|niveau <0-1000>` répond aussitôt `accepte`,
puis l'événement `ordre` donne son issue : c'est la « livraison » de Halo,
branchée sur la sortie `signaler` du cœur `lampes`. `mesh lampe <n>
masquer|afficher` répond en une fois.

**Le firmware :**
````

par :

````markdown
**Ordres.** `lampe <n> on|off|niveau <0-1000>` répond aussitôt `accepte`,
puis l'événement `ordre` donne son issue : c'est la « livraison » de Halo,
branchée sur la sortie `signaler` du cœur `lampes`. Le cœur signale désormais
chaque ordre : `confirme`, `abandon`, ou `tenu` (la lampe était déjà dans cet
état : rien n'est parti). L'`id` d'un ordre de l'app part avec l'ordre dans la
file de la tâche des lampes : l'événement qui le finit le porte, sans course
possible. `mesh lampe <n> masquer|afficher` répond en une fois, puis
l'événement `lampe`.

**Le firmware :**
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 5 sur 6. Remplacer :

````markdown
  exemple vérifié par les tests.

**Risque à lever d'abord.** La console d'ESP-IDF (linenoise) doit pouvoir
couper l'écho et l'invite en mode machine, et l'USB doit pouvoir écrire une
ligne entière sans bloquer. La première tâche du plan 3b-1 est un essai de ces
deux points ; le repli est une lecture de ligne propre au mode machine.

## 7. Thread, le canal à distance (3b-2)
````

par :

````markdown
  exemple vérifié par les tests.

**Risque levé en préparant le plan.** La console d'ESP-IDF (linenoise) ne
coupe pas son écho : le pont lit lui-même l'USB en mode machine (le repli
prévu). `usb_serial_jtag_write_bytes`, sans attente, écrit une ligne entière ou
rien. Le banc A du plan 3b-1 le confirme sur la carte, avant l'app.

## 7. Thread, le canal à distance (3b-2)
````

`docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md`, bloc 6 sur 6. Remplacer :

````markdown
| risque | parade | levé par |
|---|---|---|
| linenoise ne coupe ni l'écho ni l'invite | lecture de ligne propre au mode machine | essai, tâche 1 du plan 3b-1 |
| l'USB ne sait pas écrire une ligne entière sans bloquer | tampon et écriture tout ou rien, ligne perdue et comptée | essai, tâche 1 du plan 3b-1 |
| le signet ne donne pas accès au conteneur d'amaran Desktop | copie de la base choisie par Djoko, ou app sans sandbox (à décider avec lui) | première tâche app du plan 3b-1 |
| une socket UDP sur OpenThread gêne CHIP | essai d'abord ; Halo l'a déjà fait | tâche 1 du plan 3b-2 |
| la tâche `json` ou H1 manque de tas ou de pile | budget relevé au banc ; cadences abaissées | bancs 3b-1 et 3b-2 |
````

par :

````markdown
| risque | parade | levé par |
|---|---|---|
| linenoise ne coupe ni l'écho ni l'invite | lecture de ligne propre au mode machine | levé en préparant le plan 3b-1 : linenoise fait toujours l'écho ; le pont a sa propre tâche de console ; à confirmer au banc A |
| l'USB ne sait pas écrire une ligne entière sans bloquer | tampon et écriture tout ou rien, ligne perdue et comptée | levé en préparant le plan 3b-1 : `usb_serial_jtag_write_bytes` sans attente écrit tout ou rien (tampon porté à 4 Ko) ; à confirmer au banc A |
| le signet ne donne pas accès au conteneur d'amaran Desktop | copie de la base choisie par Djoko, ou app sans sandbox (à décider avec lui) | banc B du plan 3b-1, en premier : l'essai demande l'app signée et un choix de Djoko ; macOS lui demande alors d'autoriser l'accès aux données d'une autre app |
| une socket UDP sur OpenThread gêne CHIP | essai d'abord ; Halo l'a déjà fait | tâche 1 du plan 3b-2 |
| la tâche `json` ou H1 manque de tas ou de pile | budget relevé au banc ; cadences abaissées | bancs 3b-1 et 3b-2 |
````

- [ ] **Step 4 : les liens mènent quelque part.**

Run: `for f in docs/PROTOCOLE-JSON.md apps/macos/README.md docs/BANC.md; do test -f "$f" || echo "manque $f"; done; /usr/bin/grep -c "P3b-1" README.md`
Expected : aucune ligne `manque`, puis `1`.

- [ ] **Step 5 : commit.**

```bash
git add README.md apps/macos/README.md docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md
git commit -m "$(printf "Documentation : l'app compagnon et le mode JSON dans le README, la spec suit le plan 3b-1\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

### Task 11: Banc B : l'app et le pont, avec les lampes (Claude et Djoko)

**Files:**
- Modify: `docs/BANC.md` (une section « Plan 3b-1 : banc B »), `README.md` (la ligne `P3b-1` : « faite »)

Cette tâche est faite par Claude, avec Djoko, jamais par un sous-agent : la vraie base d'amaran Desktop, le trousseau du Mac, le port du pont, les lampes. Djoko fait les gestes dans l'app ; Claude prépare, lit les journaux, et vérifie le pont à la console après « Libérer le port ».

**Interfaces:**
- Consumes : l'app (Tasks 5 à 9) et le pont du banc A (Task 4).
- Produces : les faits du banc dans `docs/BANC.md` ; la ligne `P3b-1` du README ; un ruling dans le registre pour tout écart.

Pourquoi : la spec 3b, section 11 (banc 3b-1) et section 12 (le risque du signet, levé ici en premier).

- [ ] **Step 1 : signer l'app avec l'équipe de Djoko, et l'icône M2 (Claude).** `Local.xcconfig` et `AppIconM2.icon` sont ignorés par git ; l'icône M2 vient de `~/Dev/amaran/.superpowers/icones/final/AppIcon.icon` (hors du dépôt).

```bash
cd apps/macos
EQUIPE=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -E 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/')
printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_IDENTITY = Apple Development\nENABLE_HARDENED_RUNTIME = YES\nASSETCATALOG_COMPILER_APPICON_NAME = AppIconM2\n' "$EQUIPE" > Local.xcconfig
cp -R ~/Dev/amaran/.superpowers/icones/final/AppIcon.icon AmaranCompagnon/Ressources/AppIconM2.icon
xcodegen generate && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' -derivedDataPath build/dd build 2>&1 | tail -1
git status --short
cd ../..
```

Expected : `** BUILD SUCCEEDED **` ; `git status` vide (rien d'ignoré n'apparaît) ; `codesign -dv "apps/macos/build/dd/Build/Products/Debug/Amaran Compagnon.app" 2>&1 | /usr/bin/grep TeamIdentifier` montre l'équipe, pas `not set`.

- [ ] **Step 2 : le signet du dossier d'amaran Desktop, en premier (le risque de la spec, section 12).** Djoko ouvre l'app (`open "apps/macos/build/dd/Build/Products/Debug/Amaran Compagnon.app"`), puis Réglages (⌘,), Général, « Changer… » ; le panneau s'ouvre sur `Bibliothèque › Containers › amaran Desktop › Data › Library › Application Support › amaran Desktop` : « Ouvrir ». Si macOS demande l'accès aux données d'une autre app, Djoko accepte.
Expected : dans la carte Clés du tableau de bord, la ligne « amaran Desktop » montre deux empreintes et deux lampes, sans erreur. Claude compare les empreintes à celles que le pont donne à `mesh` (lues par `python3 outils/console.py --port <port> "mesh"` avant d'ouvrir l'app), sans les écrire nulle part.
Si l'accès est refusé : arrêter le banc. La parade de la spec (une copie de la base choisie par Djoko, ou l'app sans sandbox) se décide avec lui ; ruling dans le registre.

- [ ] **Step 3 : la copie dans le trousseau.** « Copier depuis amaran Desktop ». Expected : la ligne « Ce Mac » montre les mêmes empreintes. Djoko quitte l'app (⌘Q) et la relance : la copie est toujours là, le dossier toujours autorisé (aucun panneau).

- [ ] **Step 4 : connecter.** Claude donne le port du pont (reconnu à son `SER=`). Djoko le choisit dans le menu de la barre latérale : la connexion part aussitôt.
Expected : la pastille passe à « connecté » ; la ligne « Le pont » de la carte Clés montre les mêmes empreintes ; deux cartes de lampe (nom, place dans Maison, état lu, joignable) ; Bluetooth Mesh prêt ; Thread et Matter ; Voyant ; Système. La carte Clés ne signale aucun écart.

- [ ] **Step 5 : piloter les lampes (Djoko présent).** Écran « Commandes et console », lampe 1 : marche, niveau 30 %, arrêt ; puis « marche » deux fois de suite.
Expected : la lampe obéit et Maison suit ; chaque ordre finit « confirmée » dans le suivi, avec son `id` ; le second ordre identique finit « déjà tenue ». Un ordre donné dans Maison apparaît aussi (sans `id`).

- [ ] **Step 6 : retirer de Maison, puis remettre.** Maison oublie une lampe retirée (plan 3a) : Djoko choisit une lampe dont la configuration peut se perdre, ou la refera. « Retirer de Maison », confirmer ; puis « Remettre ».
Expected : la tuile disparaît de Maison, puis revient (nouvelle tuile) ; la carte de la lampe suit (`masquée`, puis un numéro d'endpoint).

- [ ] **Step 7 : charger le pont depuis l'app.** Menu « Charger le pont », « Depuis amaran Desktop », confirmer.
Expected : les étapes défilent, le pont redémarre, l'app se reconnecte seule ; « Pont chargé » ; aucun écart. Les lampes répondent ; Maison n'a rien perdu (mêmes clés, même liste).

- [ ] **Step 8 : débrancher l'USB 5 s, puis rebrancher.** Expected : l'app attend, puis se reconnecte seule ; le journal note le redémarrage du pont (il est alimenté par l'USB) ; les cartes se remplissent de nouveau.

- [ ] **Step 9 : la sauvegarde.** « Exporter une sauvegarde… » : une phrase de 12 caractères au moins, deux fois, puis un fichier dans iCloud Drive. « Importer une sauvegarde… » : d'abord une phrase fausse, puis la bonne, puis « Remplacer la copie de ce Mac ».
Expected : la phrase fausse est refusée sans indice ; la bonne montre les mêmes empreintes ; après le remplacement, la copie est inchangée ; Réglages montre la date de la sauvegarde.

- [ ] **Step 10 : les marges.** Carte Système : le tas au plus bas, la pile libre de `json` et de `console`. Expected : au moins 1 Ko de pile libre pour chacune ; le tas proche de celui du banc A.

- [ ] **Step 11 : rendre le port, et vérifier le pont à la console.** « Libérer le port » (barre d'outils), puis :

Run: `python3 outils/console.py --port <port> "mesh" "lampes" "taches"`
Expected : la console texte répond, avec l'écho ; mêmes empreintes ; les deux lampes ; les marges.

- [ ] **Step 12 : la démo, et l'avis de Djoko.** « Mode démo » (⇧⌘D). Expected : trois lampes, dont une jamais vue qui entre dans Maison au bout de 15 s. Djoko dit ce qu'il pense des écrans : les retouches qu'il demande se font après le banc (ruling dans le registre).

- [ ] **Step 13 : consigner.** `docs/BANC.md` : une section `## Plan 3b-1 : banc B, l'app compagnon (<date>)` (étapes 2 à 12, ce qui a été vu, les marges, tout écart). README : la ligne `P3b-1` devient `faite (<date>) : …` (l'essentiel du banc, comme les lignes P1 à P3a). Puis :

```bash
git add docs/BANC.md README.md
git commit -m "$(printf "Banc B du plan 3b-1 : l'app compagnon pilote le pont et charge ses cles\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")"
```

Les pushes (spec, plan, code) se font avec l'accord de Djoko.

## Après l'exécution (05/10/2026)

> **Amendements de fin d'exécution.** La Task 10 a reçu une correction (commit `ef07593`) : la spec dit la sandbox réelle (sans `network.client` en 3b-1) et le runtime durci avec une équipe, la console en mode simple, la phrase de passe NFC, et l'événement `ordre` toujours après sa réponse `accepte`. Après le banc B, une relecture finale (Opus) a conduit à une vague de correctifs (`63d0643`, `82c5369`) :
> - l'hôte des tests utilise un trousseau en mémoire et ses propres préférences : aucun test ne lit le vrai trousseau ni la base d'amaran Desktop ;
> - l'app relit la base d'amaran Desktop au lancement ;
> - un port ne s'appelle « Pont amaran » qu'une fois l'identité du pont confirmée par son `hello`, les autres cartes « Autre carte Espressif » ;
> - la carte Clés est visible sans pont ;
> - des guillemets ne contournent plus le masquage de `mesh cles` (pont et app) ni la confirmation des commandes dangereuses ;
> - la console du pont ne garde plus d'historique.
> Tests à la fin : `AmaranProtocoleTests` 89, `AmaranCompagnonTests` 12, tests natifs du pont tout verts.
