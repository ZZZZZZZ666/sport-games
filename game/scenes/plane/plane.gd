class_name RSPlane
extends Node3D
## Arcade propeller plane. The stick sets the bank and pitch *angles* (not rates): banking turns
## the plane, letting go flies level again, and it can never end up upside down, which keeps
## tilt control friendly for first-time players.

const CRUISE := 26.0            ## m/s
const BOOST := 40.0
const MAX_BANK_DEG := 65.0
const MAX_PITCH_DEG := 40.0
const TURN_GAIN := 1.2          ## > 1 turns tighter than a real coordinated turn
const WINGTIP := Vector3(3.75, -0.05, -0.35)
const TRAIL_POINTS := 40

var color := Color.WHITE
var speed := CRUISE
var heading := 0.0              ## rad about +Y, 0 = flying toward -Z
var pitch := 0.0                ## rad, + = nose up
var bank := 0.0                 ## rad, + = right wing down
var boost_fuel := 1.0           ## 0..1
var boosting := false

var _prop: Node3D
var _trail := ImmediateMesh.new()
var _trail_mat := StandardMaterial3D.new()
var _tips: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _ups := PackedVector3Array()


func _init(c: Color = Color.WHITE) -> void:
	color = c


func _ready() -> void:
	_build_model()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trail := MeshInstance3D.new()
	trail.mesh = _trail
	trail.material_override = _trail_mat
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)


func place(pos: Vector3, yaw: float) -> void:
	position = pos
	heading = yaw
	pitch = 0.0
	bank = 0.0
	speed = CRUISE
	boost_fuel = 1.0
	_apply_basis()
	clear_trail()


func forward() -> Vector3:
	return -basis.z


func fly(stick: Vector2, want_boost: bool, dt: float) -> void:
	## stick.x: -1..1 bank left/right, stick.y: -1..1 dive/climb.
	bank = lerpf(bank, stick.x * deg_to_rad(MAX_BANK_DEG), 1.0 - exp(-dt * 4.0))
	pitch = lerpf(pitch, stick.y * deg_to_rad(MAX_PITCH_DEG), 1.0 - exp(-dt * 3.0))
	boosting = want_boost and boost_fuel > 0.02
	boost_fuel = clampf(boost_fuel + (-0.4 if boosting else 0.15) * dt, 0.0, 1.0)
	var target := (BOOST if boosting else CRUISE) - sin(pitch) * 8.0
	speed = lerpf(speed, target, 1.0 - exp(-dt * 1.5))
	heading -= 9.81 * tan(bank) / speed * TURN_GAIN * dt
	_apply_basis()
	position += forward() * speed * dt
	_record_trail()


func clear_trail() -> void:
	for t in _tips:
		t.clear()
	_ups.clear()
	_trail.clear_surfaces()


func _apply_basis() -> void:
	basis = Basis.from_euler(Vector3(pitch, heading, -bank))


func _process(delta: float) -> void:
	if _prop:
		_prop.rotation.z += delta * (55.0 if boosting else 38.0)
	_draw_trail()


# --------------------------------------------------------------------------- trail ----

func _record_trail() -> void:
	var tip_l := global_transform * Vector3(-WINGTIP.x, WINGTIP.y, WINGTIP.z)
	if not _tips[0].is_empty() and _tips[0][_tips[0].size() - 1].distance_to(tip_l) < 1.5:
		return
	_tips[0].append(tip_l)
	_tips[1].append(global_transform * WINGTIP)
	_ups.append(global_basis.y)
	if _ups.size() > TRAIL_POINTS:
		_tips[0].remove_at(0)
		_tips[1].remove_at(0)
		_ups.remove_at(0)


