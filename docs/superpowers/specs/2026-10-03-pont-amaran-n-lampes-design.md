# Pont amaran : N lampes et catalogue de modèles (plan 3a)

Date : 03/10/2026. Statut : design validé section par section avec Djoko ;
précisé le même jour par la lecture d'esp-matter et le prototype du plan (5, 4,
7, 10, 11).
Prolonge la spec du pont (`2026-09-28-pont-amaran-design.md`), qui reste la
référence pour tout ce que ce document ne change pas.

Le pont pilote aujourd'hui exactement deux amaran COB 60d. Ce plan le rend prêt
pour l'avenir : autant de lampes que la carte peut en tenir, et d'autres modèles
Aputure ou amaran du même protocole. C'est la fondation de l'app compagnon
(plan 3b), qui sera bâtie directement sur N lampes.

## 1. But et périmètre

Dans le périmètre :
- une liste de lampes au lieu de deux emplacements, jusqu'à une capacité de
  compilation (16 au départ) ;
- des numéros d'endpoint Matter stables, gardés par MAC ;
- l'exposition dans Maison : une lampe jamais vue n'y apparaît pas, et le
  retrait de Maison est un geste explicite (7) ;
- un catalogue de modèles dans le firmware, dont seule la COB 60d est réalisée ;
- la migration du pont en service sans perdre ses tuiles dans Maison ;
- l'alerte de relectures manquées par lampe ;
- la console, `outils/cles_amaran.py`, le firmware `ecoute` et les tests,
  adaptés à N ;
- les bancs de migration, de retrait et retour, de lampe jamais vue et de
  capacité.

Hors périmètre :
- l'app compagnon, le mode JSON, le canal UDP sur Thread (plan 3b) ;
- le provisionnement autonome d'une lampe (essai à part, puis plan 3c) ;
- tout réglage autre que marche/arrêt et intensité : le CCT, la couleur et les
  effets d'un autre modèle viendront quand ce modèle sera catalogué et vérifié
  avec la vraie lampe ;
- changer la liste à chaud : charger une nouvelle liste demande un
  redémarrage, comme aujourd'hui (l'exposition d'une lampe de la liste, elle,
  se fait à chaud : 7) ;
- le masquage automatique d'une lampe absente : seulement en option, et
  seulement si le banc 2 montre que Maison garde tout au retour (12) ;
- les groupes Mesh configurés dans les lampes (piste notée en 9).

## 2. Décisions de Djoko (03/10/2026)

1. **Plan 3, propriétaire du réseau : « A puis C ».** amaran Desktop reste
   propriétaire du réseau Bluetooth Mesh ; le pont y adhère comme aujourd'hui.
   Un secours autonome viendra plus tard (plan 3c). Le réseau propre au pont
   est écarté : Djoko se sert encore d'amaran Desktop et de l'app Sidus (CCT,
   effets).
2. **Prêt pour l'avenir : nombre de lampes et autres modèles.**
3. **Le firmware N lampes passe avant l'app**, dans son propre plan.
4. **Une lampe d'un modèle inconnu est exposée en intensité seule** (marche et
   niveau), avec une note.
5. **Horizon inconnu : viser le maximum raisonnable, mesuré.** Capacité de 16
   au départ, relevée si le banc le permet.
6. **Lampes absentes.** Une lampe jamais vue n'est jamais exposée dans Maison ;
   une lampe déjà vue reste exposée, en « Pas de réponse » quand elle est
   absente ; le retrait de Maison est un geste explicite. Retirer
   automatiquement une lampe muette depuis 5 minutes (idée de Djoko) ferait
   très probablement perdre à Maison sa pièce, ses groupes, ses scènes et ses
   automatisations, à chaque extinction au bouton d'alimentation : ce masquage
   ne viendra qu'en option par lampe, si le banc 2 montre que Maison garde
   tout au retour.

## 3. Faits établis (03/10/2026)

Lus dans la base d'amaran Desktop (colonnes descriptives seulement, jamais les
clés) :
- la table `fixtures` garde, par lampe : `node_address`, `mac_address`, `name`,
  `code`, `device_key`, `device_uuid`, `composition_data`,
  `fast_provision_supported`, et les versions matérielles et logicielles ;
- **`code` = `40065`** pour les deux 60d : le code produit Sidus du modèle ;
- **`composition_data`** d'une 60d : société `0x0211` (Telink), produit
  `0x0102`, version `0x3333`. Un élément, dix modèles SIG (serveur de
  configuration, santé, Generic OnOff, Generic Level, transition par défaut,
  Power OnOff et son réglage, Light Lightness et son réglage) et le modèle
  vendeur Telink. **Ni Light CTL ni Light HSL** : une lampe lumière du jour ;
