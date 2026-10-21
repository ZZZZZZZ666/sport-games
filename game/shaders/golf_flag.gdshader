shader_type spatial;
// Pin flag: a small cloth on the flagstick, rippling harder in more wind. The mesh is a plane
// facing +Z, its left edge (x = -0.275) on the pole.
render_mode cull_disabled;

uniform vec4 color : source_color = vec4(0.85, 0.1, 0.12, 1.0);
uniform float wind = 3.0;      // m/s

void vertex() {
	float u = clamp((VERTEX.x + 0.275) / 0.55, 0.0, 1.0);
	float amp = (0.025 + clamp(wind, 0.0, 12.0) * 0.006) * u;
	float ph = TIME * (5.0 + wind * 0.6) - u * 7.0;
	VERTEX.z += sin(ph) * amp + sin(ph * 1.7 + VERTEX.y * 9.0) * amp * 0.35;
	VERTEX.y -= u * u * max(0.0, 0.06 - wind * 0.008);
	NORMAL = normalize(NORMAL + vec3(-cos(ph) * amp * 6.0, 0.0, 0.0));
}

void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = 0.8;
	BACKLIGHT = color.rgb * 0.4;
}
