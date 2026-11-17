shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Un tramo del CHORRO de agua de un golpe de la Langosta Azul
// (WaterBurst.tscn): agua que sube en vetas con espuma arriba. Va sobre un
// cuadro de 1 x 1 que el chorro reparte en círculo y estira; las vetas se
// dibujan con la posición en el mundo, así los tramos vecinos calzan.

group_uniforms Color;
// Espuma de arriba y de las vetas, agua del cuerpo y agua oscura del pie.
uniform vec3 foam_color : source_color = vec3(0.94, 1.0, 1.0);
uniform vec3 water_color : source_color = vec3(0.22, 0.72, 1.0);
uniform vec3 deep_color : source_color = vec3(0.04, 0.3, 0.9);
// Brillo del chorro.
uniform float strength : hint_range(0.0, 4.0) = 1.5;

group_uniforms Chorro;
// Vetas por metro alrededor del chorro y rapidez con que suben.
uniform float streak_scale = 1.6;
uniform float rise_speed = 6.0;
// Parte de arriba del chorro (0-1) que es cresta deshilachada.
uniform float ragged : hint_range(0.0, 0.9) = 0.42;

group_uniforms Camara;
// Metros a la cámara por debajo de los cuales el chorro no se ve y por encima
// de los cuales se ve entero: uno que brota pegado a la cámara no deja la
// pantalla en blanco.
uniform float fade_near = 1.5;
uniform float fade_far = 5.0;

// 0-1: opacidad de todo el chorro (la baja al apagarse).
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
	float around = (world_pos.x + world_pos.z) * streak_scale;
	float coarse = noise2(vec2(around, h * 2.5 - TIME * rise_speed));
	float fine = noise2(vec2(around * 2.7 + 11.0, h * 7.0 - TIME * rise_speed * 1.8));
	// Cada veta llega más alto donde el ruido es mayor.
	float top = 1.0 - ragged * (0.25 + 0.75 * coarse);
	float body = 1.0 - smoothstep(top - 0.16, top, h);
	float streak = smoothstep(0.45, 0.9, fine);
	float foam = clamp(streak * 0.75 + smoothstep(top - 0.3, top - 0.04, h), 0.0, 1.0) * body;
	vec3 color = mix(mix(deep_color, water_color, smoothstep(0.0, 0.5, h)), foam_color, foam);
	ALBEDO = color * strength;
	// Denso al pie, calado arriba. VERTEX es la posición del píxel vista desde
	// la cámara.
	float seen = smoothstep(fade_near, fade_far, length(VERTEX));
	ALPHA = body * (0.3 + 0.7 * foam + 0.3 * (1.0 - h)) * fade * seen;
}
