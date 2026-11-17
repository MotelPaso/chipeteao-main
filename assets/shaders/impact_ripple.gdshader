shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// La ONDA que deja en el suelo un golpe de la Langosta Azul
// (ImpactRipple.tscn): un fogonazo en el centro, anillos que se abren hasta
// el borde del golpe y rayos que se apagan. Va sobre un cuadro de 2 x 2
// acostado en el suelo y escalado al radio del golpe; solo suma luz.

group_uniforms Onda;
// Anillos que se abren uno detrás del otro y su grosor (en radios).
uniform int rings : hint_range(1, 5) = 3;
uniform float ring_width : hint_range(0.01, 0.4) = 0.09;
// Cuánto más atrás va cada anillo respecto del anterior (en radios).
uniform float ring_gap : hint_range(0.05, 0.6) = 0.26;
// Rayos alrededor del centro y cuánto brillan.
uniform float spokes = 16.0;
uniform float spoke_strength : hint_range(0.0, 2.0) = 0.7;
// Brillo general.
uniform float strength : hint_range(0.0, 6.0) = 2.2;

// Color de la onda (lo pone quien la lanza).
instance uniform vec3 tint : source_color = vec3(1.0, 0.5, 0.45);
// 0-1: cuánto lleva de su vida (lo escribe ImpactRipple).
instance uniform float progress = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	// El frente sale rápido y frena al llegar al borde.
	float front = 1.0 - (1.0 - progress) * (1.0 - progress);
	float light = 0.0;
	for (int i = 0; i < rings; i++) {
		float radius = front - ring_gap * float(i);
		if (radius > 0.0) {
			light += smoothstep(ring_width, 0.0, abs(r - radius)) * (1.0 - 0.3 * float(i));
		}
	}
	// Rayos desparejos que nacen del centro y no pasan del frente.
	float angle = atan(p.y, p.x);
	float slot = floor((angle / TAU + 0.5) * spokes);
	float within = fract((angle / TAU + 0.5) * spokes) - 0.5;
	float ray = smoothstep(0.5, 0.0, abs(within) * (2.0 + 4.0 * hash11(slot)));
	ray *= smoothstep(front, front * 0.25, r) * (0.4 + 0.6 * hash11(slot + 7.0));
	light += ray * spoke_strength * (1.0 - progress);
	// Fogonazo del centro, solo al principio.
	light += smoothstep(0.55, 0.0, r) * pow(1.0 - progress, 3.0) * 1.4;
	float life = 1.0 - progress * progress;
	ALBEDO = tint * strength;
	ALPHA = clamp(light, 0.0, 1.0) * life;
}
