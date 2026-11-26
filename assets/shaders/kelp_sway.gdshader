shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Bosque de algas del Cementerio de barcos (KelpForest). Un MultiMesh: cada
// alga es una instancia de una misma hoja de alto 1, estirada a su altura.
// El vaivén se hace aquí, con TIME, así no cuesta nada al script y sigue
// aunque el mundo esté congelado. VERTEX llega en coordenadas del mundo.
// Cada instancia trae en INSTANCE_CUSTOM: x = fase (0-1), y = escala del
// vaivén (las más altas se mecen más). UV.y es la fracción de altura (0-1).

group_uniforms Movimiento;
// Metros que se corre la punta de un alga de escala 1.
uniform float sway_amount = 1.6;
// Radianes por segundo de la onda principal del vaivén.
uniform float sway_speed = 0.55;

group_uniforms Color;
// Color que multiplica al color de vértice (blanco = sin cambio).
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	float along = UV.y;
	float phase = INSTANCE_CUSTOM.x * TAU;
	// Dos senos de frecuencia distinta; el término con `along` hace que la
	// onda suba por el tallo en vez de mover el alga como una vara rígida.
	float main_wave = sin(TIME * sway_speed + phase);
	float ripple = sin(TIME * sway_speed * 2.37 + phase * 3.1 - along * 2.2);
	float side_wave = sin(TIME * sway_speed * 0.71 + phase * 1.7);
	vec3 push = vec3(main_wave * 0.75 + ripple * 0.25, 0.0, side_wave * 0.45 + ripple * 0.15);
	VERTEX += push * sway_amount * INSTANCE_CUSTOM.y * along * along;
}

void fragment() {
	// El color de vértice ya viene en espacio lineal desde kelp_forest.gd.
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
}
