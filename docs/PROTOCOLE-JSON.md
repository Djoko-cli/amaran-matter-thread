# Protocole JSON du pont amaran (v1)

Le protocole machine entre le pont (ESP32-C6, `firmware/`) et l'app Amaran Compagnon (`apps/macos/`), par l'USB et par Thread. Il reprend la version 1 du protocole du pont Halo (`~/Documents/Dev/esp32/benq/docs/PROTOCOLE-JSON.md`) : même tramage, même session, mêmes réponses, même enveloppe H1 par Thread. Seuls les messages propres au pont changent (sections 5 et 7). Le canal par Thread est décrit à la section 10.

Chaque exemple des sections 9 et 10 est formé tel quel par `tests/hote/test_json.cpp`, et chaque message que ce test forme y figure : le document et le firmware ne peuvent pas diverger.

## 0. Décisions en bref

| Sujet | Décision |
|---|---|
| Tramage | Une ligne machine = l'octet RS (`0x1E`), un objet JSON compact, puis LF. 1 024 octets au plus, RS et LF compris ; 896 au pire visé. Tout le reste du flux est du texte : réponses des commandes, journaux d'ESP-IDF, invite. |
| Sens app → pont | Les lignes de la console, telles qu'un humain les tape, préfixées par `id=<n> `. Jamais de JSON vers le pont. |
| Session | `json 1` passe en mode machine, avec un bail de 30 s que `json ping` renouvelle ; `json 0` ou le bail échu ramènent la console texte. Rien n'est gardé en NVS : chaque démarrage repart en texte. |
| Réponses | Toute ligne qui porte un `id` reçoit une `reponse`. Les ordres de lampe sont asynchrones : `reponse` aussitôt, puis l'événement `ordre`. Les autres commandes : `reponse` `debut`, leur texte, puis `reponse` `fin`. |
| État | `etat` (blocs `pont` et `sante` chaque seconde ; une ligne par lampe à chaque changement, et toutes les 10 s), `compteurs` (chaque seconde), `reseau` (toutes les 5 s). Les événements sont des indices ; la vérité est dans l'état périodique. |
| Compatibilité | `v` dans chaque ligne ; les ajouts ne changent pas `v` ; l'app ignore les champs, types et valeurs qu'elle ne connaît pas. |
| Clés | Jamais dans une ligne machine : seulement leurs empreintes (8 premiers chiffres hexa, en majuscules, du SHA-256). `reponse.cmd` d'un `mesh cles` ne cite pas les clés, et le pont ne renvoie pas d'écho en mode machine. Seule exception : la clé UDP, rendue une fois, par l'USB, à sa création (10.2). |
| Thread | Les mêmes lignes, dans des datagrammes UDP signés (enveloppe H1 de Halo), port 5480 ; deux sessions à la fois au plus ; une liste blanche de commandes (10.5). |

## 1. Vocabulaire et principes

- **pont** : l'ESP32-C6 et son firmware ; **app** : Amaran Compagnon.
- **ligne machine** : une ligne RS + JSON (section 2) ; **texte** : toute autre ligne.
- **lampe *n*** : la lampe numéro *n* de la liste du pont, de 1 à 16, comme dans les commandes de la console.
- **consigne** : l'état voulu pour une lampe (Maison, la console ou l'app) ; **état lu** : le dernier état que la lampe a renvoyé.

