# Logique pure du socle, reprise du pont Halo (commit 3f82f76) : voyant et
# bouton BOOT. Testee sur le Mac (tests/hote/test_socle.cpp).
idf_component_register(SRCS "status_led.cpp" "boot_button.cpp"
                       INCLUDE_DIRS "include")
