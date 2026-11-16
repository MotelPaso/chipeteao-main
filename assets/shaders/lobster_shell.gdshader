shader_type spatial;

// Caparazón de la Langosta Azul (BlueLobster.tscn). Va sobre mallas
// primitivas de tamaño 1 (esfera, cilindro, cono) que cada nodo estira a su
// medida, y un solo material sirve a todas las piezas: cada una se distingue
// con los uniforms por instancia `tone` y `pale`. Tiene un degradado de lomo
// a vientre, las motas del caparazón, un borde mojado que brilla para que la
// silueta se lea dentro de la horda y un brillo extra mientras carga un
// ataque (`anger`, lo escribe el rig).

group_uniforms Color;
// Azul profundo de las sombras y azul vivo del lomo.
uniform vec3 deep_color : source_color = vec3(0.015, 0.06, 0.32);
uniform vec3 bright_color : source_color = vec3(0.06, 0.34, 0.98);
// Color del vientre y de las articulaciones (las piezas con `pale`).
uniform vec3 pale_color : source_color = vec3(0.56, 0.8, 1.0);
// Hacia dónde va el azul vivo, en el espacio de la malla, y cuánto se difumina.
uniform vec3 gradient_axis = vec3(0.0, 1.0, 0.0);
uniform float gradient_soft : hint_range(0.02, 1.0) = 0.45;
// Brillo propio: lo que se ve aunque la luz del mapa cambie de color.
uniform float glow : hint_range(0.0, 4.0) = 0.55;

group_uniforms Motas;
// Motas por unidad de malla (0 = caparazón liso), cuánto oscurecen y su color.
uniform float speckle_scale = 9.0;
uniform float speckle_amount : hint_range(0.0, 1.0) = 0.38;
uniform vec3 speckle_color : source_color = vec3(0.0, 0.02, 0.16);

group_uniforms Borde;
// Color, fuerza y finura del borde mojado que brilla.
uniform vec3 rim_color : source_color = vec3(0.55, 0.9, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.4;

group_uniforms Furia;
// Color que toma el brillo mientras carga un ataque y cuánto se enciende.
uniform vec3 anger_color : source_color = vec3(0.55, 0.95, 1.0);
uniform float anger_glow : hint_range(0.0, 6.0) = 1.6;

group_uniforms Camara;
// Metros a la cámara por debajo de los cuales la pieza desaparece y por
// encima de los cuales se ve entera. Entre medio se deshace en una trama de
// puntos: así la langosta no tapa la pantalla cuando queda encima del raider.
uniform float fade_near = 2.2;
uniform float fade_far = 5.5;

// -1 a 1: oscurece o aclara esta pieza.
instance uniform float tone = 0.0;
// 0-1: cuánto del color del vientre lleva esta pieza.
instance uniform float pale = 0.0;
// 0-1: cuánto se enciende ahora (lo escribe el rig en todas las piezas).
instance uniform float anger = 0.0;
// 1 = se deshace cerca de la cámara; 0 = se ve entera aunque la cámara se le
// pegue (lo apaga la entrada, que la filma de cerca).
instance uniform float near_fade = 1.0;

varying vec3 local_pos;

// Trama ordenada de 4x4 (Bayer) para deshacer la pieza cerca de la cámara:
// 16 niveles entre 0 y 1 según el píxel. Va como fórmula y no como tabla: una
// tabla constante en un sombreador deja su nombre sin liberar al cerrar.
float bayer2(vec2 cell) {
	cell = floor(cell);
	return fract(cell.x * 0.5 + cell.y * cell.y * 0.75);
}

float bayer4(vec2 pixel) {
	return bayer2(pixel * 0.5) * 0.25 + bayer2(pixel);
}

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Motas redondas: una por celda, con tamaño y lugar al azar.
float speckles(vec3 p) {
	vec3 cell = floor(p);
	vec3 inside = fract(p) - 0.5;
	float size = 0.18 + 0.26 * hash31(cell);
	vec3 offset = vec3(hash31(cell + 7.1), hash31(cell + 13.7), hash31(cell + 29.3)) - 0.5;
	return 1.0 - smoothstep(size * 0.6, size, length(inside - offset * 0.4));
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Cerca de la cámara la pieza se deshace en puntos (VERTEX es la posición
	// del píxel vista desde la cámara).
	float seen = mix(1.0, smoothstep(fade_near, fade_far, length(VERTEX)), near_fade);
	if (seen < 1.0 && seen < bayer4(FRAGCOORD.xy) + 0.03125) {
		discard;
	}

	float side = dot(normalize(gradient_axis), local_pos);
	vec3 color = mix(deep_color, bright_color, smoothstep(-gradient_soft, gradient_soft, side));
	color *= 1.0 + tone * 0.55;
	if (speckle_scale > 0.0) {
		color = mix(color, speckle_color, speckle_amount * speckles(local_pos * speckle_scale)
				* (1.0 - pale));
	}
	color = mix(color, pale_color, pale);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = color * 0.6;
	EMISSION = color * glow + rim_color * rim * rim_strength
			+ anger_color * anger * anger_glow * (0.35 + rim);
	ROUGHNESS = 0.28;
	SPECULAR = 0.6;
}
