# Pont amaran → Matter : design

Date : 28/09/2026. Statut : design validé section par section avec Djoko, à
relire avant le plan d'implémentation. Mis à jour le 01/10/2026 avec ce que
les plans 1 et 2, leurs bancs et la revue finale ont établi (2.5, 4.2, 4.3,
5.1, 5.4 à 5.8, 6.1 à 6.6, 7.3 à 7.5, 8.3, 8.4, 9, 10, 11).

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
5. **Une adresse Mesh propre à l'ESP32**, tirée au hasard dans `0x7F00` à
   `0x7F7F` au premier démarrage, et gardée en NVS (5.4) : `0x7F38` pour
   l'écoute, `0x7F3A` pour le pont. Écarté : prendre `0x0001`, l'adresse
   d'amaran Desktop, comme amaran-bridge. On ne pourrait plus ouvrir l'app en
   même temps.
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
- `mesh_pret(oui/non)`, de `mesh` vers `lampes` : l'ESP32 est entré dans le
  réseau (clés présentes, adhésion faite). Il ne repasse jamais à non.

**Précision par rapport à la section 1 validée :** décider qu'une lampe est
muette relève de `lampes` (essais, délais), pas de `mesh`. Le troisième
message dit donc si l'ESP32 est entré dans le réseau Mesh, et non si une lampe
est muette. Un réseau devenu inutilisable (clés périmées, IV Index faux) ne le
change pas : le diagnostic (7.3) le signale, et les lampes passent à « Pas de
réponse » par la règle 7.2.

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
    `attribute::report()` d'esp-matter, qui prend lui-même le verrou de la
    pile et ne rappelle pas l'application (6.4). Jamais d'appel Matter hors de
    la tâche CHIP sans son verrou.

## 5. Côté Bluetooth Mesh

### 5.1 Adhésion

- Rôle nœud, auto-provisionné par `bt_mesh_provision()` : au démarrage dans
  le firmware d'écoute ; dans le pont, une fois Maison appairée, 3 s après la
  fin de la mise en service (6.6).
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

- Le compteur est sauvé par nous, pas par la pile (`CONFIG_BLE_MESH_SETTINGS=n`,
  plan 1) : un plancher en NVS, avancé par blocs de 256, d'où la séquence
  repart au démarrage. Elle ne redescend jamais.
- Adresses réservées : `0x7F00` à `0x7F7F`. **On change d'adresse** au lieu
  de toucher au compteur :
  - après un effacement de la flash : l'ESP32 tire alors une adresse au hasard
    dans la plage. Si elle tombe sur une adresse déjà employée (environ 1
    chance sur 128 par adresse déjà servie), les lampes rejettent nos
    messages, sans indice clair : `mesh adresse suivante` en prend une
    autre ;
  - automatiquement quand le compteur dépasse `0x700000`, sous le seuil de
    8 000 000 où la pile d'ESP-IDF lance d'elle-même une mise à jour d'IV. Cela
    évite la mise à jour d'IV, qui engagerait tout le réseau, amaran Desktop
    compris.
- Budget : deux demandes d'état de groupe à chaque relecture (5.6, 5.7). Toutes
  les 2 s, elles consomment environ 87 000 numéros par jour, ordres compris
  (mesuré du 02 au 03/10/2026) : une adresse tient environ 2 mois et demi avant
  de changer d'elle-même. Toutes les 5 s (banc C), c'était environ 35 000 par
  jour et 7 mois. Les 128 adresses réservées tiennent des décennies.

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
- Les doublons (copies réseau, rejeux) sont écartés, par lampe : un état n'est
  transmis que si son IV Index et sa SEQ sont plus récents que ceux du dernier
  état transmis. Un compteur les dénombre.

### 5.6 Émission

- **`mesh`** émet un message à la fois, avec **au moins 70 ms** entre deux
  messages, 3 copies réseau à 20 ms d'écart, TTL 3.
