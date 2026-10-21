shader_type spatial;
// Golf course ground. The course's surface fields (RSGolfCourse: signed distances in metres,
// R fairway, G green, B bunker, A water, 1 m texels) decide what grows where, so what you see
// is the lie the ball gets: striped fairway, cross-cut green with a collar, a first cut, rough
// (links fescue or parkland grass), sand bunkers with a darker lip, wet banks, the beach.
// Photo textures (Poly Haven, CC0) give the grain; the greens' colours come from the map.

uniform sampler2D fields : filter_linear, repeat_disable;
uniform sampler2D mow_dir : filter_nearest, repeat_disable;
uniform vec2 field_origin;
uniform vec2 field_size;
uniform float field_range = 12.0;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_color : source_color = vec3(0.25, 0.43, 0.13);
uniform vec3 green_color : source_color = vec3(0.2, 0.45, 0.12);
uniform vec3 rough_tint : source_color = vec3(0.6, 0.65, 0.35);
uniform float links = 0.0;
uniform float sea_level = -1000.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;   // seamless simplex fbm, ~6 blobs a tile

varying vec3 wpos;

float fbm(vec2 p) {
	// Smooth noise with features about 1 unit of p across (two rotated lookups hide the tile).
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	return texture(noise_tex, p / 6.0).r * 0.65 + texture(noise_tex, q / 3.1 + 0.37).r * 0.35;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// World-aligned texturing (u = x, v = z): tangents to match.
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = cross(NORMAL, TANGENT);
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 unpack_n(vec4 t) {
	return t.xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 xz = wpos.xz;
	vec2 fuv = (xz - field_origin) / field_size;
	vec4 f = (texture(fields, fuv) * 2.0 - 1.0) * field_range;    // metres, < 0 inside
	vec2 md = texture(mow_dir, fuv).rg * 2.0 - 1.0;
	float wob = (fbm(xz * 0.35) - 0.5) * 0.9;                     // ragged edges
	float d_fair = f.r + wob * 0.5;
	float d_green = f.g + wob * 0.25;
	float d_bunk = f.b + wob * 0.2;
	float d_water = f.a;

	// Photo grain at two scales so the tiling does not show.
	vec2 uv1 = xz / 3.0;
	vec2 uv2 = xz / 11.3 + vec2(0.37, 0.71);
	vec3 g1 = texture(grass_tex, uv1).rgb;
	vec3 g2 = texture(grass_tex, uv2).rgb;
	float grain = lum(mix(g1, g2, 0.4));
	vec3 r1 = texture(rough_tex, xz / 2.6).rgb;
	vec3 r2 = texture(rough_tex, xz / 9.7 + 0.5).rgb;
	vec3 sand = texture(sand_tex, xz / 3.5).rgb;
	float big = fbm(xz * 0.025);                                   // large patches of colour

	// Rough: green grass grain with patches of the map's rough texture (straw fescue on the
	// links, darker leafy grass in the park).
	vec3 rtex = mix(r1, r2, 0.45);
	vec3 lush = grass_color * 0.78 * (0.7 + grain * 0.8);
	vec3 straw = rtex * rough_tint * 1.5;
	float patch = smoothstep(0.35, 0.75, fbm(xz * 0.06 + 9.0));
	vec3 rough = mix(lush, straw, mix(0.25, 0.85, patch));
	rough *= 0.85 + big * 0.3;
	// Fairway: mown stripes along the hole.
	vec2 along = length(md) > 0.2 ? normalize(md) : vec2(0.0, 1.0);
	float across = dot(xz, vec2(-along.y, along.x));
	float stripe = step(0.5, fract(across / 9.0));
	vec3 fair = grass_color * (0.72 + grain * 0.75) * (0.92 + stripe * 0.13) * (0.94 + big * 0.12);
	// First cut: between.
	vec3 cut = mix(fair, rough, 0.45) * 0.95;
	// Green: finer, cross-cut.
	float cross = step(0.5, fract((xz.x + xz.y) / 6.0)) * 0.5 + step(0.5, fract((xz.x - xz.y) / 6.0)) * 0.5;
	vec3 green = green_color * (0.86 + grain * 0.35) * (0.95 + cross * 0.08);
	vec3 collar = green_color * (0.8 + grain * 0.5) * 0.92;

	vec3 col = rough;
	float rgh = 0.92;
	vec3 tn = unpack_n(mix(texture(rough_nor, xz / 2.6), texture(rough_nor, xz / 9.7 + 0.5), 0.45));
	float nstr = 0.9;
	float w_cut = smoothstep(3.0, 1.5, d_fair);
	col = mix(col, cut, w_cut);
	float w_fair = smoothstep(0.35, -0.35, d_fair);
	col = mix(col, fair, w_fair);
	nstr = mix(nstr, 0.45, w_fair);
	float w_collar = smoothstep(1.8, 1.2, d_green);
	col = mix(col, collar, w_collar);
	float w_green = smoothstep(0.15, -0.15, d_green);
	col = mix(col, green, w_green);
	rgh = mix(rgh, 0.78, w_green);
	nstr = mix(nstr, 0.25, max(w_green, w_collar));
	vec3 gn = unpack_n(mix(texture(grass_nor, uv1), texture(grass_nor, uv2), 0.4));
	tn = mix(tn, gn, max(w_fair, w_collar));

	// Bunkers: sand, a darker edge where turf meets it, and smooth raked bottoms.
	vec3 sandc = sand * vec3(1.18, 1.12, 1.0) * (0.95 + big * 0.1);
	float w_sand = smoothstep(0.12, -0.12, d_bunk);
	float lip = smoothstep(0.6, 0.0, abs(d_bunk - 0.15)) * (1.0 - w_sand);
	col *= 1.0 - lip * 0.35;
	col = mix(col, sandc, w_sand);
	rgh = mix(rgh, 0.95, w_sand);
	tn = mix(tn, unpack_n(texture(sand_nor, xz / 3.5)), w_sand);
	nstr = mix(nstr, 0.6, w_sand);

	// Pond banks: wet, dark mud under the water line.
	float wet = smoothstep(2.5, -0.5, d_water);
	col = mix(col, col * vec3(0.45, 0.42, 0.35), wet);
	rgh = mix(rgh, 0.35, wet * 0.8);

	// Links: a beach and the dunes' sandy blowouts.
	if (links > 0.5) {
		float beach = smoothstep(2.4, 0.9, wpos.y - sea_level + (fbm(xz * 0.05) - 0.5) * 1.5);
		float blow = smoothstep(0.82, 0.9, fbm(xz * 0.018 + 3.0)) * smoothstep(8.0, 20.0, d_fair) * smoothstep(8.0, 20.0, d_green);
		float s = max(beach, blow);
		col = mix(col, sand * vec3(1.2, 1.12, 0.98), s);
		rgh = mix(rgh, 0.95, s);
	}

	ALBEDO = col;
	ROUGHNESS = rgh;
	SPECULAR = 0.35;
	NORMAL_MAP = normalize(vec3(tn.xy * nstr, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
