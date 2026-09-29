# Le composant main depend de tous les autres (regle d'ESP-IDF).
idf_component_register(SRCS "app_main.c"
                       INCLUDE_DIRS ".")
