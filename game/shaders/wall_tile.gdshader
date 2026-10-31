shader_type spatial;
// Her wall tiles (scripts/facility.gd). One MultiMesh holds them all: INSTANCE_CUSTOM is each tile's center
// in the world (xyz) and a random number (w). A tile's local +Z points into the room, its back at z = 0 and
// its face at z = 0.18, so pushing a tile out moves it along +Z. Her light comes through the seams: the
// tiles' sides glow with it, brighter toward the back.

uniform sampler2D grain : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.6, 0.57);
uniform vec3 her_color : source_color = vec3(1.0, 0.42, 0.06);
uniform float her_energy = 3.0;
uniform float breathe = 0.0;  // her voice, 0 to 1: the walls breathe deeper while she talks
uniform vec3 subject = vec3(0.0, -100.0, 0.0);  // tiles near the subject lean out toward them
uniform vec4 ripple = vec4(0.0, -100.0, 0.0, 99.0);  // a ripple's origin (xyz) and age in seconds (w)
uniform float ripple_strength = 0.0;
uniform float restless_from = 7.0;  // tiles above this height shift on their own: the shaft over the pit
uniform float rigid = 0.0;  // 1 for a tile pulled out into a beam (scripts/sculpt.gd): it holds still

varying float side;
varying float depth;
varying float shade;

void vertex() {
	vec3 center = INSTANCE_CUSTOM.xyz;
	side = 1.0 - abs(NORMAL.z);
	depth = 1.0 - clamp(VERTEX.z / 0.18, 0.0, 1.0);
	shade = INSTANCE_CUSTOM.w;
	float push = (0.004 + 0.035 * breathe) * sin(TIME * (1.4 + 2.5 * breathe) - dot(center, vec3(0.5, 0.7, 0.4)));
	float near = distance(center, subject);
	push += 0.07 * exp(-near * near / 2.5);
	float front = distance(center, ripple.xyz) - ripple.w * 7.0;
	push += ripple_strength * exp(-front * front / 0.6) * exp(-ripple.w * 0.5);
	float wake = smoothstep(restless_from, restless_from + 3.0, center.y);
	float cycle = sin(TIME * 0.22 + shade * 61.0);
	push += wake * (0.9 * pow(max(cycle, 0.0), 24.0) - 0.15 * pow(max(-cycle, 0.0), 8.0));
	VERTEX.z += push * (1.0 - rigid);
	UV = VERTEX.xy * 0.45 + vec2(shade * 7.31, shade * 3.17);
}

void fragment() {
	float grain_light = dot(texture(grain, UV).rgb, vec3(0.333));
	ALBEDO = tint * (0.8 + 0.3 * grain_light) * (0.94 + 0.12 * shade);
	NORMAL_MAP = texture(grain_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.5;
	ROUGHNESS = mix(0.3, 0.6, texture(grain_roughness, UV).r);
	EMISSION = her_color * her_energy * side * depth * depth * mix(1.0, 0.3, rigid);
}
