class_name TerrainMesh
extends RefCounted
## La malla de render clásica de un Terrain: una cuadrícula de mesh_step
## metros sobre la altura del colisionador. La usan las arenas sin relieve por
## zonas; las que lo tienen arman la suya en ReliefMesh, y las dos pasan por
## assert_winding().
##
## Arreglos empaquetados y una sola add_surface_from_arrays: SurfaceTool
## sobre una cuadrícula de este tamaño son cientos de miles de llamadas de
## GDScript y tarda segundos.


## Vértices, normales, UVs e índices de la cuadrícula de `terrain`.
static func grid(terrain: Terrain) -> Array:
	var cells := maxi(int(round(terrain.size / maxf(terrain.mesh_step, 0.5))), 2)
	var arrays := _grid_arrays(terrain, cells + 1)
	arrays[Mesh.ARRAY_INDEX] = _grid_indices(cells)
	return arrays


## Comprueba hacia dónde miran los triángulos, lo único de esta malla que
## un soak headless no ve. Revisa solo el PRIMER triángulo: todas las celdas
## salen de las mismas tres líneas, así que si uno está al revés lo están todos.
##
## `up` es la normal de MANO DERECHA del triángulo tal como está listado.
## Godot descarta el lado antihorario, así que una cara visible desde arriba
## lista sus vértices en sentido horario visto desde +Y y su normal de mano
## derecha apunta ABAJO. Una Y positiva es el error.
static func assert_winding(vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	if indices.size() < 3:
		return
	var v0 := vertices[indices[0]]
	var v1 := vertices[indices[1]]
	var v2 := vertices[indices[2]]
	var up := (v1 - v0).cross(v2 - v0)
	if up.y >= 0.0:
		push_error("Terrain: ground triangles wound the wrong way — "
				+ "the whole surface is back-face culled from above")


## Vértices, normales y UVs de una cuadrícula de `verts` x `verts` puntos a
## mesh_step metros, sobre la altura del colisionador.
static func _grid_arrays(terrain: Terrain, verts: int) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(verts * verts)
	normals.resize(verts * verts)
	uvs.resize(verts * verts)
	var half := terrain.size * 0.5
	var mesh_step := terrain.mesh_step
	for iz in verts:
		var z := -half + float(iz) * mesh_step
		for ix in verts:
			var x := -half + float(ix) * mesh_step
			var index := iz * verts + ix
			vertices[index] = Vector3(x, terrain.height_at(x, z), z)
			# Normal analítica desde las diferencias de altura a cada lado:
			# diferencia central sobre un paso de malla, la misma pendiente
			# que tiene el colisionador.
			var dx := terrain.height_at(x + mesh_step, z) - terrain.height_at(x - mesh_step, z)
			var dz := terrain.height_at(x, z + mesh_step) - terrain.height_at(x, z - mesh_step)
			normals[index] = Vector3(-dx, 2.0 * mesh_step, -dz).normalized()
			# UVs en XZ de mundo: los shaders de suelo del bioma leen la
			# posición de mundo.
			uvs[index] = Vector2(x, z)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


## Dos triángulos por celda de una cuadrícula de `cells` x `cells`.
## ORIENTACIÓN. La cara frontal en Godot es la HORARIA vista de frente, así
## que un suelo para caminar debe ser horario visto desde +Y, o sea
## cross(v1 - v0, v2 - v0) apunta hacia ABAJO. Al revés, todo el terreno se
## descarta por cara trasera desde cualquier cámara de arriba y ningún log lo
## dice: los soaks corren headless y no rasterizan nada. assert_winding hace
## que ese error falle un soak headless.
static func _grid_indices(cells: int) -> PackedInt32Array:
	var verts := cells + 1
	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var cursor := 0
	for iz in cells:
		for ix in cells:
			var top_left := iz * verts + ix
			var top_right := top_left + 1
			var bottom_left := top_left + verts
			var bottom_right := bottom_left + 1
			indices[cursor] = top_left
			indices[cursor + 1] = top_right
			indices[cursor + 2] = bottom_left
			indices[cursor + 3] = top_right
			indices[cursor + 4] = bottom_right
			indices[cursor + 5] = bottom_left
			cursor += 6
	return indices