func _draw_trail() -> void:
	_trail.clear_surfaces()
	var n := _ups.size()
	if n < 2:
		return
	var strength := 0.75 if boosting else 0.4
	_trail.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _trail_mat)
	for side in 2:
		var pts := _tips[side]
		for k in n - 1:
			var a0 := pow(float(k) / n, 1.5) * strength
			var a1 := pow(float(k + 1) / n, 1.5) * strength
			var w0 := _ups[k] * 0.14
			var w1 := _ups[k + 1] * 0.14
			var c0 := Color(1, 1, 1, a0)
			var c1 := Color(1, 1, 1, a1)
			for v in [[pts[k] - w0, c0], [pts[k] + w0, c0], [pts[k + 1] + w1, c1], [pts[k] - w0, c0], [pts[k + 1] + w1, c1], [pts[k + 1] - w1, c1]]:
				_trail.surface_set_color(v[1])
				_trail.surface_add_vertex(v[0])
	_trail.surface_end()


# --------------------------------------------------------------------------- model ----

func _build_model() -> void:
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://shaders/outline.gdshader")
	outline.set_shader_parameter("outline_width", 0.035)
	var body := RSMeshUtil.toon_material(color, 0.45)
	body.next_pass = outline
	# Outlines only on the round parts: the inverted hull darkens thin flat boxes like wings.
	var body_flat := RSMeshUtil.toon_material(color, 0.45)
	var white := RSMeshUtil.toon_material(Color(0.95, 0.95, 0.97), 0.3)
	var dark := RSMeshUtil.toon_material(Color(0.15, 0.16, 0.2), 0.3)
	var glass := RSMeshUtil.toon_material(Color(0.55, 0.82, 0.96), 0.7, 0.1)
	glass.next_pass = outline

	var fuselage := CapsuleMesh.new()
	fuselage.radius = 0.55
	fuselage.height = 4.6
	_add(fuselage, body, Vector3(0, 0, 0.1), Basis(Vector3.RIGHT, PI / 2.0))
	_add(RSMeshUtil.rounded_box(Vector3(7.6, 0.2, 1.4), 0.09), white, Vector3(0, -0.05, -0.35))
	for sx in [-1.0, 1.0]:
		_add(RSMeshUtil.rounded_box(Vector3(1.0, 0.24, 1.44), 0.1), body_flat, Vector3(sx * 3.35, -0.05, -0.35))
	_add(RSMeshUtil.rounded_box(Vector3(2.8, 0.14, 0.8), 0.06), white, Vector3(0, 0.15, 2.05))
	_add(RSMeshUtil.rounded_box(Vector3(0.14, 1.15, 0.95), 0.06), body_flat, Vector3(0, 0.62, 2.1))
	var canopy := SphereMesh.new()
	canopy.radius = 0.42
	canopy.height = 0.7
	_add(canopy, glass, Vector3(0, 0.45, -0.25), Basis.from_scale(Vector3(1, 1, 1.7)))
	var spinner := SphereMesh.new()
	spinner.radius = 0.24
	spinner.height = 0.48
	_add(spinner, body, Vector3(0, 0, -2.42), Basis.from_scale(Vector3(1, 1, 1.4)))
	_prop = Node3D.new()
	_prop.position = Vector3(0, 0, -2.38)
	add_child(_prop)
	for a in [0.0, PI / 2.0]:
		var blade := MeshInstance3D.new()
		blade.mesh = RSMeshUtil.rounded_box(Vector3(0.2, 2.4, 0.05), 0.025)
		blade.material_override = dark
		blade.rotation.z = a
		_prop.add_child(blade)
	var wheel := SphereMesh.new()
	wheel.radius = 0.22
	wheel.height = 0.44
	for sx in [-0.75, 0.75]:
		_add(wheel, dark, Vector3(sx, -0.85, -0.9), Basis.from_scale(Vector3(0.6, 1, 1)))
		_add(RSMeshUtil.rounded_box(Vector3(0.08, 0.5, 0.12), 0.03), dark, Vector3(sx * 0.8, -0.6, -0.9))


func _add(mesh: Mesh, mat: Material, pos: Vector3, b: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(b, pos)
	add_child(mi)
	return mi
