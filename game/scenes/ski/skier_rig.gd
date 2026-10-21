class_name RSSkierRig
extends RSHumanRig
## A skier: a rigged MakeHuman character (CC0, tools/blender/make_skiers.py) in a nylon suit in
## the player's colours, with helmet, goggles, boots, skis and poles built here. Posed
## procedurally like RSSkaterRig: legs are IK onto the skis, arms IK to pose targets (ready
## stance, racing tuck, pole plants, double-pole pushes, grabs), spine and head FK.
## RSSkier sets the pose values every frame and calls update().
##
## Spaces: this node sits on the snow under the middle of the bindings, -Z = where the skis
## point. `spin` leans everything into the turn about the snow contact (inclination) and turns
## it about the vertical (air spins); `body` faces -Z inside it. The skis stay on the snow
## while the body leans: the inside leg folds up.

const SKIERS := [
	"res://assets/characters/skier0.glb",
	"res://assets/characters/skier1.glb",
	"res://assets/characters/skier2.glb",
	"res://assets/characters/skier3.glb",
]
const SKI_LEN := 1.72
const SKI_W := 0.072
const STANCE := 0.115          ## half the distance between the boots
const BOOT_Y := 0.072          ## boot sole above the ski base
const POLE_LEN := 1.2
const PANTS := [Color(0.07, 0.075, 0.09), Color(0.92, 0.92, 0.93), Color(0.1, 0.11, 0.14), Color(0.16, 0.17, 0.2)]

# ---- pose inputs, set by RSSkier -------------------------------------------------
var crouch := 0.3              ## 0 standing tall .. 1 deep
var tuck := 0.0                ## 0..1 racing tuck: chest down, hands in front, poles under the arms
var lean := 0.0                ## rad, inclination into the turn (+ = toward the right of travel)
var edge := 0.0                ## rad, skis edged beyond the body's lean (angulation)
var yaw := 0.0                 ## rad, skis + body turned from the travel direction (spins)
var wedge := 0.0               ## 0..1 snowplough: tips together, tails apart
var grounded := 1.0            ## 1 on the snow, 0 in the air (skis follow the feet, not the snow)
var plant := -1.0              ## pole plant cycle 0..1, < 0 = none
var plant_side := 1.0          ## +1 right pole, -1 left
var push := -1.0               ## double-pole push cycle 0..1, < 0 = not pushing
var grab := 0                  ## 0 none, 1 mute, 2 safety, 3 tail, 4 japan
var feet_lift := 0.0           ## 0..1, knees pulled up in the air
var arms := 0.0                ## 0 ready stance .. 1 spread for balance
var cheer := 0.0               ## 0..1 podium: poles up
var impacts := 0.0             ## landing impulses since the last read (for replays)

var spin := Node3D.new()

var _color := Color.WHITE
var _variant := 0
var _crouch := 0.3
var _tuck := 0.0
var _arms := 0.0
var _feet := 0.0
var _grab_w := 0.0
var _grab_kind := 1
var _lean := 0.0
var _edge := 0.0
var _wedge := 0.0
var _ground := 1.0
var _squash := 0.0
var _squash_v := 0.0
var _time := 0.0
var _push_w := 0.0
var _plant_w := 0.0
var _cheer := 0.0
var _crash := false
var _crash_t := 0.0
var _crash_side := 1.0

var _skis: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _boots: Array[Node3D] = []
var _cuffs: Array[Node3D] = []
var _helmet := Node3D.new()


func _init(color: Color = Color.WHITE, variant: int = 0) -> void:
	_color = color
	_variant = variant


func _ready() -> void:
	add_child(spin)
	spin.add_child(body)
	_build_body()
	_build_gear()
	update(0.0)


func impact(strength: float) -> void:
	## Landing: knees soak it up (a damped spring on the crouch).
	_squash_v += strength
	impacts += strength


func start_crash() -> void:
	_crash = true
	_crash_t = 0.0
	_crash_side = 1.0 if randf() < 0.5 else -1.0


func end_crash() -> void:
	_crash = false


func is_crashing() -> bool:
	return _crash


func ski_tip(i: int) -> Vector3:
	## World position of a ski's tail (spray comes off the tails).
	return _skis[i].global_transform * Vector3(0, 0, SKI_LEN * 0.42)


# --------------------------------------------------------------------------- update ----

