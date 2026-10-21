// BLE wire format v1. Keep in sync with docs/protocol.md and hub/regina_hub/protocol.py.
#pragma once

#include <stdint.h>

#define FW_VERSION_MAJOR 0
#define FW_VERSION_MINOR 2

// UUIDs 5253a00X-6a2e-4c1f-9b7e-726567696e61, little-endian byte order for NimBLE.
#define RS_UUID128(x) \
    0x61, 0x6e, 0x69, 0x67, 0x65, 0x72, 0x7e, 0x9b, 0x1f, 0x4c, 0x2e, 0x6a, (x), 0xa0, 0x53, 0x52

#define PKT_IMU 0x01
#define PKT_INPUT 0x02
#define PKT_STATUS 0x03

#define OP_SET_PLAYER 0x01
#define OP_BEEP 0x04
#define OP_VIBRATE 0x05
#define OP_SET_ROTATION 0x06  // u8 0..3: LovyanGFX rotation, 1/3 = portrait
#define OP_UI 0x10

#define UI_CLEAR 0x00
#define UI_TITLE 0x01
#define UI_MAIN 0x02
#define UI_SUB 0x03
#define UI_BAR 0x04
#define UI_LEGEND_A 0x05
#define UI_TOAST 0x09
#define UI_BAR_HIDDEN 255

#define IMU_SAMPLES_PER_PACKET 4
#define IMU_RANGES_BYTE 0x02  // accel +-8 g (2), gyro +-2000 dps (0 << 2)

#pragma pack(push, 1)
typedef struct
{
    uint16_t dt_us;
    int16_t ax, ay, az;
    int16_t gx, gy, gz;
} imu_sample_t;

typedef struct
{
    uint8_t type;
    uint8_t seq;
    uint8_t count;
    uint8_t ranges;
    uint32_t t0_us;
    imu_sample_t samples[IMU_SAMPLES_PER_PACKET];
} imu_packet_t;

typedef struct
{
    uint8_t type;
    uint8_t buttons;
    int16_t dial_small;
    int16_t dial_big;
    uint32_t t_us;
} input_packet_t;

typedef struct
{
    uint8_t type;
    uint8_t battery;  // 255 = unknown
    uint8_t flags;    // bit0 charging, bit1 imu ok, bit2 imu drdy irq
    uint8_t fw_major;
    uint8_t fw_minor;
    uint8_t player;
} status_packet_t;
#pragma pack(pop)

#ifdef __cplusplus
#define RS_STATIC_ASSERT static_assert
#else
#define RS_STATIC_ASSERT _Static_assert
#endif
RS_STATIC_ASSERT(sizeof(imu_sample_t) == 14, "imu sample layout");
RS_STATIC_ASSERT(sizeof(input_packet_t) == 10, "input packet layout");
RS_STATIC_ASSERT(sizeof(status_packet_t) == 6, "status packet layout");
