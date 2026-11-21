shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Cola de llama de algo que vuela o sale disparado (las plumas ardientes, las
// bolas de fuego y el chorro que baja del pico de Mythos). Va sobre un cono
// de alto 1 y radio 0.5 que cada escena estira: la base (y = -0.5) es la
// cabeza, pegada a lo que arde, y la punta (y = 0.5) el final de la cola.
// Las lenguas de fuego corren de la cabeza a la punta y la cola serpentea.

group_uniforms Color;
// Del centro al borde de la llama: corazón casi blanco, fuego y borde que se apaga.
uniform vec3 core_color : source_color = vec3(1.0, 0.92, 0.6);
uniform vec3 fire_color : source_color = vec3(1.0, 0.45, 0.06);
uniform vec3 edge_color : source_color = vec3(0.7, 0.08, 0.0);
// Brillo de la cola.
uniform float strength : hint_range(0.0, 8.0) = 2.6;

group_uniforms Renacido;
// Los mismos tres colores en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_core_color : source_color = vec3(0.85, 0.97, 1.0);
uniform vec3 ascended_fire_color : source_color = vec3(0.2, 0.62, 1.0);
uniform vec3 ascended_edge_color : source_color = vec3(0.02, 0.12, 0.8);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Forma;
// Tamaño de las lenguas de fuego (más alto = más chicas) y rapidez con que corren hacia la punta.
uniform float tongue_scale = 3.2;
uniform float flow_speed = 5.0;
// Cuánto se apaga la llama hacia la punta (1 = la punta se deshace del todo; 0 = arde entera).
uniform float tip_fade : hint_range(0.0, 1.0) = 0.9;
// Cuánto serpentea la punta (en radios) y con qué rapidez.
uniform float wobble_amount = 0.25;
uniform float wobble_speed = 15.0;

// 0-1: opacidad de toda la cola (quien la usa la apaga con esto).
instance uniform float fade = 1.0;

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
	local_pos = VERTEX;
	// 0 en la cabeza, 1 en la punta: la cola serpentea más cuanto más lejos.
	float along = VERTEX.y + 0.5;
	float reach = along * along * wobble_amount;
	VERTEX.x += sin(TIME * wobble_speed + along * 9.0) * reach;
	VERTEX.z += cos(TIME * wobble_speed * 0.77 + along * 7.0) * reach;
}

void fragment() {
	float along = local_pos.y + 0.5;
	// 1 mirando al centro de la llama, 0 en su silueta.
	float facing = abs(dot(NORMAL, VIEW));
	float n = noise3(vec3(local_pos.x * tongue_scale * 2.0,
			along * tongue_scale - TIME * flow_speed, local_pos.z * tongue_scale * 2.0));
	float body = facing * (1.0 - along * tip_fade) + (n - 0.5) * 0.55;
	vec3 core = mix(core_color, ascended_core_color, fire_ascend);
	vec3 fire = mix(fire_color, ascended_fire_color, fire_ascend);
	vec3 edge = mix(edge_color, ascended_edge_color, fire_ascend);
	vec3 color = mix(edge, fire, smoothstep(0.15, 0.5, body));
	color = mix(color, core, smoothstep(0.55, 0.95, body));
	ALBEDO = color * strength;
	ALPHA = smoothstep(0.06, 0.45, body) * fade;
}