func update(dt: float) -> void:
	_time += dt
	var k := 1.0 - exp(-dt * 12.0)
	_crouch = lerpf(_crouch, crouch, k)
	_tuck = lerpf(_tuck, tuck, 1.0 - exp(-dt * 6.0))
	_arms = lerpf(_arms, arms, 1.0 - exp(-dt * 7.0))
	_feet = lerpf(_feet, feet_lift, 1.0 - exp(-dt * 10.0))
	_grab_w = move_toward(_grab_w, 1.0 if grab != 0 else 0.0, dt * 7.0)
	if grab != 0:
		_grab_kind = grab
	_lean = lerpf(_lean, lean, 1.0 - exp(-dt * 10.0))
	_edge = lerpf(_edge, edge, 1.0 - exp(-dt * 10.0))
	_wedge = lerpf(_wedge, wedge, 1.0 - exp(-dt * 6.0))
	_ground = lerpf(_ground, grounded, 1.0 - exp(-dt * 14.0))
	_push_w = move_toward(_push_w, 1.0 if push >= 0.0 else 0.0, dt * 5.0)
	_plant_w = move_toward(_plant_w, 1.0 if plant >= 0.0 else 0.0, dt * 8.0)
	_cheer = lerpf(_cheer, cheer, 1.0 - exp(-dt * 5.0))
	_squash_v += (-_squash * 200.0 - _squash_v * 20.0) * dt
	_squash = clampf(_squash + _squash_v * dt, -0.15, 0.5)
	spin.basis = Basis(Vector3.BACK, -_lean) * Basis(Vector3.UP, yaw)
	if _crash:
		_crash_t += dt
		var fall := smoothstep(0.0, 0.45, _crash_t)
		var bounce := absf(sin(minf(_crash_t - 0.45, 0.5) * TAU)) * 0.05 * float(_crash_t > 0.45) * maxf(0.0, 1.0 - (_crash_t - 0.45) * 2.0)
		body.transform = Transform3D(Basis(Vector3.BACK, -_crash_side * 1.3 * fall) * Basis(Vector3.RIGHT, 0.25 * fall), Vector3(0, bounce + 0.06 * fall, 0))
		_crouch = lerpf(_crouch, 0.5, 1.0 - exp(-dt * 6.0))
		_arms = lerpf(_arms, 1.0, 1.0 - exp(-dt * 6.0))
		_tuck = 0.0
		_grab_w = 0.0
	else:
		body.transform = Transform3D()
	_layout_body()


