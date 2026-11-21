shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// El anillo de choque de un estallido (FireBlast.tscn > Ring) y la quemadura
// que deja (Scorch): van sobre un plano de 2 x 2 a ras de suelo.
// fire_blast.gd escribe `reach` (hasta dónde llegó el anillo, 0-1) y `fade`.

group_uniforms Color;
// Color del frente del anillo y de la estela que deja detrás.
uniform vec3 front_color : source_color = vec3(1.0, 0.9, 0.6);
uniform vec3 wake_color : source_color = vec3(1.0, 0.35, 0.04);
// Brillo del anillo.
uniform float strength : hint_range(0.0, 8.0) = 2.6;

group_uniforms Renacido;
// Los mismos colores en la segunda fase del jefe.
uniform vec3 ascended_front_color : source_color = vec3(0.8, 0.95, 1.0);
uniform vec3 ascended_wake_color : source_color = vec3(0.1, 0.45, 1.0);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Forma;
// Ancho del frente y largo de su estela, en fracciones del radio.
uniform float front_width : hint_range(0.005, 0.2) = 0.035;
uniform float wake_length : hint_range(0.0, 1.0) = 0.3;
// Grietas encendidas que quedan en el suelo dentro del anillo (0 = ninguna).
uniform float cracks : hint_range(0.0, 1.0) = 0.6;
// Cuánto se ve el frente (0 = solo quedan las grietas: así lo usa la quemadura).
uniform float front_gain : hint_range(0.0, 1.0) = 1.0;

// 0-1: hasta dónde llegó el anillo. Y cuánto se ve todo (1 = entero).
instance uniform float reach = 0.0;
instance uniform float fade = 1.0;

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
	float angle = atan(p.y, p.x);
	// El frente: una línea fina y brillante, algo dentada.
	float wobble = (noise2(vec2(angle * 5.0, TIME * 3.0)) - 0.5) * front_width;
	float front = (1.0 - smoothstep(0.0, front_width, abs(r - reach + wobble))) * front_gain;
	// La estela: se apaga hacia adentro.
	float wake = smoothstep(reach - wake_length, reach, r) * step(r, reach) * 0.55 * front_gain;
	// Grietas: líneas de brasa que salen del centro y se enfrían con `fade`.
	float veins = noise2(vec2(angle * 3.0 + noise2(p * 4.0) * 2.0, r * 2.0));
	float crack = (1.0 - smoothstep(0.0, 0.07, abs(veins - 0.5))) * step(r, reach)
			* (1.0 - smoothstep(0.55, 1.0, r)) * cracks;
	vec3 front_c = mix(front_color, ascended_front_color, fire_ascend);
	vec3 wake_c = mix(wake_color, ascended_wake_color, fire_ascend);
	float cover = clamp(front + wake + crack, 0.0, 1.0);
	ALBEDO = (front_c * front + wake_c * (wake + crack)) / max(cover, 0.001) * strength;
	ALPHA = cover * fade * step(r, 1.0);
}
