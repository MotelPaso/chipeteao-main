shader_type canvas_item;

// Viñeta de peligro de la Langosta Azul (nodo Feel/Vignette de
// BlueLobster.tscn): los bordes de la pantalla se oscurecen y se tiñen de
// azul profundo, con ondas que se cierran hacia el centro, mientras carga un
// golpe grande. El color y cuánto se ve los escribe lobster_feel.gd.

// Color de los bordes.
uniform vec3 tint : source_color = vec3(0.0, 0.08, 0.32);
// 0-1: cuánto se ve ahora.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Distancia al centro (0 = centro, 1 = borde) donde empieza y donde llega a pleno.
uniform float inner : hint_range(0.0, 1.5) = 0.4;
uniform float outer : hint_range(0.0, 2.0) = 1.1;
// Ondas que se cierran: cuántas se ven a la vez, qué tan rápido y cuánto aclaran.
uniform float ripples = 5.0;
uniform float ripple_speed = 1.4;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float reach = length(centered);
	float edge = smoothstep(inner, outer, reach);
	float wave = 0.5 + 0.5 * sin((reach * ripples + TIME * ripple_speed) * 6.28318);
	vec3 color = tint * (1.0 + ripple_strength * wave * 2.0);
	COLOR = vec4(color, edge * amount * (1.0 - ripple_strength * 0.5 * wave));
}
