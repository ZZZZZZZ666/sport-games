// Stylized see-through sea: turquoise over shallows, deep blue offshore, a foam line where
// it meets the island. Depth comes from the depth texture, so it must stay transparent.
shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.3, 0.86, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.3, 0.6, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0);
uniform float depth_range = 16.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

void fragment() {
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	float depth = clamp(VERTEX.z - view.z, 0.0, 1000.0);
	float t = clamp(depth / depth_range, 0.0, 1.0);
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple = sin(wpos.x * 0.15 + TIME * 1.3) * sin(wpos.z * 0.13 - TIME * 1.1);
	float foam = 1.0 - smoothstep(0.2, 1.8 + ripple * 0.7, depth);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, sqrt(t));
	col = mix(col, foam_color.rgb, foam * 0.85);
	ALBEDO = col;
	ALPHA = clamp(0.6 + t * 0.5 + foam, 0.0, 1.0);
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = vec3(0.55, 0.75, 1.0) * fres * 0.25;
}
