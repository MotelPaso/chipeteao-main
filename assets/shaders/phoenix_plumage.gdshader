shader_type spatial;
render_mode cull_disabled;

// Plumas del fénix (Mythos). Va sobre una CINTA de largo 1 (RibbonTrailMesh),
// con la raíz en UV.y = 0 y la punta en UV.y = 1. El color pasa de la raíz a
// la punta, la punta brilla y se mece como una llama, y un raquis y unas
// barbas dibujadas le dan textura de pluma.
// Todas las plumas de un tipo comparten UN material; lo que cambia de pluma
// en pluma viaja por instancia (lo fija cada nodo de la escena, en
// «Instance Shader Parameters»): su curvatura, su desfase y su calor.

group_uniforms Color;
// Color en la raíz, en el medio y en la punta de la pluma.
uniform vec3 root_color : source_color = vec3(0.3, 0.015, 0.03);
uniform vec3 mid_color : source_color = vec3(0.95, 0.2, 0.03);
uniform vec3 tip_color : source_color = vec3(1.0, 0.82, 0.28);
// Dónde cae el color del medio a lo largo de la pluma (0 = raíz, 1 = punta).
uniform float mid_point : hint_range(0.1, 0.9) = 0.45;
// Brillo propio de toda la pluma y brillo extra de la punta.
uniform float glow : hint_range(0.0, 4.0) = 0.75;
uniform float tip_glow : hint_range(0.0, 8.0) = 2.0;
// Cuánto oscurecen las barbas y el borde (0 = pluma lisa).
uniform float vane_contrast : hint_range(0.0, 1.0) = 0.4;
// Cantidad de barbas a lo largo de la pluma.
uniform float barb_count = 18.0;

group_uniforms Ojo;
// El «ojo» de las plumas largas de la cola (0 = sin ojo).
uniform float eye_amount : hint_range(0.0, 1.0) = 0.0;
// Dónde va el ojo a lo largo de la pluma y su tamaño (fracciones del largo).
uniform float eye_center : hint_range(0.0, 1.0) = 0.84;
uniform float eye_size : hint_range(0.01, 0.5) = 0.11;
// Cuánto se angosta el centro del ojo (1 = redondo; más alto = una pupila rasgada).
uniform float eye_slit : hint_range(1.0, 8.0) = 1.0;
// Centro del ojo y anillo que lo rodea.
uniform vec3 eye_core_color : source_color = vec3(1.0, 0.97, 0.8);
uniform vec3 eye_ring_color : source_color = vec3(0.05, 0.7, 0.8);

group_uniforms Renacido;
// Colores de la pluma en la forma renacida de Mythos (segunda fase): raíz,
// medio, punta y anillo del ojo. El rig mezcla hacia ellos con `ascend`.
uniform vec3 ascended_root_color : source_color = vec3(0.006, 0.008, 0.05);
uniform vec3 ascended_mid_color : source_color = vec3(0.015, 0.08, 0.45);
uniform vec3 ascended_tip_color : source_color = vec3(0.45, 0.85, 1.0);
// Cuánto baja el brillo en la forma renacida (el azul claro se quema a blanco antes que el rojo).
uniform float ascended_glow : hint_range(0.0, 1.0) = 0.62;
uniform vec3 ascended_eye_ring_color : source_color = vec3(0.0, 0.01, 0.05);

group_uniforms Movimiento;
// Metros que se mece la punta y con qué rapidez.
uniform float sway_amount = 0.1;
uniform float sway_speed = 2.6;
// Temblor rápido de llama en la punta, en metros, y su rapidez.
uniform float flutter_amount = 0.03;
uniform float flutter_speed = 11.0;

group_uniforms Camara;
// Metros a la cámara por debajo de los cuales la pieza desaparece y por
// encima de los cuales se ve entera. Entre medio se deshace en una trama de
// puntos: así el fénix no tapa la pantalla cuando queda encima del raider.
uniform float fade_near = 3.0;
uniform float fade_far = 7.5;

// Metros que la punta se curva hacia la cara de la pluma (negativo = hacia el otro lado).
instance uniform float bend = 0.0;
// Desfase del movimiento, para que las plumas no se mezan todas juntas.
instance uniform float phase = 0.0;
// 0-1: corre el color de esta pluma hacia el de la punta.
instance uniform float heat = 0.0;
// 0-1: cuánto tomó la forma renacida (lo escribe el rig en cada pieza).
instance uniform float ascend = 0.0;

varying float along;

// Trama ordenada de 4x4 para deshacer la pieza cerca de la cámara.
const float DITHER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	// La cinta nace en +Y (raíz) y termina en -Y (punta); su cara mira a Z.
	along = UV.y;
	float reach = along * along;
	float wave = sin(TIME * sway_speed + phase + along * 2.4);
	float flick = sin(TIME * flutter_speed + phase * 3.7 + along * 9.0);
	VERTEX.z += (bend + wave * sway_amount + flick * flutter_amount) * reach;
	VERTEX.x += sin(TIME * sway_speed * 0.63 + phase * 1.9 + along * 3.1)
			* sway_amount * 0.4 * reach;
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
	float t = clamp(along + heat * 0.35, 0.0, 1.0);
	vec3 root = mix(root_color, ascended_root_color, ascend);
	vec3 mid = mix(mid_color, ascended_mid_color, ascend);
	vec3 tip = mix(tip_color, ascended_tip_color, ascend);
	vec3 color = mix(root, mid, smoothstep(0.0, mid_point, t));
	color = mix(color, tip, smoothstep(mid_point, 1.0, t));
	// A lo ancho: 0 en el raquis, 1 en el borde de la pluma.
	float across = abs(UV.x - 0.5) * 2.0;
	// Barbas en espiga, apuntando a la punta, y borde más oscuro.
	float barbs = 0.5 + 0.5 * sin((along * barb_count + across * 1.6) * TAU);
	float shade = mix(1.0, 0.62 + 0.38 * barbs, vane_contrast);
	shade *= 1.0 - 0.45 * vane_contrast * smoothstep(0.7, 1.0, across);
	color *= shade;
	// Raquis: una línea clara al centro, más fina hacia la punta.
	float shaft = 1.0 - smoothstep(0.0, 0.07 + 0.05 * (1.0 - along), across);
	color = mix(color, tip, shaft * 0.45);
	float shine = (glow + tip_glow * t * t) * mix(1.0, ascended_glow, ascend);
	if (eye_amount > 0.0) {
		float lengthwise = (along - eye_center) / eye_size;
		float r = length(vec2(across, lengthwise));
		// La pupila rasgada es más angosta y un poco más alta que el ojo redondo.
		float core = 1.0 - smoothstep(0.28, 0.42,
				length(vec2(across * eye_slit, lengthwise / pow(eye_slit, 0.25))));
		float ring = smoothstep(0.42, 0.55, r) * (1.0 - smoothstep(0.7, 0.85, r));
		color = mix(color, mix(eye_ring_color, ascended_eye_ring_color, ascend),
				ring * eye_amount);
		color = mix(color, eye_core_color, core * eye_amount);
		shine += 0.9 * core * eye_amount;
	}
	ALBEDO = color * 0.5;
	EMISSION = color * shine;
	ROUGHNESS = 0.9;
	// La cinta tiene una sola cara: por detrás la normal apunta al revés.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
