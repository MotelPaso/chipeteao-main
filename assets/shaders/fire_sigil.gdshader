shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// El aviso en el suelo de un golpe de Mythos (FireSigil.tscn): un aro que
// marca desde el primer momento hasta dónde llega el golpe, una rueda de
// marcas que gira y un relleno de brasas que crece desde el centro: cuando
// toca el aro, cae el golpe. Va sobre un plano de 2 x 2. fire_sigil.gd
// escribe `fill`, `fade` y `locked`.

group_uniforms Color;
// Color del aro y las marcas, y de las brasas del relleno.
uniform vec3 ring_color : source_color = vec3(1.0, 0.5, 0.08);
uniform vec3 ember_color : source_color = vec3(1.0, 0.82, 0.4);
// Color cuando el aviso ya está clavado (la Picada dejó de perseguir).
uniform vec3 locked_color : source_color = vec3(1.0, 0.95, 0.85);
// Brillo del aviso.
uniform float strength : hint_range(0.0, 8.0) = 2.2;

group_uniforms Renacido;
// Los mismos colores en la segunda fase del jefe.
uniform vec3 ascended_ring_color : source_color = vec3(0.2, 0.6, 1.0);
uniform vec3 ascended_ember_color : source_color = vec3(0.6, 0.9, 1.0);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Forma;
// Marcas de la rueda y vueltas por segundo a las que gira.
uniform float marks = 16.0;
uniform float spin = 0.12;
// Latidos por segundo del aro al empezar y justo antes del golpe.
uniform float pulse_slow = 1.5;
uniform float pulse_fast = 7.0;

// 0-1: cuánto creció el relleno (1 = cae el golpe), cuánto se ve y si está clavado.
instance uniform float fill = 0.0;
instance uniform float fade = 1.0;
instance uniform float locked = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float turn = atan(p.y, p.x) / TAU;
	float beat = 0.72 + 0.28 * sin(TIME * TAU * mix(pulse_slow, pulse_fast, fill * fill));
	// El aro: el borde del golpe, visible desde el principio.
	float ring = smoothstep(0.925, 0.955, r) * (1.0 - smoothstep(0.975, 1.0, r));
	float halo = (1.0 - smoothstep(0.0, 0.14, abs(r - 0.96))) * 0.25;
	// La rueda de marcas, un poco más adentro, girando.
	float wheel = step(0.55, fract((turn + TIME * spin) * marks))
			* smoothstep(0.80, 0.82, r) * (1.0 - smoothstep(0.885, 0.905, r));
	float inner = step(0.5, fract((turn - TIME * spin * 1.7) * marks * 0.5))
			* smoothstep(0.585, 0.6, r) * (1.0 - smoothstep(0.615, 0.63, r)) * 0.6;
	// El relleno: brasas que crecen desde el centro, con el frente más vivo.
	float grown = fill * 0.93;
	float inside = 1.0 - smoothstep(grown - 0.015, grown, r);
	float embers = noise2(p * 4.5 + vec2(0.0, -TIME * 0.9)) * noise2(p * 9.0 + vec2(TIME * 0.6, 0.0));
	float front = smoothstep(grown - 0.1, grown, r) * inside;
	float body = inside * (0.05 + 0.32 * embers) + front * 0.85;
	vec3 ring_c = mix(mix(ring_color, ascended_ring_color, fire_ascend), locked_color, locked);
	vec3 ember_c = mix(mix(ember_color, ascended_ember_color, fire_ascend), locked_color, locked * 0.6);
	float lines = (ring + halo) * beat + wheel * 0.8 + inner;
	float cover = clamp(lines + body, 0.0, 1.0);
	ALBEDO = (ring_c * lines + ember_c * body) / max(cover, 0.001) * strength;
	ALPHA = cover * fade * step(r, 1.0);
}
