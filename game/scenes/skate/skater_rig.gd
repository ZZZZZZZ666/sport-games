class_name RSSkaterRig
extends RSHumanRig
## The skater and the board. The rider is a rigged MakeHuman character (CC0, built by
## tools/blender/make_skaters.py) posed procedurally, with no animation files: legs are two-bone
## IK onto the board so crouching, popping, landing and carving keep the feet planted, arms are
## IK to pose targets (relaxed, balance, grabs), the spine and head are FK. RSSkater sets the
## pose values every frame and calls update().
##
## Spaces: this node sits at the board's wheel contact point, -Z = direction of travel.
## `spin` turns board + body together (spins, fakie, boardslides) and leans into turns.
## The body's own space faces -Z with the board along X (nose = -X): regular stance, left foot
## forward. The character's skeleton faces +Z, so it hangs under `body` turned half round.

const DECK_Y := 0.105          ## deck top above the wheel contact point
const BOARD_C := 0.065         ## height of the flip axis
const TRUCK_Z := 0.215
const FRONT_FOOT := -0.185     ## along the board, - = toward the nose
const BACK_FOOT := 0.2

const RIDERS := [
	"res://assets/characters/rider0.glb",
	"res://assets/characters/rider1.glb",
	"res://assets/characters/rider2.glb",
	"res://assets/characters/rider3.glb",
]

# ---- pose inputs, set by RSSkater -------------------------------------------------
var crouch := 0.3              ## 0 standing tall .. 1 deep squat
var lean := 0.0                ## rad, roll into a turn (+ = toward the right of travel)
var yaw := 0.0                 ## rad, board + body turned from the travel direction
var flip := 0.0                ## rad, board roll about its long axis (kickflips)
var board_pitch := 0.0         ## rad, + = nose up (pivots on the back truck)
var board_lift := 0.0          ## m, board raised from the contact point (grabs)
var feet_lift := 0.0           ## 0..1, feet pulled up off the board (flip tuck)
var arms := 0.0                ## 0 relaxed .. 1 spread for balance
var balance := 0.0             ## -1..1, seesaw of the arms and torso
var push := -1.0               ## push cycle 0..1, < 0 = not pushing
var grab := 0                  ## 0 none, 1 indy, 2 melon, 3 nosegrab, 4 tailgrab
var wheel_speed := 0.0         ## m/s
var cheer := 0.0               ## 0..1 podium: face front, right arm up (0.5), both arms up (1)
var impacts := 0.0             ## landing impulses since the last read (for replays)

var spin := Node3D.new()
var board := Node3D.new()

var _color := Color.WHITE
var _variant := 0
var _crouch := 0.3
var _arms := 0.0
var _feet := 0.0
var _grab_w := 0.0
var _grab_kind := 1
var _lean := 0.0
var _pitch := 0.0
var _balance := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _wheel_angle := 0.0
var _time := 0.0
var _push_w := 0.0
var _cheer := 0.0
var _bail := false
var _bail_t := 0.0
var _bail_side := 1.0
var _bail_board_pos := Vector3.ZERO
var _bail_board_vel := Vector3.ZERO
var _bail_board_rot := Basis()
var _bail_board_spin := Vector3.ZERO

var _wheels: Array[Node3D] = []


func _init(color: Color = Color.WHITE, variant: int = 0) -> void:
	_color = color
	_variant = variant


func _ready() -> void:
	add_child(spin)
	spin.add_child(board)
	spin.add_child(body)
	body.rotation.y = -PI * 0.5
	_build_board()
	_build_body()
	update(0.0)


func impact(strength: float) -> void:
	## Landing: knees soak it up (a damped spring on the crouch).
	_squash_v += strength
	impacts += strength


func start_bail(speed: float) -> void:
	_bail = true
	_bail_t = 0.0
	_bail_side = 1.0 if randf() < 0.6 else -1.0
	_bail_board_pos = Vector3.ZERO
	_bail_board_vel = Vector3(randf_range(-1.0, 1.0), 2.6, -speed * 0.35)
	_bail_board_rot = Basis()
	_bail_board_spin = Vector3(randf_range(-9.0, 9.0), randf_range(-6.0, 6.0), randf_range(-14.0, 14.0))


func end_bail() -> void:
	_bail = false
	board.visible = true


func is_bailing() -> bool:
	return _bail


func board_world_point(local: Vector3) -> Vector3:
	return board.global_transform * local


