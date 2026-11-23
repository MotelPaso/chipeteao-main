shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded;

// Medusas del Cementerio de barcos (JellyfishBloom). Un MultiMesh: cada
// medusa es una instancia de la misma malla (campana de radio 1 abierta
// abajo y seis tentáculos), escalada a su tamaño. Late, sube y baja y se
// deriva en un círculo con TIME, así sigue aunque el mundo esté congelado.
// INSTANCE_CUSTOM: x = fase (0-1), y = amplitud del vaivén (cerca de 1),
// z = sentido y rapidez de la deriva (0-1; 0.5 = quieta), w = ritmo del latido.
// COLOR.r de la malla: 1 en la campana, 0 en los tentáculos.
// COLOR.a: 0 en la campana y de 0 a 1 bajando por cada tentáculo.

group_uniforms Color;
// Color del borde que brilla y del centro de la campana.
uniform vec3 glow_color : source_color = vec3(0.55, 0.9, 1.0);
uniform vec3 core_color : source_color = vec3(0.95, 0.6, 0.9);
// Opacidad del borde de la campana (el centro y los tentáculos son más tenues).
uniform float alpha : hint_range(0.0, 1.0) = 0.55;
// Multiplica el color: más de 1 la hace brillar contra el agua.
uniform float brightness : hint_range(0.0, 4.0) = 1.4;

group_uniforms Latido;
// Radianes por segundo del latido y cuánto se abre la campana (fracción del radio).
uniform float pulse_speed = 1.6;
uniform float pulse_amount = 0.14;

group_uniforms Deriva;
// Metros que sube y baja, y su velocidad en radianes por segundo.
uniform float bob_height = 0.8;
uniform float bob_speed = 0.35;
// Radio en metros del círculo que recorre a la deriva, y su velocidad en radianes por segundo.
uniform float drift_radius = 1.5;
uniform float drift_speed = 0.12;
// Cuánto se mecen las puntas de los tentáculos (en radios de campana) y su velocidad.
uniform float tentacle_sway = 0.35;
uniform float tentacle_speed = 1.1;

varying float beat;
varying float bell;
varying float down;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * TAU;
	float swing = INSTANCE_CUSTOM.y;
	bell = COLOR.r;
	down = COLOR.a;
	beat = sin(TIME * pulse_speed * INSTANCE_CUSTOM.w + phase);

	// La campana se abre más en el borde (y = 0) que en la cúpula; el pie de
	// los tentáculos la sigue para no despegarse.
	float rim_weight = bell > 0.5 ? clamp(1.0 - VERTEX.y, 0.0, 1.0) : 1.0 - down;
	VERTEX.xz *= 1.0 + pulse_amount * beat * rim_weight;
	VERTEX.y *= 1.0 - pulse_amount * 0.5 * beat * bell;

	// Los tentáculos se mecen más hacia la punta.
	float tip = down * sqrt(down);
	float sway_time = TIME * tentacle_speed + phase;
	VERTEX.x += sin(sway_time + down * 3.0) * tentacle_sway * tip;
	VERTEX.z += cos(sway_time * 0.83 + down * 2.4) * tentacle_sway * tip;

	// MODEL_MATRIX trae el tamaño de la medusa: la deriva se divide por él
	// para quedar en metros.
	float body_scale = max(length(MODEL_MATRIX[1].xyz), 1e-4);
	float drift_angle = TIME * drift_speed * (INSTANCE_CUSTOM.z * 2.0 - 1.0) + phase;
	vec3 drift = vec3(cos(drift_angle) * drift_radius, 0.0, sin(drift_angle) * drift_radius);
	drift.y = sin(TIME * bob_speed + phase) * bob_height;
	VERTEX += drift * swing / body_scale;
}

void fragment() {
	// De canto la campana se ve más espesa: el borde brilla y el centro se
	// transparenta. abs() porque con cull_disabled se ven las dos caras.
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	rim = rim * rim;
	float glow = brightness * (1.0 + 0.25 * beat);
	if (bell > 0.5) {
		ALBEDO = mix(core_color, glow_color, rim) * glow;
		ALPHA = alpha * mix(0.3, 1.0, rim);
	} else {
		ALBEDO = mix(core_color, glow_color, 0.5 + 0.5 * down) * glow;
		ALPHA = alpha * 0.8 * (1.0 - down * 0.75);
	}
}
