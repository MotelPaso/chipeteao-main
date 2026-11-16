shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// La bola de fuego de un estallido (FireBlast.tscn > Ball): se hincha con
// bultos que se mueven y, a medida que avanza `life`, se deshace en jirones
// desde afuera hacia el centro. fire_blast.gd le escribe `life`.

group_uniforms Color;
// Del centro al borde: el corazón casi blanco, el fuego y el borde que se apaga.
uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.72);
uniform vec3 fire_color : source_color = vec3(1.0, 0.45, 0.06);
uniform vec3 edge_color : source_color = vec3(0.75, 0.09, 0.0);
// Brillo del estallido.
uniform float strength : hint_range(0.0, 8.0) = 3.2;

group_uniforms Renacido;
// Los mismos tres colores en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_core_color : source_color = vec3(0.85, 0.97, 1.0);
uniform vec3 ascended_fire_color : source_color = vec3(0.2, 0.62, 1.0);
uniform vec3 ascended_edge_color : source_color = vec3(0.02, 0.12, 0.8);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Forma;
// Tamaño de los bultos y cuánto deforman la bola (en radios).
uniform float lump_scale = 1.7;
uniform float lump_depth : hint_range(0.0, 0.6) = 0.22;
// Rapidez con que hierven.
uniform float boil_speed = 2.2;

// 0-1: cuánto lleva el estallido (0 = recién nace, 1 = ya se deshizo).
instance uniform float life = 0.0;

varying vec3 local_pos;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
				mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
				mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
			f.z);
}

void vertex() {
	float lump = noise3(VERTEX * lump_scale + vec3(0.0, -TIME * boil_speed, 0.0));
	VERTEX += NORMAL * (lump - 0.4) * lump_depth;
	local_pos = VERTEX;
}

void fragment() {
	// 1 mirando al centro de la bola, 0 en su borde.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = noise3(local_pos * lump_scale * 2.2 + vec3(0.0, -TIME * boil_speed * 1.6, 0.0));
	float body = facing * 0.75 + n * 0.45;
	// Se deshace desde lo más frío: primero los bordes, al final el corazón.
	float burn = smoothstep(life * 1.25 - 0.1, life * 1.25 + 0.22, body);
	vec3 core = mix(core_color, ascended_core_color, fire_ascend);
	vec3 fire = mix(fire_color, ascended_fire_color, fire_ascend);
	vec3 edge = mix(edge_color, ascended_edge_color, fire_ascend);
	vec3 color = mix(edge, fire, smoothstep(0.15, 0.6, body));
	color = mix(color, core, smoothstep(0.65, 1.05, body) * (1.0 - life * 0.7));
	ALBEDO = color * strength;
	ALPHA = clamp(burn * (0.35 + 0.65 * facing), 0.0, 1.0);
}
