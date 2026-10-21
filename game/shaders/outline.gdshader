// Inverted-hull outline. Use as `next_pass` on smooth meshes (characters, balls, rounded props).
// Hard-edged meshes (plain boxes) split at the seams; give those a rounded mesh instead.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.05, 0.06, 0.09, 1.0);
uniform float outline_width : hint_range(0.0, 0.1) = 0.012;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
