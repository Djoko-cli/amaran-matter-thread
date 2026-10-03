idf_component_register(
    SRCS "texte.c" "crochet_tri.c" "config_amaran.c" "hote_ble.c" "crochet.c" "plancher.c" "mesh_amaran.c" "mesh_console.c" "diagnostic.c" "autotest.c"
    INCLUDE_DIRS "include"
    PRIV_INCLUDE_DIRS
        "."
        # En-tetes internes de la pile Bluetooth Mesh : aucune API publique ne
        # permet d'entrer dans un reseau existant ni de dechiffrer a cote.
        "${IDF_PATH}/components/bt/esp_ble_mesh/core/include"
        "${IDF_PATH}/components/bt/esp_ble_mesh/core"
        "${IDF_PATH}/components/bt/esp_ble_mesh/common/include"
    REQUIRES telink liste
    PRIV_REQUIRES nvs_flash mbedtls bt esp_timer console)

# Crochet de reception (spec 5.5) : la pile appelle nos enveloppes a la place
# de ses propres fonctions, sans que rien ne soit modifie dans ESP-IDF.
target_link_libraries(${COMPONENT_LIB} INTERFACE
    "-Wl,--wrap=bt_mesh_generic_net_recv"
    "-Wl,--wrap=bt_mesh_beacon_recv")
