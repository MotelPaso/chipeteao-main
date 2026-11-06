shader_type spatial;

// Roca facetada. Las rocas de props son esferas de 8x4 con normales SUAVES,
// que junto a las RockFormation de sombreado plano parecen guijarros de río.
// Este shader ilumina cada triángulo con su propia normal de cara, así la
// misma esfera se lee como una roca tallada.
//
// La normal de cara sale de las derivadas en pantalla de la posición en
// espacio de vista, y luego se gira hacia la cámara: hacia dónde apunta el
// producto cruz depende de la convención de Y de pantalla de la plataforma,
// y una cara visible siempre mira a la cámara.

// Color de la roca (sRGB).
uniform vec4 albedo : source_color = vec4(0.38, 0.39, 0.42, 1.0);
// Rugosidad de la superficie (0-1).
uniform float roughness : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(face, -VERTEX) < 0.0 ? -face : face;
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
}