- `fast_provision_supported` = 0 ;
- la table `groups` n'a qu'un groupe, « All » (`0xC000`).

Du banc :
- une relecture interroge le groupe « All » : toutes les lampes répondent à une
  seule demande. Le budget de séquence ne dépend donc pas du nombre de lampes :
  environ 87 000 numéros par jour à 2 s (BANC.md, relecture toutes les 2 s) ;
- une salve d'ordre occupe la file d'émission environ 0,4 s par lampe (revue
  finale du plan 2, M5).

## 4. Les lampes en NVS

**Une lampe :**

| champ | rôle |
|---|---|
| MAC | identité stable (UniqueID dans Matter) |
| adresse Mesh | unicast, `0x0001` à `0x7FFF`, hors `0x7F00`–`0x7F7F` (nos adresses) |
| nom | NodeLabel dans Matter, 32 caractères au plus |
| code de modèle | code produit Sidus (`40065` pour la 60d) |
| endpoint | numéro d'endpoint Matter, attribué une fois (5) |
| vue | la lampe a répondu au moins une fois (7) |
| masquée | retirée de Maison par un geste explicite (7) |

**Capacité.** `LAMPES_CAPACITE`, une constante de compilation, vaut 16 au
départ. Elle remplace `AMARAN_LAMPES_MAX` et `LAMPES_MAX` (aujourd'hui 2), et
fixe aussi le nombre d'endpoints dynamiques réservés dans la configuration
Matter, et la taille de la file d'émission.

**Format versionné.** La liste est écrite en un seul enregistrement, avec un
en-tête : numéro de format (2), nombre de lampes, et **taille d'une lampe**. Une
capacité relevée plus tard relit donc toujours une liste écrite avant. Une
liste illisible ou invalide donne une liste vide, et le journal le dit. Au
premier démarrage, le firmware lit l'ancien format (deux emplacements) et le
convertit une fois :
- la lampe 1 garde l'endpoint 2, la lampe 2 l'endpoint 3 ;
- le compteur d'esp-matter est déjà à 4 (5) ;
- les deux lampes sont marquées vues, et non masquées : leurs tuiles restent ;
- le code de modèle des lampes converties vaut `40065` : seules des 60d ont pu
  être chargées avant ce plan.

La conversion est une fonction pure, testée sur le Mac. Une conversion
interrompue (coupure) se refait au démarrage suivant : l'ancien format n'est
effacé qu'après l'écriture complète du nouveau.

**Refus, avec un message clair à la console :**
- une liste plus longue que la capacité ;
- deux lampes avec la même MAC, ou la même adresse ;
- une adresse hors de l'unicast, ou dans nos adresses réservées ;
- un nom vide ou avec un caractère de contrôle.

Un code de modèle inconnu n'est **pas** un refus : la lampe est gardée, et
exposée en intensité seule (6).

## 5. Numéros d'endpoint stables

Règles :
- une MAC déjà connue garde son numéro, quelle que soit sa place dans la liste ;
- une lampe reçoit son numéro **à sa première exposition** dans Maison (7), et
  le garde ensuite, même masquée ;
- **un numéro libéré n'est jamais réattribué**, et le compteur ne recule
  jamais : Maison ne confond pas une nouvelle lampe avec une tuile disparue ;
- une MAC retirée de la liste perd son numéro avec elle, et son endpoint n'est
  plus créé.

Le numéro de chaque lampe vit en NVS, dans la liste (4).

**Le compteur est celui d'esp-matter** (lu dans `c5b9ea8`). Il garde en NVS le
plus petit numéro jamais utilisé (`min_uu_ep_id`), ne le fait jamais reculer,
et l'a mis à 4 sur le pont en service (EP0 à EP3). Une lampe sans numéro le
reçoit de `bridged_node::create`. Une lampe qui en a un est recréée avec lui par
`bridged_node::resume`, qui exige un numéro déjà passé par ce compteur.
`resume` n'est possible qu'**après** `esp_matter::start()`, qui relit le
compteur. C'est le schéma des exemples de pont d'esp-matter : endpoints pontés
recréés juste après le démarrage, puis activés (7).

**Désappairage complet** (`decommission`, BOOT 8 s) : esp-matter efface son
compteur avec le reste de sa NVS. Au démarrage suivant, les lampes exposées
sont recréées dans l'ordre croissant de leur numéro. Un numéro devenu trop
grand pour le compteur repart de lui. Les mêmes numéros reviennent donc s'ils
se suivaient depuis 2. Sinon, la lampe en prend un neuf, sans conséquence : le
pont n'est plus dans Maison.

## 6. Catalogue de modèles

Une petite table dans le firmware, indexée par le code Sidus. Pour chaque
modèle :
- son nom ;
- ses capacités : intensité, CCT (avec sa plage en kelvins), couleur ;
- le type d'appareil Matter qui en découle : lampe à intensité variable
  (Dimmable Light), à température de couleur (Color Temperature Light), ou
  couleur (Extended Color Light).

**Une seule entrée est réalisée : `40065`, amaran COB 60d, intensité seule,
Dimmable Light.** Un code absent du catalogue donne les capacités de repli :
intensité seule, Dimmable Light, avec la note « modèle non catalogué » à la
console. Les trames `0x8C` (marche) et `0x8F` (intensité) sont celles du
protocole Sidus commun : elles restent les seules qu'on émet.

Le firmware est la **source unique** du catalogue. Il annonce le modèle et les
capacités de chaque lampe (console aujourd'hui, mode JSON au plan 3b) ; l'app
affichera ce qu'il annonce, sans table à elle.

Ajouter un modèle plus tard, c'est ajouter une entrée au catalogue, puis la
vérifier au banc avec la vraie lampe.

## 7. Matter

- **Exposée** = vue et non masquée. Au démarrage, le pont crée un endpoint pont
  par lampe exposée, avec son numéro (5) et le type que donne le catalogue (6).
  Le code de création est organisé par capacité : ajouter le CCT plus tard ne
  touchera qu'à la partie CCT.
- **Une lampe jamais vue n'est pas exposée.** À sa première réponse, le pont la
  marque vue en NVS et crée son endpoint **à chaud** : sa tuile apparaît dans
  Maison. Une lampe déclarée dans amaran Desktop mais absente d'ici (autre
  studio, lampe prêtée) n'encombre donc jamais Maison.
- **Une lampe déjà vue reste exposée**, en « Pas de réponse » quand elle est
  absente (règle 7.2 de la spec du pont). Elle garde sa tuile, sa pièce, ses
  groupes, ses scènes et ses automatisations.
- **Retrait explicite.** `mesh lampe <n> masquer` retire l'endpoint à chaud et
  marque la lampe masquée ; `mesh lampe <n> afficher` la ré-expose avec le même
  numéro, même si elle n'a jamais été vue (c'est ce qui sert au banc de
  capacité). Un masquage survit aux redémarrages et aux rechargements de la
  liste. L'app compagnon (3b) offrira le même geste.
