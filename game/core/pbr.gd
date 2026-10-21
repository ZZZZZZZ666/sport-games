class_name RSPbr
## Materials from the Poly Haven scans in res://assets/polyhaven (see tools/fetch_polyhaven.py).
## surface(): the anti-tiling shader for course geometry with UVs in metres.
## standard(): a plain ORMMaterial3D from the same maps (props, small parts).
## Picks the highest resolution that was downloaded; caches the textures.

const ROOT := "res://assets/polyhaven/textures/"
const SHADER := preload("res://shaders/pbr_surface.gdshader")

static var _tex: Dictionary = {}


static func maps(id: String) -> Array:
	## [albedo, normal, orm] textures (null for any that are missing).
	if _tex.has(id):
		return _tex[id]
	var out := [null, null, null]
	for res in ["4k", "2k", "1k"]:
		var base := "%s%s/%s_%%s_%s.jpg" % [ROOT, id, id, res]
		if ResourceLoader.exists(base % "diff"):
			out = [load(base % "diff"), load(base % "nor_gl"), load(base % "arm")]
			break
	if out[0] == null:
		push_warning("RSPbr: no textures for '%s'" % id)
	_tex[id] = out
	return out


static func surface(id: String, size_m: float, tint: Color = Color.WHITE, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var t := maps(id)
	m.set_shader_parameter("albedo_tex", t[0])
	m.set_shader_parameter("normal_tex", t[1])
	m.set_shader_parameter("orm_tex", t[2])
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("size_m", size_m)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func standard(id: String, size_m: float = 1.0, tint: Color = Color.WHITE) -> ORMMaterial3D:
	var t := maps(id)
	var m := ORMMaterial3D.new()
	m.albedo_texture = t[0]
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = t[1]
	m.orm_texture = t[2]
	m.ao_enabled = true
	m.metallic = 1.0
	m.roughness = 1.0
	m.uv1_scale = Vector3.ONE / size_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
