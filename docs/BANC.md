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
| R6 | 30/09/2026 | fait | App → pont : les ordres d'amaran Desktop (`0x8C`, `0x8F`) sont captés à l'émission ; la lampe n'y répond pas. Ceux qu'on capte sont ceux adressés à la lampe 1 : la lampe 2 servait très probablement de proxy à l'app, et rien n'est passé en radio à son adresse (voir PROTOCOLE.md). Pont → app : l'affichage d'amaran Desktop **ne suit pas** nos ordres, même relus. L'app a fonctionné normalement. |

Marges (`taches`, après tous les essais) : pile libre au plus bas `mesh_adv_task` 1 052 o, `amaran_tx` 1 924 o, `console_repl` 2 092 o, `journal` 2 168 o, `nimble_host` 2 460 o ; tas libre au plus bas 330 Ko. Aucune tâche sous 512 o.

Compteurs en fin de banc : 750 messages vus, 750 déchiffrés, 0 NetMIC faux ; 190 messages émis, 0 refusé ; 0 événement perdu. Le plancher de séquence en NVS n'est jamais resté derrière la séquence (il lui est égal juste après un démarrage).

Incidents du banc, corrigés :
- ouvrir le port redémarrait la carte (pyserial baissait DTR puis RTS), et la première commande se perdait : commit d6fad12 ;
- le `redemarre` final de `cles_amaran.py` se perdait à la fermeture du port : commit 3d63553.

### Plan 2 : contrôle du firmware d'écoute (Tasks 2 à 4)

30/09/2026, firmware `ecoute` du commit `00254ff`, sur la C6 du pont. La NVS du plan 1 est gardée : adresse `0x7F38`, IV Index 0. amaran Desktop est ouvert.
- **Autotest** : 11 vérifications, 0 échec, dont la BeaconKey et l'authentification de balise (exemples 8.2.6 et 8.4.3 de la spec Mesh).
- **Entrée dans le réseau sans balise « non provisionné »** : `mesh pret : oui` dès le démarrage. La séquence reprend au plancher sauvé (`0x000303`).
- **Balises des lampes authentifiées** : 7 après 30 s d'écoute, 0 fausse ; 30 sur l'ensemble du contrôle.
- **R2 abrégé** : 10 réponses sur 10, une ligne chacune.
  - 11 doublons écartés pendant les 10 demandes (13 au compteur depuis le démarrage, dont 2 avant la première demande).
  - 10 messages émis, 0 refus, 0 NetMIC faux.
