// Passive buzzer on LEDC; non-blocking beeps.
#pragma once

#include <stdint.h>

namespace buzzer
{
void init();
void beep(uint16_t freq_hz, uint16_t ms);
}  // namespace buzzer
