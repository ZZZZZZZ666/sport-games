class_name RSCrowd
## Spectators for finish areas: a low-poly fan (MultiMesh-ready) whose shirt colour comes from
## the instance colour and whose hop/wave rhythm comes from the instance custom data
## (phase, tempo), animated by shaders/crowd.gdshader.

const SHIRTS := [Color(0.95, 0.3, 0.3), Color(0.2, 0.5, 0.95), Color(1.0, 0.8, 0.2), Color(0.2, 0.75, 0.4), Color(0.95, 0.95, 0.95),
	Color(0.6, 0.35, 0.8), Color(0.1, 0.12, 0.16), Color(1.0, 0.55, 0.2)]


static func person_mesh() -> ArrayMesh:
	## Capsule body (shirt colour per instance) + head and raised arms (skin).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CapsuleMesh.new()
	body.radius = 0.2
	body.height = 1.15
	body.radial_segments = 8
	body.rings = 3
	st.append_from(body, 0, Transform3D(Basis(), Vector3(0, 0.6, 0)))
	var mesh := st.commit()
	var head_st := SurfaceTool.new()
	head_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	head.radial_segments = 8
	head.rings = 4
	head_st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 1.38, 0)))
	var arm := CapsuleMesh.new()
	arm.radius = 0.06
	arm.height = 0.6
	arm.radial_segments = 6
	arm.rings = 2
	head_st.append_from(arm, 0, Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-0.3, 1.35, 0)))
	head_st.append_from(arm, 0, Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.3, 1.35, 0)))
	head_st.commit(mesh)
	var crowd := ShaderMaterial.new()
	crowd.shader = preload("res://shaders/crowd.gdshader")
	mesh.surface_set_material(0, crowd)
	var skin := crowd.duplicate() as ShaderMaterial
	skin.set_shader_parameter("skin", true)
	mesh.surface_set_material(1, skin)
	return mesh


static func place(parent: Node, xforms: Array[Transform3D], rng: RandomNumberGenerator, shirts: Array = SHIRTS) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = person_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, (shirts[rng.randi_range(0, shirts.size() - 1)] as Color))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.7, 1.3), 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	return mmi
