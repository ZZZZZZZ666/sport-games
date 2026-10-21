class_name RSBallerRig
extends RSHumanRig
## A basketball player: a rigged MakeHuman character (CC0, tools/blender/make_ballers.py) whose
## jersey and shorts are repainted in the player's colour, with a number on the back. Posed
## procedurally like the skater and skier rigs: legs IK to the feet, arms IK to hand targets
## around the ball, spine and head FK.
##
## The game picks a move with play(); each move is a function of its own clock (_pose_for),
## and a change of move blends from wherever the body was. hand_ball() is where the ball sits
## in the hands, for the game to put the held ball there. capture() / show_pose() record and
## play back the pose for replays.
##
## Body space: the player faces -Z (the game turns the node to face the rim), +X is the right
## hand side, the floor is y = 0.

enum Move { IDLE, HOLD, PICKUP, SET, SHOOT, WALK, CELEBRATE, SAD, CHEER }

const BALLERS := [
	"res://assets/characters/baller0.glb",
	"res://assets/characters/baller1.glb",
	"res://assets/characters/baller2.glb",
	"res://assets/characters/baller3.glb",
]
const RELEASE_T := 0.1           ## SHOOT: the ball leaves the hand this long after the move starts
const PICK_GRAB := 0.24          ## PICKUP: hands reach the ball
const PICK_T := 0.5              ## PICKUP: back in the triple-threat hold
const BLEND := 0.16
const NUMBERS := [23, 7, 11, 30]


class Pose:
	var hips := Vector3.ZERO
	var bend := 0.0              ## rad, upper body forward
	var twist := 0.0             ## rad, upper body turned (+ = to the left)
	var head := 0.0              ## rad, + = looking up
	var ball := Vector3.ZERO
	var hand_l := Vector3.ZERO   ## wrist targets
	var hand_r := Vector3.ZERO
	var pole_l := Vector3(-1, -1, 0.3)
	var pole_r := Vector3(1, -1, 0.3)
	var foot_l := Vector3.ZERO   ## soles
	var foot_r := Vector3.ZERO
	var toe_l := 0.0             ## foot pitch, - = toes down
	var toe_r := 0.0
	var flex_l := 0.0            ## wrist, + = fingers forward / down (gooseneck), - = cocked back
	var flex_r := 0.0

	func blend(o: Pose, w: float) -> Pose:
		var p := Pose.new()
		p.hips = hips.lerp(o.hips, w)
		p.bend = lerpf(bend, o.bend, w)
		p.twist = lerpf(twist, o.twist, w)
		p.head = lerpf(head, o.head, w)
		p.ball = ball.lerp(o.ball, w)
		p.hand_l = hand_l.lerp(o.hand_l, w)
		p.hand_r = hand_r.lerp(o.hand_r, w)
		p.pole_l = pole_l.lerp(o.pole_l, w)
		p.pole_r = pole_r.lerp(o.pole_r, w)
		p.foot_l = foot_l.lerp(o.foot_l, w)
		p.foot_r = foot_r.lerp(o.foot_r, w)
		p.toe_l = lerpf(toe_l, o.toe_l, w)
		p.toe_r = lerpf(toe_r, o.toe_r, w)
		p.flex_l = lerpf(flex_l, o.flex_l, w)
		p.flex_r = lerpf(flex_r, o.flex_r, w)
		return p

	func pack() -> Array:
		return [hips, bend, twist, head, ball, hand_l, hand_r, pole_l, pole_r, foot_l, foot_r, toe_l, toe_r, flex_l, flex_r]

	static func unpack(a: Array) -> Pose:
		var p := Pose.new()
		p.hips = a[0]
		p.bend = a[1]
		p.twist = a[2]
		p.head = a[3]
		p.ball = a[4]
		p.hand_l = a[5]
		p.hand_r = a[6]
		p.pole_l = a[7]
		p.pole_r = a[8]
		p.foot_l = a[9]
		p.foot_r = a[10]
		p.toe_l = a[11]
		p.toe_r = a[12]
		p.flex_l = a[13]
		p.flex_r = a[14]
		return p


