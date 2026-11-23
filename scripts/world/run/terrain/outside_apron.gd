class_name OutsideApron
extends RefCounted
## La franja de suelo que sigue AFUERA del muro, agregada a la malla del
## Terrain (la de ReliefMesh) como más cuadrícula: el mismo material, la misma
## malla. Por eso arde con el frente del infierno de Mythos (HellDressing
## quema la malla del Terrain), lleva los reflejos de la marea de la langosta
## (LobsterTide copia esa misma malla) y no deja costura: su primera fila son
## los vértices del borde de la arena.
##
## Las alturas son las de OutsideRelief. Sin colisión: el colisionador del
## Terrain sigue siendo el cuadrado de la arena y los muros del Perimeter son
## lo único que frena.

## Agrega la franja a `arrays`, los arreglos de ReliefMesh.arrays: una
## cuadrícula de `verts` × `verts` vértices cada `step` metros que empieza en
## (-half, -half), seguida de sus vértices extra. Devuelve los triángulos que agregó.
static func append(arrays: Array, verts: int, step: float, half: float,
		outside: OutsideRelief) -> int:
	var ring := ceili(outside.reach / step)
	if ring <= 0:
		return 0
	var side := verts + ring * 2
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Índice de cada vértice de la cuadrícula grande: los de adentro son los
	# de la arena (solo se usan los del borde), los de afuera son nuevos.
	var table := PackedInt32Array()
	table.resize(side * side)
	var first := vertices.size()
	var added := 0
	for gz in side:
		for gx in side:
			var cx := gx - ring
			var cz := gz - ring
			if cx >= 0 and cz >= 0 and cx < verts and cz < verts:
				table[gz * side + gx] = cz * verts + cx
			else:
				table[gz * side + gx] = first + added
				added += 1
	vertices.resize(first + added)
	normals.resize(first + added)
	uvs.resize(first + added)
	# Primero todas las alturas (las de adentro, de la malla de la arena): la
	# normal de cada vértice nuevo sale de sus vecinos en esta tabla.
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for gz in side:
		for gx in side:
			var index := table[gz * side + gx]
			if index < first:
				heights[gz * side + gx] = vertices[index].y
			else:
				heights[gz * side + gx] = outside.height_at(-half + float(gx - ring) * step,
						-half + float(gz - ring) * step)
	for gz in side:
		for gx in side:
			var index := table[gz * side + gx]
			if index < first:
				continue
			var x := -half + float(gx - ring) * step
			var z := -half + float(gz - ring) * step
			vertices[index] = Vector3(x, heights[gz * side + gx], z)
			normals[index] = _normal(heights, side, gx, gz, step)
			uvs[index] = Vector2(x, z)
	var faces := 0
	for gz in side - 1:
		for gx in side - 1:
			var cx := gx - ring
			var cz := gz - ring
			# Los cuadrados de la arena ya están en la malla.
			if cx >= 0 and cz >= 0 and cx < verts - 1 and cz < verts - 1:
				continue
			var top_left := table[gz * side + gx]
			var top_right := table[gz * side + gx + 1]
			var bottom_left := table[(gz + 1) * side + gx]
			var bottom_right := table[(gz + 1) * side + gx + 1]
			# Horarios vistos desde +Y, como ReliefMesh._quad.
			indices.append_array(PackedInt32Array([top_left, top_right, bottom_left,
					top_right, bottom_right, bottom_left]))
			faces += 2
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return faces


## Normal del vértice (gx, gz) de la tabla de alturas `heights` (lado
## `side`, un vértice cada `step` metros), por diferencias a sus vecinos.
static func _normal(heights: PackedFloat32Array, side: int, gx: int, gz: int,
		step: float) -> Vector3:
	var x0 := maxi(gx - 1, 0)
	var x1 := mini(gx + 1, side - 1)
	var z0 := maxi(gz - 1, 0)
	var z1 := mini(gz + 1, side - 1)
	var dx := (heights[gz * side + x1] - heights[gz * side + x0]) / (float(x1 - x0) * step)
	var dz := (heights[z1 * side + gx] - heights[z0 * side + gx]) / (float(z1 - z0) * step)
	return Vector3(-dx, 1.0, -dz).normalized()
