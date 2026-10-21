class_name RSIsland
extends Node3D
## Procedural low-poly island for the flying games: flat-shaded terrain with height-banded
## colours, trees, a see-through toon sea and drifting clouds. ground_height() follows the
## rendered triangles exactly, so crashes line up with what players see.

const SIZE := 800.0           ## terrain square, metres, centred on the origin
const GRID := 128             ## cells per side
const SEA_FLOOR := -14.0
const CLOUD_DRIFT := Vector3(2.0, 0.0, 0.6)

var _noise := FastNoiseLite.new()
var _heights := PackedFloat32Array()
var _cell := SIZE / GRID
var _clouds: Array[Node3D] = []


func _init() -> void:
	_noise.seed = 7
	_noise.frequency = 0.0055
	_noise.fractal_octaves = 4
	_heights.resize((GRID + 1) * (GRID + 1))
	for j in GRID + 1:
		for i in GRID + 1:
			_heights[j * (GRID + 1) + i] = _shape(-SIZE * 0.5 + i * _cell, -SIZE * 0.5 + j * _cell)


func _ready() -> void:
	_build_terrain()
	_build_trees()
	_build_sea()
	_build_clouds()


func _process(delta: float) -> void:
	for c in _clouds:
		c.position += CLOUD_DRIFT * delta
		if c.position.x > 700.0:
			c.position.x -= 1400.0
		if c.position.z > 700.0:
			c.position.z -= 1400.0


func ground_height(x: float, z: float) -> float:
	var fx := (x + SIZE * 0.5) / _cell
	var fz := (z + SIZE * 0.5) / _cell
	if fx < 0.0 or fz < 0.0 or fx >= GRID or fz >= GRID:
		return SEA_FLOOR
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var h00 := _h(i, j)
	var h10 := _h(i + 1, j)
	var h01 := _h(i, j + 1)
	var h11 := _h(i + 1, j + 1)
	# Cells are split along the 00-11 diagonal, same as _build_terrain.
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v


func _h(i: int, j: int) -> float:
	return _heights[j * (GRID + 1) + i]


func _shape(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var n := _noise.get_noise_2d(x, z)
	var land := 1.0 - smoothstep(110.0, 270.0, r)
	var peak := pow(1.0 - smoothstep(0.0, 150.0, r), 2.0) * (60.0 + 40.0 * _noise.get_noise_2d(z + 300.0, x))
	return land * (12.0 + 32.0 * n) + peak + (1.0 - land) * SEA_FLOOR


func _vertex(i: int, j: int) -> Vector3:
	return Vector3(-SIZE * 0.5 + i * _cell, _h(i, j), -SIZE * 0.5 + j * _cell)


func _face_color(h: float, ny: float, seed_value: int) -> Color:
	var c: Color
	if h < -3.0:
		c = Color(0.72, 0.68, 0.52)
	elif h < 2.4:
		c = Color(0.94, 0.87, 0.62)
	elif h > 62.0 and ny > 0.6:
		c = Color(0.95, 0.96, 0.98)
	elif ny < 0.72 or h > 46.0:
		c = Color(0.58, 0.55, 0.52)
	else:
		c = Color(0.52, 0.8, 0.36).lerp(Color(0.3, 0.56, 0.3), clampf(h / 40.0, 0.0, 1.0))
	# A little per-face variation sells the low-poly look.
	var jitter := 1.0 + (float(hash(seed_value) % 1000) / 1000.0 - 0.5) * 0.08
	return Color(c.r * jitter, c.g * jitter, c.b * jitter).srgb_to_linear()


func _build_terrain() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in GRID:
		for i in GRID:
			var a := _vertex(i, j)
			var b := _vertex(i + 1, j)
			var c := _vertex(i + 1, j + 1)
			var d := _vertex(i, j + 1)
			for tri in [[a, b, c], [a, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var n := (p2 - p0).cross(p1 - p0).normalized()
				var col := _face_color((p0.y + p1.y + p2.y) / 3.0, n.y, j * 4096 + i * 2 + int(p1 == c))
				for p in [p0, p1, p2]:
					verts.append(p)
					normals.append(n)
					colors.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := RSMeshUtil.toon_material(Color.WHITE, 0.1, 0.9)
	mat.set_shader_parameter("use_vertex_color", true)
	mi.material_override = mat
	add_child(mi)


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var xforms: Array[Transform3D] = []
	for k in 2500:
		var p := Vector2(rng.randf_range(-280.0, 280.0), rng.randf_range(-280.0, 280.0))
		var h := ground_height(p.x, p.y)
		if h < 3.5 or h > 38.0:
			continue
		var slope := absf(ground_height(p.x + 2.0, p.y) - h) + absf(ground_height(p.x, p.y + 2.0) - h)
		if slope > 1.6 or rng.randf() < 0.35:
			continue
		var s := rng.randf_range(0.8, 1.5)
		xforms.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), Vector3(p.x, h - 0.3, p.y)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.7
	cone.height = 5.0
	cone.radial_segments = 7
	cone.rings = 1
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.35
	trunk.height = 1.6
	trunk.radial_segments = 6
	for part in [[cone, Color(0.2, 0.5, 0.28), 3.4], [trunk, Color(0.45, 0.3, 0.2), 0.8]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k].translated_local(Vector3(0, part[2], 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = RSMeshUtil.toon_material(part[1], 0.25, 0.8)
		add_child(mmi)


func _build_sea() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5000, 5000)
	sea.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	sea.material_override = mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 16
	puff.rings = 8
	var mat := RSMeshUtil.toon_material(Color(0.98, 0.99, 1.0), 0.55, 0.9)
	for k in 40:
		var cloud := Node3D.new()
		var a := rng.randf() * TAU
		var r := rng.randf_range(60.0, 650.0)
		cloud.position = Vector3(cos(a) * r, rng.randf_range(95.0, 150.0) if k % 4 else rng.randf_range(65.0, 85.0), sin(a) * r)
		for n in rng.randi_range(3, 6):
			var mi := MeshInstance3D.new()
			mi.mesh = puff
			mi.material_override = mat
			var s := rng.randf_range(6.0, 13.0)
			mi.scale = Vector3(s * 1.3, s * 0.75, s)
			mi.position = Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(-2.0, 3.0), rng.randf_range(-8.0, 8.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(mi)
		add_child(cloud)
		_clouds.append(cloud)