# --------------------------------------------------------------------------- update ----

func update(dt: float) -> void:
	_time += dt
	var k := 1.0 - exp(-dt * 12.0)
	_crouch = lerpf(_crouch, crouch, k)
	_arms = lerpf(_arms, arms, 1.0 - exp(-dt * 7.0))
	_feet = lerpf(_feet, feet_lift, 1.0 - exp(-dt * 22.0))
	_grab_w = move_toward(_grab_w, 1.0 if grab != 0 else 0.0, dt * 8.0)
	if grab != 0:
		_grab_kind = grab
	_lean = lerpf(_lean, lean, 1.0 - exp(-dt * 8.0))
	_pitch = lerpf(_pitch, board_pitch, 1.0 - exp(-dt * 20.0))
	_balance = lerpf(_balance, balance, 1.0 - exp(-dt * 10.0))
	_push_w = move_toward(_push_w, 1.0 if push >= 0.0 else 0.0, dt * 6.0)
	_cheer = lerpf(_cheer, cheer, 1.0 - exp(-dt * 5.0))
	_squash_v += (-_squash * 240.0 - _squash_v * 22.0) * dt
	_squash = clampf(_squash + _squash_v * dt, -0.15, 0.45)
	_wheel_angle = fmod(_wheel_angle + wheel_speed / 0.027 * dt, TAU)
	for w in _wheels:
		w.rotation.x = -_wheel_angle
	spin.basis = Basis(Vector3.BACK, -_lean) * Basis(Vector3.UP, yaw)
	if _bail:
		_bail_t += dt
		_update_bail(dt)
		return
	body.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	board.transform = _board_transform()
	_layout_body()


func _board_transform() -> Transform3D:
	# Grabs tuck the board up to the hand on top of what RSSkater asks for.
	var t := Transform3D(Basis(), Vector3(0, board_lift + 0.1 * _grab_w, 0))
	var pivot := TRUCK_Z if _pitch >= 0.0 else -TRUCK_Z
	t = t * Transform3D(Basis(), Vector3(0, 0, pivot)) * Transform3D(Basis(Vector3.RIGHT, _pitch), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, 0, -pivot))
	t = t * Transform3D(Basis(), Vector3(0, BOARD_C, 0)) * Transform3D(Basis(Vector3.BACK, flip), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, -BOARD_C, 0))
	return t


