idf_component_register(
    SRCS "texte.c" "crochet_tri.c" "config_amaran.c" "hote_ble.c" "crochet.c" "mesh_amaran.c"
    INCLUDE_DIRS "include"
    PRIV_INCLUDE_DIRS
        "."
        # En-tetes internes de la pile Bluetooth Mesh : aucune API publique ne
        # permet d'entrer dans un reseau existant ni de dechiffrer a cote.
        "${IDF_PATH}/components/bt/esp_ble_mesh/core/include"
        "${IDF_PATH}/components/bt/esp_ble_mesh/core"
        "${IDF_PATH}/components/bt/esp_ble_mesh/common/include"
    REQUIRES telink
    PRIV_REQUIRES nvs_flash mbedtls bt esp_timer)
