#include "display_ui.h"

#include <M5GFX.h>
#include <lgfx/v1/panel/Panel_SSD1306.hpp>

#include <mutex>
#include <string>

#include "board.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "protocol.h"

namespace
{
class ReginaOled : public lgfx::LGFX_Device
{
    lgfx::Panel_SH110x _panel;
    lgfx::Bus_SPI _bus;

public:
    ReginaOled()
    {
        auto bus = _bus.config();
        bus.pin_mosi = PIN_OLED_SDA;
        bus.pin_miso = -1;
        bus.pin_sclk = PIN_OLED_SCL;
        bus.pin_dc = PIN_OLED_DC;
        bus.freq_write = 30000000;
        bus.spi_3wire = false;
        _bus.config(bus);
        _panel.setBus(&_bus);

        auto p = _panel.config();
        p.pin_cs = PIN_OLED_CS;
        p.pin_rst = PIN_OLED_RST;
        p.pin_busy = -1;
        p.panel_width = 128;
        p.panel_height = 64;
        p.bus_shared = false;
        _panel.config(p);
        setPanel(&_panel);
    }
};

struct UiModel
{
    std::string title, main, sub;
    int bar_pct = -1;  // -1 hidden
    std::string bar_label;
    std::string legends[4];
    std::string toast;
    int64_t toast_until_us = 0;
    bool has_content = false;
};

ReginaOled* s_lcd = nullptr;
LGFX_Sprite* s_canvas = nullptr;
std::mutex s_mutex;
UiModel s_ui;
std::string s_device_name;
uint8_t s_player = 0;
bool s_connected = false;
uint8_t s_battery = 255;
bool s_charging = false;
uint8_t s_buttons = 0;
bool s_dirty = true;
bool s_toast_visible = false;
bool s_blink_phase = false;

// uint16_t = RGB565. As uint32_t LovyanGFX reads colours as RGB888, so 0xFFFF would be cyan,
// which the 1-bit panel renders as a dithered grey.
constexpr uint16_t ON = TFT_WHITE;
constexpr uint16_t OFF = TFT_BLACK;
const char* const LETTERS[4] = {"A", "B", "C", "D"};

std::string take_str(const uint8_t* p, uint8_t len)
{
    std::string s(reinterpret_cast<const char*>(p), len);
    for (char& c : s)
        if (c < 0x20 || c > 0x7E)
            c = '?';
    return s;
}

std::string cut(const std::string& s, size_t n) { return s.size() > n ? s.substr(0, n) : s; }

bool low_battery() { return s_battery != 255 && s_battery < 15 && !s_charging; }

/// Text shown in the body when the game hasn't sent anything.
void default_body(std::string& main, std::string& sub)
{
    if (s_player > 0)
        main = "P" + std::to_string(s_player);
    else
    {
        size_t dash = s_device_name.find('-');
        main = dash == std::string::npos ? s_device_name : s_device_name.substr(dash + 1);
    }
    sub = s_connected ? "CONNECTED" : "WAITING PC";
}

void draw_battery(LGFX_Sprite& c, int x, int y)
{
    c.drawRect(x, y, 13, 8, ON);
    c.fillRect(x + 13, y + 2, 2, 4, ON);
    if (s_battery != 255 && !(low_battery() && s_blink_phase))
        c.fillRect(x + 1, y + 1, (11 * s_battery) / 100, 6, ON);
}

void draw_not_connected(LGFX_Sprite& c, int x, int y)
{
    c.drawLine(x, y, x + 4, y + 6, ON);
    c.drawLine(x + 4, y, x, y + 6, ON);
}

// ------------------------------------------------------------- portrait 64 x 128 ----
// Held upright with the A-D buttons running down the left edge, so the legends are a
// column of four rows in the same order. Must match game/core/oled_preview.gd.
void draw_portrait(LGFX_Sprite& c)
{
    // status bar
    if (s_player > 0)
    {
        c.fillRect(0, 0, 15, 10, ON);
        c.setTextColor(OFF);
        c.setTextDatum(textdatum_t::middle_center);
        c.drawString(("P" + std::to_string(s_player)).c_str(), 8, 5);
    }
    if (!s_connected)
        draw_not_connected(c, 39, 2);
    draw_battery(c, 47, 1);
    c.drawFastHLine(0, 11, 64, ON);

    // title
    c.setTextColor(ON);
    c.setTextDatum(textdatum_t::middle_center);
    c.drawString(cut(s_ui.title.empty() ? std::string("REGINA") : s_ui.title, 10).c_str(), 32, 18);

    // body
    std::string main = s_ui.main, sub = s_ui.sub;
    if (!s_ui.has_content)
        default_body(main, sub);
    if (s_ui.bar_pct >= 0)
    {
        c.drawString(cut(s_ui.bar_label, 10).c_str(), 32, 31);
        c.drawRect(2, 37, 60, 9, ON);
        c.fillRect(4, 39, (56 * s_ui.bar_pct) / 100, 5, ON);
        if (main.size() <= 7)
            c.setFont(&fonts::Font2);
        c.drawString(cut(main, 10).c_str(), 32, 59);
        c.setFont(&fonts::Font0);
    }
    else
    {
        if (main.size() <= 3)
            c.setFont(&fonts::Font4);
        else if (main.size() <= 7)
            c.setFont(&fonts::Font2);
        c.drawString(cut(main, 10).c_str(), 32, 43);
        c.setFont(&fonts::Font0);
        c.drawString(cut(sub, 10).c_str(), 32, 64);
    }

    // button legends, one row per button, top to bottom
    c.drawFastHLine(0, 76, 64, ON);
    for (int i = 0; i < 4; ++i)
    {
        int y = 80 + i * 12;
        bool pressed = s_buttons & (1 << i);
        if (pressed)
            c.drawRect(0, y, 10, 10, ON);
        else
            c.fillRect(0, y, 10, 10, ON);
        c.setTextColor(pressed ? ON : OFF);
        c.setTextDatum(textdatum_t::middle_center);
        c.drawString(LETTERS[i], 5, y + 5);
        std::string label = s_ui.legends[i];
        if (label.empty() && i == 3)
            label = "HOLD:0";
        c.setTextColor(ON);
        c.setTextDatum(textdatum_t::middle_left);
        c.drawString(cut(label, 8).c_str(), 13, y + 5);
    }

    // toast
    if (s_toast_visible)
    {
        c.fillRoundRect(2, 32, 60, 42, 4, ON);
        c.setTextColor(OFF);
        c.setTextDatum(textdatum_t::middle_center);
        const std::string& t = s_ui.toast;
        if (t.size() <= 7)
        {
            c.setFont(&fonts::Font2);
            c.drawString(t.c_str(), 32, 53);
            c.setFont(&fonts::Font0);
        }
        else
        {
            size_t split = t.size() > 10 ? t.rfind(' ', 10) : std::string::npos;
            if (split == std::string::npos || split == 0)
                split = 10;
            c.drawString(cut(t, split).c_str(), 32, t.size() > 10 ? 48 : 53);
            if (t.size() > 10)
                c.drawString(cut(t.substr(split + (t[split] == ' ' ? 1 : 0)), 10).c_str(), 32, 59);
        }
    }
}

// ------------------------------------------------------------ landscape 128 x 64 ----
void draw_landscape(LGFX_Sprite& c)
{
    if (s_player > 0)
    {
        c.fillRect(0, 0, 16, 10, ON);
        c.setTextColor(OFF);
        c.setTextDatum(textdatum_t::middle_center);
        c.drawString(("P" + std::to_string(s_player)).c_str(), 8, 5);
    }
    c.setTextColor(ON);
    c.setTextDatum(textdatum_t::middle_center);
    c.drawString(cut(s_ui.title.empty() ? std::string("REGINA") : s_ui.title, 14).c_str(), 64, 5);
    if (!s_connected)
        draw_not_connected(c, 100, 2);
    draw_battery(c, 110, 1);
    c.drawFastHLine(0, 11, 128, ON);

    std::string main = s_ui.main, sub = s_ui.sub;
    if (!s_ui.has_content)
        default_body(main, sub);
    if (s_ui.bar_pct >= 0)
    {
        c.setTextDatum(textdatum_t::baseline_left);
        c.drawString(s_ui.bar_label.c_str(), 4, 21);
        c.drawRect(4, 24, 120, 9, ON);
        c.fillRect(6, 26, (116 * s_ui.bar_pct) / 100, 5, ON);
        c.setTextDatum(textdatum_t::baseline_center);
        c.drawString(main.c_str(), 64, 44);
    }
    else
    {
        c.setFont(&fonts::Font2);
        c.setTextDatum(textdatum_t::baseline_center);
        c.drawString(main.c_str(), 64, 33);
        c.setFont(&fonts::Font0);
        c.drawString(sub.c_str(), 64, 44);
    }

    for (int i = 0; i < 4; ++i)
    {
        int x = (i % 2) ? 64 : 0;
        int y = (i < 2) ? 47 : 56;
        bool pressed = s_buttons & (1 << i);
        if (pressed)
            c.drawRect(x, y, 8, 8, ON);
        else
            c.fillRect(x, y, 8, 8, ON);
        c.setTextColor(pressed ? ON : OFF);
        c.setTextDatum(textdatum_t::middle_center);
        c.drawString(LETTERS[i], x + 4, y + 4);
        std::string label = s_ui.legends[i];
        if (label.empty() && i == 3)
            label = "HOLD:ZERO";
        c.setTextColor(ON);
        c.setTextDatum(textdatum_t::middle_left);
        c.drawString(cut(label, 9).c_str(), x + 10, y + 4);
    }

    if (s_toast_visible)
    {
        c.fillRoundRect(8, 18, 112, 26, 4, ON);
        c.setTextColor(OFF);
        c.setTextDatum(textdatum_t::middle_center);
        c.setFont(s_ui.toast.size() <= 13 ? static_cast<const lgfx::IFont*>(&fonts::Font2) : &fonts::Font0);
        c.drawString(cut(s_ui.toast, 20).c_str(), 64, 31);
        c.setFont(&fonts::Font0);
    }
}

void draw_locked()
{
    auto& c = *s_canvas;
    c.fillScreen(OFF);
    c.setTextWrap(false);
    c.setFont(&fonts::Font0);  // 6x8
    c.setTextSize(1);
    if (c.width() < c.height())
        draw_portrait(c);
    else
        draw_landscape(c);
    c.pushSprite(0, 0);
}

void make_canvas_locked()
{
    if (s_canvas != nullptr)
        s_canvas->deleteSprite();
    else
        s_canvas = new LGFX_Sprite(s_lcd);
    s_canvas->createSprite(s_lcd->width(), s_lcd->height());
}
}  // namespace

