# Déploiement d'Amaran Compagnon : mise à jour automatique, versions publiées, français et anglais

Spec du 06/10/2026. Djoko a validé la conception le même jour. Elle reprend le
déploiement de Maillage Thread et de Halo Compagnon (spec
`docs/superpowers/specs/2026-10-06-deploiement-design.md` des dépôts
`Djoko-cli/maillage-thread` et `Djoko-cli/benq-screenbar-halo-matter`, et le
brief de passation, version mise à jour après leur publication en 1.0.0 le
06/10), et dit seulement ce qui diffère pour Amaran Compagnon. Amendée le même
jour par ce que ce premier déploiement a appris.

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
| Moteur | **Sparkle 2.10.0**, comme les autres apps (brief, section 1) : tout automatique, flux `appcast.xml` dans le dépôt, même paire Ed25519 que les autres apps |
| Signature | **le certificat auto-signé commun à toutes les apps de Djoko, `Djoko-cli Code Signing`**, déjà dans son trousseau (2) |
| Première version | **1.0.0** |
| Langues | **français et anglais** : toute l'interface (4) |
| Thread Route | l'app **repère** le démon et dit comment l'installer ; son code reste dans le dépôt du pont Halo (3) |
| Commits | comme dans ce dépôt : directement sur `main` ; **push seulement avec l'accord de Djoko** |
| Calendrier | après la publication de Halo Compagnon 1.0.0 (faite le 06/10) : le prototype reprend son code final et le brief complété |
| Remise | `Amaran-Compagnon-1.0.0.dmg` sur le Bureau |

