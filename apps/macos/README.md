# Amaran Compagnon

L'app macOS du pont amaran : supervision, commandes et console, par l'USB ou par le réseau Thread, et gestion des clés du réseau Bluetooth Mesh des lampes. Copie adaptée de Halo Compagnon (le pont BenQ Halo du même auteur). La spec : [docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md](../../docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) ; le protocole du pont : [docs/PROTOCOLE-JSON.md](../../docs/PROTOCOLE-JSON.md).

## Compiler

Il faut Xcode 26 ou plus et XcodeGen (`brew install xcodegen`). Le projet Xcode est généré : `project.yml` fait foi.

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
- **Réglages** (⌘,) : « Général » (langue, dossier d'amaran Desktop, sauvegarde) et « Accès réseau Thread » (les ponts connus de ce Mac, avec leur empreinte et l'état de leur session, « Oublier… » ; pour le pont branché en USB, « Activer l'accès réseau… » ou « Nouvelle clé… »). La carte « Thread et Matter » du tableau de bord ouvre cet onglet.

## Accès par Thread

Le menu Source de la barre latérale propose, en plus des ports série, les ponts « Réseau » dont ce Mac a la clé. La clé UDP d'un pont se crée par l'USB (« Activer l'accès réseau… ») et se range dans le trousseau de ce Mac (service `fr.djoko.amaran.pont`, un compte par nom SRP) : elle n'est jamais affichée, seule son empreinte l'est. Chaque session s'ouvre par `json 1 bail 60`, sans Ctrl-U.

- **Droit réseau** : l'app est sandboxée, avec `com.apple.security.network.client` (`AmaranCompagnon.entitlements`), et `NSLocalNetworkUsageDescription` dans `project.yml`. À la première session, macOS demande l'accès au « Réseau local » ; s'il est refusé, un bandeau le dit (Réglages Système › Confidentialité et sécurité › Réseau local).
- **Route IPv6** : si macOS n'a pas de route vers le réseau Thread, la console et le panneau de connexion pointent vers l'assistant `halo-routes` du dépôt de Halo ; l'app réessaie seule, sans bandeau, comme Halo.

## Signature

Par défaut, l'app est signée ad hoc : le dépôt compile partout, sans compte Apple. Mais une app ad hoc perd l'accès au trousseau, et au dossier d'amaran Desktop autorisé, à chaque compilation. Pour qu'ils tiennent, signer avec son équipe : créer `Local.xcconfig` (ignoré par git) à côté de `Signature.xcconfig` :

```
DEVELOPMENT_TEAM = <équipe, 10 caractères>
CODE_SIGN_IDENTITY = Apple Development
ENABLE_HARDENED_RUNTIME = YES
```

L'équipe : `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject` (champ OU). Un compte développeur gratuit suffit : l'app n'a aucun droit restreint.

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
