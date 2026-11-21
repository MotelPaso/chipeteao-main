shader_type spatial;
render_mode unshaded, shadows_disabled;

// Una chispa, una brasa o una pluma del fuego de Mythos: un color plano que
// pasa al de su segunda fase junto con todo su fuego (FireTint escribe el
// uniform global fire_ascend).

group_uniforms Color;
// Color en la primera fase.
uniform vec3 color : source_color = vec3(1.0, 0.6, 0.15);
// Brillo.
uniform float glow : hint_range(0.0, 6.0) = 1.0;

group_uniforms Renacido;
// El mismo color en la segunda fase (el fuego azul).
uniform vec3 ascended_color : source_color = vec3(0.3, 0.75, 1.0);

// 0-1: cuánto del fuego de la segunda fase.
global uniform float fire_ascend;

void fragment() {
	ALBEDO = mix(color, ascended_color, fire_ascend) * glow;
}
