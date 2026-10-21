#include "input.h"

#include "board.h"
#include "driver/gpio.h"
#include "esp_rom_sys.h"

#include <initializer_list>

namespace
{
struct Dial
{
    uint8_t last = 0;
    int16_t count = 0;
    bool swapped = false;
};

Dial s_small, s_big;
uint8_t s_samples[3];
int s_sample_idx = 0;
uint8_t s_btn_stable = 0;
uint8_t s_btn_last_raw = 0;
bool s_first = true;

void out_level(int pin, int level) { gpio_set_level((gpio_num_t)pin, level); }

uint8_t read_shift_register()
{
    out_level(PIN_DIAL_CE, 1);
    out_level(PIN_DIAL_PL, 0);
    esp_rom_delay_us(5);
    out_level(PIN_DIAL_PL, 1);
    out_level(PIN_DIAL_CE, 0);
    uint8_t v = 0;
    for (int i = 0; i < 8; ++i)
    {
        v |= (gpio_get_level((gpio_num_t)PIN_DIAL_DATA) & 1) << (7 - i);
        out_level(PIN_DIAL_CLK, 1);
        esp_rom_delay_us(5);
        out_level(PIN_DIAL_CLK, 0);
    }
    return v;
}

uint8_t unswap(uint8_t v)
{
    // Encoder soldered the other way round: swap bit0<->bit1 and bit2<->bit3.
    return (uint8_t)(((v & 0b0101) << 1) | ((v & 0b1010) >> 1));
}

void count_dial(Dial& d, uint8_t value)
{
    if (d.swapped)
        value = unswap(value);
    if (value == d.last)
        return;
    int inc = (int)value - (int)d.last;
    if (inc == 15)
        inc -= 16;
    else if (inc == -15)
        inc += 16;
    // The shift register sometimes latches garbage mid-transition; clamp to one step.
    if (inc > 1)
        inc = 1;
    else if (inc < -1)
        inc = -1;
    d.count += inc;
    d.last = value;
}

uint8_t read_buttons()
{
    uint8_t b = 0;
    if (!gpio_get_level((gpio_num_t)PIN_BTN_A))
        b |= 1;
    if (!gpio_get_level((gpio_num_t)PIN_BTN_B))
        b |= 2;
    if (!gpio_get_level((gpio_num_t)PIN_BTN_C))
        b |= 4;
    if (!gpio_get_level((gpio_num_t)PIN_BTN_D))
        b |= 8;
    return b;
}
}  // namespace

namespace input
{
void init(bool dial_small_swapped, bool dial_big_swapped)
{
    for (int pin : {PIN_BTN_A, PIN_BTN_B, PIN_BTN_C, PIN_BTN_D, PIN_DIAL_DATA})
    {
        gpio_reset_pin((gpio_num_t)pin);
        gpio_set_direction((gpio_num_t)pin, GPIO_MODE_INPUT);
    }
    for (int pin : {PIN_DIAL_CE, PIN_DIAL_CLK, PIN_DIAL_PL})
    {
        gpio_reset_pin((gpio_num_t)pin);
        gpio_set_direction((gpio_num_t)pin, GPIO_MODE_OUTPUT);
    }
    s_small.swapped = dial_small_swapped;
    s_big.swapped = dial_big_swapped;
    uint8_t v = read_shift_register();
    s_small.last = s_small.swapped ? unswap(v & 0x0F) : (v & 0x0F);
    s_big.last = s_big.swapped ? unswap((v & 0xF0) >> 4) : ((v & 0xF0) >> 4);
}

bool update(InputState& out)
{
    bool changed = s_first;
    s_first = false;

    // Majority vote over 3 reads (every 30 ms), like the original firmware.
    s_samples[s_sample_idx++] = read_shift_register();
    if (s_sample_idx >= 3)
    {
        s_sample_idx = 0;
        uint8_t v = s_samples[0];
        if (s_samples[1] == s_samples[2])
            v = s_samples[1];
        int16_t before_small = s_small.count, before_big = s_big.count;
        count_dial(s_small, v & 0x0F);
        count_dial(s_big, (v & 0xF0) >> 4);
        changed |= before_small != s_small.count || before_big != s_big.count;
    }

    // Two consecutive equal reads (10 ms apart) debounce the buttons.
    uint8_t raw = read_buttons();
    if (raw == s_btn_last_raw && raw != s_btn_stable)
    {
        s_btn_stable = raw;
        changed = true;
    }
    s_btn_last_raw = raw;

    out.buttons = s_btn_stable;
    out.dial_small = s_small.count;
    out.dial_big = s_big.count;
    return changed;
}
}  // namespace input
