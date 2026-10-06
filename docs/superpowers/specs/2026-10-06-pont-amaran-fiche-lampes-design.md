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
| Programme interne | `SoftwareVersionString` | `<commande> (BLE <ble>)`, par exemple `1.4 (BLE 1.69)` ; `<commande>` seul si le module Bluetooth n'est pas connu ; absent si aucune version n'est connue (Maison n'affiche alors pas la ligne) |

`NodeLabel` et `UniqueID` ne changent pas. Le fabricant est le fabricant réel ;
la marque est dans le modèle.

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
mesh lampe <n> <adresse> <mac> <code> [v<commande>[/<ble>]] <nom>
```

Exemple : `mesh lampe 2 0x0004 02:00:00:00:00:02 40065 v1.4/1.69 "Lampe fenêtre"`.
- Le pont reconnaît le jeton à sa forme : `v`, une version, puis
  facultativement `/` et une version.
- Un mot qui commence par `v` suivi d'un chiffre mais n'a pas cette forme est
  refusé (`erreur : version <...> : attendu v<x.y>[/<x.y>]`), pour qu'une faute
  de frappe ne finisse pas dans le nom.
- Sans jeton, les versions de la lampe sont inconnues : une ancienne app ou un
  ancien script chargent toujours le pont.
- La réponse `ok lampe ...` cite la version reçue.
- La règle de lecture (jeton et versions) vit dans le composant `liste`, en C
  pur, testé sur le Mac.

**La liste en NVS** passe au format 3 (`LISTE_VERSION 3`) : deux champs par
lampe, `commande` et `ble`, chaînes de 8 octets NUL compris (vides : inconnue).
16 lampes : 256 octets de plus. `liste_depuis_nvs` relit le format 2 (versions
vides) ; la liste est réécrite au format 3 au prochain chargement. La
migration du format 1 reste ce qu'elle est (versions vides). Le firmware
`ecoute`, qui partage les composants, suit.

**Le protocole JSON** (`docs/PROTOCOLE-JSON.md`) : le bloc `config` `lampe`
gagne `"logiciel"` et `"ble"` (chaînes, ou `null` si inconnues). Ajout
compatible : la révision reste 1.

**`outils/cles_amaran.py`** lit les deux colonnes et envoie le jeton quand la
version est connue et bien formée.

## 4. `ConfigurationVersion`

Faits (06/10/2026, esp-matter `c5b9ea8`) : l'attribut existe sur le cluster
Basic Information du nœud (créé à 0 par esp-matter) ; la pile sait
l'incrémenter (`chip::app::Clusters::BasicInformation::GetClusterInstance()->IncreaseConfigurationVersion()`,
valeur gardée par le `ConfigurationManager`, donc en NVS) ; rien ne l'appelle
aujourd'hui, ni esp-matter ni le pont. Maison suit l'apparition et le retrait
des lampes par la `PartsList` de l'agrégateur, à laquelle elle est abonnée ;
mais les attributs fixes d'une lampe (fabricant, modèle, série, version), elle
les lit une fois et les garde.

Le pont incrémente `ConfigurationVersion`, sous le verrou de la pile Matter :
- **au démarrage**, une fois les lampes exposées, si l'empreinte de ce qui est
  exposé diffère de celle gardée en NVS (clé `fiche` de l'espace `amaran`) ;
  puis il range la nouvelle empreinte. L'empreinte couvre, pour chaque lampe
  exposée, dans l'ordre des numéros d'endpoint : le numéro, `NodeLabel`,
  `VendorName`, `ProductName`, `SerialNumber`, `SoftwareVersionString` ; et
  une constante de format, changée si la liste des attributs change. Le
  premier démarrage du firmware de ce plan l'incrémente donc une fois : c'est
  ce qui doit faire relire les fiches de lampes déjà appairées ;
- **en marche**, quand une lampe apparaît (première réponse, `afficher`) ou
  disparaît (`masquer`), comme le prévoit Matter 1.4 pour un changement
  d'endpoints ; l'empreinte en NVS est mise à jour du même geste.

Un échec d'écriture est journalisé et compté, jamais bloquant : au pire,
Maison garde l'ancienne fiche.

## 5. L'app

- **Lecture de la base** (`BaseAmaranDesktop`) : les deux colonnes, si elles
  existent ; une valeur mal formée devient inconnue.
- **`LampeReseau`** gagne `logiciel` et `ble` (facultatifs). La copie du
  trousseau et la sauvegarde chiffrée les gardent ; une copie ou une
  sauvegarde plus ancienne se relit (versions inconnues).
- **« Charger le pont »** (`ReseauMesh`) envoie le jeton, et la vérification
  après redémarrage (`VerificationChargement`) compare aussi les versions.
- **Comparaison base / copie / pont** (`ComparaisonCles`) : les versions font
  partie de la lampe. Après la mise à jour, la carte Clés montre que le pont
  diffère de la base et propose de le charger ; de même après une mise à jour
  des lampes par Sidus, une fois la base relue. Une version inconnue d'un côté
  et connue de l'autre est un écart (le pont n'a pas tout).
- **Carte de la lampe** (tableau de bord, Commandes) : une ligne « Logiciel »,
  `1.4 (BLE 1.69)`, ou « inconnu (recharger le pont) ».
- **Mode démo** : des versions inventées (`1.4`, `1.69` sont des versions, pas
  des valeurs du réseau de Djoko ; elles peuvent servir d'exemple).

## 6. Tests sur le Mac

- `tests/hote` : le jeton (forme correcte, sans `/`, abîmé, absent, nom qui
  commence par `v` sans chiffre) ; le format 3 aller-retour ; la relecture du
  format 2 et du format 1 ; la forme de `SoftwareVersionString` ; l'empreinte
  (stable, change avec chaque champ, indépendante de l'ordre de chargement
  pour un même jeu d'endpoints).
- `outils/test_cles_amaran.py` : le jeton envoyé, et pas d'envoi d'une version
  mal formée.
- App : lecture de la base avec et sans les colonnes, valeurs mal formées ;
  trousseau et sauvegarde relus sans les champs ; lignes de chargement ;
  écarts de version dans la comparaison et la vérification ; carte de lampe.

## 7. Banc, avec Djoko

1. Flash sans effacement. Au premier démarrage, le journal dit
   `ConfigurationVersion` incrémentée ; au second, non.
2. Dans Maison, sans rien réappairer : la fiche du pont inchangée ; la fiche
   des deux lampes : `Aputure`, `AMARAN-<MAC>`, `amaran COB 60d`, et pas
   encore de programme interne (la liste en NVS est au format 2).
3. Depuis l'app : la carte Clés montre l'écart de version ; « Charger le
   pont » ; après le redémarrage, plus d'écart ; dans Maison, `1.4 (BLE 1.69)`
   sur les deux lampes.
4. Pièces, scènes et automatisations des lampes intactes dans Maison.
5. `mesh lampe 2 masquer` puis `afficher` (lampe 2, que Djoko accepte de
   reconfigurer) : noter si la lampe revient comme nouvel accessoire ou garde
   sa pièce.
6. Sur secteur : démarrage normal (voyant blanc), Maison réactive.

Les valeurs réelles (MAC, n° de série des lampes) ne vont jamais dans le dépôt
ni dans `docs/BANC.md`.

## 8. Risques et questions ouvertes

| Risque | Parade | Où |
|---|---|---|
| Maison ne relit pas les attributs fixes d'une lampe déjà appairée, même avec `ConfigurationVersion` | banc 2 ; si la fiche reste « Unknown » : essayer aussi le `ConfigurationVersion` du cluster Bridged Device Basic Information de chaque lampe (attribut facultatif, créé par esp-matter sur demande) ; en dernier recours, documenter qu'il faut retirer et remettre le pont | prototype, puis banc |
| `GetClusterInstance()` nul si le cluster Basic Information n'est pas géré par l'intégration du code généré dans cette version | le vérifier au prototype ; repli : écrire l'attribut par l'API d'esp-matter et notifier | prototype |
| le jeton `v...` pris pour un nom (« v2 » comme nom de lampe) | seul un `v` suivi d'un chiffre est jugé ; « v2 » sans point est refusé, à renommer dans amaran Desktop | tests |
| une ancienne app recharge un pont à jour et efface les versions | voulu : la liste chargée fait foi ; la carte Clés de la nouvelle app le montre | — |