- La création et le retrait à chaud suivent les exemples de pont d'esp-matter
  (création, puis activation de l'endpoint ; retrait qui met à jour la liste
  des parties de l'agrégateur). Le détail des appels est à vérifier dans le
  commit installé lors du plan.
- Seul le type Dimmable Light est réalisé. Tout le reste du comportement
  d'une lampe est celui de la spec du pont (6.2 à 6.5) : conversion linéaire,
  lampe noire, pas d'écho, démarrage sans ordre rejoué.
- Une lampe retirée de la liste n'a plus d'endpoint au redémarrage : la liste
  des parties de l'agrégateur change, et Maison retire sa tuile.
- Au démarrage, les endpoints des lampes exposées sont recréés **juste après**
  `esp_matter::start()` (5), avant que Thread ne soit rattaché et que les
  contrôleurs ne se reconnectent. Le banc 1 vérifie, sur plusieurs
  redémarrages, que Maison garde les tuiles.
- Une garde de 2 s par lampe, à la création de son endpoint, ignore les valeurs
  que la pile y pose (leçon du Halo) : ce ne sont pas des ordres.
- Les noms et la joignabilité suivent les règles actuelles (NodeLabel non
  persistant, Reachable par la règle 7.2 de la spec du pont).

## 8. Relecture et radio à N lampes

- La relecture reste une demande au groupe « All », envoyée 2 fois, toutes les
  2 s par défaut (`mesh releve` la règle de 1 à 60 s).
- Toutes les lampes répondent à la même demande : plus il y en a, plus les
  réponses risquent de se télescoper. Le pont ne devine pas de règle : il
  mesure.
- **Alerte de relectures manquées.** Pour chaque lampe, le pont suit la part des
  relectures répondues sur une fenêtre glissante de 10 minutes. Sous 95 % (le
  seuil de la règle 5.8), la console affiche
  `!! lampe <n> : relectures manquees (<p> % sur 10 min) : allonger la periode (mesh releve)`,
  une fois, puis de nouveau seulement après être repassée au-dessus. Une lampe
  muette (« Pas de réponse », 7.2) n'est pas concernée : c'est une autre alerte.
- Pas d'adaptation automatique de la période tant qu'on n'en a pas vu le besoin
  avec de vraies lampes.

## 9. Ordres à N lampes

- Chaque lampe reçoit sa propre salve, comme aujourd'hui. La file d'émission
  est dimensionnée selon la capacité.
- **Limite connue, assumée :** quand une pièce de Maison règle beaucoup de
  lampes à la fois, la dernière suit plusieurs secondes après la première
  (environ 0,4 s de file par lampe). Le banc la mesure.
- Piste pour plus tard, hors de ce plan : une seule trame à un groupe Mesh
  quand plusieurs lampes reçoivent la même consigne. Il faudrait configurer des
  groupes dans les lampes.

## 10. Console et outils

- `lampes` : une ligne par lampe (numéro, nom, sa place dans Maison : `EP<n>`,
  « jamais vue » ou « masquée », état lu, joignable, relectures répondues sur
  relectures), puis les compteurs d'ordres.
- `mesh lampe <n> masquer | afficher` : retire la lampe de Maison, ou l'y
  remet (7). Effet immédiat, sans redémarrage.
- `lampe <n> on | off | niveau <0-1000> | releve` : pour `n` de 1 à N. Avec
  `lampe <n>` seul : le détail de la lampe (adresse, MAC, modèle,
  capacités, endpoint, consigne, relectures). La console est locale : la MAC
  n'y est pas un secret, mais ne va jamais dans le dépôt.
- **Chargement d'une liste, tout ou rien** : `mesh lampes <N>` ouvre une liste
  de N lampes, puis `mesh lampe <n> <adresse> <mac> <code> <nom>` en donne
  chacune. Le code passe **avant** le nom, qu'un nombre peut terminer
  (« Lampe 2 »). Chaque ligne reçoit une seule réponse : `ok lampe <n> 0x<adresse>
  modele <code> <nom du modèle> [<capacités>] : <nom>`, ou `erreur ...`. La
  dernière lampe donnée, la liste est validée (doublons) et enregistrée, et sa
  réponse se termine par `; liste de N lampe(s) enregistree`. Une liste refusée
  ne change rien. `mesh lampes 0` vide la liste. Effet au redémarrage, comme
  aujourd'hui.
- `mesh oublie` efface les clés et **garde la liste** : les tuiles restent dans
  Maison, en « Pas de réponse », comme au banc T9.
- `outils/cles_amaran.py` :
  - lit aussi la colonne `code` ;
  - accepte jusqu'à `LAMPES_CAPACITE` lampes, et refuse au-delà ;
  - envoie `mesh lampes <N>` puis chaque `mesh lampe`, et exige que la
    dernière réponse dise la liste enregistrée (sinon, pas de redémarrage) ;
  - contrôle `composition_data` : si une lampe déclare Light CTL ou Light HSL
    alors que le pont, dans sa réponse, ne lui donne pas ces capacités, il le
    signale (« modèle à cataloguer »), sans refuser. Le catalogue reste dans le
    firmware : l'outil lit ce que le pont annonce.
- Le firmware `ecoute` partage le composant `mesh` : il passe à la liste, sans
  autre changement de comportement.

## 11. Tests sur le Mac

TDD, comme aux plans 1 et 2, dans `tests/hote/` :
- `liste` : validation (capacité, doublons, adresses, MAC, noms), fusion d'une
  nouvelle liste (une MAC connue garde numéro et drapeaux, quelle que soit sa
  place ; une absente disparaît), format en NVS (aller-retour, en-tête,
  refus d'un autre format), conversion de l'ancien format (EP2, EP3, vues) ;
- catalogue : la 60d, un code inconnu (repli) ;
- exposition (module pur) : jamais vue → pas exposée ; première réponse →
  exposée et marquée vue ; masquée → pas exposée même si elle répond ;
  afficher → exposée, même jamais vue ; le tout survit à un redémarrage
  simulé ;
- `lampes` à N : relecture de groupe, joignabilité par lampe, ordres sur
  plusieurs lampes, et l'alerte sous 95 % sur 10 minutes (entrée, sortie, pas de
  répétition) ;
- `cles_amaran.py` : N lampes, colonne `code`, refus au-delà de la capacité,
  contrôle de `composition_data` (base SQLite factice).

## 12. Bancs, avec Djoko

1. **Migration.** Flash sans effacer, sur le pont en service. Attendu : les deux
   tuiles, leur pièce, le groupe d'accessoires et les automatisations restent
   identiques dans Maison ; EP2 et EP3 inchangés (`matter`) ; un T1 rapide
   (allumer, régler, éteindre chaque lampe).
2. **Retrait et retour : ce que Maison garde.** Masquer la lampe 2, puis
   l'afficher. Attendu : sa tuile disparaît, puis revient avec **EP3** ; la
   lampe 1 n'a pas bougé. **On relève ce que Maison a gardé au retour** : la
   pièce, le groupe d'accessoires, une scène et une automatisation de test qui
   la contiennent. (Retirer une lampe de la liste, elle, lui fait perdre son
   numéro, 5 : remise plus tard, elle revient comme une lampe nouvelle. Le
   banc 4 exerce ce retrait avec ses lampes fictives.)
   - Si Maison garde tout : on ajoute l'option par lampe « masquer quand
     absente depuis 5 min » (décision 6), avec son propre test.
   - Sinon : on en reste au geste explicite, et le constat va dans BANC.md.
3. **Lampe jamais vue.** Déclarer une lampe fictive (`outils/cles_amaran.py
   --fictives 1`) : aucune tuile n'apparaît, et `lampes` la dit « jamais vue ».
4. **Capacité, avec l'accord de Djoko le moment venu.** Ajouter des lampes
   fictives jusqu'à 16 (`outils/cles_amaran.py --fictives 14` : adresses qui ne
   répondent jamais, MAC administrées localement), et les exposer avec
   `afficher`.
   Mesurer : tas libre et piles, temps jusqu'à `mesh pret`, tenue de Maison
   (16 tuiles, abonnements), ordres sur les deux vraies lampes. Puis recharger
   la liste sans les fictives (`outils/cles_amaran.py`) : leurs tuiles
   disparaissent au redémarrage. Ce banc est intrusif
   (tuiles « Pas de réponse » le temps de la mesure). La charge radio réelle à N lampes
   ne se mesurera qu'avec de vraies lampes en plus.