func _layout_body() -> void:
	var c := clampf(_crouch + _squash, -0.1, 1.15)
	var tk := _tuck * (1.0 - _grab_w)
	var face := clampf(_cheer * 2.0, 0.0, 1.0)

	# Skis: on the snow plane (seen from the leaning body), or under the feet in the air.
	var up_s := (spin.basis.inverse() * Vector3.UP).normalized().lerp(Vector3.UP, 1.0 - _ground).normalized()
	var lift := Vector3(0, 0.34 * _feet + 0.12 * _grab_w, -0.05 * _feet)
	var soles: Array[Vector3] = []
	var ski_ups: Array[Vector3] = []
	var ski_fwd: Array[Vector3] = []
	for i in 2:
		var sx := (-1.0 if i == 0 else 1.0) * (STANCE + 0.05 * _wedge)
		var on_snow := Vector3(sx, -up_s.x * sx / up_s.y, 0.0)
		var at := on_snow.lerp(Vector3(sx, 0.0, 0.0), 1.0 - _ground) + lift
		at += up_s * (SKI_W * 0.5 * absf(sin(_lean + _edge))) * _ground
		var wy := (-0.32 if i == 0 else 0.32) * _wedge
		var b := Basis(Vector3.BACK, -_edge * _ground) * Basis(Vector3.UP, wy)
		if _ground < 0.99:
			b = b.slerp(Basis(Vector3.RIGHT, 0.12 * _feet), 1.0 - _ground)
		var xf := Transform3D(b, at)
		_skis[i].transform = body.transform.affine_inverse() * xf if not _crash else xf
		soles.append(xf * Vector3(0, BOOT_Y, 0))
		ski_ups.append(b.y)
		ski_fwd.append(-b.z)
	if _crash:
		# Skis stay put on the snow while the body tumbles; the legs follow the body.
		for i in 2:
			soles[i] = body.transform.affine_inverse() * soles[i]
			ski_ups[i] = body.transform.basis.inverse() * ski_ups[i]
			ski_fwd[i] = body.transform.basis.inverse() * ski_fwd[i]

	var push_env := sin(PI * clampf(push, 0.0, 1.0)) * _push_w if push >= 0.0 else 0.0
	var bend := 0.18 + 0.35 * c + 1.05 * tk + 0.35 * push_env + 0.3 * _grab_w
	bend *= 1.0 - face * 0.8
	var legs := _thigh_len + _shin_len
	var knees := lerpf(lerpf(0.95, 0.6, clampf(c, 0.0, 1.0)), 0.52, tk)
	knees = lerpf(knees, 0.42, _grab_w)
	var foot_y := (soles[0].y + soles[1].y) * 0.5
	var hip_y := foot_y + _ankle_h + legs * knees
	var hip_z := 0.06 + 0.12 * c + 0.12 * tk - 0.08 * _feet
	var bob := sin(_time * 2.6) * 0.004
	var hips := Vector3(0.0, hip_y + bob, hip_z)
	# Angulation: the upper body stays more upright than the legs in a turn.
	var counter := _lean * 0.45 * _ground
	var pelvis_basis := Basis(Vector3.BACK, counter * 0.4) * Basis(Vector3.RIGHT, -bend * 0.45)
	var chest_basis := pelvis_basis * Basis(Vector3.BACK, counter * 0.6) * Basis(Vector3.UP, -_lean * 0.25 * _ground) * Basis(Vector3.RIGHT, -bend * 0.55)
	var head_basis := Basis(Vector3.BACK, counter) * Basis(Vector3.RIGHT, -0.12 + (bend - 0.2) * 0.55 * (1.0 - face) + 0.2 * face)

	var pelvis: int = _bone["pelvis"]
	var rest_p: Transform3D = _rest[pelvis]
	_pose[pelvis] = Transform3D(pelvis_basis * rest_p.basis, hips + pelvis_basis * (rest_p.origin - _hip_mid))
	var pq := pelvis_basis.get_rotation_quaternion()
	var cq := chest_basis.get_rotation_quaternion()
	_fk("spine_01", Basis(pq.slerp(cq, 0.33)))
	_fk("spine_02", Basis(pq.slerp(cq, 0.67)))
	_fk("spine_03", chest_basis)
	_fk("neck_01", Basis(cq.slerp(head_basis.get_rotation_quaternion(), 0.5)))
	_fk("head", head_basis)

	# Legs onto the bindings; knees forward over the toes (ski boots lean the shins).
	for i in 2:
		var s := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		var up: Vector3 = ski_ups[i]
		var t: Vector3 = ski_fwd[i]
		t = (t - up * t.dot(up)).normalized()
		var ankle: Vector3 = soles[i] + up * _ankle_h - t * _ankle_back
		_limb("thigh" + s, "calf" + s, ankle, _thigh_len, _shin_len, Vector3(side * 0.25, 0.0, -1.0), Vector3.LEFT)
		_fk("foot" + s, _frame(up, t) * _frame(Vector3.UP, Vector3.FORWARD).transposed())
		_place_boot(i, soles[i], up, t)

	# Arms: ready stance (hands forward, poles back), tuck, pole plant, double-pole, grabs.
	var ready := [Vector3(-0.2, -0.36, -0.3), Vector3(0.2, -0.36, -0.3)]
	var spread := [Vector3(-0.55, -0.12, -0.12), Vector3(0.55, -0.12, -0.12)]
	var sway := sin(_time * 2.1) * 0.02
	var plant_env := sin(PI * clampf(plant, 0.0, 1.0)) * _plant_w if plant >= 0.0 else 0.0
	var hands: Array[Vector3] = []
	for i in 2:
		var s := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		_fk("clavicle" + s, chest_basis * Basis(Vector3.BACK, side * _arms * 0.1))
		var shoulder := _joint("upperarm" + s)
		var local: Vector3 = (ready[i] as Vector3) + Vector3(0, sway * side, 0)
		# Tuck: fists together in front of the knees (placed in body space, not off the chest).
		local = local.lerp(chest_basis.inverse() * (hips + Vector3(side * 0.12, 0.1, -0.5) - shoulder), tk)
		local = local.lerp(spread[i], _arms)
		if plant_env > 0.0 and signf(plant_side) == side:
			local = local.lerp(Vector3(side * 0.24, -0.3, -0.5), plant_env)
		if push >= 0.0 and _push_w > 0.0:
			var p := push
			var swing: Vector3
			if p < 0.35:
				swing = Vector3(side * 0.22, -0.05, -0.5).lerp(Vector3(side * 0.22, -0.2, -0.45), p / 0.35)
			elif p < 0.75:
				swing = Vector3(side * 0.22, -0.2, -0.45).lerp(Vector3(side * 0.24, -0.62, 0.18), (p - 0.35) / 0.4)
			else:
				swing = Vector3(side * 0.24, -0.62, 0.18).lerp(Vector3(side * 0.22, -0.05, -0.5), (p - 0.75) / 0.25)
			local = local.lerp(swing, _push_w)
		var up_w := clampf(_cheer * 2.0 - (0.0 if i == 1 else 1.0), 0.0, 1.0)
		if up_w > 0.0:
			local = local.lerp(Vector3(side * 0.22, 0.5 + 0.04 * sin(_time * 7.0 + i), -0.05), up_w)
		var hand := shoulder + chest_basis * local
		if _grab_w > 0.0 and i == _grab_hand(_grab_kind):
			hand = hand.lerp(_grab_point(_grab_kind, soles, ski_fwd), _grab_w)
		hands.append(hand)
		var pole := chest_basis * Vector3(side * 0.6, -0.5, 0.6)
		_limb("upperarm" + s, "lowerarm" + s, hand, _upper_len, _fore_len, pole, Vector3.ZERO)
		_fk("hand" + s, _delta("lowerarm" + s) * Basis(Vector3.BACK, side * 0.25))

	# Poles: from the grip, pointing back and down, under the arms in a tuck, into the snow
	# for a plant or a push, up in the air on the podium.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hb: Transform3D = _pose[_bone["hand_l" if i == 0 else "hand_r"]]
		var grip := hb.origin + hb.basis.y.normalized() * 0.075 + hb.basis.z.normalized() * 0.01 * side
		var dir := Vector3(side * 0.14, -0.72, 0.68).normalized()
		dir = dir.slerp(Vector3(side * 0.12, 0.18, 1.0).normalized(), tk)
		dir = dir.slerp(Vector3(side * 0.5, -0.6, 0.6).normalized(), _arms * 0.8)
		if plant_env > 0.0 and signf(plant_side) == side:
			var tip := Vector3(side * 0.42, foot_y - BOOT_Y, -0.55)
			dir = dir.slerp((tip - grip).normalized(), plant_env)
		if push >= 0.0 and _push_w > 0.0:
			var z := lerpf(-0.35, 0.65, clampf((push - 0.25) / 0.55, 0.0, 1.0))
			var tip := Vector3(side * 0.34, foot_y - BOOT_Y, z)
			var down := (tip - grip).normalized()
			dir = dir.slerp(down, _push_w * clampf(1.0 - absf(push - 0.55) / 0.35, 0.0, 1.0))
		dir = dir.slerp(Vector3(side * 0.25, 1.0, 0.1).normalized(), clampf(_cheer * 2.0 - (0.0 if i == 1 else 1.0), 0.0, 1.0))
		if _grab_w > 0.0:
			dir = dir.slerp(Vector3(side * 0.6, -0.2, 0.8).normalized(), _grab_w * 0.7)
		_poles[i].transform = Transform3D(_frame(-dir, Vector3.RIGHT), grip)

	var head: Transform3D = _pose[_bone["head"]]
	_helmet.transform = head
	_apply_pose()


