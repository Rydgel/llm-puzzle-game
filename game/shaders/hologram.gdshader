shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// Her projection (scripts/hologram.gd): a bridge she draws in light over the acid, flickering, scanned, not
// there. Where her searchlight eye looks, it hardens into solid light, steady and bright.

uniform vec3 color : source_color = vec3(1.0, 0.42, 0.06);
uniform float solid = 0.0;  // 0 a hologram, 1 hard light
uniform vec2 half_size = vec2(0.6, 0.5);  // of a cell, across and along

varying vec3 local;
varying vec3 world;

void vertex() {
	local = VERTEX;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge_x = smoothstep(half_size.x - 0.06, half_size.x, abs(local.x));
	float edge_z = smoothstep(half_size.y - 0.06, half_size.y, abs(local.z));
	float edge = max(edge_x, edge_z);
	float scan = 0.5 + 0.5 * sin(world.z * 40.0 - TIME * 6.0);
	float flicker = 0.8 + 0.2 * sin(TIME * 43.0 + world.z * 7.0) * sin(TIME * 17.0);
	float hex = abs(sin(world.x * 18.0) * sin(world.z * 18.0));
	vec3 hologram = color * (0.4 * scan + 1.8 * edge) * flicker;
	vec3 hard = mix(color, vec3(1.0), 0.45) * (0.5 + 0.35 * hex) + color * 3.0 * edge;
	ALBEDO = mix(hologram, hard, solid);
	ALPHA = mix(0.14 + 0.5 * edge, 0.8 + 0.2 * edge, solid);
}
