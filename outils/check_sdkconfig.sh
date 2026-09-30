#!/usr/bin/env bash
# Verifie que chaque symbole des sdkconfig.defaults* existe dans les Kconfig
# d'ESP-IDF (et d'esp-matter si ESP_MATTER_PATH est pose). Un symbole inconnu
# est ignore EN SILENCE par idf.py. Repris du SmartButton.
# Verifie aussi, pour chaque sdkconfig genere (ecoute, firmware), que la pile
# Mesh n'est pas reglee au-dessus du niveau de trace ERROR (elle imprimerait des cles).
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

# Valeur epinglee, lue dans le sdkconfig genere (ignore par git) de chaque
# firmware : au-dessus d'ERROR la pile Mesh imprime des cles (voir
# components/mesh/mesh_amaran.c). sdkconfig.defaults ne pese que sur les symboles
# absents de sdkconfig : une valeur plus ancienne, ou posee par menuconfig,
# l'emporterait en silence.
for projet in ecoute firmware; do
  SDKCONFIG="$ICI/$projet/sdkconfig"
  echo "-- $projet/sdkconfig (niveau de trace de la pile Mesh)"
  if [ ! -f "$SDKCONFIG" ]; then
    echo "   sdkconfig absent (pas encore genere) : rien a verifier ici, mesh_amaran.c garde la compilation"
  elif "$GREP" -qx 'CONFIG_BLE_MESH_NO_LOG=y' "$SDKCONFIG"; then
    echo "   ok : BLE_MESH_NO_LOG, la pile n'imprime rien (mais l'erreur \"IVIndex out of sync\" disparait, spec 5.3)"
  else
    niveau="$("$GREP" -E '^CONFIG_BLE_MESH_STACK_TRACE_LEVEL=[0-9]+$' "$SDKCONFIG" | cut -d= -f2)"
    if [ -z "$niveau" ]; then
      echo "   x CONFIG_BLE_MESH_STACK_TRACE_LEVEL : introuvable dans $projet/sdkconfig"
      rc=1
    elif [ "$niveau" -gt 1 ]; then
      echo "   x CONFIG_BLE_MESH_STACK_TRACE_LEVEL=$niveau : au-dessus d'ERROR (1), la pile imprime des cles"
      rc=1
    else
      echo "   ok : niveau $niveau (0 NONE, 1 ERROR) : la pile n'imprime aucune cle"
    fi
  fi
done
exit $rc