func _grab_hand(kind: int) -> int:
	return 0 if kind in [1, 4] else 1


func _grab_point(kind: int, soles: Array[Vector3], fwd: Array[Vector3]) -> Vector3:
	## Where the grabbing hand goes on a ski (body space).
	match kind:
		1:
			return soles[1] + fwd[1] * 0.32 + Vector3(0, 0.03, 0)        # mute: left hand, right ski's front
		2:
			return soles[1] + fwd[1] * 0.02 + Vector3(0.09, 0.0, 0)      # safety: right hand, under the boot
		3:
			return soles[1] - fwd[1] * 0.55 + Vector3(0.03, 0.0, 0)      # tail
	return soles[0] - fwd[0] * 0.2 + Vector3(-0.08, 0.02, 0)               # japan: left hand behind the boot


func _place_boot(i: int, sole: Vector3, up: Vector3, fwd: Vector3) -> void:
	_boots[i].position = sole
	_boots[i].basis = Basis(up.cross(-fwd).normalized(), up, -fwd.normalized()).orthonormalized()
	# The cuff follows the shin, from the ankle up.
	var calf: Transform3D = _pose[_bone["calf_l" if i == 0 else "calf_r"]]
	var foot: Transform3D = _pose[_bone["foot_l" if i == 0 else "foot_r"]]
	var shin := (calf.origin - foot.origin).normalized()
	var side := shin.cross(fwd).normalized()
	_cuffs[i].transform = Transform3D(Basis(side, shin, side.cross(shin)).orthonormalized(), foot.origin + shin * 0.02)


