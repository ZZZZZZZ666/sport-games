class_name RSSfx
extends RefCounted
## Sound effects by name. A recording in assets/sfx wins (CC0, cut and loudness-matched by
## tools/blender/audio_tool.py; "pop_0.wav", "pop_1.wav"... are variants picked at random,
## levels.json holds per-sound playback trims). Anything without a recording is synthesized
## in code: noise, filters and envelopes rendered once into AudioStreamWAVs. Everything is
## cached by name; call warm_up() while a scene loads so nothing is generated mid-game.
##
## One-shots: RSSfx.play(node, "pop"). Loops: RSSfx.loop(node, "roll") returns a player that
## starts silent; the caller drives its volume_db / pitch_scale every frame. Each player goes to
## the SFX or Ambience bus (RSAudio), so the volume settings reach every sound.

const RATE := 22050
const XFADE := 2048          ## samples cross-faded at a loop seam
const DIR := "res://assets/sfx/"
const LOOPS := ["roll", "grind_metal", "grind_ledge", "wind", "applause", "carve", "skid", "wind_amb", "city_amb"]

static var _cache: Dictionary = {}
static var _levels: Dictionary = {}
static var _recorded: Dictionary = {}


class Biquad:
	## RBJ band-pass (constant 0 dB peak). set_band() may be called between samples.
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(freq: float, q: float) -> void:
		set_band(freq, q)

	func set_band(freq: float, q: float) -> void:
		var w0 := TAU * freq / RATE
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0

	func run(x: float) -> float:
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


static func stream(id: String) -> AudioStream:
	if not _cache.has(id):
		var rec := _recording(id)
		_cache[id] = rec if rec != null else _make(id)
	return _cache[id]


static func trim_db(id: String) -> float:
	## Extra playback gain for a recording too peaky to be stored at full loudness.
	if _levels.is_empty() and FileAccess.file_exists(DIR + "levels.json"):
		_levels = JSON.parse_string(FileAccess.get_file_as_string(DIR + "levels.json"))
	stream(id)
	return float(_levels.get(id, 0.0)) if id in _recorded else 0.0


static func _recording(id: String) -> AudioStream:
	var found: Array[AudioStream] = []
	if ResourceLoader.exists(DIR + id + ".wav"):
		found.append(load(DIR + id + ".wav"))
	for i in 8:
		var path := "%s%s_%d.wav" % [DIR, id, i]
		if ResourceLoader.exists(path):
			found.append(load(path))
	if found.is_empty():
		return null
	_recorded[id] = true
	for w: AudioStreamWAV in found:
		if id in LOOPS:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	if found.size() == 1:
		return found[0]
	var r := AudioStreamRandomizer.new()
	r.random_pitch = 1.0
	r.random_volume_offset_db = 1.5
	for w in found:
		r.add_stream(-1, w)
	return r


static func warm_up(ids: Array) -> void:
	RSAudio.ensure()
	for id: String in ids:
		stream(id)