- **Coupure de la lampe 2** au bouton d'alimentation, puis remise :
  - elle répond à chacune des 3 demandes : le filtre des rejeux ne l'écarte pas. Son compteur de séquence n'est donc très probablement pas reparti sous la dernière valeur vue (déduit : le numéro de séquence n'est pas journalisé, et une seule coupure a été faite) ;
  - elle est revenue **allumée à 6 %**, son niveau retenu, et non vers 40 % comme au banc R4.
- **Marges** : pile libre la plus basse `console_repl` 1 932 o ; tas libre au plus bas 330 692 o.

## Phase 1 : banc C, radio partagée (firmware du pont)

30/09/2026. Procédure : plan 2, Task 8. Carte du pont effacée, flashée, clés rechargées, puis appairée dans Maison. Thread en enfant non dormant (MED), relecture au groupe toutes les 5 s, amaran Desktop fermé pendant les mesures au repos.

### Premier essai : le Mesh étouffe Thread

Réglé comme par défaut dans ESP-IDF, le Bluetooth Mesh écoute en continu (20 ms toutes les 20 ms). Dès son entrée dans le réseau, 3 s après la mise en service, toutes les émissions Thread échouent (« ChannelAccessFailure »). La seconde mise en service d'Apple expire, et l'appairage échoue dans Maison. C'est le cas « End Device + BLE Scan », que la documentation d'ESP-IDF sur la coexistence classe comme instable.

### Leviers appliqués

- **Écoute du Mesh à 50 %** (20 ms toutes les 40 ms), réglable à chaud par `mesh balayage` (commit `67631cc`). Thread ne perd plus une émission. Le pont règle cette valeur au démarrage.
- **Consigne d'intensité arrondie au pour cent** (commit `c588bc3`). La 60d ne garde que le pour cent entier (voir PROTOCOLE.md). Sans cela, les ordres dont l'intensité ne tombait pas sur un pour cent entier finissaient abandonnés après trois essais, alors que la lampe avait obéi.
- **Demande d'état envoyée deux fois** (commit `c0b7f13`). À 50 % d'écoute, une réponse sur dix environ était manquée ; deux demandes donnent deux chances.

### Mesures

| réglage | durée | relectures répondues, lampe 1 | lampe 2 |
|---|---|---|---|
| écoute 50 %, 1 demande | 30 min | 324/360 (90,0 %) | 323/360 (89,7 %) |
| écoute 75 %, 1 demande | 10 min | 108/120 (90,0 %) | 112/120 (93,3 %) |
| écoute 100 %, 1 demande (5 échecs d'émission Thread) | 3 min | 35/36 (97,2 %) | 34/36 (94,4 %) |
| écoute 50 %, 2 demandes | 30 min | 349/360 (96,9 %) | 354/360 (98,3 %) |

| ordres de Maison | salves | confirmées | abandonnées | au-delà d'1 s | délai moyen, maximal |
|---|---|---|---|---|---|
| écoute 50 %, 1 demande, sans arrondi | 15 | 10 | 5 | 2 | 650 ms, 1 111 ms |
| écoute 50 %, 2 demandes, avec arrondi | 47 | 47 | 0 | 0 | 455 ms, 974 ms |

**Verdict (règle 5.8) : une seule C6 suffit**, avec les trois leviers.
- Relectures répondues : 96,9 % et 98,3 % sur 30 min (seuil : 95 %).
- Ordres de Maison : 0 échec et 0 au-delà d'une seconde sur 47 (seuil : 1 %).
- Thread : aucun échec d'émission sur les mesures à 50 %.

Mémoire : image de 1,70 Mo (58 % de la partition libre) ; pile de `main` 1 552 o libres au plus bas ; pile libre la plus basse `lampes` 1 892 o ; tas libre au plus bas 186 548 o.

Remarques :
- Maison reprend les noms d'amaran Desktop. Au premier démarrage sans clés, les deux emplacements s'appellent « lampe absente » ; ils prennent les vrais noms au redémarrage qui suit le chargement des clés.
- Aucun ordre parasite au démarrage.
- Glisser le curseur de luminosité dans Maison envoie une valeur toutes les 150 à 300 ms. Le pont suit, mais taper sur la jauge est plus fluide (constat de Djoko).
- Pendant une série d'ordres, les relectures répondues baissent (104/122 et 115/122 sur 10 min). Relectures et ordres passent par la même file d'émission, mais la cause n'est pas établie.
- Budget de séquence : deux demandes toutes les 5 s consomment environ 35 000 numéros par jour ; l'adresse change d'elle-même tous les 7 mois environ.

## Phase 2 : bancs T (firmware complet)

01/10/2026. Procédure : plan 2, Task 11. Firmware du commit `8bf88a5`, flashé sans effacer : l'appairage et les clés de la phase 1 restent. amaran Desktop fermé, sauf pour T4.

Au démarrage : cause `reinitialisation par l'USB`, 2 fabriques, Thread `child`, Bluetooth Mesh prêt, écoute à 50 %, voyant opérationnel. `led test` : Djoko a vu les 9 motifs, dans l'ordre.

| banc | date | résultat | remarques |
|---|---|---|---|
| T1 ordres depuis Maison | 01/10/2026 | réussi | Chaque ordre obéi, sur les deux lampes. 25 ordres confirmés, 0 abandon, 465 ms en moyenne, 781 ms au plus. Les tuiles portent les noms d'amaran Desktop. |
| T2 curseur glissé vite | 01/10/2026 | réussi | La lampe finit à la valeur lâchée. 51 écritures, 9 salves, toutes confirmées, 0 abandon, 0 refus ; une confirmation à 1 577 ms pendant le glissé. |
| T3 molette | 01/10/2026 | réussi | Maison suit en 5 s environ, trois fois par lampe. |
| T4 amaran Desktop | 01/10/2026 | réussi | Luminosité et extinction depuis l'app : Maison suit en 5 s environ. L'app fonctionne normalement. |
| T5 lampe coupée | 01/10/2026 | partiel | Le pont est conforme : `PAS DE REPONSE` et Reachable à faux publiés 15 à 20 s après la coupure ; Reachable revient à vrai dès la première réponse. Mais **Maison n'affiche « Pas de réponse », puis le retour, qu'après avoir touché la tuile**. La lampe, allumée à 60 % juste avant la coupure, est revenue éteinte, à ce niveau retenu. |
| T6 redémarrage du pont | 01/10/2026 | réussi | Aucune lampe n'a bougé. `redemarrage logiciel`, 0 ordre, 6 relectures en 28 s. Maison garde les lampes joignables, avec leur état réel. |
| T7 Thread perdu | — | non fait | Couper tout le réseau Thread de la maison était trop contraignant. À faire plus tard. |
| T8 bouton BOOT | 01/10/2026 | réussi | Appuis courts (183 et 168 ms) : éclat blanc, redémarrage. 3,7 s et 6,7 s : annulés. 8,5 s : rouge et violet, retrait des fabriques, redémarrage en bleu. Clés gardées ; réappairé dans Maison, les deux lampes reviennent sous leurs noms. |
| T9 clés oubliées, rechargées | 01/10/2026 | réussi | `mesh oublie` : message `cles absentes`, rouge fixe, « Pas de réponse » pour les deux lampes. Clés rechargées : tout revient en 30 s environ. Maison garde les tuiles (noms, pièce). |
| T10 endurance 24 h | 01/10 au 02/10/2026 | réussi | 24 h sans redémarrage. Relectures répondues : 97,9 % (lampe 1) et 98,3 % (lampe 2), sur 17 270 chacune. Ordres de Maison : 41 salves (121 écritures), toutes confirmées, 0 abandon, 510 ms en moyenne, 861 ms au plus. Émission : 17 408 messages, 0 refus, 0 événement perdu. Séquence Mesh : +34 816 en 24 h (2 par message), loin de `0x700000`. Tas libre : 187 324 o au début, 186 636 o à la fin (au plus bas 179 024 o) ; aucune tâche sous 1 888 o libres. Thread toujours attaché ; 1 abonnement actif à la fin. |

Remarques :
- **Maison et Reachable (T5, T9).** Maison ne met pas d'elle-même à jour l'état « joignable » d'une lampe : il faut toucher sa tuile. Le pont, lui, publie chaque changement : l'attribut Reachable, et aussi l'événement ReachableChanged (constat fait dans le code d'esp-matter, pas à l'écoute du réseau). Le comportement vient donc de Maison. La spec (11) acceptait ce risque, qui relève du confort.
- **Appui de 42 ms (T8).** Juste après l'appui annulé de 6,7 s, la console a noté un appui court de 42 ms, et la carte a redémarré. Ce n'est pas un rebond : l'anti-rebond du bouton exige que chaque niveau tienne 30 ms, ce qu'un rebond électrique ne fait pas, et ce contact en a duré 42. C'était un second contact réel, probablement un doigt qui retouche le bouton en le quittant. Conséquence bénigne : un redémarrage ne rejoue aucun ordre et garde les clés et l'appairage. Aucune garde n'est ajoutée, et le README conseille de relâcher net.
- **Tuile en chargement (T1).** Une fois, la tuile de la lampe 2 est restée « en chargement » à 100 % après son extinction, alors que le pont avait publié l'état. Non reproduit sur 4 essais.
- **Molette à 0 %.** Baissée jusqu'à 0 % à la molette, la lampe n'éclaire plus, mais Maison la montrait allumée à 1 %. Corrigé dans le commit `2b2393b` : une lampe lue en marche à l'intensité 0 est montrée éteinte, à son dernier niveau non nul, et la toucher la rallume à ce niveau (spec 6.2 et 6.3). Vérifié au banc le 02/10 (ci-dessous).
- **Endurance (T10).** Sur les 24 h : 128 830 messages Mesh vus, 0 NetMIC faux ; 6 émissions Thread perdues après leurs relances (3 `ChannelAccessFailure`, 3 `NoAck`), isolées ; environ 95 avertissements Thread « Duplicated » par heure, réguliers (messages de gestion reçus deux fois) ; 3 reprises d'abonnement échouées vers un contrôleur disparu et 5 messages sur une session inconnue, dans la première heure : bruit du SDK Matter, sans effet.
- **Pile de la tâche `socle`** : 2 604 o libres au plus bas, relevés après le redémarrage qui suit le désappairage par BOOT. Ce minimum ne couvre donc pas le passage par `factory_reset()`, exécuté dans la tâche `socle` avant ce redémarrage. Ce passage s'est fait sans panique (fabriques retirées, réappairage). Tas libre au plus bas : 178 540 o après le réappairage.

### Contrôle de la vague de correctifs

02/10/2026, après T10. Firmware du commit `7ab7339`, flashé sans effacer. Djoko présent.

- **Démarrage.** 2 fabriques, Thread `child`, 1 abonnement, Bluetooth Mesh prêt. Le journal d'un redémarrage montre `balayage regle : 20 ms sur 40 ms` 5 ms avant `entre dans le reseau` : l'écoute à 50 % est posée avant l'adhésion. Aucun échec d'émission Thread.
- **Lampe noire.** Lampe 1 allumée depuis Maison, puis molette à 0 % : `lampes` lit `marche 0,0 % (noire : eteinte pour Maison)`, et Maison la montre éteinte, à son dernier niveau lu (7 % ou 12 % selon l'essai).
- **Siri « éteins » sur la lampe noire.** Le pont reçoit l'arrêt ; la pile Matter répond `On/off already set to new value`, et rien ne part vers la lampe. La molette, remontée ensuite, rallume la lampe, et Maison suit.
- **Toucher la tuile de la lampe noire.** Une seule commande « allumer » : la lampe se rallume à son dernier niveau (7 %).
- **Curseur de groupe.** Djoko a regroupé les deux lampes en un seul accessoire de Maison, puis a fait glisser sa luminosité. Les deux lampes suivent ; la lampe 2 avec un léger retard : Maison envoie ses commandes une lampe après l'autre, à 1 ou 2 s d'écart. 0 abandon, 0 refus ; une confirmation à 1 106 ms.
- **Depuis le flash** (environ 11 h) : relectures répondues 98,3 % et 98,8 % ; 52 écritures, 20 salves confirmées, 0 abandon ; 7 958 messages émis, 0 refus.

Remarques :
- **Un premier essai de Siri a verrouillé la molette**, sans capture pour en voir la cause. Le plus probable : l'arrêt est parti avant que le pont ait relu la lampe à 0 (spec 6.4). Refait avec une capture : conforme.
- **Une tuile touchée trop tôt** (avant que le pont ait publié la lampe noire) envoie un arrêt, puis le geste suivant un allumage : c'est le cas décrit au README (« À savoir »).
- **Intensité changée sur une lampe éteinte par l'app.** Vers 12:52, la lampe 1, éteinte par l'app, a été relue à 100 % puis à 22 %, sans s'allumer ; l'allumage suivant l'a rallumée à 22 %. La cause n'est pas établie : peut-être la molette, qui changerait alors le niveau retenu sans allumer la lampe. À vérifier.

### Relecture toutes les 2 s

Du 02/10/2026 13:03 au 03/10/2026 13:26 (24 h 20), firmware `7ab7339`, relecture passée de 5 à 2 s par `mesh releve 2`. Djoko s'est servi des lampes normalement et trouve le délai de 2 s confortable.

| mesure | 2 s | 5 s (T10) |
|---|---|---|
| relectures | 43 816 | 17 270 |
| répondues, lampe 1 | 98,0 % | 97,9 % |
| répondues, lampe 2 | 98,7 % | 98,3 % |
| salves d'ordres de Maison | 33, 0 abandon | 41, 0 abandon |
| confirmations au-delà d'1 s | 1 (1 611 ms) | 0 |
| messages émis | 44 022, 0 refus, 0 perdu | 17 408, 0 refus, 0 perdu |
| tas libre (au plus bas) | 186 188 o (179 336 o) | 186 636 o (179 024 o) |

Aucun redémarrage ; Thread attaché, 1 abonnement actif ; pile la plus basse 1 828 o (`lampes`). La séquence Mesh avance d'environ 87 000 numéros par jour. Verdict : 2 s devient la période par défaut (`LAMPES_RELEVE_DEFAUT_MS`). La confirmation à 1,6 s n'a pas été capturée : T2 en avait eu une semblable à 5 s, pendant un glissé du curseur.

