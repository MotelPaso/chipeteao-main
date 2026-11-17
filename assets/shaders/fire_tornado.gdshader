shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Embudo de un tornado de fuego (FireTornado.tscn). Va sobre un cilindro sin
// tapas de alto 1, más ancho arriba que abajo, que la escena estira. Es una
// columna de humo oscuro con vetas de fuego que suben girando (así se lee
// también contra el cielo rojo del infierno), y el embudo se bambolea.
// Cuánto está formado y si es el corazón (más claro y más rápido) viaja por
// instancia.

group_uniforms Color;
// Color en la base, en el medio y en lo alto del embudo.
uniform vec3 base_color : source_color = vec3(1.0, 0.66, 0.2);
uniform vec3 mid_color : source_color = vec3(1.0, 0.36, 0.04);
uniform vec3 top_color : source_color = vec3(0.7, 0.1, 0.02);
// Brillo de las vetas de fuego.
uniform float strength : hint_range(0.0, 6.0) = 1.05;
// Color y opacidad del humo entre las vetas.
uniform vec3 smoke_color : source_color = vec3(0.17, 0.045, 0.02);
uniform float smoke_alpha : hint_range(0.0, 1.0) = 0.6;

group_uniforms Renacido;
// Base, medio, punta y humo en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_base_color : source_color = vec3(0.7, 0.95, 1.0);
uniform vec3 ascended_mid_color : source_color = vec3(0.1, 0.5, 1.0);
uniform vec3 ascended_top_color : source_color = vec3(0.04, 0.12, 0.75);
uniform vec3 ascended_smoke_color : source_color = vec3(0.02, 0.04, 0.17);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Remolino;
// Vetas de fuego alrededor del embudo (número entero).
uniform float bands = 5.0;
// Vueltas que da cada veta de la base a la punta.
uniform float twist = 1.4;
// Vueltas por segundo que gira y rapidez con que suben las vetas.
uniform float spin_speed = 1.3;
uniform float rise_speed = 1.1;
// Cuánto se bambolea la punta (en radios) y con qué rapidez.
uniform float wobble_amount = 0.22;
uniform float wobble_speed = 2.4;
// Cuánto del dibujo es grano fino (0 = solo vetas anchas; más alto = lenguas chicas que rompen las vetas).
uniform float detail : hint_range(0.0, 0.8) = 0.35;
// Qué tan ancho es el borde que se deshace en la silueta del embudo (0 = borde duro).
uniform float soft_edge : hint_range(0.0, 1.0) = 0.32;
// Cuánto más brilla donde el tornado toca el suelo.
uniform float base_heat : hint_range(0.0, 2.0) = 0.3;

// 0-1: cuánto está formado (0 = invisible).
instance uniform float form = 1.0;
// 1 en el corazón del tornado: más claro y más rápido.
instance uniform float core = 0.0;

varying float height;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Ruido que se repite cada `period` en x, para que cierre alrededor del embudo.
float wrap_noise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	float a = hash21(vec2(x0, i.y));
	float b = hash21(vec2(x1, i.y));
	float c = hash21(vec2(x0, i.y + 1.0));
	float d = hash21(vec2(x1, i.y + 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	// El cilindro va de -0.5 (base) a 0.5 (punta).
	height = VERTEX.y + 0.5;
	float lean = wobble_amount * height * height;
	VERTEX.x += sin(TIME * wobble_speed + height * 5.0) * lean;
	VERTEX.z += cos(TIME * wobble_speed * 0.8 + height * 4.0) * lean;
}

void fragment() {
	float count = max(floor(bands), 1.0);
	float around = UV.x * count + height * twist * count
			- TIME * spin_speed * count * (1.0 + 0.6 * core);
	float n = wrap_noise(vec2(around, height * 7.0 - TIME * rise_speed * 3.0), count);
	// Un grano más fino y más rápido rompe las vetas en lenguas de fuego.
	float fine = wrap_noise(vec2(around * 4.0 + 7.0, height * 9.0 - TIME * rise_speed * 5.0),
			count * 4.0);
	n = mix(n, fine, detail);
	// Vetas de fuego angostas sobre un cuerpo de humo más ancho.
	float fire = smoothstep(0.42, 0.68, n);
	float body = smoothstep(0.14, 0.42, n);
	vec3 base = mix(base_color, ascended_base_color, fire_ascend);
	vec3 flame = mix(base, mix(mid_color, ascended_mid_color, fire_ascend),
			smoothstep(0.0, 0.45, height));
	flame = mix(flame, mix(top_color, ascended_top_color, fire_ascend),
			smoothstep(0.45, 1.0, height));
	flame = mix(flame, base, core * 0.6) * strength * (0.7 + 0.8 * n);
	flame += base * base_heat * (1.0 - smoothstep(0.0, 0.28, height));
	ALBEDO = mix(mix(smoke_color, ascended_smoke_color, fire_ascend), flame, fire);
	// Se deshace en la base y en la punta.
	float ends = smoothstep(0.0, 0.06, height) * (1.0 - smoothstep(0.7, 1.0, height));
	// Y en la silueta, para que el embudo no termine en un borde duro.
	float rim = smoothstep(0.0, max(soft_edge, 0.001), abs(dot(NORMAL, VIEW)));
	ALPHA = clamp(max(fire, body * smoke_alpha) * ends * rim * form * (0.85 + 0.3 * core),
			0.0, 1.0);
}
