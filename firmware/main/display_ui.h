// 128x64 OLED: renders the game-driven UI described in docs/protocol.md section 2.5,
// in portrait (rotation 1/3, the usual upright grip) or landscape (0/2).
// Layout must match game/core/oled_preview.gd.
#pragma once

#include <stdint.h>

namespace display_ui
{
void init(const char* device_name, uint8_t rotation);
/// LovyanGFX rotation 0..3; 1 and 3 are portrait. Thread-safe.
void set_rotation(uint8_t rotation);
/// Apply a UI command payload (bytes after the OP_UI opcode). Thread-safe.
void apply_tlv(const uint8_t* data, uint16_t len);
void set_player(uint8_t player);
void set_connected(bool connected);
void set_battery(uint8_t percent, bool charging);
void set_buttons(uint8_t buttons);
void toast(const char* text, uint16_t ms);
/// Redraws if anything changed (or a toast expired / battery blinks). Call ~20-30 Hz.
void tick();
}  // namespace display_ui
