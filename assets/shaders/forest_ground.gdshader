shader_type spatial;

// Suelo del Bosque Hueco: dos tonos de verde con ruido de valor sobre el XZ
// del mundo, que se leen como pasto disparejo y dejan ver la velocidad sin
// una grilla.
// Cuando un jefe quema el bosque (HellTransformation), un frente de fuego
// avanza desde burn_origin y deja tierra calcinada con grietas de lava; al
// enfriarse (heat baja, ash sube) quedan grietas apagadas y ceniza.
// En la escena de la arena burn_radius vale 0 y el suelo es el pasto de
// siempre: HellTransformation escribe estos valores sobre SU copia del
// material, nunca sobre el de la escena.

group_uniforms Pasto;
// Verde oscuro del pasto.
uniform vec3 grass_dark : source_color = vec3(0.4236, 0.6180, 0.4731);
// Verde claro del pasto.
uniform vec3 grass_light : source_color = vec3(0.5371, 0.7354, 0.5469);
// Tamaño de las manchas de pasto (más alto = manchas más chicas).
uniform float grass_scale = 0.35;

group_uniforms Quemado;
// Tierra calcinada, tono oscuro y tono claro.
uniform vec3 scorch_dark : source_color = vec3(0.1, 0.07, 0.06);
uniform vec3 scorch_light : source_color = vec3(0.22, 0.14, 0.11);
// Lava de las grietas y su centro más caliente.
uniform vec3 lava_color : source_color = vec3(1.0, 0.28, 0.03);
uniform vec3 lava_core : source_color = vec3(1.0, 0.7, 0.25);
// Ceniza que queda al enfriarse.
uniform vec3 ash_color : source_color = vec3(0.3, 0.29, 0.28);
// Tamaño de la red de grietas (más alto = grietas más juntas).
uniform float crack_scale = 0.3;
// Grosor de las grietas (0-1).
uniform float crack_width : hint_range(0.01, 0.5) = 0.055;
// Fuerza del brillo de la lava.
uniform float lava_glow = 1.6;

group_uniforms Renacido;
// Lava y centro de las grietas en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_lava_color : source_color = vec3(0.04, 0.34, 1.0);
uniform vec3 ascended_lava_core : source_color = vec3(0.55, 0.9, 1.0);
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
// 1 = el suelo arde; 0 = ya se enfrió.
uniform float heat : hint_range(0.0, 1.0) = 1.0;
// 0 = recién quemado; 1 = cubierto de ceniza.
uniform float ash : hint_range(0.0, 1.0) = 0.0;

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
	float n = value_noise(world_pos.xz * grass_scale);
	vec3 grass = mix(grass_dark, grass_light, n);
	// El frente: un círculo que crece, con el borde roto por ruido.
	float reach = distance(world_pos.xz, burn_origin.xz)
			+ (value_noise(world_pos.xz * 0.08) - 0.5) * burn_edge * 2.0;
	float burnt = burn_radius <= 0.0 ? 0.0
			: 1.0 - smoothstep(burn_radius - burn_edge, burn_radius, reach);
	float rim = burnt * (1.0 - burnt) * 4.0;
	// Tierra calcinada y grietas: las venas son la línea media de otro ruido.
	float patch = value_noise(world_pos.xz * 0.5 + vec2(31.0, 7.0));
	float vein_noise = value_noise(world_pos.xz * crack_scale + vec2(13.7, 4.2));
	float vein = 1.0 - smoothstep(0.0, crack_width, abs(vein_noise * 2.0 - 1.0));
	vein *= vein;
	float pulse = 0.7 + 0.3 * sin(TIME * 1.5 + vein_noise * 20.0);
	vec3 ground = mix(scorch_dark, scorch_light, patch);
	ground = mix(ground, ash_color, ash * (0.12 + 0.55 * patch));
	ground = mix(ground, scorch_dark * 0.35, vein * 0.8);
	ALBEDO = mix(grass, ground, burnt);
	// El fuego azul avanza igual que el primer frente, desde su propio origen.
	float ascend_reach = distance(world_pos.xz, ascend_origin.xz)
			+ (value_noise(world_pos.xz * 0.08) - 0.5) * burn_edge * 2.0;
	float ascended = ascend_radius <= 0.0 ? 0.0
			: 1.0 - smoothstep(ascend_radius - burn_edge, ascend_radius, ascend_reach);
	vec3 lava = mix(lava_color, ascended_lava_color, ascended);
	vec3 core = mix(lava_core, ascended_lava_core, ascended);
	vec3 glow = mix(lava, core, vein * pulse) * vein * pulse * lava_glow
			+ lava * rim * 3.0 + ascended_lava_core * ascended * (1.0 - ascended) * 6.0;
	EMISSION = glow * burnt * heat;
	ROUGHNESS = 1.0;
}
