shader_type spatial;
// The acid, deep and thick: you see down into it, through glowing clouds churning at different depths, to
// her tiles below fading into its glow. A dull crust drifts on top, its surface heaves slowly, and it glows
// where it meets the walls. Its surface is the liquid simulation's (scripts/acid.gd, spill.gd): a height map
// over the pit and the platforms, so it rises, and spills, and runs; where the map is dry, nothing is drawn.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D churn : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.32, 1.0, 0.1);
uniform float energy = 1.6;
uniform sampler2D surface_map : filter_linear, repeat_disable;  // height (r), how fast it flows (g)
uniform vec2 map_origin = vec2(-4.0, -6.0);  // the map's corner, in world x and z
uniform vec2 map_size = vec2(8.0, 24.0);
uniform vec4 pours[4];  // where her vents' streams land (x, z) and how hard they pour (z), 0 to 1
uniform float agitation = 0.0;  // 0 at rest, 1 while it fills or drains: it heaves, churns and foams
uniform float stir = 0.0;  // its own clock, which runs faster while it is agitated

varying vec3 world;
varying float flow;

// Two layers of noise drifting apart; where they cross, thin bright veins.
float veins(vec2 at, float drift) {
	float a = texture(churn, at + vec2(TIME * 0.011, TIME * 0.007) * drift).r;
	float b = texture(churn, at * 1.9 - vec2(TIME * 0.016, -TIME * 0.009) * drift).r;
	return pow(clamp(1.0 - abs(a - b) * 5.0, 0.0, 1.0), 5.0);
}

// The pit, 6 m down between the platforms; the platforms at 0.
float ground(vec3 at) {
	return (at.z > 0.0 && at.z < 12.0 && abs(at.x) < 4.0) ? -6.0 : 0.0;
}

void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 map = texture(surface_map, (at.xz - map_origin) / map_size).rg;
	float wet = map.r - ground(at);
	flow = map.g;
	VERTEX.y = map.r;
	// It heaves, less where it is thin: a spill only creeps.
	float heave = (1.0 + 2.0 * agitation) * smoothstep(0.05, 0.6, wet);
	VERTEX.y += heave * (0.035 * sin(at.x * 0.9 + TIME * 0.6) + 0.045 * sin(at.z * 0.65 - TIME * 0.45));
	// Rings of waves out from where the streams land.
	for (int i = 0; i < 4; i++) {
		float d = distance(at.xz, pours[i].xy);
		VERTEX.y += smoothstep(0.05, 0.6, wet) * pours[i].z * 0.06 * sin(d * 7.0 - TIME * 9.0) * exp(-d * 0.9);
	}
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How deep it is here, from this point's own height over the ground: dry ground draws nothing, and the
	// surface runs right up to the pit's walls.
	float wet = world.y - ground(world);
	if (wet < 0.004) {
		discard;
	}
	vec3 ray = mat3(INV_VIEW_MATRIX) * normalize(VERTEX);
	float slope = max(-ray.y, 0.2);
	// Glowing clouds churning inside it, at several depths, each where the view ray reaches it: the deeper,
	// the dimmer and the slower. This is what makes it a volume and not a surface.
	float inside = 0.0;
	for (int layer = 0; layer < 4; layer++) {
		float down = 0.3 + float(layer) * 0.7;
		vec2 at = world.xz + ray.xz / slope * down;
		float drift = stir * (0.006 + 0.004 * float(layer));
		float cloud = texture(churn, at * 0.05 + vec2(drift, -drift * 0.7) + float(layer) * 0.23).r;
		inside += smoothstep(0.4, 0.85, cloud) * exp(-down * 0.6);
	}
	// A crust floating on top in slow patches, dull and dark: acid, not water.
	float crust = smoothstep(0.52, 0.66, texture(churn, world.xz * 0.11 + vec2(stir * 0.004, stir * 0.003)).r);
	crust *= 1.0 - 0.7 * agitation;  // it breaks up while the acid moves
	// Foam where the streams land, churned, and along the walls while it moves.
	float foam = 0.0;
	for (int i = 0; i < 4; i++) {
		foam += pours[i].z * smoothstep(1.1, 0.1, distance(world.xz, pours[i].xy));
	}
	vec3 surface = 0.5 * (texture(ripples, world.xz * 0.06 + vec2(TIME * 0.006, TIME * 0.004)).rgb
		+ texture(ripples, world.xz * 0.1 - vec2(TIME * 0.005, -TIME * 0.007)).rgb);
	NORMAL_MAP = surface;
	NORMAL_MAP_DEPTH = 0.25;
	// How much acid lies between the surface and whatever is under it: her tiles fade into its glow.
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, texture(depth, SCREEN_UV).r);
	vec4 under = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	under.xyz /= under.w;
	float thickness = max(VERTEX.z - under.z, 0.0);
	float murk = max(1.0 - exp(-thickness * 1.1), 0.45);  // even a thin spill glows: it is acid
	vec3 bent = texture(screen, SCREEN_UV + (surface.xy - 0.5) * 0.04 * murk).rgb;
	vec3 body = color * energy * (0.05 + 0.5 * inside);
	float edge = (1.0 - smoothstep(0.0, 0.3, thickness)) * smoothstep(0.15, 0.4, wet);  // where deep acid meets the walls
	foam += 0.8 * flow + 0.5 * (1.0 - smoothstep(0.0, 0.03, wet)) * agitation;  // where it runs, and its creeping edge
	foam = clamp((foam + 0.5 * agitation * edge) * (0.4 + 0.7 * texture(churn, world.xz * 0.35 + stir * 0.05).r), 0.0, 1.0);
	vec3 glow = mix(bent * vec3(0.35, 0.9, 0.25), body, murk) + color * energy * (0.35 * veins(world.xz * 0.09, 1.0) + 0.8 * edge);
	ALBEDO = mix(vec3(0.07, 0.1, 0.02) * crust, vec3(0.45, 0.75, 0.25), foam);
	ROUGHNESS = mix(mix(0.08, 0.7, crust), 0.5, foam);
	SPECULAR = 0.5;
	EMISSION = glow * (1.0 - 0.75 * crust) + vec3(0.5, 1.3, 0.3) * energy * 0.6 * foam;
}
