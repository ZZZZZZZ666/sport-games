class_name RSControllerModel
extends Node3D
## The Regina model (maintainer-declared AI original; docs/ASSET_PROVENANCE.md) mirroring a live
## RSController: orientation, button presses, both dials, the OLED screen (rendered through
## a SubViewport) and a motion trail.

const PLAYER_COLORS := [
	Color(0.55, 0.58, 0.65),   # unassigned
	Color(0.23, 0.51, 0.96),   # P1 blue
	Color(0.94, 0.27, 0.27),   # P2 red
	Color(0.13, 0.77, 0.37),   # P3 green
	Color(0.96, 0.62, 0.04),   # P4 amber
]
const TRAIL_SECONDS := 0.45

const MODEL := preload("res://assets/models/regina.glb")
## The glb is an exploded view in millimetres, but every part shares one frame: +X runs from
## the top end down to the dials, +Y is out of the screen, +Z is the A-D button side. Held
## upright (screen on the right, A-D top to bottom on the left) that makes the controller
## axes right = -Z, out of screen = +Y, back/down = +X.
const MM := 0.016                        ## model scale: 68 mm long -> ~1.1 units
const MODEL_BASIS := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
const MODEL_CENTER := Vector3(0.57, -0.8, 0.3)    ## middle of the shell, mm
const KEY_SPLITS := [-18.7, -8.4, 1.85]           ## mm along X between the A|B|C|D caps
const SCREEN_CENTER := Vector3(-8.16, 6.45, -4.46)  ## centre of the screen glass, mm
const SCREEN_SIZE := Vector2(14.7, 29.4)            ## 1.3" OLED active area, portrait, mm
const BIG_DIAL_CENTER := Vector3(24.44, 7.8, 7.19)
const SMALL_DIAL_CENTER := Vector3(20.9, 7.8, -10.38)
const DIAL_STEP := TAU / 16.0
const TIP := Vector3(0, 0, -0.56)                 ## top end of the controller, model units

var controller: RSController

var _body_mat: ShaderMaterial
var _back_mat: ShaderMaterial
var _big_dial: Node3D
var _small_dial: Node3D
var _button_mats: Array[ShaderMaterial] = []
var _label: Label3D
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _trail_mat := StandardMaterial3D.new()
var _shown_player := -1
var _pivot := Node3D.new()

func _init(c: RSController = null) -> void:
	controller = c


func _ready() -> void:
	add_child(_pivot)
	var model := Node3D.new()
	model.transform = Transform3D(MODEL_BASIS.scaled(Vector3.ONE * MM), MODEL_BASIS * -MODEL_CENTER * MM)
	_pivot.add_child(model)

	_body_mat = RSMeshUtil.toon_material(PLAYER_COLORS[0], 0.45)
	_back_mat = RSMeshUtil.toon_material(PLAYER_COLORS[0].darkened(0.35), 0.3)
	var glass := RSMeshUtil.toon_material(Color(0.03, 0.035, 0.045), 0.25, 0.15)
	var dark := RSMeshUtil.toon_material(Color(0.16, 0.17, 0.2), 0.3)
	var light := RSMeshUtil.toon_material(Color(0.88, 0.9, 0.93), 0.3)
	var src := MODEL.instantiate()
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var part := String(mi.name)
		if part.contains("外壳"):   # no-i18n: node names in the model file
			_part(model, mi.mesh, _body_mat)
		elif part.contains("后盖"):   # no-i18n: node names in the model file
			_part(model, mi.mesh, _back_mat)
		elif part.contains("屏幕"):   # no-i18n: node names in the model file
			_part(model, mi.mesh, glass)
		elif part.contains("电源键"):   # no-i18n: node names in the model file
			_part(model, mi.mesh, light)
		elif part.contains("大拨轮"):   # no-i18n: node names in the model file
			_big_dial = _dial(model, mi.mesh, dark, BIG_DIAL_CENTER)
		elif part.contains("小波轮"):   # no-i18n: node names in the model file
			_small_dial = _dial(model, mi.mesh, dark, SMALL_DIAL_CENTER)
		elif part.contains("排键"):   # no-i18n: node names in the model file
			var caps := _split_keys(mi.mesh)
			for i in 4:
				var m := RSMeshUtil.toon_material(Color(0.92, 0.93, 0.96), 0.3, 0.4)
				_button_mats.append(m)
				_part(model, caps[i], m)
		# PCB, battery and chips sit inside the shell: not added.
	src.free()

	# Live OLED texture on the screen glass, upright (portrait) like the real screen.
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 256)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	var oled := RSOledPreview.new()
	oled.controller = controller
	oled.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(oled)
	add_child(vp)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	screen.mesh = quad
	# quad right -> controller right (-Z mm), quad up -> top end (-X mm), facing out (+Y mm)
	screen.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)), SCREEN_CENTER + Vector3(0, 0.05, 0))
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_texture = vp.get_texture()
	smat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	smat.emission_enabled = true
	smat.emission_texture = vp.get_texture()
	smat.emission_energy_multiplier = 0.6
	screen.material_override = smat
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(screen)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 36
	_label.outline_size = 10
	_label.pixel_size = 0.0022
	_label.line_spacing = -6
	_label.position = Vector3(0, 0.62, 0)
	_label.no_depth_test = true
	add_child(_label)

	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)


