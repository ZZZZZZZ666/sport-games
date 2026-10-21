class_name RSSkiMaps
## The ski game's courses. Each map is data for RSSkiCourse: the run (length, width, how it
## winds, how steep it gets where), what is along it (gates, kickers, trees, lights, lift,
## village) and the weather and light (Poly Haven sky, sun, fog, snowfall).
##
## profile: [s, grade] points along the run (grade = drop per metre); kickers: [s of the lip,
## height, across the piste (-1..1)].

const MAPS := [
	{
		"name": "阿尔卑斯晴空", "en": "ALPINE BLUEBIRD", "stars": 2,
		"desc": "宽阔的压雪道，阳光明媚。两个跳台，22 道旗门，山脚下是木屋小镇。适合第一次玩。",
		"length": 1000.0, "half_width": 17.0, "amp": 18.0, "wave": 300.0, "seed": 11,
		"profile": [[0, 0.3], [60, 0.24], [180, 0.3], [330, 0.17], [460, 0.32], [640, 0.36], [780, 0.2], [900, 0.25], [1000, 0.12]],
		"kickers": [[300.0, 1.6, 0.0], [740.0, 2.0, 0.25]],
		"gate_gap": 38.0, "gate_w": 4.6, "trees": 1.0, "tree_line": 0.0, "rocks": 0.3,
		"village": true, "lift": true, "lights": false, "snowfall": 0.0,
		"hdri": "res://assets/polyhaven/hdris/kloofendal_43d_clear_puresky/kloofendal_43d_clear_puresky_4k.hdr",
		"sky_energy": 1.0, "sky_rot": 0.6, "sun_az": 35.0, "sun_el": 38.0, "sun_color": Color(1.0, 0.96, 0.9), "sun_energy": 2.6,
		"ambient": 0.7, "exposure": 0.85, "fog": Color(0.72, 0.8, 0.92), "fog_density": 0.00018, "snow_tint": Color(1.0, 1.0, 1.0),
	},
	{
		"name": "松林黄昏", "en": "PINE FOREST DUSK", "stars": 3,
		"desc": "夕阳下穿过密林的窄道，弯多、起伏多。三个跳台，旗门更密，考验转弯。",
		"length": 1100.0, "half_width": 12.0, "amp": 17.0, "wave": 240.0, "seed": 23,
		"profile": [[0, 0.3], [70, 0.26], [200, 0.2], [300, 0.33], [430, 0.22], [560, 0.3], [700, 0.18], [820, 0.34], [960, 0.24], [1100, 0.12]],
		"kickers": [[250.0, 1.4, -0.2], [600.0, 1.7, 0.2], [930.0, 2.1, 0.0]],
		"gate_gap": 32.0, "gate_w": 4.0, "trees": 1.8, "tree_line": 0.0, "rocks": 0.2,
		"village": true, "lift": false, "lights": false, "snowfall": 0.0,
		"hdri": "res://assets/polyhaven/hdris/belfast_sunset_puresky/belfast_sunset_puresky_4k.hdr",
		"sky_energy": 1.1, "sky_rot": 2.2, "sun_az": -60.0, "sun_el": 9.0, "sun_color": Color(1.0, 0.68, 0.42), "sun_energy": 2.3,
		"ambient": 0.42, "exposure": 0.8, "fog": Color(0.8, 0.6, 0.55), "fog_density": 0.00022, "snow_tint": Color(1.0, 0.97, 0.95),
	},
	{
		"name": "夜场灯光", "en": "NIGHT FLOODLIGHTS", "stars": 2,
		"desc": "灯光照亮的夜场雪道，终点前是连续的大跳台区。星空下飞得更高！",
		"length": 900.0, "half_width": 15.0, "amp": 15.0, "wave": 260.0, "seed": 37,
		"profile": [[0, 0.3], [70, 0.24], [220, 0.3], [380, 0.2], [520, 0.3], [640, 0.22], [900, 0.16]],
		"kickers": [[200.0, 1.5, 0.0], [520.0, 1.8, -0.2], [680.0, 2.2, 0.0], [800.0, 2.4, 0.15]],
		"gate_gap": 40.0, "gate_w": 4.6, "trees": 1.1, "tree_line": 0.0, "rocks": 0.2,
		"village": true, "lift": true, "lights": true, "snowfall": 0.25,
		"hdri": "res://assets/polyhaven/hdris/kloppenheim_02_puresky/kloppenheim_02_puresky_4k.hdr",
		"sky_energy": 0.6, "sky_rot": 0.0, "sun_az": 140.0, "sun_el": 30.0, "sun_color": Color(0.62, 0.72, 1.0), "sun_energy": 0.22,
		"ambient": 0.35, "exposure": 1.25, "fog": Color(0.05, 0.07, 0.12), "fog_density": 0.0008, "snow_tint": Color(0.92, 0.95, 1.0),
	},
	{
		"name": "冰川风雪", "en": "GLACIER STORM", "stars": 4,
		"desc": "林线以上的冰川陡坡，暴风雪里能见度很低，跟着旗门和路标走。最长最陡，高手专用。",
		"length": 1200.0, "half_width": 19.0, "amp": 22.0, "wave": 340.0, "seed": 53,
		"profile": [[0, 0.3], [70, 0.32], [200, 0.38], [340, 0.24], [480, 0.4], [640, 0.3], [800, 0.42], [950, 0.26], [1100, 0.3], [1200, 0.12]],
		"kickers": [[420.0, 1.8, 0.0], [890.0, 2.2, -0.2]],
		"gate_gap": 42.0, "gate_w": 5.0, "trees": 0.25, "tree_line": 650.0, "rocks": 1.0,
		"village": false, "lift": true, "lights": false, "snowfall": 1.0,
		"hdri": "res://assets/polyhaven/hdris/snow_field_puresky/snow_field_puresky_4k.hdr",
		"sky_energy": 0.9, "sky_rot": 0.0, "sun_az": 20.0, "sun_el": 30.0, "sun_color": Color(0.9, 0.93, 1.0), "sun_energy": 0.9,
		"ambient": 1.0, "exposure": 0.95, "fog": Color(0.78, 0.82, 0.88), "fog_density": 0.0045, "snow_tint": Color(0.96, 0.98, 1.0),
	},
]


static func count() -> int:
	return MAPS.size()


static func get_map(i: int) -> Dictionary:
	return MAPS[posmod(i, MAPS.size())]


static func stars(i: int) -> String:
	var n: int = get_map(i)["stars"]
	return "★".repeat(n) + "☆".repeat(5 - n)
