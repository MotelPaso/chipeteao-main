shader_type spatial;
render_mode cull_disabled;

// Cardumen del Cementerio de barcos (FishSchool). Un MultiMesh: cada pez es
// una instancia de la misma malla (nariz hacia +X), y este shader lo lleva
// por una elipse alrededor del nodo con TIME, así nada cuesta en el script y
// los peces siguen nadando aunque el mundo esté congelado.
// La transformada de cada instancia solo trae el tamaño del pez.
// INSTANCE_CUSTOM: x = fase en la vuelta (0-1), y = escala del radio,
// z = altura en metros, w = escala de la velocidad.
// COLOR.a de la malla: 0 en la nariz, 1 en la punta de la cola.

group_uniforms Recorrido;
// Radios de la elipse en X y en Z, en metros.
uniform vec2 loop_radius = vec2(14.0, 9.0);
// Vueltas por segundo; el signo elige el sentido.
uniform float loop_speed = 0.035;
// Metros que sube y baja cada pez, y vaivenes por segundo (en radianes).
uniform float bob_height = 0.35;
uniform float bob_speed = 0.9;

group_uniforms Cola;
// Radianes que gira la punta de la cola, y aletazos por segundo (en radianes).
uniform float wiggle_angle = 0.45;
uniform float wiggle_speed = 9.0;

group_uniforms Color;
// Color del lomo y de la panza.
uniform vec3 body_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 belly_color : source_color = vec3(1.0, 0.75, 0.35);

varying float belly;

// Gira `v` alrededor de Y por `angle` radianes.
vec3 turn_y(vec3 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	belly = 1.0 - smoothstep(-0.04, 0.015, VERTEX.y);

	// La cola se mece más hacia la punta.
	float flap = wiggle_angle * COLOR.a * sin(TIME * wiggle_speed + phase * 61.0);
	vec3 local = turn_y(VERTEX, flap);
	vec3 local_normal = turn_y(NORMAL, flap);

	float angle = TAU * (phase + TIME * loop_speed * INSTANCE_CUSTOM.w);
	vec2 radii = loop_radius * INSTANCE_CUSTOM.y;
	vec3 centre = vec3(cos(angle) * radii.x, INSTANCE_CUSTOM.z, sin(angle) * radii.y);
	centre.y += bob_height * sin(TIME * bob_speed + phase * 37.0);

	// La tangente de la elipse (derivada respecto del ángulo) marca hacia
	// dónde nada; su signo sigue al sentido de la vuelta.
	vec3 ahead = normalize(vec3(-sin(angle) * radii.x, 0.0, cos(angle) * radii.y))
			* sign(loop_speed + 1e-6);
	vec3 side = cross(ahead, vec3(0.0, 1.0, 0.0));
	VERTEX = ahead * local.x + vec3(0.0, local.y, 0.0) + side * local.z;
	NORMAL = ahead * local_normal.x + vec3(0.0, local_normal.y, 0.0) + side * local_normal.z;

	// MODEL_MATRIX trae el tamaño del pez: el recorrido se divide por él
	// para que la elipse quede en metros.
	float fish_scale = max(length(MODEL_MATRIX[0].xyz), 1e-4);
	VERTEX += centre / fish_scale;
}

void fragment() {
	ALBEDO = mix(body_color, belly_color, belly);
	ROUGHNESS = 0.35;
	SPECULAR = 0.7;
	METALLIC = 0.2;
}
