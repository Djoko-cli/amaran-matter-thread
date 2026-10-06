# Pont amaran : la fiche des lampes dans Maison (plan 3b-3)

Date : 06/10/2026. Statut : design validé section par section avec Djoko.
Prolonge la spec du pont (`2026-09-28-pont-amaran-design.md`), celle des N
lampes (`2026-10-03-pont-amaran-n-lampes-design.md`) et celle de l'app
compagnon (`2026-10-05-pont-amaran-app-compagnon-design.md`), qui restent la
référence pour tout ce que ce document ne change pas.

Dans Maison, la fiche du pont est complète (Fabricant `Djoko-CLI`, N° de série
`AMARAN-<MAC du pont>`, Modèle `Pont amaran`, Programme interne
`0.1.0-<commit>`), comme celle du pont Halo. Celle de chaque lampe dit
« Unknown » partout : le pont ne remplit, dans le cluster Bridged Device Basic
Information de la lampe, que son nom (`NodeLabel`) et sa MAC (`UniqueID`). Ce
plan remplit la fiche des lampes et dit au contrôleur de la relire.

## 1. But et périmètre

Dans le périmètre :
- la fiche de chaque lampe dans Maison : fabricant, modèle, n° de série,
  programme interne (2) ;
- la version du logiciel des lampes, de la base d'amaran Desktop jusqu'au
  pont : app, `outils/cles_amaran.py`, commande `mesh lampe`, liste en NVS
  (format 3), protocole JSON (3) ;
- `ConfigurationVersion` du nœud, pour que Maison relise ce qui a changé (4) ;
- la comparaison base / trousseau / pont et la carte de chaque lampe dans
  l'app (5) ;
- les tests et le banc (6, 7).

Hors périmètre :
- lire la version sur la lampe elle-même : il faudrait sa clé d'appareil, que
  le pont n'a pas (les clés d'appareil restent dans la base et le trousseau) ;
- le retour d'une lampe remise par `afficher` comme nouvel accessoire
  (décision 7 de la spec N lampes) : le banc regarde si `ConfigurationVersion`
  y change quelque chose, sans le promettre (8) ;
- un `VendorID` ou un `ProductID` de lampe : nous n'en avons pas de réels.

## 2. La fiche d'une lampe

Décisions de Djoko (06/10/2026). Attributs du cluster Bridged Device Basic
Information de l'endpoint de la lampe, créés à chaque exposition comme
`NodeLabel` aujourd'hui (sans `NONVOLATILE` : la liste fait foi à chaque
démarrage) :

| Maison | Attribut | Valeur |
|---|---|---|
| Fabricant | `VendorName` | `Aputure` |
| Modèle | `ProductName` | le nom du catalogue (`amaran COB 60d`) ; modèle non catalogué : `amaran <code>` |
| N° de série | `SerialNumber` | `AMARAN-<MAC de la lampe>`, 12 hexa majuscules sans séparateur, comme le pont |
| Programme interne | `SoftwareVersionString` et `SoftwareVersion` | `<logiciel> (BLE <ble>)`, par exemple `1.4 (BLE 1.69)` ; `<logiciel>` seul si le module Bluetooth n'est pas connu ; et la forme numérique du logiciel, `x × 1000 + y` (1004 pour 1.4), comme le nœud a les deux ; absents si aucune version n'est connue. **Maison ne l'affiche pas** (banc du prototype, 3 essais, voir 7) : il reste pour les autres contrôleurs et pour l'app |

`NodeLabel` et `UniqueID` ne changent pas. Le fabricant est le fabricant réel ;
la marque est dans le modèle. Chaque lampe porte aussi le `ConfigurationVersion`
de son cluster (Matter 1.4), égal à celui du nœud et mis à jour avec lui (4).

## 3. La version, de la base jusqu'au pont

**La base d'amaran Desktop** (table `fixtures`) donne, par lampe :
`control_software_version` (le logiciel de commande, `1.4` sur les deux COB 60d
de Djoko), `ble_software_version` (le module Bluetooth, `1.69`), et des
versions matérielles que ce plan n'utilise pas. Une base plus ancienne peut ne
pas avoir ces colonnes : les versions sont alors inconnues, sans gravité (comme
`code` et `composition_data` aujourd'hui).

**Forme d'une version** : 1 à 3 chiffres, un point, 1 à 3 chiffres
(`^[0-9]{1,3}\.[0-9]{1,3}$`). Toute autre valeur de la base est traitée comme
inconnue (jamais envoyée au pont).

**La commande** gagne un jeton facultatif, avant le nom :

```
mesh lampe <n> <adresse> <mac> <code> [v<logiciel>[/<ble>]] "<nom>"
```

Exemple : `mesh lampe 2 0x0004 02:00:00:00:00:02 40065 v1.4/1.69 "Lampe fenêtre"`.
- Le mot qui suit le code est le jeton s'il a sa forme (`v`, une version, puis
  facultativement `/` et une version), s'il ne contient pas d'espace et s'il
  est suivi d'au moins un mot. Sinon, c'est le début du nom, sans erreur : un
  nom comme « v2 », « v2 bureau » ou, entre guillemets, « v1.4 bureau » reste
  un nom. L'app et le script mettent toujours le nom entre guillemets. Une
  version mal tapée à la main finit dans le nom, et la réponse le montre.
  (Précisé au prototype : la première règle refusait un nom qui commence par
  `v` suivi d'un chiffre, et le refus tombait après l'envoi des clés.)
