// NimBLE GATT peripheral for the Regina Sports service (C so the GATT tables can use C99 literals).
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ble_cmd_cb_t)(const uint8_t* data, uint16_t len);

/// Starts the host task and advertising as `name`. `on_command` runs on the NimBLE host task.
void ble_service_start(const char* name, ble_cmd_cb_t on_command);

bool ble_service_connected(void);
uint16_t ble_service_mtu(void);

/// Notify if the central subscribed; returns false if not connected/subscribed or out of buffers.
bool ble_service_notify_imu(const void* data, uint16_t len);
/// Store the latest value for reads and notify it if subscribed.
bool ble_service_update_input(const void* data, uint16_t len);
bool ble_service_update_status(const void* data, uint16_t len);

#ifdef __cplusplus
}
#endif
