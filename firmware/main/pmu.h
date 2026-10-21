// AXP202 power management: battery percentage and charging state.
#pragma once

#include <stdint.h>

namespace pmu
{
bool init();
/// 0..100, or 255 when the PMU is missing.
uint8_t battery_percent();
bool charging();
}  // namespace pmu
