cmake_minimum_required(VERSION 3.16)
# Firmware du pont (plan 2) : Matter sur Thread et Bluetooth Mesh sur une C6,
# ESP-IDF v5.5.4 + esp-matter (~/esp). Structure des exemples d'esp-matter et
# du SmartButton.
if(NOT DEFINED ENV{ESP_MATTER_PATH})
  message(FATAL_ERROR "ESP_MATTER_PATH absent : sourcer ~/esp/esp-matter/export.sh")
endif()

# Version montree dans Maison (« Programme interne ») : 0.1.0-<commit>[-dirty],
# 31 caracteres au plus (esp_app_desc). Calculee a la configuration, refaite a
# chaque commit (dependance sur .git/logs/HEAD).
execute_process(COMMAND git --no-optional-locks rev-parse --short=7 HEAD
                WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
                OUTPUT_VARIABLE REV OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE REV_RC)
if(NOT REV_RC EQUAL 0 OR REV STREQUAL "")
  set(REV "nogit")
endif()
execute_process(COMMAND git --no-optional-locks status --porcelain --untracked-files=no
                WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
                OUTPUT_VARIABLE SALE OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(NOT SALE STREQUAL "")
  set(REV "${REV}-dirty")
endif()
set(PROJECT_VER "0.1.0-${REV}")
set(PROJECT_VER_NUMBER 1)
if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../.git/logs/HEAD")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/../.git/logs/HEAD")
endif()

set(ESP_MATTER_PATH $ENV{ESP_MATTER_PATH})
set(MATTER_SDK_PATH ${ESP_MATTER_PATH}/connectedhomeip/connectedhomeip)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
set(EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_LIST_DIR}/../components"
    "${MATTER_SDK_PATH}/config/esp32/components"
    "${ESP_MATTER_PATH}/components")
project(amaran_pont)

idf_build_set_property(CXX_COMPILE_OPTIONS "-std=gnu++17;-Os;-DCHIP_HAVE_CONFIG_H;-Wno-overloaded-virtual" APPEND)
idf_build_set_property(C_COMPILE_OPTIONS "-Os" APPEND)
idf_build_set_property(COMPILE_OPTIONS "-Wno-format-nonliteral;-Wno-format-security" APPEND)
# Transitions de LevelControl immediates : sinon chaque pas d'une transition
# rappellerait l'application, et partirait vers la lampe.
idf_build_set_property(COMPILE_DEFINITIONS "IGNORE_LEVEL_CONTROL_CLUSTER_TRANSITION" APPEND)
