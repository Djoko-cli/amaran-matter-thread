idf_component_register(SRCS "texte.c" "crochet_tri.c" "config_amaran.c"
                       INCLUDE_DIRS "include"
                       REQUIRES telink
                       PRIV_REQUIRES nvs_flash mbedtls)
