shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Un tramo del carril de aviso (TelegraphLane.tscn): galones que corren hacia
// donde va a pasar el golpe, entre dos bordes. Va sobre un plano de 1 x 1 que
// el carril estira. El color y la opacidad de cada tramo llegan por el color
// de su instancia (los escribe telegraph_lane.gd).

group_uniforms Galones;
// Galones por tramo y rapidez con que corren hacia adelante.
uniform float chevrons = 1.0;
uniform float flow_speed = 1.6;
// Cuánto se echa atrás el galón hacia los costados (0 = una barra recta).
uniform float sweep : hint_range(0.0, 2.0) = 0.9;
// Ancho de cada borde del carril, como fracción del ancho.
uniform float edge : hint_range(0.0, 0.4) = 0.07;

void fragment() {
	// UV.y corre a lo largo del carril; la punta del galón va adelante.
	float along = (UV.y + abs(UV.x - 0.5) * sweep) * chevrons - TIME * flow_speed;
	float band = fract(along);
	float chevron = smoothstep(0.2, 0.32, band) * (1.0 - smoothstep(0.62, 0.74, band));
	float border = step(UV.x, edge) + step(1.0 - edge, UV.x);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * clamp(chevron * 0.8 + border, 0.0, 1.0);
}
