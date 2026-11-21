shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// Zona de fuego de un jefe: primero un AVISO (un aro y un relleno que crece
// desde el centro, como los discos de aviso) y después lava encendida. El
// disco es un cilindro de radio 1 escalado al radio de la zona.
// `charge`, `burn` y `fade` son POR INSTANCIA (los escribe fire_zone.gd), así
// todas las zonas comparten un solo material.

// Color del aviso antes de encenderse.
uniform vec3 warn_color : source_color = vec3(1.0, 0.42, 0.08);
// Color del fuego encendido.
uniform vec3 fire_color : source_color = vec3(1.0, 0.36, 0.05);
// Color del centro más caliente.
uniform vec3 core_color : source_color = vec3(1.0, 0.86, 0.38);
// Los mismos tres colores en la segunda fase del jefe (el fuego azul).
uniform vec3 ascended_warn_color : source_color = vec3(0.25, 0.65, 1.0);
uniform vec3 ascended_fire_color : source_color = vec3(0.06, 0.36, 1.0);
uniform vec3 ascended_core_color : source_color = vec3(0.6, 0.92, 1.0);
// 0-1: cuánto del fuego de la segunda fase (FireTint lo escribe para todo el fuego a la vez).
global uniform float fire_ascend;
// Tamaño de las manchas de lava, en metros.
uniform float flow_scale : hint_range(0.2, 4.0) = 1.1;
// Velocidad con que se mueve la lava.
uniform float flow_speed : hint_range(0.0, 3.0) = 0.6;
// Cuánto brillan de más las vetas calientes de la lava (0 = nada).
uniform float vein_glow : hint_range(0.0, 2.0) = 0.55;
// Opacidad del relleno del aviso (0-1).
uniform float warn_fill_alpha : hint_range(0.0, 1.0) = 0.3;
// Metros que el disco se acerca a la cámara al dibujarse: así una loma del
// suelo no le come un pedazo.
uniform float depth_bias : hint_range(0.0, 3.0) = 1.2;

// Avance del aviso (0-1): el relleno llega al borde en 1.
instance uniform float charge = 0.0;
// Encendido (0-1): 0 es solo aviso, 1 es lava.
instance uniform float burn = 0.0;
// Opacidad de toda la zona (0-1), para apagarse.
instance uniform float fade = 1.0;

varying vec3 local_pos;
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

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Mismo lugar en pantalla, un poco más cerca en profundidad.
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.xyz -= normalize(view_pos.xyz) * depth_bias;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	// Distancia al centro en radios: 1.0 es el borde de la zona de daño.
	float r = length(local_pos.xz);
	float ring = smoothstep(0.86, 0.94, r) * (1.0 - smoothstep(0.985, 1.0, r));
	float pulse = 0.75 + 0.25 * sin(TIME * 12.0);
	float fill = (1.0 - smoothstep(charge - 0.04, charge, r)) * warn_fill_alpha;
	float warn_alpha = max(ring * pulse, fill);
	// Lava: dos capas de ruido que se cruzan sobre el suelo del mundo.
	vec2 flow = world_pos.xz / flow_scale;
	float n = value_noise(flow + vec2(TIME * flow_speed, 0.0)) * 0.6
			+ value_noise(flow * 2.3 - vec2(0.0, TIME * flow_speed * 1.4)) * 0.4;
	float heat = smoothstep(0.25, 0.85, n);
	float inside = 1.0 - smoothstep(0.82, 1.0, r);
	vec3 fire = mix(fire_color, ascended_fire_color, fire_ascend);
	vec3 core = mix(core_color, ascended_core_color, fire_ascend);
	vec3 lava = mix(fire, core, max(heat, ring * 0.7));
	float lava_alpha = max(mix(0.6, 0.94, heat) * inside, ring);
	// Las vetas más calientes de la lava brillan de más, para que resplandezcan.
	ALBEDO = mix(mix(warn_color, ascended_warn_color, fire_ascend), lava * (1.0 + vein_glow * heat), burn);
	ALPHA = mix(warn_alpha, lava_alpha, burn) * fade;
}
