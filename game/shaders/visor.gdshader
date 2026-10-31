shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
// The technician's visor (scripts/visor.gd): the world as a diagnostic X-ray, every crease and silhouette
// traced in cyan from the depth buffer, dimmer with distance. It switches on with a scan line sweeping down.
// Her nerves and pulses (scripts/nerves.gd) are drawn over it.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth : hint_depth_texture, filter_nearest;
uniform float amount = 0.0;
uniform vec3 tint : source_color = vec3(0.3, 0.78, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // the whole screen, whatever the camera
}

// 1 / distance from the camera: flat on any plane, so only creases and edges have a second derivative.
float nearness(vec2 uv, mat4 inverse_projection) {
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, texture(depth, uv).r, 1.0);
	return view.w / -view.z;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float here = nearness(SCREEN_UV, INV_PROJECTION_MATRIX);
	float dx = nearness(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX) + nearness(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - 2.0 * here;
	float dy = nearness(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX) + nearness(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX) - 2.0 * here;
	float edge = clamp((abs(dx) + abs(dy)) / max(here, 0.0001) * 30.0, 0.0, 1.0);
	float distance = 1.0 / max(here, 0.0001);
	float near = exp(-distance * 0.07);
	vec3 world = texture(screen, SCREEN_UV).rgb;
	float light = dot(world, vec3(0.3, 0.59, 0.11));
	vec3 xray = tint * (0.02 + 0.1 * light + 0.05 * near) + tint * edge * (0.25 + 0.75 * near);
	float front = amount * 1.15;  // the scan line, sweeping down as it switches on
	float covered = step(SCREEN_UV.y, front) * clamp(amount * 1.5, 0.0, 1.0);
	ALBEDO = mix(world, xray, covered) + tint * 1.5 * smoothstep(0.012, 0.0, abs(SCREEN_UV.y - front)) * (1.0 - amount);
}
