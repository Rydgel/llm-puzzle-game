shader_type spatial;
render_mode cull_disabled;
// A stream of acid pouring from one of her vents (scripts/acid.gd): bright, streaked, running down. It ends
// where it lands in the acid, and its head and tail run down it as the vent starts and stops pouring.

uniform sampler2D churn : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.32, 1.0, 0.1);
uniform float energy = 1.6;
uniform float surface = -3.0;  // the acid's level
uniform float head = 0.0;  // how far down the stream the acid has reached, 0 to 1
uniform float tail = 0.0;  // how far down it has stopped pouring, 0 to 1

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (height < surface - 0.05 || UV.y > head || UV.y < tail) {
		discard;
	}
	float streak = texture(churn, vec2(UV.x * 0.5, UV.y * 1.5 - TIME * 1.8)).r;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = color * 0.08;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	EMISSION = color * energy * (0.5 + 1.8 * smoothstep(0.35, 0.8, streak) + 0.8 * rim);
}
