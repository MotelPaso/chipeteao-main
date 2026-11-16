shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

// Fondo de los primeros planos de la entrada de la Langosta Azul (nodo
// Camera/Backdrop de LobsterEntrance.tscn): una esfera vista desde adentro
// que rodea a la cámara y tapa el mapa entero. Es agua profunda: casi negro
// en los bordes, un resplandor azul detrás de la langosta y rayos de luz muy
// tenues que giran despacio. Se dibuja en coordenadas de pantalla, así el
// resplandor queda siempre en el centro, mire a donde mire la cámara.

// Azul del resplandor del centro y color de los bordes.
uniform vec3 core_color : source_color = vec3(0.02, 0.2, 0.55);
uniform vec3 edge_color : source_color = vec3(0.0, 0.008, 0.04);
// Tamaño del resplandor (1 = llega al borde de arriba y de abajo).
uniform float core_size : hint_range(0.1, 3.0) = 1.15;
// Rayos de luz: cuántos, cuánto aclaran y vueltas por segundo.
uniform float ray_count = 7.0;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.22;
uniform float ray_speed = 0.02;

void fragment() {
	vec2 centered = (SCREEN_UV - 0.5) * 2.0;
	centered.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float reach = length(centered);
	float glow = 1.0 - smoothstep(0.0, core_size, reach);
	float angle = atan(centered.y, centered.x);
	float rays = 0.5 + 0.5 * sin(angle * ray_count + TIME * ray_speed * 6.28318);
	rays *= 0.5 + 0.5 * sin(angle * (ray_count * 2.0 + 1.0) - TIME * ray_speed * 9.4);
	vec3 color = mix(edge_color, core_color, glow * glow);
	ALBEDO = color * (1.0 + ray_strength * rays * 2.0 * glow);
}