Principes :
1. **Le pont n'attend jamais l'app.** Une ligne machine qui ne tient pas dans le tampon d'émission de l'USB est perdue et comptée (`json_perdus`) ; `json_perdus` compte aussi les événements perdus parce que leur file interne était pleine (ils n'ont pas de `n`). Chaque session compte ses propres lignes perdues : l'USB les siennes, chaque session distante les siennes (10.4).
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
4. **1 024 octets au plus**, RS et LF compris. Le pire cas de chaque message à contenu variable, avec 16 lampes et des noms de 31 octets, tient en **896 octets** (vérifié par `tests/hote/test_json.cpp`) : il reste 128 octets aux ajouts. Un message qui approcherait le budget gagne un bloc, jamais de longueur.
5. Les premiers champs sont toujours `v`, `t`, `n`, `ms`, dans cet ordre, puis `bloc` pour les messages en blocs (`hello`, `config`, `etat`, `compteurs`, `reseau`).

### 2.3 Émission côté pont

- Une ligne est formée dans un tampon de 1 024 octets, puis confiée **d'un seul appel** au pilote de l'USB (`usb_serial_jtag_write_bytes`, sans attente) : elle entre entière dans son tampon d'émission de 4 096 octets, ou pas du tout. Faute de place, elle est perdue et comptée (`json_perdus`) ; le pont réessaie une fois une milliseconde plus tard, pour le cas où une autre tâche tenait le pilote.
- Les lignes périodiques et les instantanés passent par une file (48 places) : la tâche `json` en émet une toutes les 10 ms. Une ligne périodique en retard de plus de 500 ms est perdue et comptée ; une `reponse` n'est jamais abandonnée pour retard : si la file est pleine, elle part tout de suite ; elle n'est perdue, et comptée dans `json_perdus`, que si le pilote de l'USB n'a pas de place.
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
| `json trames 0\|1` | trafic Bluetooth Mesh en messages `trame` (7.6) ; à distance, coupé seul au bout de 60 s | 0 par défaut |
| `json cle nouvelle <64 hexa>` | crée la clé UDP (10.2) ; USB seulement | |
| `json cle efface` | efface la clé UDP : les sessions distantes tombent, le port 5480 se ferme | |

Un argument hors bornes : `reponse` `usage`, avec les bornes dans `msg`.

### 3.4 Bail et ping

Le pont date le dernier octet reçu et la fin de la dernière commande ; le bail court depuis le plus récent des deux, et pas pendant une commande (la console ne lit plus l'USB tant qu'elle tourne). Bail échu : message `fin` (`cause` `bail`), puis le texte `json : mode machine coupe (hote muet depuis 30 s)` et l'invite. L'app envoie `json ping` après 10 s sans autre commande.

### 3.5 Battement, silence, redémarrage

- Les blocs `etat` servent de battement. Si `periode_ms` vaut 0 ou plus de 2 000, le pont émet un `hb` toutes les 2 000 ms.
- Silence : aucune ligne depuis 3 × max(période, 2 s), hors commande en cours. L'app renvoie `json 1` ; sans réponse sous 5 s, elle ferme et rouvre le port.
- Redémarrage : `boot` (8 chiffres hexa tirés au démarrage) change, ou `up_s` recule.

### 3.6 Écho et invite

En mode texte, la console est celle d'ESP-IDF (linenoise, toujours en mode simple : sans édition aux flèches) : écho, invite `amaran> `, historique. En mode machine, la tâche de la console lit elle-même l'USB, sans écho ni invite : linenoise ne sait pas couper son écho. L'app affiche elle-même la commande envoyée dans sa console.

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
| `rev` | révision mineure du protocole (1 : Thread, `trame`, `texte`) |
| `fw` | version du firmware (`0.1.0-<commit>`) |
| `date`, `heure` | compilation |
| `idf`, `puce` | version d'ESP-IDF, `esp32c6` |
| `boot` | 8 hexa, tirés au démarrage |
| `reset`, `reset_n` | cause du démarrage : `mise_sous_tension`, `broche`, `logiciel`, `panique`, `chien_int`, `chien_tache`, `chien`, `baisse_tension`, `usb`, `inconnue` ; et la valeur de `esp_reset_reason()` |
| `up_s` | secondes depuis le démarrage |
| `session` | réglages en vigueur : `transport` (`usb` ou `udp`), `periode_ms`, `lampes_ms`, `compteurs_ms`, `reseau_ms`, `bail_s`, `log`, `trames` |
| `limites` | `ligne_max` (1 024), `cmd_max` (127) |

**Bloc `identite`** : `boot` ; `mac` (MAC de la puce) ; `id` (`fabricant`, `produit`, `serie` = `AMARAN-<MAC>`, `nom`) ; `caps`, les capacités : `matter`, `thread`, `mesh`, `catalogue`, `ordres` (ordres de lampe asynchrones), `led`, `log`, `trames`, `udp` (canal par Thread), `cle` (`json cle`), `texte` (texte des commandes à distance), `logiciel` (`mesh lampe` prend la version du logiciel de la lampe, et le bloc `lampe` la rend). L'app se règle sur `caps`, pas sur la version du firmware.

### 5.2 `config`

Réglages lents : émis avec `hello`, et de nouveau après toute commande `mesh` réussie portant un `id`.

**Bloc `catalogue`** : `modeles`, un objet par modèle catalogué (`code` produit Sidus, `nom`, `capacites` parmi `intensite`, `cct`, `couleur`, `type` d'appareil Matter `variable`, `temperature` ou `couleur`, `cct_k` : `{min, max}` ou `null`), et `repli`, le modèle prêté à un code inconnu. Le firmware est la seule source du catalogue.

**Bloc `mesh`** : `cles` (chargées ou non), `empreintes` (`reseau`, `application`, ou `null` sans clés), `adresse` de l'ESP32, `iv_nvs` (l'IV Index gardé en NVS), `balayage` (`fenetre_ms`, `intervalle_ms`), et l'en-tête de la liste : `lampes` (*N*), `capacite` (16), `releve_ms` (période de relecture), `groupe` (`C000`). Les clés chargées par `mesh cles` ne valent qu'après le redémarrage : jusque-là, ce bloc montre les empreintes en service.

**Bloc `lampe`**, une ligne par lampe de la liste en service : `lampe`, `adresse`, `mac`, `nom`, `code`, `modele` (nom du modèle, ou celui du repli), `catalogue` (code connu ou non), `capacites`, `type`, `logiciel` et `ble` (versions du logiciel de commande et du module Bluetooth de la lampe, `x.y`, chargées depuis la base d'amaran Desktop ; `null` si inconnues). Une liste chargée par `mesh lampes` ne vaut, elle aussi, qu'après le redémarrage.

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

**Bloc `sante`** (toutes les `periode_ms`) : `boot`, `up_s` ; `commande` : l'`id` de la commande de la console en cours, ou `null` (6.2) ; `led` (`motif` du voyant, `test`, `depuis_ms` : âge de la phase du motif) ; `matter` (`en_service`, `thread` attaché, `identifie`, `ble` : annonce de mise en service en cours) ; `sys` (`heap`, `heap_min`, `heap_bloc`, `piles` : octets jamais utilisés de chaque tâche, `null` si elle n'existe pas, `json_perdus` : lignes perdues de cette session, et événements perdus file pleine, `json_trop_longs`, `rejets` : lignes refusées pour longueur ou cadence).

### 5.4 `compteurs`

**Bloc `mesh`** (toutes les `compteurs_ms`), cumulatifs depuis le démarrage : `annonces` (messages Mesh vus), `nid_reconnu` et `nid_inconnu` (de notre réseau ou d'un autre), `netmic_faux`, `acces_dechiffres`, `etats_lampes`, `doublons` (copies réseau et rejeux écartés), `balises` (`notres`, `autres`, `fausses`, `derniere` : `iv`, `drapeaux`, `ms`, ou `null`), `emis`, `echecs_emission`, `file_pleine` (événements du crochet perdus), puis l'`iv` courant, la séquence `seq` et le `plancher` de séquence gardé en NVS.

### 5.5 `reseau`

**Bloc `matter`** (toutes les `reseau_ms`) : `demarre`, `fabriques`, `ble`, `identifie` ; `abonnements` (`demandes`, `plafonnes`, `etablis`, `termines`, `plafond_s`) ; `code_manuel` et `qr` (charge `MT:…`), pour ajouter le pont à Maison, ou `null` ; toujours `null` vers une session distante (10.1). Les abonnements actifs valent à peu près `etablis − termines`.

**Bloc `thread`** : `role` (`disabled`, `detached`, `child`, `router`, `leader`), tel que l'annonce le dernier événement d'OpenThread ; `attache`. Le pont ne prend jamais le verrou d'OpenThread depuis ses tâches : ce qu'il lui demande passe par la file de tâches d'OpenThread.

**Bloc `ip`** : `srp`, le nom que le pont publie par SRP (16 hexa ; l'app le résout en `<srp>.local`), ou `null` ; `adresses`, ses adresses (`type` : `omr`, `ml_eid`, `autre` ; `adresse`) ; `udp` : `port` (5480), `cle` (une clé UDP existe), `empreinte` (8 hexa, ou `null`), `ouvert` (le port écoute), `sessions` (sessions H1 établies), `recus`, `emis`, `rejets` (datagrammes refusés en silence : 10.3), `perdus`.

### 5.6 `hb` et `fin`

`hb` : battement quand les `etat` sont coupés ou lents (3.5) : `boot`, `up_s`, `json_perdus` (comme dans le bloc `sante` : lignes de cette session et événements perdus), et `commande` comme le bloc `sante`.

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
| `lampe <n> on\|off\|niveau <0-1000>` | **asynchrone** : `reponse` `fin`, code `accepte`, `suite` `ordre`, en quelques millisecondes ; puis l'événement `ordre` qui porte l'`id` (7.1), toujours après la réponse `accepte` ; si la file des lampes est pleine : `erreur`, « file des lampes pleine », sans `suite` |
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
| `cle`, `empreinte` | `json cle nouvelle` : la clé UDP (64 hexa), une seule fois, et son empreinte |

| Code | ok | Sens |
|---|---|---|
| `ok` | oui | exécutée |
| `accepte` | oui | ordre de lampe accepté : un `ordre` suivra (si la file des lampes ne peut pas le prendre, la réponse est `erreur`, « file des lampes pleine », sans `suite`) |
| `en_cours` | oui | étape `debut` |
| `erreur` | non | la commande a échoué : son texte dit pourquoi |
| `usage` | non | arguments invalides (famille `json`, ordres de lampe) |
| `inconnue` | non | commande inconnue |
| `trop_long` | non | ligne de plus de 127 octets : rien n'est exécuté |
| `cadence` | non | plus de 20 lignes par seconde en mode machine : rien n'est exécuté |
| `interdite` | non | à distance, commande hors de la liste blanche (10.5) : rien n'est exécuté |
| `deja_traite` | non | à distance, `id` plus ancien que les 8 dernières réponses gardées (10.4) |

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
| clés | charger le pont | `mesh cles <reseau> <application>`, `mesh lampes <N>`, une ligne `mesh lampe <n> <adresse> <mac> <code> [v<logiciel>[/<ble>]] <nom>` par lampe (la version seulement si `caps` contient `logiciel`), puis `redemarre` |
| console | tout le reste | la ligne tapée, préfixée d'un `id` |

L'app confirme avant d'envoyer `redemarre`, `decommission`, `mesh oublie`, `mesh adresse`, `mesh iv` et `mesh lampe <n> masquer`. Elle n'envoie qu'une commande à la fois, et attend sa `reponse` `fin` (3 s au plus sans `debut`) avant la suivante.

## 7. Événements (pont → app)

Émis en mode machine seulement, dès que le pont les constate.

### 7.1 `ordre` : fin d'un ordre de lampe

`lampe` ; `issue` : `confirme` (l'état relu égale la consigne), `abandon` (trois essais sans confirmation, ou Bluetooth Mesh pas prêt), `tenu` (la lampe était déjà dans cet état : rien n'est émis) ; `delai_ms` (depuis le dernier ordre de la chaîne ; 0 pour `tenu`, et pour un ordre refusé faute de Bluetooth Mesh) ; `essai` (1 à 3 ; 0 pour `tenu`, et pour un ordre refusé faute de Bluetooth Mesh) ; `ids` (les `id` des ordres de l'app couverts, 4 au plus ; vide pour un ordre de Maison ou de la console sans `id`) ; `ids_perdus` (au-delà de 4 ; ce compte est celui de la lampe, toutes origines confondues : une session peut y lire des `id` perdus d'une autre).

### 7.2 `alerte`

- `quoi` `releves` : `lampe`, `manque` (vrai quand la part des relectures répondues sur 10 min passe sous 95 %, faux quand elle y revient), `part` (en pour cent).
- `quoi` `mesh` : `diag`, la cause probable d'un Bluetooth Mesh inopérant (5.3), ou `ok` quand il repart.

### 7.3 `lampe` : place dans Maison

`lampe` ; `quoi` : `entree` (première réponse d'une lampe jamais vue : elle entre dans Maison), `masquee` (`mesh lampe <n> masquer`), `remise` (`mesh lampe <n> afficher`), `echec` (endpoint Matter non créé) ; `endpoint`, ou `null`.

### 7.4 `led` : motif du voyant

À chaque changement de motif : `motif`, `avant`, `test`, `depuis_ms`. Les motifs sont ceux du pont Halo (`components/socle/include/status_led.h`, `patternCode`) : `identification`, `desappairage`, `redemarrage`, `injoignable`, `panne_radio` (ici : Bluetooth Mesh inopérant), `livree` (ordre confirmé), `non_appaire`, `hors_reseau`, `operationnel`.

### 7.5 `log` : annonces du pont

Seulement avec `json log 1` : les annonces de la tâche des lampes (`[lampes] …`, `!! …`, `[mesh] …`) et du bouton BOOT (`[bouton] …`) partent alors en `log` **au lieu** du texte. Champs : `src` (`lampes`, `mesh`, `bouton`), `niv` (`notice` ou `alerte`), `txt` (127 octets au plus). Au plus 20 par seconde ; au-delà, le suivant porte `sautes`. Les journaux d'ESP-IDF et le texte des commandes ne passent jamais par `log`.

### 7.6 `trame` : trafic Bluetooth Mesh

Seulement avec `json trames 1` : chaque message de lampe que le pont émet ou reçoit, décodé. `sens` (`tx`, `rx`) ; `quoi` : `ordre` (marche ou intensité vers une lampe), `demande` (demande d'état au groupe des lampes), `etat` (état renvoyé par une lampe) ; `lampe` (`null` pour le groupe) ; `marche`, `intensite` (`null` si absents) ; `essai` (ordre, 1 à 3) ; `sautes` : trames non émises depuis la précédente (au plus 50 par seconde par l'USB, 10 à distance). À distance, `json trames 1` se coupe seul au bout de 60 s.

## 8. Versionnage et débit

- `v` change seulement pour une rupture. Tout le reste est additif et garde `v` ; `rev` augmente à chaque ajout.
- L'app ignore les champs, types et blocs inconnus, et range une valeur d'énumération inconnue sous « inconnu ».
- Au repos, deux lampes, réglages par défaut : environ 1,8 Ko/s (`etat` `pont` et `sante`, `compteurs` chaque seconde ; une ligne par lampe toutes les 10 s ; `reseau` toutes les 5 s). À 16 lampes : environ 2,3 Ko/s. Un instantané complet à 16 lampes fait 43 lignes, environ 11 Ko, émises en un peu plus de 0,4 s. À distance, le débit est plafonné (10.3).

## 9. Exemples (USB)

`<RS>` note l'octet `0x1E` ; le LF final est omis. Les MAC, le numéro de série et les empreintes sont inventés.

### 9.1 Connexion

App → pont (`\x15` : l'octet `0x15`, suivi de LF) :

```
\x15
id=1 json 1
```

Pont → app : le pont a deux lampes, toutes deux dans Maison ; « Lumière fenêtre » montre un nom accentué.

```
<RS>{"v":1,"t":"hello","n":0,"ms":83512,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"3FA2C901","reset":"logiciel","reset_n":3,"up_s":83,"session":{"transport":"usb","periode_ms":1000,"lampes_ms":10000,"compteurs_ms":1000,"reseau_ms":5000,"bail_s":30,"log":false,"trames":false},"limites":{"ligne_max":1024,"cmd_max":127}}
<RS>{"v":1,"t":"hello","n":1,"ms":83522,"bloc":"identite","boot":"3FA2C901","mac":"F0F5BD0A0B0C","id":{"fabricant":"TEST_VENDOR","produit":"TEST_PRODUCT","serie":"AMARAN-F0F5BD0A0B0C","nom":"Pont amaran"},"caps":["matter","thread","mesh","catalogue","ordres","led","log","trames","udp","cle","texte","logiciel"]}
<RS>{"v":1,"t":"config","n":2,"ms":83532,"bloc":"catalogue","modeles":[{"code":40065,"nom":"amaran COB 60d","capacites":["intensite"],"type":"variable","cct_k":null}],"repli":{"nom":"modele non catalogue","capacites":["intensite"],"type":"variable","cct_k":null}}
<RS>{"v":1,"t":"config","n":3,"ms":83542,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":0,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}
<RS>{"v":1,"t":"config","n":4,"ms":83552,"bloc":"lampe","lampe":1,"adresse":"0002","mac":"020000000001","nom":"Lampe bureau","code":40065,"modele":"amaran COB 60d","catalogue":true,"capacites":["intensite"],"type":"variable","logiciel":"1.4","ble":"1.69"}
<RS>{"v":1,"t":"config","n":5,"ms":83562,"bloc":"lampe","lampe":2,"adresse":"0004","mac":"020000000002","nom":"Lumière fenêtre","code":40065,"modele":"amaran COB 60d","catalogue":true,"capacites":["intensite"],"type":"variable","logiciel":null,"ble":null}
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

## 10. À distance (Thread)

### 10.1 Le canal

Les mêmes lignes qu'à l'USB, dans des datagrammes UDP sur le réseau Thread, port 5480. L'app apprend par l'USB le nom SRP du pont (bloc `reseau` `ip`) et le résout en `<srp>.local` (mDNS, IPv6) : le nom suit les changements de préfixe. L'enveloppe est celle de Halo, octet pour octet :
- poignée de main : l'app envoie `H1 SALUT <kid> <na> <mac>` ; le pont répond `H1 DEFI <sid> <nc> <mac>` (plus court que le SALUT : aucune amplification). `kid` : empreinte de la clé UDP ; `na`, `nc` : aléas de 16 octets ; les `mac` : HMAC-SHA256 de la clé UDP. La clé de session dérive de la clé UDP, de `na`, `nc` et `sid` ;
- messages : `H1 <sid> <ctr> <mac> <ligne>`, une ligne par datagramme. `mac` : 16 octets du HMAC-SHA256 de la clé de session sur le sens (`A` : app → pont, `C` : pont → app), `sid`, `ctr` et la ligne ; `ctr` compte de 1 par sens ; une fenêtre de 32 refuse les rejeux ;
- intégrité seulement, pas de confidentialité : rien de secret ne passe par Thread. Vers une session distante, `code_manuel` et `qr` valent `null` dans le bloc `reseau` `matter`, et la commande `matter` n'imprime pas les codes d'appairage.

### 10.2 La clé UDP

32 octets, créés par l'USB seulement : l'app tire un aléa de 32 octets et envoie `json cle nouvelle <64 hexa>` ; le pont dérive la clé de cet aléa et du sien, l'écrit en NVS, ouvre le port 5480 et la rend **une seule fois**, dans la `reponse` (`cle`, `empreinte`). `reponse.cmd` ne cite jamais l'aléa. L'app la range dans le trousseau du Mac. `json cle efface`, `decommission` ou le bouton BOOT tenu 8 s l'effacent ; une nouvelle clé fait tomber les sessions en cours. Sans clé, le port 5480 est fermé. Avec un `id` hors du mode machine (sans `json 1`), `json cle nouvelle` est refusée (`usage`, rien ne change) : seule une ligne du mode machine porte la clé. Si l'accès par Thread n'a pas démarré (Matter non démarré), `json cle nouvelle` répond `erreur` et rien ne change ; `json cle efface`, `decommission` et BOOT effacent quand même la clé de la NVS. Si la NVS refuse l'effacement, la clé quitte la mémoire (sessions tombées, port fermé) mais reviendrait au redémarrage : `json cle efface` répond `erreur`, et son `msg` le dit.

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
