shader_type spatial;

// Borde negro de silueta (casco invertido): una segunda pasada de la malla,
// inflada hacia afuera y dibujada solo por dentro (cull_front), así desde la
// cámara asoma un contorno alrededor del cuerpo. La suma Outline.apply() como
// next_pass de cada material opaco de personajes y enemigos. El grosor va en
// metros del mundo, así un modelo escalado x100 (el zombi) no sale más grueso.
render_mode unshaded, cull_front, shadows_disabled;

// Color del borde.
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Grosor del borde, en metros.
uniform float width = 0.035;

void vertex() {
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_position.xyz += view_normal * width;
	POSITION = PROJECTION_MATRIX * view_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