- **`lampes`** garde une seule consigne en attente par lampe : une nouvelle
  valeur (le curseur de Maison qu'on fait glisser) remplace l'ancienne au lieu
  de s'empiler.
- **Regroupement :** un ordre attend 80 ms avant de partir. Une commande
  Matter écrit souvent plusieurs attributs de suite (l'arrêt avec effet écrit
  CurrentLevel au minimum, OnOff, puis CurrentLevel restauré) : tout part en
  une salve, avec la consigne finale.
- **Déroulé d'un ordre :**
  1. la trame (`0x8F` ou `0x8C`), envoyée 2 fois ;
  2. 200 ms plus tard, une demande d'état `0x0E`, envoyée 2 fois (banc C :
     à 50 % d'écoute, une réponse sur dix environ était manquée) ;
  3. l'ordre est confirmé si, dans la seconde, arrive un état égal à la
     consigne (marche/arrêt et intensité) ;
  4. sinon, on recommence : 3 essais au plus, puis abandon (7.1).
- **Ordre des trames :** éteindre avant de changer le niveau (`0x8C`, puis
  `0x8F`). Pour allumer à un niveau donné : `0x8F`, puis `0x8C`, puis `0x0E`.
  R3 l'a vérifié.
- Pendant un ordre en cours, les états arrivés avant notre propre demande
  d'état sont ignorés pour cette lampe : ils peuvent être périmés.

### 5.7 Relecture périodique

- Une demande d'état toutes les 2 s, envoyée 2 fois comme en 5.6, réglable
  (`mesh releve <s>`, de 1 à 60 s). C'était 5 s jusqu'au 03/10/2026 : 2 s
  suit mieux la molette, et la radio tient aussi bien (BANC.md).
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
- Rôle Thread : non dormant (MED). Le rôle dormant n'a pas été essayé : la
  règle de repli a tenu sans lui (verdict ci-dessous). Si elle cassait un
  jour, il se réglerait par la console s'il peut changer à chaud, sinon par
  une variante de compilation.
- **Règle de repli.** Après réglage, on passe à la 2ᵉ C6 si :
  - moins de 95 % des demandes d'état obtiennent une réponse ;
  - ou plus de 1 % des ordres de Maison échouent ou prennent plus d'une
    seconde.
- **Verdict du banc C (30/09/2026) : une seule C6.** Le levier qui a compté
  n'était pas dans la liste : l'écoute du Bluetooth Mesh, continue par défaut
  dans ESP-IDF, étouffait Thread (aucune émission 802.15.4 ne passait). Le pont
  écoute à 50 % (20 ms toutes les 40 ms, réglable par `mesh balayage`), en
  Thread non dormant. Avec la demande d'état doublée (5.6) et l'arrondi au
  pour cent (6.2) : 96,9 % et 98,3 % des relectures répondues sur 30 min,
  47 salves d'ordres de Maison sans échec ni dépassement d'une seconde
  (docs/BANC.md).

## 6. Côté Matter

### 6.1 Endpoints

| EP | rôle | contenu |
|---|---|---|
| 0 | nœud | Basic Information : « Djoko-CLI », « Pont amaran », série `AMARAN-<MAC en 12 hexa>`, matériel « ESP32-C6 SuperMini », version `0.1.0-<commit>` (`-dirty` si modifié) ; VID/PID de test `0xFFF1`/`0x8000` |
| 1 | agrégateur | |
| 2 | lampe 1 | Bridged Node + Dimmable Light : grappes créées par esp-matter pour ce type (Identify, Groups, OnOff, LevelControl…) ; Bridged Device Basic Information : NodeLabel = nom de la base, Reachable, UniqueID = MAC |
| 3 | lampe 2 | idem |

- Depuis le plan 3a (spec `2026-10-03-pont-amaran-n-lampes-design.md`, 5 et
  7) : un endpoint par lampe exposée, jusqu'à 16, avec un numéro stable par
  MAC. Les deux lampes du plan 2 gardent EP2 et EP3. Une lampe jamais vue n'est
  pas exposée ; son retrait de Maison est un geste explicite.
- Maison reprend les noms (T1). Il affiche « Pas de réponse » pour une lampe
  non joignable, mais seulement après qu'on a touché sa tuile (T5, T9), bien
  que le pont publie l'attribut Reachable et l'événement ReachableChanged. Ce
  comportement vient de Maison.
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
- **Lampe noire.** Une lampe lue en marche à l'intensité 0 (molette à 0 %)
  n'éclaire pas : elle est éteinte pour Maison, au dernier niveau non nul lu
  (une lampe éteinte à l'intensité 0 est montrée de même). Si elle n'en a lu
  aucun depuis le démarrage, le niveau de Matter n'est pas touché. La
  conversion donne bien le niveau 1 pour une intensité de 0 (bornes), mais ce
  niveau n'est jamais publié. Vérifié au banc le 02/10/2026 : la molette à
  0 % se lit « en marche, 0,0 % » (BANC.md).
- **Plancher de niveau 4 publié** (`PONT_NIVEAU_PLANCHER`). Leçon du Halo :
  sous 4, Maison montre une lampe allumée à fond. Une intensité qui donnerait
  un niveau de 1 à 3 est donc publiée au niveau 4.
- **Consigne arrondie au pour cent entier avant l'envoi** (banc C) : la 60d
  ne garde que le pour cent entier (433 est relu 430), et un ordre dont
  l'intensité tombait entre deux finissait abandonné alors que la lampe avait
  obéi. Une consigne non nulle vaut au moins 10 (1 %). Le prix : après la
  relecture, le curseur de Maison peut se recaler d'un niveau.

### 6.3 Marche/arrêt

- L'attribut OnOff correspond à la trame `0x8C`. « Allumée » veut dire en
  marche **et** à une intensité non nulle (6.2, lampe noire).
- Un niveau reçu pendant que la lampe reste éteinte part tout de suite (plan
  2) : R3 a montré qu'une lampe éteinte retient le niveau reçu sans
  s'allumer, puis s'allume directement à ce niveau. Le garder jusqu'à
  l'allumage ramènerait le curseur de Maison à l'ancien niveau, à la
  relecture suivante.
- **Lampe noire.** Une lampe noire (en marche à l'intensité 0), ou éteinte à
  l'intensité 0, se rallume à sa dernière intensité non nulle lue ; à défaut, à
  40 % (`LAMPES_INTENSITE_RALLUMAGE`, le niveau que la 60d a pris d'elle-même
  au retour d'une coupure, banc R4). Un niveau reçu avec l'ordre d'allumage
  (effet de LevelControl) remplace cette valeur.
- Le pont n'éteint jamais de lui-même une lampe noire : sa molette reste vive,
  alors qu'une lampe éteinte par l'app l'ignore (PROTOCOLE.md). C'est pourquoi
  Maison la montre éteinte : toucher sa tuile l'allume, au lieu d'envoyer un
  arrêt.

### 6.4 Pas d'écho

- Seul un ordre venu d'un contrôleur Matter ou de la console fait émettre.
- Pas d'écho, par construction : `lampes` pousse l'état dans Matter par
  `attribute::report()`, qui ne rappelle pas l'application. Aucun marquage des
  mises à jour n'est nécessaire.
- En plus, une valeur égale au dernier état lu, après l'arrondi au pour cent,
  ne fait jamais émettre. Cette comparaison porte sur l'état brut de la lampe.
- « Allumée = en marche et intensité non nulle » vaut pour ce que Maison
  montre et pour l'allumage : un ordre d'allumage sur une lampe noire n'est
  donc pas égal à son état, et la rallume (6.3).
- Un arrêt explicite sur une lampe noire, lui, part bien (`0x8C` à 0) : la
  lampe s'éteint alors « par l'app » et ignore sa molette (PROTOCOLE.md). Trois
  cas : `lampe <n> off` à la console ; un arrêt de Maison avant que le pont ait
  relu la lampe à 0 (une période de relecture au plus : 2 s par défaut) ; un
  double appui rapide sur sa tuile.

### 6.5 Démarrage

- esp-matter restaure les attributs. `StartUpOnOff` reste nul : rien ne
  change au démarrage.
- Joignable part de « oui » : pas de « Pas de réponse » fugace à chaque
  redémarrage.
- Seules des demandes d'état partent vers les lampes, la première dès que le
  Mesh est prêt : au moins 3 s après le démarrage d'un pont déjà appairé
  (6.6). Aucun ordre n'est rejoué.
- Maison se cale sur l'état réel dès les premières réponses.

### 6.6 Réseau et Apple

- Matter sur Thread, en appareil minimal (MTD). Le rôle est décrit en 5.8.
- **L'intervalle maximal des abonnements est plafonné à 20 s.** Leçon du Halo :
  Apple ne reprend pas seul un abonnement après un redémarrage du nœud ; il se
  réabonne quand l'intervalle expire.
- Pas de `blemesh_platform` : la pile Matter possède l'hôte NimBLE, et garde
  CHIPoBLE après la mise en service. La pile Bluetooth Mesh n'est donc pas
  initialisée au démarrage : l'ESP32 l'initialise, puis rejoint le réseau des
  lampes (provisionnement, écoute), une fois l'appairage Matter terminé et
  CHIPoBLE silencieux, 3 s plus tard (3 s après le démarrage s'il est déjà
  appairé). Le Mesh retient ses émissions si CHIPoBLE annonce de nouveau, et
  n'enregistre aucun service GATT (`CONFIG_BLE_MESH_PROXY=n`).
- Codes d'appairage de test du SDK, VID/PID `0xFFF1`/`0x8000`, comme pour le
  Halo, sans partition d'usine : une seule carte, à la maison. Maison accepte,
  avec l'avertissement « non certifié ». `matter` affiche le code tant que la
  carte n'est pas appairée. Le Halo a les mêmes codes : ne pas mettre les deux
  en service en même temps.

## 7. Erreurs et exploitation

### 7.1 Ordre sans réponse

Après 3 essais (5.6), l'ESP32 abandonne : Maison revient au dernier état lu,
et le voyant clignote 3 fois en rouge.

### 7.2 Lampe muette à la relecture

- Après 3 relectures sans réponse (~6 s à 2 s de période), Reachable passe à
  faux : Maison affiche « Pas de réponse ».
- À la première réponse, Reachable repasse à vrai et les attributs prennent
  l'état réel.

### 7.3 Bluetooth Mesh inopérant

Le voyant est rouge fixe, une fois la carte appairée à Maison (avant, le bleu
clignotant prime), et la console affiche le message.

| constat | cause probable | remède |
|---|---|---|
| clés absentes en NVS | jamais chargées, ou `mesh oublie` | `outils/cles_amaran.py` |
| clés présentes, mais pas entré dans le réseau après 2 min | Maison pas encore appairée (le Mesh démarre après), ou adhésion échouée | appairer le pont dans Maison ; sinon, lire le journal de démarrage |
| des annonces Mesh passent, mais aucune ne porte notre NID depuis 2 min | réseau recréé dans amaran Desktop : clés périmées | recharger les clés |
| notre NID, mais NetMIC faux | IV Index faux | `mesh iv` ou `mesh iv cherche` |

`mesh_pret` ne repasse jamais à non une fois le réseau rejoint : c'est le
diagnostic qui signale la panne. Dans tous les cas, les deux lampes passent à
« Pas de réponse » par la règle 7.2.

### 7.4 Voyant (WS2812, IO8) : signature du Halo

| voyant | sens |
|---|---|
| bleu clignotant | pas appairé à Maison |
| orange lent | réseau Thread absent |
| éteint, brève lueur blanche toutes les 10 s | tout va bien |
| rouge fixe | Bluetooth Mesh inopérant (7.3) |
| éclat vert | ordre confirmé par la lampe |
| rouge ×3 | ordre abandonné (7.1) |
| arc-en-ciel | un contrôleur demande l'identification (Identify) |
| rouge, noir, violet, noir, vite | BOOT tenu 8 s : relâcher pour désappairer |
| éclat blanc | BOOT court : redémarrage |

Priorités et intensités comme sur le Halo ; `led test` joue chaque motif.

### 7.5 Console série, en français

- `lampes` : pour chaque lampe, la consigne, l'état lu, l'âge de la dernière
  réponse et si elle est joignable.
- `lampe <n> on | off | niveau <0-1000> | releve` : pilotage manuel, pour les
  bancs, Djoko présent. Le niveau est arrondi au pour cent, comme pour Maison
  (6.2).
- `mesh` : adresse, IV Index, compteur de séquence, empreintes des clés,
  compteurs du crochet et de l'émission, part d'écoute du Mesh.
- Réglages : `mesh cles <netkey> <appkey>`, `mesh lampes <N>` puis
  `mesh lampe <n> <adresse> <mac> <code> <nom>` (plan 3a, spec N lampes 10),
  `mesh lampe <n> masquer | afficher`, `mesh iv <n> | cherche`,
  `mesh adresse <a> | suivante`,
  `mesh releve <s>`, `mesh balayage [<fenêtre> <intervalle>]` (part d'écoute
  du Mesh, en ms : 5.8), `mesh ecoute on | off` (écoute détaillée : messages
  d'accès, balises et états des lampes), `mesh oublie`.
- `mesh autotest` : passe les exemples chiffrés de la spécification Bluetooth
  Mesh dans les fonctions de chiffrement de la pile (9).
- `matter` : codes d'appairage, fabriques, rôle Thread, abonnements.
- `led` : état du voyant ; `led test` joue chaque motif, `led stop` l'arrête.
- `cause` : pourquoi la carte a redémarré la dernière fois.
- `taches` : marges de pile des tâches et du tas.
- `decommission`, `redemarre`.

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
- `decommission` les garde ; `mesh oublie` les efface, et garde la liste des
  lampes (plan 3a).

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
- Mesures avec Thread non dormant, puis dormant (le dormant n'a pas été
  essayé : la règle de 5.8 a tenu en non dormant) :
  - la part des relectures qui obtiennent une réponse, sur au moins 30 min ;
  - les ordres depuis Maison (une trentaine, à la main) et depuis la console
    (en rafales) : échecs et délai.
- Verdict une ou deux cartes, selon la règle de 5.8.

### 8.4 Phase 2 : produit

On ajoute le socle (voyant, bouton, console, fiche produit ; sans partition
d'usine : codes de test du SDK, 6.6), puis on passe les bancs :

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
- **`lampes`**, avec une horloge simulée : consigne remplacée, regroupement,
  ordre des trames, déroulé d'un ordre, 3 essais puis abandon, joignabilité,
  états périmés ignorés, arrondi au pour cent, lampe noire, valeur égale à
  l'état lu (rien n'est émis). L'absence d'écho n'est pas dans `lampes` : elle
  est construite dans `pont_matter` (6.4), qui publie par
  `attribute::report()`.
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
- NimBLE ; Bluetooth Mesh en rôle nœud, sans réglages persistés
  (`CONFIG_BLE_MESH_SETTINGS=n` : le compteur de séquence est sauvé par nous,
  5.4), avec 120 tampons d'annonce et sans proxy GATT
  (`CONFIG_BLE_MESH_PROXY=n`) ; `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING=n` ;
  OpenThread MTD ; `CONFIG_FREERTOS_HZ=1000` (tic de 1 ms, comme le Halo, pour
  le bouton et le voyant) ; `CONFIG_MBEDTLS_HARDWARE_AES=n`.
- Pas de plateforme externe `blemesh_platform` : la pile Matter possède l'hôte
  NimBLE (6.6).
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
components/          composants ; telink et mesh servent aux deux firmwares
  telink/            trames 0x26 (C pur)
  lampes/            le cœur (C pur)
  mesh/              ESP-BLE-MESH, crochet --wrap, file d'émission
  socle/             voyant et bouton BOOT : logique pure copiée du Halo
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
| Maison ne reprend pas les noms, ou n'affiche pas « Pas de réponse » | confort | aucune à faire : noms repris ; « Pas de réponse » seulement au toucher de la tuile, comportement de Maison (le pont publie l'attribut Reachable et l'événement ReachableChanged) | T1, T5 |
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