# -------------------------------------------------------------------------- body ----

func _build_body() -> void:
	var rider := _load_character(SKIERS[_variant % SKIERS.size()])
	var jacket := StandardMaterial3D.new()
	var pants := StandardMaterial3D.new()
	var glove := _mat(Color(0.05, 0.05, 0.06), 0.55)
	for mi: MeshInstance3D in rider.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name).to_lower()
		if nm.contains("shoes"):
			mi.visible = false           # inside the ski boots
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m == null:
				continue
			match m.resource_name:
				"jacket":
					jacket = _nylon(m, _color, 0.42)
					mi.set_surface_override_material(s, jacket)
				"pants":
					pants = _nylon(m, PANTS[_variant % PANTS.size()], 0.6)
					mi.set_surface_override_material(s, pants)
				"glove":
					mi.set_surface_override_material(s, glove)


func _nylon(src: StandardMaterial3D, color: Color, roughness: float) -> StandardMaterial3D:
	## Ski wear: the garment's folds (normal map) in a plain colour with a soft sheen.
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.normal_enabled = src.normal_enabled
	m.normal_texture = src.normal_texture
	m.normal_scale = 1.4
	m.roughness = roughness
	m.metallic_specular = 0.6
	m.rim_enabled = true
	m.rim = 0.15
	m.rim_tint = 0.6
	return m


# -------------------------------------------------------------------------- gear ----

