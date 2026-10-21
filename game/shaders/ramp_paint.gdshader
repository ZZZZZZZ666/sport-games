shader_type spatial;
// Painted plywood ramp sides with scanned graffiti pieces (assets/decals, cut from Poly Haven's
// CC0 roller-shutter scans) sprayed along each panel, one per slot, picked by a hash. UV is in
// metres for the plywood; UV2 is (metres along the panel, metres above the ground) as the viewer
// reads it. The vertex colour carries the panel: r = height / 4 m, g = a per-panel seed, b = 1
// when the panel is painted at all, a = length / 16 m.

uniform sampler2D ply_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ply_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D decal0 : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D decal1 : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D decal2 : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 aspects = vec3(1.37, 0.875, 2.43);   // width / height of each piece
uniform vec4 paint : source_color = vec4(0.4, 0.42, 0.44, 1.0);
uniform float size_m = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV / size_m;
	vec3 ply = texture(ply_albedo, uv).rgb;
	float grain = dot(ply, vec3(0.333));
	// Paint over plywood: the grain shows through faintly, scuffs near the ground show the wood.
	vec3 base = paint.rgb * mix(1.0, grain / 0.42, 0.25);
	float scuff = smoothstep(0.62, 0.8, vnoise(UV2 * vec2(3.0, 9.0)) * (1.0 - smoothstep(0.0, 0.35, UV2.y)) + vnoise(UV2 * 14.0) * 0.25);
	base = mix(base, ply * vec3(0.95, 0.85, 0.72), scuff * 0.8);

	float h = COLOR.r * 4.0;
	float len = COLOR.a * 16.0;
	float dh = min(h * 0.86, 1.8);
	float slots = max(1.0, floor(len / (dh * 2.2)));
	float slot = len / slots;
	float idx = clamp(floor(UV2.x / slot), 0.0, slots - 1.0);
	float r1 = hash(vec2(idx, COLOR.g * 97.0));
	float r2 = hash(vec2(idx + 13.0, COLOR.g * 31.0));
	float r3 = hash(vec2(idx + 7.0, COLOR.g * 53.0));
	float pick = floor(r1 * 3.0);
	float aspect = pick < 0.5 ? aspects.x : (pick < 1.5 ? aspects.y : aspects.z);
	float dw = min(dh * aspect, slot * 0.92);
	dh = dw / aspect;
	float cx = (idx + 0.5) * slot + (r2 - 0.5) * (slot - dw) * 0.8;
	vec2 duv = vec2((UV2.x - cx) / dw + 0.5, 1.0 - (UV2.y - (h - dh) * 0.4) / dh);
	vec4 d0 = texture(decal0, duv);
	vec4 d1 = texture(decal1, duv);
	vec4 d2 = texture(decal2, duv);
	vec4 d = pick < 0.5 ? d0 : (pick < 1.5 ? d1 : d2);
	float inside = step(0.0, duv.x) * step(duv.x, 1.0) * step(0.0, duv.y) * step(duv.y, 1.0);
	float a = d.a * inside * COLOR.b * step(r3, 0.8) * (1.0 - scuff * 0.7);

	ALBEDO = mix(base, d.rgb, a * 0.95);
	ROUGHNESS = mix(mix(0.74, 0.85, scuff), 0.58, a);
	NORMAL_MAP = texture(ply_normal, uv).rgb;
	NORMAL_MAP_DEPTH = mix(0.5, 0.25, a);
}
