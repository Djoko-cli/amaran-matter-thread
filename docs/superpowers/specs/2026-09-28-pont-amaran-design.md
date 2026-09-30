# Pont amaran → Matter : design

Date : 28/09/2026. Statut : design validé section par section avec Djoko, à
relire avant le plan d'implémentation.

Deux amaran COB 60d pilotées depuis Maison (Apple Home) par un ESP32-C6 : un
nœud Matter sur Thread qui rejoint le réseau Bluetooth Mesh qu'amaran Desktop a
créé pour ces lampes. amaran Desktop reste utilisable en même temps.

## 1. But et périmètre

Dans le périmètre (v1) :
- deux lampes à intensité variable dans Maison : marche/arrêt et luminosité ;
- Maison montre toujours l'état réel des lampes, quel que soit l'auteur du
  changement : Maison, amaran Desktop ou la molette de la lampe ;
- un outil Mac qui charge dans l'ESP32 les clés du réseau et la liste des
  lampes ;
- le socle porté du pont Halo : console série, voyant, bouton BOOT, fiche
  produit ;
- un firmware de reconnaissance et les bancs d'essai.

Hors périmètre (v1) :
- effets Sidus, accessoire « Les deux », tout réglage autre que marche/arrêt
  et intensité ;
- d'autres lampes que les deux 60d ;
- app compagnon, mode JSON, mise à jour à distance (OTA) ;
- relais par le Mac (API WebSocket d'amaran Desktop) ;
- la réparation d'amaran Desktop sur macOS 27 : tâche à part (8.1) ;
- traduction anglaise (le dépôt, lui, est publié : voir 10).

## 2. Décisions

1. **Miroir « Maison suit tout ».** Maison reflète l'état réel des lampes.
   amaran Desktop suit s'il le fait de lui-même : c'est un bonus, pas une
   exigence, et il n'y a pas de relais sur le Mac.
2. **Une seule C6.** Une deuxième C6 reste en renfort si la radio partagée
   entre Thread et Bluetooth ne tient pas (règle en 5.8).
3. **v1 minimale** (périmètre ci-dessus).
4. **ESP-IDF v5.5.4 + esp-matter + ESP-BLE-MESH, sur une carte**
   (approche A). Écartées : deux C6 dès le départ, avec Matter en Arduino
   (gardée comme repli matériel) ; Arduino avec un framework recompilé (trop
   d'inconnues côté Matter).
5. **Une adresse Mesh propre à l'ESP32, `0x7F00`.** Écarté : prendre
   `0x0001`, l'adresse d'amaran Desktop, comme amaran-bridge. On ne pourrait
   plus ouvrir l'app en même temps.
6. **Les états sont lus par un crochet posé avec l'éditeur de liens
   (`--wrap`), sans modifier ESP-IDF**, que le SmartButton partage. Repli : le
   patch d'amaran-bridge, appliqué à une copie d'ESP-IDF propre au projet.
7. **Un pont Matter** : un agrégateur et une lampe « pontée » par 60d, avec
   un nom et une joignabilité par lampe. Écartés : des endpoints simples comme
   sur le Halo.
8. **Luminosité linéaire, sans gamma** : 50 % dans Maison = 50,0 % dans
   amaran Desktop. C'est l'inverse du Halo (gamma 2), assumé pour le miroir.
9. **Dépôt `~/Dev/amaran`, hors iCloud**, public sur GitHub
   (`Djoko-cli/amaran-60d-matter`) ; doc en français.

## 3. Faits établis

Relevés le 28/09/2026 en lecture seule (base, journaux et paquet d'amaran
Desktop ; code d'ESP-IDF installé) et dans les deux projets libres cités
en 12.

### 3.1 Les lampes et leur réseau

| | lampe 1 | lampe 2 |
|---|---|---|
| nom dans amaran Desktop | amaran COB 60d #1 | amaran COB 60d #2 |
| adresse Mesh | `0x0002` | `0x0004` |
| versions | contrôle 1.4, BLE 1.69 | idem |

- Groupe « All » : `0xC000`.
- 60d de première génération (achat de mai 2022), puce Telink.
- *Composition data* identique pour les deux lampes :
  - CID `0x0211` (Telink), CRPL 105, fonctions `0x000A`, un élément ;
  - modèles SIG `0x0000`, `0x0002`, `0x0003`, `0x1000` (OnOff), `0x1002`,
    `0x1004`, `0x1006`, `0x1007`, `0x1300` (Lightness), `0x1301` ;
  - modèle vendeur `0x0211:0x0000`.
- **Pas de fonction relais** : l'ESP32 doit entendre chacune des deux lampes
  en direct.
- Base d'amaran Desktop :
  `~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop/<id>_secure_id/amaran.db`.
  - Clés : `mesh.net_key` et `mesh.app_key`.
  - Lampes : table `fixtures` (`node_address`, `mac_address`, `name`,
    `device_key`).
  - **L'IV Index n'y est pas.**

### 3.2 Le protocole des lampes

Établi par amaran-BLE-control et amaran-bridge (licence MIT), à reconfirmer en
phase 0.

- D'après amaran-BLE-control, la sortie lumineuse obéit à un opcode Telink
  d'**un octet, `0x26`**. Les modèles SIG répondent, mais sans agir sur la
  lumière.
- La charge fait 10 octets. L'octet 0 est la somme des octets 1 à 9,
  modulo 256.

| octet 9 | sens | contenu |
|---|---|---|
| `0x0E` | demande d'état | octets 1 à 8 à zéro |
| `0x8C` | marche/arrêt | octet 8 = 1 (marche) ou 0 (arrêt) |
| `0x8F` | intensité *v*, de 0 à 1000 | octet 7 = (*v* & 3) << 6, octet 8 = *v* >> 2 |
| `& 0x7F` = `0x02` ou `0x01` | état en mode CCT ou HSI (réponse) | voir ci-dessous |

- Dans un état :
  - marche = bit 0 de l'octet 1 ;
  - intensité = ((octet 8 << 2) | (octet 7 >> 6)) & 0x3FF ;
  - température et G/M occupent les bits 42 à 61, sans usage pour une 60d.
- **Les lampes adressent leurs réponses d'état à `0x0001`** (le provisioner,
  c'est-à-dire amaran Desktop), jamais au demandeur.
- `0x26` + 10 octets = 11 octets : la taille maximale d'un message non
  segmenté.

Pièges relevés par amaran-bridge (ESP32-C5, ESP-IDF 5.5.2) :
- **IV Index faux de plus de 42 :** aucun message ne passe, dans aucun sens, et
  sans erreur.
- **Compteur de séquence non sauvegardé :** les lampes ignorent l'émetteur, à
  cause de leur liste anti-rejeu.
- **File d'émission trop rapide :** la pile affiche « Out of network buffers »
  et jette des commandes avant même de les émettre. D'où 60 à 70 ms entre deux
  messages et 120 tampons d'annonce.
- **Accusés peu fiables :** les lampes n'accusent pas réception de façon
  fiable. Répéter à l'aveugle (2 envois à 70 ms, 3 copies réseau à 20 ms)
  marche mieux qu'attendre un accusé.
- **AES matériel :** allocation DMA à chaque bloc, puis « Encrypt failed » et
  pile Mesh arrêtée. D'où `CONFIG_MBEDTLS_HARDWARE_AES=n`.

### 3.3 amaran Desktop

- Version 1.1.03 (App Store) : Python/PySide6 compilé par Nuitka, Bluetooth
  par CoreBluetooth.
- L'app rejoint le réseau **par un proxy GATT** : elle se connecte à une des
  lampes, avec l'adresse `0x0001`.
- Conséquence : les ordres qu'elle envoie à la lampe à laquelle elle est
  connectée ne passent pas par les annonces, et l'ESP32 ne les voit pas. Il en
  voit l'effet : réponses d'état et relectures.
- API WebSocket locale `ws://127.0.0.1:33782/ws`, utilisée par le plugin
  Stream Deck (`set_intensity`, `get_sleep`, `toggle_sleep`…) ; non utilisée
  en v1.
- **Plante au démarrage depuis le 21/09 sur macOS 27.**
  `system_profiler -xml SPFontsDataType` rend un dictionnaire sans `_items`
  (vérifié), et `matplotlib.font_manager._get_macos_fonts` lève `KeyError`.
  Voir 8.1.

### 3.4 ESP-IDF v5.5.4 et esp-matter (installés dans `~/esp`)

- Les bibliothèques Arduino du C6 contiennent le Bluetooth Mesh, mais sans
  rôle nœud ni modèle client : d'où ESP-IDF.
- `bt_mesh_provision()` (`core/main.c`, interne) permet
  l'auto-provisionnement, comme dans amaran-bridge.
- Les annonces Mesh entrent par `bt_mesh_generic_net_recv()`, défini dans
  `net.c` et appelé depuis `scan.c` : `--wrap` peut l'intercepter.
- `bt_mesh_net_decode()` inscrit chaque message dans le cache anti-doublon.
  L'appeler une seconde fois sur le même message le fait rejeter.
- Fonctions accessibles pour déchiffrer à côté de la pile :
  - `bt_mesh_net_obfuscate`, `bt_mesh_net_decrypt`, `bt_mesh_app_decrypt`
    (`crypto.c`) ;
  - `bt_mesh_rx_netkey_get/size`, `bt_mesh_rx_appkey_get/size` (`access.h`).
- L'IV Index suit les balises du réseau jusqu'à +42 (récupération, `net.c`).
- esp-matter fournit `examples/bridge_apps/blemesh_bridge` et la plateforme
  `examples/common/blemesh_platform`.
  - Le Bluetooth Mesh y possède les annonces, et l'appairage Matter par
    Bluetooth passe par lui (`CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING=n`).
  - L'exemple vise un ESP32 en Wi-Fi, pas un C6 en Thread.

## 4. Architecture

```
Maison ─Thread─► ┌──────────────── ESP32-C6 ────────────────┐
                 │  matter  ⇄   lampes   ⇄   mesh + telink   │
                 │  socle : console, voyant, BOOT, NVS       │
                 └──────────────────┬────────────────────────┘
                                    │ Bluetooth Mesh (annonces)
                     60d #1 (0x0002)   60d #2 (0x0004) ◄─GATT─ amaran Desktop (0x0001)
```

### 4.1 Modules

- **`telink`** : fabrique et lit les trames de 10 octets.
  - C pur, repris d'amaran-bridge (en-tête MIT conservé).
  - Compilé aussi sur le Mac.
- **`mesh`** : adhésion au réseau (5.1), crochet de réception (5.5), file
  d'émission et rythme (5.6).
  - Le seul module qui touche ESP-BLE-MESH.
- **`lampes`**, le cœur. Pour chaque lampe, il garde la consigne, le dernier
  état lu, l'âge de la dernière réponse et la joignabilité.
  - Il décide quoi envoyer, confirme, relit et abandonne (5.6, 5.7, 7).
  - C pur, sans ESP-IDF ni Matter, avec une horloge injectée : testé sur le
    Mac.
- **`matter`** : le pont (6), et la traduction entre les attributs Matter et
  `lampes`.
- **Le socle** : console série, voyant WS2812, bouton BOOT, NVS, fiche
  produit (7).
- **`outils/cles_amaran.py`** : lit la base d'amaran Desktop et envoie par la
  console les clés et la liste des lampes (5.2).

### 4.2 La couture entre `lampes` et `mesh`

`lampes` ne parle à `mesh` que par trois messages :
- `envoyer(adresse, trame)`, de `lampes` vers `mesh` ;
- `etat_recu(adresse, trame)`, de `mesh` vers `lampes` ;
- `mesh_pret(oui/non)`, de `mesh` vers `lampes` : les clés sont présentes et
  le réseau est reconnu.

**Précision par rapport à la section 1 validée :** décider qu'une lampe est
muette relève de `lampes` (essais, délais), pas de `mesh`. Le troisième
message dit donc si le réseau Mesh est utilisable, et non si une lampe est
muette.

Si la radio partagée ne tient pas, `mesh` et `telink` partent sur la 2ᵉ C6, et
ces trois messages passent par une liaison série. `lampes` et `matter` ne
changent pas.

### 4.3 Tâches et concurrence

- **Tâche `lampes` (FreeRTOS)** : elle seule modifie l'état des lampes. Elle
  consomme une file d'événements : ordres de Matter ou de la console, états
  reçus, et un tic de 50 ms pour les délais.
- **Crochet de réception** : il tourne dans la tâche de la pile Bluetooth.
  - Il déchiffre, filtre, puis dépose l'état dans la file, sans jamais
    bloquer.
  - Si la file est pleine, il jette le message et le compte.
- **File d'émission de `mesh`** : sa propre tâche espace les envois (5.6).
- **Matter** :
  - les rappels d'attributs tournent dans la tâche CHIP et déposent un ordre
    dans la file, sans bloquer ;
  - les mises à jour d'attributs venues de `lampes` passent par
    `PlatformMgr().ScheduleWork()`. Jamais d'appel Matter hors de la tâche
    CHIP sans son verrou.

## 5. Côté Bluetooth Mesh

### 5.1 Adhésion

- Rôle nœud, auto-provisionné au démarrage par `bt_mesh_provision()`.
  - Paramètres : la clé réseau (indice 0), l'IV Index et l'adresse (5.4).
  - Plus une clé d'appareil, tirée au hasard une fois puis gardée.
- L'AppKey (indice 0) est ajoutée localement et liée à notre modèle.
- Composition : un élément, avec le serveur de configuration (obligatoire) et
  un modèle vendeur (CID `0x0211`) qui porte l'opcode d'un octet `0x26`.
- Relais, proxy GATT, fonction ami et balises émises : coupés. L'ESP32 n'émet
  que ses propres messages, et les balises des lampes lui suffisent pour
  suivre l'IV Index.
- Rien n'est écrit dans les lampes, et amaran Desktop ne voit pas l'ESP32.

### 5.2 Clés et liste des lampes

- Rangées en NVS, dans l'espace `amaran` : clé réseau, AppKey, IV Index,
  adresse, clé d'appareil, et les lampes (adresse, MAC, nom ; 2 au plus en
  v1).
- `outils/cles_amaran.py --port <port>` les charge :
  - il trouve la base d'amaran Desktop, ou la prend dans `--db` ;
  - il envoie les commandes `mesh cles …` et `mesh lampe …` ;
  - il n'affiche que des empreintes, jamais les clés.
- À relancer si le réseau est recréé dans amaran Desktop. Le cas est détecté
  (7.3).

### 5.3 IV Index

- Au démarrage, l'ESP32 prend la valeur de la NVS, ou 0 à défaut.
- La pile se recale d'elle-même sur les balises des lampes, jusqu'à +42, et
  l'ESP32 sauvegarde toute nouvelle valeur.
- Au-delà de +42, la pile journalise la valeur de la balise (« IVIndex out of
  sync »). La console l'affiche, et `mesh iv <n>` la règle.
- Si les lampes n'émettent pas de balises : `mesh iv cherche` essaie les
  valeurs sur des messages captés qui portent le NID du réseau, jusqu'à ce que
  leur code d'intégrité (NetMIC) soit valide.

### 5.4 Compteur de séquence et adresse

- La pile sauve le compteur en NVS (`CONFIG_BLE_MESH_SETTINGS`) à un rythme
  donné, et saute d'autant au démarrage.
  - À vérifier dans le code d'ESP-IDF lors du plan.
  - Si besoin, on ajoute un plancher, comme amaran-bridge.
- Adresses réservées : `0x7F00` à `0x7F7F`. **On change d'adresse** au lieu
  de toucher au compteur :
  - après un effacement de la flash (`mesh adresse suivante`), faute de quoi
    les lampes rejetteraient nos messages ;
  - automatiquement quand le compteur dépasse `0x700000`, sous le seuil de
    8 000 000 où la pile d'ESP-IDF lance d'elle-même une mise à jour d'IV. Cela
    évite la mise à jour d'IV, qui engagerait tout le réseau, amaran Desktop
    compris.
- Budget : une relecture de groupe toutes les 5 s fait environ 6 millions de
  messages par an, et le double avec une demande par lampe (5.7). Une adresse
  tient donc entre ~7 et ~14 mois, ordres compris à la marge.

### 5.5 Crochet de réception

`__wrap_bt_mesh_generic_net_recv(data, rx, net_if)` :
1. Il copie le message réseau (29 octets au plus).
2. Il appelle `__real_bt_mesh_generic_net_recv` : la pile traite le message
   comme d'habitude.
3. Il déchiffre la copie à côté de la pile :
   - pour chaque clé réseau dont le NID correspond, il choisit l'IV Index
     selon le bit IVI ;
   - il retire l'obfuscation, déchiffre et vérifie le NetMIC ;
   - s'il s'agit d'un message d'accès (CTL = 0) non segmenté, avec AKF = 1 et
     un AID connu, il déchiffre la charge avec l'AppKey (TransMIC de
     32 bits).
4. Si la charge est `0x26` suivie de 10 octets, avec une somme de contrôle
   juste, et que la source est l'une de nos lampes, il transmet
   `etat_recu(source, trame)`. La destination importe peu : c'est `0x0001` en
   pratique.

Autres règles :
- Compteurs pour les diagnostics (7.3) : annonces Mesh vues, NID reconnu,
  NetMIC faux, états transmis.
- Aucun journal dans ce chemin : il tourne dans la tâche Bluetooth.
- Les doublons (copies réseau, répétitions) sont sans danger : un état est
  absolu.

### 5.6 Émission

- **`mesh`** émet un message à la fois, avec **au moins 70 ms** entre deux
  messages, 3 copies réseau à 20 ms d'écart, TTL 3.
- **`lampes`** garde une seule consigne en attente par lampe : une nouvelle
  valeur (le curseur de Maison qu'on fait glisser) remplace l'ancienne au lieu
  de s'empiler.
- **Déroulé d'un ordre :**
  1. la trame (`0x8F` ou `0x8C`), envoyée 2 fois ;
  2. 200 ms plus tard, une demande d'état `0x0E` ;
  3. l'ordre est confirmé si, dans la seconde, arrive un état égal à la
     consigne (marche/arrêt et intensité) ;
  4. sinon, on recommence : 3 essais au plus, puis abandon (7.1).
- Pour allumer à un niveau donné : `0x8F`, puis `0x8C`, puis `0x0E`. Cet
  ordre sera vérifié en R3.
- Pendant un ordre en cours, les états arrivés avant notre propre demande
  d'état sont ignorés pour cette lampe : ils peuvent être périmés.

### 5.7 Relecture périodique

- Une demande d'état toutes les 5 s, réglable (`mesh releve <s>`).
  - Adressée au groupe `0xC000` si les deux lampes y répondent (R5).
  - Sinon, une demande par lampe, à 2,5 s d'écart.
- Une lampe devient joignable dès qu'elle répond, et muette après 3
  relectures sans réponse (7.2).
- Si les lampes signalent d'elles-mêmes les changements faits à la molette
  (R4), on espace les relectures.
- Chaque réponse part vers `0x0001` : amaran Desktop, s'il écoute, reste au
  courant.

### 5.8 Radio partagée entre Thread et Bluetooth

- Le C6 alterne entre 802.15.4 et Bluetooth (coexistence logicielle
  d'ESP-IDF). Le risque : un Thread non dormant garde le récepteur, et le
  Bluetooth manque des réponses.
- Leviers, dans l'ordre :
  1. les priorités de coexistence d'ESP-IDF ;
  2. Thread en appareil dormant, avec une relève rapide ;
  3. la 2ᵉ C6.
- Rôle Thread : non dormant (MED) par défaut ; le rôle dormant est essayé au
  banc C. Il se règle par la console s'il peut changer à chaud, sinon par une
  variante de compilation.
- **Règle de repli.** Après réglage, on passe à la 2ᵉ C6 si :
  - moins de 95 % des demandes d'état obtiennent une réponse ;
  - ou plus de 1 % des ordres de Maison échouent ou prennent plus d'une
    seconde.

## 6. Côté Matter

### 6.1 Endpoints

| EP | rôle | contenu |
|---|---|---|
| 0 | nœud | Basic Information : « Djoko-CLI », « Pont amaran », série `AMARAN-<MAC en 12 hexa>`, matériel « ESP32-C6 SuperMini », version `0.1.0-<commit>` (`-dirty` si modifié) ; VID/PID de test `0xFFF1`/`0x8000` |
| 1 | agrégateur | |
| 2 | lampe 1 | Bridged Node + Dimmable Light : grappes créées par esp-matter pour ce type (Identify, Groups, OnOff, LevelControl…) ; Bridged Device Basic Information : NodeLabel = nom de la base, Reachable, UniqueID = MAC |
| 3 | lampe 2 | idem |

- Les numéros d'endpoint sont liés à l'adresse de chaque lampe et gardés en
  NVS : recharger les clés ne crée pas de nouvelles tuiles.
- Maison devrait reprendre les noms, et afficher « Pas de réponse » pour une
  lampe non joignable. À vérifier (T1, T5).
- Identify reste sans effet sur la lampe : Maison ne le propose pas pour un
  accessoire Matter (leçon du Halo).

### 6.2 Luminosité : conversion linéaire

- intensité = arrondi(niveau × 1000 / 254), pour un niveau de 1 à 254 ;
- niveau = borne(arrondi(intensité × 254 / 1000), 1, 254) ;
- arrondi au plus proche, demi vers le haut.
- **Propriété vérifiée par les tests :** niveau → intensité → niveau redonne
  le même niveau, pour chacun des 254 niveaux. L'erreur d'arrondi ramenée au
  niveau vaut au plus 0,5 × 0,254 ≈ 0,13, sous le demi : le curseur de
  Maison ne saute pas.
- Une intensité de 0 lue sur la lampe donne le niveau 1.

### 6.3 Marche/arrêt

- L'attribut OnOff correspond à la trame `0x8C`.
- Un niveau reçu pendant que la lampe reste éteinte est gardé comme
  consigne. Il n'est émis qu'à l'allumage.

### 6.4 Pas d'écho

- Seul un ordre venu d'un contrôleur Matter ou de la console fait émettre.
- `lampes` marque les mises à jour qu'il pousse dans Matter, et le rappel
  d'attribut les ignore.
- En plus, une valeur égale au dernier état lu ne fait jamais émettre.

### 6.5 Démarrage

- esp-matter restaure les attributs. `StartUpOnOff` reste nul : rien ne
  change au démarrage.
- Joignable part de « oui » : pas de « Pas de réponse » fugace à chaque
  redémarrage.
- Seules des demandes d'état partent vers les lampes, la première aussitôt.
  Aucun ordre n'est rejoué.
- Maison se cale sur l'état réel dès les premières réponses.

### 6.6 Réseau et Apple

- Matter sur Thread, en appareil minimal (MTD). Le rôle est décrit en 5.8.
- **L'intervalle maximal des abonnements est plafonné à 20 s.** Leçon du Halo :
  Apple ne reprend pas seul un abonnement après un redémarrage du nœud ; il se
  réabonne quand l'intervalle expire.
- La pile Bluetooth Mesh est initialisée au démarrage : la plateforme
  d'esp-matter en a besoin pour les annonces d'appairage. Mais l'ESP32 ne
  rejoint le réseau des lampes (provisionnement, écoute) qu'une fois
  l'appairage Matter terminé, ou dès le démarrage s'il est déjà appairé.
- Le code d'appairage et le discriminateur sont propres à la carte :
  - rangés dans une partition d'usine (esp-matter-mfg-tool, comme sur le
    SmartButton) ;
  - affichés par `matter`.

## 7. Erreurs et exploitation

### 7.1 Ordre sans réponse

Après 3 essais (5.6), l'ESP32 abandonne : Maison revient au dernier état lu,
et le voyant clignote 3 fois en rouge.

### 7.2 Lampe muette à la relecture

- Après 3 relectures sans réponse (~15 s), Reachable passe à faux : Maison
  affiche « Pas de réponse ».
- À la première réponse, Reachable repasse à vrai et les attributs prennent
  l'état réel.

### 7.3 Bluetooth Mesh inopérant

Le voyant est rouge fixe et la console affiche le message.

| constat | cause probable | remède |
|---|---|---|
| clés absentes en NVS | jamais chargées, ou `mesh oublie` | `outils/cles_amaran.py` |
| des annonces Mesh passent, mais aucune ne porte notre NID depuis 2 min | réseau recréé dans amaran Desktop : clés périmées | recharger les clés |
| notre NID, mais NetMIC faux | IV Index faux | `mesh iv` ou `mesh iv cherche` |

`mesh_pret` passe à non, et les deux lampes à « Pas de réponse ».

### 7.4 Voyant (WS2812, IO8) : signature du Halo

| voyant | sens |
|---|---|
| bleu clignotant | pas appairé à Maison |
| orange lent | réseau Thread absent |
| éteint, brève lueur blanche toutes les 10 s | tout va bien |
| rouge fixe | Bluetooth Mesh inopérant (7.3) |
| éclat vert | ordre confirmé par la lampe |
| rouge ×3 | ordre abandonné (7.1) |
| rouge, noir, violet, noir, vite | BOOT tenu 8 s : relâcher pour désappairer |
| éclat blanc | BOOT court : redémarrage |

Priorités et intensités comme sur le Halo ; `led test` joue chaque motif.

### 7.5 Console série, en français

- `lampes` : pour chaque lampe, la consigne, l'état lu, l'âge de la dernière
  réponse et si elle est joignable.
- `lampe <n> on | off | niveau <0-1000> | releve` : pilotage manuel, pour les
  bancs, Djoko présent.
- `mesh` : adresse, IV Index, compteur de séquence, empreintes des clés,
  compteurs du crochet et de l'émission.
- Réglages : `mesh cles <netkey> <appkey>`, `mesh lampe <n> <adresse> <mac>
  <nom>`, `mesh iv <n> | cherche`, `mesh adresse <a> | suivante`,
  `mesh releve <s>`, `mesh oublie`.
- `mesh autotest` : passe les exemples chiffrés de la spécification Bluetooth
  Mesh dans les fonctions de chiffrement de la pile (9).
- `matter` : codes d'appairage, fabriques, rôle Thread, abonnements.
- `decommission`, `redemarre`, `led test`.

### 7.6 Bouton BOOT (IO9)

Comme sur le Halo, l'action a toujours lieu au relâchement, puisque c'est une
broche de démarrage :
- appui court : redémarrage ;
- appui de 8 s ou plus : désappairage de Maison.

### 7.7 Clés

- Rangées en NVS, en clair, comme la clé réseau du Halo. Qui a la carte en
  main peut les lire : acceptable à la maison.
- Jamais affichées (empreinte seulement), jamais dans un journal ni dans le
  dépôt.
- `decommission` les garde ; `mesh oublie` les efface.

## 8. Phases et bancs

Un plan d'implémentation par étape :
- **plan 1** : la phase 0 (firmware `ecoute`, composants `telink` et `mesh`),
  l'outil des clés et les tests sur le Mac ;
- **plan 2** : les phases 1 et 2, écrit après les bancs R, dont les résultats
  fixent plusieurs choix (8.2).

### 8.1 Préalable, tâche à part : réparer amaran Desktop

- Déposer `fontlist-v<N>.json` dans
  `~/Library/Containers/com.sidus.amaran-desktop/Data/.matplotlib/`, pour
  que matplotlib ne consulte plus `system_profiler`.
- Un seul fichier, qu'il suffit de retirer pour revenir en arrière.
- Utile pour R6 et T4. Proposé à Djoko séparément.

### 8.2 Phase 0 : reconnaissance

Le firmware `ecoute` est un second projet ESP-IDF :
- il réutilise `telink` et `mesh`, avec une console ;
- il n'a pas de Matter : compilation rapide, et radio réservée au Bluetooth.

Djoko est présent dès qu'on émet vers les lampes.

| essai | question | réussi si |
|---|---|---|
| R1 | IV Index | trouvé et sauvé ; des messages des lampes se déchiffrent |
| R2 | réponse captée | `lampe 1 releve` : la réponse de `0x0002` vers `0x0001` est captée par le crochet, 10 fois sur 10 |
| R3 | ordres depuis `0x7F00` | marche, arrêt, niveaux, et « intensité puis marche » : la lampe obéit et l'état lu le confirme, 10 fois sur 10 |
| R4 | molette | noter si un tour de molette ou un appui produit un message spontané, ou seulement une réponse à la relecture |
| R5 | groupe « All » | une demande à `0xC000` fait répondre les deux lampes, 10 fois sur 10 |
| R6 | amaran Desktop ouvert | chacun voit-il les changements de l'autre ? L'app fonctionne-t-elle normalement ? |

Les résultats fixent quatre choix :
- le rythme de relecture (R4) ;
- la relecture par groupe ou par lampe (R5) ;
- l'ordre « intensité puis marche » (R3) ;
- le miroir vers amaran Desktop (R6).

Ils sont consignés dans `docs/BANC.md` et `docs/PROTOCOLE.md`.

### 8.3 Phase 1 : Matter sur la même carte, et banc C de radio partagée

- Firmware produit minimal : pont Matter, `mesh` et `lampes`.
- Appairage dans Maison.
- Mesures avec Thread non dormant, puis dormant :
  - la part des relectures qui obtiennent une réponse, sur au moins 30 min ;
  - les ordres depuis Maison (une trentaine, à la main) et depuis la console
    (en rafales) : échecs et délai.
- Verdict une ou deux cartes, selon la règle de 5.8.

### 8.4 Phase 2 : produit

On ajoute le socle (voyant, bouton, console, fiche produit, partition
d'usine), puis on passe les bancs :

| banc | attendu |
|---|---|
| T1 | marche, arrêt et luminosité de chaque lampe depuis Maison, confirmés par l'état lu ; noms repris |
| T2 | curseur glissé vite : pas d'empilement, la lampe finit à la dernière valeur |
| T3 | molette → Maison en 5 s au plus |
| T4 | amaran Desktop → Maison (app réparée) |
| T5 | lampe coupée au secteur → « Pas de réponse » en ~15 s ; rallumée → état réel |
| T6 | redémarrage de l'ESP32 : seules des demandes d'état partent ; Maison se cale sur l'état réel |
| T7 | Thread perdu → voyant orange ; au retour, abonnements repris en ~60 s au plus |
| T8 | BOOT court → redémarrage ; BOOT 8 s → désappairage |
| T9 | `mesh oublie` → rouge fixe et message ; clés rechargées → reprise |
| T10 | endurance 24 h : réponses manquées, mémoire libre, compteur de séquence, aucun redémarrage |

## 9. Tests

Sur le Mac, sans carte :
- **`telink`** : trames connues (3.2), puis trames relevées en phase 0.
- **Conversion** : aller-retour exact sur les 254 niveaux, bornes,
  intensité 0.
- **`lampes`**, avec une horloge simulée : consigne remplacée, déroulé d'un
  ordre, 3 essais puis abandon, joignabilité, états périmés ignorés, pas
  d'écho.
- **Crochet** : le tri (en-têtes, AKF, AID, segmentation, filtre des lampes),
  avec un déchiffrement simulé.
- **`outils/cles_amaran.py`** : base SQLite factice, empreintes, aucune clé
  affichée. Tests avec unittest de Python, sans dépendance à installer.

Sur la carte :
- `mesh autotest` passe les exemples chiffrés de la spécification Bluetooth
  Mesh (*sample data*) dans les fonctions de chiffrement de la pile ;
- puis les bancs R, C et T.

## 10. Outillage, dépôt, licences

**Environnement**
- ESP-IDF v5.5.4 + esp-matter (commit `c5b9ea8`) dans `~/esp` :
  `source ~/esp/esp-idf/export.sh && source ~/esp/esp-matter/export.sh`,
  puis `idf.py set-target esp32c6`.
- Carte : C6 SuperMini (à confirmer), flash de 4 Mo, une seule partition
  d'application (pas d'OTA), WS2812 sur IO8, BOOT sur IO9.

**sdkconfig**
- NimBLE ; Bluetooth Mesh en rôle nœud, avec réglages persistés et
  120 tampons d'annonce ; `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING=n` ;
  OpenThread MTD ; `CONFIG_MBEDTLS_HARDWARE_AES=n`.
- Plateforme externe `blemesh_platform` : référencée dans esp-matter tant
  qu'elle convient au C6 en Thread ; copiée et adaptée sinon.
- Chaque symbole est vérifié contre les Kconfig, comme dans le SmartButton
  (`check_sdkconfig.sh`) : un symbole inconnu est ignoré en silence.

**Flash**
- Le port série est toujours donné explicitement (`-p /dev/cu.usbmodem…`),
  parce que les écrans LG apparaissent eux aussi en `usbmodem`.
- Claude flashe avec l'accord de Djoko. Les sous-agents ne flashent jamais et
  n'ouvrent jamais de port série.

**Dépôt**
- `~/Dev/amaran`, dépôt public sur GitHub (`Djoko-cli/amaran-60d-matter`, remote
  `origin`), commits et doc en français.
- `telink` est repris d'amaran-bridge (MIT) : en-tête de licence conservé,
  mention dans le README.
- `.gitignore` : `build/`, `sdkconfig`, `managed_components/`, journaux, tout
  fichier de clés.

Arborescence prévue :

```
components/          partagés par les deux firmwares
  telink/            trames 0x26 (C pur)
  lampes/            le cœur (C pur)
  mesh/              ESP-BLE-MESH, crochet --wrap, file d'émission
firmware/            produit : pont Matter et socle (idf.py)
ecoute/              reconnaissance (phase 0), sans Matter
tests/hote/          tests natifs sur le Mac
outils/              cles_amaran.py et ses tests
docs/                PROTOCOLE.md, BANC.md, superpowers/
```

## 11. Risques et questions ouvertes

| risque ou question | conséquence | parade | tranché par |
|---|---|---|---|
| radio partagée insuffisante | réponses perdues, ordres lents | leviers de 5.8, puis la 2ᵉ C6 | banc C |
| `--wrap` ou fonctions internes d'ESP-IDF différentes de ce qui est prévu | pas de lecture d'état | patch sur une copie d'ESP-IDF | R2 |
| l'hypothèse « réponses vers `0x0001` » | crochet à revoir | établie par les deux projets | R2 |
| IV Index introuvable (pas de balises) | rien ne passe | `mesh iv cherche` | R1 |
| les lampes ignorent un émetteur autre que `0x0001` | décision 5 à revoir avec Djoko | aucune à ce stade | R3 |
| amaran Desktop ignore les réponses qu'il n'a pas demandées | pas de miroir vers l'app (bonus perdu) | aucune ; accepté | R6 |
| Maison ne reprend pas les noms, ou n'affiche pas « Pas de réponse » | confort | noms donnés à la main dans Maison | T1, T5 |
| mémoire vive ou flash du C6 (Matter + NimBLE + Mesh) | ne tient pas | mesurer dès la phase 1 ; réduire tampons et journaux | phase 1 |
| réseau recréé dans amaran Desktop | clés périmées | diagnostic de 7.3, recharger | à l'usage |
| les lampes ne relaient pas | une lampe hors de portée de l'ESP32 reste muette | placer l'ESP32 à portée des deux | installation |

## 12. Références

- amaran-bridge (Kevin Schaich, MIT) :
  <https://github.com/kevinschaich/amaran-bridge>. Fichiers `main/telink.c`,
  `main/mesh.c`, `patches/apply-net-hook.py`, et le README.
- amaran-BLE-control (Wes Bos, MIT) :
  <https://github.com/wesbos/amaran-BLE-control>. Fichiers
  `DIRECT-BLE-CONTROL.md` et
  `esp32-firmware/patches/0001-amaran-net-recv-status-snoop.patch`.
- esp-matter : `examples/bridge_apps/blemesh_bridge` et
  `examples/common/blemesh_platform`.
- Pont Halo : <https://github.com/Djoko-cli/benq-screenbar-halo-matter>
  (`~/Documents/Dev/esp32/benq`).
  - `README.fr.md` : voyant, bouton BOOT, fiche produit.
  - Notes du projet : abonnements Apple, rôle Thread.
- SmartButton : `~/Documents/Dev/esp32/smartbutton` (ESP-IDF + esp-matter
  sur C6 en Thread, `check_sdkconfig.sh`, partition d'usine).
- Spécification Bluetooth Mesh Protocol 1.1 : exemples chiffrés (*sample
  data*).
