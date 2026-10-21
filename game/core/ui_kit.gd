class_name RSUi
extends RefCounted
## Shared look for the 2D UI: a CJK-capable system font and dark rounded panels.

const PANEL_BG := Color(0.07, 0.08, 0.11, 0.9)
const TEXT_MUTED := Color(0.6, 0.64, 0.72)

static var _font: SystemFont


static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"])
	return _font


static func theme(font_size: int = 18) -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = font_size
	return t


static func panel_style(radius: int = 16, bg: Color = PANEL_BG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(18)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	return sb


static func label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func qr_texture(rows: PackedStringArray) -> ImageTexture:
	## Hub QR matrix ("1" = dark) -> texture with a quiet zone, scaled up for nearest filtering.
	var n := rows.size()
	var img := Image.create_empty(n + 4, n + 4, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in n:
		var row: String = rows[y]
		for x in mini(n, row.length()):
			if row[x] == "1":
				img.set_pixel(x + 2, y + 2, Color.BLACK)
	img.resize((n + 4) * 4, (n + 4) * 4, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
