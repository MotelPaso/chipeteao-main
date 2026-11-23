shader_type canvas_item;

// El AGUA que inunda la pantalla en el rapto de la Langosta Azul (nodo Flood
// del Overlay de LobsterEntrance.tscn): sube desde abajo con el borde
// ondulado y espuma, con burbujas que suben y franjas de luz. Con level en 1
// tapa la pantalla entera; con dissolve se va en burbujas y deja ver el
// fondo del mar.

// Cuánto subió el agua: 0 = nada, 1 = tapa toda la pantalla.
uniform float level : hint_range(0.0, 1.0) = 0.0;
// Cuánto se fue ya en burbujas: 0 = agua entera, 1 = no queda nada.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

group_uniforms Color;
// Agua del fondo, agua junto a la superficie y espuma.
uniform vec3 deep_color : source_color = vec3(0.02, 0.1, 0.3);
uniform vec3 shallow_color : source_color = vec3(0.1, 0.46, 0.84);
uniform vec3 foam_color : source_color = vec3(0.88, 0.98, 1.0);

group_uniforms Agua;
// Alto de las olas del borde, en fracción de la pantalla, y su rapidez.
uniform float wave_height : hint_range(0.0, 0.2) = 0.035;
uniform float wave_speed = 2.4;
// Grosor de la espuma del borde, en fracción de la pantalla.
uniform float foam_width : hint_range(0.0, 0.2) = 0.03;
// Burbujas por ancho de pantalla y rapidez con que suben (pantallas por segundo).
uniform float bubble_scale = 22.0;
uniform float bubble_speed = 0.45;

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

// 1 en el borde de una burbuja, 0 fuera. Una burbuja por celda, no todas.
float bubbles(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p) - 0.5;
	float pick = hash21(cell);
	vec2 offset = (vec2(hash21(cell + 3.1), hash21(cell + 7.7)) - 0.5) * 0.5;
	float radius = mix(0.1, 0.3, hash21(cell + 11.3));
	float ring = abs(length(local - offset) - radius);
	return step(0.55, pick) * (1.0 - smoothstep(0.0, 0.06, ring));
}

void fragment() {
	// 0 en el borde de abajo de la pantalla, 1 en el de arriba.
	float up = 1.0 - UV.y;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float wave = sin(UV.x * 9.0 + TIME * wave_speed) * 0.5
			+ sin(UV.x * 23.0 - TIME * wave_speed * 1.7) * 0.3
			+ (noise2(vec2(UV.x * 6.0, TIME * 1.3)) - 0.5) * 0.8;
	// Con level en 1 el borde queda por encima de la pantalla, olas incluidas.
	float line = level * (1.0 + wave_height * 4.0) - wave_height * 2.0 + wave * wave_height;
	float under = smoothstep(line + 0.003, line - 0.003, up);
	float depth = clamp((line - up) / 0.7, 0.0, 1.0);
	vec3 water = mix(shallow_color, deep_color, depth);
	// Franjas de luz que bajan desde la superficie.
	float shaft = noise2(vec2(UV.x * 7.0 * aspect + TIME * 0.4, up * 1.5 - TIME * 0.25));
	water += shallow_color * 0.35 * smoothstep(0.55, 0.95, shaft) * (1.0 - depth);
	vec2 grid = vec2(UV.x * aspect, up - TIME * bubble_speed) * bubble_scale;
	float bubble = max(bubbles(grid), bubbles(grid * 0.47 + 13.0));
	water = mix(water, foam_color, bubble * 0.7);
	float foam = (1.0 - smoothstep(0.0, foam_width, line - up)) * under;
	water = mix(water, foam_color, foam * 0.85);
	// Se va en burbujas: el agua se aclara entera y cada burbuja aguanta un poco más.
	float grain = noise2(vec2(UV.x * aspect, up - TIME * bubble_speed) * 46.0);
	float gone = smoothstep(0.0, 1.0, dissolve * 1.5 - grain * 0.3 - bubble * 0.25);
	COLOR = vec4(water, under * (1.0 - gone));
}
