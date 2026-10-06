# Déploiement d'Amaran Compagnon : mise à jour automatique, versions publiées, français et anglais

Spec du 06/10/2026. Djoko a validé la conception le même jour. Elle reprend le
déploiement de Maillage Thread et de Halo Compagnon (spec
`docs/superpowers/specs/2026-10-06-deploiement-design.md` des dépôts
`Djoko-cli/maillage-thread` et `Djoko-cli/benq-screenbar-halo-matter`, et le
brief de passation du 06/10), et dit seulement ce qui diffère pour Amaran
Compagnon.

## 0. Contexte et décisions

Amaran Compagnon (`apps/macos`) est aujourd'hui en version 1.0, dans le bac à
sable, sans aucune version publiée. Par défaut, il est signé ad hoc ; Djoko le
compile avec son équipe (`Local.xcconfig`, ignoré par git), parce que trois
choses doivent survivre d'une compilation à l'autre : la copie des clés du Mesh
et les clés UDP des ponts, dans le trousseau ; le signet vers le dossier
d'amaran Desktop ; le runtime durci (signé ad hoc, l'app ne peut pas charger
son framework avec lui).

**Décisions de Djoko (06/10) :**

| Sujet | Décision |
|---|---|
| Moteur | **Sparkle 2**, comme les autres apps (brief, section 1) : tout automatique, flux `appcast.xml` joint à chaque version publiée, même paire Ed25519 que les autres apps |
| Signature | **un certificat auto-signé stable**, sans nom de personne ni équipe (2) |
| Première version | **1.0.0** |
| Langues | **français et anglais** : toute l'interface (4) |
| Thread Route | l'app **repère** le démon et dit comment l'installer ; son code reste dans le dépôt du pont Halo (3) |
| Commits | comme dans ce dépôt : directement sur `main` ; **push seulement avec l'accord de Djoko** |
| Calendrier | après la publication de Halo Compagnon 1.0.0 : le prototype reprend son code final et le brief complété |
| Remise | `Amaran-Compagnon-1.0.0.dmg` sur le Bureau |

