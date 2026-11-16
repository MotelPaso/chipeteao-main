shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Un tramo del anillo de una onda de choque (ShockRing.tscn): una cresta de
// agua y tierra levantada que corre a ras de suelo. Va sobre un cuadro de
// 1 x 1 que la onda estira; la cresta se dibuja con la posición en el mundo,
// así los tramos vecinos calzan entre sí.

group_uniforms Color;
// Color de la espuma de arriba y del cuerpo de la onda.
uniform vec3 crest_color : source_color = vec3(0.92, 0.98, 1.0);
uniform vec3 body_color : source_color = vec3(0.16, 0.62, 1.0);
// Brillo de la onda.
uniform float strength : hint_range(0.0, 4.0) = 1.5;

group_uniforms Cresta;
// Picos por metro a lo largo del anillo y rapidez con que suben.
uniform float streak_scale = 1.3;
uniform float rise_speed = 2.6;

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
	float along = (world_pos.x + world_pos.z) * streak_scale;
	float n = noise2(vec2(along, h * 2.0 - TIME * rise_speed));
	// Cada columna de la cresta llega más alto donde el ruido es mayor.
	float top = 0.35 + 0.6 * n;
	float body = 1.0 - smoothstep(top - 0.25, top, h);
	float foam = smoothstep(top - 0.24, top - 0.05, h) * body;
	ALBEDO = mix(body_color, crest_color, foam) * strength;
	ALPHA = body * (0.3 + 0.7 * foam + 0.25 * (1.0 - h)) * fade;
}