namespace display_ui
{
void init(const char* device_name, uint8_t rotation)
{
    s_device_name = device_name;
    s_lcd = new ReginaOled();
    s_lcd->init();
    s_lcd->setRotation(rotation & 3);
    std::lock_guard<std::mutex> lock(s_mutex);
    make_canvas_locked();
#if DISPLAY_BOOT_TEST
    // Panel check: every pixel lit, then the outer border + diagonals + a 4 px grid corner.
    s_canvas->fillScreen(ON);
    s_canvas->pushSprite(0, 0);
    vTaskDelay(pdMS_TO_TICKS(1500));
    auto& c = *s_canvas;
    int w = c.width(), h = c.height();
    c.fillScreen(OFF);
    c.drawRect(0, 0, w, h, ON);
    c.drawLine(0, 0, w - 1, h - 1, ON);
    c.drawLine(w - 1, 0, 0, h - 1, ON);
    for (int y = 2; y < 18; y += 2)
        c.drawFastHLine(2, y, 16, ON);
    c.setFont(&fonts::Font2);
    c.setTextColor(ON, OFF);
    c.setTextDatum(textdatum_t::middle_center);
    c.drawString("TOP", w / 2, 24);
    c.pushSprite(0, 0);
    vTaskDelay(pdMS_TO_TICKS(1500));
#endif
    draw_locked();
}

void set_rotation(uint8_t rotation)
{
    if (s_lcd == nullptr)
        return;
    std::lock_guard<std::mutex> lock(s_mutex);
    if (s_lcd->getRotation() == (rotation & 3))
        return;
    s_lcd->setRotation(rotation & 3);
    s_lcd->clear();
    make_canvas_locked();
    s_dirty = true;
}

void apply_tlv(const uint8_t* data, uint16_t len)
{
    std::lock_guard<std::mutex> lock(s_mutex);
    uint16_t i = 0;
    while (i + 2 <= len)
    {
        uint8_t tag = data[i];
        uint8_t n = data[i + 1];
        const uint8_t* p = data + i + 2;
        if (i + 2 + n > len)
            break;
        i += 2 + n;
        switch (tag)
        {
        case UI_CLEAR:
            s_ui = UiModel();
            break;
        case UI_TITLE:
            s_ui.title = take_str(p, n);
            break;
        case UI_MAIN:
            s_ui.main = take_str(p, n);
            break;
        case UI_SUB:
            s_ui.sub = take_str(p, n);
            break;
        case UI_BAR:
            if (n >= 1)
            {
                s_ui.bar_pct = p[0] == UI_BAR_HIDDEN ? -1 : (p[0] > 100 ? 100 : p[0]);
                s_ui.bar_label = take_str(p + 1, n - 1);
            }
            break;
        case UI_TOAST:
            if (n >= 2)
            {
                uint16_t ms = p[0] | (p[1] << 8);
                s_ui.toast = take_str(p + 2, n - 2);
                s_ui.toast_until_us = esp_timer_get_time() + (int64_t)ms * 1000;
            }
            break;
        default:
            if (tag >= UI_LEGEND_A && tag < UI_LEGEND_A + 4)
                s_ui.legends[tag - UI_LEGEND_A] = take_str(p, n);
            break;
        }
        if (tag != UI_TOAST)
            s_ui.has_content = true;
    }
    s_dirty = true;
}

void set_player(uint8_t player)
{
    std::lock_guard<std::mutex> lock(s_mutex);
    s_dirty |= s_player != player;
    s_player = player;
}

void set_connected(bool connected)
{
    std::lock_guard<std::mutex> lock(s_mutex);
    if (s_connected != connected && !connected)
        s_ui = UiModel();  // the game owns the screen only while connected
    s_dirty |= s_connected != connected;
    s_connected = connected;
}

void set_battery(uint8_t percent, bool charging)
{
    std::lock_guard<std::mutex> lock(s_mutex);
    s_dirty |= s_battery != percent || s_charging != charging;
    s_battery = percent;
    s_charging = charging;
}

void set_buttons(uint8_t buttons)
{
    std::lock_guard<std::mutex> lock(s_mutex);
    s_dirty |= s_buttons != buttons;
    s_buttons = buttons;
}

void toast(const char* text, uint16_t ms)
{
    std::lock_guard<std::mutex> lock(s_mutex);
    s_ui.toast = text;
    s_ui.toast_until_us = esp_timer_get_time() + (int64_t)ms * 1000;
    s_dirty = true;
}

void tick()
{
    if (s_canvas == nullptr)
        return;
    std::lock_guard<std::mutex> lock(s_mutex);
    int64_t now = esp_timer_get_time();
    bool toast_visible = now < s_ui.toast_until_us;
    bool blink = (now / 400000) % 2;
    if (toast_visible != s_toast_visible)
    {
        s_toast_visible = toast_visible;
        s_dirty = true;
    }
    if (low_battery() && blink != s_blink_phase)
    {
        s_blink_phase = blink;
        s_dirty = true;
    }
    if (!s_dirty)
        return;
    s_dirty = false;
    draw_locked();
}
}  // namespace display_ui
