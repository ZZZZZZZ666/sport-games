#include "imu.h"

#include <utility/I2C_Class.hpp>
#include <utility/imu/BMI270_Class.hpp>

#include "board.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "i2c_bus.h"

static const char* TAG = "imu";

namespace
{
constexpr uint8_t REG_ACC_RANGE = 0x41;
constexpr uint8_t REG_GYR_RANGE = 0x43;
constexpr int64_t MIN_SAMPLE_GAP_US = 2500;  // drdy may pulse for acc and gyr separately

class ReginaBmi270 : public m5::BMI270_Class
{
public:
    explicit ReginaBmi270(uint8_t addr) : m5::BMI270_Class(addr, 400000, &m5::In_I2C) {}

    void configure()
    {
        writeRegister8(ACC_CONF_ADDR, 0xA9);   // ODR 200 Hz, normal bandwidth, performance mode
        writeRegister8(REG_ACC_RANGE, 0x02);   // +-8 g
        writeRegister8(GYR_CONF_ADDR, 0xE9);   // ODR 200 Hz, normal bandwidth, noise+filter performance
        writeRegister8(REG_GYR_RANGE, 0x00);   // +-2000 dps
        writeRegister8(PWR_CTRL_ADDR, 0x0E);   // acc + gyr + temp on, aux off
        writeRegister8(INT1_IO_CTRL_ADDR, 0x0A);  // INT1 output enable, push-pull, active high
        writeRegister8(INT2_IO_CTRL_ADDR, 0x00);
        writeRegister8(INT_LATCH_ADDR, 0x00);     // pulsed
        writeRegister8(INT_MAP_DATA_ADDR, 0x04);  // data ready -> INT1 only
    }

    bool read(int16_t out[6])
    {
        // One burst over ACC (0x0C..0x11) and GYR (0x12..0x17) keeps the pair coherent.
        uint8_t buf[12];
        if (!readRegister(ACC_X_LSB_ADDR, buf, sizeof(buf)))
            return false;
        for (int i = 0; i < 6; ++i)
            out[i] = (int16_t)(buf[2 * i] | (buf[2 * i + 1] << 8));
        return true;
    }
};

ReginaBmi270* s_imu = nullptr;
imu_sample_cb_t s_cb = nullptr;
TaskHandle_t s_task = nullptr;
volatile int64_t s_irq_time = 0;
volatile bool s_irq_mode = false;

void IRAM_ATTR on_drdy(void*)
{
    s_irq_time = esp_timer_get_time();
    BaseType_t woken = pdFALSE;
    vTaskNotifyGiveFromISR(s_task, &woken);
    portYIELD_FROM_ISR(woken);
}

void sample_task(void*)
{
    int64_t last_t = 0;
    int irq_hits = 0;
    int timeouts = 0;
    TickType_t last_wake = xTaskGetTickCount();
    while (true)
    {
        int64_t t;
        if (s_irq_mode)
        {
            if (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(20)) > 0)
            {
                t = s_irq_time;
                irq_hits++;
                timeouts = 0;
            }
            else
            {
                // No data-ready pulses (INT1 not wired / not soldered): fall back to polling.
                if (++timeouts >= 5 && irq_hits == 0)
                {
                    ESP_LOGW(TAG, "no data-ready interrupt, polling at 200 Hz instead");
                    s_irq_mode = false;
                    gpio_isr_handler_remove((gpio_num_t)PIN_IMU_INT1);
                }
                continue;
            }
        }
        else
        {
            xTaskDelayUntil(&last_wake, pdMS_TO_TICKS(5));
            t = esp_timer_get_time();
        }
        if (t - last_t < MIN_SAMPLE_GAP_US)
            continue;

        int16_t raw[6];
        bool ok;
        {
            std::lock_guard<std::mutex> lock(i2c_bus_mutex());
            ok = s_imu->read(raw);
        }
        if (!ok)
            continue;
        last_t = t;
        ImuRawSample s{t, raw[0], raw[1], raw[2], raw[3], raw[4], raw[5]};
        if (s_cb)
            s_cb(s);
    }
}
}  // namespace

namespace imu
{
bool init()
{
    for (uint8_t addr : {(uint8_t)0x68, (uint8_t)0x69})
    {
        auto* dev = new ReginaBmi270(addr);
        bool found;
        {
            std::lock_guard<std::mutex> lock(i2c_bus_mutex());
            found = dev->begin(&m5::In_I2C) != m5::IMU_Base::imu_spec_none;
            if (found)
                dev->configure();
        }
        if (found)
        {
            s_imu = dev;
            ESP_LOGI(TAG, "BMI270 at 0x%02x, 200 Hz, +-8 g, +-2000 dps", addr);
            return true;
        }
        delete dev;
    }
    ESP_LOGE(TAG, "BMI270 not found");
    return false;
}

void start(imu_sample_cb_t cb)
{
    if (s_imu == nullptr)
        return;
    s_cb = cb;
    xTaskCreate(sample_task, "imu", 4096, nullptr, configMAX_PRIORITIES - 2, &s_task);

    gpio_config_t io = {};
    io.pin_bit_mask = 1ULL << PIN_IMU_INT1;
    io.mode = GPIO_MODE_INPUT;
    io.pull_down_en = GPIO_PULLDOWN_ENABLE;
    io.intr_type = GPIO_INTR_POSEDGE;
    gpio_config(&io);
    esp_err_t err = gpio_install_isr_service(0);
    if (err == ESP_OK || err == ESP_ERR_INVALID_STATE)
        s_irq_mode = gpio_isr_handler_add((gpio_num_t)PIN_IMU_INT1, on_drdy, nullptr) == ESP_OK;
    ESP_LOGI(TAG, "sampling via %s", s_irq_mode ? "data-ready interrupt" : "polling");
}

bool ok() { return s_imu != nullptr; }

bool using_irq() { return s_irq_mode; }
}  // namespace imu
