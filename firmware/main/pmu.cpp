#include "pmu.h"

#include <utility/I2C_Class.hpp>

#include "esp_log.h"
#include "i2c_bus.h"

static const char* TAG = "pmu";

namespace
{
class Axp202 : public m5::I2C_Device
{
public:
    Axp202() : m5::I2C_Device(0x34, 400000, &m5::In_I2C) {}

    bool probe() { return readRegister8(0x03) == 0x41; }

    void clear_irq()
    {
        for (uint8_t r = 0x48; r < 0x4D; ++r)
            writeRegister8(r, 0xFF);
    }

    uint8_t percent() { return readRegister8(0xB9) & 0x7F; }
    bool charging() { return readRegister8(0x01) & 0x40; }
};

Axp202* s_pmu = nullptr;
}  // namespace

namespace pmu
{
bool init()
{
    std::lock_guard<std::mutex> lock(i2c_bus_mutex());
    auto* p = new Axp202();
    if (!p->probe())
    {
        ESP_LOGE(TAG, "AXP202 not found");
        delete p;
        return false;
    }
    p->clear_irq();
    s_pmu = p;
    return true;
}

uint8_t battery_percent()
{
    if (s_pmu == nullptr)
        return 255;
    std::lock_guard<std::mutex> lock(i2c_bus_mutex());
    uint8_t v = s_pmu->percent();
    return v > 100 ? 100 : v;
}

bool charging()
{
    if (s_pmu == nullptr)
        return false;
    std::lock_guard<std::mutex> lock(i2c_bus_mutex());
    return s_pmu->charging();
}
}  // namespace pmu
