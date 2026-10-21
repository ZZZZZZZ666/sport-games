// BMI270 at 200 Hz: data-ready interrupt on INT1 (falls back to polling), timestamped samples.
#pragma once

#include <stdint.h>

struct ImuRawSample
{
    int64_t t_us;
    int16_t ax, ay, az;
    int16_t gx, gy, gz;
};

typedef void (*imu_sample_cb_t)(const ImuRawSample& s);

namespace imu
{
bool init();
/// Spawns the sampling task; `cb` runs on that task for every new sample.
void start(imu_sample_cb_t cb);
bool ok();
bool using_irq();
}  // namespace imu
