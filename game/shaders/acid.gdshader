shader_type spatial;
// The acid in the pit, deep and thick: you see down into it, through glowing clouds churning at different
// depths, to her tiles below fading into its glow. A dull crust drifts on top, its surface heaves slowly,
// and it glows where it meets the walls. The pit is 3 m deep under it (main.gd); her flood raises it.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D churn : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.32, 1.0, 0.1);
uniform float energy = 1.6;

varying vec3 world;

// Two layers of noise drifting apart; where they cross, thin bright veins.
float veins(vec2 at, float drift) {
	float a = texture(churn, at + vec2(TIME * 0.011, TIME * 0.007) * drift).r;
	float b = texture(churn, at * 1.9 - vec2(TIME * 0.016, -TIME * 0.009) * drift).r;
	return pow(clamp(1.0 - abs(a - b) * 5.0, 0.0, 1.0), 5.0);
}

void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += 0.035 * sin(at.x * 0.9 + TIME * 0.6) + 0.045 * sin(at.z * 0.65 - TIME * 0.45);
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ray = mat3(INV_VIEW_MATRIX) * normalize(VERTEX);
	float slope = max(-ray.y, 0.2);
	// Glowing clouds churning inside it, at several depths, each where the view ray reaches it: the deeper,
	// the dimmer and the slower. This is what makes it a volume and not a surface.
	float inside = 0.0;
	for (int layer = 0; layer < 4; layer++) {
		float down = 0.3 + float(layer) * 0.7;
		vec2 at = world.xz + ray.xz / slope * down;
		float drift = TIME * (0.006 + 0.004 * float(layer));
		float cloud = texture(churn, at * 0.05 + vec2(drift, -drift * 0.7) + float(layer) * 0.23).r;
		inside += smoothstep(0.4, 0.85, cloud) * exp(-down * 0.6);
	}
	// A crust floating on top in slow patches, dull and dark: acid, not water.
	float crust = smoothstep(0.52, 0.66, texture(churn, world.xz * 0.11 + vec2(TIME * 0.004, TIME * 0.003)).r);
	vec3 surface = 0.5 * (texture(ripples, world.xz * 0.06 + vec2(TIME * 0.006, TIME * 0.004)).rgb
		+ texture(ripples, world.xz * 0.1 - vec2(TIME * 0.005, -TIME * 0.007)).rgb);
	NORMAL_MAP = surface;
	NORMAL_MAP_DEPTH = 0.25;
	// How much acid lies between the surface and whatever is under it: her tiles fade into its glow.
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, texture(depth, SCREEN_UV).r);
	vec4 under = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	under.xyz /= under.w;
	float thickness = max(VERTEX.z - under.z, 0.0);
	float murk = 1.0 - exp(-thickness * 1.1);
	vec3 bent = texture(screen, SCREEN_UV + (surface.xy - 0.5) * 0.04 * murk).rgb;
	vec3 body = color * energy * (0.05 + 0.5 * inside);
	float edge = 1.0 - smoothstep(0.0, 0.3, thickness);  // where it meets the walls
	vec3 glow = mix(bent * vec3(0.35, 0.9, 0.25), body, murk) + color * energy * (0.35 * veins(world.xz * 0.09, 1.0) + 0.8 * edge);
	ALBEDO = vec3(0.07, 0.1, 0.02) * crust;
	ROUGHNESS = mix(0.08, 0.7, crust);
	SPECULAR = 0.5;
	EMISSION = glow * (1.0 - 0.75 * crust);
}
