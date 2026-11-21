shader_type canvas_item;
// Suelo del mapa, para el minimapa y el mapa de Tab. TEXTURE es la imagen del
// terreno de la etapa y fog_texture la niebla de guerra (blanco = explorado).
// Muestra la ventana del mapa centrada en `center`, de ancho `span` y girada
// `rotation`; atenúa lo que nadie exploró, marca el borde de la arena y, con
// round_mask, recorta un círculo.
// Los valores los pone scripts/ui/maps/map_view.gd: se editan allá, no aquí.

uniform sampler2D fog_texture : filter_linear, repeat_disable, hint_default_white;
// Centro de la vista en UV del mapa (0.5, 0.5 = centro de la arena).
uniform vec2 center = vec2(0.5, 0.5);
// Fracción del lado de la arena que cabe en el ancho del rectángulo.
uniform float span = 1.0;
// Giro de la vista, en radianes.
uniform float rotation = 0.0;
uniform bool round_mask = false;
uniform vec4 unexplored_color : source_color = vec4(0.05, 0.12, 0.14, 1.0);
uniform float unexplored_strength : hint_range(0.0, 1.0) = 0.86;
uniform vec4 outside_color : source_color = vec4(0.03, 0.07, 0.08, 1.0);
uniform vec4 border_color : source_color = vec4(0.6, 0.8, 0.8, 0.5);
// Grosor de la línea del borde de la arena, en UV del mapa.
uniform float border_width = 0.004;
// Radio del suavizado del borde de la niebla, en píxeles de la niebla.
uniform float fog_blur = 0.75;
// Cuánto se oscurece el suelo hacia la orilla del círculo.
uniform float rim_shade : hint_range(0.0, 1.0) = 0.0;

// Niebla suavizada: el píxel y cuatro vecinos en diagonal. La imagen de niebla
// es gruesa (2 m por píxel), y sin esto su borde se ve en escalones.
float explored_at(vec2 map_uv) {
	vec2 step_uv = fog_blur / vec2(textureSize(fog_texture, 0));
	float total = texture(fog_texture, map_uv).r * 2.0;
	total += texture(fog_texture, map_uv + step_uv).r;
	total += texture(fog_texture, map_uv - step_uv).r;
	total += texture(fog_texture, map_uv + vec2(step_uv.x, -step_uv.y)).r;
	total += texture(fog_texture, map_uv + vec2(-step_uv.x, step_uv.y)).r;
	return smoothstep(0.3, 0.7, total / 6.0);
}

void fragment() {
	vec2 offset = UV - vec2(0.5);
	float s = sin(rotation);
	float c = cos(rotation);
	vec2 map_uv = vec2(offset.x * c - offset.y * s, offset.x * s + offset.y * c) * span + center;
	vec3 ground = texture(TEXTURE, map_uv).rgb;
	vec3 hidden = mix(ground, unexplored_color.rgb, unexplored_strength);
	vec3 color = mix(hidden, ground, explored_at(map_uv));
	// Distancia al borde de la arena en UV del mapa: negativa afuera.
	vec2 to_edge = min(map_uv, vec2(1.0) - map_uv);
	float inside = min(to_edge.x, to_edge.y);
	float soft = max(fwidth(inside), 0.00001);
	color = mix(outside_color.rgb, color, smoothstep(-soft, soft, inside));
	float line = 1.0 - smoothstep(border_width, border_width + soft * 2.0, abs(inside));
	color = mix(color, border_color.rgb, line * border_color.a);
	float alpha = 1.0;
	if (round_mask) {
		float radius = length(offset) * 2.0;
		float edge = max(fwidth(radius), 0.00001);
		alpha = 1.0 - smoothstep(1.0 - edge * 1.5, 1.0, radius);
		color *= 1.0 - rim_shade * smoothstep(0.7, 1.0, radius);
	}
	COLOR = vec4(color, alpha);
}