## 13. Risques et questions ouvertes

| risque ou question | parade | tranché par |
|---|---|---|
| fonction d'esp-matter pour imposer le numéro d'endpoint absente ou différente | repli décrit en 5 | plan (lecture d'esp-matter) |
| mémoire insuffisante pour 16 endpoints | capacité abaissée à ce que mesure le banc | banc 4 |
| création ou retrait d'endpoint à chaud mal suivi par Maison | retour au comportement « au démarrage seulement » (exposition au redémarrage suivant) | bancs 2 et 3 |
| Maison oublie pièce, groupes et scènes d'une lampe retirée puis revenue | retrait seulement par geste explicite ; pas de masquage automatique | banc 2 |
| Maison réordonne ou recrée les tuiles à la migration | numéros et UniqueID inchangés ; sinon, retour au firmware précédent (flash) | banc 1 |
| réponses télescopées au-delà de quelques lampes | alerte sous 95 %, période allongée à la main | banc réel, plus tard |
| autres modèles : trames `0x8C`/`0x8F` différentes | repli en intensité seule à vérifier avec la vraie lampe ; entrée de catalogue | à l'arrivée d'un nouveau modèle |

## 14. Suite du plan 3

- **Plan 3b, app compagnon macOS** : décisions déjà prises le 03/10. Elle reprend
  Halo Compagnon (copie adaptée, comme le socle), avec quatre écrans (tableau de
  bord, commandes et console, graphiques, trames) et une liaison par l'USB et
  par Thread. Pour les clés, elle lit amaran Desktop sans jamais y écrire, et
  garde une copie dans le trousseau iCloud, mise à jour seulement sur un geste
  de Djoko. Les clés ne sont chargées dans le pont que par l'USB, et l'app
  compare les empreintes base / trousseau / pont. Elle offre aussi le geste
  « retirer de Maison » / « remettre » par lampe (7). Sa spec viendra après ce
  plan, bâtie sur N lampes et sur le catalogue.
- **Essai de provisionnement** (indépendant) : capture PacketLogger pendant
  qu'amaran Desktop rajoute une lampe réinitialisée, déchiffrée hors ligne avec
  les clés de la base (`device_key` compris), puis essai avec une C6.
- **Plan 3c, secours autonome** : réintégrer une lampe réinitialisée dans le
  même réseau ; sa spec s'écrit après l'essai.
