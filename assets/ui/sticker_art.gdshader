shader_type canvas_item;
// Dibujo tipo sticker de las tarjetas del menú: le suma a cualquier textura
// con transparencia un contorno de tinta y una sombra dura (sin difuminar).
// La imagen se dibuja un poco más chica que su rectángulo (padding) para que
// el contorno y la sombra tengan dónde caer sin cortarse.

// Color de la tinta: contorno y sombra.
uniform vec4 ink_color : source_color = vec4(0.082, 0.075, 0.102, 1.0);
// Grosor del contorno, en píxeles de pantalla (0 = sin contorno).
uniform float outline_px = 4.0;
// Desplazamiento de la sombra dura, en píxeles de pantalla.
uniform vec2 shadow_px = vec2(0.0, 6.0);
// Aire alrededor de la imagen, como fracción de su rectángulo.
uniform float padding : hint_range(0.0, 0.3) = 0.08;

const int DIRECTIONS = 12;

// 1 dentro de la imagen, 0 fuera. Sin "if": leer la textura dentro de una
// rama rompe la elección de mipmap y deja líneas finas en el borde.
float inside(vec2 uv) {
	vec2 edge = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return edge.x * edge.y;
}

void fragment() {
	float zoom = 1.0 + padding * 2.0;
	vec2 uv = (UV - 0.5) * zoom + 0.5;
	// Cuánto UV ocupa un píxel de pantalla: así los grosores no dependen del
	// tamaño al que se dibuje la imagen.
	vec2 uv_per_px = vec2(length(dFdx(UV)), length(dFdy(UV))) * zoom;
	vec2 radius = uv_per_px * outline_px;
	vec4 art = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))) * inside(uv);
	// Silueta engordada: el máximo de la transparencia en un anillo de
	// muestras alrededor del punto. Una vez para el contorno y otra, corrida,
	// para la sombra. (TEXTURE solo se puede leer aquí, no en una función.)
	vec2 shadow_uv = uv - shadow_px * uv_per_px;
	float outline = art.a;
	float shadow = texture(TEXTURE, clamp(shadow_uv, vec2(0.0), vec2(1.0))).a
			* inside(shadow_uv);
	for (int i = 0; i < DIRECTIONS; i++) {
		float angle = TAU * float(i) / float(DIRECTIONS);
		vec2 step_uv = vec2(cos(angle), sin(angle)) * radius;
		vec2 near = uv + step_uv;
		vec2 far = shadow_uv + step_uv;
		outline = max(outline, texture(TEXTURE, clamp(near, vec2(0.0), vec2(1.0))).a
				* inside(near));
		shadow = max(shadow, texture(TEXTURE, clamp(far, vec2(0.0), vec2(1.0))).a
				* inside(far));
	}
	float ink = max(outline, shadow);
	vec3 rgb = mix(ink_color.rgb, art.rgb, art.a);
	// Se escribe el color completo: COLOR ya trae la textura multiplicada, y
	// usarlo otra vez oscurecería los colores del dibujo.
	COLOR = vec4(rgb, max(ink, art.a));
}
