# Amaran Compagnon

L'app macOS du pont amaran : supervision, commandes et console par l'USB, et gestion des clés du réseau Bluetooth Mesh des lampes. Copie adaptée de Halo Compagnon (le pont BenQ Halo du même auteur). La spec : [docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md](../../docs/superpowers/specs/2026-10-05-pont-amaran-app-compagnon-design.md) ; le protocole du pont : [docs/PROTOCOLE-JSON.md](../../docs/PROTOCOLE-JSON.md).

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

- `open "<DerivedData>/Build/Products/Debug/Amaran Compagnon.app" --args -demo` : démarre en mode démo (pont simulé à trois lampes) ;
- `--args -ecran commandes` : ouvre l'écran des commandes.

L'app ne s'ouvre jamais seule sur un port : choisir le pont (VID 303A) dans le menu de la barre latérale, la connexion part aussitôt. Ensuite, « Connecter » vise ce même pont, reconnu à son numéro de série USB, jamais un autre port Espressif. Ouvrir le port ne redémarre pas le pont : DTR et RTS passent à 0 en un seul appel. « Libérer le port » rend la console texte au pont (`json 0`) et ferme le port, pour flasher.

## Structure

- `AmaranProtocole/` : le protocole, sans interface : tramage, session et corrélation (repris de Halo Compagnon), messages du pont, clés (base d'amaran Desktop, sauvegarde chiffrée, chargement, comparaison).
- `AmaranCompagnon/` : l'app SwiftUI : port série, modèle `Pont`, trousseau, écrans, mode démo.
- `AmaranProtocoleTests/`, `AmaranCompagnonTests/` : les tests. `ExemplesSpecTests` lit les exemples de `docs/PROTOCOLE-JSON.md`, que le firmware forme tels quels (`tests/hote/test_json.cpp`).
