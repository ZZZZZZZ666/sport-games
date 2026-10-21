#include "buzzer.h"

#include "board.h"
#include "driver/ledc.h"
#include "esp_timer.h"

namespace
{
constexpr ledc_mode_t MODE = LEDC_LOW_SPEED_MODE;
constexpr ledc_channel_t CHANNEL = LEDC_CHANNEL_0;
constexpr ledc_timer_t TIMER = LEDC_TIMER_0;
esp_timer_handle_t s_stop_timer = nullptr;

void stop(void*)
{
    ledc_set_duty(MODE, CHANNEL, 0);
    ledc_update_duty(MODE, CHANNEL);
}
}  // namespace

namespace buzzer
{
void init()
{
    ledc_timer_config_t timer = {};
    timer.speed_mode = MODE;
    timer.duty_resolution = LEDC_TIMER_10_BIT;
    timer.timer_num = TIMER;
    timer.freq_hz = 2000;
    timer.clk_cfg = LEDC_AUTO_CLK;
    ledc_timer_config(&timer);

    ledc_channel_config_t ch = {};
    ch.gpio_num = PIN_BUZZER;
    ch.speed_mode = MODE;
    ch.channel = CHANNEL;
    ch.timer_sel = TIMER;
    ch.duty = 0;
    ledc_channel_config(&ch);

    esp_timer_create_args_t args = {};
    args.callback = stop;
    args.name = "beep_stop";
    esp_timer_create(&args, &s_stop_timer);
}

void beep(uint16_t freq_hz, uint16_t ms)
{
    if (!BUZZER_ENABLED || s_stop_timer == nullptr || ms == 0)
        return;
    if (freq_hz < 100)
        freq_hz = 100;
    if (freq_hz > 10000)
        freq_hz = 10000;
    esp_timer_stop(s_stop_timer);
    ledc_set_freq(MODE, TIMER, freq_hz);
    ledc_set_duty(MODE, CHANNEL, 512);  // 50 %
    ledc_update_duty(MODE, CHANNEL);
    esp_timer_start_once(s_stop_timer, (uint64_t)ms * 1000);
}
}  // namespace buzzer
