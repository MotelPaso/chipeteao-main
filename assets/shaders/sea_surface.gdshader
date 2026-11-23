shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// LA SUPERFICIE DEL MAR vista desde abajo (nodo Surface de
// ShipGraveyard.tscn): un plano grande muy por encima del claro, con ondas de
// luz que corren y un resplandor donde está el sol. Se desvanece hacia los
// bordes para que no se le vea el final. Solo es luz: no choca con nada.

// Color de las ondas de luz y del agua entre ellas.
uniform vec3 light_color : source_color = vec3(0.78, 0.95, 1.0);
uniform vec3 water_color : source_color = vec3(0.16, 0.56, 0.86);
// Brillo general.
uniform float strength : hint_range(0.0, 3.0) = 1.1;
// Metros de una onda y rapidez con que corren.
uniform float ripple_size = 9.0;
uniform float ripple_speed = 0.35;
// Dónde está el resplandor del sol sobre el plano (UV 0-1) y su tamaño.
uniform vec2 sun_spot = vec2(0.56, 0.6);
uniform float sun_size : hint_range(0.01, 1.0) = 0.16;
// Lado del plano, en metros (lo pone quien lo arma: así las ondas miden metros).
uniform float side = 400.0;
// Fracción del plano, desde el centro, donde empieza a desvanecerse.
uniform float fade_from : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 metres = UV * side / ripple_size;
	float t = TIME * ripple_speed;
	// Dos capas de ruido que se cruzan: donde se anulan queda una veta de luz.
	float one = noise2(metres + vec2(t, t * 0.6));
	float two = noise2(metres * 1.7 - vec2(t * 0.8, t * 1.1) + 7.0);
	float veins = 1.0 - smoothstep(0.0, 0.16, abs(one - two));
	float away = distance(UV, vec2(0.5)) * 2.0;
	float sun = 1.0 - smoothstep(0.0, sun_size, distance(UV, sun_spot));
	vec3 color = mix(water_color, light_color, clamp(veins * 0.8 + sun, 0.0, 1.0));
	ALBEDO = color * strength;
	ALPHA = (0.35 + 0.65 * clamp(veins + sun, 0.0, 1.0)) * (1.0 - smoothstep(fade_from, 1.0, away));
}