func _build_gear() -> void:
	var top := _mat(Color.WHITE, 0.25, 0.0, _topsheet_texture())
	var base := _mat(Color(0.06, 0.06, 0.07), 0.3)
	var steel := _mat(Color(0.7, 0.72, 0.74), 0.25, 1.0)
	var black := _mat(Color(0.08, 0.08, 0.09), 0.45)
	var binding := _mat(_color.lerp(Color(0.85, 0.86, 0.88), 0.55), 0.35, 0.6)
	var ski_mesh := _ski_mesh()
	for i in 2:
		var ski := Node3D.new()
		spin.add_child(ski)
		var mi := _mi(ski_mesh, null, ski)
		mi.set_surface_override_material(0, top)
		mi.set_surface_override_material(1, base)
		mi.set_surface_override_material(2, steel)
		# Binding: toe piece, heel piece, the plate between.
		_mi(RSMeshUtil.rounded_box(Vector3(0.068, 0.022, 0.42), 0.008, 3, 6), black, ski, Transform3D(Basis(), Vector3(0, 0.022, 0.02)))
		_mi(RSMeshUtil.rounded_box(Vector3(0.07, 0.05, 0.08), 0.015, 3, 6), binding, ski, Transform3D(Basis(), Vector3(0, 0.05, -0.17)))
		_mi(RSMeshUtil.rounded_box(Vector3(0.07, 0.06, 0.1), 0.015, 3, 6), binding, ski, Transform3D(Basis(), Vector3(0, 0.055, 0.2)))
		_skis.append(ski)
	# Boots: a shell around the foot and a cuff around the lower shin, buckles on the cuff.
	var shell := _mat(_color.lerp(Color(0.95, 0.95, 0.96), 0.7), 0.28, 0.0)
	var dark_shell := _mat(Color(0.1, 0.1, 0.12), 0.35)
	for i in 2:
		var boot := Node3D.new()
		body.add_child(boot)
		_mi(RSMeshUtil.rounded_box(Vector3(0.115, 0.1, 0.32), 0.03, 4, 8), dark_shell, boot, Transform3D(Basis(), Vector3(0, 0.05, -0.015)))
		_mi(RSMeshUtil.rounded_box(Vector3(0.118, 0.03, 0.33), 0.012, 3, 6), black, boot, Transform3D(Basis(), Vector3(0, 0.012, -0.015)))
		_boots.append(boot)
		var cuff := Node3D.new()
		body.add_child(cuff)
		_mi(RSMeshUtil.rounded_box(Vector3(0.13, 0.25, 0.15), 0.045, 4, 8), shell, cuff, Transform3D(Basis(), Vector3(0, 0.1, 0.0)))
		for b in 3:
			_mi(RSMeshUtil.rounded_box(Vector3(0.02, 0.012, 0.05), 0.004, 2, 4), steel, cuff,
				Transform3D(Basis(), Vector3(0.066, 0.03 + b * 0.075, -0.02)))
		_cuffs.append(cuff)
	# Poles: grip, strap, shaft, basket, tip; built hanging down from the grip (origin).
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.009
	shaft.bottom_radius = 0.006
	shaft.height = POLE_LEN - 0.12
	shaft.radial_segments = 8
	shaft.rings = 1
	var grip := CylinderMesh.new()
	grip.top_radius = 0.019
	grip.bottom_radius = 0.016
	grip.height = 0.15
	grip.radial_segments = 10
	grip.rings = 1
	var basket := CylinderMesh.new()
	basket.top_radius = 0.045
	basket.bottom_radius = 0.045
	basket.height = 0.008
	basket.radial_segments = 14
	basket.rings = 1
	var pole_paint := _mat(_color.lerp(Color(0.15, 0.15, 0.17), 0.3), 0.3, 0.7)
	for i in 2:
		var pole := Node3D.new()
		body.add_child(pole)
		_mi(grip, black, pole, Transform3D(Basis(), Vector3(0, -0.02, 0)))
		_mi(shaft, pole_paint, pole, Transform3D(Basis(), Vector3(0, -0.06 - shaft.height * 0.5, 0)))
		_mi(basket, black, pole, Transform3D(Basis(), Vector3(0, -POLE_LEN + 0.09, 0)))
		_poles.append(pole)
	_build_helmet()


func _build_helmet() -> void:
	## Shell in the player's colour over the top of the head, goggles on the front with a
	## mirrored lens. Hangs off the head bone; sized from the head joint to the crown.
	body.add_child(_helmet)
	var head := rest_point("head")
	var crown_h := 0.2
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower().contains("body"):
			crown_h = maxf(crown_h, (_to_body * mi.get_aabb()).end.y - head.y)
	var inv := (_rest[_bone["head"]] as Transform3D).basis.inverse()
	var centre := inv * Vector3(0, crown_h - 0.1, 0.012)
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.142
	shell_mesh.height = 0.125         # a hemisphere's height is the dome's own
	shell_mesh.is_hemisphere = true
	shell_mesh.radial_segments = 28
	shell_mesh.rings = 10
	var shell := _mat(_color.darkened(0.08), 0.22, 0.0)
	shell.clearcoat_enabled = true
	shell.clearcoat = 0.8
	var holder := Node3D.new()
	holder.transform = Transform3D(inv, Vector3.ZERO)
	_helmet.add_child(holder)
	var up := Vector3(0, crown_h - 0.13, -0.012)
	_mi(shell_mesh, shell, holder, Transform3D(Basis().scaled(Vector3(0.94, 1.0, 1.1)), up - Vector3(0, 0.03, 0)))
	# Goggles: strap ring, frame and lens across the eyes.
	var strap := CylinderMesh.new()
	strap.top_radius = 0.131
	strap.bottom_radius = 0.133
	strap.height = 0.042
	strap.radial_segments = 28
	strap.rings = 1
	strap.cap_top = false
	strap.cap_bottom = false
	var black := _mat(Color(0.06, 0.06, 0.07), 0.6)
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	var eyes_y := up.y - 0.07
	_mi(strap, black, holder, Transform3D(Basis().scaled(Vector3(0.95, 1.0, 1.1)), Vector3(0, eyes_y, up.z - 0.005)))
	var frame := RSMeshUtil.rounded_box(Vector3(0.19, 0.075, 0.05), 0.022, 4, 8)
	_mi(frame, black, holder, Transform3D(Basis(), Vector3(0, eyes_y, up.z - 0.128)))
	var lens := _mat(Color(1.0, 0.55, 0.15).lerp(_color, 0.35), 0.06, 1.0)
	lens.metallic_specular = 1.0
	_mi(RSMeshUtil.rounded_box(Vector3(0.175, 0.062, 0.02), 0.016, 4, 8), lens, holder,
		Transform3D(Basis(), Vector3(0, eyes_y, up.z - 0.148)))