func _layout_body() -> void:
	var to_body := body.transform.affine_inverse() * board.transform
	var board_up := (to_body.basis * Vector3.UP).normalized()
	var toe := (to_body.basis * Vector3.RIGHT).normalized()
	# A flipping board must not drag the feet round with it: use an upright copy.
	var flat_up := board_up if absf(flip) < 0.01 else (to_body.basis * Basis(Vector3.BACK, -flip) * Vector3.UP).normalized()
	var flat_toe := toe if absf(flip) < 0.01 else (to_body.basis * Basis(Vector3.BACK, -flip) * Vector3.RIGHT).normalized()
	var c := clampf(_crouch + _squash, -0.1, 1.15)

	var push_env := 0.0
	var p := push
	if p >= 0.0:
		push_env = sin(PI * clampf(p, 0.0, 1.0))
	var face := clampf(_cheer * 2.0, 0.0, 1.0)
	var twist := (0.35 + 0.85 * push_env * _push_w + _balance * 0.12) * (1.0 - face)
	var bend := 0.12 + 0.55 * c + 0.1 * push_env + 0.5 * _grab_w
	var legs := _thigh_len + _shin_len
	var knees := lerpf(lerpf(0.94, 0.47, clampf(c, 0.0, 1.0)), 0.3, _grab_w)
	var hip_y := DECK_Y + _ankle_h + legs * knees + board_lift * lerpf(0.6, 1.0, _grab_w) + 0.1 * _grab_w
	var hip_x := -0.02 - 0.12 * push_env * _push_w + _pitch * -0.35
	var bob := sin(_time * 3.1) * 0.006
	var hips := Vector3(hip_x, hip_y + bob, 0.02 + 0.06 * c)
	var pelvis_basis := Basis(Vector3.UP, twist * 0.45) * Basis(Vector3.RIGHT, -bend * 0.4) * Basis(Vector3.BACK, _balance * 0.1)
	var chest_basis := pelvis_basis * Basis(Vector3.UP, twist * 0.55) * Basis(Vector3.RIGHT, -bend * 0.6) * Basis(Vector3.BACK, _balance * 0.18)
	var head_basis := Basis(Vector3.UP, (1.15 + twist * 0.3) * (1.0 - face)) * Basis(Vector3.RIGHT, -0.12 - 0.15 * c + 0.2 * face)

	# Spine: FK from the pelvis, the bend spread over the three spine bones.
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

	# Feet: on the board, tucked up in the air, or the back foot pushing off the ground.
	var soles := [to_body * Vector3(0, DECK_Y, FRONT_FOOT), to_body * Vector3(0, DECK_Y, BACK_FOOT)]
	var ups := [flat_up, flat_up]
	var toes := [flat_toe.rotated(flat_up, 0.3), flat_toe.rotated(flat_up, -0.08)]
	for i in 2:
		soles[i] = (soles[i] as Vector3) + (flat_up * 0.3 + Vector3(0, 0.02, 0)) * _feet
	if p >= 0.0 and _push_w > 0.0:
		var spin_to_body := body.transform.affine_inverse()
		var ground_a := spin_to_body * Vector3(0.24, 0.0, -0.1)
		var ground_b := spin_to_body * Vector3(0.24, 0.0, 0.62)
		var foot: Vector3
		if p < 0.22:
			var u := p / 0.22
			foot = (soles[1] as Vector3).lerp(ground_a, u) + Vector3.UP * sin(PI * u) * 0.12
		elif p < 0.65:
			foot = ground_a.lerp(ground_b, (p - 0.22) / 0.43)
		else:
			var u := (p - 0.65) / 0.35
			foot = ground_b.lerp(soles[1], u) + Vector3.UP * sin(PI * u) * 0.18
		soles[1] = (soles[1] as Vector3).lerp(foot, _push_w)
		ups[1] = (ups[1] as Vector3).lerp(Vector3.UP, _push_w * push_env).normalized()
		toes[0] = (toes[0] as Vector3).slerp(Vector3.LEFT, 0.75 * push_env * _push_w)
		toes[1] = (toes[1] as Vector3).slerp(Vector3(-0.6, 0, -0.8).normalized(), push_env * _push_w)
	for i in 2:
		var s := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		var up: Vector3 = ups[i]
		var t: Vector3 = toes[i]
		t = (t - up * t.dot(up)).normalized()
		var ankle: Vector3 = (soles[i] as Vector3) + up * _ankle_h - t * _ankle_back
		_limb("thigh" + s, "calf" + s, ankle, _thigh_len, _shin_len, Vector3(side * 0.8, 0.0, -1.0), Vector3.LEFT)
		_fk("foot" + s, _frame(up, t) * _frame(Vector3.UP, Vector3.FORWARD).transposed())

	# Arms: relaxed, spread for balance (seesawing with the balance meter), or grabbing.
	var relax := [Vector3(-0.1, -0.44, -0.12), Vector3(0.16, -0.43, 0.06)]
	var spread := [Vector3(-0.56, -0.06, -0.08), Vector3(0.56, -0.04, 0.1)]
	var sway := sin(_time * 2.3) * 0.03
	var seesaw := Basis(Vector3.BACK, _balance * 0.45 + sway)
	for i in 2:
		var s := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		_fk("clavicle" + s, chest_basis * Basis(Vector3.BACK, side * _arms * 0.12))
		var shoulder := _joint("upperarm" + s)
		var local: Vector3 = (relax[i] as Vector3).lerp(spread[i], _arms)
		if push_env > 0.0:
			local = local.lerp(Vector3(side * 0.35, -0.3, -0.25 * side), push_env * _push_w)
		# Podium: the right arm goes up first, then both, pumping.
		var up := clampf(_cheer * 2.0 - (0.0 if i == 1 else 1.0), 0.0, 1.0)
		if up > 0.0:
			local = local.lerp(Vector3(side * 0.18, 0.46 + 0.05 * sin(_time * 7.0 + i), -0.06), up)
		var hand := shoulder + chest_basis * (seesaw * local)
		var grab_hand := 0 if _grab_kind in [2, 3] else 1
		if _grab_w > 0.0 and i == grab_hand:
			hand = hand.lerp(to_body * _grab_point(_grab_kind) + Vector3.UP * 0.05, _grab_w)
		var pole := chest_basis * Vector3(side * 0.3, -0.6, 0.7).lerp(Vector3(0, -1.0, 0.25), _arms)
		_limb("upperarm" + s, "lowerarm" + s, hand, _upper_len, _fore_len, pole, Vector3.ZERO)
		_fk("hand" + s, _delta("lowerarm" + s))
	_apply_pose()


