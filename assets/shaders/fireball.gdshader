shader_type spatial;
render_mode unshaded, shadows_disabled;

// Superficie de una bola de fuego (Fireball.tscn): vetas de costra oscura,
// fuego y un corazón casi blanco que fluyen por la esfera. Va sobre una
// esfera de radio 1 que la escena estira.

group_uniforms Color;
// Costra, fuego y corazón de la bola.
uniform vec3 crust_color : source_color = vec3(0.45, 0.06, 0.02);
uniform vec3 fire_color : source_color = vec3(1.0, 0.45, 0.06);
uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.62);
// Brillo de la bola.
uniform float glow : hint_range(0.0, 6.0) = 2.4;

group_uniforms Renacido;
// Costra, fuego y corazón en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_crust_color : source_color = vec3(0.02, 0.06, 0.4);
uniform vec3 ascended_fire_color : source_color = vec3(0.08, 0.45, 1.0);
uniform vec3 ascended_core_color : source_color = vec3(0.7, 0.96, 1.0);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Flujo;
// Tamaño de las vetas (más alto = vetas más chicas) y rapidez con que fluyen.
uniform float vein_scale = 2.6;
uniform float flow_speed = 1.5;

varying vec3 local_pos;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = normalize(local_pos) * vein_scale;
	float n = noise3(p + vec3(0.0, TIME * flow_speed, 0.0)) * 0.65
			+ noise3(p * 2.1 - vec3(TIME * flow_speed * 0.7, 0.0, 0.0)) * 0.35;
	vec3 color = mix(mix(crust_color, ascended_crust_color, fire_ascend),
			mix(fire_color, ascended_fire_color, fire_ascend), smoothstep(0.3, 0.55, n));
	color = mix(color, mix(core_color, ascended_core_color, fire_ascend),
			smoothstep(0.55, 0.85, n));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = color * glow * (0.55 + 0.45 * facing);
}
