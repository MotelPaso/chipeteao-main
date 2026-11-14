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
uniform vec3 base_color : source_color = vec3(1.0, 0.85, 0.4);
uniform vec3 mid_color : source_color = vec3(1.0, 0.42, 0.05);
uniform vec3 top_color : source_color = vec3(0.7, 0.1, 0.02);
// Brillo de las vetas de fuego.
uniform float strength : hint_range(0.0, 6.0) = 2.2;
// Color y opacidad del humo entre las vetas.
uniform vec3 smoke_color : source_color = vec3(0.17, 0.045, 0.02);
uniform float smoke_alpha : hint_range(0.0, 1.0) = 0.6;

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
	// Vetas de fuego angostas sobre un cuerpo de humo más ancho.
	float fire = smoothstep(0.4, 0.72, n);
	float body = smoothstep(0.1, 0.42, n);
	vec3 flame = mix(base_color, mid_color, smoothstep(0.0, 0.45, height));
	flame = mix(flame, top_color, smoothstep(0.45, 1.0, height));
	flame = mix(flame, base_color, core * 0.6) * strength * (0.7 + 0.8 * n);
	ALBEDO = mix(smoke_color, flame, fire);
	// Se deshace en la base y en la punta.
	float ends = smoothstep(0.0, 0.06, height) * (1.0 - smoothstep(0.7, 1.0, height));
	ALPHA = clamp(max(fire, body * smoke_alpha) * ends * form * (0.85 + 0.3 * core), 0.0, 1.0);
}