func _part(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _dial(parent: Node3D, mesh: Mesh, mat: Material, center: Vector3) -> Node3D:
	## Dials spin about their own centre (axis = out of the screen).
	var pivot := Node3D.new()
	pivot.position = center
	parent.add_child(pivot)
	_part(pivot, mesh, mat).position = -center
	return pivot


func _split_keys(mesh: Mesh) -> Array[ArrayMesh]:
	## The A-D caps are one moulded strip; cut its triangles at the gaps between caps so
	## each cap can light up on its own. A is at the top end (lowest X).
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(verts.size())
		for k in verts.size():
			indices[k] = k
	var buckets: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for t in range(0, indices.size(), 3):
		var cx := (verts[indices[t]].x + verts[indices[t + 1]].x + verts[indices[t + 2]].x) / 3.0
		var b := 0
		while b < 3 and cx > KEY_SPLITS[b]:
			b += 1
		buckets[b].append_array([indices[t], indices[t + 1], indices[t + 2]])
	var out: Array[ArrayMesh] = []
	for b in 4:
		var a := arrays.duplicate()
		a[Mesh.ARRAY_INDEX] = buckets[b]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.append(m)
	return out


func player_color() -> Color:
	var p := controller.player if controller else 0
	return PLAYER_COLORS[clampi(p, 0, 4)]


func _process(_delta: float) -> void:
	if controller == null:
		return
	_pivot.quaternion = controller.orientation
	if controller.player != _shown_player:
		_shown_player = controller.player
		_body_mat.set_shader_parameter("albedo", player_color())
		_back_mat.set_shader_parameter("albedo", player_color().darkened(0.35))
	for i in 4:
		var pressed := controller.is_pressed(1 << i)
		_button_mats[i].set_shader_parameter("albedo", player_color().lightened(0.3) if pressed else Color(0.92, 0.93, 0.96))
		_button_mats[i].set_shader_parameter("emission_color", player_color() * 0.6 if pressed else Color.BLACK)
	var status := "" if controller.connected else "  (offline)"
	_label.text = "%s
%s%s" % ["P%d" % controller.player if controller.player > 0 else "--", controller.display_name, status]
	_label.modulate = player_color().lightened(0.2)
	if _big_dial:
		_big_dial.rotation.y = lerp_angle(_big_dial.rotation.y, controller.dial_big * DIAL_STEP, 0.3)
	if _small_dial:
		_small_dial.rotation.y = lerp_angle(_small_dial.rotation.y, controller.dial_small * DIAL_STEP, 0.3)
	_pivot.visible = controller.connected
	_draw_trail()


func _draw_trail() -> void:
	_trail_mesh.clear_surfaces()
	var n := controller.history_size()
	if n < 2 or not controller.connected:
		return
	var newest: float = controller.sample_time
	var col := player_color()
	var points: Array[Vector3] = []
	var alphas: Array[float] = []
	for age in mini(n, 200):
		var i := controller.history_index(age)
		var age_s := newest - controller.hist_time[i]
		if age_s > TRAIL_SECONDS:
			break
		points.append(global_transform * (controller.hist_quat[i] * TIP))
		alphas.append(1.0 - age_s / TRAIL_SECONDS)
	if points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _trail_mat)
	for k in points.size():
		_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, alphas[k]))
		_trail_mesh.surface_add_vertex(points[k])
	_trail_mesh.surface_end()
