class_name ReliefMesh
extends RefCounted
## Malla del suelo de un Terrain con relieve por zonas: la cuadrícula de 2 m
## de siempre, más parches a 1 m en los bloques que tocan un corte.
##
## Por qué los parches: el colisionador lleva un escalón duro escondido bajo
## la cornisa de roca de cada corte. Dibujado a 2 m, ese escalón se abriría
## en una cuña de pasto de hasta 3 m a cada lado y asomaría fuera de la
## roca; a 1 m ocupa lo mismo que en el colisionador y queda tapado.
##
## Sin grietas: donde un bloque fino toca uno grueso, el vértice del medio de
## la arista compartida toma la altura que le da la arista gruesa (el
## promedio de sus dos esquinas).

## Edita aquí (no hay Inspector).
##
## Metros de desnivel por metro que ya son un corte y no una pendiente: las
## normales los ignoran y miran el suelo base, o el borde de cada corte
## quedaría sombreado como una rampa.
const STEP_LIMIT: float = 1.2


## Los arreglos de la malla (vértices, normales, UVs en XZ de mundo e
## índices) para las rejillas de `field`. Triángulos en el mismo sentido que
## la malla clásica del Terrain: horarios vistos desde +Y.
static func arrays(field: ReliefField, samples: int, size: float) -> Array:
	var block := ReliefField.BLOCK
	var blocks := (samples - 1) / block
	var verts := blocks + 1
	var half := size * 0.5
	var fine_count := field.fine.count(1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var total := verts * verts + fine_count * 5
	vertices.resize(total)
	normals.resize(total)
	uvs.resize(total)
	for cz in verts:
		var iz := cz * block
		for cx in verts:
			var ix := cx * block
			var index := cz * verts + cx
			var x := float(ix) - half
			var z := float(iz) - half
			vertices[index] = Vector3(x, field.heights[iz * samples + ix], z)
			normals[index] = _normal(field, samples, ix, iz, block)
			uvs[index] = Vector2(x, z)
	var indices := PackedInt32Array()
	indices.resize((blocks * blocks - fine_count) * 6 + fine_count * 24)
	var cursor := 0
	var extra := verts * verts
	for bz in blocks:
		for bx in blocks:
			var top_left := bz * verts + bx
			var top_right := top_left + 1
			var bottom_left := top_left + verts
			var bottom_right := bottom_left + 1
			if field.fine[bz * blocks + bx] == 0:
				cursor = _quad(indices, cursor, top_left, top_right, bottom_left, bottom_right)
				continue
			# Cinco vértices propios: medio de arriba, de la izquierda, centro,
			# de la derecha y de abajo.
			var ix := bx * block
			var iz := bz * block
			var top := extra
			var left := extra + 1
			var center := extra + 2
			var right := extra + 3
			var bottom := extra + 4
			extra += 5
			var tl := vertices[top_left].y
			var tr := vertices[top_right].y
			var bl := vertices[bottom_left].y
			var br := vertices[bottom_right].y
			_place(vertices, normals, uvs, field, samples, half, top, ix + 1, iz,
					_coarse(field, blocks, bx, bz - 1), (tl + tr) * 0.5)
			_place(vertices, normals, uvs, field, samples, half, left, ix, iz + 1,
					_coarse(field, blocks, bx - 1, bz), (tl + bl) * 0.5)
			_place(vertices, normals, uvs, field, samples, half, center, ix + 1, iz + 1,
					false, 0.0)
			_place(vertices, normals, uvs, field, samples, half, right, ix + 2, iz + 1,
					_coarse(field, blocks, bx + 1, bz), (tr + br) * 0.5)
			_place(vertices, normals, uvs, field, samples, half, bottom, ix + 1, iz + 2,
					_coarse(field, blocks, bx, bz + 1), (bl + br) * 0.5)
			cursor = _quad(indices, cursor, top_left, top, left, center)
			cursor = _quad(indices, cursor, top, top_right, center, right)
			cursor = _quad(indices, cursor, left, center, bottom_left, bottom)
			cursor = _quad(indices, cursor, center, right, bottom, bottom_right)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = indices
	return out


## Dos triángulos de un cuadrado, horarios vistos desde +Y. Devuelve el
## cursor ya avanzado.
static func _quad(indices: PackedInt32Array, cursor: int, top_left: int, top_right: int,
		bottom_left: int, bottom_right: int) -> int:
	indices[cursor] = top_left
	indices[cursor + 1] = top_right
	indices[cursor + 2] = bottom_left
	indices[cursor + 3] = top_right
	indices[cursor + 4] = bottom_right
	indices[cursor + 5] = bottom_left
	return cursor + 6


## True si el bloque (bx, bz) existe y va a 2 m: quien lo toca tiene que
## ceñirse a su arista recta.
static func _coarse(field: ReliefField, blocks: int, bx: int, bz: int) -> bool:
	if bx < 0 or bz < 0 or bx >= blocks or bz >= blocks:
		return false
	return field.fine[bz * blocks + bx] == 0


## Escribe el vértice extra `index` en la muestra (ix, iz): a la altura del
## colisionador, o a `edge_height` si `on_coarse_edge` (ver la cabecera).
static func _place(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, field: ReliefField, samples: int, half: float, index: int,
		ix: int, iz: int, on_coarse_edge: bool, edge_height: float) -> void:
	var x := float(ix) - half
	var z := float(iz) - half
	var height := edge_height if on_coarse_edge else field.heights[iz * samples + ix]
	vertices[index] = Vector3(x, height, z)
	normals[index] = _normal(field, samples, ix, iz, 1)
	uvs[index] = Vector2(x, z)


## Normal del suelo en la muestra (ix, iz), por diferencias a `reach`
## muestras de cada lado. Mira la superficie que se pisa; donde esa
## diferencia cruza un corte, mira el suelo base.
static func _normal(field: ReliefField, samples: int, ix: int, iz: int, reach: int) -> Vector3:
	var x0 := maxi(ix - reach, 0)
	var x1 := mini(ix + reach, samples - 1)
	var z0 := maxi(iz - reach, 0)
	var z1 := mini(iz + reach, samples - 1)
	var row := iz * samples
	var span_x := float(x1 - x0)
	var span_z := float(z1 - z0)
	var dx := field.surface[row + x1] - field.surface[row + x0]
	if absf(dx) > STEP_LIMIT * span_x:
		dx = field.base[row + x1] - field.base[row + x0]
	var dz := field.surface[z1 * samples + ix] - field.surface[z0 * samples + ix]
	if absf(dz) > STEP_LIMIT * span_z:
		dz = field.base[z1 * samples + ix] - field.base[z0 * samples + ix]
	return Vector3(-dx / span_x, 1.0, -dz / span_z).normalized()
