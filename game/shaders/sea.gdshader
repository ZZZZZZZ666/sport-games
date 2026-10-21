shader_type spatial;
render_mode depth_draw_always;
// Open sea for the skate map: a dozen directional swells summed into the surface normal (no
// displacement; the plane is flat), physically lit so the sky and sun do the colouring. Waves
// too small for a pixel fade out into roughness, so the far water glitters instead of aliasing.
// Clear over the beach, opaque within a few metres of depth, foam where it laps the sand.

uniform vec4 deep_color : source_color = vec4(0.015, 0.06, 0.085, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.1, 0.33, 0.32, 1.0);
uniform float clear_depth = 3.5;
uniform float wave_scale = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

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
	vec2 p = wpos.xz;
	float foot = length(fwidth(p));          // metres per pixel here
	vec2 grad = vec2(0.0);
	float amp = 1.1 * wave_scale;
	float k = 0.05;
	float kept = 0.0;
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		// Directions spread by the golden angle around a prevailing wind (from the sea).
		float a = 2.1 + float(i) * 2.399;
		vec2 d = normalize(vec2(cos(a), sin(a)) + vec2(0.35, -0.55));
		float w = sqrt(9.81 * k);
		float ph = dot(d, p) * k - TIME * w + float(i) * 1.73;
		float fade = clamp(1.6 - foot * k * 1.1, 0.0, 1.0);
		grad += d * (amp * k * cos(ph)) * fade;
		kept += amp * k * fade;
		total += amp * k;
		amp *= 0.6;
		k *= 1.62;
	}
	// A little wind chop that is not in the swells.
	vec2 q = p * 1.7 + vec2(TIME * 0.35, -TIME * 0.2);
	float chop = clamp(1.0 - foot * 1.5, 0.0, 1.0) * 0.05;
	grad += vec2(vnoise(q) - vnoise(q + vec2(0.3, 0.0)), vnoise(q) - vnoise(q + vec2(0.0, 0.3))) * chop * 3.0;

	vec3 n = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Water depth along the view ray, from the depth buffer.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	float depth = max(VERTEX.z - view.z, 0.0);
	float t = 1.0 - exp(-depth / clear_depth);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);

	float lap = 1.0 - smoothstep(0.0, 1.4 + 0.5 * sin(TIME * 0.9 + p.x * 0.05), depth);
	float foam = lap * smoothstep(0.35, 0.75, vnoise(p * 1.3 + TIME * 0.25) * 0.7 + vnoise(p * 4.1 - TIME * 0.4) * 0.3 + lap * 0.3);

	ALBEDO = mix(col, vec3(0.88, 0.9, 0.9), foam);
	ALPHA = clamp(mix(0.35, 1.0, t) + foam, 0.0, 1.0);
	// Waves lost below the pixel size come back as roughness.
	ROUGHNESS = mix(0.03, 0.14, 1.0 - kept / total) + foam * 0.6;
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
