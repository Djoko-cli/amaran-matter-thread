# Pont amaran : l'app compagnon (plan 3b)

Date : 05/10/2026. Statut : design validé section par section avec Djoko.
Prolonge la spec du pont (`2026-09-28-pont-amaran-design.md`) et celle des
N lampes (`2026-10-03-pont-amaran-n-lampes-design.md`), qui restent la
référence pour tout ce que ce document ne change pas.

Amaran Compagnon est une app macOS qui supervise et pilote le pont, et qui
gère les clés du réseau Bluetooth Mesh des lampes à la place de
`outils/cles_amaran.py`. C'est une copie adaptée de Halo Compagnon, l'app du
pont BenQ Halo de Djoko (`~/Documents/Dev/esp32/benq/apps/macos`), dont elle
reprend le protocole (`~/Documents/Dev/esp32/benq/docs/PROTOCOLE-JSON.md`),
la structure et le style.

## 1. But et périmètre

Dans le périmètre :
- côté pont : un mode JSON sur la console USB (3b-1), puis un canal UDP
  authentifié sur Thread (3b-2) ;
- côté Mac : l'app, avec la lecture des clés d'amaran Desktop, leur copie dans
  le trousseau, une sauvegarde chiffrée, le chargement du pont, un tableau de
  bord à N lampes, les commandes et la console (3b-1), puis l'accès par
  Thread, les graphiques et les trames (3b-2) ;
- les tests sur le Mac et les bancs avec Djoko.

Hors périmètre :
- une app iOS ;
- la mise à jour du firmware par l'app ;
- tout réglage des lampes autre que marche, arrêt et niveau ;
- le provisionnement d'une lampe réinitialisée (essai à part, puis plan 3c) ;
- les lampes fictives de banc, qui restent dans `outils/cles_amaran.py`.

## 2. Décisions de Djoko

Le 03/10/2026, au brainstorming du plan 3 :
1. **amaran Desktop reste le propriétaire du réseau** (« A puis C ») : l'app le
   lit sans jamais y écrire ; un secours autonome viendra au plan 3c.
2. **Copie adaptée de Halo Compagnon**, avec ses quatre écrans (tableau de
   bord, commandes et console, graphiques, trames), par l'USB et par Thread.
3. **Les clés du Mesh ne sont chargées dans le pont que par l'USB.** L'app
   compare les empreintes de la base, de sa copie et du pont.

Le 05/10/2026, au brainstorming du plan 3b :
4. **Copie des clés : trousseau local et sauvegarde chiffrée.** Le compte
   développeur Apple de Djoko est gratuit : un trousseau iCloud demanderait un
   profil de provisionnement qui expire. L'app garde donc sa copie dans le
   trousseau local du Mac, comme Halo, et exporte sur geste une sauvegarde
   chiffrée par phrase de passe vers un dossier choisi (iCloud Drive
   conseillé), qui survit à la perte du Mac.
5. **Une spec, deux plans** : 3b-1 par l'USB, puis 3b-2 par Thread.
6. **L'app reste sandboxée.** Pour lire la base d'amaran Desktop, Djoko
   désigne une fois son dossier ; l'app en garde un signet.
7. **« Retirer de Maison / remettre » reste dans l'app, par l'USB et par
   Thread**, avec une confirmation qui dit ce que Maison va oublier (banc 2 du
   plan 3a : une lampe masquée puis remise revient comme un nouvel accessoire).
8. **Le firmware reprend les modules purs de Halo** (écriture JSON, sessions,
   enveloppe H1), avec une fine couche pour ESP-IDF : même protocole v1.
9. **Icône : « M2 »**, le A d'Aputure (blanc `#F2F3F4`, lame rouge `#CD3A3B`)
   sur le bleu-noir du logo (`#01101E`), entouré d'un maillage. Format Icon
   Composer, comme l'icône validée de Halo Compagnon (constellation). C'est la
   marque déposée d'Aputure : M2 n'est pas versionnée et reste sur le Mac de
   Djoko (`AppIconM2.icon`, ignorée par git, choisie par `Local.xcconfig`) ; le
   dépôt public porte une icône libre (« A2 » : une constellation qui trace un
   A, sur fond rouge, `AppIcon.icon`), que la compilation prend par défaut.
