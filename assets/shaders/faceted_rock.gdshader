shader_type spatial;

// Faceted rock (iteration 63). The boulder props are 8x4 sphere blobs with
// SMOOTH normals, which next to the flat-shaded RockFormations read as
// river pebbles from another game. This lights every triangle with its own
// face normal instead, so the same blob reads as a chipped boulder.
//
// The face normal comes from screen-space derivatives of the view-space
// position, and is then turned to face the camera: which way round the
// derivative cross product points depends on the platform's screen-space
// Y convention, and a visible face always faces the camera anyway.

uniform vec4 albedo : source_color = vec4(0.38, 0.39, 0.42, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(face, -VERTEX) < 0.0 ? -face : face;
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
}
