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
- **Réglages** (⌘,) : « Général » (dossier d'amaran Desktop, sauvegarde) et « Accès réseau Thread » (les ponts connus de ce Mac, avec leur empreinte et l'état de leur session, « Oublier… » ; pour le pont branché en USB, « Activer l'accès réseau… » ou « Nouvelle clé… »). La carte « Thread et Matter » du tableau de bord ouvre cet onglet.

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

## Structure

- `AmaranProtocole/` : le protocole, sans interface : tramage, session et corrélation (repris de Halo Compagnon), messages du pont, clés (base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison), `Reseau/` (enveloppe H1, clé UDP et état de l'accès réseau, erreurs du réseau, répertoire des ponts), `Transport/TransportUDP` (la session par Thread, reprise de Halo) et `Courbes/` (différences des compteurs et séries des graphiques).
- `AmaranCompagnon/` : l'app SwiftUI : port série, modèle `Pont`, trousseau des clés du Mesh, `Reseau/` (trousseau des ponts, alertes de la source réseau, état de session des ponts connus), écrans, mode démo.
- `AmaranProtocoleTests/`, `AmaranCompagnonTests/` : les tests. `ExemplesSpecTests` lit les exemples de `docs/PROTOCOLE-JSON.md`, que le firmware forme tels quels (`tests/hote/test_json.cpp`).
