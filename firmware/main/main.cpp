// Regina Sports controller firmware.
// Streams timestamped raw IMU samples (200 Hz), buttons/dials and battery over BLE; shows the
// game-driven UI on the OLED. All fusion / calibration / recentering happens in regina-hub.

#include <utility/I2C_Class.hpp>

#include <cstdio>
#include <cstring>

#include "ble_service.h"
#include "board.h"
#include "buzzer.h"
#include "display_ui.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "imu.h"
#include "input.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "pmu.h"
#include "protocol.h"

static const char* TAG = "main";

namespace
{
char s_name[16];
volatile uint8_t s_player = 0;
volatile bool s_status_dirty = true;

// ------------------------------------------------------------------------------ IMU ----

imu_packet_t s_pkt;
uint8_t s_seq = 0;
int64_t s_prev_t = 0;

void on_imu_sample(const ImuRawSample& s)
{
    if (!ble_service_connected())
    {
        s_pkt.count = 0;
        return;
    }
    uint8_t i = s_pkt.count;
    if (i == 0)
    {
        s_pkt.type = PKT_IMU;
        s_pkt.ranges = IMU_RANGES_BYTE;
        s_pkt.t0_us = (uint32_t)s.t_us;
        s_pkt.samples[0].dt_us = 0;
    }
    else
    {
        int64_t dt = s.t_us - s_prev_t;
        s_pkt.samples[i].dt_us = (uint16_t)(dt > 65535 ? 65535 : (dt < 0 ? 0 : dt));
    }
    s_prev_t = s.t_us;
    imu_sample_t& o = s_pkt.samples[i];
    o.ax = s.ax;
    o.ay = s.ay;
    o.az = s.az;
    o.gx = s.gx;
    o.gy = s.gy;
    o.gz = s.gz;
    s_pkt.count = i + 1;

    // Pack as many samples as the negotiated MTU allows (4 with MTU >= 67).
    uint16_t room = ble_service_mtu() > 3 + 8 ? (ble_service_mtu() - 3 - 8) / sizeof(imu_sample_t) : 0;
    uint8_t target = room >= IMU_SAMPLES_PER_PACKET ? IMU_SAMPLES_PER_PACKET : (room == 0 ? 1 : room);
    if (s_pkt.count >= target)
    {
        s_pkt.seq = s_seq++;
        ble_service_notify_imu(&s_pkt, 8 + s_pkt.count * sizeof(imu_sample_t));
        s_pkt.count = 0;
    }
}

// --------------------------------------------------------------------------- input ----

void input_task(void*)
{
    InputState st{};
    int64_t last_sent = 0;
    TickType_t wake = xTaskGetTickCount();
    while (true)
    {
        xTaskDelayUntil(&wake, pdMS_TO_TICKS(10));
        bool changed = input::update(st);
        int64_t now = esp_timer_get_time();
        if (changed || now - last_sent > 1000000)
        {
            input_packet_t pkt{PKT_INPUT, st.buttons, st.dial_small, st.dial_big, (uint32_t)now};
            ble_service_update_input(&pkt, sizeof(pkt));
            display_ui::set_buttons(st.buttons);
            last_sent = now;
        }
    }
}

// ------------------------------------------------------------------ status + screen ----

void send_status(uint8_t battery, bool charging)
{
    uint8_t flags = (charging ? 1 : 0) | (imu::ok() ? 2 : 0) | (imu::using_irq() ? 4 : 0);
    status_packet_t pkt{PKT_STATUS, battery, flags, FW_VERSION_MAJOR, FW_VERSION_MINOR, s_player};
    ble_service_update_status(&pkt, sizeof(pkt));
}

void ui_task(void*)
{
    int64_t last_status = 0;
    bool was_connected = false;
    uint8_t battery = pmu::battery_percent();
    bool charging = pmu::charging();
    TickType_t wake = xTaskGetTickCount();
    while (true)
    {
        xTaskDelayUntil(&wake, pdMS_TO_TICKS(33));
        int64_t now = esp_timer_get_time();
        bool connected = ble_service_connected();
        if (connected != was_connected)
        {
            was_connected = connected;
            display_ui::set_connected(connected);
            if (connected)
                buzzer::beep(2400, 40);
            s_status_dirty = true;
        }
        if (now - last_status > 5000000 || s_status_dirty)
        {
            uint8_t b = pmu::battery_percent();
            bool c = pmu::charging();
            if (b != battery || c != charging || now - last_status > 5000000 || s_status_dirty)
            {
                battery = b;
                charging = c;
                display_ui::set_battery(battery, charging);
                send_status(battery, charging);
            }
            last_status = now;
            s_status_dirty = false;
        }
        display_ui::tick();
    }
}

// ------------------------------------------------------------------ screen rotation ----
// Remembered across reboots so the "waiting for PC" screen is already the right way up.

constexpr uint8_t DEFAULT_ROTATION = 3;  // portrait, upright with A-D on the left

uint8_t load_rotation()
{
    nvs_handle_t h;
    uint8_t r = DEFAULT_ROTATION;
    if (nvs_open("rs", NVS_READONLY, &h) == ESP_OK)
    {
        nvs_get_u8(h, "rot", &r);
        nvs_close(h);
    }
    return r & 3;
}

void save_rotation(uint8_t r)
{
    nvs_handle_t h;
    if (nvs_open("rs", NVS_READWRITE, &h) == ESP_OK)
    {
        uint8_t old = 255;
        if (nvs_get_u8(h, "rot", &old) != ESP_OK || old != r)
        {
            nvs_set_u8(h, "rot", r);
            nvs_commit(h);
        }
        nvs_close(h);
    }
}

// ------------------------------------------------------------------------ commands ----

void on_command(const uint8_t* data, uint16_t len)
{
    switch (data[0])
    {
    case OP_SET_PLAYER:
        if (len >= 2 && data[1] <= 4)
        {
            s_player = data[1];
            display_ui::set_player(data[1]);
            s_status_dirty = true;
        }
        break;
    case OP_BEEP:
        if (len >= 5)
            buzzer::beep(data[1] | (data[2] << 8), data[3] | (data[4] << 8));
        break;
    case OP_SET_ROTATION:
        if (len >= 2)
        {
            display_ui::set_rotation(data[1] & 3);
            save_rotation(data[1] & 3);
        }
        break;
    case OP_VIBRATE:
        // Reserved until the haptic driver (DRV2605L) is added to the hardware.
        break;
    case OP_UI:
        display_ui::apply_tlv(data + 1, len - 1);
        break;
    default:
        ESP_LOGW(TAG, "unknown opcode 0x%02x", data[0]);
        break;
    }
}
}  // namespace

extern "C" void app_main(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        nvs_flash_erase();
        nvs_flash_init();
    }

    uint8_t mac[6] = {};
    esp_read_mac(mac, ESP_MAC_BT);
    snprintf(s_name, sizeof(s_name), "Regina-%02X%02X", mac[4], mac[5]);
    ESP_LOGI(TAG, "%s firmware %d.%d", s_name, FW_VERSION_MAJOR, FW_VERSION_MINOR);

    m5::In_I2C.begin(I2C_NUM_0, PIN_I2C_SDA, PIN_I2C_SCL);
    pmu::init();
    display_ui::init(s_name, load_rotation());
    input::init();
    buzzer::init();
    imu::init();

    ble_service_start(s_name, on_command);
    imu::start(on_imu_sample);
    xTaskCreate(input_task, "input", 3072, nullptr, 6, nullptr);
    xTaskCreate(ui_task, "ui", 6144, nullptr, 3, nullptr);

    buzzer::beep(1800, 60);
}
