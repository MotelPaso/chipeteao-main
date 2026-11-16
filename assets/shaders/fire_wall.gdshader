shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Un tramo del anillo de una onda de fuego (FireWave.tscn): lenguas de
// llama que suben desde el suelo. Va sobre un cuadro de 1 x 1 que la onda
// estira; las lenguas se dibujan con la posición en el mundo, así los tramos
// vecinos calzan entre sí.

group_uniforms Color;
// Color en la base y en la punta de las llamas.
uniform vec3 base_color : source_color = vec3(1.0, 0.88, 0.4);
uniform vec3 tip_color : source_color = vec3(1.0, 0.28, 0.03);
// Brillo de las llamas.
uniform float strength : hint_range(0.0, 6.0) = 2.0;

group_uniforms Renacido;
// Base y punta de las llamas en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_base_color : source_color = vec3(0.4, 0.8, 1.0);
uniform vec3 ascended_tip_color : source_color = vec3(0.04, 0.3, 1.0);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;

group_uniforms Llamas;
// Lenguas por metro a lo largo del anillo y rapidez con que suben.
uniform float tongue_scale = 0.9;
uniform float rise_speed = 3.4;
// Cuánto brilla de más el pie de las llamas (0 = parejo).
uniform float base_heat : hint_range(0.0, 3.0) = 0.55;
// Parte del ancho del tramo que se pisa con el vecino a cada lado: ahí se funden (0 = sin fundido).
uniform float seam : hint_range(0.0, 0.5) = 0.0;

group_uniforms Chispas;
// Cuántas chispas suben sobre las llamas (0 = ninguna), su tamaño y su rapidez.
uniform float spark_density : hint_range(0.0, 1.0) = 0.4;
uniform float spark_size : hint_range(0.02, 0.4) = 0.14;
uniform float spark_speed = 2.4;

// 0-1: opacidad de toda la onda (la baja al apagarse).
instance uniform float fade = 1.0;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 0 en el suelo, 1 en lo alto del tramo.
	float h = 1.0 - UV.y;
	float along = (world_pos.x + world_pos.z) * tongue_scale;
	float n = noise2(vec2(along, h * 2.5 - TIME * rise_speed));
	// Una segunda capa, más fina y más rápida, le da detalle a las lenguas.
	float fine = noise2(vec2(along * 2.7 + 11.0, h * 6.0 - TIME * rise_speed * 1.8));
	// Cada lengua llega más alto donde el ruido es mayor.
	float top = 0.2 + 0.5 * n + 0.22 * fine;
	float flame = 1.0 - smoothstep(top - 0.22, top, h);
	vec3 base = mix(base_color, ascended_base_color, fire_ascend);
	vec3 tip = mix(tip_color, ascended_tip_color, fire_ascend);
	vec3 color = mix(base, tip, smoothstep(0.0, 0.85, h / max(top, 0.05)));
	// El pie de las llamas es lo más caliente.
	color += base * base_heat * (1.0 - smoothstep(0.0, 0.3 + 0.2 * n, h));
	// Chispas: celdas que suben; unas pocas llevan un punto brillante, que
	// aparece cerca de las puntas de las llamas y se apaga antes del borde.
	vec2 grid = vec2(along * 3.0, h * 9.0 - TIME * spark_speed);
	vec2 cell = floor(grid);
	vec2 spot = fract(grid) - 0.5 + (vec2(hash21(cell + 7.0), hash21(cell + 13.0)) - 0.5) * 0.5;
	float spark = step(1.0 - spark_density * 0.2, hash21(cell))
			* (1.0 - smoothstep(0.0, spark_size, length(spot)));
	spark *= smoothstep(top * 0.55, top, h) * (1.0 - smoothstep(0.8, 1.0, h));
	// Donde dos tramos vecinos se pisan, uno se va mientras el otro entra.
	float edge = seam > 0.0 ? smoothstep(0.0, seam, UV.x) * smoothstep(0.0, seam, 1.0 - UV.x) : 1.0;
	float cover = max(flame, spark);
	ALBEDO = (color * flame + base * spark * 1.6) / max(cover, 0.001) * strength;
	ALPHA = clamp(cover * fade * edge, 0.0, 1.0);
}
