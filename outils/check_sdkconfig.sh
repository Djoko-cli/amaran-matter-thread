#!/usr/bin/env bash
# Verifie que chaque symbole des sdkconfig.defaults* existe dans les Kconfig
# d'ESP-IDF (et d'esp-matter si ESP_MATTER_PATH est pose). Un symbole inconnu
# est ignore EN SILENCE par idf.py. Repris du SmartButton.
#
# Usage : source ~/esp/esp-idf/export.sh, puis bash outils/check_sdkconfig.sh
set -u
: "${IDF_PATH:?source ~/esp/esp-idf/export.sh d abord}"
GREP=/usr/bin/grep
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNUS="$(mktemp)"
trap 'rm -f "$CONNUS"' EXIT

dossiers=("$IDF_PATH/components")
if [ -n "${ESP_MATTER_PATH:-}" ]; then
  dossiers+=("$ESP_MATTER_PATH/components" "$ESP_MATTER_PATH/device_hal"
             "$ESP_MATTER_PATH/connectedhomeip/connectedhomeip/config/esp32")
fi

{ find "$IDF_PATH" -maxdepth 1 -name 'Kconfig*' -type f -print0
  find "${dossiers[@]}" -name 'Kconfig*' -type f -print0 2>/dev/null; } \
  | xargs -0 "$GREP" -hoE '^[[:space:]]*(menu)?config[[:space:]]+[A-Z0-9_]+' 2>/dev/null \
  | awk '{print $NF}' | sort -u > "$CONNUS"
echo "$(wc -l < "$CONNUS" | tr -d ' ') symboles connus"

rc=0
for f in "$ICI"/ecoute/sdkconfig.defaults* "$ICI"/firmware/sdkconfig.defaults*; do
  [ -f "$f" ] || continue
  echo "-- ${f#"$ICI"/}"
  mauvais=0
  while IFS= read -r sym; do
    [ "$sym" = "IDF_TARGET" ] && continue  # pose par idf.py set-target
    if ! "$GREP" -qxF "$sym" "$CONNUS"; then
      echo "   x CONFIG_$sym : INCONNU (ignore en silence)"
      mauvais=$((mauvais + 1))
      rc=1
    fi
  done < <("$GREP" -oE '^CONFIG_[A-Z0-9_]+' "$f" | sed 's/^CONFIG_//' | sort -u)
  [ "$mauvais" -eq 0 ] && echo "   ok : tous les symboles existent"
done
exit $rc
