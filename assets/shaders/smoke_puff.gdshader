shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

// Bocanada de humo oscuro de la estela de una bola de fuego (Fireball.tscn >
// Smoke). Va sobre una esfera que las partículas agrandan: es más densa al
// centro y se deshace hacia el borde. La opacidad de cada bocanada llega con
// el color de su partícula.

group_uniforms Color;
// Color del humo.
uniform vec3 smoke_color : source_color = vec3(0.09, 0.035, 0.03);
// Opacidad en el centro de la bocanada.
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
// Qué tan blando es el borde (más alto = bocanada más chica y concentrada).
uniform float softness : hint_range(0.5, 6.0) = 1.6;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = smoke_color;
	ALPHA = pow(facing, softness) * opacity * COLOR.a;
}
