# Regina Sports controller firmware (ESP32-C6, ESP-IDF 5.1+).
cmake_minimum_required(VERSION 3.16)

# Drivers are external dependencies; the parent Regina workspace is not distributed.
# Prefer paths explicitly provided by the developer, then repository-local dependencies.
set(REGINA_M5GFX_DIR "$ENV{REGINA_M5GFX_DIR}")
set(REGINA_M5UNIFIED_DIR "$ENV{REGINA_M5UNIFIED_DIR}")
if(NOT REGINA_M5GFX_DIR)
    set(REGINA_M5GFX_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party/M5GFX")
    if(NOT EXISTS "${REGINA_M5GFX_DIR}/CMakeLists.txt")
        set(REGINA_M5GFX_DIR "${CMAKE_CURRENT_LIST_DIR}/../../dependencies/M5GFX")
    endif()
endif()
if(NOT REGINA_M5UNIFIED_DIR)
    set(REGINA_M5UNIFIED_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party/M5Unified")
    if(NOT EXISTS "${REGINA_M5UNIFIED_DIR}/CMakeLists.txt")
        set(REGINA_M5UNIFIED_DIR "${CMAKE_CURRENT_LIST_DIR}/../../platforms/regina/components/M5Unified")
    endif()
endif()
foreach(component IN ITEMS REGINA_M5GFX_DIR REGINA_M5UNIFIED_DIR)
    if(NOT EXISTS "${${component}}/CMakeLists.txt")
        message(FATAL_ERROR "Missing firmware dependency ${component}. See docs/DEVELOPMENT.md.")
    endif()
endforeach()
set(EXTRA_COMPONENT_DIRS "${REGINA_M5GFX_DIR}" "${REGINA_M5UNIFIED_DIR}")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(regina_sports_fw)
