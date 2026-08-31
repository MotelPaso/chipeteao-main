shader_type canvas_item;
// Menu backdrop (CharacterSelect / QuestLog): vertical dark gradient with
// two layers of slowly drifting value-noise fog and a corner vignette.
// Fully procedural — no textures. Two noise layers at four taps each keep
// it trivially cheap for a full-screen rect.

uniform vec3 top_color: source_color = vec3(0.07, 0.085, 0.135);
uniform vec3 bottom_color: source_color = vec3(0.028, 0.032, 0.052);
uniform vec3 fog_color: source_color = vec3(0.18, 0.26, 0.33);
uniform float fog_strength = 0.20;
uniform float drift_speed = 0.03;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
			f.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color, bottom_color, uv.y);
	float t = TIME * drift_speed;
	float fog = vnoise(uv * vec2(3.0, 2.2) + vec2(t * 2.0, t)) * 0.65
			+ vnoise(uv * vec2(7.0, 5.0) - vec2(t * 3.0, t * 0.6)) * 0.35;
	// fog^3 keeps only the bright crests, reading as sparse drifting wisps.
	col += fog_color * fog * fog * fog * fog_strength;
	float vig = smoothstep(1.25, 0.45, length(uv - 0.5) * 1.7);
	col *= mix(0.5, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
