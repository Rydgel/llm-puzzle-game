shader_type canvas_item;
// Over the whole picture: a soft vignette and film grain, and her glitch, when her voice breaks up or she
// reboots: the picture tears into bands and its colors split.

uniform sampler2D picture : hint_screen_texture, filter_linear_mipmap;
uniform float glitch = 0.0;  // 0 to 1
uniform vec3 her_color : source_color = vec3(1.0, 0.42, 0.06);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float tick = floor(TIME * 18.0);
	// Torn bands: some rows slide sideways for a frame or two.
	float band = floor(uv.y * 24.0);
	float tear = step(1.0 - 0.35 * glitch, hash(vec2(band, tick))) * (hash(vec2(tick, band)) - 0.5) * 0.08 * glitch;
	uv.x += tear;
	float split = 0.004 * glitch + abs(tear) * 0.5;
	vec3 color = vec3(texture(picture, uv + vec2(split, 0.0)).r, texture(picture, uv).g, texture(picture, uv - vec2(split, 0.0)).b);
	// Her color bleeds into torn rows, and scanlines show through.
	color = mix(color, color * her_color * 2.0, step(0.001, abs(tear)) * 0.5);
	color *= 1.0 - glitch * 0.25 * step(0.5, fract(SCREEN_UV.y * 240.0));
	float edge = distance(SCREEN_UV, vec2(0.5));
	color *= 1.0 - smoothstep(0.45, 0.95, edge) * 0.55;
	color += (hash(SCREEN_UV * 731.0 + fract(TIME)) - 0.5) * 0.025;
	COLOR = vec4(color, 1.0);
}
