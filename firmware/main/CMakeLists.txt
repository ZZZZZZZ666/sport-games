idf_component_register(
    SRCS
        "main.cpp"
        "imu.cpp"
        "input.cpp"
        "pmu.cpp"
        "buzzer.cpp"
        "display_ui.cpp"
        "ble_service.c"
    INCLUDE_DIRS "."
    REQUIRES bt nvs_flash driver esp_timer M5GFX M5Unified
)
