# amaran COB 60d -> Matter

Piloter deux lampes **amaran COB 60d** (Aputure, 1re génération) depuis Apple
Maison, Siri et les automatisations, par **Matter sur Thread**, avec un
ESP32-C6, tout en gardant l'app **amaran Desktop** utilisable.

Projets frères :
- [benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter) :
  le socle (voyant, bouton BOOT, console) et les leçons côté Apple ;
- [maillage-thread](https://github.com/Djoko-cli/maillage-thread).

## État

**Reconnaissance faite : l'ESP32 entre dans le réseau des lampes, les pilote
et lit leur état.** Le design complet est dans
[docs/superpowers/specs/2026-09-28-pont-amaran-design.md](docs/superpowers/specs/2026-09-28-pont-amaran-design.md).

| Phase | Contenu | État |
|---|---|---|
| P0 | Reconnaissance. Un firmware d'écoute rejoint le réseau des lampes et vérifie : IV Index, réponses captées, ordres, molette, groupe, cohabitation avec amaran Desktop | faite (30/09/2026) : 62 ordres sur 62 confirmés par relecture, toutes les demandes d'état ont reçu leur réponse ; aucun état spontané (ni molette, ni bouton, ni coupure) |
| P1 | Matter sur la même carte, et banc de la radio partagée entre Thread et Bluetooth : une ou deux C6 | faite (30/09/2026) : une seule C6 suffit, avec l'écoute du Mesh à 50 % ; 96,9 % et 98,3 % des relectures répondues, 47 ordres de Maison sans échec |
| P2 | Produit : voyant, bouton, console, fiche produit ; bancs, puis endurance 24 h | à faire |

Résultats des bancs : [docs/BANC.md](docs/BANC.md). Protocole relevé : [docs/PROTOCOLE.md](docs/PROTOCOLE.md).

## Ce que le pont fera

- Montrer chaque 60d dans Maison comme une lampe à intensité variable, avec
  marche/arrêt et luminosité.
- Suivre l'état réel des lampes, qu'on les règle dans Maison, dans amaran
  Desktop ou à la molette.
- Laisser amaran Desktop fonctionner en même temps.

## Comment

**Côté lampes.** Les 60d forment un réseau **Bluetooth Mesh**, créé par amaran
Desktop.
- L'ESP32 en devient membre avec **sa propre adresse**, grâce aux clés du
  réseau qu'un script lit dans la base locale de l'app.
- Rien n'est modifié, ni dans les lampes ni dans l'app.
- L'ESP32 parle aux lampes leur vrai langage : un opcode Telink propriétaire,
  `0x26`.
- Il lit leur état au passage : les lampes adressent leurs réponses à amaran
  Desktop, et il les capte.

**Côté Maison.** C'est un pont Matter sur Thread (ESP-IDF + esp-matter) : un
agrégateur, et une lampe « pontée » par 60d.

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

Projet personnel, sans lien avec Aputure. Il n'ouvre ni ne modifie les lampes.