func _grab_point(kind: int) -> Vector3:
	match kind:
		1:
			return Vector3(0.11, DECK_Y - 0.01, 0.02)      # indy: back hand, toe edge
		2:
			return Vector3(-0.11, DECK_Y - 0.01, -0.02)    # melon: front hand, heel edge
		3:
			return Vector3(0.0, DECK_Y + 0.03, -0.38)      # nosegrab
	return Vector3(0.0, DECK_Y + 0.03, 0.38)               # tailgrab


func _update_bail(dt: float) -> void:
	# The rider topples like a plank around the feet and slides; the board flies off.
	var t := _bail_t
	var fall := minf(t / 0.42, 1.0)
	fall = fall * fall * (3.0 - 2.0 * fall)
	var angle := _bail_side * 1.38 * fall
	var bounce := absf(sin(minf(t - 0.42, 0.5) * PI * 2.0)) * 0.06 * float(t > 0.42) * maxf(0.0, 1.0 - (t - 0.42) * 2.0)
	body.transform = Transform3D(Basis(Vector3.BACK, -angle) * Basis(Vector3.UP, -PI * 0.5), Vector3(0, bounce + 0.05 * fall, 0))
	_crouch = lerpf(_crouch, 0.25, 1.0 - exp(-dt * 6.0))
	_arms = lerpf(_arms, 1.0, 1.0 - exp(-dt * 6.0))
	_feet = 0.0
	_grab_w = 0.0
	_balance = sin(t * 9.0) * 0.6 * maxf(0.0, 1.0 - t)
	_layout_body()
	# Board: ballistic in the rider's frame, bouncing on the ground.
	_bail_board_vel.y -= 11.0 * dt
	_bail_board_pos += _bail_board_vel * dt
	if _bail_board_pos.y < 0.0:
		_bail_board_pos.y = 0.0
		_bail_board_vel.y = absf(_bail_board_vel.y) * 0.35
		_bail_board_vel.x *= 0.7
		_bail_board_vel.z *= 0.7
		_bail_board_spin *= 0.5
	_bail_board_rot = (_bail_board_rot * Basis.from_euler(_bail_board_spin * dt)).orthonormalized()
	board.transform = Transform3D(_bail_board_rot, _bail_board_pos + Vector3(0, BOARD_C * 0.5, 0))


# ------------------------------------------------------------------------- board ----

func _build_board() -> void:
	var deck := MeshInstance3D.new()
	deck.mesh = _deck_mesh()
	board.add_child(deck)
	var metal := _mat(Color(0.78, 0.79, 0.8), 0.32, 1.0)
	var dark := _mat(Color(0.25, 0.25, 0.27), 0.45, 1.0)
	var urethane := _mat(Color(0.93, 0.9, 0.8), 0.55)
	var base := RSMeshUtil.rounded_box(Vector3(0.07, 0.014, 0.1), 0.005, 4, 8)
	var hanger := RSMeshUtil.rounded_box(Vector3(0.16, 0.026, 0.034), 0.012, 6, 12)
	var axle := CylinderMesh.new()
	axle.top_radius = 0.006
	axle.bottom_radius = 0.006
	axle.height = 0.2
	axle.radial_segments = 6
	axle.rings = 1
	var bush := CylinderMesh.new()
	bush.top_radius = 0.014
	bush.bottom_radius = 0.016
	bush.height = 0.03
	bush.radial_segments = 8
	bush.rings = 1
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.027
	wheel.bottom_radius = 0.027
	wheel.height = 0.032
	wheel.radial_segments = 16
	wheel.rings = 1
	var core := CylinderMesh.new()
	core.top_radius = 0.012
	core.bottom_radius = 0.012
	core.height = 0.034
	core.radial_segments = 8
	core.rings = 1
	var sideways := Basis(Vector3.BACK, PI * 0.5)
	for z: float in [-TRUCK_Z, TRUCK_Z]:
		_mi(base, metal, board, Transform3D(Basis(), Vector3(0, 0.085, z)))
		_mi(bush, _mat(Color(0.95, 0.75, 0.15), 0.5), board, Transform3D(Basis(), Vector3(0, 0.066, z)))
		_mi(hanger, metal, board, Transform3D(Basis(), Vector3(0, 0.045, z)))
		_mi(axle, dark, board, Transform3D(sideways, Vector3(0, 0.027, z)))
		for x: float in [-0.085, 0.085]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, 0.027, z)
			board.add_child(pivot)
			_mi(wheel, urethane, pivot, Transform3D(sideways, Vector3.ZERO))
			_mi(core, dark, pivot, Transform3D(sideways, Vector3.ZERO))
			_wheels.append(pivot)


