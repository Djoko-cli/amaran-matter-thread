# Enveloppe H1 du transport reseau, reprise du pont Halo (commit e114cd5) :
# h1_proto.cpp est pur (teste sur le Mac, tests/hote/test_h1.cpp), h1_crypto.cpp
# fournit HMAC-SHA256 et SHA-256 par mbedTLS (SHA materiel du C6).
idf_component_register(SRCS "h1_proto.cpp" "h1_crypto.cpp"
                       INCLUDE_DIRS "include"
                       PRIV_REQUIRES mbedtls)
