shader_type spatial;
// Hemi-octahedral tree impostor (atlases baked by tools/blender/bake_impostor.py).
// One quad per tree, instanced: the instance origin is the tree's ground point, its basis a
// turn about Y times a uniform scale; INSTANCE_CUSTOM.rgb tints the foliage. The quad faces
// the camera (the sun in the shadow pass), and the fragment blends the four atlas frames baked
// nearest the view direction, lit with the baked normals.
render_mode cull_disabled;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform float radius = 4.0;        // bounding sphere, metres at scale 1
uniform float centre_up = 4.0;     // sphere centre above the ground point
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform vec3 backlight_color : source_color = vec3(0.55, 0.62, 0.3);

varying vec2 v_grid;               // view direction on the frame grid (continuous)
varying vec3 v_tint;
varying mat3 v_rot;                // tree local -> world rotation

vec2 hemi_oct(vec3 b) {
	// Blender axes (z up), z >= 0 -> [-1, 1]^2
	float s = abs(b.x) + abs(b.y) + b.z;
	return vec2(b.x / s + b.y / s, b.x / s - b.y / s);
}

void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	mat3 rot = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz) / sc;
	vec3 centre = MODEL_MATRIX[3].xyz + rot * vec3(0.0, centre_up * sc, 0.0);
	vec3 d;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		d = INV_VIEW_MATRIX[2].xyz;              // orthographic (directional shadow): along the view
	} else {
		d = normalize(CAMERA_POSITION_WORLD - centre);
	}
	vec3 dl = transpose(rot) * d;
	dl.y = max(dl.y, 0.0);
	dl = normalize(dl + vec3(0.0, 1e-4, 0.0));
	vec2 uv = hemi_oct(vec3(dl.x, -dl.z, dl.y));
	v_grid = (uv * 0.5 + 0.5) * frames - 0.5;
	// Billboard axes, as the bake framed its camera: right = up x d, up = d x right.
	vec3 up = abs(dl.y) > 0.999 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, dl));
	vec3 cup = cross(dl, right);
	// Built in the tree's own space; the instance transform adds the turn and the scale.
	VERTEX = vec3(0.0, centre_up, 0.0) + (right * VERTEX.x + cup * VERTEX.y) * (2.0 * radius);
	NORMAL = dl;
	v_tint = INSTANCE_CUSTOM.rgb;
	v_rot = rot;
}

void fragment() {
	vec2 g = clamp(v_grid, vec2(0.0), vec2(frames - 1.0));
	vec2 g0 = min(floor(g), vec2(frames - 2.0));
	vec2 f = g - g0;
	vec4 col = vec4(0.0);
	vec4 nor = vec4(0.0);
	float wsum = 0.0;
	for (int k = 0; k < 4; k++) {
		vec2 cell = g0 + vec2(float(k & 1), float(k >> 1));
		float w = (k & 1) == 1 ? f.x : 1.0 - f.x;
		w *= (k >> 1) == 1 ? f.y : 1.0 - f.y;
		if (w < 0.01) {
			continue;
		}
		vec2 auv = vec2((cell.x + UV.x) / frames, (frames - 1.0 - cell.y + UV.y) / frames);
		vec4 a = texture(albedo_atlas, auv);
		vec4 n = texture(normal_atlas, auv);
		col += vec4(a.rgb * a.a, a.a) * w;
		nor += vec4(n.rgb * a.a, n.a * a.a) * w;
		wsum += w;
	}
	col /= max(wsum, 1e-4);
	nor /= max(wsum, 1e-4);
	float cov = col.a;
	vec3 albedo = col.rgb / max(cov, 1e-3);
	float leaf = clamp(nor.a / max(cov, 1e-3), 0.0, 1.0);
	vec3 n_local = normalize(nor.rgb / max(cov, 1e-3) * 2.0 - 1.0);
	ALBEDO = albedo * mix(vec3(1.0), v_tint, leaf);
	NORMAL = normalize((VIEW_MATRIX * vec4(v_rot * n_local, 0.0)).xyz);
	ROUGHNESS = mix(0.85, 0.7, leaf);
	SPECULAR = 0.3;
	BACKLIGHT = backlight_color * leaf * 0.6;
	ALPHA = cov;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.25;
}