var move := Move.IDLE
var move_t := 0.0
var walk_speed := 0.0            ## m/s, WALK
var pick_at := Vector3(0.56, 0.92, 0.25)   ## PICKUP: the ball on the rack, body space
var number := 0

var _color := Color.WHITE
var _variant := 0
var _cur := Pose.new()
var _from := Pose.new()
var _phase := 0.0
var _time := 0.0
var _seed := 0.0
var _sh := 1.45                  ## shoulder height (rest)
var _legs := 0.86
var _num: Label3D
var _replay := false


func _init(color: Color = Color.WHITE, variant: int = 0) -> void:
	_color = color
	_variant = variant
	number = NUMBERS[variant % NUMBERS.size()]
	_seed = variant * 1.7


func _ready() -> void:
	add_child(body)
	_build_body()
	_sh = rest_point("upperarm_r").y
	_legs = _thigh_len + _shin_len
	_cur = _pose_for(Move.IDLE, 0.0)
	_from = _cur
	update(0.0)


func play(m: Move) -> void:
	_from = _cur
	move = m
	move_t = 0.0
	_replay = false


func hand_ball() -> Vector3:
	## Where the ball's centre is in the hands this frame, world space.
	return global_transform * _cur.ball


func capture() -> Array:
	return _cur.pack()


func show_pose(a: Array) -> void:
	## Replays: pose straight from a recorded frame.
	_replay = true
	_cur = Pose.unpack(a)
	_layout()


func update(dt: float) -> void:
	if _replay:
		return
	_time += dt
	move_t += dt
	if move == Move.WALK:
		_phase = fmod(_phase + dt * walk_speed / 1.5, 1.0)
	var target := _pose_for(move, move_t)
	_cur = _from.blend(target, smoothstep(0.0, BLEND, move_t)) if move_t < BLEND else target
	_layout()


# --------------------------------------------------------------------------- moves ----

func _hips(c: float, lift: float = 0.0) -> Vector3:
	## Hips for a crouch (0 standing .. 1 deep) with the feet `lift` off the floor.
	return Vector3(0.0, lift + _ankle_h + _legs * (0.965 - 0.28 * c), 0.03 + 0.07 * c)


func _stance(p: Pose, lift: float = 0.0) -> void:
	p.foot_l = Vector3(-0.15, lift, 0.06)
	p.foot_r = Vector3(0.15, lift, -0.07)


