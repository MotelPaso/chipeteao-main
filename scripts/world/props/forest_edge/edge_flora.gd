extends RefCounted
## La FRANJA del bosque de afuera (ver ForestEdge): árboles, rocas, matas y
## troncos caídos sobre el pasto que sigue pasado el muro, cada vez más
## tupidos y altos hacia afuera. Los árboles y las rocas son los MISMOS
## modelos del reparto de adentro (los del kit de supervivencia, con su
## textura): el bosque de afuera es el mismo bosque, y arde igual. Cada trozo
## es una malla hija del ForestEdge: una superficie por material de modelo y
## otra de color de vértice para matas, helechos y troncos. Ninguna pieza
## asoma adentro de la arena: cada una guarda su propio radio más
## ForestEdge.wall_gap con el muro (no tienen colisión, así que lo que
## asomara se atravesaría). Los valores son exports de ForestEdge (grupos
## «Franja»); ninguna escena usa este script.

## Lados de la franja, en orden: norte, este, sur y oeste (norte = -Z), con su
## dirección hacia afuera; después vienen las cuatro esquinas.
const SIDES: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const CORNERS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
## Tipo de trozo para su semilla (ver ForestEdge.chunk_seed).
const SEED_KIND: int = 1
## Radios que llega un arbusto desde su pie: el segundo bulto va corrido 0.7
## y LowPolyMesh.blob ondula cada bulto un 20 %.
const BUSH_REACH: float = 1.5
## Puntos a lo largo de un tronco caído en que se mide su distancia al muro.
const LOG_SAMPLES: int = 5


## Un modelo listo para copiar en un trozo: sus triángulos sueltos (sin
## índices), su material y su radio en planta a escala 1 (lo más lejos del eje
## vertical que llega un vértice).
class Kit extends RefCounted:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var material: Material = null
	var radius: float = 0.0


## Los trozos de la franja: los tramos de cada lado y las cuatro esquinas.
static func jobs(edge: ForestEdge) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := ceili(edge.outside().half * 2.0 / edge.near_chunk)
	for side in SIDES.size():
		for index in count:
			out.append({"kind": "near", "side": side, "index": index})
	for corner in CORNERS.size():
		out.append({"kind": "near", "side": SIDES.size() + corner, "index": 0})
	return out


## El kit de la primera malla de `scene` (un modelo glb), o null.
static func kit(scene: PackedScene) -> Kit:
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	var views := root.find_children("*", "MeshInstance3D", true, false) if root != null else []
	if views.is_empty():
		if root != null:
			root.free()
		return null
	var view := views[0] as MeshInstance3D
	var arrays := view.mesh.surface_get_arrays(0)
	var out := Kit.new()
	out.material = view.mesh.surface_get_material(0)
	var place := view.transform
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
			else PackedInt32Array(range(vertices.size()))
	var turn := place.basis.inverse().transposed()
	for index: int in order:
		var at := place * vertices[index]
		out.positions.append(at)
		out.normals.append(turn * normals[index])
		out.uvs.append(uvs[index])
		out.radius = maxf(out.radius, Vector2(at.x, at.z).length())
	root.free()
	return out


## Arma el trozo `job` como hijo de `edge`.
static func build(edge: ForestEdge, job: Dictionary) -> void:
	var side := int(job["side"])
	var index := int(job["index"])
	var rng := RandomNumberGenerator.new()
	rng.seed = edge.chunk_seed(SEED_KIND, side, index)
	var paint := LowPolyMesh.new(rng.randi())
	var models: Dictionary[Material, Array] = {}
	var trunks := _plant_trees(edge, rng, side, index, models)
	_place_rocks(edge, rng, side, index, models, trunks)
	_add_undergrowth(edge, rng, side, index, paint, trunks)
	var mesh := _commit(models, paint)
	if mesh.get_surface_count() == 0:
		return
	edge.tally("near", 1)
	var view := MeshInstance3D.new()
	view.name = "Edge_%d_%d" % [side, index]
	view.mesh = mesh
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.add_child(view)
	for surface in mesh.get_surface_count():
		edge.tally("faces", (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				as PackedVector3Array).size() / 3)


