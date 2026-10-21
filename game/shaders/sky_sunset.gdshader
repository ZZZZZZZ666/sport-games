// Golden-hour sky: deep blue overhead fading to orange and pink at the horizon, a glowing
// sun from the first directional light, and wispy clouds lit from below by the sun.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.13, 0.2, 0.45);
uniform vec3 mid_color : source_color = vec3(0.55, 0.45, 0.62);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.62, 0.36);
uniform vec3 sun_color : source_color = vec3(1.0, 0.58, 0.26);
uniform vec3 below_color : source_color = vec3(0.16, 0.2, 0.32);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float cs = dot(d, sd);
	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.25, up));
	col = mix(col, zenith_color, smoothstep(0.2, 0.85, up));
	// Pink band just above the horizon, warmer toward the sun.
	col = mix(col, vec3(1.0, 0.5, 0.55), exp(-abs(h) * 14.0) * 0.28 * (1.0 - max(cs, 0.0)));
	col += sun_color * (pow(max(cs, 0.0), 6.0) * 0.45 + pow(max(cs, 0.0), 60.0) * 0.9);
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.1) * 0.9 + vec2(TIME * 0.004, 0.0);
		float c = fbm(uv * 1.3);
		float streak = fbm(vec2(uv.x * 0.6, uv.y * 2.4) + 3.0);
		float m = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover * 0.6, c * 0.6 + streak * 0.5);
		m *= smoothstep(0.0, 0.12, h);
		vec3 lit = mix(vec3(0.42, 0.32, 0.5), vec3(1.0, 0.68, 0.45), pow(max(cs * 0.5 + 0.5, 0.0), 3.0));
		col = mix(col, lit, m * 0.85);
	}
	if (!AT_CUBEMAP_PASS) {
		col += vec3(1.0, 0.92, 0.75) * smoothstep(0.9992, 0.9996, cs) * 3.0;
	}
	col = mix(col, below_color, smoothstep(0.0, -0.08, h));
	COLOR = col;
}