func _pose_for(m: Move, t: float) -> Pose:
	var p := Pose.new()
	var breathe := sin(_time * 1.7 + _seed) * 0.01
	_stance(p)
	match m:
		Move.IDLE:
			p.hips = _hips(0.06 + breathe)
			p.bend = 0.04
			p.head = 0.05
			p.hand_l = Vector3(-0.23, _sh - 0.5, 0.03 + breathe)
			p.hand_r = Vector3(0.23, _sh - 0.5, 0.03 - breathe)
			p.ball = p.hand_r + Vector3(0.05, -0.08, -0.08)
			p.pole_l = Vector3(-1, -0.2, 0.6)
			p.pole_r = Vector3(1, -0.2, 0.6)
		Move.HOLD:
			_hold(p, breathe)
		Move.PICKUP:
			# Turn and reach down to the rack, both hands on the ball, then up into the hold.
			var hold := Pose.new()
			_stance(hold)
			_hold(hold, breathe)
			var reach := Pose.new()
			reach.hips = _hips(0.45)
			reach.bend = 0.45
			reach.twist = -0.55
			reach.head = -0.25
			reach.ball = pick_at
			var side := Basis(Vector3.UP, -0.55)
			reach.hand_l = pick_at + side * Vector3(-0.15, 0.03, 0.04)
			reach.hand_r = pick_at + side * Vector3(0.15, 0.03, 0.04)
			reach.pole_l = Vector3(-0.6, -0.4, 0.8)
			reach.pole_r = Vector3(1, -0.2, 0.5)
			reach.foot_l = Vector3(-0.14, 0, 0.08)
			reach.foot_r = Vector3(0.3, 0, 0.02)
			var w := smoothstep(0.0, PICK_GRAB, t) if t < PICK_GRAB else 1.0 - smoothstep(PICK_GRAB, PICK_T, t)
			var idle := _pose_for(Move.IDLE, 0.0)
			p = (idle if t < PICK_GRAB else hold).blend(reach, w)
			if t >= PICK_GRAB:
				p.ball = pick_at.lerp(hold.ball, smoothstep(PICK_GRAB, PICK_T, t))
		Move.SET:
			_set_pose(p, minf(t / 0.22, 1.0))
		Move.SHOOT:
			_shoot(p, t)
		Move.WALK:
			_walk(p)
		Move.CELEBRATE:
			var pump := absf(sin(t * 7.0)) if t < 1.2 else 1.0
			var hop := maxf(0.0, sin(t * 7.0)) * 0.06 if t < 1.0 else 0.0
			_stance(p, hop)
			p.hips = _hips(0.15, hop)
			p.bend = -0.05
			p.head = 0.15
			p.hand_r = Vector3(0.26, _sh + 0.12 + 0.2 * pump + hop, -0.08)
			p.pole_r = Vector3(1, -0.3, 0.2)
			p.hand_l = Vector3(-0.22, _sh - 0.45 + hop, 0.0)
			p.pole_l = Vector3(-1, -0.2, 0.5)
			p.ball = p.hand_r
		Move.CHEER:
			var hop := maxf(0.0, sin(t * 6.0)) * 0.12
			_stance(p, hop)
			p.hips = _hips(0.1, hop)
			p.bend = -0.1
			p.head = 0.25
			var wave := sin(t * 6.0) * 0.05
			p.hand_l = Vector3(-0.36, _sh + 0.48 + hop + wave, -0.05)
			p.hand_r = Vector3(0.36, _sh + 0.48 + hop - wave, -0.05)
			p.pole_l = Vector3(-1, 0, 0.2)
			p.pole_r = Vector3(1, 0, 0.2)
			p.ball = p.hand_r
		Move.SAD:
			p.hips = _hips(0.08)
			p.bend = 0.12
			p.head = -0.4
			p.hand_l = Vector3(-0.1, _sh + 0.32, 0.06)
			p.hand_r = Vector3(0.1, _sh + 0.32, 0.06)
			p.pole_l = Vector3(-1, 0.2, -0.2)
			p.pole_r = Vector3(1, 0.2, -0.2)
			p.ball = p.hand_r
	return p


func _hold(p: Pose, breathe: float) -> void:
	## Triple threat: knees bent, ball at the chest, eyes on the rim.
	p.hips = _hips(0.2 + breathe)
	p.bend = 0.12
	p.head = 0.12
	p.ball = Vector3(0.06, _sh - 0.3 + breathe, -0.3)
	p.hand_l = p.ball + Vector3(-0.17, -0.01, 0.07)
	p.hand_r = p.ball + Vector3(0.17, -0.01, 0.07)
	p.pole_l = Vector3(-1, -0.7, 0.3)
	p.pole_r = Vector3(1, -0.7, 0.3)


func _set_pose(p: Pose, u: float) -> void:
	## Ball up to the set point over the right eye, knees loaded.
	var h := Pose.new()
	_stance(h)
	_hold(h, 0.0)
	p.hips = _hips(0.34)
	p.bend = 0.04
	p.head = 0.2
	p.ball = Vector3(0.13, _sh + 0.4, -0.2)
	p.hand_r = p.ball + Vector3(0.015, -0.13, 0.09)
	p.hand_l = p.ball + Vector3(-0.17, -0.02, 0.04)
	p.pole_r = Vector3(0.3, -1, -0.1)
	p.pole_l = Vector3(-1, -0.6, 0.1)
	p.flex_r = -0.9
	var w := smoothstep(0.0, 1.0, u)
	var b := h.blend(p, w)
	p.hips = b.hips
	p.bend = b.bend
	p.head = b.head
	p.ball = b.ball
	p.hand_l = b.hand_l
	p.hand_r = b.hand_r
	p.pole_l = b.pole_l
	p.pole_r = b.pole_r
	p.flex_r = b.flex_r


