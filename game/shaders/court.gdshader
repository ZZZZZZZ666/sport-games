shader_type spatial;
// Rooftop floor for RSBallCourt: scanned concrete (Poly Haven) everywhere, and on each half
// court a coat of acrylic court paint (two tones, a contrasting key) with FIBA lines drawn
// analytically, so they stay crisp at any distance. Paint is worn through in patches.
// Court coordinates: x across (0 = under the rim), z out from the rim centre (+z = toward
// the half-way line).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float size_m = 3.0;
uniform float pitch = 17.0;            // court centres this far apart along x
uniform int courts = 4;
uniform vec4 court_col : source_color = vec4(0.13, 0.33, 0.55, 1.0);
uniform vec4 inner_col : source_color = vec4(0.18, 0.42, 0.62, 1.0);
uniform vec4 key_col : source_color = vec4(0.78, 0.33, 0.16, 1.0);
uniform vec4 line_col : source_color = vec4(0.95, 0.95, 0.92, 1.0);
uniform float wear = 1.0;
uniform float wet = 0.0;               // 0..1, puddle sheen (night map)

const float BASE_Z = -1.575;           // baseline, from the rim centre
const float HALF_W = 7.5;
const float LEN = 14.0;
const float LW = 0.05;                 // line width

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / size_m;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * wpos.xz / (size_m * 1.43) + 0.37;
	float w2 = smoothstep(0.3, 0.7, vnoise(wpos.xz * 0.15));
	vec3 conc = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv2).rgb, w2);
	vec3 cn = normalize(mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv2).rgb, w2) * 2.0 - 1.0);
	vec3 orm = mix(texture(orm_tex, uv).rgb, texture(orm_tex, uv2).rgb, w2);
	float macro = vnoise(wpos.xz * 0.05) * 0.6 + vnoise(wpos.xz * 0.21) * 0.4;
	conc = mix(vec3(dot(conc, vec3(0.33))), conc, 0.6);
	conc = mix(vec3(0.42), conc, 0.55) * (0.88 + macro * 0.24);   // calmer, lighter concrete

	// Which court, and where on it.
	float span = pitch * float(courts);
	float ci = clamp(floor((wpos.x + span * 0.5) / pitch), 0.0, float(courts - 1));
	vec2 p = vec2(wpos.x - (-span * 0.5 + pitch * (ci + 0.5)), wpos.z);
	float aa = max(fwidth(p.x), fwidth(p.y)) * 1.2;

	float on_court = step(abs(p.x), HALF_W) * step(BASE_Z, p.y) * step(p.y, BASE_Z + LEN);
	float apron = step(abs(p.x), HALF_W + 0.6) * step(BASE_Z - 1.0, p.y) * step(p.y, BASE_Z + LEN + 1.0);
	float r = length(p);
	float inside_arc = (abs(p.x) < 6.6 && (r < 6.75 || p.y < 1.416)) ? 1.0 : 0.0;
	float key = step(abs(p.x), 2.45) * step(p.y, BASE_Z + 5.8);
	vec3 paint = mix(court_col.rgb, inner_col.rgb, inside_arc);
	paint = mix(paint, key_col.rgb, key);
	paint = mix(vec3(0.16, 0.18, 0.2), paint, on_court);        // dark border band round the court

	// Lines.
	float d = 1e3;
	d = min(d, abs(abs(p.x) - HALF_W + LW * 0.5) + max(0.0, max(BASE_Z - p.y, p.y - BASE_Z - LEN)));
	d = min(d, abs(p.y - BASE_Z - LW * 0.5) + max(0.0, abs(p.x) - HALF_W));
	d = min(d, abs(p.y - BASE_Z - LEN) + max(0.0, abs(p.x) - HALF_W));
	d = min(d, seg(p, vec2(-2.45, BASE_Z), vec2(-2.45, BASE_Z + 5.8)));
	d = min(d, seg(p, vec2(2.45, BASE_Z), vec2(2.45, BASE_Z + 5.8)));
	d = min(d, seg(p, vec2(-2.45, BASE_Z + 5.8), vec2(2.45, BASE_Z + 5.8)));
	vec2 ft = p - vec2(0.0, BASE_Z + 5.8);
	d = min(d, abs(length(ft) - 1.8));                                      // free-throw circle
	d = min(d, abs(length(p - vec2(0.0, BASE_Z + LEN)) - 1.8));             // centre circle (half)
	d = min(d, abs(r - 1.25) + max(0.0, -p.y) * 4.0);                       // no-charge semicircle
	float arc = abs(r - 6.75) + max(0.0, 1.416 - p.y) * 4.0;
	d = min(d, arc);
	d = min(d, seg(p, vec2(-6.6, BASE_Z), vec2(-6.6, 1.416)));
	d = min(d, seg(p, vec2(6.6, BASE_Z), vec2(6.6, 1.416)));
	float line = (1.0 - smoothstep(LW * 0.5 - aa, LW * 0.5 + aa, d)) * apron;

	// Wear: the paint is scuffed through where players stand most, and in random patches.
	float scuff = vnoise(wpos.xz * 2.3) * 0.5 + vnoise(wpos.xz * 9.0) * 0.35 + vnoise(wpos.xz * 37.0) * 0.15;
	float hot = exp(-pow(r - 6.9, 2.0) * 0.8) * 0.25 + exp(-dot(p - vec2(0.0, 1.5), p - vec2(0.0, 1.5)) * 0.2) * 0.2;
	float coat = apron * smoothstep(0.2, 0.26, scuff + 0.1 - hot * wear * 0.3);
	vec3 painted = paint * (0.82 + 0.25 * dot(conc, vec3(0.33)));
	painted = mix(painted, line_col.rgb * (0.9 + 0.1 * macro), line);
	float line_coat = line * smoothstep(0.22, 0.3, scuff + 0.1);
	float cov = max(coat, line_coat);

	ALBEDO = mix(conc, painted, cov);
	ROUGHNESS = mix(orm.g, mix(0.62, 0.5, line), cov) * (1.0 - wet * 0.75 * smoothstep(0.45, 0.6, macro));
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.5, cov);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = normalize(mix(cn, vec3(0.0, 0.0, 1.0), cov * 0.65)) * 0.5 + 0.5;
}
