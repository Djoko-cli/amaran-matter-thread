#!/bin/sh
# Tests sur le Mac, sans carte. Depuis la racine du depot : sh tests/hote/lancer.sh
set -eu
cd "$(dirname "$0")/../.."
SORTIE="${TMPDIR:-/tmp}/amaran-tests-hote"
mkdir -p "$SORTIE"
CC="${CC:-clang}"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Icomponents/mesh -Icomponents/lampes/include -Icomponents/liste/include -Itests/hote"

compiler_et_lancer() {
  nom="$1"
  shift
  # shellcheck disable=SC2086
  "$CC" $CFLAGS "$@" -o "$SORTIE/$nom"
  "$SORTIE/$nom"
}

compiler_et_lancer test_telink components/telink/telink.c tests/hote/test_telink.c
compiler_et_lancer test_texte components/mesh/texte.c tests/hote/test_texte.c
compiler_et_lancer test_crochet_tri components/telink/telink.c components/mesh/texte.c components/mesh/crochet_tri.c tests/hote/test_crochet_tri.c
compiler_et_lancer test_plancher components/mesh/plancher.c tests/hote/test_plancher.c
compiler_et_lancer test_lampes components/telink/telink.c components/lampes/lampes.c tests/hote/test_lampes.c
compiler_et_lancer test_diagnostic components/mesh/diagnostic.c tests/hote/test_diagnostic.c
compiler_et_lancer test_liste components/liste/liste.c components/liste/catalogue.c tests/hote/test_liste.c

# Socle repris du Halo : C++17, comme ses tests d'origine.
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/socle/include components/socle/status_led.cpp \
  components/socle/boot_button.cpp tests/hote/test_socle.cpp -o "$SORTIE/test_socle"
"$SORTIE/test_socle"

# Protocole JSON (components/protocole) : C++17, avec le catalogue (C) ; lit les exemples
# de docs/PROTOCOLE-JSON.md. La liste blanche est jugee sur la ligne decoupee par la vraie
# fonction de la console d'ESP-IDF (split_argv.c, compilee ici, jamais modifiee).
SPLIT_ARGV="${IDF_PATH:-$HOME/esp/esp-idf}/components/console/split_argv.c"
if [ ! -f "$SPLIT_ARGV" ]; then
  echo "introuvable : $SPLIT_ARGV (ESP-IDF 5.5.4 dans ~/esp/esp-idf, ou IDF_PATH)" >&2
  exit 1
fi
"$CC" $CFLAGS -c components/liste/catalogue.c -o "$SORTIE/catalogue.o"
"$CC" -std=c11 -Wall -Wextra -Werror -c "$SPLIT_ARGV" -o "$SORTIE/split_argv.o"
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/protocole/include -Icomponents/liste/include \
  -Icomponents/lampes/include -Icomponents/telink/include components/protocole/json_ligne.cpp \
  components/protocole/json_amaran.cpp tests/hote/test_json.cpp "$SORTIE/catalogue.o" "$SORTIE/split_argv.o" \
  -o "$SORTIE/test_json"
"$SORTIE/test_json"

# Enveloppe H1 du transport reseau (components/h1) : C++17, crypto de CommonCrypto.
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/h1/include components/h1/h1_proto.cpp \
  tests/hote/test_h1.cpp -o "$SORTIE/test_h1"
"$SORTIE/test_h1"

echo "tests hote : tout est vert"
