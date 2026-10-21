class_name RSOledPreview
extends Control
## Draws the controller's OLED screen the way the firmware lays it out
## (firmware/main/display_ui.cpp, portrait 64x128 = the upright grip with A-D down the
## left edge), so screen designs can be checked without hardware.

const W := 64.0
const H := 128.0
const ON := Color(0.78, 0.95, 1.0)
const OFF := Color(0.02, 0.03, 0.05)
## Glyph heights of the firmware fonts, in OLED pixels: Font0 (6x8), Font2, Font4.
const SMALL := 9.0
const MEDIUM := 15.0
const LARGE := 24.0

var controller: RSController
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	queue_redraw()


func _k() -> float:
	return minf(size.x / W, size.y / H)


func _rect(x: float, y: float, w: float, h: float, color: Color, filled: bool = true) -> void:
	var k := _k()
	draw_rect(Rect2(Vector2(x, y) * k, Vector2(w, h) * k), color, filled, maxf(1.0, k) if not filled else -1.0)


func _text(x: float, cy: float, text: String, px: float, color: Color, centered: bool) -> void:
	## Vertically centred like LovyanGFX's middle_* datums; x is the centre or the left edge.
	var k := _k()
	var fs := int(round(px * k))
	var baseline := cy * k + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	if centered:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(x * k - w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	else:
		draw_string(font, Vector2(x * k, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw() -> void:
	_rect(0, 0, W, H, OFF)
	if controller == null:
		return
	var ui := controller.ui_state

	# --- status bar -----------------------------------------------------------------
	if controller.player > 0:
		_rect(0, 0, 15, 10, ON)
		_text(8, 5, "P%d" % controller.player, SMALL, OFF, true)
	if not controller.connected:
		draw_line(Vector2(39, 2) * _k(), Vector2(43, 8) * _k(), ON, maxf(1.0, _k()))
		draw_line(Vector2(43, 2) * _k(), Vector2(39, 8) * _k(), ON, maxf(1.0, _k()))
	_rect(47, 1, 13, 8, ON, false)
	_rect(60, 3, 2, 4, ON)
	if controller.battery >= 0:
		var blink := controller.battery < 15 and not controller.charging and (Time.get_ticks_msec() / 400) % 2 == 0
		if not blink:
			_rect(48, 2, 11.0 * clampf(controller.battery / 100.0, 0.0, 1.0), 6, ON)
	_rect(0, 11, W, 1, ON)

	# --- title + body -------------------------------------------------------------------
	var title := str(ui.get("title", ""))
	_text(32, 18, (title if not title.is_empty() else "REGINA").left(10), SMALL, ON, true)
	var main := str(ui.get("main", ""))
	var sub := str(ui.get("sub", ""))
	var has_content := ui.has("title") or ui.has("main") or ui.has("sub") or ui.has("bar") or ui.has("legends")
	if not has_content:
		main = "P%d" % controller.player if controller.player > 0 else controller.display_name.get_slice("-", 1).left(10)
		sub = "CONNECTED" if controller.connected else "WAITING PC"
	var bar = ui.get("bar")
	if typeof(bar) == TYPE_DICTIONARY:
		_text(32, 31, str(bar.get("label", "")).left(10), SMALL, ON, true)
		_rect(2, 37, 60, 9, ON, false)
		_rect(4, 39, 56.0 * clampf(float(bar.get("pct", 0)) / 100.0, 0.0, 1.0), 5, ON)
		_text(32, 59, main.left(10), MEDIUM if main.length() <= 7 else SMALL, ON, true)
	else:
		var px := LARGE if main.length() <= 3 else (MEDIUM if main.length() <= 7 else SMALL)
		_text(32, 43, main.left(10), px, ON, true)
		_text(32, 64, sub.left(10), SMALL, ON, true)

	# --- one legend row per button, top to bottom ------------------------------------------
	_rect(0, 76, W, 1, ON)
	var legends: Array = ui.get("legends", [null, null, null, null])
	var letters := ["A", "B", "C", "D"]
	for i in 4:
		var y := 80.0 + i * 12.0
		var pressed := controller.is_pressed(1 << i)
		_rect(0, y, 10, 10, ON, not pressed)
		_text(5, y + 5, letters[i], SMALL, ON if pressed else OFF, true)
		var label = legends[i] if i < legends.size() else null
		if (label == null or str(label).is_empty()) and i == 3:
			label = "HOLD:0"
		if label != null:
			_text(13, y + 5, str(label).left(8), SMALL, ON, false)

	# --- toast ---------------------------------------------------------------------------
	if Time.get_ticks_msec() < int(ui.get("toast_until", 0)):
		var t := str(ui.get("toast", {}).get("text", ""))
		_rect(2, 32, 60, 42, ON)
		if t.length() <= 7:
			_text(32, 53, t, MEDIUM, OFF, true)
		else:
			var split := t.rfind(" ", 10) if t.length() > 10 else -1
			if split <= 0:
				split = 10
			_text(32, 48 if t.length() > 10 else 53, t.left(split), SMALL, OFF, true)
			if t.length() > 10:
				_text(32, 59, t.substr(split + (1 if t[split] == " " else 0)).left(10), SMALL, OFF, true)