## Los árboles del trozo, más tupidos y más altos hacia afuera; ninguna copa
## asoma adentro de la arena. Devuelve dónde quedaron los troncos.
static func _plant_trees(edge: ForestEdge, rng: RandomNumberGenerator, side: int, index: int,
		models: Dictionary[Material, Array]) -> PackedVector2Array:
	var outside := edge.outside()
	var trunks := PackedVector2Array()
	var trees := edge.tree_kits()
	if trees.is_empty():
		return trunks
	var most := maxf(edge.trees_at_wall, edge.trees_at_back)
	for attempt in ceili(_area(edge, side) / 100.0 * most * 1.4):
		var xz := _point(edge, rng, side, index)
		var d := outside.distance_out(xz.x, xz.y)
		if d < edge.near_from or d > outside.reach:
			continue
		var depth := d / outside.reach
		if rng.randf() * most > lerpf(edge.trees_at_wall, edge.trees_at_back, depth) \
				or not _apart(xz, trunks, edge.tree_spacing):
			continue
		var width := rng.randf_range(edge.tree_width_min, edge.tree_width_max)
		var tall := rng.randf_range(edge.tree_height_min, edge.tree_height_max) \
				* (1.0 + edge.back_height_boost * depth)
		var model := trees[rng.randi() % trees.size()] as Kit
		if d < model.radius * width * edge.tree_scale + edge.wall_gap:
			continue
		trunks.append(xz)
		_copy(models, model, _frame(outside, xz, rng.randf() * TAU,
				Vector3(width, tall, width) * edge.tree_scale))
	edge.tally("trees", trunks.size())
	return trunks


## Las rocas del trozo, lejos de los troncos y sin asomar adentro de la arena.
static func _place_rocks(edge: ForestEdge, rng: RandomNumberGenerator, side: int, index: int,
		models: Dictionary[Material, Array], trunks: PackedVector2Array) -> void:
	var rock := edge.rock_kit() as Kit
	if rock == null:
		return
	var outside := edge.outside()
	var rocks := 0
	for attempt in roundi(_area(edge, side) / 100.0 * edge.rocks_per_100):
		var xz := _point(edge, rng, side, index)
		var size := rng.randf_range(edge.rock_scale_min, edge.rock_scale_max)
		if outside.distance_out(xz.x, xz.y) < rock.radius * size + edge.wall_gap \
				or not _apart(xz, trunks, 2.0):
			continue
		_copy(models, rock, _frame(outside, xz, rng.randf() * TAU,
				Vector3(size, size * rng.randf_range(0.7, 1.2), size)))
		rocks += 1
	edge.tally("rocks", rocks)


## Las matas, los helechos y los troncos caídos del trozo.
static func _add_undergrowth(edge: ForestEdge, rng: RandomNumberGenerator, side: int,
		index: int, paint: LowPolyMesh, trunks: PackedVector2Array) -> void:
	var outside := edge.outside()
	for attempt in roundi(_area(edge, side) / 100.0 * edge.bushes_per_100):
		var xz := _point(edge, rng, side, index)
		_bush(edge, paint, rng, Vector3(xz.x, outside.height_at(xz.x, xz.y), xz.y),
				outside.distance_out(xz.x, xz.y) - edge.wall_gap)
	for attempt in edge.logs_per_chunk:
		var xz := _point(edge, rng, side, index)
		if outside.distance_out(xz.x, xz.y) > edge.near_from and _apart(xz, trunks, 3.0):
			_log(edge, paint, rng, outside, xz)


## La transformación de un modelo parado en `xz` sobre el suelo de afuera,
## girado `yaw` y escalado `scale` (ancho, alto, ancho).
static func _frame(outside: OutsideRelief, xz: Vector2, yaw: float, scale: Vector3) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	return Transform3D(basis, Vector3(xz.x, outside.height_at(xz.x, xz.y) - 0.15, xz.y))


## Copia `source` con la transformación `frame` en la pila de su material.
static func _copy(models: Dictionary[Material, Array], source: Kit, frame: Transform3D) -> void:
	if not models.has(source.material):
		models[source.material] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
	var pile: Array = models[source.material]
	var turn := Transform3D(frame.basis.inverse().transposed(), Vector3.ZERO)
	var positions: PackedVector3Array = pile[0]
	var normals: PackedVector3Array = pile[1]
	var uvs: PackedVector2Array = pile[2]
	positions.append_array(frame * source.positions)
	normals.append_array(turn * source.normals)
	uvs.append_array(source.uvs)
	pile[0] = positions
	pile[1] = normals
	pile[2] = uvs


