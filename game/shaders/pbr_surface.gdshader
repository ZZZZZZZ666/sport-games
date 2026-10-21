shader_type spatial;
// Scanned PBR surface (Poly Haven albedo / OpenGL normal / ARM maps) for course geometry whose
// UVs are in metres. Breaks up tiling by blending a second, rotated and rescaled sample through
// low-frequency noise, adds large-scale brightness variation, an optional tint from the vertex
// colour, and optional painted road lines. RSPbr builds these materials.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float size_m = 2.0;            // the texture covers this many metres
uniform float normal_depth = 1.0;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metal_mul = 1.0;
uniform float macro = 0.12;            // large-scale brightness variation
uniform float anti_tile = 1.0;
uniform bool use_vertex_color = false;
uniform bool road_lines = false;
uniform float half_width = 9.0;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV / size_m;
	// Second sample: rotated ~37 degrees, scaled, offset; blended by noise.
	const float c = 0.7986;
	const float s = 0.6018;
	mat2 rot = mat2(vec2(c, s), vec2(-s, c));
	vec2 uv2 = rot * uv * 0.83 + vec2(0.37, 0.61);
	float w = smoothstep(0.35, 0.65, vnoise(UV * 0.11 + 3.1)) * anti_tile;

	vec3 a1 = texture(albedo_tex, uv).rgb;
	vec3 a2 = texture(albedo_tex, uv2).rgb;
	vec3 n1 = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_tex, uv2).rgb * 2.0 - 1.0;
	n2.xy = transpose(rot) * n2.xy;     // back into the first sample's tangent frame
	vec3 o1 = texture(orm_tex, uv).rgb;
	vec3 o2 = texture(orm_tex, uv2).rgb;

	vec3 alb = mix(a1, a2, w);
	vec3 nrm = normalize(mix(n1, n2, w));
	vec3 orm = mix(o1, o2, w);

	float m = vnoise(wpos.xz * 0.045) * 0.65 + vnoise(wpos.xz * 0.17 + 7.0) * 0.35;
	alb *= 1.0 + (m - 0.5) * 2.0 * macro;
	alb *= tint.rgb;
	if (use_vertex_color) {
		alb *= COLOR.rgb;
	}
	float rough = clamp(orm.g * rough_mul + rough_add, 0.04, 1.0);

	if (road_lines) {
		// Edge lines and a dashed centre line, a little worn by the asphalt's own texture.
		float ax = abs(wpos.x);
		float edge = 1.0 - smoothstep(0.06, 0.075, abs(ax - (half_width - 0.45)));
		float dash = step(fract(wpos.z / 6.0), 0.5);
		float centre = (1.0 - smoothstep(0.06, 0.075, ax)) * dash;
		float wear = smoothstep(0.25, 0.75, vnoise(wpos.xz * 3.0)) * 0.35 + smoothstep(0.6, 0.9, vnoise(wpos.xz * 23.0)) * 0.3;
		float paint = max(edge, centre) * (1.0 - wear);
		alb = mix(alb, vec3(0.78, 0.76, 0.7), paint);
		rough = mix(rough, 0.55, paint);
		nrm = normalize(mix(nrm, vec3(0.0, 0.0, 1.0), paint * 0.7));
	}

	ALBEDO = alb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = rough;
	METALLIC = clamp(orm.b * metal_mul, 0.0, 1.0);
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_depth;
}