**Ce qui ne change pas :** le bac à sable et ses droits (`network.client` y est
déjà) ; aucune donnée réelle dans ce qui est publié (le contrôle
d'anonymisation passe avant chaque publication) ; l'icône publiée est la A2,
versionnée : la M2 (le A d'Aputure) n'est jamais publiée.

## 1. Le moteur de mise à jour

Comme le brief et la spec de Halo, à l'identique :
- Sparkle 2 par le gestionnaire de paquets Swift, à la version figée par Halo,
  déclaré dans `apps/macos/project.yml` ;
- `Info.plist` : `SUFeedURL`
  (`https://github.com/Djoko-cli/amaran-60d-matter/releases/latest/download/appcast.xml`),
  `SUPublicEDKey`, `SUEnableInstallerLauncherService`, `SUEnableAutomaticChecks`,
  `SUAutomaticallyUpdate`, `SUScheduledCheckInterval` = 86400 ;
- droits `mach-lookup` `fr.djoko.amaran.compagnon-spks` et `-spki` ;
- menu « Rechercher les mises à jour… » ; dans les Réglages, « Rechercher
  automatiquement » et « Installer automatiquement », cochés ;
- le moteur ne démarre jamais sous les tests.

**Le dépôt contient aussi le firmware.** Le flux se lit à la dernière version
publiée (`releases/latest`) : seules les versions de l'app sont publiées sur ce
dépôt, avec l'étiquette `vX.Y.Z`. Le firmware continue de se compiler depuis le
dépôt.

## 2. La signature

**Un certificat auto-signé de signature de code**, créé une fois avec Djoko
dans son trousseau de session, au nom de `Djoko-CLI` (le nom de son compte
GitHub, déjà public) : ni son nom, ni son adresse, ni son équipe Apple dans le
binaire publié.

- **Pourquoi :** l'exigence de signature (« designated requirement ») d'une app
  signée ainsi porte sur ce certificat, qui ne change pas d'une version à
  l'autre. Le trousseau, le signet et le conteneur de l'app reconnaissent donc
  chaque mise à jour comme la même app. Signée ad hoc, l'app changerait
  d'identité à chaque version, et macOS redemanderait l'accès à chaque clé du
  trousseau après chaque mise à jour.
- **Gatekeeper** le traite comme une signature ad hoc : la première
  installation, depuis le navigateur, demande une autorisation dans Réglages
  Système ; les mises à jour installées par Sparkle sont garanties par la
  signature Ed25519 (choix du brief).
- **Le runtime durci reste coupé**, comme aujourd'hui en ad hoc : sans équipe,
  la validation des bibliothèques refuserait le framework de l'app.
- **`publier.sh`** signe avec ce certificat (identité donnée à `xcodebuild` sur
  la ligne de commande) ; rien de commité ne nomme l'équipe Apple de Djoko.
- **Les compilations de travail de Djoko** passent au même certificat
  (`Local.xcconfig` : `CODE_SIGN_IDENTITY = Djoko-CLI`, sans équipe, runtime
  durci coupé, icône M2 gardée) : son app de travail et l'app installée ont
  alors la même identité, et passer de l'une à l'autre ne redemande rien.
- **Une fois, au passage :** l'app d'aujourd'hui est signée par l'équipe de
  Djoko. La première app signée par le nouveau certificat redemandera l'accès
  aux clés du trousseau (« Toujours autoriser »), et peut-être le dossier
  d'amaran Desktop ; ensuite plus rien.

La répétition (5) vérifie ces trois points avant toute publication.

## 3. Thread Route

Comme Halo Compagnon (branche du déploiement de Halo, `ThreadRoute.swift`) :
l'essai de Halo a montré que `SMAppService` refuse un démon installé depuis une
app du bac à sable. Thread Route s'installe donc par son script, dans le dépôt
du pont Halo (`sh tools/macos/thread-route/installer.sh`, mot de passe
administrateur), et le code du démon n'existe que là.

Amaran Compagnon lit son état auprès du système
(`SMAppService.statusForLegacyPlist`, permis dans le bac à sable) : absent, à
approuver, actif, ou l'ancien `halo-routes` encore là. Actif, il n'y touche
pas ; sinon, il dit quelle commande lancer, dans le dépôt du pont Halo. Les
messages qui nomment aujourd'hui `halo-routes` (console, panneau de connexion)
nomment Thread Route. Le code est repris de Halo Compagnon.

## 4. Français et anglais

- **Toute l'interface de l'app** passe par un catalogue de chaînes
  (`Localizable.xcstrings`), langue de développement le français, traduction
  anglaise ; comme Halo Compagnon (`tr(...)` pour les textes formés hors des
  vues). Les textes formés dans `AmaranProtocole` (notes, erreurs, écarts,
  interprétation) aussi.
- **Ce qui vient du pont reste tel quel :** la console du pont, ses messages
  `texte`, ses erreurs, ses noms de lampes sont en français, et l'app les
  montre sans les traduire.
- **Les tests** passent en français et en anglais (langue de l'app forcée par
  le schéma ou l'argument de lancement, comme Halo).
- **Les notes de version** (`apps/macos/NOTES-VERSIONS.md`) et la partie
  « installer, Gatekeeper, mise à jour, Thread Route » du README de l'app sont
  en français et en anglais.
- Les textes de Sparkle viennent de ses propres traductions.

## 5. La publication et la répétition

`apps/macos/Outils/publier.sh X.Y.Z`, repris de Halo Compagnon : vérifications
(`main` propre et à jour, version nouvelle, tests verts : app, tests natifs,
outil), numéros (`MARKETING_VERSION` ; numéro de compilation = nombre de
commits de `main`), compilation Release signée par le certificat (2), `.dmg`
(`hdiutil`, l'app et un raccourci vers Applications), signature `sign_update`,
`appcast.xml` (système minimal macOS 15.0), contrôle d'anonymisation, étiquette
et version publiée (`gh release create`), copie sur le Bureau.

**La répétition, sans GitHub**, comme le brief (clé d'essai dans un fichier,
serveur local sur 127.0.0.1, `sparkle-cli`), avec trois vérifications propres
à Amaran, sur une copie de l'app :
1. la version 1.0.0, signée par le certificat, range une clé d'essai dans le
   trousseau (jamais la vraie clé du Mesh) et un signet d'essai ;
2. elle se met à jour en 1.0.1, signée par le même certificat ;
3. la 1.0.1 relit la clé et le signet sans rien demander.

Plus les vérifications du brief : un `.dmg` mal signé est refusé, un flux sans
nouveauté ne change rien.

## 6. Tests et vérification

- Les suites existantes restent vertes, en français et en anglais.
- Tests nouveaux (repris de Halo) : l'`Info.plist` porte le flux, la clé
  publique et les réglages ; le moteur ne démarre pas sous les tests ; les
  numéros ; `appcast.xml` à partir de valeurs inventées ; l'état de Thread Route
  dans ses quatre cas ; chaque chaîne du catalogue a sa traduction anglaise.
- **Avec Djoko, en vrai :** créer le certificat ; installer depuis le `.dmg`
  du Bureau et passer Gatekeeper ; l'accès au trousseau et au dossier d'amaran
  Desktop au passage à la 1.0.0 ; le menu de mise à jour ; l'état de Thread
  Route.

## 7. Limites

- **La première installation** passe par Gatekeeper.
- **Le certificat** est valable plusieurs années (durée choisie à la
  création) ; le renouveler change l'identité : une fois de plus, macOS
  redemandera l'accès au trousseau.
- **Une copie déjà installée par quelqu'un d'autre** ne se met à jour qu'à
  partir de la 1.0.0.
- **Le pont et sa console restent en français.**
