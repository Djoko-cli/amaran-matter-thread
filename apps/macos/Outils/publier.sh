#!/bin/sh
# Publie une version d'Amaran Compagnon sur GitHub (spec du deploiement d'Amaran Compagnon, section 5 ; repris de
# Halo Compagnon) : verifications, numeros, compilation Release signee par le certificat de Djoko, .dmg signe par
# Sparkle (cle du trousseau), controle d'anonymisation, version publiee (etiquette compagnon-vX.Y.Z, avec le .dmg),
# puis le flux des mises a jour (apps/macos/appcast.xml, qui garde toutes les versions) commite sur main et pousse
# aussitot, .dmg sur le Bureau. Le .dmg porte aussi la licence de Sparkle 2.10.0 (Outils/Sparkle-LICENSE.txt, le
# fichier LICENSE de l'etiquette 2.10.0, entier) ; le commit du flux est signe Djoko-cli, a l'adresse noreply de GitHub.
# La logique est dans Outils/publication.py (identique a l'octet a celui de Maillage Thread et de Halo Compagnon),
# ses tests dans Outils/tests.
#   apps/macos/Outils/publier.sh X.Y.Z [--sans-bureau]
# La repetition, sans GitHub ni Bureau, avec la cle du trousseau, ou une paire d'essai :
#   apps/macos/Outils/publier.sh X.Y.Z --repetition DOSSIER --url-base URL [--cle-privee FICHIER --cle-publique CLE]
#                                      [--trousseau TROUSSEAU] [--sans-tests]
# SPARKLE_BIN : le dossier bin de l'archive de Sparkle 2.10.0 (sign_update, generate_keys), obligatoire hors repetition.
# NOTARISER=1 (desactive par defaut) : notarisation du .dmg, avec PROFIL_NOTARISATION, le profil que
# notarytool store-credentials a range dans le trousseau ; il faut alors un Developer ID pour IDENTITE_SIGNATURE.
# Produits : apps/macos/build/publication/X.Y.Z/ ; compilation dans DD (par defaut, a part :
# DerivedData/amaran-compagnon-publication). Le numero de compilation compte les commits de tout le depot.
# Les tests : l'app (francais, puis anglais), l'outil de publication, les tests natifs du pont et l'outil des cles.
set -eu
cd "$(dirname "$0")/.."
# L'identite de signature de la version publiee, a ce seul endroit : le certificat auto-signe de Djoko, trouve par
# son nom dans le trousseau.
IDENTITE_SIGNATURE=${IDENTITE_SIGNATURE:-Djoko-cli Code Signing}
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/amaran-compagnon-publication}
# Le numero de compilation compte les commits : un clone superficiel donnerait 1, que l'app prend pour une
# compilation de travail (jamais de mise a jour). Il faut un clone complet.
if [ "$(git rev-parse --is-shallow-repository)" != false ]; then
  echo "publier.sh : clone superficiel (ou hors git) ; publier depuis un clone complet" >&2
  exit 1
fi
export DD
exec /usr/bin/python3 Outils/publication.py publier "$@" --identite "$IDENTITE_SIGNATURE" \
  --auteur Djoko-cli --etiquette compagnon-v --flux appcast.xml --licence Outils/Sparkle-LICENSE.txt \
  --nom-app "Amaran Compagnon" --fichier Amaran-Compagnon --depot-github Djoko-cli/amaran-matter-thread \
  --projet AmaranCompagnon.xcodeproj --schema AmaranCompagnon --cible AmaranCompagnon \
  --test 'xcodegen generate --quiet && xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination platform=macOS -derivedDataPath "$DD" test' \
  --test 'xcodebuild -project AmaranCompagnon.xcodeproj -scheme AmaranCompagnon -destination platform=macOS -derivedDataPath "$DD" -testLanguage en -testRegion US test' \
  --test '/usr/bin/python3 -m unittest discover -s Outils/tests' \
  --test 'cd ../.. && sh tests/hote/lancer.sh && cd outils && /usr/bin/python3 -m unittest test_cles_amaran' \
  --textes AmaranCompagnon/Ressources/Localizable.xcstrings --textes AmaranCompagnon/Ressources/InfoPlist.xcstrings \
  --textes AmaranCompagnon/Ressources/Titres.xcstrings --textes AmaranProtocole/Localizable.xcstrings
