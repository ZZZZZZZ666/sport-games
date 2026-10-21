// Regina PCB pin map (from platforms/regina/main/hal_regina/hal_config.h).
#pragma once

// OLED (SH1106, SPI)
#define PIN_OLED_CS 9
#define PIN_OLED_DC 18
#define PIN_OLED_RST 19
#define PIN_OLED_SDA 20
#define PIN_OLED_SCL 21

// Buttons, active low
#define PIN_BTN_A 16
#define PIN_BTN_B 3
#define PIN_BTN_C 2
#define PIN_BTN_D 8

// Two 16-step encoders read through a parallel-in/serial-out shift register
#define PIN_DIAL_CE 0
#define PIN_DIAL_PL 6
#define PIN_DIAL_CLK 7
#define PIN_DIAL_DATA 1

// Internal I2C: BMI270 (0x68), AXP202 (0x34), RTC
#define PIN_I2C_SCL 10
#define PIN_I2C_SDA 11

#define PIN_BUZZER 22
// Buzzer muted for now: set to 1 to let the hub / game beep again.
#define BUZZER_ENABLED 0
// Show a full-white frame, then a border/diagonal test pattern for ~3 s at boot.
#define DISPLAY_BOOT_TEST 0

#define PIN_IMU_INT1 23
#define PIN_IMU_INT2 17
