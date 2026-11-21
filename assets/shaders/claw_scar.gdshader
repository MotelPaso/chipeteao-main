shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Marca de un zarpazo de Mythos en el suelo (ClawScar.tscn): tres tajos al
// rojo vivo, uno al lado del otro, que se enfrían y se apagan. Va sobre un
// plano de lado 1 que la escena estira; los tajos corren a lo largo de UV.y.
// claw_scar.gd le escribe `life`.

group_uniforms Color;
// Del centro al borde de cada tajo: el corazón casi blanco, el fuego y el borde que se enfría.
uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 fire_color : source_color = vec3(1.0, 0.42, 0.05);
uniform vec3 edge_color : source_color = vec3(0.6, 0.06, 0.0);
// Brillo de la marca recién hecha.
uniform float strength : hint_range(0.0, 8.0) = 3.0;

group_uniforms Renacido;
// Los mismos tres colores en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_core_color : source_color = vec3(0.85, 0.97, 1.0);
uniform vec3 ascended_fire_color : source_color = vec3(0.2, 0.62, 1.0);
uniform vec3 ascended_edge_color : source_color = vec3(0.02, 0.12, 0.8);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Forma;
// Separación entre un tajo y el siguiente y ancho de cada uno (fracciones del plano).
uniform float spacing : hint_range(0.05, 0.45) = 0.24;
uniform float gash_width : hint_range(0.01, 0.2) = 0.07;
// Cuánto se curvan los tajos hacia un lado.
uniform float curve : hint_range(-0.4, 0.4) = 0.12;
// Cuánto se desparejan sus bordes.
uniform float ragged : hint_range(0.0, 1.0) = 0.5;

// 0-1: cuánto lleva la marca (0 = recién hecha, 1 = ya se apagó).
instance uniform float life = 0.0;

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
	// A lo largo del tajo (-1 a 1) y a lo ancho del plano (-0.5 a 0.5).
	float along = UV.y * 2.0 - 1.0;
	float across = UV.x - 0.5 - curve * (1.0 - along * along);
	// Cada tajo es más ancho al medio y termina en punta; el del centro es el más largo.
	float heat = 0.0;
	for (int i = -1; i <= 1; i++) {
		float reach = 1.0 - 0.18 * abs(float(i));
		float taper = max(1.0 - (along * along) / (reach * reach), 0.0);
		float edge = gash_width * taper
				* (1.0 - ragged * 0.6 * noise2(vec2(float(i) * 7.3, along * 9.0)));
		float distance_to = abs(across - float(i) * spacing);
		heat = max(heat, 1.0 - smoothstep(edge * 0.25, edge, distance_to));
	}
	// Se enfría: primero se va el blanco, después el fuego y al final el rojo.
	float cool = heat * (1.0 - life * 0.85);
	vec3 core = mix(core_color, ascended_core_color, fire_ascend);
	vec3 fire = mix(fire_color, ascended_fire_color, fire_ascend);
	vec3 edge = mix(edge_color, ascended_edge_color, fire_ascend);
	vec3 color = mix(edge, fire, smoothstep(0.15, 0.5, cool));
	color = mix(color, core, smoothstep(0.6, 0.95, cool));
	ALBEDO = color * strength * (1.0 - life * 0.6);
	ALPHA = heat * (1.0 - smoothstep(0.55, 1.0, life));
}