## La malla del trozo: una superficie por material de modelo y la de color de vértice.
static func _commit(models: Dictionary[Material, Array], paint: LowPolyMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for material: Material in models:
		var pile: Array = models[material]
		if (pile[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pile[0]
		arrays[Mesh.ARRAY_NORMAL] = pile[1]
		arrays[Mesh.ARRAY_TEX_UV] = pile[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	if not paint.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, paint.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, LowPolyMesh.MATERIAL)
	return mesh


## Metros cuadrados de franja del trozo de `side` (un tramo de lado o una esquina).
static func _area(edge: ForestEdge, side: int) -> float:
	var reach := edge.outside().reach
	if side < SIDES.size():
		return edge.near_chunk * reach
	return reach * reach


## Un punto al azar del trozo `index` del lado (o esquina) `side`.
static func _point(edge: ForestEdge, rng: RandomNumberGenerator, side: int, index: int) -> Vector2:
	var outside := edge.outside()
	var half := outside.half
	if side >= SIDES.size():
		var corner := CORNERS[side - SIDES.size()]
		return Vector2(corner.x * (half + rng.randf() * outside.reach),
				corner.y * (half + rng.randf() * outside.reach))
	var out := SIDES[side]
	var along := Vector2(-out.y, out.x)
	var start := -half + float(index) * edge.near_chunk
	var run := rng.randf_range(start, minf(start + edge.near_chunk, half))
	return out * (half + rng.randf() * outside.reach) + along * run


## True si `xz` queda a `gap` metros o más de todo punto de `taken`.
static func _apart(xz: Vector2, taken: PackedVector2Array, gap: float) -> bool:
	for other: Vector2 in taken:
		if xz.distance_squared_to(other) < gap * gap:
			return false
	return true


## Un arbusto (dos bultos) o un helecho (hojas en abanico) con el pie en
## `foot`, si cabe entero en `room` metros alrededor del pie (lo que lo separa
## del muro); si no cabe, no se pone.
static func _bush(edge: ForestEdge, mesh: LowPolyMesh, rng: RandomNumberGenerator,
		foot: Vector3, room: float) -> void:
	var tone := edge.bush_color.lerp(edge.bush_bright, rng.randf())
	if rng.randf() < 0.55:
		var radius := rng.randf_range(0.5, 1.2)
		if radius * BUSH_REACH > room:
			return
		mesh.blob(foot + Vector3.UP * radius * 0.5, Vector3(radius, radius * 0.75, radius), tone,
				5, 3, 0.2)
		mesh.blob(foot + Vector3(radius * 0.7, radius * 0.3, 0.0),
				Vector3(radius, radius * 0.7, radius) * 0.65, tone.darkened(0.1), 5, 3, 0.2)
		return
	var fronds := rng.randi_range(5, 7)
	var turn := rng.randf() * TAU
	# Las hojas más largas miden 1.6 m: más cerca del muro, se acortan.
	if room < 0.9:
		return
	for frond in fronds:
		var angle := turn + TAU * float(frond) / float(fronds)
		var reach := minf(rng.randf_range(0.9, 1.6), room)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var bend := foot + out * reach * 0.5 + Vector3.UP * reach * 0.55
		var tip := foot + out * reach + Vector3.UP * reach * 0.2
		mesh.quad(foot + side * 0.06, foot - side * 0.06, bend - side * reach * 0.2,
				bend + side * reach * 0.2, tone, bend + Vector3.DOWN)
		mesh.triangle(bend + side * reach * 0.2, bend - side * reach * 0.2, tip, tone,
				bend + Vector3.DOWN)


## Un tronco caído: un prisma de cinco lados tendido sobre el suelo. No se
## pone si alguna parte suya quedaría a menos de su radio y wall_gap del muro.
static func _log(edge: ForestEdge, mesh: LowPolyMesh, rng: RandomNumberGenerator,
		outside: OutsideRelief, xz: Vector2) -> void:
	var along := Vector2.from_angle(rng.randf() * TAU)
	var length := rng.randf_range(4.0, 8.0)
	var radius := rng.randf_range(0.35, 0.6)
	for sample in LOG_SAMPLES:
		var point := xz + along * length * (float(sample) / float(LOG_SAMPLES - 1) - 0.5)
		if outside.distance_out(point.x, point.y) < radius + edge.wall_gap:
			return
	var ends: Array[PackedVector3Array] = []
	for point: Vector2 in [xz - along * length * 0.5, xz + along * length * 0.5]:
		var center := Vector3(point.x, outside.height_at(point.x, point.y) + radius * 0.6, point.y)
		var side := Vector3(-along.y, 0.0, along.x)
		var ring := PackedVector3Array()
		for corner in 5:
			var angle := TAU * float(corner) / 5.0
			ring.append(center + (side * cos(angle) + Vector3.UP * sin(angle)) * radius)
		ends.append(ring)
	var middle := (ends[0][0] + ends[1][0]) * 0.5
	mesh.band(ends[0], ends[1], edge.log_color)
	mesh.cap(ends[0], edge.log_color.lightened(0.25), middle)
	mesh.cap(ends[1], edge.log_color.lightened(0.25), middle)
