shader_type canvas_item;
// Oscurecido de los menús: una capa de color petróleo con viñeta de tinta
// sobre el mapa 3D que el autoload MenuBackdrop mantiene vivo detrás, para
// que el texto se lea. Lo usan las pantallas de menú (MainMenu,
// CharacterSelect, QuestLog, Collection, RelicShop) en su nodo Background, a
// través de un solo material: assets/ui/menu_backdrop.tres.
//
// Sin mapa detrás (headless o una escena de prueba) `reveal` queda en 0 y la
// capa es opaca: el color petróleo es el fondo de respaldo.
// No lee la pantalla (sin screen texture): es un solo color con alfa, casi
// gratis a pantalla completa.
// Edita los colores y las fuerzas aquí, o en el Inspector del material (lo
// que guarde el material gana). `reveal` lo maneja MenuBackdrop: no lo toques.

// Color del oscurecido y del fondo de respaldo.
uniform vec3 tint_color: source_color = vec3(0.055, 0.165, 0.188);
// Color hacia el que se cierran las esquinas.
uniform vec3 edge_color: source_color = vec3(0.082, 0.075, 0.102);
// Cuánto tapa el oscurecido al mapa en el centro (0 = nada, 1 = todo).
uniform float dim: hint_range(0.0, 1.0) = 0.62;
// Cuánto más tapa en las esquinas.
uniform float vignette: hint_range(0.0, 1.0) = 0.34;
// 0 = capa opaca (sin mapa); 1 = mapa visible bajo el oscurecido.
uniform float reveal: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float edge = smoothstep(0.28, 0.92, length(UV - 0.5) * 1.3);
	vec3 col = mix(tint_color, edge_color, edge * 0.7);
	float cover = clamp(dim + vignette * edge, 0.0, 1.0);
	COLOR = vec4(col, mix(1.0, cover, reveal));
}
