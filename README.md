# amaran COB 60d -> Matter

Piloter des lampes **amaran** (Aputure), aujourd'hui deux **COB 60d** (1re
génération), depuis Apple Maison, Siri et les automatisations, par **Matter sur
Thread**, avec un ESP32-C6, tout en gardant l'app **amaran Desktop** utilisable.
Jusqu'à 16 lampes par pont.

Projets frères :
- [benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter) :
  le socle (voyant, bouton BOOT, console) et les leçons côté Apple ;
- [maillage-thread](https://github.com/Djoko-cli/maillage-thread).

## État

**Le pont marche : les deux lampes sont dans Maison, sur une seule C6.** Le design complet est dans
[docs/superpowers/specs/2026-09-28-pont-amaran-design.md](docs/superpowers/specs/2026-09-28-pont-amaran-design.md).

| Phase | Contenu | État |
|---|---|---|
| P0 | Reconnaissance. Un firmware d'écoute rejoint le réseau des lampes et vérifie : IV Index, réponses captées, ordres, molette, groupe, cohabitation avec amaran Desktop | faite (30/09/2026) : 62 ordres sur 62 confirmés par relecture, toutes les demandes d'état ont reçu leur réponse ; aucun état spontané (ni molette, ni bouton, ni coupure) |
| P1 | Matter sur la même carte, et banc de la radio partagée entre Thread et Bluetooth : une ou deux C6 | faite (30/09/2026) : une seule C6 suffit, avec l'écoute du Mesh à 50 %, l'arrondi au pour cent et la demande d'état doublée ; 96,9 % et 98,3 % des relectures répondues, 47 salves d'ordres de Maison sans échec |
| P2 | Produit : voyant, bouton, console, fiche produit ; bancs, puis endurance 24 h | faite (02/10/2026) : T1 à T10 (T5 partiel, T7 non fait) ; 24 h sans redémarrage, 97,9 % et 98,3 % des relectures répondues, 41 salves d'ordres sans échec ; lampe noire (molette à 0 %) corrigée et vérifiée |
| P3a | N lampes : liste, catalogue de modèles, numéros d'endpoint stables, exposition à la première réponse | faite (05/10/2026) : bancs 1 à 4 ; migration sans perte dans Maison ; 16 lampes tenues (tas au plus bas 103 Ko) ; une lampe masquée puis remise est oubliée par Maison, donc pas de masquage automatique |

Résultats des bancs : [docs/BANC.md](docs/BANC.md). Protocole relevé : [docs/PROTOCOLE.md](docs/PROTOCOLE.md).

## Ce que fait le pont

- Il montre chaque lampe dans Maison comme une lampe à intensité variable, avec
  marche/arrêt et luminosité.
- Il suit l'état réel des lampes, qu'on les règle dans Maison, dans amaran
  Desktop ou à la molette.
- Il laisse amaran Desktop fonctionner en même temps.

## Comment

**Côté lampes.** Les lampes forment un réseau **Bluetooth Mesh**, créé par amaran
Desktop.
- L'ESP32 en devient membre avec **sa propre adresse**, grâce aux clés du
  réseau qu'un script lit dans la base locale de l'app.
- Rien n'est modifié, ni dans les lampes ni dans l'app.
- L'ESP32 parle aux lampes leur vrai langage : un opcode Telink propriétaire,
  `0x26`.
- Il lit leur état au passage : les lampes adressent leurs réponses à amaran
  Desktop, et il les capte.

**Côté Maison.** C'est un pont Matter sur Thread (ESP-IDF + esp-matter) : un
agrégateur, et une lampe « pontée » par lampe.

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

Une fois appairé, le pont entre dans le réseau des lampes. Chaque lampe apparaît dans Maison, sous son nom d'amaran Desktop, à sa première réponse : une lampe déclarée dans amaran Desktop mais absente d'ici n'y apparaît pas.

Carte déjà servie : `erase-flash` fait tirer au pont une nouvelle adresse Mesh au hasard (`0x7F00` à `0x7F7F`). Dans environ 1 cas sur 128 par adresse déjà employée, elle retombe sur une adresse que les lampes connaissent, et elles ignorent alors le pont, sans message d'erreur. Si toutes les lampes restent muettes (`lampes` : « lue jamais ») sans autre alerte de la console, taper `mesh adresse suivante` : le pont prend l'adresse voisine, repart de zéro et redémarre.

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
- `lampes` : une ligne par lampe (sa place dans Maison : `EP<n>`, « jamais vue », « masquee » ou « hors de Maison » ; état lu, joignabilité, relectures répondues), puis les ordres ;
- `lampe <n>` : le détail d'une lampe (adresse, MAC, modèle et capacités, consigne, relectures sur 10 min) ;
- `lampe <n> on|off|niveau <0-1000>|releve` : le niveau est arrondi au pour cent (la lampe ne garde pas mieux) ;
- `mesh lampe <n> masquer|afficher` : retirer la lampe de Maison, qui l'oublie alors (voir « À savoir »), ou l'y remettre, avec le même numéro (`afficher` y fait aussi entrer une lampe jamais vue) ;
- `mesh` : réseau, empreintes des clés, compteurs ; `mesh releve <s>`, `mesh balayage`, `mesh ecoute on|off`, `mesh autotest`, etc. ;
- `mesh lampes <N>`, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` : la liste des lampes, tout ou rien (c'est ce qu'envoie `outils/cles_amaran.py`) ;
- `matter` : mise en service, Thread, abonnements, codes, identité ;
- `led [test|stop]`, `cause`, `taches`, `decommission`, `redemarre`.

## À savoir

- Une lampe éteinte depuis Maison, ou depuis amaran Desktop, ignore sa molette et le bouton de sa molette. Pour la rallumer à la main : couper puis remettre son alimentation. Son état au retour varie : allumée vers 40 %, allumée à son niveau retenu, ou éteinte.
- Une lampe dont la molette est à 0 % reste en marche, mais n'éclaire pas : Maison la montre éteinte, à son dernier niveau. La toucher dans Maison la rallume à ce niveau (à 40 % seulement sur une installation neuve, quand Maison n'a encore aucun niveau pour elle). Le pont ne l'éteint jamais de lui-même : sa molette reste vive. Mais juste après avoir tourné la molette à 0, Maison la montre encore allumée quelques secondes : l'éteindre à ce moment-là l'éteint « par l'app », et sa molette ne répond plus.
- Maison suit la molette et amaran Desktop en 2 s environ : les lampes ne signalent rien d'elles-mêmes, et le pont les relit toutes les 2 s (`mesh releve <s>` pour changer).
- amaran Desktop, lui, ne suit pas les ordres venus de Maison.
- Maison ne montre une lampe « Pas de réponse », puis son retour, qu'après avoir touché sa tuile. Le pont publie pourtant chaque changement.
- Pour la luminosité, taper sur la jauge de Maison est plus fluide que la faire glisser : un glissé envoie une valeur toutes les 150 à 300 ms.
- Une lampe n'entre dans Maison qu'à sa première réponse, puis y reste : absente, elle y est « Pas de réponse », et garde sa tuile, sa pièce et ses scènes. Pour la retirer de Maison : `mesh lampe <n> masquer`. Maison oublie alors la lampe : remise (`afficher`, avec le même numéro), elle revient comme un nouvel accessoire, sous son nom d'amaran Desktop, sans le nom donné dans Maison, ni groupe, ni scènes, ni automatisations (banc du 05/10/2026).
- Retirer une lampe dans amaran Desktop, puis recharger la liste (`outils/cles_amaran.py`), lui fait perdre son numéro : remise plus tard, elle revient comme une lampe nouvelle.
- `mesh oublie` efface les clés, mais garde la liste des lampes : leurs tuiles restent, en « Pas de réponse », jusqu'au rechargement des clés. `mesh lampes 0` vide la liste.
- Un modèle que le pont ne connaît pas encore est piloté en marche et intensité seulement. `outils/cles_amaran.py` signale une lampe qui déclare la température de couleur ou la couleur : modèle à cataloguer.
- Si une lampe joignable manque plus de 5 % de ses relectures sur 10 minutes, la console le dit (`!! lampe <n> : relectures manquees, <p> % repondues sur 10 min`) : allonger la période (`mesh releve`). Le premier verdict vient au plus tôt 10 minutes après le démarrage, ou 5 minutes après une coupure du Mesh ou le retour d'une lampe.
- Bouton BOOT : juste après un appui annulé (tenu de 2 à 8 s, donc sans effet), relâcher net ; un effleurement redémarre le pont, sans conséquence (les clés et l'appairage restent).

## Clés du réseau

Qui détient les clés du réseau Bluetooth Mesh contrôle les lampes.
- Elles ne vont **jamais** dans ce dépôt.
- Un script les lit dans la base d'amaran Desktop et les charge dans l'ESP32
  par l'USB.

## amaran Desktop sur macOS 27

amaran Desktop 1.1.03 plante au démarrage sur macOS 27 : matplotlib, qu'il
embarque, ne sait plus lire la liste des polices du système. Le script
[outils/polices_amaran_desktop.py](outils/polices_amaran_desktop.py) lui pose
le cache de polices qu'il cherche, sans toucher à l'application :

```bash
python3 outils/polices_amaran_desktop.py
```

Pour annuler, supprimer le fichier que le script indique.

## Crédits

Le protocole des lampes a été décodé par deux projets libres, sous licence
MIT :
- [amaran-bridge](https://github.com/kevinschaich/amaran-bridge), de Kevin
  Schaich. Ce pont en reprend du code : l'encodage des trames Telink
  (`components/telink/telink.c`) et la séquence d'adhésion au réseau
  (`components/mesh/mesh_amaran.c`). Chacun de ces fichiers garde, en tête, la
  mention de licence MIT de l'auteur ;
- [amaran-BLE-control](https://github.com/wesbos/amaran-BLE-control), de Wes
  Bos. Ce pont lui doit la connaissance du protocole (l'opcode `0x26`), mais
  n'en reprend aucun code.

Le script de réparation d'amaran Desktop
([outils/polices_amaran_desktop.py](outils/polices_amaran_desktop.py)) reprend
de [matplotlib](https://matplotlib.org) 3.10.8 (`font_manager.py`) la fonction
`ttfFontProperty` et la table `_weight_regexes`, sous la
[licence de matplotlib](https://matplotlib.org/stable/project/license.html)
(Copyright (c) 2012- Matplotlib Development Team). Sa mention est en tête du
script, et le texte de la licence dans
[outils/LICENCE-matplotlib.txt](outils/LICENCE-matplotlib.txt).

Le voyant et le bouton BOOT reprennent la logique du pont Halo
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
du même auteur) : `components/socle`, avec ses tests.

Projet personnel, sans lien avec Aputure. Il n'ouvre ni ne modifie les lampes.