- Sans jeton, les versions de la lampe sont inconnues.
- La réponse `ok lampe ...` cite la version reçue (`logiciel <version>` ou
  `logiciel inconnu`).
- La règle de lecture (jeton et versions) vit dans le composant `liste`, en C
  pur, testé sur le Mac.
- Une ligne de plus de 127 octets est refusée par la console : l'app et le
  script la refusent avant d'envoyer les clés.

**Un ancien firmware** prendrait le jeton pour le début du nom. Le pont qui
prend la version le dit : la capacité `logiciel` dans `hello` `identite`
(pour l'app), et la fin `[v<x.y>[/<x.y>]]` de sa réponse à `mesh lampes <N>`
(pour le script ; la même constante, `LISTE_JETON_AIDE`, des deux côtés, liée
par un test). Sans elle, l'app et le script chargent sans versions et le
disent (« mettre à jour son firmware »).

**En NVS**, la clé `lampes` reste au format 2 : un firmware d'avant ce plan la
relit toujours, et un retour en arrière ne fait perdre que les versions, jamais
les lampes ni leur place dans Maison. (Précisé au prototype : un format 3 de
`lampes` rendait le retour en arrière destructeur.) Les versions vont sous une
clé à part, `logiciels` : un en-tête, puis, pour chaque lampe dont le logiciel
est connu, sa MAC et ses deux versions (22 octets). Elles sont rangées par
MAC : une liste rechargée par un ancien firmware ne prête jamais à une lampe
les versions d'une autre. Une entrée mal formée, ou d'une MAC absente, est
ignorée. La migration du format 1 reste ce qu'elle est (versions inconnues).
En mémoire, chaque lampe porte ses deux versions (`logiciel`, `ble`). Le
firmware `ecoute`, qui partage les composants, suit.

**Le protocole JSON** (`docs/PROTOCOLE-JSON.md`) : le bloc `config` `lampe`
gagne `"logiciel"` et `"ble"` (chaînes, ou `null` si inconnues), `caps` gagne
`logiciel`. Ajout compatible : la révision reste 1.

**`outils/cles_amaran.py`** lit les deux colonnes (en texte seulement : un
nombre perdrait ses zéros) et envoie le jeton quand la version est connue et
bien formée, et que le pont le prend. Un `ble` connu sans logiciel n'est
jamais envoyé (le pont refuse un `ble` seul) : ce n'est pas un écart dans
l'app non plus.

## 4. `ConfigurationVersion`

Faits (06/10/2026, esp-matter `c5b9ea8`, lus en préparant le prototype) :
- l'attribut est servi par le cluster Basic Information « code-driven » de la
  pile, qui le lit à chaque fois dans le `ConfigurationManager` ; sur ESP32,
  celui-ci rend la constante `CHIP_DEVICE_CONFIG_DEVICE_CONFIGURATION_VERSION`
  (1) et ne sait pas la ranger (`StoreConfigurationVersion` : non pris en
  charge). La macro n'a qu'un usage, à l'exécution ;
- esp-matter garde l'instance du cluster dans un espace anonyme : pas d'appel
  public à `IncreaseConfigurationVersion` ;
- Maison suit l'apparition et le retrait des lampes par la `PartsList` de
  l'agrégateur, à laquelle elle est abonnée ; mais les attributs fixes d'une
  lampe (fabricant, modèle, série, version), elle les lit une fois et les
  garde ;
- les attributs de la fiche des lampes (cluster Bridged Device Basic
  Information) sont servis par le stockage d'esp-matter, qui copie leurs
  valeurs.

Donc :
- `firmware/main/CHIPProjectConfig.h` définit la macro comme l'appel
  `pont_version_configuration()` : le pont tient la version lui-même, en NVS
  (clé `cfgver` de l'espace `amaran`), sans toucher à ESP-IDF ni à esp-matter ;
- pour l'annoncer, le pont fait changer la DataVersion du cluster avec la
  valeur (Matter 7.10.3 : jamais une valeur nouvelle sous une DataVersion
  ancienne, sinon un contrôleur qui se réabonne avec un `DataVersionFilter`
  saute le cluster) : `NotifyAttributeChanged` du cluster enregistré, protégé,
  atteint par un pointeur de membre pris dans une classe dérivée. Si le cluster
  manquait : le simple signalement, journalisé.

Le pont incrémente `ConfigurationVersion` (valeur et annonce sous le verrou de
la pile ; une à la fois, sous le verrou des expositions) :
- **au démarrage**, une fois les lampes exposées, si l'empreinte de ce qui est
  exposé diffère de celle gardée en NVS (clé `fiche`) ; puis il range la
  nouvelle empreinte. L'empreinte couvre, pour chaque lampe exposée, dans
  l'ordre des numéros d'endpoint : le numéro, le type d'appareil, le nom et la
  fiche ; et une constante de format, changée si ce qu'elle couvre change. Elle
  vit dans le composant `liste` (testée sur le Mac). Le premier démarrage du
  firmware de ce plan l'incrémente donc une fois (de 1 à 2) : c'est ce qui doit
  faire relire les fiches de lampes déjà appairées ;
- **en marche**, quand une lampe entre dans Maison (première réponse,
  `afficher`) ou en sort (`masquer`), comme le prévoit Matter 1.4 pour un
  changement d'endpoints ; l'empreinte en NVS est mise à jour du même geste.

La version est rangée avant l'empreinte : une NVS qui refuserait la seconde
ferait monter la version à chaque démarrage, jamais reculer ; l'échec est
journalisé et compté. Une NVS illisible au démarrage (autre chose qu'une clé
absente) bloque tout incrément jusqu'au démarrage suivant : la version rangée
est peut-être plus haute que celle lue, et `ConfigurationVersion` ne doit
jamais reculer. La console `matter` montre la version.

## 5. L'app

- **Lecture de la base** (`BaseAmaranDesktop`) : les deux colonnes, si elles
  existent ; une valeur mal formée devient inconnue.
- **`LampeReseau`** gagne `logiciel` et `ble` (facultatifs). La copie du
  trousseau et la sauvegarde chiffrée les gardent ; une copie ou une
  sauvegarde plus ancienne se relit (versions inconnues).
- **« Charger le pont »** (`ReseauMesh`) envoie le jeton si le pont a la
  capacité `logiciel` (sinon il charge sans versions et le dit), et la
  vérification après redémarrage (`VerificationChargement`) compare aussi les
  versions.
- **Comparaison base / copie / pont** (`ComparaisonCles`) : les versions font
  partie de la lampe. Après la mise à jour, la carte Clés montre que le pont
  diffère de la base et propose de le charger ; de même après une mise à jour
  des lampes par Sidus, une fois la base relue. Une version inconnue d'un côté
  et connue de l'autre est un écart (le pont n'a pas tout).
- **Carte de la lampe** (tableau de bord, Commandes) : une ligne « Logiciel »,
  `1.4 (BLE 1.69)`, ou « inconnu (recharger le pont) », ou, si le pont ne
  prend pas la version, « inconnu (firmware du pont à mettre à jour) ». Sans
  la capacité, l'absence de version côté pont n'est pas un écart à résoudre
  par « Charger le pont » (ce serait une boucle) : la carte Clés dit de mettre
  à jour le firmware.
- **Mode démo** : des versions inventées (`1.4`, `1.69` sont des versions, pas
  des valeurs du réseau de Djoko ; elles peuvent servir d'exemple).

## 6. Tests sur le Mac

- `tests/hote` : le jeton (forme correcte, sans `/`, abîmé, absent) et la règle
  des mots de `mesh lampe` (jeton suivi d'un nom ; « v2 », « v2 bureau »,
  « v1.4 » seul et un nom entre guillemets restent des noms) ; la clé
  `lampes` au format 2 sans versions ; la clé `logiciels` aller-retour, relue
  par MAC sur une liste dans un autre ordre, entrée mal formée ou MAC absente
  ignorées ; la migration du format 1 (versions inconnues) ; la fiche
  (modèle catalogué ou non, série, programme interne) ; l'empreinte (stable,
  change avec chaque champ, indépendante de l'ordre de chargement).
- `outils/test_cles_amaran.py` : le jeton envoyé si le pont le prend ; rien
  sinon, avec l'avertissement ; noms entre guillemets ; ligne trop longue
  refusée avant tout envoi ; version en nombre ignorée ; la constante
  `LISTE_JETON_AIDE` de `liste.h` égale à celle du script.
- App : lecture de la base avec et sans les colonnes, valeurs mal formées ;
  trousseau et sauvegarde relus sans les champs ; lignes de chargement, avec
  et sans la capacité ; écarts de version dans la comparaison et la
  vérification ; carte de lampe ; simulateur fidèle à la règle des mots.

## 7. Banc, avec Djoko

0. Sauvegarde de la flash entière avant de flasher (`esptool.py read_flash`,
   hors du dépôt : elle contient des clés).
1. Flash sans effacement. Au premier démarrage, le journal dit
   `ConfigurationVersion 2` ; au second, « inchangée ». `matter` montre la
   version.
2. Dans Maison, sans rien réappairer : la fiche du pont inchangée ; la fiche
   des deux lampes : `Aputure`, `AMARAN-<MAC>`, `amaran COB 60d`, et pas
   encore de programme interne (aucune version en NVS).
3. Depuis l'app : la carte Clés montre l'écart de version ; « Charger le
   pont » ; après le redémarrage, plus d'écart ; `ConfigurationVersion` monte ;
   dans Maison, `1.4 (BLE 1.69)` sur les deux lampes.
4. Pièces, scènes et automatisations des lampes intactes dans Maison.
5. `mesh lampe 2 masquer` puis `afficher` (lampe 2, que Djoko accepte de
   reconfigurer) : la version monte à chaque geste ; noter si la lampe revient
   comme nouvel accessoire ou garde sa pièce.
6. Sur secteur : démarrage normal (voyant blanc), Maison réactive ; `taches` :
   tas au plus bas comparé au banc B du plan 3b-2 (106 Ko).

Les valeurs réelles (MAC, n° de série des lampes) ne vont jamais dans le dépôt
ni dans `docs/BANC.md`.

**Banc du prototype (06/10/2026, avec Djoko)** : flash sans effacement après
sauvegarde de la flash ; `ConfigurationVersion` 2 au premier démarrage, puis
inchangée ; dans Maison, sans rien réappairer, la fiche des deux lampes est
remplie (`Aputure`, `AMARAN-<MAC>`, `amaran COB 60d`) ; pièces, scènes et
automatisations intactes. La carte Clés de l'app montre l'écart (copie sans
versions), « Copier depuis amaran Desktop » puis « Charger le pont » : plus
d'écart, `1.4 (BLE 1.69)` sur les deux cartes de lampe, version 3. Mais
Maison n'affiche pas de programme interne pour les lampes, ni avec
`SoftwareVersionString` seul, ni avec `SoftwareVersion` en plus (version 4), ni
avec le `ConfigurationVersion` de chaque lampe (version 5), même après avoir
rouvert Maison ; un pont HomeKit (HAP) de Djoko montre bien celui de ses
accessoires. Conclusion : Maison n'affiche pas la version d'un accessoire
Matter ponté. `masquer` (version 6 : la tuile disparaît) puis `afficher`
(version 7) : la lampe revient comme un nouvel accessoire, comme avant
(décision 7) : `ConfigurationVersion` n'y change rien. Sur cette lampe revenue, Maison refusait
ensuite de changer l'icône (« Impossible de modifier ce réglage »), avec ou sans
le `ConfigurationVersion` par lampe ; retirer le pont de Maison puis le
réappairer l'a réglé. Sur secteur : voyant
normal, Maison pilote les lampes. Tas au plus bas 102 Ko juste après un
démarrage (106 Ko au banc B du plan 3b-2, après une heure).

## 8. Risques et questions ouvertes

| Risque | Parade | Où |
|---|---|---|
| Maison ne relit pas les attributs fixes d'une lampe déjà appairée, même avec `ConfigurationVersion` | levé au banc du prototype : elle relit fabricant, modèle et série | banc |
| Maison n'affiche pas le programme interne d'une lampe pontée | constaté au banc du prototype (3 essais) ; la version reste exposée (autres contrôleurs) et visible dans l'app ; le README le dit | — |
| le pointeur de membre vers `NotifyAttributeChanged` dépend de l'enregistrement d'esp-matter (`DefaultServerCluster`) | si le cluster manque, repli journalisé (signalement sans DataVersion) ; à revoir à chaque mise à jour d'esp-matter | banc 1 et 3 |
| un retour à un firmware d'avant ce plan | la clé `lampes` reste au format 2 : seules les versions sont ignorées ; `ConfigurationVersion` revient à 1 (constante de la pile) : Maison voit une valeur plus basse jusqu'au retour de ce firmware, qui reprend sa valeur rangée | — |
| une ancienne app recharge un pont à jour et efface les versions | voulu : la liste chargée fait foi ; la carte Clés de la nouvelle app le montre | — |