static func play(parent: Node, id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(id)
	p.volume_db = volume_db + trim_db(id)
	p.pitch_scale = pitch
	p.bus = RSAudio.bus_for(id)
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func loop(parent: Node, id: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream(id)
	p.volume_db = -80.0
	p.bus = RSAudio.bus_for(id)
	parent.add_child(p)
	p.play()
	return p


# ------------------------------------------------------------------------ synthesis ----

static func _make(id: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		"roll":
			return _wav(_roll(rng), true)
		"grind_metal":
			return _wav(_grind_metal(rng), true)
		"grind_ledge":
			return _wav(_grind_ledge(rng), true)
		"wind":
			return _wav(_wind(rng), true)
		"applause":
			return _wav(_applause(rng), true)
		"pop":
			return _wav(_pop(rng), false)
		"land":
			return _wav(_land(rng), false)
		"flip":
			return _wav(_whoosh(rng, 0.28, 500.0, 2400.0), false)
		"spin":
			return _wav(_whoosh(rng, 0.4, 300.0, 900.0), false)
		"push":
			return _wav(_push(rng), false)
		"bail":
			return _wav(_bail(rng), false)
		"thud":
			return _wav(_thud(rng), false)
		"chime":
			return _wav(_bells([523.25, 659.25, 783.99, 1046.5], 0.07, 0.4, 1.1), false)
		"pickup":
			return _wav(_bells([1318.5, 1568.0, 1975.5, 2637.0], 0.05, 0.18, 0.7), false)
		"ding":
			return _wav(_bells([1046.5, 1568.0], 0.0, 0.3, 0.7), false)
		"beep":
			return _wav(_tone([880.0], 0.16), false)
		"go":
			return _wav(_tone([1318.5, 1760.0], 0.5), false)
		"fail":
			return _wav(_bells([392.0, 311.1], 0.12, 0.25, 0.7), false)
		"swish":
			return _wav(_swish(rng), false)
		"buzzer":
			return _wav(_buzzer(), false)
	push_warning("RSSfx: unknown sound '%s'" % id)
	return _wav(PackedFloat32Array([0.0]), false)


static func _buf(seconds: float, looped: bool) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE) + (XFADE if looped else 0))
	return b


static func _wav(s: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	if looped:
		# Fold the extra tail over the start so the seam is a cross-fade.
		var n := s.size() - XFADE
		for i in XFADE:
			var k := float(i) / XFADE
			s[i] = s[i] * k + s[n + i] * (1.0 - k)
		s.resize(n)
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


static func _lp_k(freq: float) -> float:
	## One-pole low-pass coefficient.
	return 1.0 - exp(-TAU * freq / RATE)


static func _click(s: PackedFloat32Array, rng: RandomNumberGenerator, at: int, amp: float, ring_hz: float, decay: float) -> void:
	## A hard little impact: a noise spike plus a short ringing tone.
	for j in int(decay * 6.0 * RATE):
		if at + j >= s.size():
			return
		var t := float(j) / RATE
		s[at + j] += amp * (rng.randf_range(-1.0, 1.0) * exp(-t / 0.0025) + 0.6 * sin(TAU * ring_hz * t) * exp(-t / decay))


static func _roll(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Urethane on concrete: low rumble, a soft hum, and a tick at each pavement joint.
	var s := _buf(2.0, true)
	var lp := 0.0
	var lp2 := 0.0
	var bp := Biquad.new(650.0, 1.4)
	var k := _lp_k(160.0)
	for i in s.size():
		var w := rng.randf_range(-1.0, 1.0)
		lp += k * (w - lp)
		lp2 += k * (lp - lp2)
		s[i] = lp2 * 5.0 + bp.run(w) * 0.22
	for j in 4:
		_click(s, rng, int((0.12 + 0.5 * j + rng.randf_range(-0.04, 0.04)) * RATE), 0.35, 240.0, 0.02)
	return s


static func _grind_metal(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Steel on steel: narrow noise bands, ringing partials with a wobble, a gritty texture.
	var s := _buf(1.5, true)
	var b1 := Biquad.new(2300.0, 4.0)
	var b2 := Biquad.new(3700.0, 5.0)
	var b3 := Biquad.new(5200.0, 6.0)
	var grain := 0.8
	var grain_to := 0.8
	for i in s.size():
		var t := float(i) / RATE
		if i % 600 == 0:
			grain_to = rng.randf_range(0.45, 1.0)
		grain += (grain_to - grain) * 0.004
		var w := rng.randf_range(-1.0, 1.0)
		var noise := b1.run(w) * 0.9 + b2.run(w) * 0.6 + b3.run(w) * 0.4
		var wob := 3.0 * sin(TAU * 5.3 * t)
		var ring := 0.10 * sin(TAU * 1840.0 * t + wob) + 0.07 * sin(TAU * 2760.0 * t + wob * 1.3) + 0.04 * sin(TAU * 4150.0 * t)
		s[i] = noise * grain * 2.2 + ring
	return s


static func _grind_ledge(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Trucks on a concrete/waxed edge: rough, lower, choppy.
	var s := _buf(1.5, true)
	var lp := 0.0
	var lp2 := 0.0
	var hp := 0.0
	var k := _lp_k(1300.0)
	var grain := 0.7
	var grain_to := 0.7
	for i in s.size():
		if i % 350 == 0:
			grain_to = rng.randf_range(0.25, 1.0)
		grain += (grain_to - grain) * 0.01
		var w := rng.randf_range(-1.0, 1.0)
		lp += k * (w - lp)
		lp2 += k * (lp - lp2)
		hp += 0.03 * (lp2 - hp)
		s[i] = (lp2 - hp) * grain
	return s


static func _wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(2.0, true)
	var lp := 0.0
	var lp2 := 0.0
	var k := _lp_k(420.0)
	for i in s.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += k * (w - lp)
		lp2 += k * (lp - lp2)
		s[i] = lp2 * (0.65 + 0.35 * sin(TAU * 0.5 * t))
	return s


static func _applause(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# A crowd: dense random hand claps over a murmur bed.
	var s := _buf(3.0, true)
	var claps := PackedFloat32Array()
	claps.resize(s.size())
	for c in 200:
		var at := rng.randi_range(0, s.size() - 200)
		var amp := rng.randf_range(0.3, 1.0)
		for j in 160:
			claps[at + j] += amp * rng.randf_range(-1.0, 1.0) * exp(-float(j) / 40.0)
	var bp := Biquad.new(1500.0, 0.8)
	var lp := 0.0
	var k := _lp_k(700.0)
	for i in s.size():
		var w := rng.randf_range(-1.0, 1.0)
		lp += k * (w - lp)
		s[i] = bp.run(claps[i]) * 1.4 + lp * 0.5
	return s


static func _pop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Tail snapping on the ground: a sharp crack and a hollow wood knock.
	var s := _buf(0.3, false)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (rng.randf_range(-1.0, 1.0) * exp(-t / 0.003) * 1.2
			+ sin(TAU * 170.0 * t) * exp(-t / 0.05) * 0.9
			+ sin(TAU * 830.0 * t) * exp(-t / 0.014) * 0.45)
	return s


static func _land(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Four wheels hitting at once: a low thump, a double clack (front and back trucks).
	var s := _buf(0.45, false)
	var lp := 0.0
	var k := _lp_k(500.0)
	for i in s.size():
		var t := float(i) / RATE
		lp += k * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] = sin(TAU * (88.0 - 50.0 * minf(t / 0.2, 1.0)) * t) * exp(-t / 0.09) + lp * exp(-t / 0.1) * 1.5
	_click(s, rng, 0, 0.7, 620.0, 0.02)
	_click(s, rng, int(0.022 * RATE), 0.55, 540.0, 0.02)
	return s


static func _thud(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.35, false)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * (75.0 - 30.0 * minf(t / 0.2, 1.0)) * t) * exp(-t / 0.1)
	_click(s, rng, 0, 0.5, 300.0, 0.03)
	return s


static func _whoosh(rng: RandomNumberGenerator, dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var s := _buf(dur, false)
	var bp := Biquad.new(f0, 1.2)
	for i in s.size():
		var u := float(i) / s.size()
		if i % 64 == 0:
			bp.set_band(lerpf(f0, f1, u), 1.2)
		s[i] = bp.run(rng.randf_range(-1.0, 1.0)) * pow(sin(PI * u), 2.0)
	return s


static func _push(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Shoe sole scuffing the ground.
	var s := _buf(0.4, false)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := t / 0.4
		lp += _lp_k(lerpf(2200.0, 500.0, u)) * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] = lp * minf(t / 0.03, 1.0) * exp(-t / 0.13)
	return s


static func _bail(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Body hitting the ground, board clattering away, a slide.
	var s := _buf(1.0, false)
	var bp := Biquad.new(900.0, 0.7)
	var lp := 0.0
	var k := _lp_k(1500.0)
	for i in s.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += k * (w - lp)
		s[i] = (sin(TAU * 62.0 * t) * exp(-t / 0.13) * 1.2
			+ bp.run(w) * exp(-t / 0.05) * 1.5
			+ lp * 0.5 * exp(-maxf(t - 0.1, 0.0) / 0.35) * minf(t / 0.1, 1.0))
	for j in 5:
		_click(s, rng, int(rng.randf_range(0.12, 0.6) * RATE), rng.randf_range(0.2, 0.5), rng.randf_range(400.0, 1100.0), 0.025)
	return s


static func _swish(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# A ball dropping clean through a nylon net: a soft rising "shhk" of string on leather.
	var s := _buf(0.42, false)
	var bp := Biquad.new(2500.0, 0.9)
	var bp2 := Biquad.new(5200.0, 1.6)
	for i in s.size():
		var t := float(i) / RATE
		var u := t / 0.42
		if i % 64 == 0:
			bp.set_band(lerpf(1800.0, 3600.0, u), 0.9)
		var w := rng.randf_range(-1.0, 1.0)
		var env := smoothstep(0.0, 0.05, t) * exp(-maxf(t - 0.06, 0.0) / 0.1)
		# The strings flick in little bursts as the ball passes each knot row.
		var flick := 0.6 + 0.4 * absf(sin(TAU * 38.0 * t))
		s[i] = (bp.run(w) * 1.0 + bp2.run(w) * 0.45) * env * flick
	return s


static func _buzzer() -> PackedFloat32Array:
	# Shot-clock horn: a rough, buzzing low chord.
	var s := _buf(1.1, false)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for f: float in [196.0, 247.0, 294.0]:
			v += signf(sin(TAU * f * t)) * 0.33 + sin(TAU * f * 2.0 * t) * 0.1
		s[i] = v * minf(t / 0.01, 1.0) * minf((1.1 - t) / 0.08, 1.0) * 0.6
	return s


static func _bells(notes: Array, gap: float, decay: float, dur: float) -> PackedFloat32Array:
	var s := _buf(dur, false)
	for n in notes.size():
		var f: float = notes[n]
		var at := int(gap * n * RATE)
		for i in range(at, s.size()):
			var t := float(i - at) / RATE
			s[i] += (sin(TAU * f * t) * exp(-t / decay)
				+ 0.4 * sin(TAU * 2.01 * f * t) * exp(-t / (decay * 0.5))
				+ 0.15 * sin(TAU * 3.0 * f * t) * exp(-t / (decay * 0.25))) * minf(t / 0.003, 1.0)
	return s


static func _tone(freqs: Array, dur: float) -> PackedFloat32Array:
	var s := _buf(dur, false)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * t)
		s[i] = v * minf(t / 0.005, 1.0) * minf((dur - t) / 0.06, 1.0)
	return s
