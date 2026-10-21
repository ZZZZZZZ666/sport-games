class_name RSMeshUtil
extends RefCounted
## Procedural helpers for the stylized look (rounded shapes read better with toon shading).


static func rounded_box(size: Vector3, radius: float, rings: int = 12, segments: int = 24) -> ArrayMesh:
	## Box with rounded edges/corners: a sphere whose vertices are pushed out to the box core.
	var half := size * 0.5
	var r := minf(radius, minf(half.x, minf(half.y, half.z)))
	var core := half - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in rings + 1:
		var v := float(y) / rings
		var theta := v * PI
		for x in segments + 1:
			var u := float(x) / segments
			var phi := u * TAU
			var n := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			var p := Vector3(
				signf(n.x) * core.x if absf(n.x) > 1e-6 else 0.0,
				signf(n.y) * core.y if absf(n.y) > 1e-6 else 0.0,
				signf(n.z) * core.z if absf(n.z) > 1e-6 else 0.0) + n * r
			st.set_normal(n)
			st.set_uv(Vector2(u, v))
			st.add_vertex(p)
	for y in rings:
		for x in segments:
			var a := y * (segments + 1) + x
			var b := a + segments + 1
			# Clockwise seen from outside (Godot's front face).
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	return st.commit()


static func toon_material(color: Color, rim: float = 0.35, roughness: float = 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/toon.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("roughness", roughness)
	return m


static func coverage_mipmaps(img: Image, cutoff: float) -> Image:
	## Mipmaps for an alpha-tested texture that keep the same share of opaque texels at every
	## level (plain averaging thins leaves and fences out to nothing in the distance).
	var base := img.duplicate() as Image
	base.convert(Image.FORMAT_RGBA8)
	var target := _coverage(base, cutoff, 1.0)
	var data := base.get_data()
	var level := base
	while level.get_width() > 1 or level.get_height() > 1:
		var next := level.duplicate() as Image
		next.resize(maxi(1, level.get_width() / 2), maxi(1, level.get_height() / 2), Image.INTERPOLATE_BILINEAR)
		# Find the alpha scale that restores the coverage, then bake it in.
		var lo := 0.5
		var hi := 4.0
		for i in 12:
			var mid := (lo + hi) * 0.5
			if _coverage(next, cutoff, mid) < target:
				lo = mid
			else:
				hi = mid
		var px := next.get_data()
		for i in range(3, px.size(), 4):
			px[i] = clampi(int(px[i] * hi), 0, 255)
		next = Image.create_from_data(next.get_width(), next.get_height(), false, Image.FORMAT_RGBA8, px)
		data.append_array(next.get_data())
		level = next
	return Image.create_from_data(base.get_width(), base.get_height(), true, Image.FORMAT_RGBA8, data)


static func _coverage(img: Image, cutoff: float, scale: float) -> float:
	var px := img.get_data()
	var n := 0
	var lim := cutoff * 255.0 / scale
	for i in range(3, px.size(), 4):
		if px[i] > lim:
			n += 1
	return float(n) / (px.size() / 4)
