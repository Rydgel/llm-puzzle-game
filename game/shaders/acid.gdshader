shader_type spatial;
// The acid in the pit: dark and wet, bright veins drifting through it.

uniform vec3 color : source_color = vec3(0.32, 1.0, 0.1);
uniform float energy = 1.6;
uniform sampler2D churn : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 0.09;
	// Two layers of noise drifting apart; where they cross, thin bright veins.
	float a = texture(churn, at + vec2(TIME * 0.011, TIME * 0.007)).r;
	float b = texture(churn, at * 1.9 - vec2(TIME * 0.016, -TIME * 0.009)).r;
	float glow = pow(clamp(1.0 - abs(a - b) * 5.0, 0.0, 1.0), 5.0) + 0.15 * smoothstep(0.45, 0.8, a);
	ALBEDO = color * 0.04;
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	NORMAL_MAP = 0.5 * (texture(ripples, at * 2.0 + vec2(TIME * 0.02, 0.0)).rgb + texture(ripples, at * 2.7 - vec2(0.0, TIME * 0.03)).rgb);
	NORMAL_MAP_DEPTH = 0.6;
	EMISSION = color * energy * (0.03 + glow);
}
