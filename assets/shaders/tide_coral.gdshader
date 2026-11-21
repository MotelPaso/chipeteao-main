shader_type spatial;

// Corales de la marea de la Langosta Azul (LobsterTide.tscn, nodos Branches
// y Bulbs). Son dos MultiMesh: ramas (un cilindro de tamaño 1 por rama) y
// bulbos (una esfera en la punta de cada una), con el azul del caparazón de
// la langosta y brillo propio. Brotan del suelo cuando sube la marea y se
// encogen cuando baja: `rise` lo escribe lobster_tide.gd.
// Cada instancia trae en INSTANCE_CUSTOM: x = cuánto tarda en brotar (0-1),
// y = 1 si es un bulbo, z = un número al azar para que no latan todas juntas.

group_uniforms Marea;
// 0 = bajo tierra, 1 = brotado del todo.
uniform float rise : hint_range(0.0, 1.0) = 0.0;

group_uniforms Color;
// Azul del pie, azul vivo del tallo y color de la punta.
uniform vec3 deep_color : source_color = vec3(0.015, 0.07, 0.34);
uniform vec3 bright_color : source_color = vec3(0.08, 0.5, 1.0);
uniform vec3 tip_color : source_color = vec3(0.6, 0.95, 1.0);
// Brillo propio, cuánto de él late y latidos por segundo.
uniform float glow : hint_range(0.0, 4.0) = 1.2;
uniform float pulse : hint_range(0.0, 1.0) = 0.4;
uniform float pulse_speed = 1.3;
// Borde que brilla contra la cámara.
uniform vec3 rim_color : source_color = vec3(0.55, 0.9, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 0.9;

group_uniforms Movimiento;
// Cuánto se mece la punta de una rama (en anchos de rama) y qué tan rápido.
uniform float sway = 0.6;
uniform float sway_speed = 0.9;

group_uniforms Camara;
// Metros a la cámara por debajo de los cuales el coral desaparece y por
// encima de los cuales se ve entero. Entre medio se deshace en una trama de
// puntos: así un coral nunca tapa la pelea por quedar pegado a la cámara.
uniform float fade_near = 3.0;
uniform float fade_far = 8.0;

varying float along;
varying float seed;
varying float grown;

// Trama ordenada de 4x4 (Bayer), como fórmula: 16 niveles entre 0 y 1 según
// el píxel.
float bayer2(vec2 cell) {
	cell = floor(cell);
	return fract(cell.x * 0.5 + cell.y * cell.y * 0.75);
}

float bayer4(vec2 pixel) {
	return bayer2(pixel * 0.5) * 0.25 + bayer2(pixel);
}

void vertex() {
	seed = INSTANCE_CUSTOM.z;
	// Las que tardan más en brotar son también las primeras en irse.
	grown = clamp(rise * 1.8 - INSTANCE_CUSTOM.x * 0.8, 0.0, 1.0);
	float eased = 1.0 - pow(1.0 - grown, 3.0);
	if (INSTANCE_CUSTOM.y > 0.5) {
		along = 1.0;
		VERTEX *= eased;
	} else {
		// El cilindro va de -0.5 a 0.5: el pie queda quieto y la punta sube.
		along = VERTEX.y + 0.5;
		VERTEX.xz *= mix(0.25, 1.0, eased);
		VERTEX.y = along * eased - 0.5;
		VERTEX.x += sin(TIME * sway_speed + seed * 20.0) * sway * along * along * eased;
	}
}

void fragment() {
	if (grown < 0.01) {
		discard;
	}
	// VERTEX es la posición del píxel vista desde la cámara.
	float seen = smoothstep(fade_near, fade_far, length(VERTEX));
	if (seen < 1.0 && seen < bayer4(FRAGCOORD.xy) + 0.03125) {
		discard;
	}
	vec3 color = mix(deep_color, bright_color, smoothstep(0.0, 0.8, along));
	color = mix(color, tip_color, smoothstep(0.75, 1.0, along));
	float beat = 0.5 + 0.5 * sin(TIME * pulse_speed + seed * 31.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	ALBEDO = color * 0.6;
	EMISSION = color * glow * (1.0 - pulse * beat) * (0.35 + 0.65 * along)
			+ rim_color * rim * rim_strength;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
}
