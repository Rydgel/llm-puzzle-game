shader_type spatial;
render_mode cull_disabled;
// Her flood: clear dark water that clouds over as it gets deeper, bends what's under it, and moves.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.01, 0.05, 0.06);
uniform vec3 clear : source_color = vec3(0.75, 0.92, 0.92);

void fragment() {
	vec2 at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 0.1;
	vec3 surface = 0.5 * (texture(ripples, at + vec2(TIME * 0.03, TIME * 0.02)).rgb
		+ texture(ripples, at * 1.7 - vec2(TIME * 0.025, -TIME * 0.035)).rgb);
	NORMAL_MAP = surface;
	NORMAL_MAP_DEPTH = 0.12;
	// How much water lies between the surface and whatever is under it.
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, texture(depth, SCREEN_UV).r);
	vec4 under = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	under.xyz /= under.w;
	float murk = 1.0 - exp(-clamp(VERTEX.z - under.z, 0.0, 4.0) * 1.6);
	vec3 bent = texture(screen, SCREEN_UV + (surface.xy - 0.5) * 0.05 * murk).rgb;
	ALBEDO = deep;
	EMISSION = bent * clear * (1.0 - 0.85 * murk);
	ROUGHNESS = 0.08;
	SPECULAR = 0.5;
}
