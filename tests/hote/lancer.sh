#!/bin/sh
# Tests sur le Mac, sans carte. Depuis la racine du depot : sh tests/hote/lancer.sh
set -eu
cd "$(dirname "$0")/../.."
SORTIE="${TMPDIR:-/tmp}/amaran-tests-hote"
mkdir -p "$SORTIE"
CC="${CC:-clang}"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Icomponents/telink/include -Icomponents/mesh/include -Itests/hote"

compiler_et_lancer() {
  nom="$1"
  shift
  # shellcheck disable=SC2086
  "$CC" $CFLAGS "$@" -o "$SORTIE/$nom"
  "$SORTIE/$nom"
}

compiler_et_lancer test_telink components/telink/telink.c tests/hote/test_telink.c
echo "tests hote : tout est vert"
