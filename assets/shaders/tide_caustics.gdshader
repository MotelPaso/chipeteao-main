shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Reflejos de agua sobre el suelo mientras dura la marea de la Langosta Azul
// (LobsterTide.tscn, nodo Caustics). Va sobre una copia de la malla del
// terreno, apenas levantada, y solo SUMA luz: filamentos azules que se
// mueven como la luz en el fondo del mar. `amount` lo escribe
// lobster_tide.gd (0 = nada, 1 = marea alta).

group_uniforms Marea;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms Reflejos;
// Color y fuerza de los reflejos.
uniform vec3 tint : source_color = vec3(0.25, 0.7, 1.0);
uniform float strength : hint_range(0.0, 3.0) = 0.42;
// Tamaño del dibujo (más = filamentos más chicos), velocidad y finura.
uniform float scale = 0.5;
uniform float speed = 0.5;
uniform float sharpness : hint_range(1.0, 16.0) = 5.0;
// Metros a la cámara a partir de los que se desvanecen.
uniform float fade_far = 70.0;
// Metros que la copia va por encima del suelo, para que no parpadee contra él.
uniform float lift = 0.04;

varying vec3 world_pos;

// Ondas que se cruzan: los filamentos brillan donde la suma pasa por cero.
float ripples(vec2 p, float t) {
	float v = sin(p.x * 1.3 + sin(p.y * 0.9 + t) * 1.7 + t * 0.7);
	v += sin(p.y * 1.1 + sin(p.x * 1.4 - t * 0.8) * 1.5 - t * 0.5);
	v += sin((p.x + p.y) * 0.8 + sin((p.x - p.y) * 1.2 + t * 0.6) * 1.3);
	return v / 3.0;
}

void vertex() {
	VERTEX += NORMAL * lift;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * speed;
	vec2 p = world_pos.xz * scale;
	float lines = pow(1.0 - abs(ripples(p, t)), sharpness);
	lines += 0.6 * pow(1.0 - abs(ripples(p * 1.9 + 7.3, t * 1.3)), sharpness);
	float fade = 1.0 - smoothstep(fade_far * 0.5, fade_far, length(VERTEX));
	ALBEDO = tint * lines * strength * amount * fade;
}
