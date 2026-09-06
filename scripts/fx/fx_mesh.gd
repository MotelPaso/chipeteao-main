class_name FxMesh
extends RefCounted
## Mesh builders shared by the procedural FX (the slash crescent and the
## whip lash). Both are the same triangle strip — pairs of inner/outer
## vertices with vertex-alpha shaping — so only the vertex loop differs and
## the ArrayMesh assembly lives here once.

## Builds a triangle strip from `vertices`/`colors` given as consecutive
## pairs (inner, outer) along the strip. Needs at least two pairs.
static func strip(vertices: PackedVector3Array,
		colors: PackedColorArray) -> ArrayMesh:
	var pairs := vertices.size() / 2
	var indices := PackedInt32Array()
	for i: int in maxi(pairs - 1, 0):
		var base := i * 2
		indices.append_array(PackedInt32Array([
			base, base + 1, base + 2,
			base + 1, base + 3, base + 2,
		]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built
