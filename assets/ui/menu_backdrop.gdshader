shader_type canvas_item;
// Fondo de los menús (CharacterSelect, QuestLog, Collection, RelicShop):
// degradado vertical oscuro con dos capas de niebla de ruido que se mueven
// lento y una viñeta en las esquinas. Todo procedural, sin texturas: dos
// capas de ruido de cuatro muestras cada una cuestan casi nada a pantalla
// completa.

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
	// fog^3 deja solo las crestas claras: se leen como jirones sueltos.
	col += fog_color * fog * fog * fog * fog_strength;
	float vig = smoothstep(1.25, 0.45, length(uv - 0.5) * 1.7);
	col *= mix(0.5, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
