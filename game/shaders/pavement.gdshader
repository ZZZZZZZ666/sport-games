// Ground surfaces patterned in world space, so long strips need no UVs and every piece of
// road lines up: 0 = asphalt (speckle, wear, optional lane lines), 1 = square plaza tiles
// with per-tile tint, 2 = poured concrete slabs with saw cuts.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform int pattern = 0;
uniform vec4 base_color : source_color = vec4(0.27, 0.28, 0.3, 1.0);
uniform vec4 alt_color : source_color = vec4(0.32, 0.33, 0.35, 1.0);
uniform vec4 line_color : source_color = vec4(0.95, 0.92, 0.8, 1.0);
uniform float tile = 1.5;
uniform bool road_lines = false;
uniform float half_width = 9.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float line_aa(float d, float width) {
	// 1 inside a line of the given half-width around d = 0, anti-aliased.
	float w = fwidth(d);
	return 1.0 - smoothstep(width - w, width + w, abs(d));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 col = base_color.rgb;
	float n = vnoise(p * 2.7) * 0.5 + vnoise(p * 0.35) * 0.5;
	if (pattern == 0) {
		col = mix(base_color.rgb, alt_color.rgb, n);
		col *= 0.92 + 0.14 * vnoise(p * 11.0);
		col += 0.05 * step(0.94, hash(floor(p * 37.0)));
		// Worn, slightly lighter tracks where traffic used to run.
		col += 0.025 * (1.0 - smoothstep(0.6, 2.2, abs(abs(p.x) - 4.5)));
		if (road_lines) {
			float edge = line_aa(abs(p.x) - (half_width - 0.5), 0.08);
			float dash = step(0.45, fract(p.y / 6.0));
			float center = line_aa(p.x, 0.07) * dash;
			col = mix(col, line_color.rgb * (0.85 + 0.15 * n), max(edge, center) * 0.92);
		}
	} else if (pattern == 1) {
		vec2 g = p / tile;
		vec2 id = floor(g);
		float tint = hash(id);
		col = mix(base_color.rgb, alt_color.rgb, tint) * (0.93 + 0.1 * n);
		vec2 f = fract(g) - 0.5;
		float joint = max(line_aa(abs(f.x) - 0.5, 0.025), line_aa(abs(f.y) - 0.5, 0.025));
		col *= 1.0 - joint * 0.3;
	} else {
		col = mix(base_color.rgb, alt_color.rgb, n) * (0.95 + 0.08 * vnoise(p * 9.0));
		vec2 g = p / tile;
		vec2 f = fract(g) - 0.5;
		float joint = max(line_aa(abs(f.x) - 0.5, 0.012), line_aa(abs(f.y) - 0.5, 0.012));
		col *= 1.0 - joint * 0.35;
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
