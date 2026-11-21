shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;

// El sol del Amanecer de Mythos: una bola de luz que crece alrededor del
// fénix mientras carga su golpe más fuerte. Va sobre una esfera de radio 1
// que el rig (MythosRig) estira; brilla más en el centro y se deshace hacia
// el borde. Cuánto está cargado viaja por instancia.

group_uniforms Color;
// Color del centro y del borde de la bola.
uniform vec3 core_color : source_color = vec3(1.0, 0.86, 0.5);
uniform vec3 edge_color : source_color = vec3(1.0, 0.32, 0.05);
// Brillo con la carga completa.
uniform float strength : hint_range(0.0, 4.0) = 1.1;
// Qué tan blando es el borde (más alto = bola más chica y concentrada).
uniform float softness : hint_range(0.5, 6.0) = 2.4;
// Parpadeos por segundo y cuánto baja el brillo en cada uno.
uniform float flicker_speed = 9.0;
uniform float flicker_depth : hint_range(0.0, 1.0) = 0.15;

group_uniforms Renacido;
// Centro y borde de la bola en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_core_color : source_color = vec3(0.75, 0.96, 1.0);
uniform vec3 ascended_edge_color : source_color = vec3(0.05, 0.35, 1.0);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

// 0-1: avance de la carga (lo escribe el rig).
instance uniform float charge = 0.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = pow(facing, softness);
	float flicker = 1.0 - flicker_depth * (0.5 + 0.5 * sin(TIME * flicker_speed * TAU));
	vec3 edge = mix(edge_color, ascended_edge_color, fire_ascend);
	vec3 core = mix(core_color, ascended_core_color, fire_ascend);
	ALBEDO = mix(edge, core, glow) * strength * (0.35 + 0.65 * charge) * flicker;
	ALPHA = glow;
}