func _deck_mesh() -> ArrayMesh:
	## Popsicle deck: rounded nose and tail kicked up, a little concave, three materials
	## (grip tape on top, the player's graphic underneath, maple ply on the edge).
	var nu := 40
	var nv := 8
	var half_len := 0.4
	var half_w := 0.104
	var thick := 0.013
	var top_pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i in nu + 1:
		var u := lerpf(-1.0, 1.0, float(i) / nu)
		var au := absf(u)
		var hw := half_w
		if au > 0.72:
			hw = half_w * sqrt(maxf(0.0, 1.0 - pow((au - 0.72) / 0.28, 2.0)))
		var kick := 0.0
		if au > 0.6:
			kick = 0.062 * pow((au - 0.6) / 0.4, 1.6)
		for j in nv + 1:
			var v := lerpf(-1.0, 1.0, float(j) / nv)
			top_pts.append(Vector3(v * hw, DECK_Y + kick + 0.006 * v * v, u * half_len))
			uvs.append(Vector2(u * 0.5 + 0.5, v * 0.5 + 0.5))
	var mesh := ArrayMesh.new()
	var down := Vector3(0, -thick, 0)
	for part in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for idx in top_pts.size():
			st.set_uv(uvs[idx])
			st.add_vertex(top_pts[idx] + (down if part == 1 else Vector3.ZERO))
		for i in nu:
			for j in nv:
				var a := i * (nv + 1) + j
				var b := a + nv + 1
				var c := a + 1
				var d := b + 1
				# Clockwise from above for the top (a, c, b), reversed for the bottom.
				var tris := [a, c, b, b, c, d] if part == 0 else [a, b, c, b, d, c]
				for t: int in tris:
					st.add_index(t)
		st.generate_normals()
		st.commit(mesh)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in [0, nv]:
		for i in nu:
			var p0 := top_pts[i * (nv + 1) + j]
			var p1 := top_pts[(i + 1) * (nv + 1) + j]
			var quad := [p0, p1, p1 + down, p0 + down]
			var mid := (p0 + p1) * 0.5
			var out := Vector3(mid.x, 0, mid.z * 0.25).normalized()
			if (quad[2] - quad[0]).cross(quad[1] - quad[0]).dot(out) < 0.0:
				quad = [p0, p0 + down, p1 + down, p1]
			for k: int in [0, 1, 2, 0, 2, 3]:
				rim.set_normal(out)
				rim.add_vertex(quad[k])
	rim.commit(mesh)
	mesh.surface_set_material(0, _mat(Color.WHITE, 0.95, 0.0, _grip_texture()))
	mesh.surface_set_material(1, _mat(Color.WHITE, 0.3, 0.0, _graphic_texture()))
	mesh.surface_set_material(2, _mat(Color(0.8, 0.62, 0.4), 0.65))
	return mesh


func _grip_texture() -> ImageTexture:
	var img := Image.create_empty(128, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in 32:
		for x in 128:
			var g := 0.1 + rng.randf() * 0.07
			img.set_pixel(x, y, Color(g, g, g * 1.05))
	return ImageTexture.create_from_image(img)


func _graphic_texture() -> ImageTexture:
	## Underside graphic in the player's colour: a fade, chevrons and a ring logo.
	var w := 256
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var light := _color.lightened(0.35)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var c := _color.lerp(light, u)
			var chev := fposmod(u * 10.0 + absf(v - 0.5) * 3.0, 1.0)
			if chev < 0.18 and u > 0.12 and u < 0.42:
				c = Color(0.98, 0.97, 0.94)
			var d := Vector2((u - 0.7) * 4.0, v - 0.5).length()
			if d > 0.26 and d < 0.36:
				c = Color(0.08, 0.08, 0.1)
			elif d < 0.18:
				c = Color(0.98, 0.97, 0.94)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# -------------------------------------------------------------------------- body ----

func _build_body() -> void:
	_load_character(RIDERS[_variant % RIDERS.size()])