func _shoot(p: Pose, t: float) -> void:
	## Jump shot: rise, release at RELEASE_T near the top of the reach, hold the follow-through
	## (arm up, wrist dropped) through the landing.
	var air := 0.5
	var lift := 0.22 * 4.0 * (t / air) * (1.0 - t / air) if t < air else 0.0
	var land := 0.0 if t < air else exp(-(t - air) * 8.0) * 0.25
	_stance(p, lift)
	p.toe_l = -0.6 * clampf(lift * 8.0, 0.0, 1.0)
	p.toe_r = p.toe_l
	p.hips = _hips(lerpf(0.34, -0.05, smoothstep(0.0, 0.1, t)) + land + (0.06 if t > air else 0.0), lift)
	p.bend = 0.02
	p.head = 0.22
	var set_ball := Vector3(0.13, _sh + 0.4, -0.2)
	var rel_ball := Vector3(0.12, _sh + 0.58, -0.3)
	var u := smoothstep(0.0, RELEASE_T, t)
	p.ball = set_ball.lerp(rel_ball, u) + Vector3(0, lift, 0)
	if t < RELEASE_T:
		p.hand_r = p.ball + Vector3(0.015, -0.13, 0.09).lerp(Vector3(0.01, -0.11, 0.07), u)
		p.hand_l = p.ball + Vector3(-0.17, -0.02, 0.04)
		p.flex_r = lerpf(-0.9, -0.3, u)
	else:
		var f := smoothstep(RELEASE_T, RELEASE_T + 0.12, t)
		p.hand_r = Vector3(0.13, _sh + 0.47 + lift, -0.25)
		p.hand_l = Vector3(-0.1, _sh + 0.28 + lift - 0.25 * smoothstep(0.5, 0.9, t), -0.22)
		p.flex_r = lerpf(-0.3, 1.15, f)
		p.flex_l = 0.3 * f
	p.pole_r = Vector3(0.3, -1, -0.1)
	p.pole_l = Vector3(-1, -0.5, 0.1)


func _walk(p: Pose) -> void:
	## A jog: feet on a cycle (stance on the floor moving back, swing up and forward), hips
	## bobbing, arms bent and swinging against the legs.
	var amt := clampf(walk_speed / 3.0, 0.0, 1.0)
	var stride := 0.68 * amt
	var feet: Array[Vector3] = []
	var toes: Array[float] = []
	for i in 2:
		var ps := fmod(_phase + 0.5 * i, 1.0)
		var x := (-0.11 if i == 0 else 0.11)
		if ps < 0.45:
			var u := ps / 0.45
			feet.append(Vector3(x, 0.0, lerpf(-stride * 0.5, stride * 0.5, u)))
			toes.append(lerpf(0.15, -0.35, u) * amt)
		else:
			var u := (ps - 0.45) / 0.55
			feet.append(Vector3(x, sin(u * PI) * 0.2 * amt, lerpf(stride * 0.5, -stride * 0.5, smoothstep(0.0, 1.0, u))))
			toes.append(lerpf(-0.35, 0.15, u) * amt)
	p.foot_l = feet[0]
	p.foot_r = feet[1]
	p.toe_l = toes[0]
	p.toe_r = toes[1]
	var bob := (cos(_phase * TAU * 2.0) * 0.03 + 0.02) * amt
	p.hips = _hips(0.12 * amt, bob)
	p.bend = 0.05 + 0.12 * amt
	p.twist = sin(_phase * TAU) * 0.12 * amt
	p.head = 0.05
	var swing := cos(_phase * TAU) * 0.22 * amt
	p.hand_l = Vector3(-0.24, _sh - 0.42, -0.1 + swing)
	p.hand_r = Vector3(0.24, _sh - 0.42, -0.1 - swing)
	p.pole_l = Vector3(-0.2, -0.3, 1)
	p.pole_r = Vector3(0.2, -0.3, 1)
	p.ball = p.hand_r


# -------------------------------------------------------------------------- layout ----

