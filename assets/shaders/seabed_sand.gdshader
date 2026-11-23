shader_type spatial;

// Arena del fondo marino (ShipGraveyard.tscn, nodo Terrain): dos tonos de
// arena clara con manchas de ruido sobre el XZ del mundo y las ondas que
// deja la corriente. Todo sale del XZ del mundo, así no hay costura entre
// parches del terreno. Los reflejos de agua NO van aquí: los suma la marea
// (LobsterTide, nodo Caustics) sobre una copia de la malla.

group_uniforms Arena;
// Tono claro y tono oscuro de la arena.
uniform vec3 sand_light : source_color = vec3(0.90, 0.85, 0.68);
uniform vec3 sand_dark : source_color = vec3(0.72, 0.67, 0.53);
// Tamaño de las manchas (más alto = manchas más chicas).
uniform float patch_scale = 0.11;

group_uniforms Ondas;
// Color del valle de cada onda.
uniform vec3 ripple_shade : source_color = vec3(0.60, 0.57, 0.47);
// Ondas por metro, cuánto oscurecen (0-1) y cuánto las tuerce el ruido.
uniform float ripple_scale = 1.5;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.32;
uniform float ripple_warp = 1.6;
// Dirección de la corriente, en grados (las ondas quedan atravesadas a ella).
uniform float current_degrees = 35.0;

float cell_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), u.x),
			mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0, 1.0)), u.x),
			u.y);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float patch_noise = value_noise(world_pos.xz * patch_scale);
	vec3 sand = mix(sand_dark, sand_light, patch_noise);
	// Ondas: franjas atravesadas a la corriente, torcidas por un ruido lento.
	float turn = radians(current_degrees);
	float along = dot(world_pos.xz, vec2(cos(turn), sin(turn)));
	float warp = value_noise(world_pos.xz * 0.3) * ripple_warp;
	float wave = sin((along + warp) * ripple_scale * 6.2832);
	// Las ondas se pierden donde la arena está revuelta (ruido alto).
	float calm = 1.0 - smoothstep(0.55, 0.95, value_noise(world_pos.xz * 0.05 + 11.0));
	sand = mix(sand, ripple_shade, smoothstep(0.1, 1.0, wave) * ripple_strength * calm);
	ALBEDO = sand;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
