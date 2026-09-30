# Bancs d'essai

Règles :
- Djoko est présent dès qu'on émet vers les lampes (`lampe …`, `groupe …`).
- Le port série est toujours donné explicitement : les écrans LG apparaissent eux aussi en `usbmodem`.
- `303A:1001` n'identifie pas la carte : deux C6 branchées sur le banc l'avaient. On reconnaît la C6 à son numéro de série USB (le champ `SER=` de la ligne `hwid` de `python -m serial.tools.list_ports -v`, à lancer dans l'environnement ESP-IDF, qui fournit pyserial). Ce numéro n'est écrit nulle part dans le dépôt.
- Les sous-agents ne flashent pas et n'ouvrent pas de port série.
- Sessions : `python3 outils/console.py --port <port> …` (le Python du système suffit : les outils n'utilisent plus pyserial). Le journal part dans `logs/`, ignoré par git.
- Ouvrir le port ne redémarre pas la carte : les outils baissent DTR et RTS en un seul appel. Un journal de démarrage à l'ouverture trahirait une régression.
- Les clés n'apparaissent nulle part. On compare seulement les empreintes.

## Phase 0 : reconnaissance (firmware `ecoute`)

### Préparation

```bash
export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh
cd ecoute && idf.py -p <port> flash && cd ..
python3 outils/cles_amaran.py --port <port>
python3 outils/console.py --port <port> "mesh autotest" "mesh" "@30" "mesh" "taches"
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
| `IV Index … adopte, mais non sauve (NVS : …)` au journal | IV trouvé, mais la NVS refuse l'écriture : `mesh iv <valeur>`, et s'arrêter si l'erreur revient |
| balises « notres » dont l'IV dépasse l'IV courant de plus de 42 | `mesh iv <IV de la balise>` (sauve et redémarre) |
| aucune balise, mais `NetMIC faux` > 0 | `mesh iv cherche` puis `mesh iv <valeur trouvée>` |
| `NID reconnu` = 0 | clés, ou lampes hors de portée : s'arrêter et en parler |

Réussi si, après `lampe 1 releve`, une ligne `etat lampe 1` apparaît au journal.

Contrôle de la recherche d'IV (aucune émission) :
1. `mesh iv <IV du réseau + 2>` ;
2. attendre du trafic des lampes (`NetMIC faux` > 0) ;
3. `mesh iv cherche`, puis `taches`. La recherche doit rendre l'IV exact ;
4. remettre le bon : `mesh iv <IV du réseau>`.

La pile refuse les balises d'un IV plus bas que le sien : le faux IV ne se corrige pas tout seul pendant le contrôle.

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

### Marges

Après chaque essai, `taches` : pile libre au plus bas de chaque tâche, et tas libre. Une tâche sous 512 octets libres est à agrandir avant la phase 1.

## Résultats

Carte : ESP32-C6 dédiée, firmware `ecoute` (commit fc18fae), adresse Mesh `0x7F38`. amaran Desktop ouvert pendant tous les essais.

| essai | date | résultat | remarques |
|---|---|---|---|
| R1 | 30/09/2026 | réussi | IV Index **0** : les balises des lampes l'annoncent (drapeaux 0), la pile l'avait déjà. Autotest 0 échec sur la carte, empreintes identiques. `lampe 1 releve` → `etat lampe 1 (0x0002 -> 0x0001) : arret, intensite 930 (93,0 %), mode CCT`, et la lampe était bien éteinte. Contrôle de la recherche : IV forcé à 2 → `NetMIC faux` et indice à la console → `mesh iv cherche` rend 0 → remis à 0. |
| R2 | 30/09/2026 | réussi | 20 demandes sur 20 (10 par lampe). Chaque réponse arrive 1 ou 2 fois (16 fois deux copies, 4 fois une), à 5 à 58 ms d'écart : très probablement les copies réseau de la lampe (le numéro de séquence n'est pas journalisé, donc non vérifié). |
| R3 | 30/09/2026 | réussi | Séquence vue par Djoko, conforme aux états relus. Boucle de 10 cycles `on`/`niveau`/`off` : 31 ordres sur 31 confirmés par lampe. `niveau` sur une lampe éteinte : retenu, sans l'allumer ; `on` rallume **directement** au niveau retenu (30 %). |
| R4 | 30/09/2026 | fait | **Aucun message spontané** : ni la molette, ni son bouton, ni une coupure. Lampe éteinte par l'app : molette et bouton (+20 %) **sans effet**. Coupée puis remise au bouton d'alimentation, la lampe revient **allumée vers 40 %** (41 % et 40 %). Deux cas seulement, une fois par lampe, chacune éteinte avant la coupure (à 93 % et à 6 % de niveau retenu) : une lampe allumée avant la coupure n'a pas été essayée. amaran Desktop redécouvre alors la lampe (voir PROTOCOLE.md). |
| R5 | 30/09/2026 | réussi | 10 demandes sur 10 au groupe « All » : les deux lampes répondent à chaque fois, à `0x0001`. |
| R6 | 30/09/2026 | fait | App → pont : les ordres d'amaran Desktop (`0x8C`, `0x8F`) sont captés à l'émission ; la lampe n'y répond pas. Ceux qu'on capte sont ceux adressés à la lampe 1 : la lampe 2 servait de proxy à l'app, et rien n'est passé en radio à son adresse (voir PROTOCOLE.md). Pont → app : l'affichage d'amaran Desktop **ne suit pas** nos ordres, même relus. L'app a fonctionné normalement. |

Marges (`taches`, après tous les essais) : pile libre au plus bas `mesh_adv_task` 1 052 o, `amaran_tx` 1 924 o, `console_repl` 2 092 o, `journal` 2 168 o, `nimble_host` 2 460 o ; tas libre au plus bas 330 Ko. Aucune tâche sous 512 o.

Compteurs en fin de banc : 750 messages vus, 750 déchiffrés, 0 NetMIC faux ; 190 messages émis, 0 refusé ; 0 événement perdu. Le plancher de séquence en NVS n'est jamais resté derrière la séquence (il lui est égal juste après un démarrage).

Incidents du banc, corrigés :
- ouvrir le port redémarrait la carte (pyserial baissait DTR puis RTS), et la première commande se perdait : commit d6fad12 ;
- le `redemarre` final de `cles_amaran.py` se perdait à la fermeture du port : commit 3d63553.
