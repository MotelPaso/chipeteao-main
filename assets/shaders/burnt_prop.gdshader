shader_type spatial;

// Árboles, rocas, tocones, mesetas y formaciones del bosque mientras un jefe
// lo quema (HellTransformation). Con burn_radius en 0 se ve igual que el
// material que reemplaza. Cuando pasa el frente de fuego, lo VERDE (follaje,
// pasto de las mesetas) arde con llamas y el resto se carboniza con brasas;
// al enfriarse (heat baja, ash sube) el follaje se deshace y queda el
// tronco negro.
// HellTransformation crea una copia por tipo de superficie y escribe aquí;
// este shader no está en ninguna escena.

group_uniforms Superficie;
// De dónde sale el color: 0 = textura colormap, 1 = flat_color, 2 = color de vértice.
uniform int source_mode : hint_range(0, 2) = 0;
// Textura de los modelos (modo 0).
uniform sampler2D colormap : source_color, filter_linear_mipmap, repeat_enable;
// Color liso (modo 1) o tinte del color de vértice (modo 2).
uniform vec3 flat_color : source_color = vec3(1.0);
// Rugosidad de la superficie (0-1).
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
// Cuánto más verde que rojo o azul debe ser un punto para contar como follaje.
uniform float leaf_threshold = 0.04;
// 1 = el follaje se deshace al enfriarse (árboles); 0 = solo se carboniza.
uniform float leaves_fall : hint_range(0.0, 1.0) = 1.0;
// Cuánto arde lo verde (1 = follaje de árbol; menos = pasto de una meseta).
uniform float flame_amount : hint_range(0.0, 1.0) = 1.0;

group_uniforms Quemado;
// Carbón en que termina todo.
uniform vec3 char_color : source_color = vec3(0.1, 0.085, 0.08);
// Brasas del tronco y de la roca.
uniform vec3 ember_color : source_color = vec3(1.0, 0.36, 0.05);
// Llamas del follaje y su centro más caliente.
uniform vec3 fire_color : source_color = vec3(1.0, 0.42, 0.06);
uniform vec3 fire_core : source_color = vec3(1.0, 0.85, 0.4);
// Fuerza del brillo de las llamas.
uniform float fire_glow = 1.5;

group_uniforms Renacido;
// Brasas, llamas y su centro en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_ember_color : source_color = vec3(0.05, 0.36, 1.0);
uniform vec3 ascended_fire_color : source_color = vec3(0.06, 0.42, 1.0);
uniform vec3 ascended_fire_core : source_color = vec3(0.6, 0.92, 1.0);
// El frente del fuego azul: de dónde sale y hasta dónde llegó, en metros (0 = no empezó).
uniform vec3 ascend_origin = vec3(0.0);
uniform float ascend_radius = 0.0;

group_uniforms Frente;
// Punto del mundo desde el que avanza el fuego.
uniform vec3 burn_origin = vec3(0.0);
// Metros que avanzó el frente (0 = nada quemado).
uniform float burn_radius = 0.0;
// Ancho en metros del borde encendido del frente.
uniform float burn_edge = 9.0;
// 1 = arde; 0 = ya se enfrió.
uniform float heat : hint_range(0.0, 1.0) = 1.0;
// 0 = recién quemado; 1 = cubierto de ceniza y sin follaje.
uniform float ash : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

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

// Color de vértice guardado en sRGB, llevado a lineal.
vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92,
			lessThan(c, vec3(0.04045)));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = flat_color;
	if (source_mode == 0) {
		base = texture(colormap, UV).rgb;
	} else if (source_mode == 2) {
		base = srgb_to_linear(COLOR.rgb) * flat_color;
	}
	float leaf = smoothstep(leaf_threshold, leaf_threshold + 0.08,
			base.g - max(base.r, base.b));
	// El mismo frente que el suelo (forest_ground.gdshader): tienen que coincidir.
	float reach = distance(world_pos.xz, burn_origin.xz)
			+ (value_noise(world_pos.xz * 0.08) - 0.5) * burn_edge * 2.0;
	float burnt = burn_radius <= 0.0 ? 0.0
			: 1.0 - smoothstep(burn_radius - burn_edge, burn_radius, reach);
	// Llamas que suben por el follaje: dos ruidos que corren hacia arriba.
	float flicker = value_noise(world_pos.xz * 0.9 + vec2(world_pos.y * 0.7, -TIME * 1.8)) * 0.6
			+ value_noise(world_pos.xy * 1.7 + vec2(TIME * 0.9, -TIME * 2.6)) * 0.4;
	float flame = smoothstep(0.5, 0.82, flicker);
	float ember = smoothstep(0.6, 0.9,
			value_noise(world_pos.xz * 2.3 + vec2(world_pos.y * 1.9, 3.0)));
	// El fuego azul avanza igual que el primer frente, desde su propio origen.
	float ascend_reach = distance(world_pos.xz, ascend_origin.xz)
			+ (value_noise(world_pos.xz * 0.08) - 0.5) * burn_edge * 2.0;
	float ascended = ascend_radius <= 0.0 ? 0.0
			: 1.0 - smoothstep(ascend_radius - burn_edge, ascend_radius, ascend_reach);
	vec3 fire = mix(fire_color, ascended_fire_color, ascended);
	vec3 core = mix(fire_core, ascended_fire_core, ascended);
	// Lo verde queda en carbón del color del fuego; las llamas son parches que suben.
	vec3 canopy = mix(char_color, fire * 0.22, 0.5);
	vec3 charred = mix(mix(base * 0.4, char_color, 0.85), canopy, leaf);
	ALBEDO = mix(base, charred, burnt);
	float burning = leaf * flame_amount;
	vec3 glow = mix(fire, core, flame) * burning * flame * fire_glow
			+ fire * burning * 0.12
			+ mix(ember_color, ascended_ember_color, ascended) * ember * (1.0 - burning) * 1.1;
	EMISSION = glow * burnt * heat;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	// Al enfriarse el follaje quemado se deshace en huecos.
	if (leaves_fall > 0.5 && leaf > 0.5 && burnt > 0.5) {
		float hole = value_noise(world_pos.xz * 3.1 + vec2(world_pos.y * 2.7, 7.0));
		if (hole < ash * 0.92) {
			discard;
		}
	}
}
