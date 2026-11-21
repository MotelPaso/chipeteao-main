shader_type canvas_item;

// Viñeta de peligro de Mythos (nodo Feel/Vignette de Mythos.tscn): tiñe y
// oscurece los bordes de la pantalla mientras carga un ataque grande. El
// color y cuánto se ve los escribe mythos_feel.gd.

// Color de los bordes.
uniform vec3 tint : source_color = vec3(0.55, 0.04, 0.0);
// 0-1: cuánto se ve ahora.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Distancia al centro (0 = centro, 1 = borde) donde empieza y donde llega a pleno.
uniform float inner : hint_range(0.0, 1.5) = 0.42;
uniform float outer : hint_range(0.0, 2.0) = 1.12;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float edge = smoothstep(inner, outer, length(centered));
	COLOR = vec4(tint, edge * amount);
}
