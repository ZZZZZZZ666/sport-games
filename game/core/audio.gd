class_name RSAudio
extends RefCounted
## Audio buses: Music, SFX and Ambience, all sent to Master (which carries a limiter). Each
## bus has a volume step 0..10 kept in RSSettings (pause menu → 声音). RSSfx routes every
## sound through bus_for(): background beds and crowds to Ambience, the rest to SFX; music
## players use MUSIC.

const MASTER := "Master"
const MUSIC := "Music"
const SFX := "SFX"
const AMBIENCE := "Ambience"
const BUSES := [MASTER, MUSIC, SFX, AMBIENCE]
const STEPS := 10

static var _made := false


static func ensure() -> void:
	## Create the buses (once per run) and put a limiter on Master: recorded hits are peaky,
	## and a pop on top of a rolling loop could otherwise clip.
	if _made:
		return
	_made = true
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, MASTER)
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		has_limiter = has_limiter or AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)


static func bus_for(id: String) -> String:
	ensure()
	return AMBIENCE if id.ends_with("_amb") or id == "applause" else SFX


static func set_volume(bus: String, step: int) -> void:
	## step 0..STEPS; a squared taper so the middle steps sound like the middle.
	ensure()
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(i, step <= 0)
	AudioServer.set_bus_volume_db(i, linear_to_db(pow(float(step) / STEPS, 2.0)) if step > 0 else -80.0)