func _ski_mesh() -> ArrayMesh:
	## A carving ski: sidecut, tip turned up, a little tail kick, three surfaces (top sheet
	## with the player's graphic, black base, steel edges along the sides).
	var nu := 48
	var half := SKI_LEN * 0.5
	var thick := 0.014
	var top_pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i in nu + 1:
		var u := float(i) / nu                  # 0 tip .. 1 tail
		var z := lerpf(-half, half, u)
		var w := SKI_W * 0.5 * (1.0 + 0.28 * pow(absf(u - 0.52) / 0.5, 2.0))
		if u < 0.08:
			w *= sqrt(maxf(0.0, 1.0 - pow((0.08 - u) / 0.08, 2.0))) * 0.9 + 0.1
		elif u > 0.97:
			w *= 0.75 + 0.25 * (1.0 - (u - 0.97) / 0.03)
		var y := 0.0
		if u < 0.13:
			y = 0.075 * pow((0.13 - u) / 0.13, 2.0)
		elif u > 0.93:
			y = 0.02 * pow((u - 0.93) / 0.07, 2.0)
		y += thick * (1.0 - 0.4 * absf(u - 0.5) * 2.0)
		for j in 2:
			top_pts.append(Vector3((-1.0 if j == 0 else 1.0) * w, y, z))
			uvs.append(Vector2(u, float(j)))
	var mesh := ArrayMesh.new()
	for part in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for idx in top_pts.size():
			var p := top_pts[idx]
			st.set_uv(uvs[idx])
			st.add_vertex(p if part == 0 else Vector3(p.x, p.y - thick * (1.0 - 0.4 * absf(uvs[idx].x - 0.5) * 2.0), p.z))
		for i in nu:
			var a := i * 2
			var b := a + 2
			var tris := [a, a + 1, b, b, a + 1, b + 1] if part == 0 else [a, b, a + 1, b, b + 1, a + 1]
			for t: int in tris:
				st.add_index(t)
		st.generate_normals()
		st.commit(mesh)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 2:
		var out := Vector3(-1.0 if j == 0 else 1.0, 0, 0)
		for i in nu:
			var p0 := top_pts[i * 2 + j]
			var p1 := top_pts[(i + 1) * 2 + j]
			var d0 := Vector3(0, -thick * (1.0 - 0.4 * absf(float(i) / nu - 0.5) * 2.0), 0)
			var d1 := Vector3(0, -thick * (1.0 - 0.4 * absf(float(i + 1) / nu - 0.5) * 2.0), 0)
			var quad := [p0, p1, p1 + d1, p0 + d0]
			if (quad[2] - quad[0]).cross(quad[1] - quad[0]).dot(out) < 0.0:
				quad = [p0, p0 + d0, p1 + d1, p1]
			for k: int in [0, 1, 2, 0, 2, 3]:
				rim.set_normal(out)
				rim.add_vertex(quad[k])
	rim.commit(mesh)
	return mesh


func _topsheet_texture() -> ImageTexture:
	## Top sheet: the player's colour fading to white, a stripe along each side, a chevron
	## logo ahead of the binding and the tip in black.
	var w := 256
	var h := 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var white := Color(0.95, 0.95, 0.96)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var c := _color.lerp(white, smoothstep(0.3, 0.8, u))
			if absf(v - 0.5) > 0.36:
				c = Color(0.1, 0.1, 0.12)
			var chev := fposmod(u * 18.0 + absf(v - 0.5) * 4.0, 1.0)
			if u > 0.18 and u < 0.34 and chev < 0.3 and absf(v - 0.5) < 0.3:
				c = white if u < 0.3 else _color
			if u < 0.06:
				c = Color(0.08, 0.08, 0.1)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
