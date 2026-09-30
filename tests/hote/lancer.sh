#!/bin/sh
# Tests sur le Mac, sans carte. Depuis la racine du depot : sh tests/hote/lancer.sh
set -eu
cd "$(dirname "$0")/../.."
SORTIE="${TMPDIR:-/tmp}/amaran-tests-hote"
mkdir -p "$SORTIE"
CC="${CC:-clang}"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Icomponents/mesh -Icomponents/lampes/include -Itests/hote"

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

# Socle repris du Halo : C++17, comme ses tests d'origine.
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -Icomponents/socle/include components/socle/status_led.cpp \
  components/socle/boot_button.cpp tests/hote/test_socle.cpp -o "$SORTIE/test_socle"
"$SORTIE/test_socle"

echo "tests hote : tout est vert"
