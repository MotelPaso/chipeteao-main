shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Los RAYOS DE LUZ que bajan de la superficie del mar en el Cementerio de
// barcos (LightShafts). Cada rayo son dos cuadros cruzados: UV.x cruza el
// ancho (0-1), UV.y sube de la arena (0) a la cima (1) y COLOR.r es la fase al
// azar de cada rayo. Solo suma luz, y se apaga cerca de la cámara.

// Color de la luz.
uniform vec4 tint : source_color = vec4(0.75, 0.92, 1.0, 1.0);
// Brillo general: tiene que ser sutil.
uniform float intensity : hint_range(0.0, 1.0) = 0.16;
// Velocidad con que las franjas corren a lo largo del rayo (vueltas por segundo).
uniform float shimmer_speed : hint_range(0.0, 2.0) = 0.12;
// Franjas a lo largo del rayo.
uniform float shimmer_bands : hint_range(0.5, 12.0) = 4.0;
// Cuánto oscurecen las franjas (0 = rayo parejo, 1 = franjas marcadas).
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.45;
// Parte del alto (0-1) que se desvanece abajo, junto a la arena.
uniform float bottom_fade : hint_range(0.01, 1.0) = 0.3;
// Parte del alto (0-1) que se desvanece arriba.
uniform float top_fade : hint_range(0.01, 1.0) = 0.35;
// Metros a la cámara por debajo de los cuales el rayo se apaga.
uniform float near_fade : hint_range(0.0, 40.0) = 9.0;

varying float phase;

void vertex() {
	phase = COLOR.r;
}

void fragment() {
	// sin(pi x)^2 da un borde suave que llega a 0 justo en UV.x = 0 y 1.
	float across = sin(UV.x * PI);
	across *= across;
	float along = smoothstep(0.0, bottom_fade, UV.y) * (1.0 - smoothstep(1.0 - top_fade, 1.0, UV.y));
	float t = TIME * shimmer_speed + phase * 7.0;
	// Dos ondas de distinta frecuencia que corren hacia abajo: franjas que no se repiten parejo.
	float wave = sin((UV.y * shimmer_bands + t) * TAU) * 0.6
			+ sin((UV.y * shimmer_bands * 0.43 + t * 0.71 + phase * 3.0) * TAU) * 0.4;
	float shimmer = 1.0 - shimmer_strength * (0.5 + 0.5 * wave);
	// VERTEX es la posición en el espacio de la vista: -z es la profundidad.
	float depth = -VERTEX.z;
	float near = smoothstep(near_fade * 0.4, near_fade, depth);
	ALBEDO = tint.rgb * intensity;
	ALPHA = clamp(across * along * shimmer * near, 0.0, 1.0);
}
