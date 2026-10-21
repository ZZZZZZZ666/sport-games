class_name RSPlot
extends Control
## Scrolling 3-axis plot of a controller's recent history (gyro or world linear accel).

enum Source { GYRO, LINEAR_ACCEL }

const AXIS_COLORS := [Color(0.97, 0.36, 0.36), Color(0.36, 0.86, 0.45), Color(0.38, 0.6, 1.0)]

var controller: RSController
var source := Source.GYRO
var window_s := 3.0
var range_value := 15.0      ## +- full scale (rad/s or m/s^2)
var title := ""


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.06, 0.07, 0.1, 0.85))
	var mid := size.y * 0.5
	for k: float in [-1.0, -0.5, 0.5, 1.0]:
		var y := mid - k * mid * 0.9
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.05), 1.0)
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.15), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.78, 0.85))
	draw_string(font, Vector2(size.x - 70, 16), "±%.0f" % range_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.53, 0.6))
	if controller == null or controller.history_size() < 2:
		return
	var n := controller.history_size()
	var newest: float = controller.sample_time
	var pts: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	for age in n:
		var i := controller.history_index(age)
		var dt := newest - controller.hist_time[i]
		if dt > window_s:
			break
		var v: Vector3 = controller.hist_gyro[i] if source == Source.GYRO else controller.hist_lin[i]
		var x := size.x * (1.0 - dt / window_s)
		for axis in 3:
			var y := mid - clampf(v[axis] / range_value, -1.0, 1.0) * mid * 0.9
			pts[axis].append(Vector2(x, y))
	for axis in 3:
		if pts[axis].size() >= 2:
			draw_polyline(pts[axis], AXIS_COLORS[axis], 1.6, true)
	var labels := ["x", "y", "z"]
	for axis in 3:
		draw_string(font, Vector2(8 + axis * 22, size.y - 8), labels[axis], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, AXIS_COLORS[axis])
