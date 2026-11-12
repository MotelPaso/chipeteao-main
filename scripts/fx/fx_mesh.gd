class_name FxMesh
extends RefCounted
## Constructores de malla que comparten los efectos procedurales (la
## medialuna del tajo y el latigazo). Los dos son la misma tira de triángulos,
## pares de vértices interior/exterior con alfa por vértice, así que solo
## cambia el bucle de vértices y el armado del ArrayMesh vive aquí una vez.

## Arma una tira de triángulos con `vertices`/`colors` dados como pares
## consecutivos (interior, exterior) a lo largo de la tira. Necesita al menos
## dos pares.
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
