// The BMI270 and AXP202 share one I2C bus and are polled from different tasks.
#pragma once

#include <mutex>

inline std::mutex& i2c_bus_mutex()
{
    static std::mutex m;
    return m;
}
