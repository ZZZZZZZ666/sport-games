shader_type spatial;
// A size-7 basketball, all procedural in object space: eight panels of pebbled leather split by
// sunken black seams (two great circles and the two curved ones). The pebbles are a bump map
// from a cell pattern (screen-space derivative bump, faded out with distance). `money` paints
// the panels red / white / blue like the contest's money ball.

uniform vec4 leather : source_color = vec4(0.78, 0.31, 0.08, 1.0);
uniform vec4 seam_col : source_color = vec4(0.03, 0.025, 0.02, 1.0);
uniform bool money = false;
uniform float pebble_freq = 52.0;
uniform float bump = 0.35;

varying vec3 on;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float cells(vec3 p) {
	// Distance to the nearest feature point (F1), 0..~1.
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 8.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = hash3(i + g) * 0.8 + 0.1;
		vec3 r = g + o - f;
		d = min(d, dot(r, r));
	}
	return sqrt(d);
}

void vertex() {
	on = NORMAL;
}

void fragment() {
	vec3 n = normalize(on);
	// Seams (distances on the unit sphere, roughly in radians).
	float s1 = abs(n.y);                                                  // equator
	float s2 = abs(n.x);                                                  // meridian
	float curve = 0.6 + 0.3 * (n.z * n.z - n.y * n.y);
	float s3 = abs(abs(n.z) - curve) * 1.2;                               // the two curved seams
	float sd = min(min(s1, s2), s3);
	float aa = fwidth(sd) * 1.5 + 1e-4;
	float seam = 1.0 - smoothstep(0.022 - aa, 0.022 + aa, sd);
	float groove = 1.0 - smoothstep(0.0, 0.05, sd);

	vec3 col = leather.rgb;
	if (money) {
		int panel = int(n.x > 0.0) + 2 * int(n.y > 0.0) + 4 * int(abs(n.z) > curve);
		vec3 pal[3] = vec3[3](vec3(0.75, 0.06, 0.07), vec3(0.92, 0.92, 0.9), vec3(0.07, 0.18, 0.62));
		col = pal[panel % 3];
	}

	// Pebbles: round bumps, fading out where they'd shimmer.
	float h = 1.0 - smoothstep(0.18, 0.5, cells(n * pebble_freq));
	float fade = 1.0 - smoothstep(0.15, 0.6, fwidth(n.x * pebble_freq));
	h *= fade * (1.0 - groove);
	vec3 N = NORMAL;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h - groove * 3.0) * bump * 0.004;
	float dhy = dFdy(h - groove * 3.0) * bump * 0.004;
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * N - grad);

	ALBEDO = mix(col * (0.9 + 0.12 * h), seam_col.rgb, seam);
	ROUGHNESS = mix(mix(0.66, 0.56, h), 0.82, seam);
	SPECULAR = 0.45;
	RIM = 0.12;
	RIM_TINT = 0.5;
}
