# Amaran Compagnon

L'app macOS du pont amaran : supervision, commandes et console, par l'USB ou par le réseau Thread, et gestion des clés du réseau Bluetooth Mesh des lampes. Copie adaptée de Halo Compagnon (le pont BenQ Halo du même auteur). La spec : [docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md](../../docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) ; le protocole du pont : [docs/PROTOCOLE-JSON.md](../../docs/PROTOCOLE-JSON.md).

## Install · Installer

**English.** Download `Amaran-Compagnon-X.Y.Z.dmg` from the latest Amaran Compagnon
[release](https://github.com/Djoko-cli/amaran-matter-thread/releases) (`compagnon-vX.Y.Z`), open it, and drag
**Amaran Compagnon** onto **Applications**. macOS 15 or later.

- **First launch (Gatekeeper).** The app is signed with a self-signed certificate, `Djoko-cli Code Signing`, not
  with an Apple Developer ID, and isn't notarized. macOS refuses to open it the first time: in System Settings,
  Privacy & Security, click "Open Anyway" next to Amaran Compagnon, then confirm with your password (since macOS
  15, a right-click no longer does it). Only once.
- **Automatic updates** (Sparkle 2). The app checks for a new version at launch and then every 24 hours,
  downloads it, checks its Ed25519 signature, and installs it when the app quits, or right away with "Install and
  Relaunch". An update installed this way doesn't go back through Gatekeeper: the signature takes its place.
  "Check for Updates…" is in the Amaran Compagnon menu; Settings, General, "Updates", has "Check for updates
  automatically" and "Install updates automatically", both on by default.
- **Keychain and amaran Desktop folder.** Every published version is signed by the same certificate: an update
  keeps access to the copy of the Bluetooth Mesh keys and to the bridges' network keys in the keychain, and to
  the amaran Desktop folder chosen once. macOS asks again only when switching from a build signed differently
  (an ad hoc build, or one signed with an Apple team) to a published version: "Always Allow".
- **Thread Route.** The network source needs the Mac's route to the Thread network, which Thread Route keeps. It
  lives in the Halo bridge repository and installs from a copy of it:
  `sh tools/macos/thread-route/installer.sh` (administrator password). Settings, General, shows its status;
  if another app already installed it, nothing else is needed.

**Français.** Télécharger `Amaran-Compagnon-X.Y.Z.dmg` depuis la dernière
[version publiée](https://github.com/Djoko-cli/amaran-matter-thread/releases) d'Amaran Compagnon (`compagnon-vX.Y.Z`),
l'ouvrir, et glisser **Amaran Compagnon** sur **Applications**. macOS 15 ou plus.

- **Première ouverture (Gatekeeper).** L'app est signée par un certificat auto-signé, `Djoko-cli Code Signing`,
  sans Developer ID d'Apple ni notarisation. macOS refuse de l'ouvrir la première fois : dans Réglages Système,
  Confidentialité et sécurité, cliquer « Ouvrir quand même » en face d'Amaran Compagnon, puis confirmer avec son
  mot de passe (depuis macOS 15, le clic droit ne suffit plus). Une seule fois.
- **Mises à jour automatiques** (Sparkle 2). L'app recherche une nouvelle version au démarrage puis toutes les
  24 heures, la télécharge, vérifie sa signature Ed25519, et l'installe quand l'app se ferme, ou tout de suite par
  « Installer et relancer ». Une mise à jour installée ainsi ne repasse pas par Gatekeeper : la signature en tient
  lieu. « Rechercher les mises à jour… » est dans le menu Amaran Compagnon ; Réglages, Général, « Mises à jour »,
  porte « Rechercher automatiquement » et « Installer automatiquement », cochés par défaut.
- **Trousseau et dossier d'amaran Desktop.** Toutes les versions publiées sont signées par le même certificat :
  une mise à jour garde l'accès à la copie des clés du Bluetooth Mesh et aux clés réseau des ponts, dans le
  trousseau, et au dossier d'amaran Desktop choisi une fois. macOS ne redemande qu'au passage d'une compilation
  signée autrement (ad hoc, ou par une équipe Apple) à une version publiée : « Toujours autoriser ».
- **Thread Route.** La source réseau demande la route du Mac vers le réseau Thread, que garde Thread Route. Il vit
  dans le dépôt du pont Halo et s'installe depuis une copie de ce dépôt :
  `sh tools/macos/thread-route/installer.sh` (mot de passe administrateur). Réglages, Général, montre son état ;
  si une autre app l'a déjà installé, il n'y a rien d'autre à faire.

## Credits · Crédits

The app embeds [Sparkle](https://sparkle-project.org) 2.10.0 (automatic updates), under the MIT license; the text
of the license is shipped in the `.dmg`, next to the app (`Sparkle-LICENSE.txt`). · L'app embarque Sparkle 2.10.0
(les mises à jour automatiques), sous licence MIT ; le texte de la licence est livré dans le `.dmg`, à côté de
l'app.

## Publier

`Outils/publier.sh X.Y.Z` (spec du déploiement, section 5), depuis un clone neuf de GitHub :
`SPARKLE_BIN=<archive de Sparkle 2.10.0>/bin DD=<DerivedData à part> apps/macos/Outils/publier.sh X.Y.Z`. Il
vérifie `main`, lance les tests (l'app en français et en anglais, l'outil de publication, les tests natifs du pont,
l'outil des clés), compile en Release, signe l'app avec le certificat `Djoko-cli Code Signing`, crée le `.dmg`, le
signe pour Sparkle, passe le contrôle d'anonymisation, publie la version (`compagnon-vX.Y.Z`), commite le flux
(`appcast.xml`) sur `main` et copie le `.dmg` sur le Bureau. En cas d'arrêt à mi-chemin : reprendre depuis
`build/publication/X.Y.Z/gestes.txt`, jamais en relançant le script. Les notes viennent de `NOTES-VERSIONS.md`.
`publication.py` et ses tests sont ceux de Maillage Thread et de Halo Compagnon, à l'octet près.

## Compiler

Il faut Xcode 26 ou plus et XcodeGen (`brew install xcodegen`). Le projet Xcode est généré : `project.yml` fait foi. Une dépendance, Sparkle 2.10.0 (les mises à jour), par le gestionnaire de paquets Swift. Une compilation de travail (numéro de compilation 1) ne recherche jamais de mise à jour.

```bash
cd apps/macos
xcodegen generate
xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' build
```

Les tests (Swift Testing) :

```bash
xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination 'platform=macOS' test
```

Ils n'utilisent ni le pont ni le trousseau du Mac : le pont simulé du mode démo, un trousseau en mémoire, une base d'amaran Desktop factice. Le vrai trousseau ne sert que sur demande : `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild … test`.

## Écrans

- **Tableau de bord** : une carte par lampe, le Bluetooth Mesh, les clés, le voyant, le système, et « Thread et Matter », avec le bloc `ip` du pont (nom SRP, adresses OMR et ML-EID, canal UDP : clé, empreinte, ouvert, sessions, reçus, émis, rejets, perdus).
- Les cartes de lampe (tableau de bord, Commandes et console) montrent une ligne « Logiciel » (`1.4 (BLE 1.69)`) : les versions viennent de la base d'amaran Desktop (`control_software_version`, `ble_software_version`), passent par la copie du trousseau et par « Charger le pont » (jeton `v1.4/1.69` de `mesh lampe`, envoyé seulement si le pont annonce la capacité `logiciel`), et reviennent du pont dans le bloc `config` `lampe`. La carte Clés compare aussi les versions.
- **Graphiques** : par lampe, la part des relectures répondues et les délais des ordres ; pour le Mesh, les annonces, les NetMIC faux et les refus d'émission ; le tas libre. Fenêtre de 10 s ou 1 min, durée affichée au choix ; un redémarrage du pont ouvre un nouveau segment ; « Vider les courbes » n'efface que celles de l'app. Par le réseau, le pont n'envoie pas les compteurs du Mesh : un bouton les redemande (`json compteurs 5000`).
- **Trames** : le trafic Bluetooth Mesh décodé (ordres, demandes d'état, états reçus), en tableau, avec des filtres (sens, lampe, nature) et « Figer ». L'interrupteur « Trames du pont » envoie `json trames 1` ou `0` ; par le réseau, le pont coupe le flux seul au bout de 60 s : l'app l'indique et propose de relancer.
- **Commandes et console** : par le réseau, la console n'envoie que les commandes de la liste blanche du pont ; les autres ne partent pas, et la sortie texte d'une commande revient rattachée à son `id`.
- **Réglages** (⌘,) : « Général » (langue, dossier d'amaran Desktop, sauvegarde, mises à jour, état de Thread Route) et « Accès réseau Thread » (les ponts connus de ce Mac, avec leur empreinte et l'état de leur session, « Oublier… » ; pour le pont branché en USB, « Activer l'accès réseau… » ou « Nouvelle clé… »). La carte « Thread et Matter » du tableau de bord ouvre cet onglet.

## Accès par Thread

Le menu Source de la barre latérale propose, en plus des ports série, les ponts « Réseau » dont ce Mac a la clé. La clé UDP d'un pont se crée par l'USB (« Activer l'accès réseau… ») et se range dans le trousseau de ce Mac (service `fr.djoko.amaran.pont`, un compte par nom SRP) : elle n'est jamais affichée, seule son empreinte l'est. Chaque session s'ouvre par `json 1 bail 60`, sans Ctrl-U.

- **Droit réseau** : l'app est sandboxée, avec `com.apple.security.network.client` (`AmaranCompagnon.entitlements`), et `NSLocalNetworkUsageDescription` dans `project.yml`. À la première session, macOS demande l'accès au « Réseau local » ; s'il est refusé, un bandeau le dit (Réglages Système › Confidentialité et sécurité › Réseau local).
- **Route IPv6** : si macOS n'a pas de route vers le réseau Thread, la console et le panneau de connexion donnent l'état de Thread Route et ce qu'il reste à faire (Réglages, Général) ; l'app réessaie seule, sans bandeau, comme Halo.

## Signature

Par défaut, l'app est signée ad hoc : le dépôt compile partout, sans compte Apple. Mais une app ad hoc perd l'accès au trousseau, et au dossier d'amaran Desktop autorisé, à chaque compilation. Les versions publiées sont signées par le certificat auto-signé `Djoko-cli Code Signing` (`Outils/publier.sh`). Pour que le trousseau et le dossier tiennent d'une compilation à l'autre, et soient partagés avec la version installée, signer les compilations de travail avec le même certificat : créer `Local.xcconfig` (ignoré par git) à côté de `Signature.xcconfig` :

```
CODE_SIGN_IDENTITY = Djoko-cli Code Signing
DEVELOPMENT_TEAM =
```

Au premier codesign, macOS demande l'accès à la clé du certificat : « Toujours autoriser ». Le runtime renforcé reste coupé pour les compilations de travail (sans équipe, la validation des bibliothèques refuserait `AmaranProtocole.framework` et Sparkle) ; les versions publiées l'ont, avec la levée de cette validation pour l'app seule.

## Icône

Le dépôt porte une icône libre (A2 : une constellation qui trace un A, sur fond rouge), au format Icon Composer : `AmaranCompagnon/Ressources/AppIcon.icon`. Son calque se refait depuis `Outils/constellation-a.svg` :

```bash
rsvg-convert -w 1024 -h 1024 Outils/constellation-a.svg -o AmaranCompagnon/Ressources/AppIcon.icon/Assets/constellation-a.png
```

Une icône locale peut la remplacer sans être versionnée : la poser dans `AmaranCompagnon/Ressources/AppIconM2.icon` (ignoré par git), puis ajouter à `Local.xcconfig` :

```
ASSETCATALOG_COMPILER_APPICON_NAME = AppIconM2
```

et refaire `xcodegen generate`. Seule l'icône nommée entre dans l'app.

## Lancer

- `open "<DerivedData>/Build/Products/Debug/Amaran Compagnon.app" --args -demo` : démarre en mode démo (pont simulé à trois lampes, avec un bloc `ip` inventé et des trames sous `json trames 1`) ;
- `--args -ecran commandes` : ouvre l'écran des commandes (`tableau`, `graphiques`, `trames` ou `commandes`).

L'app ne s'ouvre jamais seule sur un port ni sur une session réseau : choisir le pont (VID 303A, ou un pont « Réseau ») dans le menu de la barre latérale, la connexion part aussitôt. Ensuite, « Connecter » vise ce même pont, reconnu à son numéro de série USB, jamais un autre port Espressif ; tant qu'aucun pont n'a été choisi au menu, il reste grisé. Ouvrir le port ne redémarre pas le pont : DTR et RTS passent à 0 en un seul appel. « Libérer le port » rend la console texte au pont (`json 0`) et ferme le port, pour flasher.

## Langues

L'app parle français (langue de développement : les clés des catalogues sont les textes français) et anglais. **Réglages** (⌘,) › **Général** › **Langue** : « Langue du système » (par défaut), *English* ou *Français* ; le choix est gardé dans les préférences de l'app (`langue`).

- **À chaud** : le contenu des fenêtres change aussitôt, sans relancer l'app ni perdre l'écran, les filtres ou la console. Les vues (`Text("...")`) lisent la locale de l'environnement ; les textes calculés (sens décodé, libellés, erreurs, notes, menus) passent par `Localisation` (framework `AmaranProtocole`, observable) : une vue qui en a lu un se redessine.
- **Au prochain lancement** : ce que macOS dessine lui-même (menus de l'app, Édition, Fenêtre, boîtes du système), qui suit `AppleLanguages` de l'app ; le choix l'écrit, et les Réglages le disent. Réglages Système (Langue et région › Applications) écrit au même endroit : la valeur d'avant le premier choix *English*/*Français* est gardée (`AppleLanguagesAvantChoix`) et rendue par « Langue du système ».
- **Gardent leur langue jusqu'au texte suivant** : les lignes déjà écrites dans la console (c'est un journal), la raison d'une reconnexion ou d'une erreur de port, la dernière ligne rejetée et l'erreur de saisie de la console.
- **Ce qui vient du pont n'est jamais traduit** : la console du pont, ses messages `texte`, le `msg` de ses réponses (dont la raison d'un refus de la liste blanche), les noms des lampes, les commandes tapées. L'app les montre tels quels. Restent aussi en français : les traces de débogage du transport réseau (`AMARAN_DEBUG_RESEAU`), le libellé et le commentaire des éléments du trousseau, et le nom de fichier proposé pour une sauvegarde.
- **Termes techniques inchangés** dans les deux langues : champs JSON, commandes (`mesh lampe 2 masquer`), hexa, unités, « Matter », « Thread », « Bluetooth Mesh », « amaran Desktop ». « Maison » devient « Apple Home » en anglais. Casse : phrase en français ; en anglais, *Title Case* pour les titres (écrans, cartes, sections, menus, boutons, alertes), casse de phrase pour le corps, les libellés de ligne et les pastilles.
- **Formats** (heures, nombres, octets, dates relatives) : la langue choisie avec la région de l'utilisateur, comme macOS le fait pour une langue choisie app par app. Identifiants (`id`), ports, versions et durées en ms restent sans séparateur de milliers.

Catalogues (String Catalogs) : `AmaranProtocole/Localizable.xcstrings` (framework : sens décodé, libellés, erreurs, notes de session), `AmaranCompagnon/Ressources/Localizable.xcstrings` (app), `Titres.xcstrings` (titres de section dont le français sert déjà de libellé, avec une autre casse anglaise) et `InfoPlist.xcstrings` (message de l'autorisation du réseau local). Les clés sont extraites par le compilateur (`SWIFT_EMIT_LOC_STRINGS`) : Xcode les ajoute en compilant ; en ligne de commande, après un changement de texte :

```bash
I=<DerivedData>/Build/Intermediates.noindex/AmaranCompagnon.build/Debug
xcrun xcstringstool sync AmaranProtocole/Localizable.xcstrings \
    --stringsdata $I/AmaranProtocole.build/Objects-normal/arm64/*.stringsdata
xcrun xcstringstool sync AmaranCompagnon/Ressources/Localizable.xcstrings AmaranCompagnon/Ressources/Titres.xcstrings \
    --stringsdata $I/AmaranCompagnon.build/Objects-normal/arm64/*.stringsdata
python3 Outils/traduire.py AmaranProtocole/Localizable.xcstrings traductions.json
```

puis traduire les nouvelles clés (`Outils/traduire.py` écrit les traductions d'un fichier JSON `{"clé française": "anglais"}` au format de Xcode et retire les clés périmées). Les tests (`LocalisationTests`, `LangueTests`) vérifient que chaque clé a son anglais (pluriels complets, mêmes valeurs interpolées), qu'aucune n'est périmée, que le code et les catalogues sont d'accord, et que le réglage choisit la bonne locale. Les tests qui comparent des textes français portent `.langue(.francais)` ; pour essayer toute l'app dans l'autre langue : `xcodebuild … test -testLanguage en -testRegion US`.

## Structure

- `AmaranProtocole/` : le protocole, sans interface : `Localisation/` (langue en vigueur et textes localisés, avec son catalogue), tramage, session et corrélation (repris de Halo Compagnon), messages du pont, clés (base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison), `Reseau/` (enveloppe H1, clé UDP et état de l'accès réseau, erreurs du réseau, répertoire des ponts), `Transport/TransportUDP` (la session par Thread, reprise de Halo) et `Courbes/` (différences des compteurs et séries des graphiques).
- `AmaranCompagnon/` : l'app SwiftUI : port série, modèle `Pont`, trousseau des clés du Mesh, `Reseau/` (trousseau des ponts, alertes de la source réseau, état de session des ponts connus), écrans, mode démo.
- `Outils/traduire.py` : les traductions des catalogues (voir « Langues »).
- `AmaranProtocoleTests/`, `AmaranCompagnonTests/` : les tests. `ExemplesSpecTests` lit les exemples de `docs/PROTOCOLE-JSON.md`, que le firmware forme tels quels (`tests/hote/test_json.cpp`).
