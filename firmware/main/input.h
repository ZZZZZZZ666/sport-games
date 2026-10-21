// Buttons A-D (active low) and the two encoders (via shift register), sampled every 10 ms.
#pragma once

#include <stdint.h>

struct InputState
{
    uint8_t buttons;     // bit0 A, bit1 B, bit2 C, bit3 D
    int16_t dial_small;  // dial A in the original firmware
    int16_t dial_big;    // dial B
};

namespace input
{
void init(bool dial_small_swapped = false, bool dial_big_swapped = false);
/// Call every ~10 ms. Returns true when the debounced state changed.
bool update(InputState& out);
}  // namespace input