func _layout() -> void:
	var p := _cur
	var pelvis_basis := Basis(Vector3.UP, p.twist * 0.3) * Basis(Vector3.RIGHT, -p.bend * 0.4)
	var chest_basis := Basis(Vector3.UP, p.twist) * Basis(Vector3.RIGHT, -p.bend)
	var head_basis := Basis(Vector3.UP, p.twist * 1.1) * Basis(Vector3.RIGHT, p.head)

	var pelvis: int = _bone["pelvis"]
	var rest_p: Transform3D = _rest[pelvis]
	_pose[pelvis] = Transform3D(pelvis_basis * rest_p.basis, p.hips + pelvis_basis * (rest_p.origin - _hip_mid))
	var pq := pelvis_basis.get_rotation_quaternion()
	var cq := chest_basis.get_rotation_quaternion()
	_fk("spine_01", Basis(pq.slerp(cq, 0.33)))
	_fk("spine_02", Basis(pq.slerp(cq, 0.67)))
	_fk("spine_03", chest_basis)
	_fk("neck_01", Basis(cq.slerp(head_basis.get_rotation_quaternion(), 0.5)))
	_fk("head", head_basis)

	for i in 2:
		var s := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		var sole: Vector3 = p.foot_l if i == 0 else p.foot_r
		var toe: float = p.toe_l if i == 0 else p.toe_r
		var fwd := Basis(Vector3.RIGHT, toe) * Vector3.FORWARD
		var up := Basis(Vector3.RIGHT, toe) * Vector3.UP
		var ankle := sole + up * _ankle_h - fwd * _ankle_back
		_limb("thigh" + s, "calf" + s, ankle, _thigh_len, _shin_len, Vector3(side * 0.15, 0.0, -1.0), Vector3.LEFT)
		_fk("foot" + s, _frame(up, fwd) * _frame(Vector3.UP, Vector3.FORWARD).transposed())

	for i in 2:
		var s := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		_fk("clavicle" + s, chest_basis)
		var hand: Vector3 = p.hand_l if i == 0 else p.hand_r
		var pole: Vector3 = p.pole_l if i == 0 else p.pole_r
		_limb("upperarm" + s, "lowerarm" + s, hand, _upper_len, _fore_len, pole, Vector3.ZERO)
		var fore := (_joint("hand" + s) - _joint("lowerarm" + s)).normalized()
		var ax := Vector3.RIGHT - fore * fore.dot(Vector3.RIGHT)
		ax = ax.normalized() if ax.length() > 0.1 else Vector3.BACK
		var flex: float = p.flex_l if i == 0 else p.flex_r
		_fk("hand" + s, Basis(ax, -flex) * _delta("lowerarm" + s) * Basis(Vector3.BACK, side * 0.15))

	# Number on the back of the jersey, riding on the chest.
	var chest: Transform3D = _pose[_bone["spine_03"]]
	_num.transform = Transform3D(chest_basis, chest.origin + chest_basis * Vector3(0.0, 0.02, 0.135))
	_apply_pose()


# -------------------------------------------------------------------------- body ----

func _build_body() -> void:
	var rider := _load_character(BALLERS[_variant % BALLERS.size()])
	for mi: MeshInstance3D in rider.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m == null:
				continue
			match m.resource_name:
				"jacket":
					mi.set_surface_override_material(s, _mesh_fabric(m, _color, 0.55))
				"pants":
					mi.set_surface_override_material(s, _mesh_fabric(m, _color.darkened(0.25), 0.6))
	_num = Label3D.new()
	_num.text = str(number)
	_num.font = RSUi.font()
	_num.font_size = 96
	_num.pixel_size = 0.0016
	_num.modulate = Color(0.97, 0.97, 0.95)
	_num.outline_size = 14
	_num.outline_modulate = _color.darkened(0.55)
	_num.shaded = true
	_num.double_sided = false
	body.add_child(_num)


func _mesh_fabric(src: StandardMaterial3D, color: Color, roughness: float) -> StandardMaterial3D:
	## Basketball mesh jersey: the garment's folds in a plain colour, a slight sheen.
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.normal_enabled = src.normal_enabled
	m.normal_texture = src.normal_texture
	m.normal_scale = 1.2
	m.roughness = roughness
	m.metallic_specular = 0.55
	m.rim_enabled = true
	m.rim = 0.2
	m.rim_tint = 0.5
	return m