**Ce qui ne change pas :** le bac à sable et ses droits (`network.client` y est
déjà) ; aucune donnée réelle dans ce qui est publié (le contrôle
d'anonymisation passe avant chaque publication) ; l'icône publiée est la A2,
versionnée : la M2 (le A d'Aputure) n'est jamais publiée.

## 1. Le moteur de mise à jour

Comme le brief et la spec de Halo, à l'identique :
- Sparkle **2.10.0** par le gestionnaire de paquets Swift (`exactVersion`),
  déclaré dans `apps/macos/project.yml` ; ses outils (`sign_update`,
  `generate_keys`) viennent de l'archive 2.10.0, passés par `SPARKLE_BIN` ;
- `Info.plist` : `SUFeedURL`
  (`https://raw.githubusercontent.com/Djoko-cli/amaran-60d-matter/main/apps/macos/appcast.xml`),
  `SUPublicEDKey`, `SUEnableInstallerLauncherService`, `SUEnableAutomaticChecks`,
  `SUAutomaticallyUpdate`, `SUScheduledCheckInterval` = 86400 ;
- droits `mach-lookup` `fr.djoko.amaran.compagnon-spks` et `-spki` ;
- menu « Rechercher les mises à jour… » ; dans les Réglages, « Rechercher
  automatiquement » et « Installer automatiquement », cochés ;
- le moteur ne démarre jamais sous les tests.

**Le flux est dans le dépôt** (`apps/macos/appcast.xml`, sur `main`) : il
garde toutes les versions, et chaque `.dmg` reste dans sa version publiée,
d'étiquette `compagnon-vX.Y.Z` (créée par `gh release create --target`). Le
dépôt contient aussi le firmware : une version publiée du firmware, un jour, ne
toucherait pas le flux.

## 2. La signature

**Le certificat auto-signé commun à toutes les apps de Djoko**,
`Djoko-cli Code Signing` (valide 10 ans), déjà dans le trousseau de Djoko avec
la clé Ed25519 : on le réutilise, on n'en crée pas d'autre. Ni le nom de Djoko,
ni son adresse, ni son équipe Apple dans le binaire publié.

- **Pourquoi :** l'exigence de signature (« designated requirement ») d'une app
  signée ainsi porte sur ce certificat, qui ne change pas d'une version à
  l'autre. Le trousseau, le signet et le conteneur de l'app reconnaissent donc
  chaque mise à jour comme la même app (vérifié sur Halo Compagnon). Signée ad
  hoc, l'app changerait d'identité à chaque version.
- **Gatekeeper** le traite comme une signature ad hoc : la première
  installation, depuis le navigateur, demande une autorisation dans Réglages
  Système ; les mises à jour installées par Sparkle sont garanties par la
  signature Ed25519 (choix du brief).
- **La validation des bibliothèques** (leçon du premier déploiement) : avec ce
  certificat, qui n'a pas d'équipe, le runtime renforcé empêche l'app de charger
  ses propres cadres (« different Team IDs ») : Maillage Thread et Halo
  Compagnon s'arrêtaient au lancement. `publication.py` signe donc l'app (l'app
  seulement, pas les services de Sparkle) avec, en plus des droits de Xcode,
  `com.apple.security.cs.disable-library-validation`, sans notarisation
  seulement ; toute autre exception `com.apple.security.cs.*` est refusée.
  Amaran Compagnon a, en plus de Sparkle, son propre cadre
  (`AmaranProtocole.framework`) : la répétition le vérifie.
- **`publication.py`** (copié à l'octet près de `Djoko-cli/maillage-thread`,
  dossier `outils/`, avec ses tests) cherche le certificat par son nom dans le
  trousseau ; rien de commité ne nomme l'équipe Apple de Djoko.
- **Les compilations de travail de Djoko** passent au même certificat
  (`Local.xcconfig`, ignoré par git : `CODE_SIGN_IDENTITY = Djoko-cli Code
  Signing`, sans équipe, runtime renforcé coupé, icône M2 gardée) : son app de
  travail et l'app installée ont alors la même identité, et passer de l'une à
  l'autre ne redemande rien. C'est un écart voulu au brief, où les compilations
  de travail restent ad hoc : chez Amaran, le trousseau porte les clés du Mesh.
  Au premier `codesign` avec le certificat, macOS demande l'accès à sa clé :
  « Toujours autoriser », sinon une compilation lancée par un agent resterait
  bloquée sur cette demande. Les tests restent ad hoc sans `Local.xcconfig`
  (dans une copie de travail neuve, par exemple).
- **Une fois, au passage :** l'app d'aujourd'hui est signée par l'équipe de
  Djoko. La première app signée par le certificat redemandera l'accès aux clés
  du trousseau (« Toujours autoriser »), et peut-être le dossier d'amaran
  Desktop ; ensuite plus rien.

La répétition (5) vérifie ces points avant toute publication.

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

`apps/macos/Outils/publier.sh X.Y.Z` et `publication.py`, repris de Halo
Compagnon (`publication.py` et ses tests identiques à l'octet, seuls les
arguments réglés), lancés depuis un clone neuf de GitHub :
`SPARKLE_BIN=<archive>/bin DD=<DerivedData à part> apps/macos/Outils/publier.sh X.Y.Z` ;
en cas d'arrêt à mi-chemin, reprise depuis
`build/publication/X.Y.Z/gestes.txt`, jamais en relançant le script.
Vérifications
(`main` propre et à jour, version nouvelle, tests verts : app, tests natifs,
outil), numéros (`MARKETING_VERSION` ; numéro de compilation = nombre de
commits de `main`), compilation Release signée par le certificat (2), `.dmg`
(`hdiutil`, l'app et un raccourci vers Applications), signature `sign_update`,
`appcast.xml` (système minimal macOS 15.0), contrôle d'anonymisation, étiquette
`compagnon-vX.Y.Z` et version publiée (`gh release create --target`, avec le
`.dmg`), `appcast.xml` commité sur `main`, copie sur le Bureau.

**La répétition, sans GitHub**, comme le brief (clé Ed25519 d'essai dans un
fichier, certificat d'essai dans un trousseau temporaire créé puis détruit,
jamais celui de Djoko ; serveur local sur 127.0.0.1 ; `sparkle-cli`). **Puis,
avant toute publication, l'app de la répétition est ouverte pour de vrai**
(`sparkle-cli` ne la lance jamais : la répétition a passé alors que les deux
autres apps s'arrêtaient au lancement), et « Rechercher les mises à jour… »
puis « Installer et relancer » se font dans l'app elle-même. Trois
vérifications propres à Amaran, sur une copie de l'app :
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
- **Avec Djoko, en vrai :** le certificat et la clé Ed25519 existent déjà ; installer depuis le `.dmg`
  du Bureau et passer Gatekeeper ; l'accès au trousseau et au dossier d'amaran
  Desktop au passage à la 1.0.0 ; le menu de mise à jour ; l'état de Thread
  Route.

## 7. Limites

- **La première installation** passe par Gatekeeper.
- **Le certificat** est valable 10 ans ; le renouveler change l'identité : une
  fois de plus, macOS redemandera l'accès au trousseau. Ne jamais perdre à la
  fois la clé Ed25519 et le certificat : Sparkle accepte de changer l'un des
  deux, pas les deux en même temps.
- **Une copie déjà installée par quelqu'un d'autre** ne se met à jour qu'à
  partir de la 1.0.0.
- **Le pont et sa console restent en français.**
