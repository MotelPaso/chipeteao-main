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

group_uniforms Llamas;
// Lenguas por metro a lo largo del anillo y rapidez con que suben.
uniform float tongue_scale = 0.9;
uniform float rise_speed = 3.4;

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
	// Cada lengua llega más alto donde el ruido es mayor.
	float top = 0.3 + 0.65 * n;
	float flame = 1.0 - smoothstep(top - 0.2, top, h);
	ALBEDO = mix(base_color, tip_color, smoothstep(0.0, 0.8, h)) * strength;
	ALPHA = clamp(flame * fade, 0.0, 1.0);
}
