// Base stylized material: soft two-band toon diffuse, toon specular, fresnel rim light.
// Shared by every character / prop so the whole game reads as one art style.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.4;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Multiply by the mesh vertex colours (stored linear), e.g. the island terrain.
uniform bool use_vertex_color = false;

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_texture, UV).rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	// Rim picks up a little of the surface colour so it doesn't look like a white halo.
	EMISSION = emission_color.rgb + mix(rim_color.rgb, base, 0.35) * fres * rim_strength;
}
