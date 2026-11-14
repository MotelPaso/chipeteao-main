shader_type spatial;

// Cuerpo del fénix (Mythos): las piezas macizas (pecho, vientre, cuello,
// cabeza, brazos de las alas, muslos, corazón). Va sobre mallas primitivas de
// tamaño 1 (esfera, cono, cilindro, caja) que cada nodo estira a su medida.
// Tiene un degradado a lo largo de un eje de la malla (lomo oscuro, vientre
// encendido), escamas de plumas dibujadas, un borde que brilla para que la
// silueta se lea contra el cielo del infierno, y un latido opcional.

group_uniforms Color;
// Color del lado oscuro y del lado encendido.
uniform vec3 dark_color : source_color = vec3(0.42, 0.03, 0.03);
uniform vec3 hot_color : source_color = vec3(1.0, 0.5, 0.08);
// Hacia dónde va el color encendido, en el espacio de la malla.
uniform vec3 gradient_axis = vec3(0.0, -1.0, 0.0);
// Corre el degradado a lo largo de ese eje (-0.5 a 0.5) y cuánto se difumina.
uniform float gradient_center : hint_range(-0.5, 0.5) = 0.0;
uniform float gradient_soft : hint_range(0.02, 1.0) = 0.4;
// Brillo propio.
uniform float glow : hint_range(0.0, 4.0) = 0.6;

group_uniforms Renacido;
// Colores de la pieza en la forma renacida de Mythos (segunda fase): lado
// oscuro, lado encendido y borde. El rig mezcla hacia ellos con `ascend`.
uniform vec3 ascended_dark_color : source_color = vec3(0.05, 0.07, 0.3);
uniform vec3 ascended_hot_color : source_color = vec3(0.55, 0.88, 1.0);
uniform vec3 ascended_rim_color : source_color = vec3(0.75, 0.96, 1.0);

group_uniforms Borde;
// Color, fuerza y finura del borde que brilla.
uniform vec3 rim_color : source_color = vec3(1.0, 0.72, 0.25);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.1;
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;

group_uniforms Escamas;
// Filas de escamas de pluma (0 = superficie lisa) y cuánto oscurecen.
uniform float scale_rows = 0.0;
uniform float scale_contrast : hint_range(0.0, 1.0) = 0.35;

group_uniforms Latido;
// Cuánto sube y baja el brillo (0 = sin latido) y cuántos latidos por segundo.
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 1.2;

group_uniforms Camara;
// Metros a la cámara por debajo de los cuales la pieza desaparece y por
// encima de los cuales se ve entera. Entre medio se deshace en una trama de
// puntos: así el fénix no tapa la pantalla cuando queda encima del raider.
uniform float fade_near = 3.0;
uniform float fade_far = 7.5;

// 0-1: cuánto tomó la forma renacida (lo escribe el rig en cada pieza).
instance uniform float ascend = 0.0;

varying vec3 local_pos;

// Trama ordenada de 4x4 para deshacer la pieza cerca de la cámara.
const float DITHER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Cerca de la cámara la pieza se deshace en puntos (VERTEX es la posición
	// del píxel vista desde la cámara).
	float seen = smoothstep(fade_near, fade_far, length(VERTEX));
	if (seen < 1.0) {
		int cell = int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4;
		if (seen < (DITHER[cell] + 0.5) / 16.0) {
			discard;
		}
	}
	float side = dot(normalize(gradient_axis), local_pos) - gradient_center;
	vec3 color = mix(mix(dark_color, ascended_dark_color, ascend),
			mix(hot_color, ascended_hot_color, ascend),
			smoothstep(-gradient_soft, gradient_soft, side));
	if (scale_rows > 0.0) {
		// Filas alternadas de medios discos: cada escama oscurece en su borde.
		vec2 grid = vec2(UV.x * scale_rows * 2.0, UV.y * scale_rows);
		grid.x += 0.5 * mod(floor(grid.y), 2.0);
		vec2 cell = fract(grid);
		float edge = smoothstep(0.34, 0.5, length(vec2(cell.x - 0.5, cell.y * 0.92)));
		color *= 1.0 - scale_contrast * edge;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float beat = 1.0 + pulse_amount * sin(TIME * pulse_speed * TAU);
	ALBEDO = color * 0.55;
	EMISSION = (color * glow + mix(rim_color, ascended_rim_color, ascend) * rim * rim_strength)
			* beat;
	ROUGHNESS = 0.85;
}
