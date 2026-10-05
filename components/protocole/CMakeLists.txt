# Protocole JSON du pont (docs/PROTOCOLE-JSON.md) : briques pures reprises du
# pont Halo (commit e114cd5) et messages du pont amaran. Teste sur le Mac
# (tests/hote/test_json.cpp). Pas "json" : c'est le nom du composant cJSON d'ESP-IDF.
idf_component_register(SRCS "json_ligne.cpp" "json_amaran.cpp"
                       INCLUDE_DIRS "include"
                       REQUIRES lampes liste)