10. **Français seulement** (règle du projet) : on ne reprend pas la traduction
    anglaise de Halo.

## 3. Faits établis (05/10/2026)

- **Halo Compagnon** (relevé du 05/10) : projet XcodeGen (`project.yml` seul
  versionné), Swift 6 en concurrence stricte, avertissements traités comme des
  erreurs, macOS 15, sandbox et runtime durci. Un framework sans interface
  (`HaloProtocole` : tramage, session, corrélation, H1, UDP) et l'app
  (`HaloCompagnon`). 178 tests Swift Testing. Signature par
  `Signature.xcconfig` (versionné, ad hoc) qui inclut `Local.xcconfig`
  (ignoré par git, équipe de développement).
- **Son trousseau est local** : élément générique, sans groupe d'accès ni
  synchronisation, lié à la signature de l'app. Une app signée ad hoc perd
  l'accès à chaque compilation ; signée par l'équipe, elle le garde.
- **Son mode JSON** : ligne `RS` + JSON compact + `LF`, 1 024 octets au plus,
  entrelacée avec les journaux ; `json 1 [bail]` et `json 0` ; préfixe
  `id=<n>` des commandes ; message `reponse` et ses codes ; « livraison »
  asynchrone des ordres ; le port série s'ouvre sans redémarrer la carte (DTR
  et RTS à 0 en un seul appel).
- **Son canal H1** sur Thread : nom SRP résolu en `.local`, UDP 5480, clé de
  32 octets créée par l'USB, poignée de main SALUT/DEFI, messages signés
  HMAC-SHA256 avec compteur et fenêtre anti-rejeu, liste blanche des
  commandes à distance. L'outil `halo-routes` (démon `launchd`) répare la
  route Thread que macOS perd.
- **Le pont amaran** est en ESP-IDF (console `esp_console`, USB Serial/JTAG),
  pas en Arduino : la couche d'entrée et de sortie est à réécrire.
- **La base d'amaran Desktop** range `code` et `composition_data` en texte
  (vérifié en lecture seule le 05/10).
- **Mémoire du pont** (banc 4 du plan 3a) : tas au plus bas 103 Ko à
  16 lampes ; firmware de 1,7 Mo, 57 % de la partition libres.

## 4. Architecture et découpage

**Deux plans :**
1. **Plan 3b-1, par l'USB.**
   - Pont : le mode JSON.
   - App : les clés (section 5), le tableau de bord, les commandes et la
     console, le mode démo, les réglages Généraux.
2. **Plan 3b-2, par Thread.**
   - Pont : le canal H1 et sa liste blanche.
   - App : le transport réseau, les réglages « Accès réseau Thread », les
     graphiques et les trames.

**Où vit le code :**
- `apps/macos/project.yml` (XcodeGen), `Signature.xcconfig` versionné,
  `Local.xcconfig` ignoré par git (équipe de Djoko) ;
- `apps/macos/AmaranProtocole/` : framework sans interface. Tramage, session
  et corrélation (repris de Halo), H1 et UDP, messages amaran, lecture de la
  base SQLite d'amaran Desktop (SQLite du système), sauvegarde chiffrée ;
- `apps/macos/AmaranCompagnon/` : l'app SwiftUI (vues, modèle `Pont`,
  trousseau, mode démo) ;
- `apps/macos/AmaranProtocoleTests/` et `apps/macos/AmaranCompagnonTests/` ;
- Swift 6 strict, avertissements en erreurs, macOS 15 ou plus, sandbox
  (`device.serial`, `network.client`, fichiers choisis par l'utilisateur) et
  runtime durci.

**Firmware :**
- `components/protocole` (3b-1) : écriture compacte et ordonnée, file des
  messages périodiques, cadence, bail, préfixe `id=`, codes, et les messages du
  pont amaran. Ce sont les modules purs de Halo, en C++, testés sur le Mac. Pas
  `components/json` : c'est le nom du composant cJSON d'ESP-IDF, que le nôtre
  masquerait (vu en préparant le plan 3b-1) ;
- `firmware/main` : la tâche `json`, qui relie ces modules à la console, à la
  liste des lampes, au cœur `lampes`, au Mesh et à Matter ;
- `components/h1` (3b-2) : enveloppe, sessions et anti-rejeu (purs, repris de
  Halo) ; la socket OpenThread et la clé UDP en NVS vivent dans
  `firmware/main`.

Le firmware `ecoute` n'est pas touché.

**Ce qui ne change pas :**
- le pont démarre en console texte, utilisable telle quelle ;
- `outils/cles_amaran.py` reste l'outil de secours en ligne de commande ;
- les clés du Mesh ne sont jamais affichées : seulement leurs empreintes.

## 5. Les clés

**Lire amaran Desktop**, en lecture seule :
- l'app sandboxée garde un signet sur le dossier que Djoko désigne une fois
  (panneau d'ouverture) ; macOS peut aussi demander l'accès aux données
  d'autres apps ;
- les contrôles de `cles_amaran.py` : un seul réseau, deux clés de 16 octets,
  de 1 à 16 lampes ; la composition, pour signaler un modèle à cataloguer ;
- des **pré-contrôles avant tout envoi** : un nom de plus de 31 octets ou avec
  un caractère de contrôle, une adresse dans `0x7F00`–`0x7F7F`, une adresse ou
  une MAC en double, une valeur de la base qui n'est pas du texte. L'app
  refuse alors avant d'écrire quoi que ce soit dans le pont.

**Trousseau local** :
- un élément générique par réseau (service `fr.djoko.amaran.reseau`) : les
  deux clés, la liste des lampes (adresse, MAC, nom, code), la date et la
  source de la copie ;
- mis à jour seulement sur le geste « Copier depuis amaran Desktop » ;
- en 3b-2, la clé UDP de chaque pont (service `fr.djoko.amaran.pont`, compte =
  nom SRP), comme Halo.

**Sauvegarde chiffrée**, sur le geste « Exporter une sauvegarde » :
- un fichier au contenu de l'élément du trousseau, vers le dossier choisi
  (panneau d'enregistrement) ;
- chiffré en AES-GCM 256 (CryptoKit), avec une clé tirée de la phrase de passe
  par PBKDF2-HMAC-SHA256 (600 000 tours, sel aléatoire de 16 octets) ; un
  en-tête versionné ;
- la phrase de passe : 12 caractères au moins, tapée deux fois, jamais gardée
  ni journalisée ;
- « Importer une sauvegarde » : choisir le fichier, taper la phrase, vérifier
  l'intégrité, montrer les empreintes, puis proposer de remplacer la copie du
  trousseau.

**Charger le pont, par l'USB seulement :**
- les commandes d'aujourd'hui : `mesh cles`, `mesh lampes <N>`, une ligne
  `mesh lampe <n> <adresse> <mac> <code> <nom>` par lampe, puis `redemarre` ;
- les quatre contrôles de l'outil : c'est bien le pont qui répond ; ses
  empreintes sont les nôtres ; il a enregistré la liste ; il a redémarré ;
- la source est amaran Desktop par défaut, ou le trousseau (base absente ou
  différente).

**Comparer sans rien montrer.** Le panneau « Clés » montre trois colonnes
d'empreintes (base, trousseau, pont) et la liste des lampes de chaque côté. Il
nomme l'écart et propose le geste qui convient : recharger le pont, mettre le
trousseau à jour, ou signaler un réseau recréé dans amaran Desktop.

**Hygiène :**
- une clé n'est jamais affichée, journalisée ni copiée dans le presse-papiers ;
- la console de l'app masque `mesh cles`, et le pont ne renvoie pas d'écho en
  mode machine ;
- les clés sont lues au dernier moment et effacées de la mémoire après usage.

**Sans amaran Desktop** (cassé ou désinstallé), l'app charge le pont depuis le
trousseau ou depuis une sauvegarde.

## 6. Le protocole et le mode JSON du pont (3b-1)

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

**Ce que le pont annonce :**
- `hello` : version du firmware, ESP-IDF, cause du démarrage, durée de marche,
  numéro de série `AMARAN-<MAC>`, capacités (`matter`, `thread`, `mesh`,
  `catalogue` ; `udp` et `cle` en 3b-2) ;
- `config` :
  - le catalogue des modèles (code, nom, capacités), dont le firmware est la
    seule source ;
  - l'en-tête de la liste (N, capacité, période de relecture) ;
  - une ligne par lampe : numéro, adresse, MAC, nom, code et modèle,
    capacités, endpoint, vue ou masquée ;
- `etat` :
  - le pont : Mesh prêt, statistiques des ordres (nombre, confirmés, abandons,
    délais) ;
  - une ligne par lampe : état lu (marche, intensité, lampe noire), joignable,
    consigne en cours et essai, relectures répondues sur 10 min, alerte ; une
    lampe part quand elle change, et toutes les 10 s ;
- `compteurs` (Mesh : annonces, NID reconnus, NetMIC faux, accès déchiffrés,
  émis, refus, file d'émission) et `reseau` (Thread, abonnements Matter) ;
- des événements : `ordre` (issue confirmé ou abandonné, délai), `alerte`
  (relectures manquées, Mesh inopérant), `lampe` (entendue, entrée dans Maison,
  masquée, remise), `log` (annonces de la console, sur demande), `led`, `fin`.

**Ordres.** `lampe <n> on|off|niveau <0-1000>` répond aussitôt `accepte`,
puis l'événement `ordre` donne son issue : c'est la « livraison » de Halo,
branchée sur la sortie `signaler` du cœur `lampes`. Le cœur signale désormais
chaque ordre : `confirme`, `abandon`, ou `tenu` (la lampe était déjà dans cet
état : rien n'est parti). L'`id` d'un ordre de l'app part avec l'ordre dans la
file de la tâche des lampes : l'événement qui le finit le porte, sans course
possible. `mesh lampe <n> masquer|afficher` répond en une fois, puis
l'événement `lampe`.

**Le firmware :**
- une tâche `json` de basse priorité lit les instantanés (lampes, liste, Mesh,
  Matter) et écrit ;
- une ligne s'écrit entière ou pas du tout, sans jamais bloquer les autres
  tâches : faute de place dans l'USB, elle est perdue et comptée ;
- le document `docs/PROTOCOLE-JSON.md` d'amaran décrit chaque message, avec un
  exemple vérifié par les tests.

**Risque levé en préparant le plan.** La console d'ESP-IDF (linenoise) ne
coupe pas son écho : le pont lit lui-même l'USB en mode machine (le repli
prévu). `usb_serial_jtag_write_bytes`, sans attente, écrit une ligne entière ou
rien. Le banc A du plan 3b-1 le confirme sur la carte, avant l'app.

## 7. Thread, le canal à distance (3b-2)

**Le canal H1 de Halo :**
- l'app apprend par l'USB le nom SRP du pont et le résout en `<nom>.local`,
  en IPv6, port UDP 5480 ; le nom suit les changements de préfixe ;
- **la clé UDP** (32 octets) se crée par l'USB seulement : l'app tire un aléa
  et envoie `json cle nouvelle <aléa>` ; le pont la dérive de cet aléa et du
  sien, l'écrit en NVS et la rend une seule fois, avec son empreinte ; l'app
  la range dans le trousseau. `json cle efface`, `decommission` ou BOOT tenu
  8 s l'effacent ;
- la session : SALUT puis DEFI, signés HMAC-SHA256, établissent une clé de
  session ; chaque datagramme est signé, avec son compteur, une fenêtre
  anti-rejeu et le sens. Intégrité seulement, pas de confidentialité : rien de
  secret ne passe par Thread ;
- les limites du pont : 2 sessions ouvertes et 1 en cours, 2 DEFI par seconde,
  3 000 octets par seconde en moyenne ; un datagramme refusé est ignoré en
  silence et compté.

**Liste blanche à distance** (tout le reste reçoit `interdite`) :
- `json 1` (bail de 10 à 120 s), `json 0`, `json etat`, `json hello`,
  `json ping`, et les cadences dans des bornes plus lentes ;
- `lampe <n> on|off|niveau|releve` ;
- `mesh lampe <n> masquer|afficher` (confirmé dans l'app, décision 7) ;
- `led test|stop`, et les lectures `lampes`, `lampe <n>`, `matter`, `mesh`,
  `taches`, `cause` ;
- interdits : `mesh cles`, `mesh lampes`, le chargement d'une lampe,
  `mesh oublie`, `mesh adresse`, `mesh iv`, `decommission`, `redemarre`.

**Profil à distance :** l'état toutes les 2 s (une lampe à chaque changement,
et toutes les 30 s), le réseau toutes les 30 s, ni compteurs ni trames par
défaut.

**Le firmware :** `components/h1` (pur, repris de Halo) ; dans
`firmware/main`, la socket OpenThread (`otUdp` sur l'interface Thread), la
file de réception et l'émission plafonnée.

**Sur le Mac :** l'outil `halo-routes` de Halo sert tel quel, puisque c'est le
même réseau Thread.

**Risque :** CHIP possède OpenThread. Halo y a déjà ouvert une socket UDP sur
la même pile ESP-IDF ; le plan 3b-2 commence quand même par cet essai.

## 8. L'app : écrans, réglages et mode démo

**La fenêtre** reprend celle de Halo : la barre latérale « Supervision » avec
les quatre écrans, et le panneau de connexion. Les sources :
- les ports série Espressif ; le pont est reconnu par son numéro de série USB,
  et jamais ouvert sans un clic ;
- les ponts connus par le réseau (3b-2) ;
- le mode démo.

**1. Tableau de bord (3b-1)**, une grille de cartes :
- « Ajouter à Maison » (QR et code), tant que le pont n'est pas appairé ;
- une carte par lampe, jusqu'à 16 : nom, modèle, place dans Maison (EP, jamais
  vue, masquée, hors de Maison), état lu, joignable, relectures sur 10 min,
  alerte, consigne en cours ;
- Bluetooth Mesh : prêt ou non, adresse, IV, empreintes, compteurs,
  diagnostic, période de relecture ;
- Thread et Matter (repris de Halo) ;
- Clés : le panneau de la section 5 et ses gestes (copier depuis amaran
  Desktop, charger le pont, exporter ou importer une sauvegarde) ;
- Voyant, et Système (version, démarrage, cause, tas, piles).

**2. Commandes et console (3b-1).**
- À gauche, une lampe choisie : marche, arrêt, niveau au pour cent près,
  relecture ; « retirer de Maison / remettre », avec sa confirmation ; la
  période de relecture.
- À droite, la console brute de Halo : corrélation des `id`, historique,
  masquage des clés, confirmation des commandes dangereuses (`redemarre`,
  `decommission`, `mesh oublie`, `mesh adresse`, `mesh iv`).

**3. Graphiques (3b-2)** : par lampe, la part des relectures répondues et les
délais des ordres ; pour le Mesh, les annonces, les NetMIC faux et les refus
d'émission ; le tas libre. Un redémarrage du pont ouvre un nouveau segment.

**4. Trames (3b-2)** : le trafic Mesh décodé (ordres et demandes d'état émis,
états reçus, par lampe), avec des filtres et la possibilité de figer. Le pont
ne les émet que sur demande (`json trames 1`), et les coupe seul au bout de
60 s à distance.

**Réglages (⌘,)**, sur le modèle de Halo :
- **Général** (3b-1) : le dossier d'amaran Desktop autorisé, avec
  « Changer… », et la date de la dernière sauvegarde exportée ;
- **Accès réseau Thread** (3b-2) :
  - « Ponts connus de ce Mac » : nom, empreinte de la clé UDP, état de la
    session (ouverte, en cours, refusée), et « Oublier… », qui retire la clé du
    trousseau (le pont garde la sienne) ;
  - « Pont branché en USB » : « Accès réseau : aucune clé » et « Activer
    l'accès réseau… », ou « Clé … connue de ce Mac » / « inconnue de ce Mac »
    et « Nouvelle clé… » ; la confirmation dit que le pont remplace sa clé et
    que les sessions en cours tombent ;
  - la carte « Thread et Matter » du tableau de bord ouvre cet onglet.

**Mode démo** : un pont simulé à trois lampes (dont une jamais vue et une
masquée) rejoue un scénario ; il sert aussi aux tests de bout en bout. Ses
données n'utilisent que des MAC inventées.

## 9. Erreurs

- Port pris ou débranché : nouvelles tentatives à 0,3, 1, 2 et 5 s, et
  réouverture quand macOS signale le retour du port (comme Halo).
- Firmware sans mode JSON : console seule, avec un bandeau.
- Base illisible, ou pré-contrôle refusé : message clair, rien n'est envoyé.
- Phrase de passe fausse ou fichier de sauvegarde altéré : refus net, sans
  indice.
- Thread (3b-2) : route IPv6 absente (l'app pointe vers `halo-routes`), pont
  sans clé (port fermé), sessions pleines ; messages repris de Halo.

## 10. Tests sur le Mac

- **Firmware** : les modules purs de `json` et de `h1`, avec leurs tests repris
  de Halo, dans `tests/hote/lancer.sh` ; chaque exemple de
  `docs/PROTOCOLE-JSON.md` vérifié.
- **App** (Swift Testing) :
  - tramage, session et corrélation, repris de Halo ;
  - décodage de chaque bloc amaran, et couverture de chaque champ des
    exemples ;
  - lecture d'une base SQLite factice et ses pré-contrôles ;
  - sauvegarde chiffrée : aller-retour ; une phrase fausse et un fichier
    altéré échouent ;
  - trousseau en mémoire ;
  - mode démo de bout en bout.

## 11. Bancs, avec Djoko

- **3b-1** : charger le pont depuis l'app ; piloter les lampes ; retirer puis
  remettre une lampe (Maison l'oubliera : on choisit une lampe sans
  configuration à perdre, ou on la refait) ; débrancher et rebrancher l'USB ;
  exporter puis importer une sauvegarde ; relever les marges de pile et de tas
  avec la tâche `json`.
- **3b-2** : ouvrir une session par Thread ; refuser une commande interdite ;
  piloter à distance ; une heure d'endurance à distance.

## 12. Risques et questions ouvertes

| risque | parade | levé par |
|---|---|---|
| linenoise ne coupe ni l'écho ni l'invite | lecture de ligne propre au mode machine | levé en préparant le plan 3b-1 : linenoise fait toujours l'écho ; le pont a sa propre tâche de console ; à confirmer au banc A |
| l'USB ne sait pas écrire une ligne entière sans bloquer | tampon et écriture tout ou rien, ligne perdue et comptée | levé en préparant le plan 3b-1 : `usb_serial_jtag_write_bytes` sans attente écrit tout ou rien (tampon porté à 4 Ko) ; à confirmer au banc A |
| le signet ne donne pas accès au conteneur d'amaran Desktop | copie de la base choisie par Djoko, ou app sans sandbox (à décider avec lui) | banc B du plan 3b-1, en premier : l'essai demande l'app signée et un choix de Djoko ; macOS lui demande alors d'autoriser l'accès aux données d'une autre app |
| une socket UDP sur OpenThread gêne CHIP | essai d'abord ; Halo l'a déjà fait | tâche 1 du plan 3b-2 |
| la tâche `json` ou H1 manque de tas ou de pile | budget relevé au banc ; cadences abaissées | bancs 3b-1 et 3b-2 |
| l'icône M2 reprend une marque déposée | non versionnée ; A2 en repli dans le dépôt | décision 9 |

## 13. Suite

- Après 3b-1 et 3b-2 : l'essai de provisionnement (capture PacketLogger, puis
  une C6), puis le plan 3c, le secours autonome.
- Reportés du plan 3a, à reprendre ici si l'app les rend utiles : l'alerte de
  relectures aux longues périodes, et les harnais NVS du pont à promouvoir
  dans `tests/hote`.
